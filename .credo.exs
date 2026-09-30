# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written analyser config.
# Run as `mix credo` (aliased to `credo --strict`). Defaults are kept; each
# disabled check below carries the reason it cannot hold in this codebase.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/", "mix.exs"],
        excluded: [~r"/_build", ~r"/_build-lane", ~r"/deps/", ~r"/vendor/", ~r"/cover/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        disabled: [
          # Generated modules (Dsl.*, Resource, Persist, Verify, Info) and the
          # Spark/Ash DSL reference fully-qualified module names inside
          # `use`/`extensions:` lists and DSL entity structs; aliasing them
          # changes the emitted code, and generated files are never hand-edited.
          # Measured 2026-09-29 with `if_nested_deeper_than: 2` enabled: 44 findings
          # (`mix credo --strict`), so the check stays disabled rather than baselined.
          {Credo.Check.Design.AliasUsage, []},
          # TODO/FIXME tags are not used as tracking; open work lives in the
          # CHANGELOG and docs/reference/claims_and_evidence.md, so the check
          # carries no information here and would only fire on quoted doc text.
          {Credo.Check.Design.TagTODO, []},
          {Credo.Check.Design.TagFIXME, []}
        ]
      }
    }
  ]
}
