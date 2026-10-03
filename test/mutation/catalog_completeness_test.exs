# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Mutation.CatalogCompletenessTest do
  @moduledoc """
  Completeness of the mutation catalog against the real checkout.

  `AGL-MUT-001..016` must all exist (ids are append-only), every target must resolve in the
  compiled application, every entry must have killer files on disk, and every entry must have a
  WITNESS: a killer file that actually mentions the refusal code, class or value the guard
  produces. A killer glob that matches only unrelated files would make the mutant "survive
  unattacked" and this test names it before the mutation run does.

  The `:slow` part runs the real `mix ash_graphlaw.mutate` in a subprocess and requires the
  mutants it selects to be killed.

  UNSUPPORTED(generator-capability): hand-written; no pack emits a mutation court.
  """

  use ExUnit.Case, async: false

  alias AshGraphLaw.Mutation
  alias AshGraphLaw.Mutation.Catalog

  @expected_ids Enum.map(1..16, &"AGL-MUT-#{String.pad_leading(Integer.to_string(&1), 3, "0")}")

  # id => token a killer file must contain for the guard's observable effect
  @witness %{
    "AGL-MUT-001" => ~r/class: :refused_(authority|identity|structure)|class_of/,
    "AGL-MUT-002" => ~r/wasm_digest_mismatch/,
    "AGL-MUT-003" => ~r/wasm_import_surface_mismatch/,
    "AGL-MUT-004" => ~r/ceiling_unmet/,
    "AGL-MUT-005" => ~r/Error\.codes/,
    "AGL-MUT-006" => ~r/sensitive/,
    "AGL-MUT-007" => ~r/PARTIAL_ALIVE/,
    "AGL-MUT-008" => ~r/duplicate_admission/,
    "AGL-MUT-009" => ~r/unpinned/,
    "AGL-MUT-010" => ~r/invalid_encoding/,
    "AGL-MUT-011" => ~r/missing_law_module/,
    "AGL-MUT-012" => ~r/invalid_trusted_key/,
    "AGL-MUT-013" => ~r/"construct"|"Construct"/,
    "AGL-MUT-014" => ~r/signed_lease/,
    "AGL-MUT-015" => ~r/capability_parity_drift/,
    "AGL-MUT-016" => ~r/registry_sha256/
  }

  defp root, do: File.cwd!()

  defp killer_files(entry) do
    assert {:ok, files, missing} = Mutation.resolve_killers(entry, root())
    {files, missing}
  end

  defp witnessed?(entry, pattern) do
    {files, _missing} = killer_files(entry)
    Enum.any?(files, fn file -> file |> File.read!() |> String.replace(~r/^\s*#.*$/m, "") =~ pattern end)
  end

  test "the catalog contains exactly AGL-MUT-001..016, in order" do
    assert Catalog.ids() == @expected_ids
    assert Map.keys(@witness) |> Enum.sort() == @expected_ids
  end

  test "every target resolves in the compiled application (none is BLOCKED)" do
    for entry <- Catalog.entries() do
      assert {:ok, plan} = Mutation.prepare(entry), "#{entry.id} (#{Mutation.target(entry)}) is blocked"
      assert plan.original_md5 != plan.mutant_md5, "#{entry.id} mutant is byte-identical to the original"
      assert plan.clauses_mutated >= 1
    end
  end

  test "every entry has killer files on disk, none of its globs matches nothing" do
    for entry <- Catalog.entries() do
      {files, missing} = killer_files(entry)
      assert files != [], "#{entry.id} has no killer file"
      assert missing == [], "#{entry.id} has dead killer globs #{inspect(missing)}"

      for file <- files do
        assert Path.relative_to(file, root()) =~ ~r{^test/(negative|adversarial)/}, "#{entry.id}: #{file}"
      end
    end
  end

  test "every entry has a witness: a killer file that names the guard's observable effect" do
    for entry <- Catalog.entries() do
      pattern = Map.fetch!(@witness, entry.id)
      assert witnessed?(entry, pattern), "#{entry.id} (#{entry.guard}) has no killer mentioning #{inspect(pattern)}"
    end
  end

  test "negative control: a token no test mentions has no witness, so the check is not vacuous" do
    [entry | _] = Catalog.entries()
    refute witnessed?(entry, ~r/zz_no_such_refusal_token_zz/)
  end

  test "positive control: the witness scan ignores comments" do
    [entry | _] = Catalog.entries()
    # `AGL-MUT-` appears only in comments/moduledocs of killers, never as executable text of a test
    # named for it; the scan strips comment lines, so a pattern present only in comments is unwitnessed.
    dir = Path.join(System.tmp_dir!(), "agl-witness-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "test/negative"))
    File.write!(Path.join(dir, "test/negative/only_comment_test.exs"), "# wasm_digest_mismatch appears only here\n")
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:ok, [file], _} = Mutation.resolve_killers(%{entry | killers: ["test/negative/*_test.exs"]}, dir)
    refute File.read!(file) |> String.replace(~r/^\s*#.*$/m, "") =~ ~r/wasm_digest_mismatch/
  end

  test "every entry's guard and description are documented (no anonymous mutants)" do
    for entry <- Catalog.entries() do
      assert is_binary(entry.guard) and String.length(entry.guard) > 8
      assert is_binary(entry.description) and String.length(entry.description) > 16
    end

    assert Catalog.entries() |> Enum.map(&Mutation.target/1) |> Enum.uniq() |> length() == length(Catalog.entries())
  end

  describe "the real mix task (subprocess)" do
    @describetag :slow
    @describetag timeout: 900_000

    defp mix!(args) do
      mix = System.find_executable("mix") || flunk("mix is not on PATH")
      build = Path.join(root(), "_build-catalog-subprocess")

      System.cmd(mix, args,
        cd: root(),
        env: [{"MIX_ENV", "test"}, {"MIX_BUILD_ROOT", build}],
        stderr_to_stdout: true
      )
    end

    test "--list names all 16 ids and reports each resolvable" do
      {out, status} = mix!(["ash_graphlaw.mutate", "--list"])
      assert status == 0, out

      for id <- @expected_ids do
        assert out =~ ~r/^#{id}\t.*\tresolvable\t/m, "#{id} not listed as resolvable:\n#{out}"
      end

      refute out =~ "BLOCKED"
    end

    test "a cheap, engine-free mutant is killed by the real killers (--require-killed exits 0)" do
      {out, status} = mix!(["ash_graphlaw.mutate", "--only", "AGL-MUT-007", "--require-killed"])
      assert status == 0, out
      assert out =~ "mutant_killed"
      # The final tally prints `mutant_survived: 0` on success; a survivor is a nonzero count.
      refute out =~ ~r/mutant_survived: [1-9]/
    end
  end
end
