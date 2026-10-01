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
        domain: nil,
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

    # Elixir 1.19 runs Spark verifiers in the post-compile parallel checker, where a DslError is
    # only logged as a warning. Compile, then run the real verifier on the compiled DSL state.
    # The post-compile warning is expected; swallow it so the suite output stays clean.
    {modules, _warnings} = ExUnit.CaptureIO.with_io(:stderr, fn -> Code.compile_string(source) end)
    {module, _bin} = Enum.find(modules, fn {m, _} -> Ash.Resource.Info.resource?(m) end)
    {module, AshGraphLaw.Resource.Verify.verify(module.spark_dsl_config())}
  end

  defp refusal(body) do
    assert {_module, {:error, %Spark.Error.DslError{} = error}} = compile_resource(body)
    Exception.message(error)
  end

  test "positive control: valid capabilities compile" do
    assert {module, :ok} = compile_resource("capability(:sparql)\n capability(:shacl)")
    assert Ash.Resource.Info.resource?(module)
    assert module |> AshGraphLaw.Admissions.capabilities() |> Enum.map(& &1.name) == [:sparql, :shacl]
  end

  test "an unknown capability name is refused at compile time" do
    message = refusal("capability(:bogus)")
    assert message =~ "unknown_capability"
    assert message =~ "bogus"
  end

  test "a ceiling below the op minimum is refused" do
    assert refusal("capability(:entail, ceiling: :observe)") =~ "ceiling_unmet"
  end

  test "an out-of-set ceiling is refused by the entity schema" do
    assert_raise Spark.Error.DslError, fn -> compile_resource("capability(:sparql, ceiling: :root)") end
  end

  test "a duplicate capability is refused" do
    assert refusal("capability(:sparql)\n capability(:sparql)") =~ "duplicate_capability"
  end
end
