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

`AshGraphLaw.Telemetry.events/0` lists the three capability span events and
`[:ash_graphlaw, :admission, :stop]`. Host and engine events are attached by name.

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

## Rules

- A telemetry observation is never authority.
- Metadata carries codes and ids, not projected data.
- A handler that raises is detached by `:telemetry`; keep handlers small.

## See Also

- [Telemetry reference](../reference/telemetry.md)
- [Use typed capabilities](use_typed_capabilities.md)
