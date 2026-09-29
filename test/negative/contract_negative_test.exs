# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L17. UNSUPPORTED(generator-capability): no pack emits negative courts.

defmodule AshGraphLaw.Negative.ContractNegativeTest do
  @moduledoc """
  Negative court for the DSL legality contract.

  Resources are compiled for real with `Code.compile_quoted/2`; a violating `graphlaw`
  section must fail compilation with a `Spark.Error.DslError` that names the refusal code.
  Every negative has a positive control: the same resource shape with the violation
  removed compiles. `AshGraphLaw.Contract.validate/1` is also driven directly so the exact
  refusal code is pinned even when Spark rejects a shape earlier than the verifier does.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshGraphLaw.Contract
  alias AshGraphLaw.Dsl.{Admission, Runtime}

  # Verifier errors raised inside Spark's @after_verify hook never propagate as exceptions: Spark
  # prints them to stderr as warnings, and the hook runs in Elixir's parallel checker process, so
  # the per-process `Spark.Test.dsl_errors/1` collector never sees them. The observable behavior of a
  # refused section is therefore its stderr, which carries the full `Spark.Error.DslError` text.
  defp compile(section_body) do
    module = "AshGraphLaw.Negative.Compiled#{System.unique_integer([:positive])}"

    source = """
    defmodule #{module} do
      use Ash.Resource,
        domain: AshGraphLaw.Test.Domain,
        validate_domain_inclusion?: false,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshGraphLaw.Resource]

      attributes do
        uuid_primary_key :id
      end

      graphlaw do
    #{section_body}
      end
    end
    """

    quoted = Code.string_to_quoted!(source)

    # Ash also compiles an `Inspect.<Resource>` impl into the same call, so the resource is
    # picked by name, never by position.
    mod = Module.concat([module])

    stderr =
      capture_io(:stderr, fn ->
        [_ | _] = Code.compile_quoted(quoted, "contract_negative_test.exs")
      end)

    errors = if stderr =~ "Spark.Error.DslError", do: [stderr], else: []

    on_exit(fn ->
      :code.purge(mod)
      :code.delete(mod)
    end)

    {mod, errors}
  end

  # A section the verifier accepts: returns the compiled module.
  defp compile!(section_body) do
    {mod, messages} = compile(section_body)
    assert messages == [], "expected the section to verify, got: #{inspect(messages)}"
    mod
  end

  # A section the verifier refuses: returns every error message, joined.
  defp refused_message(section_body) do
    {_mod, messages} = compile(section_body)
    assert messages != [], "expected the verifier to refuse the section, but it verified"
    Enum.join(messages, "\n")
  end

  describe "compiled resources" do
    test "positive control: a lawful section compiles and exposes its admission" do
      mod =
        compile!("""
            runtime do
              timeout_ms 1000
            end

            admission :shape do
              step :shacl
              law AshGraphLaw.Test.ShapeLaw
            end
        """)

      assert [%Admission{name: :shape, step: :shacl}] = AshGraphLaw.Admissions.all(mod)
    end

    test "a duplicate admission name is refused at compile time" do
      message =
        refused_message("""
            admission :dup do
              step :rdfs
            end

            admission :dup do
              step :owl_rl
            end
        """)

      assert message =~ ~r/duplicate/i
    end

    test "a payload step without a law module is refused with missing_law_module" do
      # control: the payload-free step needs no law module
      assert compile!("""
                 admission :entail do
                   step :rdfs
                 end
             """)

      message =
        refused_message("""
            admission :plan_only do
              step :plan
            end
        """)

      assert message =~ "missing_law_module"
    end

    test "a law module that does not exist is refused at compile time, not at the first action" do
      # control: the same admission with a real law module verifies
      assert compile!("""
                 admission :ticket_shape do
                   step :shacl
                   law AshGraphLaw.Test.ShapeLaw
                 end
             """)

      message =
        refused_message("""
            admission :ghost do
              step :shacl
              law AshGraphLaw.Test.NoSuchLaw
            end
        """)

      assert message =~ "missing_law_module"
      assert message =~ "AshGraphLaw.Test.NoSuchLaw"
    end

    test "a malformed trusted key is refused with invalid_trusted_key" do
      key = String.duplicate("ab", 32)

      assert compile!("""
                 runtime do
                   trusted_keys ["#{key}"]
                 end
             """)

      message =
        refused_message("""
            runtime do
              trusted_keys ["not-hex"]
            end
        """)

      assert message =~ "invalid_trusted_key"
    end

    test "timeout_ms 0 is refused with invalid_runtime_option" do
      assert compile!("""
                 runtime do
                   timeout_ms 1
                 end
             """)

      message =
        refused_message("""
            runtime do
              timeout_ms 0
            end
        """)

      assert message =~ "invalid_runtime_option"
    end
  end

  describe "Contract.validate/1 pins the exact codes" do
    defp compiled(entities), do: %{graphlaw: entities}
    defp codes({:error, refusals}), do: Enum.map(refusals, & &1.code)

    test "positive control: an empty and a lawful state validate" do
      assert :ok = Contract.validate(compiled([]))

      assert :ok =
               Contract.validate(
                 compiled([
                   %Runtime{},
                   %Admission{name: :a, step: :shacl, law: AshGraphLaw.Test.ShapeLaw},
                   %Admission{name: :b, step: :rdfs}
                 ])
               )
    end

    test "duplicate names" do
      result =
        Contract.validate(compiled([%Admission{name: :a, step: :rdfs}, %Admission{name: :a, step: :owl_rl}]))

      assert codes(result) == [:duplicate_admission]
    end

    test "every payload step needs a law module; rdfs and owl_rl do not" do
      for step <- Contract.payload_steps() do
        assert codes(Contract.validate(compiled([%Admission{name: :x, step: step}]))) == [:missing_law_module],
               "step #{step} must require a law module"
      end

      for step <- [:rdfs, :owl_rl] do
        assert :ok = Contract.validate(compiled([%Admission{name: :x, step: step}]))
      end
    end

    test "trusted keys must be 64 hex characters" do
      good = String.duplicate("0f", 32)
      assert :ok = Contract.validate(compiled([%Runtime{trusted_keys: [good, String.upcase(good)]}]))

      for bad <- ["", "zz", String.duplicate("a", 63), String.duplicate("a", 65), String.duplicate("g", 64), 42, nil] do
        assert codes(Contract.validate(compiled([%Runtime{trusted_keys: [bad]}]))) == [:invalid_trusted_key],
               "#{inspect(bad)} must be refused"
      end

      assert codes(Contract.validate(compiled([%Runtime{trusted_keys: "not-a-list"}]))) == [:invalid_trusted_key]
    end

    test "fail-closed: a compiled state that is not a map with a :graphlaw list is refused, never :ok" do
      assert :ok = Contract.validate(compiled([]))

      for malformed <- [%{}, %{graphlaw: nil}, %{graphlaw: :nope}, %{other: []}, nil, [], "compiled", 42] do
        assert {:error, [%{code: :invalid_runtime_option, detail: detail}]} = Contract.validate(malformed)
        assert detail =~ "compiled state is malformed"
      end
    end

    test "a law module must exist and export steps/2" do
      # positive control: a real law module
      assert :ok = Contract.validate(compiled([%Admission{name: :ok, step: :shacl, law: AshGraphLaw.Test.ShapeLaw}]))

      assert {:error, [%{code: :missing_law_module, detail: absent}]} =
               Contract.validate(compiled([%Admission{name: :gone, step: :shacl, law: AshGraphLaw.Test.NoSuchLaw}]))

      assert absent =~ "AshGraphLaw.Test.NoSuchLaw"
      assert absent =~ "not available"

      assert {:error, [%{code: :missing_law_module, detail: no_steps}]} =
               Contract.validate(compiled([%Admission{name: :bad, step: :shacl, law: Enum}]))

      assert no_steps =~ "does not export steps/2"
    end

    test "runtime bounds: timeout_ms > 0 and max_skew_secs >= 0" do
      assert :ok = Contract.validate(compiled([%Runtime{timeout_ms: 1, max_skew_secs: 0}]))

      assert codes(Contract.validate(compiled([%Runtime{timeout_ms: 0}]))) == [:invalid_runtime_option]
      assert codes(Contract.validate(compiled([%Runtime{timeout_ms: -5}]))) == [:invalid_runtime_option]
      assert codes(Contract.validate(compiled([%Runtime{max_skew_secs: -1}]))) == [:invalid_runtime_option]
      assert codes(Contract.validate(compiled([%Runtime{timeout_ms: "5"}]))) == [:invalid_runtime_option]
    end

    test "every refusal carries a detail string and a closed-table code" do
      {:error, refusals} =
        Contract.validate(
          compiled([
            %Runtime{timeout_ms: 0, trusted_keys: ["zz"]},
            %Admission{name: :a, step: :plan},
            %Admission{name: :a, step: :plan}
          ])
        )

      assert length(refusals) >= 4

      for %{code: code, detail: detail} <- refusals do
        assert code in AshGraphLaw.Refusal.codes()
        assert is_binary(detail) and detail != ""
      end
    end
  end
end
