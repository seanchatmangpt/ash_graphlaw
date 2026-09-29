# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.Ticket do
  @moduledoc """
  UNSUPPORTED(generator-capability): the reference test resource.

    * `:open` (create) is gated by the `:ticket_shape` SHACL admission;
    * `:close` (update) is gated by the `:ticket_close` plan admission (ceiling `:select`);
    * `:seed` (create) is NOT gated -- it exists only so tests can build real stored records
      (for update changesets and projections) without invoking the engine.
  """

  use Ash.Resource,
    domain: AshGraphLaw.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :state, :atom, default: :open, public?: true, constraints: [one_of: [:open, :closed]]
  end

  actions do
    defaults [:read]

    create :open do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :ticket_shape}
    end

    create :seed do
      accept [:title, :state]
    end

    update :close do
      require_atomic? false
      change set_attribute(:state, :closed)
      change {AshGraphLaw.Change.Admit, admission: :ticket_close}
    end
  end

  graphlaw do
    runtime do
      timeout_ms(5000)
      # Only the :trusted test signer may issue leases for this resource; runtime trust anchors
      # are the sole source of trust (caller context can never supply them).
      trusted_keys([AshGraphLaw.Test.Lease.public_key_hex(:trusted)])
    end

    admission :ticket_shape do
      step(:shacl)
      law(AshGraphLaw.Test.ShapeLaw)
    end

    admission :ticket_close do
      step(:plan)
      ceiling(:select)
      law(AshGraphLaw.Test.PlanLaw)
    end
  end
end
