# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Parity do
  # UNSUPPORTED(generator-capability): hand-written; no pack template emits a parity court.
  @moduledoc """
  The capability parity court: is the GraphLaw surface that `ash_graphlaw` types the same surface
  the engine actually exposes?

  `run/1` starts a real `AshGraphLaw.Host` over the engine bytes, sends `{"op": "capabilities"}`,
  and compares the live answer and the typed Elixir surface with the generated
  `AshGraphLaw.Capability.Registry`. It never skips: an engine that cannot be loaded is a typed
  refusal with a report, not a pass. It never implements RDF, SPARQL, SHACL, ShEx, N3, Datalog,
  entailment or planning semantics; it compares surfaces and replays examples through the typed API.

  ## Checks (ids are frozen)

  | id | claim |
  |----|-------|
  | `P1` | live `capabilities.ops` equals `Registry.names/0`, in order |
  | `P2` | live `rdf_dialects` and `other_dialects` equal the registry lists |
  | `P3` | the surface digest computed from the live response equals `Registry.surface_digest/0`; a live `registry_sha256` equals `Registry.digest/0` (absent on engines older than v26.9.29: reported `UNKNOWN`, not a pass of that field) |
  | `P4` | every registry op has an `AshGraphLaw.Capability.<Op>` module exporting `op/0`, `build_request/1`, `decode/1`, `run/2`, and an API function |
  | `P5` | every `AshGraphLaw.Capability.*` op module maps to a registry op |
  | `P6` | the admission DSL step enum equals the registry `law_steps` (hyphen to underscore; `record-receipts` need not be exposed) |
  | `P7` | every registry `refusal_codes` entry maps through `AshGraphLaw.Refusal.from_engine/2` to a known atom, never `:engine_unclassified` |
  | `P8` | no supported op requires `AshGraphLaw.call/2` (every op has a typed `run/2` and API function) |
  | `P9` | every `priv/graphlaw/op-examples.json` example reproduces through the typed API against the live engine (`not_run` under `examples: false`) |
  | `R1` | the vendored `priv/graphlaw/capability-registry.json` digest, recomputed by `CanonicalJSON`, equals `Registry.digest/0` |
  | `R2` | live runtime ABI identity equals the pinned `priv/graphlaw/MANIFEST.json` `abi_version` |

  `R1` and `R2` are additive checks beyond P1..P9.

  ## Result

  `run/1` returns `{:ok, report}` when no check drifted, or
  `{:error, %{refusal: refusal, report: report}}`. A drift refusal has code
  `:capability_parity_drift` and a message listing the drifted check ids; a blocked run carries the
  refusal that blocked it (for example `:wasm_not_vendored`). The report standing is at most
  `PARTIAL_ALIVE`: parity of surfaces is an observation about one engine, never `ALIVE`.

  ## Options

    * `:wasm_path`, `:bytes`, `:expected_sha256`, `:fuel`, `:timeout_ms` - forwarded to the host;
    * `:examples` - run P9 (default `true`);
    * `:registry` - registry module (default `AshGraphLaw.Capability.Registry`);
    * `:examples_path`, `:registry_json_path`, `:manifest_path` - override vendored `priv/graphlaw` files.
  """

  alias AshGraphLaw.Host
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.WasmConfig

  @schema "ash_graphlaw.parity/1"
  @registry AshGraphLaw.Capability.Registry
  @api AshGraphLaw.Capability.API
  @json AshGraphLaw.Capability.CanonicalJSON
  @helper_modules ~w(Registry API CanonicalJSON Coerce Decode Limits)
  @host_opts [:wasm_path, :bytes, :expected_sha256, :fuel, :timeout_ms]

  @checks [
    {"P1", "live capabilities.ops equals Registry.names/0, in order", "R_missing_identity"},
    {"P2", "live dialect lists equal the registry dialect lists", "R_missing_identity"},
    {"P3", "live surface and registry digests equal the registry digests", "R_missing_identity"},
    {"P4", "every registry op has a typed capability module and API function", "admission_vacuous"},
    {"P5", "every capability op module maps to a registry op", "admission_vacuous"},
    {"P6", "admission DSL step enum equals the registry law steps", "admission_vacuous"},
    {"P7", "every registry refusal code maps to a known refusal atom", "R_missing_consequence"},
    {"P8", "no supported op requires AshGraphLaw.call/2", "admission_vacuous"},
    {"P9", "every op example reproduces through the typed API on the live engine", "R_missing_replay"},
    {"R1", "vendored registry JSON digest equals Registry.digest/0", "R_missing_identity"},
    {"R2", "live runtime ABI equals pinned manifest abi_version", "R_missing_identity"}
  ]

  @typedoc "One check result inside a report."
  @type check :: %{String.t() => term()}

  @typedoc "The parity report (canonical-JSON safe: strings, integers, booleans, nil, lists, maps)."
  @type report :: %{String.t() => term()}

  @typedoc "Failure carrying the typed refusal and the report that documents it."
  @type failure :: %{refusal: Refusal.t(), report: report()}

  @doc "Every check id, in report order."
  @spec check_ids() :: [String.t()]
  def check_ids, do: Enum.map(@checks, &elem(&1, 0))

  @doc "`{id, title}` for every check, in report order."
  @spec checks() :: [{String.t(), String.t()}]
  def checks, do: Enum.map(@checks, fn {id, title, _term} -> {id, title} end)

  # True when `live` is a list equal to `expected`, element for element and in order. The comparison
  # behind P1 and P2; public only so the mutation court can attack it.
  @doc false
  @spec same_list?(term(), [term()]) :: boolean()
  def same_list?(live, expected), do: is_list(live) and live == expected

  # True when `live` is a binary equal to `expected`. The comparison behind the digest checks in P3
  # and R1; public only so the mutation court can attack it.
  @doc false
  @spec same_digest?(term(), String.t()) :: boolean()
  def same_digest?(live, expected), do: is_binary(live) and live == expected

  @doc "Runs the court. See the moduledoc for options and the result shape."
  @spec run(keyword()) :: {:ok, report()} | {:error, failure()}
  def run(opts \\ []) when is_list(opts) do
    registry = Keyword.get(opts, :registry, @registry)

    case snapshot(registry) do
      {:ok, reg} -> run_against_engine(reg, opts)
      {:error, reason} -> registry_unavailable(registry, reason)
    end
  end

  @doc """
  Writes `parity_report.json` (canonical JSON plus a trailing newline) into `dir`, creating it.
  """
  @spec write_report(report(), Path.t()) :: {:ok, Path.t()} | {:error, String.t()}
  def write_report(report, dir) when is_map(report) and is_binary(dir) do
    path = Path.join(dir, "parity_report.json")

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, apply(@json, :encode, [report]) <> "\n") do
      {:ok, path}
    else
      {:error, reason} -> {:error, "#{path}: #{inspect(reason)}"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  # ---------------------------------------------------------------------------
  # Engine
  # ---------------------------------------------------------------------------

  defp run_against_engine(reg, opts) do
    host_opts = Keyword.take(opts, @host_opts)
    {:ok, host} = Host.start_link([name: nil] ++ host_opts)

    try do
      case Host.request(host, %{"op" => "capabilities"}) do
        {:ok, %{"ok" => true} = live} ->
          engine = engine_info(host, opts)
          checks = evaluate(reg, live, host, opts)
          finish(reg, engine, checks)

        {:ok, other} ->
          blocked(
            reg,
            engine_info(host, opts),
            Refusal.new(:malformed_response, "capabilities answered #{inspect(other, limit: 5)}")
          )

        {:error, %Refusal{} = refusal} ->
          blocked(reg, engine_info(host, opts), refusal)
      end
    after
      GenServer.stop(host)
    end
  end

  defp engine_info(host, opts) do
    sha =
      case Host.info(host) do
        {:ok, %{wasm_sha256: sha}} -> sha
        _ -> nil
      end

    expected =
      case WasmConfig.expected_sha256(opts) do
        expected when is_binary(expected) -> expected
        _ -> nil
      end

    %{"wasm_sha256" => sha, "expected_sha256" => expected, "pinned" => expected != nil}
  end

  defp evaluate(reg, live, host, opts) do
    [
      check("P1", fn -> p1(reg, live) end),
      check("P2", fn -> p2(reg, live) end),
      check("P3", fn -> p3(reg, live) end),
      check("P4", fn -> p4(reg) end),
      check("P5", fn -> p5(reg) end),
      check("P6", fn -> p6(reg) end),
      check("P7", fn -> p7(reg) end),
      check("P8", fn -> p8(reg) end),
      check("P9", fn -> p9(reg, host, opts) end),
      check("R1", fn -> r1(reg, opts) end),
      check("R2", fn -> r2(live, opts) end)
    ]
  end

  defp check(id, fun) do
    {status, evidence} =
      try do
        fun.()
      rescue
        error -> {"drift", %{"exception" => Exception.message(error)}}
      catch
        kind, reason -> {"drift", %{"caught" => inspect({kind, reason}, limit: 5)}}
      end

    {^id, title, term} = List.keyfind(@checks, id, 0)

    %{
      "id" => id,
      "title" => title,
      "status" => status,
      "evidence" => jsonable(evidence),
      "broken_term" => if(status == "drift", do: term)
    }
  end

  # ---------------------------------------------------------------------------
  # P1 .. P3: the live surface
  # ---------------------------------------------------------------------------

  defp p1(reg, live) do
    got = Map.get(live, "ops")
    got_list = if is_list(got), do: got, else: []

    evidence = %{
      "expected" => reg.names,
      "live" => got,
      "missing" => reg.names -- got_list,
      "unexpected" => got_list -- reg.names
    }

    verdict(same_list?(got, reg.names), evidence)
  end

  defp p2(reg, live) do
    rdf = Map.get(live, "rdf_dialects")
    other = Map.get(live, "other_dialects")

    evidence = %{
      "rdf_dialects" => %{"expected" => reg.rdf_dialects, "live" => rdf},
      "other_dialects" => %{"expected" => reg.other_dialects, "live" => other}
    }

    verdict(same_list?(rdf, reg.rdf_dialects) and same_list?(other, reg.other_dialects), evidence)
  end

  defp p3(reg, live) do
    computed = computed_surface_digest(live)
    live_surface = Map.get(live, "surface_sha256")
    live_registry = Map.get(live, "registry_sha256")
    live_schema = Map.get(live, "registry_schema")

    parts = [
      {"computed_surface_sha256", same_digest?(computed, reg.surface_digest)},
      {"live_surface_sha256", live_surface == nil or same_digest?(live_surface, reg.surface_digest)},
      {"live_registry_sha256", live_registry == nil or same_digest?(live_registry, reg.digest)},
      {"live_registry_schema", live_schema == nil or same_digest?(live_schema, reg.schema)}
    ]

    evidence = %{
      "expected_surface_sha256" => reg.surface_digest,
      "computed_surface_sha256" => computed,
      "live_surface_sha256" => live_surface,
      "expected_registry_sha256" => reg.digest,
      "live_registry_sha256" => if(live_registry == nil, do: "UNKNOWN", else: live_registry),
      "mismatched" => for({name, false} <- parts, do: name)
    }

    verdict(Enum.all?(parts, &elem(&1, 1)), evidence)
  end

  defp computed_surface_digest(live) do
    apply(@json, :surface_digest, [live])
  rescue
    _ -> nil
  end

  # ---------------------------------------------------------------------------
  # P4, P5, P8: the typed Elixir surface
  # ---------------------------------------------------------------------------

  @module_exports [op: 0, build_request: 1, decode: 1, run: 2]

  defp p4(reg) do
    problems =
      for name <- reg.names, problem <- op_problems(reg, name), do: %{"op" => name, "problem" => problem}

    verdict(problems == [], %{"ops_checked" => length(reg.names), "problems" => problems})
  end

  defp op_problems(reg, name) do
    case reg.module_for.(name) do
      {:ok, module} ->
        module_problems(module) ++ api_problems(name)

      :error ->
        ["no capability module (Registry.module_for/1 returned :error)"]
    end
  end

  defp module_problems(module) do
    loaded? = Code.ensure_loaded?(module)

    for {fun, arity} <- @module_exports, not (loaded? and function_exported?(module, fun, arity)) do
      "#{inspect(module)} does not export #{fun}/#{arity}"
    end
  end

  defp api_problems(name) do
    Code.ensure_loaded(@api)

    for {fun, arity} <- [{String.to_atom(name), 2}, {String.to_atom(name <> "!"), 2}],
        not function_exported?(@api, fun, arity) do
      "#{inspect(@api)} does not export #{fun}/#{arity}"
    end
  end

  defp p5(reg) do
    candidates =
      :ash_graphlaw
      |> Application.spec(:modules)
      |> List.wrap()
      |> Enum.filter(&capability_module?/1)

    orphans =
      for module <- candidates,
          problem = orphan_problem(reg, module),
          do: %{"module" => inspect(module), "problem" => problem}

    verdict(orphans == [], %{"modules_checked" => length(candidates), "orphans" => orphans})
  end

  defp capability_module?(module) do
    case Module.split(module) do
      ["AshGraphLaw", "Capability", name] -> name not in @helper_modules
      _ -> false
    end
  end

  defp orphan_problem(reg, module) do
    Code.ensure_loaded(module)

    if function_exported?(module, :op, 0) do
      name = module.op()

      cond do
        not is_binary(name) -> "op/0 returned #{inspect(name)}, not a string"
        name not in reg.names -> "op #{inspect(name)} is not in Registry.names/0"
        reg.module_for.(name) != {:ok, module} -> "Registry.module_for/1 maps #{inspect(name)} elsewhere"
        true -> nil
      end
    else
      "no op/0: not a registry op module"
    end
  end

  defp p8(reg) do
    Code.ensure_loaded(@api)

    raw =
      for name <- reg.names,
          missing = raw_call_reasons(reg, name),
          missing != [],
          do: %{"op" => name, "requires_raw_call" => missing}

    api_run? = function_exported?(@api, :run, 3)

    evidence = %{
      "ops_checked" => length(reg.names),
      "requires_raw_call" => raw,
      "api_run_3_exported" => api_run?
    }

    verdict(raw == [] and api_run?, evidence)
  end

  defp raw_call_reasons(reg, name) do
    typed =
      case reg.module_for.(name) do
        {:ok, module} ->
          if Code.ensure_loaded?(module) and function_exported?(module, :run, 2), do: [], else: ["no typed run/2"]

        :error ->
          ["no typed module"]
      end

    api = if function_exported?(@api, String.to_atom(name), 2), do: [], else: ["no API function"]
    typed ++ api
  end

  # ---------------------------------------------------------------------------
  # P6, P7: DSL and refusal vocabularies
  # ---------------------------------------------------------------------------

  defp p6(reg) do
    dsl = dsl_steps()

    expected =
      reg.law_steps
      |> Enum.map(&field(&1, :name))
      |> Enum.reject(&(&1 == "record-receipts"))
      |> Enum.map(&String.replace(&1, "-", "_"))

    evidence = %{
      "registry_steps" => expected,
      "dsl_steps" => dsl,
      "missing_in_dsl" => expected -- dsl,
      "extra_in_dsl" => dsl -- expected,
      "note" => "record-receipts is an engine bookkeeping step the DSL need not expose"
    }

    verdict(Enum.sort(dsl) == Enum.sort(expected), evidence)
  end

  defp dsl_steps do
    [section | _] = AshGraphLaw.Resource.sections()
    entity = Enum.find(section.entities, &(&1.name == :admission))
    {:one_of, steps} = entity.schema[:step][:type]
    Enum.map(steps, &Atom.to_string/1)
  end

  defp p7(reg) do
    unmapped =
      for entry <- reg.refusal_codes,
          code = field(entry, :code),
          kind = field(entry, :kind) || "EngineRejected",
          refusal = Refusal.from_engine(%{"details" => %{"code" => code}, "kind" => kind}),
          refusal.code == :engine_unclassified,
          do: %{"code" => code, "kind" => kind}

    verdict(unmapped == [], %{"codes_checked" => length(reg.refusal_codes), "unmapped" => unmapped})
  end

  # ---------------------------------------------------------------------------
  # P9: examples through the typed API
  # ---------------------------------------------------------------------------

  defp p9(reg, host, opts) do
    if Keyword.get(opts, :examples, true) do
      run_examples(reg, host, opts)
    else
      {"not_run", %{"reason" => "examples disabled (--no-examples)"}}
    end
  end

  defp run_examples(reg, host, opts) do
    path = Keyword.get(opts, :examples_path) || priv_file("op-examples.json")

    with {:ok, raw} <- File.read(path),
         {:ok, %{"examples" => examples}} when is_list(examples) <- Jason.decode(raw) do
      failures =
        for example <- examples, failure = example_failure(reg, host, example), do: failure

      verdict(failures == [], %{"path" => path, "examples" => length(examples), "failures" => failures})
    else
      other -> {"drift", %{"path" => path, "unreadable" => inspect(other, limit: 5)}}
    end
  end

  defp example_failure(reg, host, %{"op" => op, "request" => request} = example) when is_map(request) do
    id = Map.get(example, "id")

    with {:ok, module} <- reg.module_for.(op),
         args = Map.delete(request, "op"),
         result = module.run(args, server: host),
         nil <- mismatch(result, example) do
      nil
    else
      :error -> %{"id" => id, "problem" => "no capability module for op #{inspect(op)}"}
      reason when is_binary(reason) -> %{"id" => id, "problem" => reason}
    end
  end

  defp example_failure(_reg, _host, example),
    do: %{"id" => inspect(example, limit: 3), "problem" => "malformed example"}

  defp mismatch({:ok, _struct}, %{"outcome" => "ok"}), do: nil
  defp mismatch({:ok, _struct}, %{"outcome" => "refused"}), do: "expected a refusal, the engine accepted"

  defp mismatch({:error, %Refusal{} = refusal}, %{"outcome" => "refused"} = example) do
    kind = Map.get(example, "refusal_kind")
    code = Map.get(example, "refusal_code")

    cond do
      kind != nil and refusal.kind != kind ->
        "expected refusal kind #{kind}, got #{inspect(refusal.kind)}"

      code != nil and Map.get(refusal.details, "code") != code ->
        "expected engine code #{code}, got #{inspect(refusal.details["code"])}"

      true ->
        nil
    end
  end

  defp mismatch({:error, %Refusal{} = refusal}, %{"outcome" => "ok"}),
    do: "expected success, got refusal #{refusal.code}: #{refusal.message}"

  defp mismatch(other, _example), do: "unexpected result #{inspect(other, limit: 5)}"

  # ---------------------------------------------------------------------------
  # R1: vendored registry digest
  # ---------------------------------------------------------------------------

  defp r1(reg, opts) do
    path = Keyword.get(opts, :registry_json_path) || priv_file("capability-registry.json")

    with {:ok, raw} <- File.read(path),
         {:ok, %{} = doc} <- Jason.decode(raw) do
      recomputed = apply(@json, :digest, [doc])

      evidence = %{
        "path" => path,
        "recomputed" => recomputed,
        "declared" => Map.get(doc, "registry_sha256"),
        "registry_module" => reg.digest
      }

      verdict(
        same_digest?(recomputed, reg.digest) and same_digest?(Map.get(doc, "registry_sha256"), reg.digest),
        evidence
      )
    else
      other -> {"drift", %{"path" => path, "unreadable" => inspect(other, limit: 5)}}
    end
  end

  defp r2(live, opts) do
    path = Keyword.get(opts, :manifest_path) || priv_file("MANIFEST.json")

    with {:ok, raw} <- File.read(path),
         {:ok, %{"abi_version" => expected}} <- Jason.decode(raw) do
      live_abi = Map.get(live, "abi_version", Map.get(live, "abi"))
      evidence = %{"path" => path, "expected" => expected, "live" => live_abi}
      verdict(is_integer(expected) and live_abi == expected, evidence)
    else
      other -> {"drift", %{"path" => path, "unreadable" => inspect(other, limit: 5)}}
    end
  end

  defp priv_file(name), do: Path.join(Application.app_dir(:ash_graphlaw, "priv/graphlaw"), name)

  # ---------------------------------------------------------------------------
  # Registry snapshot and report assembly
  # ---------------------------------------------------------------------------

  defp snapshot(registry) do
    if Code.ensure_loaded?(registry) do
      {:ok,
       %{
         module: registry,
         schema: apply(registry, :schema, []),
         graphlaw_version: apply(registry, :graphlaw_version, []),
         digest: apply(registry, :digest, []),
         surface_digest: apply(registry, :surface_digest, []),
         names: apply(registry, :names, []),
         rdf_dialects: apply(registry, :rdf_dialects, []),
         other_dialects: apply(registry, :other_dialects, []),
         law_steps: apply(registry, :law_steps, []),
         refusal_codes: apply(registry, :refusal_codes, []),
         module_for: fn name -> apply(registry, :module_for, [name]) end
       }}
    else
      {:error, "#{inspect(registry)} is not compiled; run scripts/ggen_sync.sh"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp verdict(true, evidence), do: {"pass", evidence}
  defp verdict(false, evidence), do: {"drift", evidence}

  defp finish(reg, engine, checks) do
    drift = for %{"status" => "drift", "id" => id} <- checks, do: id
    base = base_report(reg, engine, checks)

    if drift == [] do
      {:ok, Map.merge(base, %{"drift" => [], "status" => "PASS", "standing" => "PARTIAL_ALIVE"})}
    else
      refusal = Refusal.new(:capability_parity_drift, Enum.join(drift, " "), %{"checks" => drift})
      report = Map.merge(base, %{"drift" => drift, "status" => "DRIFT", "standing" => "REFUSED"})
      {:error, %{refusal: refusal, report: report}}
    end
  end

  defp blocked(reg, engine, %Refusal{} = refusal) do
    checks =
      for {id, title, _term} <- @checks do
        %{
          "id" => id,
          "title" => title,
          "status" => "blocked",
          "evidence" => %{"blocked_by" => Atom.to_string(refusal.code), "message" => refusal.message},
          "broken_term" => nil
        }
      end

    report =
      reg
      |> base_report(engine, checks)
      |> Map.merge(%{
        "drift" => [],
        "status" => "BLOCKED",
        "standing" => "BLOCKED",
        "blocked_by" => Atom.to_string(refusal.code)
      })

    {:error, %{refusal: refusal, report: report}}
  end

  defp registry_unavailable(registry, reason) do
    checks =
      for {id, title, term} <- @checks do
        %{
          "id" => id,
          "title" => title,
          "status" => "drift",
          "evidence" => %{"registry_unavailable" => reason},
          "broken_term" => term
        }
      end

    ids = check_ids()

    report = %{
      "schema" => @schema,
      "registry_module" => inspect(registry),
      "checks" => checks,
      "drift" => ids,
      "status" => "DRIFT",
      "standing" => "REFUSED"
    }

    {:error, %{refusal: Refusal.new(:capability_parity_drift, Enum.join(ids, " "), %{"checks" => ids}), report: report}}
  end

  defp base_report(reg, engine, checks) do
    %{
      "schema" => @schema,
      "graphlaw_version" => reg.graphlaw_version,
      "registry_schema" => reg.schema,
      "registry_sha256" => reg.digest,
      "surface_sha256" => reg.surface_digest,
      "engine" => engine,
      "checks" => checks
    }
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp jsonable(nil), do: nil
  defp jsonable(value) when is_boolean(value) or is_binary(value) or is_integer(value), do: value
  defp jsonable(value) when is_atom(value), do: Atom.to_string(value)
  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)
  defp jsonable(%{__struct__: _} = value), do: inspect(value, limit: 10)
  defp jsonable(value) when is_map(value), do: Map.new(value, fn {k, v} -> {to_string(k), jsonable(v)} end)
  defp jsonable(value), do: inspect(value, limit: 10)
end
