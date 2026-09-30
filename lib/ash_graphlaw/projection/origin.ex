# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): no pack template emits projection provenance.
defmodule AshGraphLaw.Projection.Origin do
  @moduledoc """
  Provenance of the RDF fed to the engine: which resource, action, record and projection
  produced which exact projected text.

  An origin is data, not authority. It names the subject a projection observed and binds it to
  the SHA-256 of the exact projected text (`:data_sha256`), so an admission can later be traced
  back to what it observed. `to_map/1` is string-keyed and JSON-safe; `digest/1` is the
  canonical-JSON SHA-256 (`"sha256:<hex>"`) of that map.
  """

  alias AshGraphLaw.Capability.CanonicalJSON

  @typedoc """
  Field meanings:

    * `:resource` - resource module.
    * `:action` - action name (atom) or `nil` when the subject carried no action.
    * `:primary_key` - primary key map of the record (`%{}` when none).
    * `:projection` - projection module that produced the text.
    * `:data_sha256` - lowercase hex SHA-256 of the exact projected text.
    * `:dialect` / `:base` - optional RDF dialect and base IRI of the projected data.
  """
  @type t :: %__MODULE__{
          resource: module(),
          action: atom() | nil,
          primary_key: map(),
          projection: module(),
          data_sha256: String.t(),
          dialect: String.t() | nil,
          base: String.t() | nil
        }

  @enforce_keys [:resource, :projection, :data_sha256]
  defstruct [:resource, :action, :projection, :data_sha256, :dialect, :base, primary_key: %{}]

  @keys [:resource, :action, :primary_key, :projection, :data_sha256, :dialect, :base]

  @doc """
  Builds an origin from a keyword list or map.

  `:resource`, `:projection` and `:data_sha256` are required. Unknown keys raise
  `ArgumentError`, so a field that would be silently dropped is caught.
  """
  @spec new(keyword() | map()) :: t()
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)

    case Map.keys(attrs) -- @keys do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown AshGraphLaw.Projection.Origin keys: #{inspect(unknown)}"
    end

    for key <- [:resource, :projection, :data_sha256], not Map.has_key?(attrs, key) do
      raise ArgumentError, "AshGraphLaw.Projection.Origin requires #{inspect(key)}"
    end

    struct!(__MODULE__, attrs)
  end

  @doc """
  String-keyed, JSON-safe map of the origin. Modules and atoms become strings; `nil` is kept.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = origin) do
    %{
      "resource" => inspect(origin.resource),
      "action" => origin.action && Atom.to_string(origin.action),
      "primary_key" => pk_map(origin.primary_key),
      "projection" => inspect(origin.projection),
      "data_sha256" => origin.data_sha256,
      "dialect" => origin.dialect,
      "base" => origin.base
    }
  end

  @doc "Canonical-JSON SHA-256 of `to_map/1` (`\"sha256:<hex>\"`)."
  @spec digest(t()) :: String.t()
  def digest(%__MODULE__{} = origin), do: origin |> to_map() |> CanonicalJSON.sha256()

  defp pk_map(pk) when is_map(pk), do: Map.new(pk, fn {k, v} -> {to_string(k), json_value(v)} end)
  defp pk_map(_other), do: %{}

  defp json_value(nil), do: nil
  defp json_value(v) when is_binary(v) or is_integer(v) or is_boolean(v), do: v
  defp json_value(v) when is_atom(v), do: Atom.to_string(v)
  defp json_value(v), do: inspect(v, limit: :infinity, printable_limit: :infinity)
end
