<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# abi_reference

The wire contract between `AshGraphLaw.Host` and `graphlaw.wasm`. Source of truth is the GraphLaw
repository (`wasm/src/lib.rs`, `src/abi.rs`, `docs/refusals.md`) and the capability registry
generated from it (`registry/capability-registry.json`).

## Versions

| Item | Value |
|---|---|
| `ABI_VERSION` | `1` |
| Pinned GraphLaw release | `v26.9.29` |
| Pinned asset | `graphlaw.wasm`, sha256 `7bb2a7e5ebcef7584b0b960451272d56fa75414d76a12138d41e8973e126eee0` |
| Capability registry | `graphlaw.capability-registry/1`, GraphLaw `26.9.29`; the same release this library pins |

`ABI_VERSION` is bumped on any incompatible request or response change. A host must compare the
`abi_version` field of the `capabilities` response with its own expectation and refuse a mismatch
(`:abi_version_mismatch`).

## Module surface

The module imports only `wasi_snapshot_preview1` and exports `gl_alloc`, `gl_free`, `gl_call`
and `memory`. If `_initialize` is exported the host calls it once before the first request.

| Export | Signature | Behaviour |
|---|---|---|
| `gl_alloc` | `(len: u32) -> ptr: u32` | Reserves `len` bytes. Returns 0 when `len` exceeds `MAX_REQUEST_BYTES`. |
| `gl_call` | `(ptr: u32, len: u32) -> u64` | Runs one request and consumes (frees) the request buffer. |
| `gl_free` | `(ptr: u32, len: u32)` | Releases a buffer from `gl_alloc` or a `gl_call` response. |

## Call protocol

```text
1. ptr  = gl_alloc(len)
2. write request bytes (UTF-8 JSON) at ptr
3. packed = gl_call(ptr, len)
4. out_ptr = packed >>> 32 ; out_len = packed &&& 0xFFFFFFFF
5. read out_len bytes at out_ptr, decode as UTF-8 JSON
6. gl_free(out_ptr, out_len)
```

Host rules:

- The return value is an unsigned 64-bit integer. A runtime that reports it as a signed i64 shows
  a negative number when the high bit is set; add 2^64 before unpacking
  (`AshGraphLaw.ABI.unpack_result/1`).
- The request buffer is consumed by `gl_call`; never `gl_free` it afterwards.
- A null pointer passed to `gl_call` yields a typed JSON error, not a trap. A `len` above
  `MAX_REQUEST_BYTES` yields a `request_bytes` `ResourceLimit` refusal without reading memory.
- Steps 1 to 6 are one transaction; the host serializes them (see
  [wasm host design](../topics/wasm_host_design.md)).

## Envelope

Request: a JSON object with a string `"op"` member.

```json
{"op": "capabilities"}
```

Success response:

```json
{"ok": true}
```

plus op-specific members. Refusal response:

```json
{"ok": false, "error": {"kind": "...", "engine": "...", "dialect": null, "message": "...",
                        "details": {"code": "..."}}}
```

`error.{kind,engine,dialect,message}` are always present for `law` and `policy` refusals;
`details` is a machine-readable object keyed by `code`. Clients read `details`, never `message`.
`AshGraphLaw.Host.request/3` returns the decoded map for both `ok` values;
`AshGraphLaw.call/2` turns `"ok": false` into `{:error, %AshGraphLaw.Refusal{}}`.

## Data spec

Ops that take a document use
`{"text": "...", "dialect"?: "turtle", "hint"?: "ttl", "base"?: "..."}`.
Without `dialect` the router sniffs the content by content, not by extension.

## Ops

| Op | Purpose |
|---|---|
| `capabilities` | ABI version, crate version, authorities and revisions, dialects, op list |
| `sniff` | Route text to a dialect and owning engine |
| `parse` | Parse a document; returns dialect, quad count and state id |
| `convert` | Re-serialize a document to another RDF dialect (`to`) |
| `canonical` | RDFC-1.0 canonical N-Quads and `sha256:` state id |
| `sparql` | Run a SPARQL query (`query`) over `data` |
| `shacl` | Validate `data` against shapes |
| `shex` | Validate `data` against ShEx |
| `n3` | Notation3 reasoning over `text` |
| `entail` | RDF/RDFS/OWL-RL/D entailment |
| `datalog` | Datalog evaluation |
| `hooks` | Run a knowledge-hook pack over `data` |
| `law` | Ordered admission steps over `data`; returns states, receipts, N-Quads |
| `policy` | Admit a FOND policy against a planning problem |

The ABI has 14 ops, in this order: `capabilities sniff parse convert canonical sparql shacl shex
n3 entail datalog hooks law policy`. Each has a typed module, API function and (except `law`) a
result struct in AshGraphLaw; `call/2` stays available for raw requests. See the
[support matrix](support_matrix.md) for the per-op table and
[capabilities.md](capabilities.md) (generated) for request and response fields.

### `capabilities` response

| Field | Since | Meaning |
|---|---|---|
| `abi`, `abi_version`, `crate`, `authorities`, `rdf_dialects`, `other_dialects`, `ops` | v26.9.28 | as before |
| `registry_schema`, `registry_sha256`, `surface_sha256` | v26.9.29 | registry identity; absent on older engines |

For an engine older than v26.9.29 the host computes `surface_sha256` from the live response and
treats `registry_sha256` as UNKNOWN. The digest rule is canonical JSON (sorted keys, compact,
integers only); `AshGraphLaw.Capability.CanonicalJSON` implements it.

### `law` op

```json
{"op": "law",
 "data": {"text": "<n-triples>", "dialect": "ntriples"},
 "steps": [{"step": "shacl", "shapes": "<turtle>"}]}
```

Steps:

