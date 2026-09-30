<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Authority

- GraphLaw derives and validates; it never authorizes. `{:ok, %Admitted{}}` is an observation.
- Only a signed lease raises authority above `:observe`. The container is
  `%{signed_lease: %{"lease" => ..., "attestation" => ...}}`. A bare atom, `%{ceiling: _}` or an
  unsigned `lease` claims `:observe`.
- Trust anchors (`trusted_keys`) and `max_skew_secs` come only from the resource `runtime`. Never
  pass them, `now_unix` or `unverified_lease` from caller context or options.
- Ceilings: `:observe` for gates, `:select` for `plan`, `:construct` for derivation steps. The
  check happens before the engine (`:ceiling_unmet`); the engine still verifies the lease
  (`:lease_refused`).
- Never issue or sign a lease in library code. Key custody is outside this library.
- Capabilities: `AshGraphLaw.Authority.op_ceiling/1` is the minimum ceiling per op. Typed ops take
  lease fields as ordinary request arguments; they never smuggle auth through options.
- Never write a code path that maps an admission to permission to act. Ash policies decide who may
  act.

See [security model](../documentation/topics/security_model.md).
