<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Release a Version

The release ladder for a tagged version. The coordinator owns commits, tags and publishing; this
page describes the gates, not a way around them.

## Ladder

```bash
scripts/vendor_registry.sh --check
scripts/import_registry.sh --check
scripts/ggen_sync.sh --check
scripts/ggen_sync.sh --check-ledger
scripts/ggen_sync.sh --check-versions
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix ash_graphlaw.vendor && mix ash_graphlaw.verify
mix test --include wasm
mix ash_graphlaw.parity --evidence-dir tmp/evidence
mix ash_graphlaw.mutate --require-killed
mix hex.build
```

Run the cheapest gate first and stop at the first failure. Record the exit code of each.

## Version bindings

The library version is calendar-versioned (`YY.M.N`). The engine pin (`glx:engineReleaseTag`,
`glx:wasmSha256`, `glx:wasmUrl`, `priv/graphlaw/MANIFEST.json`, `@graphlaw_release` in
`lib/ash_graphlaw.ex`) moves in its own step. Bumping it needs the release asset's real sha256
from the published GraphLaw release; do not derive it from a local build.

## Tag and publish

`.github/workflows/release.yml` runs on a `v*` tag, repeats every CI gate on the tag subject,
attests provenance and SBOM, and publishes only when a `HEX_API_KEY` secret is configured.
`workflow_dispatch` runs `mix hex.publish --dry-run` only.

## Receipts

A release claim is `ALIVE` only with an exact-SHA receipt. Before that, claims stay
`PARTIAL_ALIVE` or `UNKNOWN`; see [claims and evidence](../reference/claims_and_evidence.md).

## See Also

- [Reproduce](../../REPRODUCE.md)
- [Upgrading](../topics/upgrading.md)
- [Contributing](../../CONTRIBUTING.md)
