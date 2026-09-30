<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# telemetry

Events emitted by the library. All measurements are integers; durations are in native time units
(`System.convert_time_unit(d, :native, :millisecond)`). A telemetry event is an observation, never
authority.

## Capability span (`AshGraphLaw.Telemetry.capability/3`)

Wraps every typed capability `run/2`.

| Event | Measurements | Metadata |
|---|---|---|
| `[:ash_graphlaw, :capability, :start]` | `system_time` | `op`, `server` |
| `[:ash_graphlaw, :capability, :stop]` | `duration` | `op`, `server`, `outcome` (`:ok` or `:refused`), `refusal_code` (atom or `nil`) |
| `[:ash_graphlaw, :capability, :exception]` | `duration` | `op`, `server`, `outcome: :exception`, `refusal_code: nil`, `kind`, `reason`, `stacktrace` |

The exception is re-raised after the event. `AshGraphLaw.Telemetry.events/0` lists these three and
the admission event.

## Admission

| Event | Measurements | Metadata |
|---|---|---|
| `[:ash_graphlaw, :admission, :stop]` | `duration` | `admission`, `outcome` (`:admitted` or `:refused`), `code`, `standing` |

Emitted by `Change.Admit` and `Validation.Admissible`.

## Host and engine

| Event | Measurements | Metadata |
|---|---|---|
| `[:ash_graphlaw, :host, :call, :stop]` | `duration` | `op`, `outcome`, `code` |
| `[:ash_graphlaw, :host, :recycle]` | `count` | `reason`, `wasm_sha256` |
| `[:ash_graphlaw, :engine, :admit]` | none | `outcome` (`:admitted` or `:refused`), `code`, `wasm_sha256` |

Metadata carries codes, ids and digests. It does not carry projected data.

## See Also

- [Observe with telemetry](../how_to/observe_with_telemetry.md)
- [Typed refusals](typed_refusals.md)
