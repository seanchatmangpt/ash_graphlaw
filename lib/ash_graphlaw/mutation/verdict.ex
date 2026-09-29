# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Mutation.Verdict do
  @moduledoc """
  Outcome of `AshGraphLaw.Mutation.qualify/2` for one mutation.

  Development tooling. UNSUPPORTED(generator-capability): hand-written; no pack
  template emits a mutation court.

    * `:mutant_killed` - a killer test failed under the mutant after the baseline was green
    * `:mutant_survived` - every killer test still passed with the guard removed: the
      killers are vacuous for that guard
    * `:blocked` - the target or every killer file is unavailable (typed refusal in `:code`)
    * `:unknown` - the baseline was not green, a run could not be read, or the original BEAM
      could not be verifiably restored. Never a pass.

  Fields `:baseline` and `:mutant` hold the runner summary
  (`%{total, failures, failed, skipped, excluded}`) each verdict was read from.
  """

  @enforce_keys [:mutation_id, :target, :verdict]
  defstruct [
    :mutation_id,
    :target,
    :verdict,
    :code,
    :detail,
    :mutant_calls,
    :applied,
    :restored,
    :baseline,
    :mutant,
    killers: [],
    killer_files: [],
    missing_killers: [],
    killed_by: []
  ]

  @type verdict :: :mutant_killed | :mutant_survived | :blocked | :unknown

  @type t :: %__MODULE__{
          mutation_id: String.t(),
          target: String.t(),
          verdict: verdict(),
          code: atom() | nil,
          detail: String.t() | nil,
          mutant_calls: non_neg_integer() | nil,
          applied: map() | nil,
          restored: map() | nil,
          baseline: map() | nil,
          mutant: map() | nil,
          killers: [String.t()],
          killer_files: [String.t()],
          missing_killers: [String.t()],
          killed_by: [String.t()]
        }

  @verdicts [:mutant_killed, :mutant_survived, :blocked, :unknown]

  @doc "The closed set of verdicts."
  @spec verdicts() :: [verdict()]
  def verdicts, do: @verdicts

  @doc "JSON-safe map form (string keys, atoms as strings)."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = v) do
    safe(%{
      "mutation_id" => v.mutation_id,
      "target" => v.target,
      "verdict" => v.verdict,
      "code" => v.code,
      "detail" => v.detail,
      "killers" => v.killers,
      "killer_files" => v.killer_files,
      "missing_killers" => v.missing_killers,
      "killed_by" => v.killed_by,
      "mutant_calls" => v.mutant_calls,
      "applied" => v.applied,
      "restored" => v.restored,
      "baseline" => v.baseline,
      "mutant" => v.mutant
    })
  end

  @doc "Counts of verdicts, every verdict present (zero when unseen)."
  @spec tally([t()]) :: %{verdict() => non_neg_integer()}
  def tally(verdicts) do
    base = Map.new(@verdicts, &{&1, 0})
    Enum.reduce(verdicts, base, fn %__MODULE__{verdict: v}, acc -> Map.update!(acc, v, &(&1 + 1)) end)
  end

  @doc """
  Canonical JSON report: keys sorted at every depth, pretty printed, trailing
  newline. The same verdicts always produce the same bytes.
  """
  @spec canonical_json([t()]) :: String.t()
  def canonical_json(verdicts) when is_list(verdicts) do
    report =
      safe(%{
        "schema" => "ash_graphlaw.mutation_report/1",
        "tally" => tally(verdicts),
        "verdicts" => Enum.map(verdicts, &to_map/1)
      })

    report |> ordered() |> Jason.encode!(pretty: true) |> Kernel.<>("\n")
  end

  defp ordered(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> {key, ordered(value)} end)
    |> Jason.OrderedObject.new()
  end

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(other), do: other

  defp safe(map) when is_map(map) and not is_struct(map), do: Map.new(map, fn {k, v} -> {key(k), safe(v)} end)
  defp safe(list) when is_list(list), do: Enum.map(list, &safe/1)
  defp safe(value) when is_boolean(value) or is_nil(value) or is_number(value), do: value
  defp safe(value) when is_atom(value), do: Atom.to_string(value)
  defp safe(value) when is_binary(value), do: if(String.valid?(value), do: value, else: inspect(value))
  defp safe(value), do: inspect(value, limit: 20)

  defp key(key) when is_binary(key), do: key
  defp key(key) when is_atom(key), do: Atom.to_string(key)
  defp key(key), do: inspect(key)
end
