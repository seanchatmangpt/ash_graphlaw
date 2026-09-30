# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.DslCapabilityNegativeTest do
  # UNSUPPORTED(generator-capability): hand-written Chicago negative test; each case compiles a real
  # Ash resource and expects the Spark verifier to refuse it. Positive control first.
  use ExUnit.Case, async: true

  @moduletag :capture_log

  defp compile_resource(body) do
    n = System.unique_integer([:positive])

    source = """
    defmodule AshGraphLaw.DslCapabilityNegativeTest.Gen#{n} do
      use Ash.Resource,
        data_layer: Ash.DataLayer.Ets,
        validate_domain_inclusion?: false,
        extensions: [AshGraphLaw.Resource]

      attributes do
        uuid_primary_key :id
      end

      graphlaw do
        #{body}
      end
    end
    """

    Code.compile_string(source)
  end

  test "positive control: valid capabilities compile" do
    assert [{module, _bin}] = compile_resource("capability(:sparql)\n capability(:shacl)")
    assert Ash.Resource.Info.resource?(module)
    assert module |> AshGraphLaw.Admissions.capabilities() |> Enum.map(& &1.name) == [:sparql, :shacl]
  end

  test "an unknown capability name is refused at compile time" do
    error = assert_raise Spark.Error.DslError, fn -> compile_resource("capability(:bogus)") end
    assert Exception.message(error) =~ "unknown_capability"
    assert Exception.message(error) =~ "bogus"
  end

  test "a ceiling below the op minimum is refused" do
    error = assert_raise Spark.Error.DslError, fn -> compile_resource("capability(:entail, ceiling: :observe)") end
    assert Exception.message(error) =~ "ceiling_unmet"
  end

  test "an out-of-set ceiling is refused by the entity schema" do
    assert_raise Spark.Error.DslError, fn -> compile_resource("capability(:sparql, ceiling: :root)") end
  end

  test "a duplicate capability is refused" do
    error = assert_raise Spark.Error.DslError, fn -> compile_resource("capability(:sparql)\n capability(:sparql)") end
    assert Exception.message(error) =~ "duplicate_capability"
  end
end
