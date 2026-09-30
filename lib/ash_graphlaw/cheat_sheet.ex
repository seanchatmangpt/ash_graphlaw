# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.CheatSheet do
  @moduledoc """
  UNSUPPORTED(generator-capability): generates the DSL cheat sheet for `AshGraphLaw.Resource`.

  `documentation/dsls/**` is regenerated from this extension by `mix spark.cheat_sheets`; this
  module exposes the same Markdown at run time.
  """

  @doc """
  Returns the Markdown cheat sheet for the `AshGraphLaw.Resource` extension.

  ## Examples

      iex> AshGraphLaw.CheatSheet.generate() |> is_binary()
      true
  """
  @spec generate() :: String.t()
  def generate, do: Spark.CheatSheet.cheat_sheet(AshGraphLaw.Resource)
end