| `step` | Members |
|---|---|
| `shacl` | `shapes` (Turtle) |
| `n3` | `rules` |
| `rdfs`, `owl-rl` | none |
| `hooks` | `pack` (data spec) |
| `plan` | `plan`: `{"actions": [{"name","pre","pre_not"?,"add","del"}], "goal", "goal_not"?}`, N-Triples strings |
| `record-receipts` | none; writes receipts produced so far into the state |
| `require-receipt` | `step_name`; refuses unless that step's receipt is recorded (presence only) |
| `require-signed-receipt` | `step_name`, `trusted_keys` (hex Ed25519 public keys) |

Success members: `states` (state ids, start first), `receipts` (each with `step`, `parent`,
`child`, `added`, `authority`, `revision`, and where applicable `lease_id`, `plan_sha256`,
`index`), `nquads` (final state).

> **Pinned engine gap (`UNSUPPORTED(engine-capability)`).** Measured against the v26.9.28 engine, not re-measured for the pinned v26.9.29 engine:
> implements `shacl`, `n3`, `rdfs`, `owl-rl` and `hooks` only. `plan`, `record-receipts`,
> `require-receipt` and `require-signed-receipt` are refused with kind `Unsupported`
> ("unknown step `plan`", etc.), which the library projects as `engine_refused` /
> `refused_structure` (standing `UNKNOWN`). The engine also ignores lease keys entirely: it
> does not verify signature, signer or expiry, and receipts carry no `lease_id`. The
> `PlanRefused`, `LeaseRefused`, `UnverifiedLeaseRefused`, `ReceiptRequired` and `ReceiptRefused`
> codes below are therefore documented ABI shapes that v26.9.28 never emitted. A SHACL violation
> is reported as kind `EngineRejected` without a `details.code` (`engine_refused`, not
> `not_admitted`), and JSON nested beyond the depth limit is reported as kind `Unsupported`
> ("request is not JSON: recursion limit exceeded"), not `ResourceLimit`. The `policy` op is not
> in the engine's capabilities.

Leases on a `law` request (shape per the ABI; not enforced by v26.9.28, see above): `signed_lease` (`{"lease": {...}, "attestation": {...}}`) with
`trusted_keys` and optional `max_skew_secs` (default 60); or an unsigned `lease` refused unless
`unverified_lease: true` and the caller supplies `now_unix`. For a signed lease the module uses
its own clock and ignores `now_unix`. Required ceilings: `Observe` for gates, `Select` for
`plan`, `Construct` for `derive:*`.

## Law steps

Wire names, each with its ceiling: `shacl` (observe), `n3` (construct), `rdfs` (construct),
`owl-rl` (construct), `hooks` (construct), `plan` (select), `record-receipts` (none),
`require-receipt` (observe), `require-signed-receipt` (observe). The admission DSL exposes these
with hyphens as underscores, except `record-receipts`.

## Regimes and vocabularies

`entail` regimes: `simple`, `rdf`, `rdfs`, `owl-rl`, `d`. Lease ceilings: `observe`, `select`,
`construct`. Engines: `PurRdf`, `Eyeron`. Enum values in the registry are informational; clients
never enforce them.

## Limits

Checked before parsing or heavy work; over-limit input returns `kind: "ResourceLimit"`.

| `limit` | Constant | Value |
|---|---|---|
| `request_bytes` | `MAX_REQUEST_BYTES` | 16 MiB |
| `json_depth` | `MAX_JSON_DEPTH` | 64 |
| `plan_actions` | `MAX_PLAN_ACTIONS` | 1,000 |
| `atoms_per_field` | `MAX_ATOMS_PER_FIELD` | 10,000 |
| `policy_entries` | `MAX_POLICY_ENTRIES` | 100,000 |
| `n3_iterations` | `law::N3_MAX_ITERATIONS` | 4,000 |

## Refusal details codes

`details.code` values emitted by the engine:

| `details.code` | Fields |
|---|---|
| `NotAdmitted` | `violations: [{focus, path, component, message, severity}]` |
| `PlanRefused` | `index`, `action`, `unmet`, `violated_absent` |
| `PolicyRefused` | `policy_kind`, `state`, `action` |
| `LeaseRefused` | `reason` (`expired`, `out_of_scope`, `ceiling`, `bad_signature`, `untrusted_key`, `clock_skew`), `lease_id`, `step` |
| `UnverifiedLeaseRefused` | none (an unsigned `lease` without `unverified_lease: true`) |
| `ReceiptRequired` | `step` |
| `ReceiptRefused` | `step`, `reason` |
| `Refused` | `kind` (`NotSemanticContent`, `Ambiguous`, `EngineRejected`, `Unsupported`, `ResourceLimit`) |
| `ResourceLimit` | `limit`, `observed`, `max` |

The engine enums are `non_exhaustive`. `AshGraphLaw.Refusal.from_engine/2` resolves a refusal in
this order: a `details.code` in the table (`NotAdmitted`, `PlanRefused`, `ReceiptRequired`,
`ReceiptRefused` -> `:receipt_required`, `LeaseRefused` and `UnverifiedLeaseRefused` ->
`:lease_refused`, `ResourceLimit`, `PolicyRefused`) maps to its code; otherwise a known engine
`kind` (`NotSemanticContent`, `Ambiguous`, `EngineRejected`, `Unsupported`, `ResourceLimit`, the
generic `Refused` case) maps to `:engine_refused`; anything else is a future variant and maps to
`:engine_unclassified` (class `:unsupported`) rather than crashing. The mapping of these codes to
the library's closed code table is in [typed refusals](typed_refusals.md).

## See Also

- [Support matrix](support_matrix.md)
- [WASM host design](../topics/wasm_host_design.md)
- [Typed refusals](typed_refusals.md) (generated)
