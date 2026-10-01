# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Receipt do
  @moduledoc """
  Lossless typed projection of one GraphLaw receipt.

  A receipt is an observation emitted by the engine for one law step, bound to
  the parent and child graph state ids. It records what happened; it grants no
  authority. The untouched engine map is kept in `:raw`.

  ## Fields

    * `:step` - name of the law step that produced the receipt
    * `:parent` / `:child` - graph state ids before and after the step
    * `:added` - count of triples the step added
    * `:authority` - authority label the engine recorded (an observation, not a grant)
    * `:revision` - engine revision marker, kept as received
    * `:lease_id` - id of the lease under which the step ran, if any
    * `:plan_sha256` - digest of the plan the step executed, if any
    * `:index` - position of the receipt within its response
    * `:raw` - the untouched engine map, so nothing is lost by projection

  ## Examples

      iex> receipt = AshGraphLaw.Receipt.from_map(%{"step" => "shacl", "parent" => "a", "child" => "b", "extra" => 1})
      iex> {receipt.step, receipt.parent, receipt.child, receipt.raw["extra"]}
      {"shacl", "a", "b", 1}

      iex> AshGraphLaw.Receipt.from_map(%{}).added
      nil
  """

  @enforce_keys [:step, :parent, :child]
  defstruct [:step, :parent, :child, :added, :authority, :revision, :lease_id, :plan_sha256, :index, :raw]

  @typedoc "Typed projection of one engine receipt; `:raw` keeps the untouched map."
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

  @doc """
  Builds a receipt from an engine response map (string keys). Unknown keys survive in `:raw`.

  Missing fields become `nil`; the function never raises for a map.
  """
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
