# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Formatter do
  @moduledoc """
  UNSUPPORTED(generator-capability): `Spark.Formatter` plugin helper for the AshGraphLaw DSL (`graphlaw` section).
  """

  @doc "Returns the list of Spark extensions exported by AshGraphLaw."
  @spec extensions() :: [module()]
  def extensions, do: [AshGraphLaw.Resource]

  @doc "Mix.Tasks.Format plugin callback."
  @spec features(keyword()) :: keyword()
  def features(_opts), do: [extensions: [".ex", ".exs"]]

  @doc "Mix.Tasks.Format plugin format callback; returns contents unchanged when `Spark.Formatter` is unavailable."
  @spec format(String.t(), keyword()) :: String.t()
  def format(contents, opts) do
    if Code.ensure_loaded?(Spark.Formatter) do
      opts_with_spark =
        Keyword.update(opts, :spark, [extensions: [AshGraphLaw.Resource]], fn spark ->
          Keyword.update(spark, :extensions, [AshGraphLaw.Resource], &[AshGraphLaw.Resource | &1])
        end)

      Spark.Formatter.format(contents, opts_with_spark)
    else
      contents
    end
  end
end
