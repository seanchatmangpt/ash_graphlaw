# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshGraphlaw.Mutate do
  @shortdoc "Runs the anti-vacuity mutation catalog against the negative and adversarial tests"

  @moduledoc """
  Development tooling. UNSUPPORTED(generator-capability): hand-written; no pack template emits a
  mutation court.

  Hot-loads each `AshGraphLaw.Mutation.Catalog` mutant into this checkout, runs the killer tests
  (`test/negative/**`, `test/adversarial/**`) in this VM, restores the original BEAM and reports
  `mutant_killed | mutant_survived | blocked | unknown`.

      MIX_ENV=test mix ash_graphlaw.mutate
      MIX_ENV=test mix ash_graphlaw.mutate --only AGL-MUT-002 --only AGL-MUT-004
      MIX_ENV=test mix ash_graphlaw.mutate --list
      MIX_ENV=test mix ash_graphlaw.mutate --evidence-dir tmp/mutations --require-killed

  Run it with `MIX_ENV=test` so `test/support` is compiled; the task requests that environment
  itself when invoked from `mix` directly.

  Options:

    * `--only ID` - restrict to a catalog id (repeatable)
    * `--evidence-dir DIR` - where `mutation_report.json` is written (default: a fresh tmp dir)
    * `--list` - print `id`, target and `resolvable | BLOCKED code` per entry; loads nothing
    * `--require-killed` - exit non-zero unless every selected verdict is `mutant_killed`

  ## Exit codes

    * `0` - the run completed (and, with `--require-killed`, every selected verdict was
      `mutant_killed`); also `--list`.
    * `1` - `Mix.Error`: invalid options, unknown ids, a module left mutated after the run, or
      (`--require-killed`) any verdict other than `mutant_killed`.

  Without `--require-killed` a surviving mutant is reported, not failed: read the tally.

  ## Anti-vacuity

  A killer test that still passes after the guard it attacks is deleted proves nothing. Reverting
  a guard and requiring the killers to fail is what makes the `test/negative/**` and
  `test/adversarial/**` suites falsifiable. See `AshGraphLaw.Mutation`.

  ## Examples

      # qualify the whole catalog and fail the build on any survivor
      MIX_ENV=test mix ash_graphlaw.mutate --require-killed

      # one mutant, evidence written to a chosen directory
      MIX_ENV=test mix ash_graphlaw.mutate --only AGL-MUT-004 --evidence-dir tmp/mutations

  The report is canonical JSON (sorted keys). After the run the task asserts that no catalog
  module is left mutated and raises otherwise. A baseline that is not green (killer tests failing
  before any mutation) yields `unknown`, never a pass. `:wasm`-tagged killers are excluded, with a
  printed stderr line, when no engine binary is vendored.
  """

  use Mix.Task

  alias AshGraphLaw.Mutation
  alias AshGraphLaw.Mutation.{Catalog, Verdict}

  @preferred_cli_env :test
  @switches [only: :keep, evidence_dir: :string, list: :boolean, require_killed: :boolean]

  @doc """
  Runs the task with raw `argv`. Returns `:ok`; raises `Mix.Error` on refusal.
  """
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(argv) do
    {opts, _rest, invalid} = OptionParser.parse(argv, strict: @switches)
    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    Mix.Task.run("app.start")

    only = Keyword.get_values(opts, :only)
    unknown = only -- Catalog.ids()

    if unknown != [],
      do: Mix.raise("unknown mutation ids #{inspect(unknown)}; known: #{inspect(Catalog.ids())}")

    if opts[:list], do: list(only), else: execute(only, opts)
    :ok
  end

  defp selected(only), do: Enum.filter(Catalog.entries(), &(only == [] or &1.id in only))

  defp list(only) do
    for entry <- Catalog.resolution(), only == [] or entry.id in only do
      Mix.shell().info(
        Enum.join(
          [entry.id, entry.target, status(entry.target_status), "killer_files=#{length(entry.killer_files)}"],
          "\t"
        )
      )
    end

    :ok
  end

  defp status(:resolvable), do: "resolvable"
  defp status({:blocked, code, _detail}), do: "BLOCKED #{code}"

  defp execute(only, opts) do
    root = evidence_root(opts)
    mutations = selected(only)

    {verdicts, _cache} =
      Enum.map_reduce(mutations, %{}, fn mutation, cache ->
        {baseline_opts, cache} = baseline_for(mutation, cache)
        verdict = Mutation.qualify(mutation, baseline_opts)
        Mix.shell().info(verdict_line(verdict))
        {verdict, cache}
      end)

    File.mkdir_p!(root)
    report = Path.join(root, "mutation_report.json")
    File.write!(report, Verdict.canonical_json(verdicts))

    tally = Verdict.tally(verdicts)
    Mix.shell().info("tally: #{inspect(tally)}")
    Mix.shell().info("report: #{report}")

    assert_pristine(mutations)
    if opts[:require_killed], do: require_killed(verdicts, tally)
    :ok
  end

  defp evidence_root(opts) do
    case opts[:evidence_dir] do
      nil -> Path.join(System.tmp_dir!(), "ash_graphlaw-mutate-#{System.unique_integer([:positive])}")
      dir -> Path.expand(dir)
    end
  end

  # One baseline per distinct killer file set, computed only for mutations whose target resolves.
  defp baseline_for(mutation, cache) do
    with {:ok, files, _missing} <- Mutation.resolve_killers(mutation),
         {:ok, _plan} <- Mutation.prepare(mutation) do
      case Map.fetch(cache, files) do
        {:ok, baseline} ->
          {[baseline: baseline], cache}

        :error ->
          baseline = Mutation.baseline(files)
          {[baseline: baseline], Map.put(cache, files, baseline)}
      end
    else
      _blocked -> {[], cache}
    end
  end

  defp verdict_line(%Verdict{} = v) do
    Enum.join(
      [String.upcase(to_string(v.verdict)), v.mutation_id, v.target, "calls=#{inspect(v.mutant_calls)}", v.detail],
      "\t"
    )
  end

  defp assert_pristine(mutations) do
    unpristine =
      mutations
      |> Enum.map(& &1.module)
      |> Enum.uniq()
      |> Enum.filter(&Code.ensure_loaded?/1)
      |> Enum.reject(&Mutation.pristine?/1)

    if unpristine != [], do: Mix.raise("modules left mutated: #{inspect(unpristine)}")
  end

  defp require_killed(verdicts, tally) do
    if Enum.any?(verdicts, &(&1.verdict != :mutant_killed)),
      do: Mix.raise("not every selected mutant was killed: #{inspect(tally)}")
  end
end
