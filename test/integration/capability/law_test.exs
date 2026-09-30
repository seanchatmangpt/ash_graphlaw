# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written Chicago test against the real engine.

defmodule AshGraphLaw.Integration.Capability.LawTest do
  @moduledoc """
  Typed `law` against the REAL engine. `law` decodes to the existing `AshGraphLaw.Admitted`
  (an OpBinding `bindingResultModule` override), so there is no `AshGraphLaw.Result.Law`. Refusals
  map onto the specific typed atoms through `details.code`.
  """
  use AshGraphLaw.Test.CapabilityCase

  alias AshGraphLaw.Admitted

  @moduletag :wasm
  @moduletag :slow

  setup do
    {:ok, opts: engine_opts!()}
  end

  describe "positive control" do
    test "shacl+n3 is admitted and decodes to %Admitted{} equal to the legacy law/3 result", %{opts: opts} do
      example = example!("law.shacl-n3")
      assert {:ok, %Admitted{} = typed} = API.law(args_of(example), opts)
      assert {:ok, raw} = raw("law", args_of(example), opts)
      assert typed.states == raw["states"]
      assert typed.nquads == raw["nquads"]
      assert length(typed.receipts) == length(raw["receipts"])

      request = example["request"]
      assert {:ok, %Admitted{} = legacy} = AshGraphLaw.law(request["data"], request["steps"], opts)
      assert legacy.states == typed.states
      assert legacy.nquads == typed.nquads
    end

    test "there is no Result.Law module (law's result module is the OpBinding override)" do
      refute Code.ensure_loaded?(AshGraphLaw.Result.Law)
      assert Code.ensure_loaded?(AshGraphLaw.Admitted)
    end

    test "every ok example is admitted", %{opts: opts} do
      for {example, result} <- run_examples("law", "ok", opts) do
        assert {:ok, %Admitted{states: [_ | _]}} = result, example["id"]
      end
    end

    test "lease fields are ordinary args (unverified lease with an explicit clock)", %{opts: opts} do
      example = example!("law.leased-shacl-n3-plan")
      args = args_of(example)
      assert args["unverified_lease"] == true
      assert is_integer(args["now_unix"])
      assert {:ok, %Admitted{}} = API.law(args, opts)
    end

    test "law determinism: identical args yield identical typed results", %{opts: opts} do
      args = args_of(example!("law.rdfs"))
      assert {:ok, one} = API.law(args, opts)
      assert {:ok, two} = API.law(args, opts)
      assert one == two
    end
  end

  describe "refusals map to the specific typed atoms" do
    test "shacl not admitted -> :not_admitted", %{opts: opts} do
      example = example!("law.shacl-not-admitted-refused")
      assert_refusal(API.law(args_of(example), opts), :not_admitted, wire_code: "NotAdmitted")
    end

    test "plan precondition -> :plan_refused", %{opts: opts} do
      example = example!("law.plan-precondition-refused")
      assert_refusal(API.law(args_of(example), opts), :plan_refused, wire_code: "PlanRefused")
    end

    test "require-receipt without a receipt -> :receipt_required", %{opts: opts} do
      example = example!("law.receipt-required-refused")
      assert_refusal(API.law(args_of(example), opts), :receipt_required, wire_code: "ReceiptRequired")
    end

    test "expired lease and ceiling -> :lease_refused", %{opts: opts} do
      for id <- ["law.lease-expired-refused", "law.lease-ceiling-refused"] do
        assert_refusal(API.law(args_of(example!(id)), opts), :lease_refused, wire_code: "LeaseRefused")
      end
    end

    test "an unsigned lease without opt-in -> :lease_refused (UnverifiedLeaseRefused)", %{opts: opts} do
      example = example!("law.unverified-lease-refused")
      assert_refusal(API.law(args_of(example), opts), :lease_refused, wire_code: "UnverifiedLeaseRefused")
    end

    test "an unknown step is a generic engine refusal (Unsupported)", %{opts: opts} do
      example = example!("law.unknown-step-refused")
      assert_refusal(API.law(args_of(example), opts), :engine_refused, kind: "Unsupported")
    end

    test "every refused example maps to the atom expected_code/1 derives from its wire code", %{opts: opts} do
      for {example, result} <- run_examples("law", "refused", opts) do
        assert_refusal(result, expected_code(example["refusal_code"]), kind: example["refusal_kind"])
      end
    end

    test "every refusal keeps the whole engine error in :raw", %{opts: opts} do
      example = example!("law.plan-precondition-refused")
      assert {:error, refusal} = API.law(args_of(example), opts)
      assert is_binary(refusal.raw["kind"])
      assert refusal.raw["kind"] == "EngineRejected"
      assert refusal.raw["details"]["code"] == "PlanRefused"
    end
  end

  describe "client-side refusals" do
    test "missing data and steps are both named", %{opts: opts} do
      refusal = assert_refusal(API.law(%{}, opts), :invalid_capability_request)
      assert Enum.sort(refusal.details["missing"]) == ["data", "steps"]
    end

    test "steps of the wrong type are a client type error", %{opts: opts} do
      refusal =
        assert_refusal(API.law(%{data: "<urn:a> <urn:b> <urn:c> .", steps: "rdfs"}, opts), :invalid_capability_request)

      assert [%{"field" => "steps", "expected" => "list<object>"}] = refusal.details["type_errors"]
    end
  end
end
