# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw do
  @moduledoc """
  Ash/BEAM membrane over GraphLaw's WASI ABI 1 (release v26.9.29).

  GraphLaw derives and validates; it never authorizes. This library transports requests
  to the pinned `graphlaw.wasm` engine and projects the outcome as typed values:

    * `{:ok, map}` / `{:ok, %AshGraphLaw.Admitted{}}` is an observation bound to the exact
      input that was sent. It grants no authority and does not execute any consequence.
    * `{:error, %AshGraphLaw.Refusal{}}` is a closed, typed refusal carrying a `:code`,
      a `:class`, and a Chatman `:broken_term`.

  RDF, SPARQL, SHACL, N3, Datalog, entailment, hooks, plan admission, leases and receipt
  verification stay inside the engine; nothing here reimplements them.

  ## Options

  Every function takes an `opts` keyword list:

    * `:server` - host or pool to call (default `AshGraphLaw.Pool`)
    * `:timeout` - per-call timeout in milliseconds
    * `:signed_lease`, `:trusted_keys`, `:max_skew_secs`, `:lease`, `:unverified_lease`,
      `:now_unix` - authority material copied into `law/3` requests

  Request maps use string keys, e.g. `%{"op" => "law"}`.
  """

  alias AshGraphLaw.{Admitted, Host, Pool, Refusal}

  @abi_version 1
  @graphlaw_release "26.9.29"
  @auth_keys [:signed_lease, :trusted_keys, :max_skew_secs, :lease, :unverified_lease, :now_unix]

  @typedoc "Data payload: a bare text string or an engine data spec map (`text`, `dialect`)."
  @type data :: String.t() | map()

  @typedoc "Options accepted by every public function."
  @type opts :: keyword()

  @doc "ABI version this build speaks."
  @spec abi_version() :: pos_integer()
  def abi_version, do: @abi_version

  @doc "Pinned GraphLaw release tag."
  @spec graphlaw_release() :: String.t()
  def graphlaw_release, do: @graphlaw_release

  @doc """
  Sends a raw request map to the engine.

  A response with `"ok": true` becomes `{:ok, response}`; `"ok": false` becomes
  `{:error, %AshGraphLaw.Refusal{}}` mapped from the engine error. Transport and host
  failures pass through as their own typed refusals.
  """
  @spec call(map(), opts()) :: {:ok, map()} | {:error, Refusal.t()}
  def call(request, opts \\ []) when is_map(request) and is_list(opts) do
    request
    |> dispatch(opts)
    |> classify()
  end

  @doc """
  The SHA-256 of the engine bytes behind the server named in `opts` (`:server`), or `nil`
  when no live host can report it. Evidence records this so an admission names the exact
  engine that produced it.
  """
  @spec engine_sha256(opts()) :: String.t() | nil
  def engine_sha256(opts \\ []) when is_list(opts) do
    info =
      case Keyword.get(opts, :server, Pool) do
        Pool -> Pool.info()
        server -> Host.info(server)
      end

    case info do
      {:ok, %{wasm_sha256: sha}} -> sha
      _ -> nil
    end
  end

  @doc "Asks the engine which operations and dialects it supports."
  @spec capabilities(opts()) :: {:ok, map()} | {:error, Refusal.t()}
  def capabilities(opts \\ []), do: call(%{"op" => "capabilities"}, opts)

  @doc "Detects the RDF dialect of `text`, optionally guided by `hint`."
  @spec sniff(String.t(), String.t() | nil, opts()) :: {:ok, map()} | {:error, Refusal.t()}
  def sniff(text, hint \\ nil, opts \\ []) when is_binary(text) do
    request = %{"op" => "sniff", "text" => text}
    request = if hint, do: Map.put(request, "hint", hint), else: request
    call(request, opts)
  end

  @doc """
  Runs the `law` operation: an ordered list of admission `steps` over `data`.

  Success is wrapped in `AshGraphLaw.Admitted`. Authority options (`:signed_lease`,
  `:trusted_keys`, `:max_skew_secs`, `:lease`, `:unverified_lease`, `:now_unix`) are
  copied into the request when present.
  """
  @spec law(data(), [map()], opts()) :: {:ok, Admitted.t()} | {:error, Refusal.t()}
  def law(data, steps, opts \\ []) when is_list(steps) and is_list(opts) do
    request =
      %{"op" => "law", "data" => data_spec(data), "steps" => steps}
      |> put_auth(opts)

    case call(request, opts) do
      {:ok, response} -> {:ok, Admitted.from_map(response)}
      {:error, %Refusal{} = refusal} -> {:error, refusal}
    end
  end

  @doc "Runs a hook `pack` over `data` (both accept text or an engine data spec)."
  @spec hooks(data(), data(), opts()) :: {:ok, map()} | {:error, Refusal.t()}
  def hooks(data, pack, opts \\ []) when is_list(opts) do
    call(%{"op" => "hooks", "data" => data_spec(data), "pack" => data_spec(pack)}, opts)
  end

  @doc """
  Typed `parse` capability: Parse text with the owning engine; counts quads or validates syntax.

  `args` is a keyword list or map of the registry request fields; `opts` are the same
  options `call/2` takes. See `AshGraphLaw.Capability.Parse`.
  """
  @spec parse(keyword() | map(), opts()) :: {:ok, term()} | {:error, Refusal.t()}
  defdelegate parse(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc "Like `parse/2` but raises `AshGraphLaw.Error.Refused` on refusal."
  @spec parse!(keyword() | map(), opts()) :: term()
  defdelegate parse!(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc """
  Typed `convert` capability: Serialize parsed RDF text into another RDF dialect.

  `args` is a keyword list or map of the registry request fields; `opts` are the same
  options `call/2` takes. See `AshGraphLaw.Capability.Convert`.
  """
  @spec convert(keyword() | map(), opts()) :: {:ok, term()} | {:error, Refusal.t()}
  defdelegate convert(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc "Like `convert/2` but raises `AshGraphLaw.Error.Refused` on refusal."
  @spec convert!(keyword() | map(), opts()) :: term()
  defdelegate convert!(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc """
  Typed `canonical` capability: Canonicalize a dataset to N-Quads and return its content-addressed id.

  `args` is a keyword list or map of the registry request fields; `opts` are the same
  options `call/2` takes. See `AshGraphLaw.Capability.Canonical`.
  """
  @spec canonical(keyword() | map(), opts()) :: {:ok, term()} | {:error, Refusal.t()}
  defdelegate canonical(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc "Like `canonical/2` but raises `AshGraphLaw.Error.Refused` on refusal."
  @spec canonical!(keyword() | map(), opts()) :: term()
  defdelegate canonical!(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc """
  Typed `sparql` capability: Evaluate a SPARQL query over a dataset.

  `args` is a keyword list or map of the registry request fields; `opts` are the same
  options `call/2` takes. See `AshGraphLaw.Capability.Sparql`.
  """
  @spec sparql(keyword() | map(), opts()) :: {:ok, term()} | {:error, Refusal.t()}
  defdelegate sparql(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc "Like `sparql/2` but raises `AshGraphLaw.Error.Refused` on refusal."
  @spec sparql!(keyword() | map(), opts()) :: term()
  defdelegate sparql!(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc """
  Typed `shacl` capability: Validate a dataset against SHACL shapes.

  `args` is a keyword list or map of the registry request fields; `opts` are the same
  options `call/2` takes. See `AshGraphLaw.Capability.Shacl`.
  """
  @spec shacl(keyword() | map(), opts()) :: {:ok, term()} | {:error, Refusal.t()}
  defdelegate shacl(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc "Like `shacl/2` but raises `AshGraphLaw.Error.Refused` on refusal."
  @spec shacl!(keyword() | map(), opts()) :: term()
  defdelegate shacl!(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc """
  Typed `shex` capability: Validate a dataset against a ShEx schema and shape map.

  `args` is a keyword list or map of the registry request fields; `opts` are the same
  options `call/2` takes. See `AshGraphLaw.Capability.Shex`.
  """
  @spec shex(keyword() | map(), opts()) :: {:ok, term()} | {:error, Refusal.t()}
  defdelegate shex(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc "Like `shex/2` but raises `AshGraphLaw.Error.Refused` on refusal."
  @spec shex!(keyword() | map(), opts()) :: term()
  defdelegate shex!(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc """
  Typed `n3` capability: Run bounded Notation3 forward reasoning over a document.

  `args` is a keyword list or map of the registry request fields; `opts` are the same
  options `call/2` takes. See `AshGraphLaw.Capability.N3`.
  """
  @spec n3(keyword() | map(), opts()) :: {:ok, term()} | {:error, Refusal.t()}
  defdelegate n3(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc "Like `n3/2` but raises `AshGraphLaw.Error.Refused` on refusal."
  @spec n3!(keyword() | map(), opts()) :: term()
  defdelegate n3!(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc """
  Typed `entail` capability: Materialize an entailment regime over a dataset.

  `args` is a keyword list or map of the registry request fields; `opts` are the same
  options `call/2` takes. See `AshGraphLaw.Capability.Entail`.
  """
  @spec entail(keyword() | map(), opts()) :: {:ok, term()} | {:error, Refusal.t()}
  defdelegate entail(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc "Like `entail/2` but raises `AshGraphLaw.Error.Refused` on refusal."
  @spec entail!(keyword() | map(), opts()) :: term()
  defdelegate entail!(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc """
  Typed `datalog` capability: Evaluate Datalog rules over triple facts to a fixpoint.

  `args` is a keyword list or map of the registry request fields; `opts` are the same
  options `call/2` takes. See `AshGraphLaw.Capability.Datalog`.
  """
  @spec datalog(keyword() | map(), opts()) :: {:ok, term()} | {:error, Refusal.t()}
  defdelegate datalog(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc "Like `datalog/2` but raises `AshGraphLaw.Error.Refused` on refusal."
  @spec datalog!(keyword() | map(), opts()) :: term()
  defdelegate datalog!(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc """
  Typed `policy` capability: Admit a FOND policy as strong-cyclic against a planning problem.

  `args` is a keyword list or map of the registry request fields; `opts` are the same
  options `call/2` takes. See `AshGraphLaw.Capability.Policy`.
  """
  @spec policy(keyword() | map(), opts()) :: {:ok, term()} | {:error, Refusal.t()}
  defdelegate policy(args, opts \\ []), to: AshGraphLaw.Capability.API

  @doc "Like `policy/2` but raises `AshGraphLaw.Error.Refused` on refusal."
  @spec policy!(keyword() | map(), opts()) :: term()
  defdelegate policy!(args, opts \\ []), to: AshGraphLaw.Capability.API

  defp dispatch(request, opts) do
    case Keyword.get(opts, :server, Pool) do
      Pool -> Pool.request(request, opts)
      server -> Host.request(server, request, opts)
    end
  end

  defp classify({:ok, %{"ok" => true} = response}), do: {:ok, response}

  defp classify({:ok, %{"ok" => false, "error" => error} = response}) when is_map(error) do
    {:error, Refusal.from_engine(error, details_of(response))}
  end

  defp classify({:ok, other}) do
    {:error, Refusal.new(:malformed_response, "GraphLaw response lacks a boolean ok", %{response: other})}
  end

  defp classify({:error, %Refusal{} = refusal}), do: {:error, refusal}

  defp details_of(%{"details" => %{} = details}), do: details
  defp details_of(_response), do: %{}

  defp data_spec(%{} = spec), do: spec
  defp data_spec(text) when is_binary(text), do: %{"text" => text}

  defp put_auth(request, opts) do
    Enum.reduce(@auth_keys, request, fn key, acc ->
      case Keyword.fetch(opts, key) do
        {:ok, value} -> Map.put(acc, Atom.to_string(key), value)
        :error -> acc
      end
    end)
  end
end
