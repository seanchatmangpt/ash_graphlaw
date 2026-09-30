# Copyright 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshGraphlaw.Parity do
  # UNSUPPORTED(generator-capability): hand-written; no pack emits a capability parity task.
  @shortdoc "Fails when the typed AshGraphLaw capability set drifts from the GraphLaw engine"

  @moduledoc """
  The capability parity court.

  Steps, all real:

    1. load the generated `AshGraphLaw.Capability.Registry`;
    2. start a real `AshGraphLaw.Host` over the vendored engine and send `{"op": "capabilities"}`;
    3. run checks P1..P9 and R1 (see `AshGraphLaw.Parity`): live ops and dialects, surface and
       registry digests, the typed modules and API, the admission DSL step enum, the refusal
       vocabulary, and every `priv/graphlaw/op-examples.json` example through the typed API.

  The task never skips. A passing run is an observation about these bytes and this registry; it is
  `PARTIAL_ALIVE` at most and grants nothing. Parity against the pinned engine can legitimately
  fail until the pin is bumped to a release that carries the registry; that failure is reported,
  never masked.

  ## Usage

      mix ash_graphlaw.parity [--evidence-dir DIR] [--list] [--no-examples] [--wasm PATH]

  ## Options

    * `--evidence-dir DIR` - write the canonical-JSON `parity_report.json` into `DIR`, also when
      the court refuses;
    * `--list` - print every check id and title, then exit `0` without loading an engine;
    * `--no-examples` - do not run P9 (reported `not_run`, never `pass`);
    * `--wasm PATH` - engine bytes to load instead of the vendored ones (an explicit path is
      unpinned; `GRAPHLAW_WASM_PATH` works the same way).

  ## Exit codes

    * `0` - no check drifted.
    * `1` - refusal, raised as `Mix.Error` with a typed code in brackets:
      `[capability_parity_drift] <check ids>`, `[wasm_not_vendored]`, `[invalid_options]`,
      `[evidence_unwritable]`, or any `AshGraphLaw.Refusal` code that blocked the run.

  ## Examples

      mix ash_graphlaw.vendor && mix ash_graphlaw.parity --evidence-dir tmp/evidence
  """

  use Mix.Task

  alias AshGraphLaw.Parity

  @switches [evidence_dir: :string, list: :boolean, no_examples: :boolean, wasm: :string]

  @doc """
  Runs the task. Returns `:ok`; raises `Mix.Error` with a `[code]` prefix on refusal.
  """
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(argv) do
    opts = parse!(argv)

    if opts[:list] do
      list()
    else
      Mix.Task.run("app.start")
      court(opts)
    end
  end

  defp parse!(argv) do
    case OptionParser.parse(argv, strict: @switches) do
      {opts, [], []} -> opts
      {_opts, rest, []} -> fail("invalid_options", "unexpected arguments: #{Enum.join(rest, " ")}")
      {_opts, _rest, invalid} -> fail("invalid_options", "unknown or malformed options: #{inspect(invalid)}")
    end
  end

  defp list do
    for {id, title} <- Parity.checks(), do: Mix.shell().info("#{id}\t#{title}")
    :ok
  end

  defp court(opts) do
    run_opts =
      [examples: not Keyword.get(opts, :no_examples, false)] ++
        if(opts[:wasm], do: [wasm_path: opts[:wasm]], else: [])

    result = Parity.run(run_opts)
    report = report_of(result)
    print(report)
    write_evidence!(report, opts[:evidence_dir])

    case result do
      {:ok, _report} ->
        Mix.shell().info("GraphLaw capability parity holds (PARTIAL_ALIVE, this engine and registry only).")
        :ok

      {:error, %{refusal: refusal}} ->
        fail(refusal.code, refusal.message)
    end
  end

  defp report_of({:ok, report}), do: report
  defp report_of({:error, %{report: report}}), do: report

  defp print(report) do
    for check <- report["checks"] do
      Mix.shell().info("#{check["id"]}\t#{check["status"]}\t#{check["title"]}")
    end
  end

  defp write_evidence!(_report, nil), do: :ok

  defp write_evidence!(report, dir) do
    case Parity.write_report(report, dir) do
      {:ok, path} -> Mix.shell().info("parity report written: #{path}")
      {:error, reason} -> fail("evidence_unwritable", reason)
    end
  end

  @spec fail(atom() | String.t(), String.t()) :: no_return()
  defp fail(code, message), do: Mix.raise("[#{code}] #{message}")
end
