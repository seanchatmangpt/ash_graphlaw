


defmodule AshR2RML.ResourceCompositionTest do
  use ExUnit.Case, async: true

  @fixture_source """
  defmodule AshR2RML.Resource.CompositionFixture do
    use Ash.Resource,
      domain: nil,
      extensions: [AshR2RML.Resource]

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
    fixture_module = AshR2RML.Resource.CompositionFixture
    true = Enum.any?(Code.compile_string(@fixture_source), &match?({^fixture_module, _}, &1))

    %{fixture: fixture_module}

  end

  test "the compiled fixture actually carries the AshR2RML.Resource extension", %{fixture: fixture} do
    assert AshR2RML.Resource in Spark.extensions(fixture)
  end

  test "AshR2RML.Resource.Info returns real, non-nil compiled state for the fixture", %{fixture: fixture} do
    refute is_nil(AshR2RML.Resource.Info.compiled(fixture))
  end



end
