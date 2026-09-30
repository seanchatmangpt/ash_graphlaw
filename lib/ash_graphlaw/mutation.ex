# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Mutation do
  @moduledoc """
  Anti-vacuity mutation engine: development tooling, not part of the runtime API.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits a mutation court.

  A test that keeps passing after the guard it attacks is deleted is presumed vacuous. This
  module proves the opposite for the negative and adversarial tests by deleting the guard in
  the running VM and re-running them:

    1. read the target module's abstract code from its BEAM `debug_info` chunk
    2. apply the operator to one named function/arity (public or private):
       `{:replace_body, source}` replaces the body of every selected clause with the Erlang
       expression `source` (heads and guards are kept, each argument is aliased as
       `ChicagoArg1..N`); `{:negate_guard}` negates the guard of every guarded selected clause
    3. `:compile.forms/2` the mutant (with debug info) and hot-load it with `:code.load_binary/3`
    4. run the killer test files in this VM (`AshGraphLaw.Mutation.Runner`)
    5. **always** restore the original BEAM, then judge

  ## Restoration is exit-safe

  A guardian process (`spawn_monitor`, not linked) holds the engine lock and the original
  binary before the mutant is loaded. The owner asks it to restore after the stimulus returns,
  raises, throws or exits. If the owner is killed outright the guardian's monitor fires and it
  restores on its own. Restoration purges old code (soft, then hard) and verifies the loaded
  md5 equals the md5 of the on-disk BEAM again.

  ## Refusals (never skips)

  The engine refuses a target that is part of the mutation machinery itself (a mutant judge
  could lie), outside the `:ash_graphlaw` application, not compiled, sticky, without object code
  or debug info, already different from its on-disk BEAM, missing the named function, matched by
  no clause, or whose mutant does not compile. Only one mutation may be live in the node at a
  time (`:global` lock held by the guardian). A refused mutation is reported as a `:blocked`
  verdict carrying the refusal code; it is never dropped from the report.

  ## Verdicts (`qualify/2`)

    * `:mutant_killed` - the killer tests were green unmutated and failed under the mutant
    * `:mutant_survived` - the killer tests stayed green with the guard removed (vacuous)
    * `:blocked` - target or killer files unavailable
    * `:unknown` - baseline not green, a run unreadable, or restoration not verified

  ## Anti-vacuity

  A negative test asserts that a bad input is refused. If deleting the refusal guard leaves the
  test green, the test never exercised the guard. Each catalog entry (ids `AGL-MUT-001` to
  `AGL-MUT-014`, append-only) removes exactly one guard and requires at least one killer test to
  fail while the unmutated baseline is green. A survivor is a vacuous killer, never a pass, and
  `mix ash_graphlaw.mutate --require-killed` turns any survivor into a failed build.

  Nothing here grants authority. A verdict is an observation bound to the exact BEAM md5s
  recorded in `:applied` and `:restored`.
  """

  alias AshGraphLaw.Mutation.{Runner, Verdict}

  @enforce_keys [:id, :module, :function, :arity, :operator]
  defstruct [
    :id,
    :module,
    :function,
    :arity,
    :operator,
    :guard,
    :description,
    clauses: :all,
    killers: []
  ]

  @typedoc "Which clauses of the target function an operator applies to."
  @type selector :: :all | {:clause, pos_integer()}
  @typedoc "`{:replace_body, erlang_source}` or `{:negate_guard}`."
  @type operator :: {:replace_body, String.t()} | {:negate_guard}

  @typedoc "One mutation: exact target `Module.function/arity`, operator, killers."
  @type t :: %__MODULE__{
          id: String.t(),
          module: module(),
          function: atom(),
          arity: non_neg_integer(),
          operator: operator(),
          clauses: selector(),
          guard: String.t() | nil,
          description: String.t() | nil,
          killers: [String.t()]
        }

  @typedoc "Typed refusal: a code from `refusal_codes/0` and a human detail."
  @type refusal :: %{code: atom(), detail: String.t()}

  @typedoc "A prepared, not yet loaded, mutant with the md5 of both BEAMs."
  @type plan :: %{
          mutation_id: String.t(),
          module: module(),
          function: atom(),
          arity: non_neg_integer(),
          target: String.t(),
          filename: charlist(),
          original_binary: binary(),
          original_md5: String.t(),
          mutant_binary: binary(),
          mutant_md5: String.t(),
          clauses_mutated: pos_integer()
        }

  @arg_prefix "ChicagoArg"
  @lock_resource {__MODULE__, :engine}
  @compile_opts [:binary, :return_errors, :return_warnings, :no_auto_import, :debug_info]
  @subject_app :ash_graphlaw
  @protected_prefix "Elixir.AshGraphLaw.Mutation"
  @protected_extra [Mix.Tasks.AshGraphlaw.Mutate]

  @refusal_codes %{
    mutation_target_protected: :refused_authority,
    mutation_target_foreign: :refused_authority,
    mutation_target_not_compiled: :blocked_resource,
    mutation_object_code_unavailable: :blocked_resource,
    mutation_debug_info_unavailable: :blocked_resource,
    mutation_target_not_pristine: :refused_identity,
    mutation_old_code_in_use: :blocked_resource,
    mutation_function_not_found: :blocked_resource,
    mutation_clause_not_matched: :refused_structure,
    mutation_body_invalid: :refused_structure,
    mutation_operator_invalid: :refused_structure,
    mutation_compile_failed: :refused_structure,
    mutation_load_failed: :blocked_resource,
    mutation_in_progress: :blocked_resource,
    mutation_guardian_failed: :blocked_resource,
    mutation_killers_missing: :blocked_resource
  }

  @doc "Closed table of refusal codes this engine emits, with their class."
  @spec refusal_codes() :: %{atom() => atom()}
  def refusal_codes, do: @refusal_codes

  @doc "`\"Module.function/arity\"`."
  @spec target(t()) :: String.t()
  def target(%__MODULE__{module: module, function: function, arity: arity}),
    do: "#{inspect(module)}.#{function}/#{arity}"

  @doc "True when `module` belongs to the mutation machinery and may never be mutated."
  @spec protected?(module()) :: boolean()
  def protected?(module) when is_atom(module) do
    module in @protected_extra or String.starts_with?(Atom.to_string(module), @protected_prefix)
  end

  # --- preparation -----------------------------------------------------------

  @doc """
  Builds the mutant without loading it. Pure with respect to the running system.

  Options: `:applications` (default `[:ash_graphlaw]`), the application names a target may
  belong to; `:undefined` admits modules loaded without an application (test fixtures).
  """
  @spec prepare(t(), keyword()) :: {:ok, plan()} | {:error, refusal()}
  def prepare(%__MODULE__{} = m, opts \\ []) do
    with :ok <- check_shape(m),
         :ok <- check_protected(m.module),
         :ok <- check_loaded(m.module),
         :ok <- check_application(m.module, Keyword.get(opts, :applications, [@subject_app])),
         :ok <- check_sticky(m.module),
         {:ok, binary, filename} <- object_code(m.module),
         :ok <- check_pristine(m.module, binary),
         {:ok, forms} <- abstract_forms(m.module, binary),
         {:ok, mutated_forms, count} <- mutate_forms(forms, m),
         {:ok, mutant} <- compile(m.module, mutated_forms) do
      {:ok, build_plan(m, filename, binary, mutant, count)}
    end
  end

  defp build_plan(m, filename, binary, mutant, count) do
    %{
      mutation_id: m.id,
      module: m.module,
      function: m.function,
      arity: m.arity,
      target: target(m),
      filename: filename,
      original_binary: binary,
      original_md5: binary_md5(binary),
      mutant_binary: mutant,
      mutant_md5: binary_md5(mutant),
      clauses_mutated: count
    }
  end

  defp check_shape(%__MODULE__{id: id, module: mod, function: fun, arity: arity, killers: killers})
       when is_binary(id) and id != "" and is_atom(mod) and is_atom(fun) and is_integer(arity) and arity >= 0 and
              is_list(killers),
       do: :ok

  defp check_shape(m), do: refuse(:mutation_operator_invalid, "malformed mutation #{inspect(m)}")

  defp check_protected(module) do
    if protected?(module),
      do: refuse(:mutation_target_protected, "#{inspect(module)} is mutation machinery; a mutant judge could lie"),
      else: :ok
  end

  defp check_loaded(module) do
    if Code.ensure_loaded?(module),
      do: :ok,
      else: refuse(:mutation_target_not_compiled, "#{inspect(module)} is not compiled in this subject")
  end

  defp check_application(module, allowed) do
    case :application.get_application(module) do
      {:ok, app} -> allow_application(module, app, allowed)
      :undefined -> allow_application(module, :undefined, allowed)
    end
  end

  defp allow_application(module, app, allowed) do
    if app in allowed,
      do: :ok,
      else: refuse(:mutation_target_foreign, "#{inspect(module)} belongs to #{inspect(app)}, not #{inspect(allowed)}")
  end

  defp check_sticky(module) do
    if :code.is_sticky(module),
      do: refuse(:mutation_target_protected, "#{inspect(module)} is a sticky runtime module"),
      else: :ok
  end

  defp object_code(module) do
    case :code.get_object_code(module) do
      {^module, binary, filename} -> {:ok, binary, filename}
      :error -> refuse(:mutation_object_code_unavailable, "no BEAM on the code path for #{inspect(module)}")
    end
  end

  defp check_pristine(module, binary) do
    cond do
      not loaded_matches_disk?(module, binary) ->
        refuse(
          :mutation_target_not_pristine,
          "loaded #{inspect(module)} differs from its on-disk BEAM (already mutated or stale)"
        )

      :erlang.check_old_code(module) and not soft_purge(module, 10) ->
        refuse(:mutation_old_code_in_use, "old code of #{inspect(module)} is still executing")

      true ->
        :ok
    end
  end

  defp abstract_forms(module, binary) do
    case :beam_lib.chunks(binary, [:debug_info]) do
      {:ok, {^module, [debug_info: {:debug_info_v1, backend, data}]}} -> backend_forms(backend, module, data)
      other -> refuse(:mutation_debug_info_unavailable, inspect(other, limit: 5))
    end
  rescue
    exception -> refuse(:mutation_debug_info_unavailable, Exception.message(exception))
  end

  defp backend_forms(backend, module, data) do
    case backend.debug_info(:erlang_v1, module, data, []) do
      {:ok, forms} -> {:ok, forms}
      {:error, reason} -> refuse(:mutation_debug_info_unavailable, inspect(reason))
    end
  end

  @doc false
  @spec mutate_forms([tuple()], t()) :: {:ok, [tuple()], pos_integer()} | {:error, refusal()}
  def mutate_forms(forms, %__MODULE__{function: fun, arity: arity} = m) do
    index =
      Enum.find_index(forms, fn
        {:function, _anno, ^fun, ^arity, _clauses} -> true
        _other -> false
      end)

    case index do
      nil ->
        refuse(:mutation_function_not_found, "#{target(m)} is not defined")

      i ->
        {:function, anno, ^fun, ^arity, clauses} = Enum.at(forms, i)

        with {:ok, new_clauses, count} <- apply_operator(m, anno, clauses) do
          {:ok, List.replace_at(forms, i, {:function, anno, fun, arity, new_clauses}), count}
        end
    end
  end

  defp apply_operator(%__MODULE__{operator: {:replace_body, source}} = m, anno, clauses) when is_binary(source) do
    with {:ok, body} <- parse_body(source, anno) do
      clauses
      |> Enum.with_index(1)
      |> Enum.map_reduce(0, fn {clause, i}, n -> replace_body(clause, selected?(i, m.clauses), body, n) end)
      |> counted(m)
    end
  end

  defp apply_operator(%__MODULE__{operator: {:negate_guard}} = m, _anno, clauses) do
    clauses
    |> Enum.with_index(1)
    |> Enum.map_reduce(0, fn {clause, i}, n -> negate_clause(clause, selected?(i, m.clauses), n) end)
    |> counted(m)
  end

  defp apply_operator(%__MODULE__{} = m, _anno, _clauses),
    do: refuse(:mutation_operator_invalid, "unsupported operator/selector #{inspect({m.operator, m.clauses})}")

  defp replace_body({:clause, a, heads, guards, _old_body}, true, body, n),
    do: {{:clause, a, alias_heads(heads, a), guards, body}, n + 1}

  defp replace_body(clause, false, _body, n), do: {clause, n}

  defp counted({_clauses, 0}, m),
    do: refuse(:mutation_clause_not_matched, "#{inspect(m.clauses)} matched no mutable clause of #{target(m)}")

  defp counted({clauses, count}, _m), do: {:ok, clauses, count}

  defp selected?(_index, :all), do: true
  defp selected?(index, {:clause, n}), do: index == n
  defp selected?(_index, _selector), do: false

  defp negate_clause({:clause, anno, heads, [_ | _] = guards, body}, true, n),
    do: {{:clause, anno, heads, [[{:op, anno, :not, guard_expression(guards, anno)}]], body}, n + 1}

  defp negate_clause(clause, _selected, n), do: {clause, n}

  # A guard sequence is an OR of ANDs of guard tests.
  defp guard_expression(groups, anno) do
    groups |> Enum.map(&fold_guard(&1, :andalso, anno)) |> fold_guard(:orelse, anno)
  end

  defp fold_guard([test], _op, _anno), do: test
  defp fold_guard([test | rest], op, anno), do: {:op, anno, op, test, fold_guard(rest, op, anno)}

  defp alias_heads(heads, anno) do
    heads
    |> Enum.with_index(1)
    |> Enum.map(fn {pattern, i} -> {:match, anno, {:var, anno, arg_var(i)}, pattern} end)
  end

  defp arg_var(i), do: String.to_atom(@arg_prefix <> Integer.to_string(i))

  defp parse_body(source, anno) do
    with {:ok, tokens, _end} <- :erl_scan.string(String.to_charlist(source), :erl_anno.line(anno)),
         {:ok, [_ | _] = exprs} <- :erl_parse.parse_exprs(tokens) do
      {:ok, exprs}
    else
      {:error, info, _location} -> refuse(:mutation_body_invalid, inspect(info))
      {:error, info} -> refuse(:mutation_body_invalid, inspect(info))
      other -> refuse(:mutation_body_invalid, inspect(other))
    end
  end

  defp compile(module, forms) do
    case :compile.forms(forms, @compile_opts) do
      {:ok, ^module, binary, _warnings} -> {:ok, binary}
      {:ok, ^module, binary} -> {:ok, binary}
      {:error, errors, _warnings} -> refuse(:mutation_compile_failed, inspect(errors, limit: 20))
      other -> refuse(:mutation_compile_failed, inspect(other, limit: 20))
    end
  rescue
    exception -> refuse(:mutation_compile_failed, Exception.message(exception))
  end

  # --- live mutation ------------------------------------------------------------

  @doc """
  Loads the mutant, runs `fun.(applied)` and always restores the original.

  Returns `{:ok, value, %{applied: map, restored: map}}`; a raise, throw or exit from `fun` is
  re-raised after restoration. Accepts the `prepare/2` options.
  """
  @spec with_mutant(t(), (map() -> result), keyword()) ::
          {:ok, result, %{applied: map(), restored: map()}} | {:error, refusal()}
        when result: var
  def with_mutant(%__MODULE__{} = m, fun, opts \\ []) when is_function(fun, 1) do
    case prepare(m, opts) do
      {:ok, plan} -> arm_and_run(plan, fun)
      {:error, _refusal} = error -> error
    end
  end

  defp arm_and_run(plan, fun) do
    owner = self()
    ref = make_ref()
    {guardian, gmon} = spawn_monitor(fn -> guardian_init(owner, ref, plan) end)

    receive do
      {^ref, :armed} ->
        load_and_run(plan, fun, guardian, gmon, ref)

      {^ref, {:refused, refusal}} ->
        Process.demonitor(gmon, [:flush])
        {:error, refusal}

      {:DOWN, ^gmon, :process, _pid, reason} ->
        {:error, %{code: :mutation_guardian_failed, detail: inspect(reason)}}
    after
      30_000 ->
        Process.demonitor(gmon, [:flush])
        Process.exit(guardian, :kill)
        {:error, %{code: :mutation_guardian_failed, detail: "guardian did not arm within 30s"}}
    end
  end

  defp load_and_run(plan, fun, guardian, gmon, ref) do
    case :code.load_binary(plan.module, plan.filename, plan.mutant_binary) do
      {:module, _module} ->
        applied = applied_info(plan)
        outcome = run_stimulus(fun, applied)
        restored = request_restore(plan, guardian, gmon, ref)
        finish(outcome, applied, restored)

      {:error, reason} ->
        disarm(guardian, gmon, ref)
        {:error, %{code: :mutation_load_failed, detail: inspect(reason)}}
    end
  end

  defp applied_info(plan) do
    %{
      mutation_id: plan.mutation_id,
      target: plan.target,
      module: inspect(plan.module),
      clauses_mutated: plan.clauses_mutated,
      original_md5: plan.original_md5,
      mutant_md5: plan.mutant_md5,
      loaded_md5: loaded_md5(plan.module),
      call_count_enabled: enable_call_count(plan)
    }
  end

  defp run_stimulus(fun, applied) do
    {:returned, fun.(applied)}
  catch
    kind, reason -> {:raised, kind, reason, __STACKTRACE__}
  end

  defp finish({:returned, value}, applied, restored), do: {:ok, value, %{applied: applied, restored: restored}}
  defp finish({:raised, kind, reason, stack}, _applied, _restored), do: :erlang.raise(kind, reason, stack)

  defp disarm(guardian, gmon, ref) do
    send(guardian, {ref, :disarm, self()})

    receive do
      {^ref, :disarmed} -> :ok
      {:DOWN, ^gmon, :process, _pid, _reason} -> :ok
    after
      5_000 -> :ok
    end

    Process.demonitor(gmon, [:flush])
  end

  defp request_restore(plan, guardian, gmon, ref) do
    send(guardian, {ref, :restore, self()})

    receive do
      {^ref, :restored, info} ->
        Process.demonitor(gmon, [:flush])
        info

      {:DOWN, ^gmon, :process, _pid, reason} ->
        restore(plan, {:guardian_down, reason})
    end
  end

  defp guardian_init(owner, ref, plan) do
    owner_mon = Process.monitor(owner)
    lock = {@lock_resource, self()}

    if :global.set_lock(lock, [node()], 0) do
      case check_pristine(plan.module, plan.original_binary) do
        :ok ->
          send(owner, {ref, :armed})
          guardian_loop(owner, owner_mon, ref, plan, lock)

        {:error, refusal} ->
          :global.del_lock(lock, [node()])
          send(owner, {ref, {:refused, refusal}})
      end
    else
      send(owner, {ref, {:refused, %{code: :mutation_in_progress, detail: "another mutation holds the engine lock"}}})
    end
  end

  defp guardian_loop(owner, owner_mon, ref, plan, lock) do
    receive do
      {^ref, :restore, from} ->
        info = restore(plan, :owner)
        :global.del_lock(lock, [node()])
        send(from, {ref, :restored, info})

      {^ref, :disarm, from} ->
        :global.del_lock(lock, [node()])
        send(from, {ref, :disarmed})

      {:DOWN, ^owner_mon, :process, ^owner, reason} ->
        _ = restore(plan, {:owner_down, reason})
        :global.del_lock(lock, [node()])
    end
  end

  defp restore(plan, trigger) do
    module = plan.module
    calls = take_call_count(plan)

    {action, purge} =
      if loaded_md5(module) == plan.original_md5 do
        {:already_original, purge_old(module)}
      else
        first = purge_old(module)
        loaded = load_original(plan)
        second = purge_old(module)
        {loaded, strongest(first, second)}
      end

    restored_md5 = loaded_md5(module)

    %{
      mutation_id: plan.mutation_id,
      target: plan.target,
      module: inspect(module),
      pristine: restored_md5 == plan.original_md5 and not :erlang.check_old_code(module),
      restored_md5: restored_md5,
      original_md5: plan.original_md5,
      action: action,
      purge: purge,
      mutant_calls: calls,
      trigger: trigger_name(trigger)
    }
  end

  defp load_original(plan) do
    case :code.load_binary(plan.module, plan.filename, plan.original_binary) do
      {:module, _module} ->
        :reloaded

      {:error, _reason} ->
        _ = :code.purge(plan.module)

        case :code.load_binary(plan.module, plan.filename, plan.original_binary) do
          {:module, _module} -> :reloaded_after_hard_purge
          {:error, reason} -> {:reload_failed, reason}
        end
    end
  end

  defp purge_old(module) do
    cond do
      not :erlang.check_old_code(module) -> :none
      soft_purge(module, 40) -> :soft
      true -> if(:code.purge(module), do: :hard_killed, else: :hard)
    end
  end

  defp soft_purge(module, 0), do: :code.soft_purge(module)

  defp soft_purge(module, retries) do
    if :code.soft_purge(module) do
      true
    else
      Process.sleep(25)
      soft_purge(module, retries - 1)
    end
  end

  defp strongest(a, b) do
    rank = %{none: 0, soft: 1, hard: 2, hard_killed: 3}
    if Map.fetch!(rank, a) >= Map.fetch!(rank, b), do: a, else: b
  end

  defp trigger_name({name, _reason}), do: name
  defp trigger_name(name) when is_atom(name), do: name

  defp enable_call_count(plan) do
    :erlang.trace_pattern({plan.module, plan.function, plan.arity}, true, [:call_count]) > 0
  rescue
    _exception -> false
  end

  defp take_call_count(plan) do
    mfa = {plan.module, plan.function, plan.arity}

    count =
      case :erlang.trace_info(mfa, :call_count) do
        {:call_count, n} when is_integer(n) -> n
        _other -> nil
      end

    _ = :erlang.trace_pattern(mfa, false, [:call_count])
    count
  rescue
    _exception -> nil
  end

  @doc "True when the loaded `module` is exactly its on-disk BEAM with no old code."
  @spec pristine?(module()) :: boolean()
  def pristine?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      case :code.get_object_code(module) do
        {^module, binary, _filename} -> loaded_matches_disk?(module, binary) and not :erlang.check_old_code(module)
        :error -> false
      end
  end

  @doc """
  Forces `module` back to its on-disk BEAM (operator safety net). Returns `pristine?/1` afterwards.
  """
  @spec restore!(module()) :: boolean()
  def restore!(module) when is_atom(module) do
    if pristine?(module) do
      true
    else
      case :code.get_object_code(module) do
        {^module, binary, filename} ->
          _ = purge_old(module)
          _ = load_original(%{module: module, filename: filename, original_binary: binary})
          _ = purge_old(module)
          pristine?(module)

        :error ->
          false
      end
    end
  end

  # --- killers and qualification ---------------------------------------------------

  @doc """
  Expands the mutation's killer paths/globs relative to `root` (default: the current directory).

  Returns `{:ok, files, missing}` where `missing` are the killer entries that matched no file,
  or a `:mutation_killers_missing` refusal when nothing matched at all.
  """
  @spec resolve_killers(t(), Path.t()) :: {:ok, [Path.t()], [String.t()]} | {:error, refusal()}
  def resolve_killers(%__MODULE__{killers: killers}, root \\ File.cwd!()) do
    expanded = Enum.map(killers, fn killer -> {killer, root |> Path.join(killer) |> Path.wildcard() |> Enum.sort()} end)
    files = expanded |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq()
    missing = for {killer, []} <- expanded, do: killer

    case files do
      [] ->
        {:error, %{code: :mutation_killers_missing, detail: "no killer test file for #{Enum.join(killers, ", ")}"}}

      _ ->
        {:ok, files, missing}
    end
  end

  @doc """
  Runs `files` unmutated and returns the summary the mutants are judged against.

  Options: `:runner` (`(files, opts -> {:ok, summary} | {:error, term})`, default
  `AshGraphLaw.Mutation.Runner.run/2`); other options are passed to the runner.
  """
  @spec baseline([Path.t()], keyword()) :: {:ok, Runner.summary()} | {:error, term()}
  def baseline(files, opts \\ []), do: run_killers(files, opts)

  @doc """
  Qualifies one mutation: resolve killers, preflight the target, run (or reuse, `opts[:baseline]`)
  the unmutated baseline, run the killers under the live mutant, restore, and judge.

  Options: `:root`, `:runner`, `:baseline`, `:applications`, plus runner options.
  """
  @spec qualify(t(), keyword()) :: Verdict.t()
  def qualify(%__MODULE__{} = m, opts \\ []) do
    with {:ok, _plan} <- prepare(m, opts),
         {:ok, files, missing} <- resolve_killers(m, Keyword.get(opts, :root, File.cwd!())) do
      baseline = Keyword.get_lazy(opts, :baseline, fn -> baseline(files, opts) end)
      qualify_against(m, files, missing, baseline, opts)
    else
      {:error, refusal} -> blocked(m, refusal)
    end
  end

  defp qualify_against(m, files, missing, {:ok, %{failures: 0, total: total}} = baseline, opts) when total > 0 do
    case with_mutant(m, fn _applied -> run_killers(files, opts) end, opts) do
      {:ok, mutant, %{applied: applied, restored: restored}} ->
        judge(m, files, missing, baseline, mutant, applied, restored)

      {:error, refusal} ->
        blocked(m, refusal)
    end
  end

  defp qualify_against(m, files, missing, baseline, _opts) do
    %Verdict{
      mutation_id: m.id,
      target: target(m),
      verdict: :unknown,
      detail: "baseline not green: " <> describe(baseline),
      killers: m.killers,
      killer_files: files,
      missing_killers: missing,
      baseline: summary(baseline)
    }
  end

  defp run_killers(files, opts) do
    runner = Keyword.get(opts, :runner, &Runner.run/2)
    runner.(files, Keyword.drop(opts, [:runner, :baseline, :root, :applications]))
  rescue
    exception -> {:error, {:runner_raised, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:runner_exited, kind, inspect(reason, limit: 5)}}
  end

  defp judge(m, files, missing, baseline, mutant, applied, restored) do
    {verdict, detail, killed_by} = decide(m, mutant, restored)

    %Verdict{
      mutation_id: m.id,
      target: target(m),
      verdict: verdict,
      detail: detail,
      killers: m.killers,
      killer_files: files,
      missing_killers: missing,
      killed_by: killed_by,
      mutant_calls: restored.mutant_calls,
      applied: applied,
      restored: restored,
      baseline: summary(baseline),
      mutant: summary(mutant)
    }
  end

  defp decide(m, mutant, restored) do
    case {restored.pristine, mutant} do
      {false, _} ->
        {:unknown, "original BEAM of #{target(m)} not verifiably restored; no verdict", []}

      {true, {:ok, %{failures: failures, failed: failed}}} when failures > 0 ->
        {:mutant_killed, "killed by #{length(failed)} failing test(s)", failed}

      {true, {:ok, %{total: total}}} when total > 0 ->
        {:mutant_survived,
         "killer tests stayed green with #{m.guard || target(m)} removed" <> call_note(restored.mutant_calls), []}

      {true, other} ->
        {:unknown, "mutant run not judgeable: " <> describe(other), []}
    end
  end

  defp call_note(0), do: " (the mutated function never ran)"
  defp call_note(_calls), do: ""

  defp describe({:ok, %{total: total, failures: failures}}), do: "#{total} test(s), #{failures} failure(s)"
  defp describe({:error, reason}), do: inspect(reason, limit: 10)
  defp describe(other), do: inspect(other, limit: 10)

  defp summary({:ok, %{} = s}), do: Map.take(s, [:total, :failures, :skipped, :excluded, :failed])
  defp summary({:error, reason}), do: %{error: inspect(reason, limit: 10)}
  defp summary(other), do: %{error: inspect(other, limit: 10)}

  defp blocked(m, %{code: code, detail: detail}) do
    %Verdict{
      mutation_id: m.id,
      target: target(m),
      verdict: :blocked,
      code: code,
      detail: detail,
      killers: m.killers
    }
  end

  # --- helpers -----------------------------------------------------------------

  defp refuse(code, detail), do: {:error, %{code: code, detail: detail}}

  # Under `mix test --cover` the loaded module is `:cover`'s instrumented re-compilation of the
  # same abstract code, so its md5 differs by construction. That is coverage, not mutation. A
  # mutant this engine loads is never cover-compiled (`:code.which/1` then names a file).
  defp loaded_matches_disk?(module, binary),
    do: binary_md5(binary) == loaded_md5(module) or :code.which(module) == :cover_compiled

  defp loaded_md5(module), do: module.module_info(:md5) |> Base.encode16(case: :lower)

  defp binary_md5(binary) do
    {:ok, {_module, md5}} = :beam_lib.md5(binary)
    Base.encode16(md5, case: :lower)
  end
end
