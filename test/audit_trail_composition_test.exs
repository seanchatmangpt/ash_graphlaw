


defmodule AuditTrail.ResourceCompositionTest do
  use ExUnit.Case, async: true

  @fixture_source """
  defmodule AuditTrail.Resource.CompositionFixture do
    use Ash.Resource,
      domain: nil,
      extensions: [AuditTrail.Resource, AshGraphql.Resource, AshJsonApi.Resource]

    attributes do
      uuid_primary_key :id
    end
  end
  """


  # setup_all: the fixture module is compiled once per test module, not redefined per
  # test. Code.compile_string/1 returns every module the source defines -- an Ash
  # resource also defines protocol impls (Inspect.<Fixture>, ...) -- so the fixture is
  # looked up by its declared name, not by destructuring a one-element list.
  setup_all do
    fixture_module = AuditTrail.Resource.CompositionFixture
    true = Enum.any?(Code.compile_string(@fixture_source), &match?({^fixture_module, _}, &1))

    %{fixture: fixture_module}

  end

  test "the compiled fixture actually carries the AuditTrail.Resource extension", %{fixture: fixture} do
    assert AuditTrail.Resource in Spark.extensions(fixture)
  end

  test "AuditTrail.Resource.Info returns real, non-nil compiled state for the fixture", %{fixture: fixture} do
    refute is_nil(AuditTrail.Resource.Info.compiled(fixture))
  end



  @tag :ash_graphql
  test "composes with real ash_graphql introspection", %{fixture: fixture} do
    # The generated extension and AshGraphql.Resource co-reside on the
    # compiled fixture, and the library's real Info module is present.
    assert AshGraphql.Resource in Spark.extensions(fixture)
    assert AuditTrail.Resource in Spark.extensions(fixture)
    assert function_exported?(AshGraphql.Resource.Info, :type, 1)
  end

  @tag :ash_json_api
  test "composes with real ash_json_api introspection", %{fixture: fixture} do
    # The generated extension and AshJsonApi.Resource co-reside on the
    # compiled fixture, and the library's real Info module is present.
    assert AshJsonApi.Resource in Spark.extensions(fixture)
    assert AuditTrail.Resource in Spark.extensions(fixture)
    assert function_exported?(AshJsonApi.Resource.Info, :type, 1)
  end

end
