# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshGraphlaw.TestLivebooks do
  # UNSUPPORTED(generator-capability): hand-written; no pack emits a livebook runner.
  @shortdoc "Runs the fenced elixir cells of every *.livemd against the loaded ash_graphlaw"

  @moduledoc """
  Executes the runnable livebooks of this repository as a test.

  A livebook is Markdown with fenced `elixir` cells. This task parses every `*.livemd`, drops the
  `Mix.install/2` cell (the project is already loaded, and installing it again is exactly what the
  notebook does when opened in Livebook), and evaluates the remaining cells one after another in
  a single shared binding and environment, the way Livebook does. Only cells fenced as `elixir`
  run; `text`, `bash`, `sparql` and every other fence is prose.

  Guarantees:

    * The engine is admitted first with `AshGraphLaw.EngineLoad.admit/2` against the pin in
      `priv/graphlaw/MANIFEST.json`. When it is not vendored the task FAILS with
      `[wasm_not_vendored]`; it never skips. `--allow-unvendored` is the one explicit opt-out
      and only forgives an absent engine: an engine that is present but refused (digest,
      imports, exports) always fails.
    * Each notebook is evaluated in its own process. The top-level `Demo` module namespace used by
      the notebooks is rewritten to a unique `AshGraphLaw.LivebookRun<N>.Demo` namespace, and
      the modules a notebook defined are purged afterwards, so notebooks never collide.
    * A raised, thrown or exited cell fails its notebook at that cell (later cells depend on
      earlier ones) and the task exits non-zero after every notebook has been tried.
    * Cell output is captured and shown only with `--verbose`. Nothing is stubbed or pre-filled.

  A passing run is an observation about these notebooks against these bytes; it grants nothing.
  When the engine is unvendored and `--allow-unvendored` is passed, engine cells run their typed
  refusal path, and the task prints that fact.

  ## Usage

      mix ash_graphlaw.test_livebooks
      mix ash_graphlaw.test_livebooks ash_graphlaw.livemd
      mix ash_graphlaw.test_livebooks --allow-unvendored --verbose

  With no file arguments the task runs `ash_graphlaw.livemd` and every `documentation/**/*.livemd`
  under the current directory.

  ## Options

    * `--allow-unvendored` - run even when `priv/graphlaw/graphlaw.wasm` is absent.
    * `--verbose` - print each cell's captured output.
    * `--timeout MS` - per-notebook time budget in milliseconds (default `300000`).

  Unknown switches raise `Mix.Error`.

  ## Exit codes

    * `0` - every cell of every notebook ran without raising.
    * `1` - failure, raised as `Mix.Error` with a typed code in brackets:
      `[wasm_not_vendored]`, the `AshGraphLaw.Refusal` code of a refused engine, `[invalid_options]`,
      `[livebook_not_found]`, `[livebook_no_cells]`, or `[livebook_cell_failed]`.

  ## Examples

      # CI: engine vendored first, so every engine cell runs for real
      mix ash_graphlaw.vendor && mix ash_graphlaw.test_livebooks

      # offline smoke: refusal paths only
      mix ash_graphlaw.test_livebooks --allow-unvendored
  """

  use Mix.Task

  alias AshGraphLaw.EngineLoad
  alias AshGraphLaw.WasmConfig

  @switches [allow_unvendored: :boolean, verbose: :boolean, timeout: :integer]
  @default_timeout 300_000
  @default_root "ash_graphlaw.livemd"
  @cell_regex ~r/^```elixir[ \t]*\r?\n(.*?)^```[ \t]*\r?$/ms
  @install_regex ~r/\bMix\.install\s*\(/
  @namespace_regex ~r/(?<![A-Za-z0-9_.])Demo(?![A-Za-z0-9_])/

  @typedoc "One fenced elixir cell: its source and the 1-based line of its first source line."
  @type cell :: %{code: String.t(), line: pos_integer(), install?: boolean()}

  @typedoc "Outcome of one notebook."
  @type outcome :: {:ok, %{cells: non_neg_integer(), output: String.t()}} | {:error, map()}

  @doc """
  Runs the task. Returns `:ok`; raises `Mix.Error` with a `[code]` prefix on failure.
  """
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(argv) do
    {opts, files} = parse!(argv)
    Mix.Task.run("app.start")

    engine = engine_state()
    check_engine!(engine, opts)

    paths =
      case files do
        [] -> discover(File.cwd!())
        given -> given
      end

    if paths == [], do: fail("livebook_not_found", "no *.livemd files found under #{File.cwd!()}")

    failures =
      paths
      |> Enum.map(&run_file(&1, opts))
      |> Enum.reject(&(&1 == :ok))

    case failures do
      [] ->
        Mix.shell().info("livebooks: #{length(paths)} notebook(s) passed.")
        :ok

      failed ->
        fail("livebook_cell_failed", "#{length(failed)} of #{length(paths)} notebook(s) failed")
    end
  end

  @doc """
  The default notebook set under `root`: `ash_graphlaw.livemd` first, then every
  `documentation/**/*.livemd`, sorted, as paths relative to `root`.
  """
  @spec discover(Path.t()) :: [Path.t()]
  def discover(root) do
    docs = root |> Path.join("documentation/**/*.livemd") |> Path.wildcard() |> Enum.sort()
    top = Path.join(root, @default_root)
    (if File.regular?(top), do: [top], else: []) ++ docs
  end

  @doc """
  Parses Markdown into its fenced `elixir` cells, in document order.

  Each cell carries the line of its first source line so an exception can be located in the
  notebook. Fences of any other language are ignored.
  """
  @spec cells(String.t()) :: [cell()]
  def cells(markdown) when is_binary(markdown) do
    scan_cells(markdown)
  end

  defp scan_cells(markdown) do
    @cell_regex
    |> Regex.scan(markdown, return: :index, capture: :all)
    |> Enum.map(fn [{_start, _len}, {body_start, body_len}] ->
      code = binary_part(markdown, body_start, body_len)
      line = line_of(markdown, body_start)
      %{code: code, line: line, install?: Regex.match?(@install_regex, code)}
    end)
  end

  defp line_of(markdown, byte_offset) do
    markdown |> binary_part(0, byte_offset) |> String.split("\n") |> length()
  end

  @doc """
  Evaluates one notebook file and prints its result. Returns `:ok` or `{:error, details}`.
  """
  @spec run_file(Path.t(), keyword()) :: :ok | {:error, map()}
  def run_file(path, opts \\ []) do
    unless File.regular?(path), do: fail("livebook_not_found", "#{path} is not a file")

    runnable = path |> File.read!() |> cells() |> Enum.reject(& &1.install?)
    if runnable == [], do: fail("livebook_no_cells", "#{path} has no runnable elixir cells")

    case evaluate(path, runnable, opts) do
      {:ok, %{cells: count, output: output}} ->
        Mix.shell().info("ok   #{path} (#{count} cells)")
        if opts[:verbose] && output != "", do: Mix.shell().info(output)
        :ok

      {:error, details} ->
        Mix.shell().error("FAIL #{path}: cell #{details.cell} (line #{details.line}) #{details.kind}: #{details.message}")
        if opts[:verbose] && details.output != "", do: Mix.shell().error(details.output)
        {:error, details}
    end
  end

  # ---- evaluation --------------------------------------------------------------------------

  @spec evaluate(Path.t(), [cell()], keyword()) :: outcome()
  defp evaluate(path, runnable, opts) do
    namespace = "AshGraphLaw.LivebookRun#{System.unique_integer([:positive])}"
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    {:ok, io} = StringIO.open("")

    task = Task.async(fn -> eval_cells(path, runnable, namespace, io) end)

    result =
      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} ->
          result

        {:exit, reason} ->
          {:error, %{cell: 0, line: 0, kind: "exit", message: Exception.format_exit(reason), output: ""}}

        nil ->
          {:error, %{cell: 0, line: 0, kind: "timeout", message: "exceeded #{timeout}ms", output: ""}}
      end

    await_teardown()
    purge_namespace(namespace)
    {:ok, {_input, output}} = StringIO.close(io)
    put_output(result, output)
  end

  defp put_output({:ok, map}, output), do: {:ok, %{map | output: output}}
  defp put_output({:error, map}, output), do: {:error, %{map | output: output}}

  defp eval_cells(path, runnable, namespace, io) do
    Process.group_leader(self(), io)
    env = Code.env_for_eval(file: path)

    runnable
    |> Enum.with_index(1)
    |> Enum.reduce_while({[], env}, fn {cell, index}, {binding, env} ->
      code = String.replace(cell.code, @namespace_regex, namespace <> ".Demo")

      case eval_cell(code, cell.line, binding, env) do
        {:ok, binding, env} ->
          {:cont, {binding, env}}

        {:error, kind, message} ->
          {:halt, {:error, %{cell: index, line: cell.line, kind: kind, message: message, output: ""}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      {_binding, _env} -> {:ok, %{cells: length(runnable), output: ""}}
    end
  end

  defp eval_cell(code, line, binding, env) do
    quoted = Code.string_to_quoted!(code, file: env.file, line: line)
    {_value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)
    {:ok, binding, env}
  rescue
    exception -> {:error, "exception", format(exception)}
  catch
    :throw, value -> {:error, "throw", inspect(value)}
    :exit, reason -> {:error, "exit", Exception.format_exit(reason)}
  end

  defp format(exception) do
    Exception.format_banner(:error, exception) |> String.replace("\n", " ")
  end

  # The notebook's Pool is linked to its process; the supervisor stops with its parent. Wait for
  # the fixed names to free so the next notebook can start its own.
  defp await_teardown(attempts \\ 100) do
    busy? = Enum.any?([AshGraphLaw.Pool, AshGraphLaw.Host], &Process.whereis/1)

    if busy? and attempts > 0 do
      Process.sleep(10)
      await_teardown(attempts - 1)
    end
  end

  defp purge_namespace(namespace) do
    prefix = "Elixir." <> namespace

    for {module, _} <- :code.all_loaded(), String.starts_with?(Atom.to_string(module), prefix) do
      :code.purge(module)
      :code.delete(module)
      :code.purge(module)
    end

    :ok
  end

  # ---- engine gate -------------------------------------------------------------------------

  @spec engine_state() :: :ok | {:error, AshGraphLaw.Refusal.t()}
  defp engine_state do
    path = WasmConfig.wasm_path([])

    case File.read(path) do
      {:ok, bytes} ->
        case EngineLoad.admit(bytes, []) do
          {:ok, _admitted} -> :ok
          {:error, refusal} -> {:error, refusal}
        end

      {:error, :enoent} ->
        {:error,
         AshGraphLaw.Refusal.new(:wasm_not_vendored, "no engine at #{path}; run `mix ash_graphlaw.vendor`", %{path: path})}

      {:error, reason} ->
        {:error, AshGraphLaw.Refusal.new(:wasm_unreadable, "#{path}: #{inspect(reason)}", %{path: path})}
    end
  end

  defp check_engine!(:ok, _opts), do: :ok

  defp check_engine!({:error, %{code: :wasm_not_vendored} = refusal}, opts) do
    if opts[:allow_unvendored] do
      Mix.shell().info(
        "engine UNVENDORED (#{refusal.message}); --allow-unvendored: engine cells run their typed refusal path."
      )

      :ok
    else
      fail(refusal.code, "#{refusal.message}; or pass --allow-unvendored to run refusal paths only")
    end
  end

  defp check_engine!({:error, refusal}, _opts), do: fail(refusal.code, refusal.message)

  # ---- arguments ---------------------------------------------------------------------------

  defp parse!(argv) do
    case OptionParser.parse(argv, strict: @switches) do
      {opts, files, []} -> {opts, files}
      {_opts, _files, invalid} -> fail("invalid_options", "invalid options: #{inspect(invalid)}")
    end
  end

  @spec fail(String.t() | atom(), String.t()) :: no_return()
  defp fail(code, message), do: Mix.raise("[#{code}] #{message}")
end
