# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.PropertyCase do
  @moduledoc """
  UNSUPPORTED(generator-capability): ExUnit case template for `test/property/**`.

  Brings in `ExUnitProperties`, the shared generators and `AshGraphLaw.Refusal`, fixes the
  run budget and prints the ExUnit seed so any failure is reproducible with
  `mix test test/property --seed <seed>`.

  `max_runs/0` is 100 by default; `PROPERTY_MAX_RUNS=<n>` overrides it (for example a large
  nightly budget). Every `check all` in `test/property/**` passes `max_runs: max_runs()`.
  Properties are deterministic under `--seed`: generators are pure and no test reads the clock.
  """

  use ExUnit.CaseTemplate

  @default_max_runs 100

  using _opts do
    quote do
      use ExUnitProperties

      import AshGraphLaw.Test.Generators
      import AshGraphLaw.Test.PropertyCase, only: [max_runs: 0, max_runs: 1]

      alias AshGraphLaw.Refusal

      setup_all do
        AshGraphLaw.Test.PropertyCase.announce(__MODULE__)
        :ok
      end
    end
  end

  @doc "The run budget per property (`PROPERTY_MAX_RUNS`, default #{@default_max_runs})."
  @spec max_runs(pos_integer() | nil) :: pos_integer()
  def max_runs(cap \\ nil) do
    configured =
      case Integer.parse(System.get_env("PROPERTY_MAX_RUNS", "")) do
        {n, ""} when n > 0 -> n
        _ -> @default_max_runs
      end

    if cap, do: min(configured, cap), else: configured
  end

  @doc "Prints the seed and run budget for `module`."
  @spec announce(module()) :: :ok
  def announce(module) do
    seed = ExUnit.configuration()[:seed]
    IO.puts("[property] #{inspect(module)} seed=#{seed} max_runs=#{max_runs()}")
  end
end
