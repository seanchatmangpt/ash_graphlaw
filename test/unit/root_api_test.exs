# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.RootApiTest do
  @moduledoc """
  The classification surface of the generated `AshGraphLaw` root API, driven through a REAL host
  whose instance is a scripted, spec-valid WebAssembly module that answers with a chosen JSON body
  (`AshGraphLaw.Test.WasmFixtures.scripted_engine(call: {:json, text})`). The engine ignores the
  request, so these tests establish how the library turns response bytes into typed values, never
  what GraphLaw itself would answer.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test; no mocks, no stubs.
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Admitted
  alias AshGraphLaw.Test.WasmFixtures

  defp server(body) do
    start_host!(bytes: WasmFixtures.scripted_engine(call: {:json, Jason.encode!(body)}), expected_sha256: :unpinned)
  end

  @admitted %{
    "ok" => true,
    "states" => ["s0", "s1"],
    "receipts" => [%{"step" => "admit:shacl", "parent" => "s0", "child" => "s1", "authority" => "purrdf::shapes"}],
    "nquads" => "<urn:a:x> <urn:a:p> <urn:a:y> <urn:g> .\n"
  }

  describe "call/2 classification" do
    test "positive control: an \"ok\": true body is {:ok, map}" do
      assert {:ok, %{"ok" => true, "abi_version" => 1}} =
               AshGraphLaw.call(%{"op" => "capabilities"}, server: server(%{"ok" => true, "abi_version" => 1}))
    end

    test "an \"ok\": false body with an error object becomes a typed refusal, details preserved" do
      body = %{
        "ok" => false,
        "error" => %{
          "kind" => "EngineRejected",
          "message" => "the shape was violated",
          "details" => %{"code" => "NotAdmitted", "violations" => [%{"focus" => "urn:a"}]}
        }
      }

      assert {:error, %Refusal{code: :not_admitted, class: :refused_admission} = refusal} =
               AshGraphLaw.call(%{"op" => "law"}, server: server(body))

      assert refusal.message == "the shape was violated"
      assert [%{"focus" => "urn:a"}] = refusal.details["violations"]
    end

    test "top-level details are used when the error object carries none" do
      body = %{
        "ok" => false,
        "error" => %{"kind" => "Refused", "message" => "no"},
        "details" => %{"code" => "PlanRefused", "index" => 2}
      }

      assert {:error, %Refusal{code: :plan_refused, details: %{"index" => 2}}} =
               AshGraphLaw.call(%{"op" => "law"}, server: server(body))
    end

    test "a body without a boolean ok, or with ok false and no error object, is :malformed_response" do
      for body <- [%{"hello" => "world"}, %{"ok" => "yes"}, %{"ok" => false}, %{"ok" => false, "error" => "text"}] do
        assert {:error, %Refusal{code: :malformed_response, class: :refused_structure}} =
                 AshGraphLaw.call(%{"op" => "law"}, server: server(body)),
               inspect(body)
      end
    end

    test "a body that is not an object is :malformed_response" do
      assert {:error, %Refusal{code: :malformed_response}} =
               AshGraphLaw.call(%{"op" => "law"}, server: server([1, 2, 3]))
    end

    test "host failures pass through as their own typed refusals" do
      trapping = start_host!(bytes: WasmFixtures.scripted_engine(call: :trap), expected_sha256: :unpinned)
      assert {:error, %Refusal{code: :call_trapped}} = AshGraphLaw.call(%{"op" => "law"}, server: trapping)
    end
  end

  describe "law/3" do
    test "an admitted body is wrapped in %Admitted{}, unchanged in its states and receipts" do
      assert {:ok, %Admitted{states: ["s0", "s1"], receipts: [receipt]}} =
               AshGraphLaw.law("<urn:a:x> <urn:a:p> <urn:a:y> .", [%{"step" => "shacl"}], server: server(@admitted))

      assert receipt.step == "admit:shacl"
      assert receipt.parent == "s0"
    end

    test "a refusal stays a refusal" do
      body = %{
        "ok" => false,
        "error" => %{"kind" => "Refused", "message" => "no"},
        "details" => %{"code" => "NotAdmitted"}
      }

      assert {:error, %Refusal{code: :not_admitted}} =
               AshGraphLaw.law(%{"text" => "x", "dialect" => "ntriples"}, [], server: server(body))
    end
  end

  describe "the other operations share the same classification" do
    test "capabilities/1, sniff/3 and hooks/3 return the engine's map" do
      s = server(%{"ok" => true, "answer" => 42})

      assert {:ok, %{"answer" => 42}} = AshGraphLaw.capabilities(server: s)
      assert {:ok, %{"answer" => 42}} = AshGraphLaw.sniff("<a> <b> <c> .", "nt", server: s)
      assert {:ok, %{"answer" => 42}} = AshGraphLaw.sniff("<a> <b> <c> .", nil, server: s)
      assert {:ok, %{"answer" => 42}} = AshGraphLaw.hooks("data text", %{"text" => "pack"}, server: s)
    end
  end

  describe "engine identity" do
    test "engine_sha256/1 names the engine bytes behind the server, and is nil when none is live" do
      bytes = WasmFixtures.scripted_engine(call: {:json, ~s({"ok":true})})
      host = start_host!(bytes: bytes, expected_sha256: :unpinned)

      assert AshGraphLaw.engine_sha256(server: host) == WasmFixtures.sha256(bytes)
      assert AshGraphLaw.engine_sha256(server: :agl_no_such_host) == nil
      assert AshGraphLaw.engine_sha256() == nil
    end

    test "abi_version/0 and graphlaw_release/0 are the pinned identity" do
      assert AshGraphLaw.abi_version() == 1
      assert AshGraphLaw.graphlaw_release() == "26.9.28"
    end
  end
end
