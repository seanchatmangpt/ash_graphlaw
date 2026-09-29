# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.Lease do
  @moduledoc """
  UNSUPPORTED(generator-capability): test-only builder of REAL signed GraphLaw leases.

  Leases are signed with real Ed25519 (`:crypto`) over the canonical payload the engine verifies
  (graphlaw `attest.rs`): the sorted-key JSON of the lease, `payload_sha256` = sha256(payload),
  `key_id` = sha256(raw public key). Nothing here is a stand-in for verification: the engine
  verifies signature, signer and expiry itself.

  Two fixed keypairs (deterministic seeds) keep resources compilable: `:trusted` is listed in the
  `runtime` section of `AshGraphLaw.Test.Ticket` (`public_key_hex/0`), `:untrusted` is a valid
  signer the resource does not trust.

  The default scope names every engine step, so a lease bounds authority through its ceiling only.
  """

  @scope ~w(admit:shacl derive:n3 derive:hooks admit:plan admit:require-receipt admit:require-signed-receipt derive:rdfs derive:owl-rl)
  @seeds %{trusted: 7, untrusted: 9}
  @far_future 4_000_000_000

  @doc "Hex public key of the trusted signer (goes in `runtime trusted_keys`)."
  @spec public_key_hex(:trusted | :untrusted) :: String.t()
  def public_key_hex(signer \\ :trusted), do: signer |> keypair() |> elem(0) |> Base.encode16(case: :lower)

  @doc """
  A signed lease map (`%{"lease" => ..., "attestation" => ...}`) for `ceiling`.

  Options: `:signer` (`:trusted` | `:untrusted`), `:expires_unix`, `:scope`, `:id`, `:tamper`
  (a map merged into the lease body AFTER signing, so the signature no longer matches).
  """
  @spec signed(:observe | :select | :construct, keyword()) :: map()
  def signed(ceiling, opts \\ []) do
    {pub, priv} = opts |> Keyword.get(:signer, :trusted) |> keypair()
    expires = Keyword.get(opts, :expires_unix, @far_future)
    scope = Keyword.get(opts, :scope, @scope)
    id = Keyword.get(opts, :id, "L-#{ceiling}")

    payload =
      ~s({"ceiling":"#{ceiling}","expires_unix":#{expires},"holder":"test","id":"#{id}","issued_unix":0,"scope":#{Jason.encode!(scope)}})

    lease =
      %{
        "id" => id,
        "holder" => "test",
        "ceiling" => Atom.to_string(ceiling),
        "scope" => scope,
        "expires_unix" => expires,
        "issued_unix" => 0
      }
      |> Map.merge(Keyword.get(opts, :tamper, %{}))

    %{
      "lease" => lease,
      "attestation" => %{
        "key_id" => sha256_hex(pub),
        "payload_sha256" => sha256_hex(payload),
        "signature" => :eddsa |> :crypto.sign(:none, payload, [priv, :ed25519]) |> Base.encode16(case: :lower)
      }
    }
  end

  @doc "Lease container as it goes into a changeset context value: `%{signed_lease: signed}`."
  @spec container(:observe | :select | :construct, keyword()) :: %{signed_lease: map()}
  def container(ceiling, opts \\ []), do: %{signed_lease: signed(ceiling, opts)}

  @doc "Changeset context carrying a real signed lease under `:graphlaw_lease`."
  @spec context(:observe | :select | :construct, keyword()) :: %{graphlaw_lease: map()}
  def context(ceiling, opts \\ []), do: %{graphlaw_lease: container(ceiling, opts)}

  defp keypair(signer) do
    seed = Map.fetch!(@seeds, signer)
    :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<seed>>, 32))
  end

  defp sha256_hex(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
