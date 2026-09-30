# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Authority do
  @moduledoc """
  The single authority boundary shared by `AshGraphLaw.Change.Admit` and
  `AshGraphLaw.Validation.Admissible`.
  UNSUPPORTED(generator-capability): hand-written; authority policy is not a pack capability.

  GraphLaw derives and validates; it never authorizes. This module decides only whether the
  caller has *presented* the material an admission's `ceiling` demands, and builds the one set
  of engine options both admission paths send. It grants nothing.

  ## What counts as a lease

  Only a **signed** lease counts: `changeset.context[lease_key]` must be a map or keyword list
  with a `:signed_lease` entry, itself a map `%{"lease" => %{"ceiling" => ...}, "attestation" =>
  ...}` (string or atom keys). Everything else grants `:observe`: a bare ceiling atom, a map with
  a bare `:ceiling` key, `:lease` (unsigned), `:unverified_lease`, `nil`.

  A caller can therefore never self-grant `:select` or `:construct` by writing an atom into
  changeset context. The ceiling a signed lease *claims* is compared with the admission's
  required ceiling here, before the engine is called; the signature, the trusted signer and the
  expiry are forwarded to the engine on the same request. The pinned GraphLaw v26.9.28 engine
  ignores lease keys entirely (`UNSUPPORTED(engine-capability)`): it neither verifies the
  signature, signer or expiry nor stamps a `lease_id`, so the ONLY lease check enforced today is
  this ceiling pre-check on the *claimed* ceiling. A lease-verifying engine would refuse a forged
  claim as `:lease_refused`; the pinned one does not. Evidence records the lease identity
  (`identity/1`) so the authority behind an admitted change can be replayed.

  ## Trust anchors and time

  `engine_opts/3` takes `trusted_keys` and `max_skew_secs` ONLY from the resource's `runtime`
  section, and never forwards `now_unix`, `lease` or `unverified_lease`. A lease-verifying engine would
  judge expiry with its own module clock (the pinned v26.9.28 engine does not). Caller context cannot supply trust anchors or a clock.
  """

  alias AshGraphLaw.Admissions
  alias AshGraphLaw.Dsl.Admission
  alias AshGraphLaw.Evidence
  alias AshGraphLaw.Refusal

  @ceiling_rank %{observe: 0, select: 1, construct: 2}
  @ceiling_names %{"observe" => :observe, "select" => :select, "construct" => :construct}

  @typedoc "What a lease container presented: the ceiling it claims and the signed lease (if any)."
  @type claim :: %{ceiling: :observe | :select | :construct, signed_lease: map() | nil}

  @typedoc "Identity of the presented lease, recorded in `AshGraphLaw.Evidence`."
  @type identity :: %{
          ceiling: :observe | :select | :construct,
          lease_id: String.t() | nil,
          key_id: String.t() | nil,
          lease_digest: String.t() | nil
        }

  @doc """
  What `lease` (a value from changeset context) presents. Only a signed lease claims a ceiling
  above `:observe`.
  """
  @spec claim(term()) :: claim()
  def claim(lease) do
    with %{} = signed <- signed_lease(lease),
         %{} = body <- get(signed, "lease"),
         ceiling when is_map_key(@ceiling_rank, ceiling) <- ceiling_of(get(body, "ceiling")) do
      %{ceiling: ceiling, signed_lease: signed}
    else
      _ -> %{ceiling: :observe, signed_lease: nil}
    end
  end

  @doc """
  Checks the presented lease against the admission's required ceiling.

  `:ok`, or `{:error, %Refusal{code: :ceiling_unmet}}` before the engine is called.
  """
  @spec check_ceiling(struct(), term()) :: :ok | {:error, Refusal.t()}
  def check_ceiling(%Admission{ceiling: :observe}, _lease), do: :ok

  def check_ceiling(%Admission{ceiling: required, name: name}, lease) do
    %{ceiling: granted} = claim(lease)

    if Map.fetch!(@ceiling_rank, granted) >= Map.fetch!(@ceiling_rank, required) do
      :ok
    else
      {:error,
       Refusal.new(
         :ceiling_unmet,
         "admission #{inspect(name)} requires ceiling #{required}, lease grants #{granted}",
         %{admission: name, required: required, granted: granted}
       )}
    end
  end

  @doc """
  The engine options both admission paths send: `:server`, `:timeout`, the runtime's
  `max_skew_secs` and `trusted_keys`, and the signed lease when one was presented.
  """
  @spec engine_opts(module(), term(), keyword()) :: keyword()
  def engine_opts(resource, lease, opts) do
    runtime = Admissions.runtime(resource)

    base = [
      server: opts[:server] || AshGraphLaw.Pool,
      timeout: opts[:timeout] || runtime.timeout_ms,
      max_skew_secs: runtime.max_skew_secs,
      trusted_keys: runtime.trusted_keys
    ]

    case claim(lease) do
      %{signed_lease: %{} = signed} -> base ++ [signed_lease: signed]
      %{signed_lease: nil} -> base
    end
  end

  @doc """
  Identity of the presented lease for evidence: ceiling, lease id, signer key id and the
  SHA-256 of the canonical signed lease. `nil` when no signed lease was presented.
  """
  @spec identity(term()) :: identity() | nil
  def identity(lease) do
    case claim(lease) do
      %{signed_lease: nil} ->
        nil

      %{ceiling: ceiling, signed_lease: signed} ->
        %{
          ceiling: ceiling,
          lease_id: signed |> get("lease") |> get("id"),
          key_id: signed |> get("attestation") |> get("key_id"),
          lease_digest: signed |> normalize() |> Evidence.canonical_json() |> sha256()
        }
    end
  end

  defp signed_lease(lease) when is_map(lease) and not is_struct(lease), do: fetch_signed(lease)
  defp signed_lease(lease) when is_list(lease), do: if(Keyword.keyword?(lease), do: fetch_signed(Map.new(lease)))
  defp signed_lease(_lease), do: nil

  defp fetch_signed(container) do
    case Map.get(container, :signed_lease) do
      %{} = signed -> signed
      _ -> nil
    end
  end

  defp ceiling_of(value) when is_binary(value), do: Map.get(@ceiling_names, value)
  defp ceiling_of(value) when is_atom(value) and not is_nil(value), do: ceiling_of(Atom.to_string(value))
  defp ceiling_of(_value), do: nil

  # String or atom keys.
  defp get(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, String.to_existing_atom(key))
    end
  rescue
    ArgumentError -> nil
  end

  defp get(_other, _key), do: nil

  defp normalize(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), normalize(v)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(other), do: other

  defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
