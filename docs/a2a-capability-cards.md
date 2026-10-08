<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# A2A v1.0 Capability Cards

`priv/graphlaw/cards/*.json` carry one A2A v1.0 agent-card-shaped capability card per
`gac:Capability` individual in the vendored GraphLaw registry
(`priv/graphlaw/capability-registry.ttl`, canonical JSON
`priv/graphlaw/capability-registry.json`): 14 cards, one per registry `ops` entry.

## Shape

Generated to the ash_a2a codec surface (`AshA2A.Protocol.AgentCard`, A2A v1.0 spec
sections 4.4/8.2):

- `name`, `description`, `version` (the pinned registry `graphlaw_version`)
- `skills` — exactly one per card, `{id, name, description, tags}`; the id is
  `graphlaw.<capability>.<verb-form>` (e.g. `graphlaw.canonical.canonicalize`)
- `supportedInterfaces` — `{url, protocolBinding, protocolVersion}` with
  `protocolBinding: "HTTP+JSON"` and `protocolVersion: "1.0"`; the url is the registry op IRI

There is no top-level `url` and no `preferredTransport`: the wasm host is not a network
endpoint, and v1.0 transport preference is positional on `supportedInterfaces`.

## Authority boundary

Every card description states the same boundary: the cards are served by the digest-pinned
`graphlaw.wasm` host, which is SELECT/CONSTRUCT only — it derives and validates, it never
authorizes and never carries DO. A successful typed call is an observation, not standing.

## Generation law

The cards are generated, never hand-edited. `scripts/import_registry.sh` (write mode)
regenerates them from the registry JSON via
`scripts/generate_capability_cards.py`, after the same `registry_sha256` digest check the
registry splice uses. `scripts/import_registry.sh --check` also verifies card drift and
exits non-zero on any difference. Stale cards (a capability removed from the registry) are
deleted on the next write-mode run.

## Regenerate

    scripts/import_registry.sh          # splice registry + regenerate cards
    scripts/import_registry.sh --check  # verify ontology.ttl and cards, write nothing
