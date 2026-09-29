# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Evidence do
  @moduledoc """
  Admission evidence: an observation bound to one exact input digest.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits it.

  Evidence records which admission ran, the standing derived from its result
  (`AshGraphLaw.Standing.of/1`), the SHA-256 of the projected input, the graph
  state ids and receipts the engine reported, the engine identity
  (`wasm_sha256`, `graphlaw_release`) and the identity of the signed lease that
  satisfied the ceiling gate (`lease`: ceiling, lease id, signer key id and
  lease digest; `nil` when no lease was presented). It is data, not authority:
  GraphLaw derives and validates; it never authorizes. The lease identity is
  what makes the authority behind an admitted change replayable: the engine
  verified that exact signed lease, and the digest names it.

  `digest/1` is the SHA-256 (lowercase hex) of a canonical encoding: every map
  is encoded with keys sorted, so identical evidence yields byte-identical
  digests. The `:digest` field itself is excluded from the digested content.
  """

  alias AshGraphLaw.{Admitted, Receipt, Standing}

  defstruct [
    :admission,
    :standing,
    :input_digest,
    :graph_ids,
    :receipts,
    :digest,
    :wasm_sha256,
    :graphlaw_release,
    :lease
  ]

  @type t :: %__MODULE__{
          admission: atom() | String.t(),
          standing: Standing.t(),
          input_digest: String.t() | nil,
          graph_ids: list(),
          receipts: [map()],
          digest: String.t(),
          wasm_sha256: String.t() | nil,
          graphlaw_release: String.t(),
          lease: AshGraphLaw.Authority.identity() | nil
        }

  @doc """
  Builds evidence for a successful admission.

  `opts`: `:wasm_sha256` (engine identity, default `nil`), `:graphlaw_release`
  (default `AshGraphLaw.graphlaw_release/0`), `:lease` (lease identity from
  `AshGraphLaw.Authority.identity/1`, default `nil`; any other shape raises `ArgumentError`). Unknown options raise
  `ArgumentError`, so an option that would be silently dropped is caught.
  """
  @spec new(atom() | String.t(), Admitted.t(), String.t() | nil, keyword()) :: t()
  def new(admission_name, %Admitted{} = admitted, input_digest, opts \\ []) do
    :ok = check_opts(opts)

    base = %__MODULE__{
      admission: admission_name,
      standing: Standing.of({:ok, admitted}),
      input_digest: input_digest,
      graph_ids: admitted.states,
      receipts: Enum.map(admitted.receipts, &receipt_map/1),
      wasm_sha256: Keyword.get(opts, :wasm_sha256),
      graphlaw_release: Keyword.get_lazy(opts, :graphlaw_release, &AshGraphLaw.graphlaw_release/0),
      lease: Keyword.get(opts, :lease)
    }

    %{base | digest: digest(base)}
  end

  @doc "Plain map with string keys (`digest` included), suitable for canonical encoding."
  # Accepts any evidence struct, including one whose digest is not yet computed (see new/4).
  @spec to_map(%__MODULE__{}) :: map()
  def to_map(%__MODULE__{} = ev) do
    %{
      "admission" => to_string(ev.admission),
      "standing" => to_string(ev.standing),
      "input_digest" => ev.input_digest,
      "graph_ids" => normalize(ev.graph_ids),
      "receipts" => normalize(ev.receipts),
      "digest" => ev.digest,
      "wasm_sha256" => ev.wasm_sha256,
      "graphlaw_release" => ev.graphlaw_release,
      "lease" => normalize(ev.lease)
    }
  end

  @doc "SHA-256 (lowercase hex) of the canonical sorted-key JSON of the evidence, excluding `digest`."
  # Takes any evidence struct, including one whose own digest is not yet computed.
  @spec digest(%__MODULE__{}) :: String.t()
  def digest(%__MODULE__{} = ev) do
    ev
    |> to_map()
    |> Map.delete("digest")
    |> canonical_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "Canonical JSON: recursively sorted map keys, compact encoding."
  @spec canonical_json(term()) :: binary()
  def canonical_json(term), do: term |> sorted() |> Jason.encode!()

  @known_opts [:wasm_sha256, :graphlaw_release, :lease]
  @lease_keys [:ceiling, :lease_id, :key_id, :lease_digest]

  defp check_opts(opts) do
    case Keyword.keys(opts) -- @known_opts do
      [] -> check_lease(Keyword.get(opts, :lease))
      unknown -> raise ArgumentError, "unknown AshGraphLaw.Evidence.new/4 options: #{inspect(unknown)}"
    end
  end

  # A lease is recorded only as the identity `Authority.identity/1` builds, never as free-form data.
  defp check_lease(nil), do: :ok

  defp check_lease(%{ceiling: ceiling} = lease) when ceiling in [:observe, :select, :construct] do
    if Enum.sort(Map.keys(lease)) == Enum.sort(@lease_keys),
      do: :ok,
      else: raise(ArgumentError, "Evidence lease identity has unexpected keys: #{inspect(Map.keys(lease))}")
  end

  defp check_lease(other),
    do: raise(ArgumentError, "Evidence :lease must be an Authority identity or nil, got: #{inspect(other)}")

  defp receipt_map(%Receipt{raw: raw}) when is_map(raw) and map_size(raw) > 0, do: raw

  defp receipt_map(%Receipt{} = r) do
    r |> Map.from_struct() |> Map.delete(:raw) |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
  end

  # Convert atom keys/values into JSON-native strings so to_map/1 is string-keyed throughout.
  defp normalize(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), normalize(v)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(nil), do: nil
  defp normalize(bool) when is_boolean(bool), do: bool
  defp normalize(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp normalize(other), do: other

  defp sorted(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), sorted(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp sorted(list) when is_list(list), do: Enum.map(list, &sorted/1)
  defp sorted(other), do: other
end
