<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Observe with Telemetry

Attach handlers to the events the library emits. Event details are in the
[telemetry reference](../reference/telemetry.md).

## Attach

```elixir
:telemetry.attach_many(
  "my-app-graphlaw",
  AshGraphLaw.Telemetry.events(),
  fn event, measurements, metadata, _config ->
    Logger.info("graphlaw #{inspect(event)} #{inspect(measurements)} #{inspect(metadata)}")
  end,
  nil
)
```

`AshGraphLaw.Telemetry.events/0` lists the capability span events (`:start`, `:stop`,
`:exception`), `[:ash_graphlaw, :admission, :stop]`, host call events (`:start`, `:stop`),
and instance recycle events (`[:ash_graphlaw, :host, :recycle]`).

## Aggregate refusals by code

```elixir
:telemetry.attach(
  "refusal-counter",
  [:ash_graphlaw, :capability, :stop],
  fn _event, %{duration: d}, %{op: op, outcome: outcome, refusal_code: code}, _ ->
    if outcome == :refused, do: MyApp.Metrics.count("graphlaw.refused", %{op: op, code: code})
    MyApp.Metrics.timing("graphlaw.capability", System.convert_time_unit(d, :native, :millisecond))
  end,
  nil
)
```

## Phoenix Integration

In your Phoenix application's telemetry module (`lib/my_app_web/telemetry.ex`), add GraphLaw metrics to `metrics/0`:

```elixir
def metrics do
  [
    # Phoenix / LiveView metrics ...

    # AshGraphLaw Capability Spans
    summary("ash_graphlaw.capability.stop.duration",
      unit: {:native, :millisecond},
      tags: [:op, :outcome],
      description: "Latency of GraphLaw capability executions"
    ),
    counter("ash_graphlaw.capability.stop.count",
      tags: [:op, :outcome, :refusal_code],
      description: "Total capability invocations categorized by refusal code"
    ),

    # AshGraphLaw Host Execution
    summary("ash_graphlaw.host.call.stop.duration",
      unit: {:native, :millisecond},
      tags: [:op, :outcome],
      description: "Low-level WASM host invocation latency"
    ),
    counter("ash_graphlaw.host.recycle.count",
      tags: [:reason],
      description: "Count of WASM instance recycles"
    ),

    # Admission Change / Validation Latency
    summary("ash_graphlaw.admission.stop.duration",
      unit: {:native, :millisecond},
      tags: [:admission, :outcome, :standing],
      description: "Admission action hook duration"
    )
  ]
end
```

## Rules

- A telemetry observation is never authority.
- Metadata carries codes and ids, not projected data.
- A handler that raises is detached by `:telemetry`; keep handlers small.

## See Also

- [Telemetry reference](../reference/telemetry.md)
- [Use typed capabilities](use_typed_capabilities.md)
