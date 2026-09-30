# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.ParityFixtures do
  @moduledoc """
  UNSUPPORTED(generator-capability): test-only scripted engines for the parity court.

  Each engine is a REAL wasm module (`AshGraphLaw.Test.WasmFixtures.scripted_engine/1`) run by the
  real Wasmtime host; its `gl_call` returns a fixed `capabilities` JSON body. The body is built from
  the generated `AshGraphLaw.Capability.Registry`, so the `:exact` variant is the positive control
  (it agrees with the registry on the surface) and every other variant injects exactly one drift:

    * `:exact` - the registry surface, both digests and the schema id;
    * `:dropped_op` - the last op is missing from `ops`;
    * `:reordered` - the first two ops are swapped;
    * `:extra_dialect` - an rdf dialect the registry does not know;
    * `:bad_registry_sha` - a well-formed but wrong `registry_sha256`;
    * `:legacy` - an engine older than v26.9.29: no registry fields at all.
  """

  alias AshGraphLaw.Test.WasmFixtures

  @registry AshGraphLaw.Capability.Registry

  @type variant :: :exact | :dropped_op | :reordered | :extra_dialect | :bad_registry_sha | :legacy

  @doc "Every drift variant (everything except the positive control)."
  @spec drift_variants() :: [variant()]
  def drift_variants, do: [:dropped_op, :reordered, :extra_dialect, :bad_registry_sha]

  @doc "The `capabilities` response body of `variant`, as a map."
  @spec capabilities(variant()) :: map()
  def capabilities(variant) do
    names = apply(@registry, :names, [])
    rdf = apply(@registry, :rdf_dialects, [])
    other = apply(@registry, :other_dialects, [])

    base = %{
      "ok" => true,
      "abi" => 1,
      "abi_version" => 1,
      "crate" => "graphlaw",
      "authorities" => [],
      "ops" => names,
      "rdf_dialects" => rdf,
      "other_dialects" => other,
      "registry_schema" => apply(@registry, :schema, []),
      "registry_sha256" => apply(@registry, :digest, []),
      "surface_sha256" => apply(@registry, :surface_digest, [])
    }

    apply_variant(variant, base)
  end

  @doc "A wrong but well-formed digest, distinct from the registry's."
  @spec wrong_digest() :: String.t()
  def wrong_digest, do: "sha256:" <> String.duplicate("0", 64)

  @doc "The wasm bytes of the scripted engine for `variant`."
  @spec engine(variant()) :: binary()
  def engine(variant), do: WasmFixtures.scripted_engine(call: {:json, Jason.encode!(capabilities(variant))})

  @doc "Writes the scripted engine for `variant` under `dir` and returns its path."
  @spec write_engine!(variant(), Path.t()) :: Path.t()
  def write_engine!(variant, dir) do
    File.mkdir_p!(dir)
    path = Path.join(dir, "scripted_#{variant}.wasm")
    File.write!(path, engine(variant))
    path
  end

  @doc "A fresh scratch directory removed at test exit."
  @spec scratch_dir!(String.t()) :: Path.t()
  def scratch_dir!(label) do
    dir = Path.join(System.tmp_dir!(), "agl-parity-#{label}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp apply_variant(:exact, base), do: base
  defp apply_variant(:dropped_op, base), do: Map.update!(base, "ops", &Enum.drop(&1, -1))

  defp apply_variant(:reordered, %{"ops" => [first, second | rest]} = base),
    do: %{base | "ops" => [second, first | rest]}

  defp apply_variant(:extra_dialect, base), do: Map.update!(base, "rdf_dialects", &(&1 ++ ["notarealdialect"]))
  defp apply_variant(:bad_registry_sha, base), do: %{base | "registry_sha256" => wrong_digest()}

  defp apply_variant(:legacy, base),
    do: Map.drop(base, ["registry_schema", "registry_sha256", "surface_sha256"])
end
