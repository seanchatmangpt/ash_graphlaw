<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Production

- Vendor the engine in the release build with `mix ash_graphlaw.vendor`; the hex package ships no
  wasm. Run `mix ash_graphlaw.verify` in the deploy pipeline.
- Start `AshGraphLaw.Pool` under your supervisor (or `start_pool: true`). Size it to expected
  concurrency; one host serializes its calls. Handle `:saturated` as load shedding.
- Keep `expected_sha256` unset in production so the manifest pin applies. An explicit `wasm_path`
  outside the vendored path is unpinned and belongs in tests only.
- List only real trust anchors in `trusted_keys`. Keep `max_skew_secs` at 60 unless clocks demand
  otherwise.
- Attach telemetry handlers for `[:ash_graphlaw, :capability, :stop]` and
  `[:ash_graphlaw, :admission, :stop]`; alert on `refusal_code` values in the `blocked_resource`
  class.
- Set `require_atomic? false` on actions that carry an admission.
- Run `mix ash_graphlaw.parity` after every engine pin change, before rollout.
- Never treat an admission as authorization in production paths.

See [run the pool](../documentation/how_to/run_the_pool.md) and
[configuration](../documentation/reference/configuration.md).
