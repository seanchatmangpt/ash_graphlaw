# Copyright 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshGraphlaw.Verify do
  # UNSUPPORTED(generator-capability): hand-written; no pack emits a wasm verification task.
  @shortdoc "Admits the vendored GraphLaw wasm and checks its ABI version against MANIFEST.json"

  @moduledoc """
  Verifies the vendored GraphLaw engine.

  Steps, all real:

    1. read `priv/graphlaw/MANIFEST.json`;
    2. admit the vendored bytes through `AshGraphLaw.EngineLoad.admit/2` (import surface,
       required exports, digest pin);
    3. start a real `AshGraphLaw.Host` and send the `capabilities` op;
    4. require the reported `abi_version` to equal the manifest `abi_version`.

  Any refusal prints its typed code and the task exits non-zero. A passing run is an observation
  about these bytes; it grants nothing.

  ## Usage

      mix ash_graphlaw.verify

  ## Options

  None. The task takes no arguments; any are ignored.

  ## Exit codes

    * `0` - the engine was admitted and reports the manifest `abi_version`.
    * `1` - refusal, raised as `Mix.Error` with a typed code in brackets:
      `[wasm_not_vendored]`, `[wasm_invalid]` (manifest), `[abi_version_mismatch]`,
      `[malformed_response]`, or any `AshGraphLaw.Refusal` code returned by
      `AshGraphLaw.EngineLoad.admit/2` or `AshGraphLaw.Host`.

  ## Examples

      mix ash_graphlaw.vendor && mix ash_graphlaw.verify
  """

  use Mix.Task

  alias AshGraphLaw.EngineLoad
  alias AshGraphLaw.Host
  alias AshGraphLaw.Refusal

  @doc """
  Runs the task. Returns `:ok`; raises `Mix.Error` with a `[code]` prefix on refusal.
  """
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(_argv) do
    Mix.Task.run("app.start")
    dir = priv_dir()
    manifest = read_manifest!(Path.join(dir, "MANIFEST.json"))
    artifact = manifest["artifact"]
    path = Path.join(dir, artifact["file"])
    expected = manifest["abi_version"]

    bytes =
      case File.read(path) do
        {:ok, bytes} -> bytes
        {:error, reason} -> fail("wasm_not_vendored", "#{path}: #{inspect(reason)}; run mix ash_graphlaw.vendor")
      end

    admitted =
      case EngineLoad.admit(bytes, expected_sha256: artifact["sha256"]) do
        {:ok, admitted} -> admitted
        {:error, %Refusal{} = refusal} -> fail(refusal.code, refusal.message)
      end

    Mix.shell().info("engine admitted: sha256=#{admitted.wasm_sha256}")
    check_abi!(bytes, artifact["sha256"], expected)
    Mix.shell().info("GraphLaw engine VERIFIED (abi_version #{expected}).")
    :ok
  end

  defp check_abi!(bytes, sha, expected) do
    {:ok, host} = Host.start_link(bytes: bytes, expected_sha256: sha)

    try do
      case Host.request(host, %{"op" => "capabilities"}) do
        {:ok, %{"ok" => true, "abi" => ^expected}} ->
          :ok

        {:ok, %{"ok" => true, "abi" => other}} ->
          fail("abi_version_mismatch", "engine reports #{inspect(other)}, manifest pins #{expected}")

        {:ok, other} ->
          fail("malformed_response", "unexpected capabilities response: #{inspect(other)}")

        {:error, %Refusal{} = refusal} ->
          fail(refusal.code, refusal.message)
      end
    after
      GenServer.stop(host)
    end
  end

  defp priv_dir do
    if Mix.Project.config()[:app] == :ash_graphlaw do
      Path.join(File.cwd!(), "priv/graphlaw")
    else
      Application.app_dir(:ash_graphlaw, "priv/graphlaw")
    end
  end

  defp read_manifest!(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, %{"abi_version" => abi, "artifact" => %{"file" => f, "sha256" => s}} = m}
         when is_integer(abi) and is_binary(f) and is_binary(s) <- Jason.decode(raw) do
      m
    else
      _ -> fail("wasm_invalid", "manifest #{path} is missing or malformed")
    end
  end

  @spec fail(String.t(), String.t()) :: no_return()
  defp fail(code, message), do: Mix.raise("[#{code}] #{message}")
end
