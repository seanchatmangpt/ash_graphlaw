# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Receipt do
  @moduledoc """
  Lossless typed projection of one GraphLaw receipt.

  A receipt is an observation emitted by the engine for one law step, bound to
  the parent and child graph state ids. It records what happened; it grants no
  authority. The untouched engine map is kept in `:raw`.
  """

  @enforce_keys [:step, :parent, :child]
  defstruct [:step, :parent, :child, :added, :authority, :revision, :lease_id, :plan_sha256, :index, :raw]

  @type t :: %__MODULE__{
          step: String.t() | nil,
          parent: term(),
          child: term(),
          added: non_neg_integer() | nil,
          authority: String.t() | nil,
          revision: term(),
          lease_id: String.t() | nil,
          plan_sha256: String.t() | nil,
          index: non_neg_integer() | nil,
          raw: map()
        }

  @doc "Builds a receipt from an engine response map (string keys). Unknown keys survive in `:raw`."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      step: map["step"],
      parent: map["parent"],
      child: map["child"],
      added: map["added"],
      authority: map["authority"],
      revision: map["revision"],
      lease_id: map["lease_id"],
      plan_sha256: map["plan_sha256"],
      index: map["index"],
      raw: map
    }
  end
end
