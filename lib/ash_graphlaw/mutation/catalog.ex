# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Mutation.Catalog do
  @moduledoc """
  Mutations of the guards that carry `ash_graphlaw`'s admission boundary.

  Development tooling. UNSUPPORTED(generator-capability): hand-written; no pack template emits a
  mutation court.

  Every entry names an exact `Module.function/arity` (public or private), the operator applied
  to it, and the killer test files (globs relative to the project root) that must fail when the
  guard is gone. Killers are the negative and adversarial suites: `test/negative/**` and
  `test/adversarial/**`. A target that does not resolve (renamed function, module not compiled)
  is reported `BLOCKED` with the resolver's reason; nothing is silently skipped.

  Ids are append-only and stable: `AGL-MUT-NNN`. Never renumber, reuse or delete an id; retire an
  obsolete entry by leaving it in place and letting its target resolve to `BLOCKED`.

  | id          | mutation                                                    | target |
  |-------------|-------------------------------------------------------------|--------|
  | AGL-MUT-001 | every refusal code classed `:refused_admission`             | `AshGraphLaw.Refusal.class_of/1` |
  | AGL-MUT-002 | engine digest pin check skipped                             | `AshGraphLaw.EngineLoad.check_digest/2` |
  | AGL-MUT-003 | engine import-surface check skipped                         | `AshGraphLaw.EngineLoad.check_imports/1` |
  | AGL-MUT-004 | lease ceiling check always passes                           | `AshGraphLaw.Authority.check_ceiling/2` |
  | AGL-MUT-005 | change swallows the refusal (adds no error, no evidence)    | `AshGraphLaw.Change.Admit.run/2` |
  | AGL-MUT-006 | projection emits sensitive arguments                        | `AshGraphLaw.Projection.Default.argument_slots/2` |
  | AGL-MUT-007 | an admitted result is standing `:ALIVE`                     | `AshGraphLaw.Standing.of/1` |
  | AGL-MUT-008 | duplicate admission names accepted                          | `AshGraphLaw.Contract.duplicate_refusals/1` |
  | AGL-MUT-009 | expected engine digest is always `:unpinned`                | `AshGraphLaw.WasmConfig.expected_sha256/1` |
  | AGL-MUT-010 | invalid UTF-8 request text no longer refused                | `AshGraphLaw.ABI.classify_encode_error/1` |
  | AGL-MUT-011 | payload steps no longer require a law module                | `AshGraphLaw.Contract.law_refusals/1` |
  | AGL-MUT-012 | malformed trusted keys accepted                             | `AshGraphLaw.Contract.key_refusals/1` |
  | AGL-MUT-013 | guards of the ceiling normalization negated                 | `AshGraphLaw.Authority.ceiling_of/1` |
  | AGL-MUT-014 | every caller claims `:construct` without a signed lease     | `AshGraphLaw.Authority.claim/1` |
  | AGL-MUT-015 | parity court accepts any list comparison (P1, P2)           | `AshGraphLaw.Parity.same_list?/2` |
  | AGL-MUT-016 | parity court accepts any digest comparison (P3, R1)         | `AshGraphLaw.Parity.same_digest?/2` |
  """

  alias AshGraphLaw.Mutation

  @killers ["test/negative/**/*_test.exs", "test/adversarial/**/*_test.exs"]

  @doc "Every mutation, in id order."
  @spec entries() :: [Mutation.t()]
  def entries do
    [
      entry("AGL-MUT-001", AshGraphLaw.Refusal, :class_of, 1, {:replace_body, "refused_admission."},
        guard: "Refusal.class_of/1 closed code table",
        description: "every code, including host and authority refusals, is classed :refused_admission"
      ),
      entry("AGL-MUT-002", AshGraphLaw.EngineLoad, :check_digest, 2, {:replace_body, "ok."},
        guard: "EngineLoad digest pin",
        description: "an engine whose sha256 differs from the pin is admitted"
      ),
      entry("AGL-MUT-003", AshGraphLaw.EngineLoad, :check_imports, 1, {:replace_body, "ok."},
        guard: "EngineLoad import surface",
        description: "an engine importing outside wasi_snapshot_preview1 is admitted"
      ),
      entry("AGL-MUT-004", AshGraphLaw.Authority, :check_ceiling, 2, {:replace_body, "ok."},
        guard: "Authority lease ceiling",
        description: "an admission runs without the lease its ceiling requires"
      ),
      entry("AGL-MUT-005", AshGraphLaw.Change.Admit, :run, 2, {:replace_body, "ChicagoArg1."},
        guard: "Change.Admit refusal propagation",
        description: "the changeset is returned untouched: no refusal error and no evidence"
      ),
      entry(
        "AGL-MUT-006",
        AshGraphLaw.Projection.Default,
        :argument_slots,
        2,
        {:replace_body, sensitive_arguments_body()},
        clauses: {:clause, 2},
        guard: "Projection.Default redaction of sensitive arguments",
        description: "arguments marked sensitive are projected into the N-Triples sent to the engine"
      ),
      entry("AGL-MUT-007", AshGraphLaw.Standing, :of, 1, {:replace_body, "'ALIVE'."},
        clauses: {:clause, 1},
        guard: "Standing.of/1 admitted result",
        description: "an admission observed on an exact input is claimed :ALIVE, not :PARTIAL_ALIVE"
      ),
      entry("AGL-MUT-008", AshGraphLaw.Contract, :duplicate_refusals, 1, {:replace_body, "[]."},
        guard: "Contract duplicate admission names",
        description: "two admissions with the same name pass verification"
      ),
      entry("AGL-MUT-009", AshGraphLaw.WasmConfig, :expected_sha256, 1, {:replace_body, "unpinned."},
        guard: "WasmConfig pin",
        description: "no engine is ever compared with the pinned digest"
      ),
      # Moved from `Host.ensure_utf8/1`: the court showed that guard survived (Jason rejects invalid
      # UTF-8 before the host ever sees the body), so the real refusal now lives in the ABI codec.
      entry("AGL-MUT-010", AshGraphLaw.ABI, :classify_encode_error, 1, {:replace_body, ~S|{error, <<"x">>}.|},
        clauses: {:clause, 1},
        guard: "ABI UTF-8 refusal",
        description: "invalid UTF-8 request text is reported as a JSON-shape error instead of :invalid_encoding"
      ),
      entry("AGL-MUT-011", AshGraphLaw.Contract, :law_refusals, 1, {:replace_body, "[]."},
        guard: "Contract law module requirement",
        description: "an admission whose step needs a payload passes without a law module"
      ),
      entry("AGL-MUT-012", AshGraphLaw.Contract, :key_refusals, 1, {:replace_body, "[]."},
        guard: "Contract trusted key format",
        description: "a trusted key that is not 64-character hex passes verification"
      ),
      entry("AGL-MUT-013", AshGraphLaw.Authority, :ceiling_of, 1, {:negate_guard},
        guard: "Authority ceiling normalization",
        description: "unknown ceilings are trusted and known ceilings are demoted to :observe"
      ),
      entry(
        "AGL-MUT-014",
        AshGraphLaw.Authority,
        :claim,
        1,
        {:replace_body, ~S"#{ceiling => construct, signed_lease => nil}."},
        guard: "Authority signed-lease requirement",
        description: "a caller self-grants :construct with no signed lease at all"
      ),
      entry("AGL-MUT-015", AshGraphLaw.Parity, :same_list?, 2, {:replace_body, "true."},
        guard: "Parity list comparison (P1, P2)",
        description: "a dropped, reordered or extra op or dialect no longer reports capability_parity_drift"
      ),
      entry("AGL-MUT-016", AshGraphLaw.Parity, :same_digest?, 2, {:replace_body, "true."},
        guard: "Parity digest comparison (P3, R1)",
        description: "a mismatched registry or surface digest no longer reports capability_parity_drift"
      )
    ]
  end

  @doc "Every id, in order."
  @spec ids() :: [String.t()]
  def ids, do: Enum.map(entries(), & &1.id)

  @doc "The killer globs shared by every entry."
  @spec killers() :: [String.t()]
  def killers, do: @killers

  @doc "Looks an entry up by id."
  @spec fetch(String.t()) :: {:ok, Mutation.t()} | :error
  def fetch(id) do
    case Enum.find(entries(), &(&1.id == id)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @doc """
  Resolves every entry without loading anything: whether the target can be prepared and which
  killer files exist. Options are those of `AshGraphLaw.Mutation.prepare/2` plus `:root`.
  """
  @spec resolution(keyword()) :: [map()]
  def resolution(opts \\ []) do
    root = Keyword.get(opts, :root, File.cwd!())

    for %Mutation{} = m <- entries() do
      %{
        id: m.id,
        target: Mutation.target(m),
        target_status: target_status(m, opts),
        killer_files: killer_files(m, root)
      }
    end
  end

  defp target_status(m, opts) do
    case Mutation.prepare(m, opts) do
      {:ok, _plan} -> :resolvable
      {:error, %{code: code, detail: detail}} -> {:blocked, code, detail}
    end
  end

  defp killer_files(m, root) do
    case Mutation.resolve_killers(m, root) do
      {:ok, files, _missing} -> files
      {:error, _refusal} -> []
    end
  end

  defp entry(id, module, function, arity, operator, attrs) do
    struct!(
      Mutation,
      [id: id, module: module, function: function, arity: arity, operator: operator, killers: @killers] ++ attrs
    )
  end

  # Erlang body for clause 2 of Projection.Default.argument_slots/2: project every declared
  # argument, sensitive or not. ChicagoArg1 is the action map, ChicagoArg2 the arguments map.
  defp sensitive_arguments_body do
    ~S"""
    [{erlang:list_to_binary("arg:" ++ erlang:atom_to_list(maps:get(name, A))),
      maps:get(maps:get(name, A),
               case ChicagoArg2 of nil -> #{}; M -> M end,
               nil)}
     || A <- maps:get(arguments, ChicagoArg1)].
    """
  end
end
