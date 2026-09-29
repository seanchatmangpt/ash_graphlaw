# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.Bare do
  @moduledoc """
  UNSUPPORTED(generator-capability): a resource that adopts the extension but declares an
  empty `:graphlaw` section -- the case where `Admissions.runtime/1` must fall back to the
  `Dsl.Runtime` struct defaults.
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
  end

  actions do
    defaults [:read, create: []]
  end
end
