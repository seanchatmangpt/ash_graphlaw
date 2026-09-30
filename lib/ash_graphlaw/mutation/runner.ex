# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Mutation.Runner do
  @moduledoc """
  Runs killer test files inside the running VM and summarizes the outcome.

  Development tooling. UNSUPPORTED(generator-capability): hand-written; no pack
  template emits a mutation court.

  Each call compiles the given test files afresh (module redefinition is allowed for the
  duration of the call, because the same files run once per baseline and once per mutant),
  runs ExUnit with `AshGraphLaw.Mutation.Collector` as the only formatter, and returns

      %{total: n, failures: n, skipped: n, excluded: n, failed: ["Mod: test name", ...]}

  Tests tagged `:wasm` are excluded when no engine binary is present at
  `AshGraphLaw.WasmConfig.wasm_path/1`, with a printed stderr line (never a stub);
  pass `exclude: [...]` to override.

  ## Containment

  `Code.compile_file/1` evaluates arbitrary top-level code and redefines loaded modules, so the
  runner admits a file only when (1) its real path is inside the project's `test/` directory
  (`:test_root`, default `test`; symlinks are refused) and (2) it does not define a module that
  is already loaded from anywhere outside that directory, which would silently replace an
  admission or ceiling module in the running VM. Either failure returns
  `{:error, {:path_outside_test_root, file}}` or `{:error, {:module_conflict, module, source}}`
  before anything is compiled. After the run the modules the files defined are purged.

  Must not be called from inside a running ExUnit suite: ExUnit's server is a singleton.
  The mix task `mix ash_graphlaw.mutate` is the caller. `ExUnit` is reached through a
  runtime module reference so the library compiles without `:ex_unit` in the application list.
  """

  alias AshGraphLaw.Mutation.Collector

  @typedoc "Counts and failed test names from one killer run."
  @type summary :: %{
          total: non_neg_integer(),
          failures: non_neg_integer(),
          skipped: non_neg_integer(),
          excluded: non_neg_integer(),
          failed: [String.t()]
        }

  @doc "Runs `files` in this VM. Returns `{:error, reason}` when ExUnit itself cannot run."
  @spec run([Path.t()], keyword()) :: {:ok, summary()} | {:error, term()}
  def run(files, opts \\ []) when is_list(files) and is_list(opts) do
    ex_unit = Module.concat(["ExUnit"])
    test_root = opts |> Keyword.get(:test_root, "test") |> Path.expand()

    with :ok <- admit_files(files, test_root) do
      run_admitted(ex_unit, files, opts)
    end
  end

  defp run_admitted(ex_unit, files, opts) do
    Collector.drop_table()
    Collector.new_table()
    compiled = :ets.new(:ash_graphlaw_mutation_compiled, [:public])

    try do
      {:ok, _apps} = Application.ensure_all_started(:ex_unit)
      ex_unit.configure(configuration(opts))
      compile(files, compiled)
      {:ok, summarize(ex_unit.run())}
    rescue
      exception -> {:error, {:ex_unit_raised, Exception.message(exception)}}
    catch
      kind, reason -> {:error, {kind, inspect(reason, limit: 10)}}
    after
      purge(compiled)
      Collector.drop_table()
    end
  end

  @doc "Tags excluded by default: `[:wasm]` when no engine binary is present, else `[]`."
  @spec default_exclusions() :: [atom()]
  def default_exclusions do
    if wasm_present?() do
      []
    else
      IO.puts(:stderr, "[wasm] EXCLUDING :wasm tests from mutation killers -- no engine binary vendored")
      [:wasm]
    end
  end

  defp wasm_present? do
    Code.ensure_loaded?(AshGraphLaw.WasmConfig) and File.regular?(AshGraphLaw.WasmConfig.wasm_path([]))
  end

  defp configuration(opts) do
    [
      autorun: false,
      formatters: [Collector],
      colors: [enabled: false],
      exclude: Keyword.get_lazy(opts, :exclude, &default_exclusions/0),
      include: [],
      max_cases: 1,
      seed: 0,
      trace: false
    ]
  end

  defp compile(files, compiled) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      for file <- files, {module, _binary} <- Code.compile_file(file) do
        :ets.insert(compiled, {module})
      end
    after
      Code.put_compiler_option(:ignore_module_conflict, previous || false)
    end
  end

  # The killer files' own modules are dropped so a later run starts from the project's code.
  defp purge(compiled) do
    for {module} <- :ets.tab2list(compiled) do
      :code.purge(module)
      :code.delete(module)
      :code.purge(module)
    end

    :ets.delete(compiled)
  end

  # -- containment -------------------------------------------------------------

  # Containment gate, public (`@doc false`) so it can be exercised without running ExUnit inside
  # ExUnit, which `run/2` cannot do.
  @doc false
  @spec admit_files([Path.t()], Path.t()) :: :ok | {:error, term()}
  def admit_files(files, test_root) do
    Enum.reduce_while(files, :ok, fn file, :ok ->
      with :ok <- inside_test_root(file, test_root),
           :ok <- no_loaded_conflict(file, test_root) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp inside_test_root(file, test_root) do
    expanded = Path.expand(file)
    inside? = expanded == test_root or String.starts_with?(expanded, test_root <> "/")
    symlink? = match?({:ok, %File.Stat{type: :symlink}}, File.lstat(expanded))

    if inside? and not symlink?, do: :ok, else: {:error, {:path_outside_test_root, file}}
  end

  defp no_loaded_conflict(file, test_root) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source, file: file) do
      ast
      |> defined_modules()
      |> Enum.find_value(:ok, fn module -> conflict(module, test_root) end)
    else
      # Unreadable or unparsable: let the compiler report it as the run error it is.
      _ -> :ok
    end
  end

  defp conflict(module, test_root) do
    # ensure_loaded, not is_loaded: a lib module the VM has not touched yet is still on the code path
    # and would be silently replaced.
    with true <- Code.ensure_loaded?(module),
         source when is_list(source) <- module.module_info(:compile)[:source],
         false <- String.starts_with?(Path.expand(to_string(source)), test_root <> "/") do
      {:error, {:module_conflict, module, to_string(source)}}
    else
      _ -> nil
    end
  end

  # Module names a file defines, with nested `defmodule`s resolved against their parents.
  defp defined_modules(ast) do
    {_ast, {_stack, modules}} =
      Macro.traverse(
        ast,
        {[], []},
        fn
          {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, {stack, acc} ->
            local = Module.concat(parts)
            name = if stack == [], do: local, else: Module.concat([hd(stack), local])
            {node, {[name | stack], [name | acc]}}

          node, state ->
            {node, state}
        end,
        fn
          {:defmodule, _, [{:__aliases__, _, _} | _]} = node, {[_ | stack], acc} -> {node, {stack, acc}}
          node, state -> {node, state}
        end
      )

    Enum.reverse(modules)
  end

  defp summarize(%{} = result) do
    %{
      total: Map.get(result, :total, 0),
      failures: Map.get(result, :failures, 0),
      skipped: Map.get(result, :skipped, 0),
      excluded: Map.get(result, :excluded, 0),
      failed: Collector.failed()
    }
  end
end
