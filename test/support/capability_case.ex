# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.CapabilityCase do
  @moduledoc """
  UNSUPPORTED(generator-capability): shared helpers for the real-engine typed capability tests.

  Everything here talks to the REAL vendored GraphLaw engine through a real `AshGraphLaw.Host`.
  Nothing is stubbed. The helpers are thin:

    * `engine_opts!/0` starts a real host under the test supervisor and returns
      `[server: pid]`, the same opts `AshGraphLaw.call/2` and every typed capability accept;
      it fails closed through `AshGraphLaw.Test.Case.require_engine!/0`;
    * `registry/0` and `examples/0` decode `priv/graphlaw/capability-registry.json` and
      `priv/graphlaw/op-examples.json` with Jason (falling back to the sibling `../graphlaw/registry`
      checkout until `scripts/vendor_registry.sh` has run);
    * `api/3`, `raw/3` and `capability/1` drive one op through `AshGraphLaw.Capability.API`, through
      `AshGraphLaw.call/2` and to its `AshGraphLaw.Capability.<Op>` module;
    * `expected_code/1` maps an engine `details.code` to the typed refusal atom.

  Module names are resolved at run time (`Module.concat/1`), so this file compiles before the
  generated capability modules exist.
  """

  use ExUnit.CaseTemplate

  alias AshGraphLaw.Test.Case, as: EngineCase

  @sample_turtle ~S(@prefix ex: <https://e/> . ex:s ex:p ex:o, "café"@fr, 42 ; a ex:T .)
  @nine_dialect_names ~w(turtle trig ntriples nquads rdfxml jsonld yamlld trix hextuples)

  using do
    quote do
      use AshGraphLaw.Test.Case, async: false

      import AshGraphLaw.Test.CapabilityCase

      alias AshGraphLaw.Capability.API
      alias AshGraphLaw.Test.CapabilityCase
    end
  end

  @doc "The sample Turtle graph (one IRI, a language-tagged literal, an integer, a typed node)."
  @spec sample_turtle() :: String.t()
  def sample_turtle, do: @sample_turtle

  @doc "The nine dialect names `convert` writes (`rdf_dialects` of the registry)."
  @spec target_dialects() :: [String.t()]
  def target_dialects, do: @nine_dialect_names

  @doc """
  Starts a real host and returns call opts `[server: pid]`.

  Fails closed: with `ASH_GRAPHLAW_REQUIRE_ENGINE` set an unusable engine raises; without it the
  test is flunked with the named reason, never silently passed.
  """
  @spec engine_opts!() :: keyword()
  def engine_opts! do
    if EngineCase.require_engine!() do
      [server: EngineCase.start_host!()]
    else
      ExUnit.Assertions.flunk("real engine unavailable at #{EngineCase.wasm_path()}; run `mix ash_graphlaw.vendor`")
    end
  end

  @doc "Decoded registry JSON (string keys)."
  @spec registry() :: map()
  def registry, do: read_json("capability-registry.json")

  @doc "Decoded op-examples JSON (string keys)."
  @spec examples() :: map()
  def examples, do: read_json("op-examples.json")

  @doc "The registry op names, in registry order."
  @spec op_names() :: [String.t()]
  def op_names, do: Enum.map(registry()["ops"], & &1["name"])

  @doc "The registry entry of `op` (raises when absent)."
  @spec registry_op(String.t()) :: map()
  def registry_op(op), do: Enum.find(registry()["ops"], &(&1["name"] == op)) || raise("no registry op #{op}")

  @doc "The examples of `op`, in file order."
  @spec examples_for(String.t()) :: [map()]
  def examples_for(op), do: Enum.filter(examples()["examples"], &(&1["op"] == op))

  @doc "One example by id."
  @spec example!(String.t()) :: map()
  def example!(id), do: Enum.find(examples()["examples"], &(&1["id"] == id)) || raise("no example #{id}")

  @doc "An example's request as typed args: the request minus `op`."
  @spec args_of(map()) :: map()
  def args_of(%{"request" => request}), do: Map.delete(request, "op")

  @doc "`AshGraphLaw.Capability.<Op>` for the op name."
  @spec capability(String.t()) :: module()
  def capability(op), do: Module.concat([AshGraphLaw.Capability, String.capitalize(op)])

  @doc "`AshGraphLaw.Result.<Op>` for the op name."
  @spec result_module(String.t()) :: module()
  def result_module(op), do: Module.concat([AshGraphLaw.Result, String.capitalize(op)])

  @doc "Runs `op` through `AshGraphLaw.Capability.API.<op>/2`."
  @spec typed(String.t(), map() | keyword(), keyword()) :: {:ok, term()} | {:error, AshGraphLaw.Refusal.t()}
  def typed(op, args, opts), do: apply(AshGraphLaw.Capability.API, String.to_atom(op), [args, opts])

  @doc "Runs `op` through `AshGraphLaw.Capability.API.<op>!/2`."
  @spec typed!(String.t(), map() | keyword(), keyword()) :: term()
  def typed!(op, args, opts), do: apply(AshGraphLaw.Capability.API, String.to_atom("#{op}!"), [args, opts])

  @doc "Runs the op through `AshGraphLaw.Capability.<Op>.run/2` (the module the API delegates to)."
  @spec via_module(String.t(), map() | keyword(), keyword()) :: {:ok, term()} | {:error, AshGraphLaw.Refusal.t()}
  def via_module(op, args, opts), do: capability(op).run(args, opts)

  @doc "The untyped engine answer for the same args: `AshGraphLaw.call/2` on the built request."
  @spec raw(String.t(), map() | keyword(), keyword()) :: {:ok, map()} | {:error, AshGraphLaw.Refusal.t()}
  def raw(op, args, opts) do
    with {:ok, request} <- capability(op).build_request(args), do: AshGraphLaw.call(request, opts)
  end

  @doc "The request the typed layer builds for `args`."
  @spec built(String.t(), map() | keyword()) :: {:ok, map()} | {:error, AshGraphLaw.Refusal.t()}
  def built(op, args), do: capability(op).build_request(args)

  @doc "Typed refusal atom for an engine `details.code` (`nil` = generic engine refusal)."
  @spec expected_code(String.t() | nil) :: atom()
  def expected_code(nil), do: :engine_refused
  def expected_code("Refused"), do: :engine_refused
  def expected_code("NotAdmitted"), do: :not_admitted
  def expected_code("PlanRefused"), do: :plan_refused
  def expected_code("ReceiptRequired"), do: :receipt_required
  def expected_code("ReceiptRefused"), do: :receipt_required
  def expected_code("LeaseRefused"), do: :lease_refused
  def expected_code("UnverifiedLeaseRefused"), do: :lease_refused
  def expected_code("PolicyRefused"), do: :policy_refused
  def expected_code("ResourceLimit"), do: :resource_limit

  @doc """
  Positive control shared by every op: the typed result is a struct of `result_module(op)` whose
  `:raw` is EXACTLY the map `AshGraphLaw.call/2` returns for the same built request.
  """
  @spec assert_typed_matches_raw(String.t(), map() | keyword(), keyword()) :: struct()
  def assert_typed_matches_raw(op, args, opts) do
    import ExUnit.Assertions

    assert {:ok, raw} = raw(op, args, opts)
    assert {:ok, result} = typed(op, args, opts)
    expected = result_module(op)
    assert %{__struct__: ^expected} = result
    assert result.raw == raw
    assert raw["ok"] == true
    result
  end

  @doc "Asserts `{:error, refusal}` with the typed atom, the engine kind and (optionally) the wire code."
  @spec assert_refusal(term(), atom(), keyword()) :: AshGraphLaw.Refusal.t()
  def assert_refusal(result, code, expect \\ []) do
    import ExUnit.Assertions

    assert {:error, %AshGraphLaw.Refusal{} = refusal} = result
    assert refusal.code == code
    assert refusal.class == AshGraphLaw.Refusal.class_of(code)

    if kind = expect[:kind], do: assert(refusal.kind == kind)
    if wire = expect[:wire_code], do: assert(refusal.details["code"] == wire)
    refusal
  end

  @doc "Runs every example of `op` whose outcome is `outcome` through the typed API, returning `{example, result}`."
  @spec run_examples(String.t(), String.t(), keyword()) :: [{map(), term()}]
  def run_examples(op, outcome, opts) do
    for example <- examples_for(op), example["outcome"] == outcome do
      {example, typed(op, args_of(example), opts)}
    end
  end

  defp read_json(name) do
    priv = Path.join([File.cwd!(), "priv", "graphlaw", name])
    sibling = Path.join([File.cwd!(), "..", "graphlaw", "registry", name])

    path = if File.exists?(priv), do: priv, else: sibling
    path |> File.read!() |> Jason.decode!()
  end
end
