# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits Ash calculations, validations or changes

defmodule AshGraphLaw.Change.Canonicalize do
  @moduledoc """
  Ash change that stores the canonical id of the record's projected graph in an attribute.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits an Ash change.

  Exposes the typed `canonical` capability. In `before_action` the changeset is projected to RDF,
  the engine canonicalizes it and the resulting `"sha256:..."` id is written to `:attribute`. The
  target attribute is projected as absent, so the id never depends on its own previous value.

  ## Usage

      create :create do
        accept [:title]
        change {AshGraphLaw.Change.Canonicalize, attribute: :graph_id}
      end

  Applies to `:create` and `:update` actions; other action types are returned untouched.

  ## Options

  | Option        | Type                  | Default                          | Meaning |
  |---------------|-----------------------|----------------------------------|---------|
  | `:attribute`  | atom                  | required                         | Attribute receiving the id. |
  | `:projection` | module                | `AshGraphLaw.Projection.Default` | Projection override. |
  | `:server`     | atom or pid           | `AshGraphLaw.Pool`               | Engine server. |
  | `:timeout`    | positive integer (ms) | the resource's `timeout_ms`      | Per-call timeout. |
  | `:lease`      | term                  | none                             | Lease checked against the declared capability ceiling. |
  | `:lease_key`  | atom                  | `:graphlaw_lease`                | Changeset context key holding the lease. |

  ## Errors

  A refusal (`:capability_not_declared`, engine refusal, unusable response) adds an
  `AshGraphLaw.Error.Refused` to the changeset and leaves the attribute unchanged; nothing is
  raised and nothing is swallowed.

  ## Atomic behavior

  `atomic/3` returns `{:not_atomic, "GraphLaw canonicalization requires a WASM call"}`; the id needs
  an engine round trip per record, so `Ash.bulk_update/4` with `strategy: :atomic` is refused by Ash
  and `strategy: :stream` runs the change per record.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshGraphLaw.Lifecycle

  @allowed [:attribute, :projection, :server, :timeout, :lease, :lease_key]
  @action_types [:create, :update]

  @doc "Validates the change options at compile time (`:attribute` is required)."
  @impl true
  @spec init(term()) :: {:ok, keyword()} | {:error, String.t()}
  def init(opts), do: Lifecycle.check_opts(opts, @allowed, [:attribute])

  @doc "Registers the canonicalization in `before_action` for create and update actions."
  @impl true
  @spec change(Changeset.t(), keyword(), Ash.Resource.Change.context()) :: Changeset.t()
  def change(%Changeset{action_type: type} = changeset, opts, _context) when type in @action_types do
    Changeset.before_action(changeset, &run(&1, opts))
  end

  def change(changeset, _opts, _context), do: changeset

  @doc "Declares the change non-atomic."
  @impl true
  @spec atomic(Changeset.t(), keyword(), Ash.Resource.Change.context()) :: {:not_atomic, String.t()}
  def atomic(_changeset, _opts, _context), do: {:not_atomic, "GraphLaw canonicalization requires a WASM call"}

  @doc """
  Hook body registered by `change/3`: canonicalizes `changeset` and writes the id.

  Public only so the hook can be captured. On refusal an `AshGraphLaw.Error.Refused` is added.
  """
  @spec run(Changeset.t(), keyword()) :: Changeset.t()
  def run(%Changeset{} = changeset, opts) do
    attribute = Keyword.fetch!(opts, :attribute)
    opts = Keyword.put(opts, :lease, Lifecycle.lease(changeset, opts))
    observed = Changeset.force_change_attribute(changeset, attribute, nil)

    case Lifecycle.run_on(observed, "canonical", [], opts) do
      {:ok, result} ->
        case Map.get(result, :id) do
          id when is_binary(id) -> Changeset.force_change_attribute(changeset, attribute, id)
          other -> add_refusal(changeset, Lifecycle.undecodable("canonical", other))
        end

      {:error, refusal} ->
        add_refusal(changeset, refusal)
    end
  end

  defp add_refusal(changeset, refusal), do: Changeset.add_error(changeset, Lifecycle.to_error(refusal))
end
