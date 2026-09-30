# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Unit.RefusalRawTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago court over the lossless :raw field.
  use ExUnit.Case, async: true

  alias AshGraphLaw.Error
  alias AshGraphLaw.Error.Refused
  alias AshGraphLaw.Refusal

  # Every engine error shape graphlaw's src/abi.rs can emit: a generic refusal by kind, and one
  # payload per details.code.
  @kinds ~w(NotSemanticContent Ambiguous EngineRejected Unsupported ResourceLimit)
  @detail_codes ~w(Refused ResourceLimit PlanRefused ReceiptRequired ReceiptRefused LeaseRefused
                   NotAdmitted UnverifiedLeaseRefused PolicyRefused)

  defp kind_payload(kind) do
    %{
      "ok" => false,
      "kind" => kind,
      "message" => "refused #{kind}",
      "engine" => "PurRdf",
      "dialect" => "Turtle",
      "details" => %{"code" => "Refused", "future_field" => [1, 2]}
    }
  end

  defp code_payload(code) do
    %{"ok" => false, "message" => "m #{code}", "details" => %{"code" => code, "reason" => "expired"}}
  end

  describe "positive control" do
    test "a client-side refusal has raw nil and an engine refusal keeps its whole map" do
      assert %Refusal{raw: nil} = Refusal.new(:not_admitted)
      payload = kind_payload("Ambiguous")
      assert %Refusal{raw: ^payload, code: :engine_refused, kind: "Ambiguous"} = Refusal.from_engine(payload)
    end
  end

  describe "from_engine/2 keeps raw == error map" do
    test "for every engine kind" do
      for kind <- @kinds do
        payload = kind_payload(kind)
        refusal = Refusal.from_engine(payload)
        assert refusal.raw == payload, "raw of kind #{kind}"
        assert refusal.code in Refusal.codes()
        assert refusal.code != :engine_unclassified, "kind #{kind}"
      end
    end

    test "for every details.code, and none maps to :engine_unclassified" do
      for code <- @detail_codes do
        payload = code_payload(code)
        refusal = Refusal.from_engine(payload)
        assert refusal.raw == payload, "raw of #{code}"
        assert refusal.code != :engine_unclassified, "details.code #{code}"
      end
    end

    test "the documented details.code mapping is unchanged" do
      expected = %{
        "NotAdmitted" => :not_admitted,
        "PlanRefused" => :plan_refused,
        "ReceiptRequired" => :receipt_required,
        "ReceiptRefused" => :receipt_required,
        "LeaseRefused" => :lease_refused,
        "UnverifiedLeaseRefused" => :lease_refused,
        "ResourceLimit" => :resource_limit,
        "PolicyRefused" => :policy_refused
      }

      for {name, code} <- expected, do: assert(Refusal.from_engine(code_payload(name)).code == code)
    end

    test "unknown keys are merged into details and also kept in raw" do
      payload = %{"kind" => "Unsupported", "details" => %{"code" => "Refused", "extra" => 1}, "novel" => "x"}
      refusal = Refusal.from_engine(payload, %{"caller" => true})
      assert refusal.details == %{"code" => "Refused", "extra" => 1, "caller" => true}
      assert refusal.raw == payload
    end

    test "unknown codes stay :engine_unclassified with raw kept" do
      payload = %{"kind" => "Future", "details" => %{"code" => "FutureCode"}}
      assert %Refusal{code: :engine_unclassified, raw: ^payload} = Refusal.from_engine(payload)
    end

    test "non-map errors keep details[raw] and have raw nil" do
      assert %Refusal{code: :engine_unclassified, raw: nil, details: %{"raw" => ":garbage"}} =
               Refusal.from_engine(:garbage)
    end
  end

  describe "build/3" do
    test "positive control: builds from the closed table with raw nil" do
      refusal = Refusal.build(:not_admitted, "no", %{"k" => 1})
      assert %Refusal{code: :not_admitted, message: "no", details: %{"k" => 1}, raw: nil} = refusal
      assert refusal.class == Refusal.class_of(:not_admitted)
    end

    test "details default to an empty map" do
      assert %Refusal{details: %{}} = Refusal.build(:not_admitted, "no")
    end

    test "an unknown code raises ArgumentError" do
      assert_raise ArgumentError, fn -> Refusal.build(:bogus, "x") end
    end
  end

  describe "Error wrapping carries raw" do
    test "Refused.raw/1 and Error.raws/1 expose the engine map" do
      payload = code_payload("NotAdmitted")
      refused = Refused.exception(refusal: Refusal.from_engine(payload))
      assert Refused.raw(refused) == payload
      assert Error.raws([refused, Refusal.build(:not_admitted, "client")]) == [payload]
      assert Refused.raw(%Refused{refusal: nil}) == nil
    end
  end
end
