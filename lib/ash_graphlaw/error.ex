# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Error do
  @moduledoc """
  Namespace and recovery helpers for AshGraphLaw errors.

  UNSUPPORTED(generator-capability): hand-written; no pack template emits a Splode error namespace.

  A refused admission is carried through Ash as `AshGraphLaw.Error.Refused`
  (Splode class `:invalid`). Ash aggregates such errors into an
  `Ash.Error.Invalid` container, so callers recover the typed
  `AshGraphLaw.Refusal` (with its `code`, `class` and `broken_term`) using
  `refusals/1`:

      case Ash.create(changeset) do
        {:error, error_class} ->
          [%AshGraphLaw.Refusal{code: code} | _] = AshGraphLaw.Error.refusals(error_class)

        {:ok, _} ->
          :ok
      end

  A refusal is an observation about one exact input. It grants no authority.
  """

  alias AshGraphLaw.Error.Refused
  alias AshGraphLaw.Refusal

  @doc """
  Returns every `AshGraphLaw.Refusal` reachable inside `error`.

  Accepts a bare `AshGraphLaw.Error.Refused`, a bare `AshGraphLaw.Refusal`, an
  Ash/Splode error class (whose `errors` list is walked recursively), or a
  list of any of these. Anything else yields `[]`.
  """
  @spec refusals(term()) :: [Refusal.t()]
  def refusals(error), do: error |> collect([]) |> Enum.reverse()

  @doc "Returns the codes of every refusal reachable inside `error`, in order."
  @spec codes(term()) :: [atom()]
  def codes(error), do: error |> refusals() |> Enum.map(& &1.code)

  @doc "Returns true when `error` contains at least one `AshGraphLaw.Refusal`."
  @spec refused?(term()) :: boolean()
  def refused?(error), do: refusals(error) != []

  defp collect(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect/2)
  defp collect(%Refused{refusal: %Refusal{} = refusal}, acc), do: [refusal | acc]
  defp collect(%Refusal{} = refusal, acc), do: [refusal | acc]
  defp collect(%{errors: errors}, acc) when is_list(errors), do: collect(errors, acc)
  defp collect(_other, acc), do: acc
end
