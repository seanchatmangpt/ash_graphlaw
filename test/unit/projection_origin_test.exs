# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Projection.OriginTest do
  use ExUnit.Case, async: true

  alias AshGraphLaw.Projection
  alias AshGraphLaw.Projection.Default
  alias AshGraphLaw.Projection.Origin
  alias AshGraphLaw.Test.Ticket

  defp changeset(title), do: Ash.Changeset.for_create(Ticket, :open, %{title: title})

  # A real Projection implementation that overrides origin/2 (not a mock).
  defmodule Custom do
    @moduledoc false
    @behaviour AshGraphLaw.Projection

    @impl true
    def data(subject, opts), do: AshGraphLaw.Projection.Default.data(subject, opts)

    @impl true
    def origin(subject, opts) do
      subject
      |> AshGraphLaw.Projection.Default.origin(opts)
      |> Map.put(:base, "urn:custom:base")
    end
  end

  # A real Projection implementation without origin/2.
  defmodule Plain do
    @moduledoc false
    @behaviour AshGraphLaw.Projection

    @impl true
    def data(subject, opts), do: AshGraphLaw.Projection.Default.data(subject, opts)
  end

  describe "Default.origin/2 (positive control)" do
    test "names resource, action, projection and the digest of the exact projected text" do
      cs = changeset("plain title")
      {:ok, data} = Default.data(cs, [])

      origin = Default.origin(cs)

      assert %Origin{resource: Ticket, action: :open, projection: Default, dialect: "ntriples"} = origin
      assert origin.primary_key == %{}
      assert origin.data_sha256 == Projection.input_digest(data)
      assert origin.data_sha256 =~ ~r/\A[0-9a-f]{64}\z/
    end

    test "a different title changes the data digest" do
      refute Default.origin(changeset("a")).data_sha256 == Default.origin(changeset("b")).data_sha256
    end

    test "an explicit :data option is digested instead of re-projecting" do
      data = %{text: "<urn:a> <urn:p> <urn:b> .\n", dialect: "ntriples"}
      origin = Default.origin(changeset("x"), data: data)
      assert origin.data_sha256 == Projection.input_digest(data)
    end

    test "an unprojectable subject still yields an origin over empty text" do
      origin = Default.origin(:not_a_subject)
      assert origin.data_sha256 == Projection.input_digest(%{text: ""})
    end
  end

  describe "to_map/1 and digest/1" do
    test "to_map is string-keyed and JSON-safe" do
      map = changeset("t") |> Default.origin() |> Origin.to_map()

      assert Enum.all?(Map.keys(map), &is_binary/1)
      assert map["resource"] == "AshGraphLaw.Test.Ticket"
      assert map["action"] == "open"
      assert map["projection"] == "AshGraphLaw.Projection.Default"
      assert {:ok, _} = Jason.encode(map)
    end

    test "digest is stable across runs and is sha256-prefixed" do
      a = changeset("stable") |> Default.origin() |> Origin.digest()
      b = changeset("stable") |> Default.origin() |> Origin.digest()

      assert a == b
      assert a =~ ~r/\Asha256:[0-9a-f]{64}\z/
    end

    test "digest moves when the projected text moves" do
      refute Origin.digest(Default.origin(changeset("a"))) == Origin.digest(Default.origin(changeset("b")))
    end
  end

  describe "new/1" do
    test "requires resource, projection and data_sha256" do
      assert_raise ArgumentError, ~r/requires :data_sha256/, fn ->
        Origin.new(resource: Ticket, projection: Default)
      end
    end

    test "rejects unknown keys" do
      assert_raise ArgumentError, ~r/unknown/, fn ->
        Origin.new(resource: Ticket, projection: Default, data_sha256: "x", bogus: 1)
      end
    end
  end

  describe "Projection.origin_for/3" do
    test "uses the projection's own origin/2 when exported" do
      origin = Projection.origin_for(Custom, changeset("t"))
      assert origin.base == "urn:custom:base"
    end

    test "falls back to the default origin when the callback is absent, naming the projection" do
      origin = Projection.origin_for(Plain, changeset("t"))
      assert origin.projection == Plain
      assert origin.base == nil
      assert origin.data_sha256 == Default.origin(changeset("t")).data_sha256
    end
  end
end
