<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Security Policy

## Supported versions

`ash_graphlaw` uses calendar versioning (`YY.M.N`). Security fixes land on `main` and ship in the
next release; only the newest published version is supported.

| Version | Supported | Notes |
|---|---|---|
| latest `26.9.x` | yes | fixes are applied to the newest release only |
| older releases | no | upgrade to the newest release |
| `main` (unreleased) | best effort | may be ahead of the last release; see [CHANGELOG](CHANGELOG.md) |

## Reporting a vulnerability

Do not open a public issue for a vulnerability. Report it privately through GitHub Private
Vulnerability Reporting for `seanchatmangpt/ash_graphlaw`:
<https://github.com/seanchatmangpt/ash_graphlaw/security/advisories/new>.

Include the impact, the affected version or commit SHA, and a reproduction if possible. Include the
refusal `code` if the library returned one (see
[typed refusals](documentation/reference/typed_refusals.md)). Never include live credentials.

If the form is unavailable, open a public issue titled `Security contact request` that contains no
vulnerability details, and the maintainer will open a private advisory and invite you to it.

## Scope

In scope:

- **WASM supply chain.** The GraphLaw engine is pinned by SHA-256 in `priv/graphlaw/MANIFEST.json`.
  A bypass of the digest pin, of the import-surface check (only `wasi_snapshot_preview1` imports are
  accepted) or of the required-export check in `AshGraphLaw.EngineLoad`, a path by which the vendor
  task uses bytes that do not match the pin, or a way for environment or application config to swap
  the engine without the pin applying.
- **Resource limits.** Bypasses of per-call fuel, the store memory limit, the request size limit
  (16 MiB), the call timeout or queue shedding in `AshGraphLaw.Host` and `AshGraphLaw.Pool`, and any
  input that crashes the calling process instead of returning a typed refusal.
- **Authority boundary.** Any path where an admission result is treated as authority, where a
  `ceiling` is not checked before the engine runs, or where `AshGraphLaw.Standing` reports `:ALIVE`
  from an admission alone.
- **Refusal integrity.** Untyped or unclassified failures that escape `AshGraphLaw.Refusal`.
- **CI and release workflows** in `.github/`.

Out of scope: vulnerabilities in GraphLaw itself (report them to the GraphLaw repository), in Ash,
Spark or Wasmex (report upstream), and denial of service that requires configuring limits above the
documented defaults.

## Security model

GraphLaw derives and validates; it never authorizes. This library transports a projected request to
the pinned engine and returns a typed success or refusal. Admission evidence is an observation bound
to an exact input digest and grants no authority. Signed leases and receipts are verified by
GraphLaw against the trusted keys configured in the `runtime` entity.

## Response targets

Solo maintainer, best effort, business days: acknowledge in 3 days, triage in 7 days. Fixes are
developed in a private advisory and published with credit to the reporter unless they ask otherwise.
