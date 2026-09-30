# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Lane L17. UNSUPPORTED(generator-capability): no pack emits adversarial courts.

defmodule AshGraphLaw.Adversarial.ConcurrencyTest do
  @moduledoc """
  Adversarial court for concurrent admission through the real pool.

  100 simultaneous admissions must produce evidence identical to the same 100 admissions run
  serially: no cross-talk between requests, no lost or duplicated responses, no digest that
  depends on scheduling. Distinct inputs must still yield distinct evidence (control against
  a constant answer).
  """

  use AshGraphLaw.Test.Case, async: false

  alias AshGraphLaw.Test.Lease

  alias AshGraphLaw.Evidence
  alias AshGraphLaw.Test.Ticket

  @moduletag :wasm
  @moduletag :slow

  @n 100

  setup do
    # The queue must hold every simultaneous caller (@n); at the default max_queue of 64 the
    # library correctly sheds load with :saturated, which made these courts timing-dependent.
    start_pool!(size: 4, max_queue: 4 * @n)
    Ash.DataLayer.Ets.stop(Ticket)
    on_exit(fn -> Ash.DataLayer.Ets.stop(Ticket) end)
    :ok
  end

  # Runs one admission and returns the evidence it produced. Called from any process: the
  # after_action hook reports to the process that built the changeset.
  defp admit(title) do
    me = self()

    result =
      Ticket
      |> Ash.Changeset.for_create(:open, %{title: title}, context: Lease.context(:construct))
      |> Ash.Changeset.after_action(fn cs, record ->
        send(me, {:evidence, title, cs.context.graphlaw})
        {:ok, record}
      end)
      |> Ash.create()

    case result do
      {:ok, _record} ->
        receive do
          {:evidence, ^title, %Evidence{} = evidence} -> {:ok, evidence}
        after
          5_000 -> {:error, :no_evidence}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp concurrently(titles) do
    titles
    |> Task.async_stream(&{&1, admit(&1)}, max_concurrency: length(titles), timeout: 120_000, ordered: true)
    |> Enum.map(fn {:ok, pair} -> pair end)
  end

  test "positive control: a single admission through the pool yields evidence" do
    assert {:ok, %Evidence{standing: :PARTIAL_ALIVE, digest: digest}} = admit("solo")
    assert String.match?(digest, ~r/\A[0-9a-f]{64}\z/)
  end

  test "#{@n} concurrent admissions equal the same admissions run serially" do
    titles = for i <- 1..@n, do: "ticket-#{i}"

    serial = Map.new(titles, fn title -> {title, admit(title)} end)
    assert Enum.all?(serial, &match?({_, {:ok, %Evidence{}}}, &1))
    Ash.DataLayer.Ets.stop(Ticket)

    concurrent = titles |> concurrently() |> Map.new()

    assert map_size(concurrent) == @n

    assert Enum.all?(concurrent, &match?({_, {:ok, %Evidence{}}}, &1)),
           inspect(Enum.reject(concurrent, &match?({_, {:ok, _}}, &1)))

    for title <- titles do
      {:ok, s} = serial[title]
      {:ok, c} = concurrent[title]
      assert c.digest == s.digest, "digest differs for #{title}"
      assert c.input_digest == s.input_digest
      assert c.graph_ids == s.graph_ids
      assert c.receipts == s.receipts
    end
  end

  test "distinct inputs stay distinct under concurrency" do
    results = concurrently(for i <- 1..@n, do: "distinct-#{i}")
    digests = for {_title, {:ok, %Evidence{digest: d}}} <- results, do: d

    assert length(digests) == @n
    assert digests |> Enum.uniq() |> length() == @n
  end

  test "#{@n} concurrent admissions of one input share one evidence digest" do
    results = concurrently(List.duplicate("same input", @n))
    digests = for {_title, {:ok, %Evidence{digest: d}}} <- results, do: d

    assert length(digests) == @n
    assert [_one] = Enum.uniq(digests)
  end

  test "a refused admission mixed into the load stays refused and does not disturb the others" do
    good = for i <- 1..50, do: "mixed-#{i}"
    expected = Map.new(good, fn t -> {t, elem(admit(t), 1).digest} end)
    Ash.DataLayer.Ets.stop(Ticket)

    tasks =
      Enum.flat_map(good, fn title ->
        [{:good, title}, {:bad, title}]
      end)

    results =
      tasks
      |> Task.async_stream(
        fn
          {:good, title} -> {:good, title, admit(title)}
          {:bad, _title} -> {:bad, nil, bad_admit()}
        end,
        max_concurrency: 100,
        timeout: 120_000
      )
      |> Enum.map(fn {:ok, r} -> r end)

    for {:good, title, {:ok, evidence}} <- results, do: assert(evidence.digest == expected[title])
    assert length(for({:good, _, {:ok, _}} <- results, do: :ok)) == 50

    bad = for {:bad, _, r} <- results, do: r
    assert length(bad) == 50

    for r <- bad do
      assert {:error, error} = r
      # The pinned engine reports a SHACL violation as `EngineRejected` with no code, which the
      # library projects as :engine_refused (see documentation/reference/abi_reference.md).
      assert AshGraphLaw.Error.codes(error) == [:engine_refused]
    end
  end

  # An empty title violates the SHACL shape (`sh:minLength 1` and `sh:minCount 1`).
  defp bad_admit do
    Ticket
    |> Ash.Changeset.for_create(:open, %{}, context: Lease.context(:construct))
    |> Ash.create()
  end
end
