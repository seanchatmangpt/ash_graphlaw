# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Admitted do
  @moduledoc """
  A successful GraphLaw `law` transition.

  Carries the state ids, the per-step receipts and the resulting N-Quads. It is
  an observation of admission on one exact input; it does not execute any
  consequence and standing is never stored here (see `AshGraphLaw.Standing`).
  """

  alias AshGraphLaw.Receipt

  @enforce_keys [:states, :receipts, :nquads]
  defstruct [:states, :receipts, :nquads, :raw]

  @type t :: %__MODULE__{
          states: list(),
          receipts: [Receipt.t()],
          nquads: String.t(),
          raw: map()
        }

  @doc "Builds an admitted transition from an engine response map. Missing fields default to `[]`, `[]`, `\"\"`."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      states: map["states"] || [],
      receipts: Enum.map(map["receipts"] || [], &Receipt.from_map/1),
      nquads: map["nquads"] || "",
      raw: map
    }
  end
end
