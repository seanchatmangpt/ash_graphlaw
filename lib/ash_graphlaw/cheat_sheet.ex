# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.CheatSheet do
  @moduledoc """
  UNSUPPORTED(generator-capability): generates the DSL cheat sheet for `AshGraphLaw.Resource`.
  """

  @doc "Returns the Markdown cheat sheet for the `AshGraphLaw.Resource` extension."
  @spec generate() :: String.t()
  def generate, do: Spark.CheatSheet.cheat_sheet(AshGraphLaw.Resource)
end
