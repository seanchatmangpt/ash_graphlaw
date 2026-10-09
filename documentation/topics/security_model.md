<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# security_model

What the library trusts, what it verifies, and what it leaves to the caller.

## Trust anchors

| Item | Source | Never from |
|---|---|---|
| Trusted signer keys | resource runtime trusted_keys (hex Ed25519, 64 characters each) | caller context, call options |
| Clock skew allowance | resource runtime max_skew_secs (default 60) | caller context |
| Engine identity | `priv/graphlaw/MANIFEST.json` sha256 | GRAPHLAW_WASM_PATH or config alone: a path override is still pinned |
| Lease | the caller presents it; the engine verifies it | the library never signs or issues one |

`now_unix`, `lease` and `unverified_lease` from caller context are never forwarded to the engine on
the admission path.

## Signed lease

The claimed ceiling is checked before the engine (`:ceiling_unmet`). The engine verifies the
signature, the signer against `trusted_keys`, expiry, scope and skew (`:lease_refused`, with a
`reason`). A bare atom, `%{ceiling: _}` or an unsigned lease claims `:observe`. See
[mint and verify a signed lease](../how_to/mint_and_verify_a_signed_lease.md).

## Digest pin

Engine bytes must match the pinned sha256 before they are compiled or instantiated
(`:wasm_digest_mismatch`). Foreign bytes never reach the Wasmtime compiler.

## Import allowlist

The engine may import only the `wasi_snapshot_preview1` functions listed as `glx:WasiImport` rows
(`{name, params, results}`). Others are refused with `:wasm_import_surface_mismatch` naming each
offender. The host passes no preopens, arguments, environment or pipes.

## Resource bounds

Fuel, memory, table size, response size and queue depth are bounded per call
([configuration](../reference/configuration.md)). Over-limit requests are refused with
`:resource_limit`, `:fuel_exhausted` or `:saturated`.

## Typed capability surface

Typed ops add no auth path: lease fields are ordinary request arguments, and typed calls never read
trust anchors from options. A resource that declares `capability` entities restricts which ops its
lifecycle modules may run. Client-side coercion refuses malformed requests before the engine
(`:invalid_capability_request`) and never echoes non-UTF-8 input.

## Not covered

- Key custody and lease issuance.
- Ash policies.
- The correctness of the engine's RDF, SPARQL or SHACL semantics.
- Confidentiality of projected data. `Projection.Default` omits sensitive attributes and arguments;
  a custom projection is your responsibility.

Report vulnerabilities as described in [SECURITY.md](../../SECURITY.md).

## See Also

- [Authority boundary](authority_boundary.md)
- [WASM host design](wasm_host_design.md)
- [Usage rule: authority](../../usage-rules/authority.md)
