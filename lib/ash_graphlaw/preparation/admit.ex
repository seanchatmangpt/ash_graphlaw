# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Preparation.Admit do
  @moduledoc """
  Ash preparation that runs a declared GraphLaw admission at prepare time.

  UNSUPPORTED(generator-capability): hand-written; Ash preparations are outside every listed pack.

  ## Usage

      read :open_tickets do
        prepare {AshGraphLaw.Preparation.Admit, admission: :ticket_scope}
      end

  Supports `Ash.Query` and `Ash.ActionInput` (generic actions). The preparation is a thin adapter
  over `AshGraphLaw.Validation.Admissible.admit/2`, which does the work.

  ## Options

  Identical to `AshGraphLaw.Validation.Admissible` (see `t:opts/0`); `init/1` delegates to it.

  | Option        | Type            | Default                                | Meaning |
  |---------------|-----------------|----------------------------------------|---------|
  | `:admission`  | atom (required) | none                                   | Declared admission name. |
  | `:projection` | module or `nil` | admission's `projection`, then `AshGraphLaw.Projection.Default` | Projection override. |
  | `:server`     | atom            | `AshGraphLaw.Pool`                     | Pool/host server name. |
  | `:timeout`    | positive integer (ms) | runtime `timeout_ms`             | Per-call timeout. |
  | `:lease_key`  | atom            | `:graphlaw_lease`                      | Context key holding the lease. |

  There is no `:phase` option: the admission runs when Ash prepares the subject.

  ## Lease context key

  The lease is read from the subject's `context[lease_key]` (default `:graphlaw_lease`), for
  example `Ash.Query.set_context(query, %{graphlaw_lease: lease})`. Only a `:signed_lease` entry
  can raise the ceiling above `:observe`; the engine verifies it against `runtime.trusted_keys`.
  See `AshGraphLaw.Authority`.

  ## Refusals

  On refusal the subject receives an `AshGraphLaw.Error.Refused` error carrying the typed
  `AshGraphLaw.Refusal` (`:unknown_admission`, `:ceiling_unmet`, `:projection_failed`,
  `:missing_law_module`, `:law_module_failed` or an engine code). On success the subject is
  returned unchanged; no evidence is recorded (use `AshGraphLaw.Change.Admit` for that).

  ## Atomic behavior

  Preparations have no atomic callback: they run when the query or action input is prepared, once
  per subject, and never inside a data-layer expression. The admission needs an engine call, so
  it is not expressible atomically either.

  ## Telemetry

  `[:ash_graphlaw, :admission, :stop]`, emitted by `AshGraphLaw.Validation.Admissible.admit/2`
  with measurements `%{duration: native_time}` and metadata
  `%{admission, outcome, code, standing}`.

  GraphLaw derives and validates; it never authorizes.
  """

  use Ash.Resource.Preparation

  alias AshGraphLaw.Error.Refused
  alias AshGraphLaw.Validation.Admissible

  @typedoc "Options accepted by `init/1`; same shape as `t:AshGraphLaw.Validation.Admissible.opts/0`."
  @type opts :: Admissible.opts()

  @doc """
  Validates and normalizes the preparation options by delegating to
  `AshGraphLaw.Validation.Admissible.init/1`.
  """
  @impl Ash.Resource.Preparation
  @spec init(keyword()) :: {:ok, opts()} | {:error, String.t()}
  def init(opts), do: Admissible.init(opts)

  @doc "Returns the subjects this preparation supports: `Ash.Query` and `Ash.ActionInput`."
  @impl Ash.Resource.Preparation
  @spec supports(opts()) :: [module()]
  def supports(_opts), do: [Ash.Query, Ash.ActionInput]

  @doc """
  Runs the admission against `subject`.

  Returns `subject` unchanged when admitted, otherwise the subject with an
  `AshGraphLaw.Error.Refused` error added.
  """
  @impl Ash.Resource.Preparation
  @spec prepare(Ash.Query.t() | Ash.ActionInput.t(), opts(), Ash.Resource.Preparation.Context.t()) ::
          Ash.Query.t() | Ash.ActionInput.t()
  def prepare(subject, opts, _context) do
    case Admissible.admit(subject, opts) do
      :ok -> subject
      {:error, refusal} -> add_error(subject, Refused.exception(refusal: refusal))
    end
  end

  defp add_error(%Ash.Query{} = query, error), do: Ash.Query.add_error(query, error)
  defp add_error(%Ash.ActionInput{} = input, error), do: Ash.ActionInput.add_error(input, error)
end
