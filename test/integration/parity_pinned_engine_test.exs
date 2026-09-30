# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Integration.ParityPinnedEngineTest do
  @moduledoc """
  The parity court against the VENDORED, PINNED engine (tag `:wasm`).

  Nothing here hardcodes a pass. The pinned engine is v26.9.28, which predates the registry
  (v26.9.29): it may legitimately drift from the generated registry until the pin is bumped. This
  test therefore asserts the report is produced and is honest in either case:

    * the report names the pinned engine digest;
    * every check id is present with a status;
    * `{:ok, _}` holds exactly when no check drifted; `{:error, drift}` names exactly the drifted
      check ids, each with evidence and a broken term;
    * the standing is never `ALIVE`.

  Observation, 2026-09-29: recorded by running this file, not asserted here; see the test output.

  UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks.
  """

  use AshGraphLaw.Test.Case

  alias AshGraphLaw.Parity
  alias AshGraphLaw.Refusal
  alias AshGraphLaw.WasmConfig

  @moduletag :wasm

  setup_all do
    {:ok, result: Parity.run([])}
  end

  defp report_of({:ok, report}), do: report
  defp report_of({:error, %{report: report}}), do: report

  test "the report names the pinned engine and every check id", %{result: result} do
    report = report_of(result)

    assert report["engine"]["wasm_sha256"] == WasmConfig.pinned_sha256()
    assert report["engine"]["pinned"] == true
    assert Enum.map(report["checks"], & &1["id"]) == Parity.check_ids()
    assert Enum.all?(report["checks"], &(&1["status"] in ["pass", "drift", "not_run"]))
  end

  test "the verdict is exactly the drifted checks, with evidence", %{result: result} do
    report = report_of(result)
    drifted = for %{"status" => "drift", "id" => id} <- report["checks"], do: id

    assert report["drift"] == drifted

    case result do
      {:ok, _report} ->
        assert drifted == []
        assert report["status"] == "PASS"

      {:error, %{refusal: %Refusal{code: :capability_parity_drift} = refusal}} ->
        # Honest drift of the pinned v26.9.28 engine (or of the typed surface) against the registry.
        assert drifted != []
        assert refusal.message == Enum.join(drifted, " ")
        assert report["status"] == "DRIFT"

        for check <- report["checks"], check["status"] == "drift" do
          assert is_map(check["evidence"]) and map_size(check["evidence"]) > 0
          assert is_binary(check["broken_term"])
        end
    end
  end

  test "the standing is at most PARTIAL_ALIVE", %{result: result} do
    report = report_of(result)
    assert report["standing"] in ["PARTIAL_ALIVE", "REFUSED"]
    refute report["standing"] == "ALIVE"
  end
end
