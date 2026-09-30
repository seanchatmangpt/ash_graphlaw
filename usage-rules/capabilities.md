<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Capabilities

- Call ops through `AshGraphLaw.Capability.API.<op>/2` or the root delegates. Do not build raw
  request maps for a supported op; `call/2` stays for raw or future ops.
- Arguments: keyword list or map, snake_case registry names. A bare binary for a `data_spec` field
  is `%{"text" => binary}`. Unknown keys, missing required fields and type mismatches are
  `:invalid_capability_request`. Registry `enum` values are never enforced client-side.
- Results: match on the struct fields and `kind`; keep a fallback for `{:unknown, tag}`. Read
  unknown fields from `raw`. `from_map/1` never raises and `raw` is the entire response.
- Refusals: match on `code`, `class`, `broken_term`, never on message text. Engine refusal detail
  is in `raw`.
- Declare `capability` entities to restrict a resource; declare none to allow all. Never declare a
  ceiling below `Authority.op_ceiling/1`.
- Never implement RDF, SPARQL, SHACL, ShEx, N3, Datalog, entailment or planning behavior in a
  wrapper.
- A typed result is `PARTIAL_ALIVE` at most.
- The generated reference is `documentation/reference/capabilities.md`; do not edit it.

See [use typed capabilities](../documentation/how_to/use_typed_capabilities.md).
