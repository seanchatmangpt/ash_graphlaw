# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits DSL legality/authority semantics

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

  ## Ceiling ordering

  Ceilings are totally ordered `:observe < :select < :construct`. A lease satisfies an
  admission when its claimed ceiling is greater than or equal to the admission's `ceiling`
  option. `:observe` (the default) needs no lease at all. A lease never widens what the
  engine derives; it only records that the caller presented the material the ceiling demands.

  ## Signed-lease shape

  The container in `changeset.context[lease_key]` (default key `:graphlaw_lease`) carries the
  signed lease minted by the engine's issuer:

      %{
        signed_lease: %{
          "lease" => %{"id" => "lease-1", "ceiling" => "construct", "...": "..."},
          "attestation" => %{"key_id" => "ops-2026", "signature" => "...", "...": "..."}
        }
      }

  String and atom keys are both accepted. `claim/1` reads `"lease"."ceiling"`; `identity/1`
  reads `"lease"."id"` and `"attestation"."key_id"`. The signature itself is never checked in
  Elixir: verification is the engine's job on the same request.

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

  @typedoc """
  What a lease container presented: the ceiling it claims and the signed lease (if any).

  `signed_lease` is `nil` exactly when `ceiling` is `:observe` because nothing signed was
  presented.
  """
  @type claim :: %{ceiling: :observe | :select | :construct, signed_lease: map() | nil}

  @typedoc """
  Identity of the presented lease, recorded in `AshGraphLaw.Evidence`.

  `lease_digest` is the lowercase-hex SHA-256 of the canonical (sorted-key JSON) signed lease.
  `lease_id` and `key_id` are `nil` when the signed lease omits them.
  """
  @type identity :: %{
          ceiling: :observe | :select | :construct,
          lease_id: String.t() | nil,
          key_id: String.t() | nil,
          lease_digest: String.t() | nil
        }

  @doc """
  What `lease` (a value from changeset context) presents. Only a signed lease claims a ceiling
  above `:observe`.

  Total: any term is accepted, and anything that is not a well-formed signed-lease container
  with a known ceiling claims `:observe` with `signed_lease: nil`.

  ## Examples

      iex> AshGraphLaw.Authority.claim(nil)
      %{ceiling: :observe, signed_lease: nil}

      iex> AshGraphLaw.Authority.claim(%{ceiling: :construct})
      %{ceiling: :observe, signed_lease: nil}

      iex> signed = %{"lease" => %{"ceiling" => "select"}, "attestation" => %{}}
      iex> AshGraphLaw.Authority.claim(%{signed_lease: signed}).ceiling
      :select
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

  `:ok`, or `{:error, %Refusal{code: :ceiling_unmet}}` before the engine is called. The
  refusal details carry `:admission`, `:required` and `:granted`. An admission with ceiling
  `:observe` is always `:ok`.

  This is a presentation check only; the engine still verifies signature, signer and expiry.
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

  @op_ceilings %{
    "capabilities" => :observe,
    "sniff" => :observe,
    "parse" => :observe,
    "convert" => :observe,
    "canonical" => :observe,
    "sparql" => :observe,
    "shacl" => :observe,
    "shex" => :observe,
    "policy" => :observe,
    "n3" => :construct,
    "entail" => :construct,
    "datalog" => :construct,
    "hooks" => :construct,
    "law" => :construct
  }

  @doc """
  The minimum ceiling a capability declaration must carry for engine op `op` (atom or string).

  `:observe` for capabilities, sniff, parse, convert, canonical, sparql, shacl, shex and policy;
  `:construct` for n3, entail, datalog, hooks and law. Any other op is a typed
  `:unknown_capability` refusal.
  """
  @spec op_ceiling(atom() | String.t()) :: {:ok, :observe | :select | :construct} | {:error, Refusal.t()}
  def op_ceiling(op) when is_atom(op) and not is_nil(op), do: op_ceiling(Atom.to_string(op))

  def op_ceiling(op) when is_binary(op) do
    case Map.fetch(@op_ceilings, op) do
      {:ok, ceiling} ->
        {:ok, ceiling}

      :error ->
        {:error,
         Refusal.new(:unknown_capability, "no capability #{inspect(op)} in the GraphLaw registry", %{
           op: op,
           known: @op_ceilings |> Map.keys() |> Enum.sort()
         })}
    end
  end

  def op_ceiling(other),
    do: {:error, Refusal.new(:unknown_capability, "capability #{inspect(other)} is not a name", %{op: inspect(other)})}

  @doc """
  Checks that `resource` may run engine op `op`.

  A resource declaring no capability allows every op (back-compat) and a declared op returns
  `:ok`; an undeclared op on a resource that declares at least one is a typed
  `:capability_not_declared` refusal, and an unknown op is `:unknown_capability`.

  `policy` is a keyword list. With `lease: term`, the ceiling that lease claims (`claim/1`) must
  be at least the declared capability's ceiling, else `:ceiling_unmet`. Presentation check only;
  the engine still verifies signature, signer and expiry.
  """
  @spec check_op(module(), atom() | String.t(), keyword()) :: :ok | {:error, Refusal.t()}
  def check_op(resource, op, policy \\ []) when is_list(policy) do
    with {:ok, _required} <- op_ceiling(op) do
      case Admissions.capabilities(resource) do
        [] -> :ok
        _declared -> check_declared(resource, op, policy)
      end
    end
  end

  defp check_declared(resource, op, policy) do
    with {:ok, capability} <- Admissions.capability(resource, op) do
      if Keyword.has_key?(policy, :lease) do
        %{ceiling: granted} = claim(Keyword.fetch!(policy, :lease))
        required = capability.ceiling

        if Map.fetch!(@ceiling_rank, granted) >= Map.fetch!(@ceiling_rank, required) do
          :ok
        else
          {:error,
           Refusal.new(
             :ceiling_unmet,
             "capability #{inspect(capability.name)} requires ceiling #{required}, lease grants #{granted}",
             %{capability: to_string(capability.name), required: required, granted: granted}
           )}
        end
      else
        :ok
      end
    end
  end

  @doc """
  The engine options both admission paths send: `:server`, `:timeout`, the runtime's
  `max_skew_secs` and `trusted_keys`, and the signed lease when one was presented.

  `opts` may override `:server` (default `AshGraphLaw.Pool`) and `:timeout` (default the
  runtime's `timeout_ms`); every other key is ignored, so caller options can never supply
  trust anchors, a clock or an unsigned lease.
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
