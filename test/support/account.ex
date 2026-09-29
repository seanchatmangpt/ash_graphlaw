# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.Account do
  @moduledoc """
  UNSUPPORTED(generator-capability): a plain Ash resource (no GraphLaw extension) carrying a
  `sensitive?: true` attribute and action arguments (`:api_token` sensitive, `:note` not), used to
  prove the default projection never emits secrets, whether they arrive as attributes or arguments.
  """

  use Ash.Resource,
    domain: AshGraphLaw.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :password, :string, public?: true, sensitive?: true
  end

  actions do
    defaults [:read]

    create :register do
      accept [:name, :password]
    end

    create :register_with_arguments do
      accept [:name]
      argument :api_token, :string, sensitive?: true
      argument :note, :string
    end
  end
end
