# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.MutationFixture do
  @moduledoc """
  Private throwaway fixture for the mutation engine tests (development tooling).

  UNSUPPORTED(generator-capability): hand-written test support. Each call compiles a fresh module,
  writes its BEAM to a private directory placed on the code path, and returns the module, the BEAM
  path and a cleanup function. The fixture never touches an `:ash_graphlaw` module.
  """

  @spec compile!() :: {module(), Path.t(), (-> :ok)}
  def compile! do
    name = Module.concat(["AshGraphLaw.Test.MutationFixture", "M#{System.unique_integer([:positive])}"])
    dir = Path.join(System.tmp_dir!(), "agl-mutation-fixture-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    source = """
    defmodule #{inspect(name)} do
      def admit(n) when is_integer(n) and n > 0, do: :ok
      def admit(_n), do: :refused

      def double(n), do: n * 2

      defp secret(_x), do: :guarded
      def reveal(x), do: secret(x)
    end
    """

    # `mix test` turns the `:debug_info` compiler option off; the mutation engine reads the
    # `debug_info` chunk of a target, which lib modules compiled by Mix always carry. The
    # fixture must carry it too, or it would not resemble a real target.
    previous = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)

    [{^name, binary}] =
      try do
        Code.compile_string(source)
      after
        Code.put_compiler_option(:debug_info, previous)
      end

    beam = Path.join(dir, "#{name}.beam")
    File.write!(beam, binary)
    true = :code.add_patha(String.to_charlist(dir))

    cleanup = fn ->
      :code.del_path(String.to_charlist(dir))
      :code.purge(name)
      :code.delete(name)
      :code.purge(name)
      File.rm_rf!(dir)
      :ok
    end

    {name, beam, cleanup}
  end

  @spec disk_md5(Path.t()) :: String.t()
  def disk_md5(beam) do
    {:ok, {_module, md5}} = :beam_lib.md5(File.read!(beam))
    Base.encode16(md5, case: :lower)
  end

  @spec loaded_md5(module()) :: String.t()
  def loaded_md5(module), do: Base.encode16(module.module_info(:md5), case: :lower)
end

defmodule AshGraphLaw.MutationEngineTest do
  use ExUnit.Case, async: false

  alias AshGraphLaw.Mutation
  alias AshGraphLaw.Mutation.{Catalog, Collector, Verdict}
  alias AshGraphLaw.Test.MutationFixture

  @apps [applications: [:undefined]]

  setup do
    {module, beam, cleanup} = MutationFixture.compile!()
    on_exit(cleanup)

    root = Path.join(System.tmp_dir!(), "agl-mutation-root-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "killer_test.exs"), "# stands in for a killer test file\n")
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, module: module, beam: beam, root: root}
  end

  defp mutation(module, function, arity, operator, attrs \\ []) do
    struct!(
      Mutation,
      [
        id: "FIX-#{function}",
        module: module,
        function: function,
        arity: arity,
        operator: operator,
        killers: ["killer_test.exs"]
      ] ++
        attrs
    )
  end

  # A real killer runner over the fixture: it exercises the guard and reports what failed, in the
  # `AshGraphLaw.Mutation.Runner` summary shape.
  defp summary(checks) do
    failed = for {name, false} <- checks, do: to_string(name)
    %{total: length(checks), failures: length(failed), skipped: 0, excluded: 0, failed: failed}
  end

  defp strong_runner(module) do
    fn _files, _opts ->
      {:ok, summary(admits_positive: module.admit(1) == :ok, refuses_negative: module.admit(-1) == :refused)}
    end
  end

  defp weak_runner(module) do
    fn _files, _opts -> {:ok, summary(admits_positive: module.admit(1) == :ok)} end
  end

  describe "prepare/2" do
    test "prepares a fixture mutant and refuses the same module as foreign to :ash_graphlaw", %{module: module} do
      m = mutation(module, :admit, 1, {:replace_body, "ok."})

      assert {:ok, plan} = Mutation.prepare(m, @apps)
      assert plan.clauses_mutated == 2
      assert plan.original_md5 != plan.mutant_md5

      assert {:error, %{code: :mutation_target_foreign}} = Mutation.prepare(m)
    end

    test "refuses every Mutation module, whatever the application override" do
      for module <- [
            AshGraphLaw.Mutation,
            AshGraphLaw.Mutation.Verdict,
            AshGraphLaw.Mutation.Catalog,
            AshGraphLaw.Mutation.Runner,
            Mix.Tasks.AshGraphlaw.Mutate
          ] do
        assert Mutation.protected?(module)
        m = mutation(module, :qualify, 2, {:replace_body, "ok."})

        assert {:error, %{code: :mutation_target_protected}} =
                 Mutation.prepare(m, applications: [:ash_graphlaw, :undefined, :mix])
      end
    end

    test "refuses modules outside the subject, not compiled, sticky-free lookups and bad targets", %{module: module} do
      assert {:ok, _plan} = Mutation.prepare(mutation(module, :double, 1, {:replace_body, "0."}), @apps)

      assert {:error, %{code: :mutation_target_foreign}} =
               Mutation.prepare(mutation(Enum, :count, 1, {:replace_body, "0."}))

      missing = Module.concat(["AshGraphLaw", "NoSuchModule"])

      assert {:error, %{code: :mutation_target_not_compiled}} =
               Mutation.prepare(mutation(missing, :x, 0, {:replace_body, "ok."}))

      assert {:error, %{code: :mutation_function_not_found}} =
               Mutation.prepare(mutation(module, :nope, 1, {:replace_body, "ok."}), @apps)

      assert {:error, %{code: :mutation_body_invalid}} =
               Mutation.prepare(mutation(module, :double, 1, {:replace_body, "ok ok."}), @apps)

      assert {:error, %{code: :mutation_clause_not_matched}} =
               Mutation.prepare(mutation(module, :admit, 1, {:replace_body, "ok."}, clauses: {:clause, 9}), @apps)

      assert {:error, %{code: :mutation_clause_not_matched}} =
               Mutation.prepare(mutation(module, :double, 1, {:negate_guard}), @apps)

      assert {:error, %{code: :mutation_operator_invalid}} =
               Mutation.prepare(mutation(module, :double, 1, :delete), @apps)
    end

    test "refuses a target whose loaded code differs from its on-disk BEAM", %{module: module} do
      m = mutation(module, :double, 1, {:replace_body, "0."})
      assert {:ok, plan} = Mutation.prepare(m, @apps)

      {:module, ^module} = :code.load_binary(module, plan.filename, plan.mutant_binary)
      on_exit(fn -> Mutation.restore!(module) end)

      assert {:error, %{code: :mutation_target_not_pristine}} = Mutation.prepare(m, @apps)
      assert Mutation.restore!(module)
      assert {:ok, _plan} = Mutation.prepare(m, @apps)
    end
  end

  describe "with_mutant/3" do
    test "loads the mutant, restores the BEAM md5-identical and verifies it", %{module: module, beam: beam} do
      m = mutation(module, :admit, 1, {:replace_body, "ok."})
      disk = MutationFixture.disk_md5(beam)

      assert MutationFixture.loaded_md5(module) == disk
      assert module.admit(-1) == :refused

      assert {:ok, :observed, %{applied: applied, restored: restored}} =
               Mutation.with_mutant(
                 m,
                 fn applied ->
                   assert MutationFixture.loaded_md5(module) == applied.mutant_md5
                   assert module.admit(-1) == :ok
                   :observed
                 end,
                 @apps
               )

      assert applied.original_md5 == disk
      assert restored.pristine
      assert restored.restored_md5 == disk
      assert MutationFixture.loaded_md5(module) == disk
      assert module.admit(-1) == :refused
      assert Mutation.pristine?(module)
    end

    test "restores after the stimulus raises", %{module: module, beam: beam} do
      m = mutation(module, :admit, 1, {:replace_body, "ok."})

      assert_raise RuntimeError, "stimulus failed", fn ->
        Mutation.with_mutant(m, fn _applied -> raise "stimulus failed" end, @apps)
      end

      assert Mutation.pristine?(module)
      assert MutationFixture.loaded_md5(module) == MutationFixture.disk_md5(beam)
    end

    test "the guardian restores the BEAM when the owner is killed outright", %{module: module, beam: beam} do
      m = mutation(module, :admit, 1, {:replace_body, "ok."})
      test_pid = self()

      owner =
        spawn(fn ->
          Mutation.with_mutant(
            m,
            fn _applied ->
              send(test_pid, :mutant_live)
              Process.sleep(:infinity)
            end,
            @apps
          )
        end)

      assert_receive :mutant_live, 10_000
      assert module.admit(-1) == :ok

      Process.exit(owner, :kill)
      assert eventually(fn -> Mutation.pristine?(module) end)
      assert MutationFixture.loaded_md5(module) == MutationFixture.disk_md5(beam)
      assert module.admit(-1) == :refused
    end

    test "mutates a private function and negates a guard", %{module: module} do
      private = mutation(module, :secret, 1, {:replace_body, "mutated."})
      assert module.reveal(1) == :guarded
      assert {:ok, :mutated, _info} = Mutation.with_mutant(private, fn _ -> module.reveal(1) end, @apps)
      assert module.reveal(1) == :guarded

      negated = mutation(module, :admit, 1, {:negate_guard})

      assert {:ok, {:refused, :ok}, %{restored: %{pristine: true}}} =
               Mutation.with_mutant(negated, fn _ -> {module.admit(1), module.admit(0)} end, @apps)

      assert {module.admit(1), module.admit(0)} == {:ok, :refused}
    end

    test "a second live mutation is refused while the first holds the engine lock", %{module: module} do
      outer = mutation(module, :admit, 1, {:replace_body, "ok."})
      inner = mutation(module, :double, 1, {:replace_body, "0."})

      assert {:ok, {:error, %{code: code}}, _info} =
               Mutation.with_mutant(outer, fn _ -> Mutation.with_mutant(inner, fn _ -> :ran end, @apps) end, @apps)

      assert code in [:mutation_in_progress, :mutation_target_not_pristine]
      assert Mutation.pristine?(module)
    end
  end

  describe "qualify/2" do
    test "killer files absent -> :blocked, killers present -> not blocked", %{module: module, root: root} do
      runner = strong_runner(module)

      present =
        Mutation.qualify(mutation(module, :admit, 1, {:replace_body, "ok."}), [root: root, runner: runner] ++ @apps)

      refute present.verdict == :blocked

      absent_mutation = mutation(module, :admit, 1, {:replace_body, "ok."}, killers: ["no/such/**/*_test.exs"])
      absent = Mutation.qualify(absent_mutation, [root: root, runner: runner] ++ @apps)

      assert absent.verdict == :blocked
      assert absent.code == :mutation_killers_missing
      assert Mutation.pristine?(module)
    end

    test "a refused target is :blocked with its refusal code, never skipped", %{root: root} do
      m = mutation(AshGraphLaw.Mutation, :qualify, 2, {:replace_body, "ok."})
      verdict = Mutation.qualify(m, root: root)
      assert %Verdict{verdict: :blocked, code: :mutation_target_protected} = verdict
    end

    test "a killer that fails under the mutant -> :mutant_killed", %{module: module, root: root} do
      m = mutation(module, :admit, 1, {:replace_body, "ok."}, guard: "fixture admit guard")
      verdict = Mutation.qualify(m, [root: root, runner: strong_runner(module)] ++ @apps)

      assert verdict.verdict == :mutant_killed
      assert verdict.killed_by == ["refuses_negative"]
      assert verdict.baseline.failures == 0
      assert verdict.mutant.failures == 1
      assert verdict.restored.pristine
      assert is_integer(verdict.mutant_calls) and verdict.mutant_calls > 0
      assert Mutation.pristine?(module)
    end

    test "killers that stay green with the guard removed -> :mutant_survived", %{module: module, root: root} do
      m = mutation(module, :admit, 1, {:replace_body, "ok."}, guard: "fixture admit guard")
      verdict = Mutation.qualify(m, [root: root, runner: weak_runner(module)] ++ @apps)

      assert verdict.verdict == :mutant_survived
      assert verdict.detail =~ "fixture admit guard"
      assert verdict.killed_by == []
      assert Mutation.pristine?(module)
    end

    test "a baseline that is not green -> :unknown and no mutation is applied", %{module: module, root: root} do
      red = fn _files, _opts -> {:ok, summary(always_red: false)} end

      verdict =
        Mutation.qualify(mutation(module, :admit, 1, {:replace_body, "ok."}), [root: root, runner: red] ++ @apps)

      assert verdict.verdict == :unknown
      assert verdict.detail =~ "baseline not green"
      assert verdict.applied == nil
      assert Mutation.pristine?(module)

      empty = fn _files, _opts -> {:ok, summary([])} end

      verdict =
        Mutation.qualify(mutation(module, :admit, 1, {:replace_body, "ok."}), [root: root, runner: empty] ++ @apps)

      assert verdict.verdict == :unknown
    end

    test "a runner that cannot run under the mutant -> :unknown, and the BEAM is restored", %{
      module: module,
      root: root
    } do
      flaky = fn _files, _opts ->
        if module.admit(-1) == :ok, do: {:error, :runner_lost}, else: {:ok, summary(ok: true)}
      end

      verdict =
        Mutation.qualify(mutation(module, :admit, 1, {:replace_body, "ok."}), [root: root, runner: flaky] ++ @apps)

      assert verdict.verdict == :unknown
      assert verdict.mutant.error =~ "runner_lost"
      assert Mutation.pristine?(module)
    end

    test "a runner that raises under the mutant is contained", %{module: module, root: root} do
      raising = fn _files, _opts ->
        if module.admit(-1) == :ok, do: raise("boom"), else: {:ok, summary(ok: true)}
      end

      verdict =
        Mutation.qualify(mutation(module, :admit, 1, {:replace_body, "ok."}), [root: root, runner: raising] ++ @apps)

      assert verdict.verdict == :unknown
      assert verdict.mutant.error =~ "boom"
      assert Mutation.pristine?(module)
    end
  end

  describe "Verdict" do
    test "canonical_json is deterministic, sorted and carries every verdict in the tally", %{module: module, root: root} do
      m = mutation(module, :admit, 1, {:replace_body, "ok."})
      verdict = Mutation.qualify(m, [root: root, runner: strong_runner(module)] ++ @apps)

      json = Verdict.canonical_json([verdict])
      assert json == Verdict.canonical_json([verdict])
      assert String.ends_with?(json, "\n")

      decoded = Jason.decode!(json)
      assert decoded["schema"] == "ash_graphlaw.mutation_report/1"
      assert decoded["tally"] == %{"mutant_killed" => 1, "mutant_survived" => 0, "blocked" => 0, "unknown" => 0}
      assert [%{"verdict" => "mutant_killed", "mutation_id" => "FIX-admit"}] = decoded["verdicts"]

      keys = decoded |> Map.keys() |> Enum.sort()
      assert keys == ["schema", "tally", "verdicts"]
      assert json =~ ~r/"schema".*"tally".*"verdicts"/s
    end

    test "verdicts/0 is the closed set" do
      assert Verdict.verdicts() == [:mutant_killed, :mutant_survived, :blocked, :unknown]
    end
  end

  describe "Catalog" do
    test "ids are the append-only AGL-MUT-NNN sequence" do
      ids = Catalog.ids()
      assert ids == Enum.uniq(ids)
      assert ids == Enum.map(1..length(ids), &"AGL-MUT-#{String.pad_leading(Integer.to_string(&1), 3, "0")}")
      assert length(ids) >= 10

      first_ten = Enum.take(ids, 10)
      assert List.first(first_ten) == "AGL-MUT-001"
      assert List.last(first_ten) == "AGL-MUT-010"
    end

    test "every entry has a parseable operator, unprotected subject targets and killers" do
      for m <- Catalog.entries() do
        refute Mutation.protected?(m.module), "#{m.id} targets protected #{inspect(m.module)}"
        assert Atom.to_string(m.module) =~ ~r/^Elixir\.AshGraphLaw\./
        assert m.killers == Catalog.killers()
        assert is_binary(m.guard) and is_binary(m.description)

        case m.operator do
          {:replace_body, source} ->
            {:ok, tokens, _} = :erl_scan.string(String.to_charlist(source))
            assert {:ok, [_ | _]} = :erl_parse.parse_exprs(tokens), "#{m.id} body does not parse"

          {:negate_guard} ->
            :ok
        end
      end
    end

    test "resolution reports each entry as resolvable or BLOCKED with a known refusal code", %{root: root} do
      resolution = Catalog.resolution(root: root)
      assert Enum.map(resolution, & &1.id) == Catalog.ids()

      for entry <- resolution do
        assert entry.killer_files == []

        case entry.target_status do
          :resolvable -> :ok
          {:blocked, code, _detail} -> assert Map.has_key?(Mutation.refusal_codes(), code)
        end
      end
    end

    test "every refusal code is classed with a closed class" do
      classes = [:refused_authority, :refused_identity, :refused_structure, :blocked_resource]
      assert Mutation.refusal_codes() |> Map.values() |> Enum.all?(&(&1 in classes))
    end
  end

  describe "Collector" do
    test "records failed tests only, by module and name" do
      Collector.drop_table()
      Collector.new_table()
      {:ok, pid} = GenServer.start_link(Collector, [])

      GenServer.cast(pid, {:test_finished, %{state: nil, name: :"test passes", module: Sample}})
      GenServer.cast(pid, {:test_finished, %{state: {:failed, []}, name: :"test fails", module: Sample}})
      GenServer.cast(pid, {:module_finished, %{name: Sample}})
      _ = :sys.get_state(pid)

      assert Collector.failed() == ["Sample: test fails"]
      GenServer.stop(pid)
      Collector.drop_table()
    end
  end

  defp eventually(fun, attempts \\ 100) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(50)
        eventually(fun, attempts - 1)
    end
  end
end
