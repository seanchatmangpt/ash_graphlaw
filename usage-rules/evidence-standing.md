<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Evidence and Standing

- Standing vocabulary: `UNKNOWN`, `PARTIAL_ALIVE`, `ALIVE`, `BLOCKED`, `BUILD_BROKEN`,
  `UNSUPPORTED`. Typed REFUSED is carried by `%Refusal{}`, not by standing.
- Standing is derived by `AshGraphLaw.Standing.of/1`, never stored. `{:ok, %Admitted{}}` derives
  `PARTIAL_ALIVE`; `blocked_resource` refusals derive `BLOCKED`, `unsupported` derive
  `UNSUPPORTED`, others `UNKNOWN`.
- `ALIVE` needs observed execution on the exact admitted subject and an exact-SHA receipt. Do not
  write `ALIVE` in code, docs or reports without one.
- A parity court pass, a SHACL conformance or a decoded typed result is `PARTIAL_ALIVE` at most.
- Evidence binds one input digest (sha256 of the projected N-Triples), the engine `wasm_sha256`,
  the release tag and the lease identity. A different engine or input is a different observation.
- `Evidence.digest/1` is over canonical JSON without the `:digest` field. Keep `origin` optional so
  evidence without one keeps its digest.
- Inspection is not execution; compile success is not an admission; a workflow is not a run.
- A claim you did not run is `UNKNOWN`. Write the token `<<RECEIPT:claim-N>>` where a receipt will
  go.

See [claims and evidence](../documentation/reference/claims_and_evidence.md).
