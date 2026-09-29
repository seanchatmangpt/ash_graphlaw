# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.Domain do
  @moduledoc """
  UNSUPPORTED(generator-capability): Ash domain for the ash_graphlaw test resources.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshGraphLaw.Test.Ticket
    resource AshGraphLaw.Test.Bare
    resource AshGraphLaw.Test.Account
  end
end
