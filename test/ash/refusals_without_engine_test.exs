# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.NoEngine.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshGraphLaw.Test.NoEngine.Note
  end
end

defmodule AshGraphLaw.Test.NoEngine.Note do
  @moduledoc false
  # UNSUPPORTED(generator-capability): fixture resource. Every admission here uses an engine-only
  # `rdfs` step (no law module), so the paths under test are the ones that run BEFORE, or INSTEAD OF,
  # the engine: authority, lookup, and the typed refusal when no engine host is running.
  use Ash.Resource,
    domain: AshGraphLaw.Test.NoEngine.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read]

    create :write do
      accept [:title]
      validate {AshGraphLaw.Validation.Admissible, admission: :entail}
    end

    create :write_ghost do
      accept [:title]
      validate {AshGraphLaw.Validation.Admissible, admission: :no_such_admission}
    end

    create :write_open do
      accept [:title]
      validate {AshGraphLaw.Validation.Admissible, admission: :entail_open}
    end

    read :checked do
      prepare {AshGraphLaw.Preparation.Admit, admission: :entail}
    end

    read :checked_open do
      prepare {AshGraphLaw.Preparation.Admit, admission: :entail_open}
    end

    action :check, :boolean do
      argument :title, :string, public?: true
      prepare {AshGraphLaw.Preparation.Admit, admission: :entail}
      run fn _input, _context -> {:ok, true} end
    end
  end

  graphlaw do
    runtime do
      timeout_ms(1000)
      trusted_keys([AshGraphLaw.Test.Lease.public_key_hex(:trusted)])
    end

    admission :entail do
      step(:rdfs)
    end

    admission :entail_open do
      step(:rdfs)
      ceiling(:observe)
    end
  end
end

defmodule AshGraphLaw.Ash.RefusalsWithoutEngineTest do
  @moduledoc """
  The refusal paths of `Validation.Admissible` and `Preparation.Admit` that need no engine, on real
  Ash actions: the authority ceiling, an unknown admission, and the typed `:host_not_started`
  refusal when a caller has cleared authority but no engine host is running. Every negative has its
  positive control: the same action gets past the check under test.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test; no pool is started, so there is no engine.
  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Error
  alias AshGraphLaw.Preparation
  alias AshGraphLaw.Test.Lease
  alias AshGraphLaw.Test.NoEngine.Note
  alias AshGraphLaw.Validation.Admissible

  setup do
    # No pool: the default server AshGraphLaw.Pool has no members in this module.
    assert AshGraphLaw.Pool.members() == []
    :ok
  end

  defp write(action, context) do
    Note |> Ash.Changeset.for_create(action, %{title: "t"}, context: context) |> Ash.create()
  end

  describe "Validation.Admissible" do
    test "positive control: a signed :construct lease clears the ceiling and reaches the engine boundary" do
      assert {:error, error} = write(:write, Lease.context(:construct))
      assert Error.codes(error) == [:host_not_started]
    end

    test "no lease, a bare atom and a signed :observe lease are refused before the engine" do
      for context <- [%{}, %{graphlaw_lease: :construct}, Lease.context(:observe), Lease.context(:select)] do
        assert {:error, error} = write(:write, context)
        assert Error.codes(error) == [:ceiling_unmet], inspect(context)
        assert [%{details: %{required: :construct}}] = Error.refusals(error)
      end
    end

    test "an :observe admission needs no lease" do
      assert {:error, error} = write(:write_open, %{})
      assert Error.codes(error) == [:host_not_started]
    end

    test "an unknown admission is refused :unknown_admission and lists what is known" do
      assert {:error, error} = write(:write_ghost, Lease.context(:construct))
      assert Error.codes(error) == [:unknown_admission]
      assert [%{details: %{known: known}}] = Error.refusals(error)
      assert Enum.sort(known) == [:entail, :entail_open]
    end

    test "its options are validated when the resource compiles" do
      assert {:ok, _} = Admissible.init(admission: :entail)
      assert {:error, _} = Admissible.init([])
      assert {:error, _} = Admissible.init(admission: "entail")
      assert {:error, _} = Admissible.init(admission: :entail, projection: "no")
      assert {:error, _} = Admissible.init(admission: :entail, timeout: 0)
      assert Admissible.describe(admission: :entail)[:message] =~ ":entail"
    end
  end

  describe "Preparation.Admit" do
    test "positive control: a signed :construct lease clears the ceiling and reaches the engine boundary" do
      query = Ash.Query.for_read(Note, :checked, %{}, context: Lease.context(:construct))
      assert {:error, error} = Ash.read(query)
      assert Error.codes(error) == [:host_not_started]
    end

    test "a read without a signed lease is refused before the engine" do
      for context <- [%{}, %{graphlaw_lease: :construct}, Lease.context(:observe)] do
        assert {:error, error} = Ash.read(Ash.Query.for_read(Note, :checked, %{}, context: context))
        assert Error.codes(error) == [:ceiling_unmet], inspect(context)
      end
    end

    test "an :observe admission on a read needs no lease" do
      assert {:error, error} = Ash.read(Ash.Query.for_read(Note, :checked_open, %{}))
      assert Error.codes(error) == [:host_not_started]
    end

    test "a generic action's input is admitted the same way" do
      input = Ash.ActionInput.for_action(Note, :check, %{title: "x"}, context: Lease.context(:construct))
      assert {:error, error} = Ash.run_action(input)
      assert Error.codes(error) == [:host_not_started]

      denied = Ash.ActionInput.for_action(Note, :check, %{title: "x"})
      assert {:error, error} = Ash.run_action(denied)
      assert Error.codes(error) == [:ceiling_unmet]
    end

    test "its options are validated" do
      assert {:ok, _} = Preparation.Admit.init(admission: :entail)
      assert {:error, _} = Preparation.Admit.init([])
    end
  end
end
