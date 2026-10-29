defmodule AshGraphLaw.Telemetry.CastleOcel do
  @moduledoc """
  Pure projection of ash_graphlaw's admission/refusal outcomes into the
  evidence cluster's closed CASTLE OCEL vocabulary -- the same closed event
  vocabulary `BeamPM.CastleOcel` defines (`evidence_admitted`,
  `refused_observation`, `ggen_sync_observed`, ...) and the exact wire shape
  `AshA2A.Telemetry.CastleOcel` emits, applied here to ash_graphlaw's
  admission surface (`AshGraphLaw.Admitted` + `AshGraphLaw.Refusal`).

  ## Observation, never subject success

    * `project/1` and `outcome_to_event/1` are total, pure functions over
      their input. They mutate nothing, spawn nothing, read no clock, touch
      no filesystem, emit no messages, and attach no telemetry handlers --
      this is the emission seam (the event maps), not a live pipeline.
    * every projected event carries the fixed attributes
      `"authority" => "none"` / `"provenance" => "observation_only"`: no
      event in this log is, carries, or implies execution authority. An
      event named `evidence_admitted` records that an admission was
      OBSERVED, not that the admitted evidence is true.
    * timestamps are caller-supplied, never sampled.

  ## Outcome -> event mapping (total over the closed refusal table)

  The closed code table (`AshGraphLaw.Refusal.codes/0`, resolved through
  `AshGraphLaw.Refusal.class_of/1`) plus the admitted outcome:

  | outcome                      | CastleOcel event      | bound object type |
  |------------------------------|-----------------------|-------------------|
  | `:admitted`                  | `evidence_admitted`   | `gym_act_episode` |
  | `refused_*` classes          | `refused_observation` | `system`          |
  | `:blocked_resource`          | `ggen_sync_observed`  | `container`       |
  | `:unsupported`               | `ggen_sync_observed`  | `container`       |
  | anything else                | typed error           | --                |

  The two non-refusal classes are a **documented non-mapping** to
  `evidence_admitted`/`refused_observation`:
  `BLOCKED != REFUSED != ADMITTED`, so `:blocked_resource` and
  `:unsupported` project as plain observations (`ggen_sync_observed`) with
  the class carried in `refusal_class`, never as admissions and never as
  refusals. Any outcome outside the closed table refuses with
  `{:error, {:unknown_class, outcome}}` -- never silently.

  ## Wire shape

  The repo's existing OCEL 2.0 envelope, the exact shape
  `AshA2A.Telemetry.CastleOcel` emits so both emitters are interchangeable
  for a shared consumer: `{"objectTypes", "eventTypes", "objects",
  "events"}` with `{event_id, event_type, event_time, attributes}` event
  maps. No second wire shape is introduced.

  ## Determinism

  Same input list -> structurally identical envelope: event ids are derived
  from list position and event name, object enumeration follows the
  canonical object-type order with lexicographic id sort, keys are sorted,
  and timestamps are caller-supplied.
  """

  @tool "ash_graphlaw admission"

  @admitted :admitted

  @typedoc """
  Caller-supplied projection input for one observed admission/refusal
  outcome. `:outcome` is `:admitted` or one of the closed-table refusal
  codes (`AshGraphLaw.Refusal.codes/0`).
  """
  @type observation :: %{
          required(:outcome) => :admitted | AshGraphLaw.Refusal.code(),
          required(:subject_id) => String.t(),
          required(:time) => String.t(),
          optional(:refusal_code) => String.t()
        }

  @doc """
  The outcome atoms this module admits as inputs: `:admitted` plus every
  closed-table refusal code. Everything else refuses.
  """
  @spec known_outcomes() :: [:admitted | AshGraphLaw.Refusal.code()]
  def known_outcomes, do: [@admitted | AshGraphLaw.Refusal.codes()]

  @doc """
  The total outcome -> CastleOcel event-name mapping, public for the
  totality court.

  `:admitted` -> `"evidence_admitted"`; every outcome whose
  `AshGraphLaw.Refusal.class_of/1` class is a `refused_*` class ->
  `"refused_observation"`; `:blocked_resource` and `:unsupported` ->
  `"ggen_sync_observed"` (documented non-mapping, see the moduledoc).
  Returns `nil` outside the closed table.
  """
  @spec outcome_to_event(atom()) :: String.t() | nil
  def outcome_to_event(:admitted), do: "evidence_admitted"

  def outcome_to_event(outcome) when is_atom(outcome) do
    class = AshGraphLaw.Refusal.class_of(outcome)

    cond do
      class == :blocked_resource or class == :unsupported -> "ggen_sync_observed"
      match?("refused_" <> _, Atom.to_string(class)) -> "refused_observation"
      true -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def outcome_to_event(_), do: nil

  @doc """
  Project an ordered list of observed admission/refusal outcomes into the
  OCEL 2.0 envelope (see the moduledoc). Pure and deterministic.

  Refusals (never silent):

    * `{:error, {:invalid_observation, element}}` -- not a map
    * `{:error, {:unknown_class, outcome}}` -- outcome outside the closed
      table (the sabotage surface)
    * `{:error, {:missing_subject_id, outcome}}` /
      `{:error, {:subject_id_not_binary, outcome, v}}`
    * `{:error, {:missing_time, outcome}}` /
      `{:error, {:time_not_binary, outcome, v}}`
  """
  @spec project([observation()]) :: {:ok, map()} | {:error, term()}
  def project(observations) when is_list(observations) do
    Enum.reduce_while(observations, {:ok, {1, []}}, fn element, {:ok, {index, acc}} ->
      case build_event(element, index) do
        {:ok, event} -> {:cont, {:ok, {index + 1, [event | acc]}}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, {_, events}} -> {:ok, envelope(Enum.reverse(events))}
      error -> error
    end
  end

  @doc """
  Convenience for one observation: `{:ok, event_map}` or a typed error.
  `event_map` is the same map `project/1` puts in `"events"`.
  """
  @spec project_event(observation()) :: {:ok, map()} | {:error, term()}
  def project_event(observation), do: build_event(observation, 1)

  ## Event building (deterministic: index-derived ids)

  defp build_event(%{outcome: outcome} = element, index) do
    with {:ok, event_name} <- classify(outcome),
         {:ok, subject_id} <- subject_id(outcome, Map.get(element, :subject_id)),
         {:ok, time} <- time(outcome, Map.get(element, :time)),
         refusal_code = normalise_refusal_code(event_name, Map.get(element, :refusal_code)) do
      attrs =
        %{
          "authority" => "none",
          "provenance" => "observation_only",
          "standing" => Atom.to_string(outcome),
          "subject_id" => subject_id,
          "tool" => @tool
        }
        |> maybe_put_refusal_class(event_name, outcome, refusal_code)

      {:ok,
       %{
         "event_id" => "ash-graphlaw-#{pad(index)}-#{event_name}",
         "event_type" => event_name,
         "event_time" => time,
         "attributes" => attrs
       }}
    end
  end

  defp build_event(other, _index), do: {:error, {:invalid_observation, other}}

  defp classify(outcome) do
    case outcome_to_event(outcome) do
      nil -> {:error, {:unknown_class, outcome}}
      event_name -> {:ok, event_name}
    end
  end

  defp subject_id(_outcome, subject_id) when is_binary(subject_id) and subject_id != "",
    do: {:ok, subject_id}

  defp subject_id(outcome, nil), do: {:error, {:missing_subject_id, outcome}}
  defp subject_id(outcome, other), do: {:error, {:subject_id_not_binary, outcome, other}}

  defp time(_outcome, time) when is_binary(time) and time != "", do: {:ok, time}
  defp time(outcome, nil), do: {:error, {:missing_time, outcome}}
  defp time(outcome, other), do: {:error, {:time_not_binary, outcome, other}}

  defp normalise_refusal_code("refused_observation", code) when is_binary(code) and code != "",
    do: code

  defp normalise_refusal_code("refused_observation", nil), do: "REFUSED"

  defp normalise_refusal_code(_event_name, code) when is_binary(code) and code != "",
    do: code

  defp normalise_refusal_code(_event_name, _), do: nil

  defp maybe_put_refusal_class(attrs, "refused_observation", outcome, refusal_code) do
    Map.put(attrs, "refusal_class", Atom.to_string(AshGraphLaw.Refusal.class_of(outcome)))
    |> Map.put("refusal_code", refusal_code)
    |> Map.put("broken_term", Atom.to_string(AshGraphLaw.Refusal.broken_term_of(outcome)))
  end

  defp maybe_put_refusal_class(attrs, "ggen_sync_observed", outcome, refusal_code) do
    Map.put(attrs, "refusal_class", Atom.to_string(AshGraphLaw.Refusal.class_of(outcome)))
    |> Map.put("refusal_code", refusal_code)
  end

  defp maybe_put_refusal_class(attrs, _event_name, _outcome, _refusal_code), do: attrs

  defp pad(index), do: String.pad_leading(Integer.to_string(index), 4, "0")

  ## Envelope (objectTypes / eventTypes / objects / events, sorted keys)

  defp envelope(events) do
    objects =
      events
      |> Enum.map(fn event ->
        {object_type, object_id} = object_binding(event)

        Map.new([{"object_id", object_id}, {"object_type", object_type}])
      end)
      |> Enum.uniq()
      |> Enum.sort_by(&{Map.fetch!(&1, "object_type"), Map.fetch!(&1, "object_id")})

    %{
      "objectTypes" =>
        events
        |> Enum.map(&(object_binding(&1) |> elem(0)))
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map(&Map.new([{"name", &1}, {"attributes", []}])),
      "eventTypes" =>
        events
        |> Enum.map(&Map.fetch!(&1, "event_type"))
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map(&Map.new([{"name", &1}, {"attributes", []}])),
      "objects" => objects,
      "events" => events
    }
  end

  # Per-event-type object binding, restricted to the event names this module
  # emits (the CastleOcel closed binding: evidence_admitted -> gym_act_episode,
  # refused_observation -> system, ggen_sync_observed -> container).
  defp object_binding(%{"event_type" => "evidence_admitted"} = event) do
    {"gym_act_episode", "subject:" <> event["attributes"]["subject_id"]}
  end

  defp object_binding(%{"event_type" => "refused_observation"}) do
    {"system", "ash-graphlaw-admission"}
  end

  defp object_binding(%{"event_type" => "ggen_sync_observed"} = event) do
    {"container", "ash-graphlaw-admission:" <> event["attributes"]["standing"]}
  end
end
