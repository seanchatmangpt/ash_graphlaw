# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# DSL entity and option calls of the `graphlaw` section format without parentheses, in this project and
# (through `export`) in every project that `import_deps: [:ash_graphlaw]`.
spark_locals_without_parens = [
  admission: 1,
  admission: 2,
  ceiling: 1,
  law: 1,
  max_skew_secs: 1,
  projection: 1,
  runtime: 1,
  step: 1,
  timeout_ms: 1,
  trusted_keys: 1,
  wasm_path: 1
]

[
  import_deps: [:ash, :spark],
  plugins: [AshGraphLaw.Formatter, Spark.Formatter],
  spark: [
    extensions: [AshGraphLaw.Resource]
  ],
  line_length: 120,
  trailing_comma: true,
  local_pipe_with_parens: true,
  single_clause_on_do: true,
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test,scripts}/**/*.{ex,exs}"
  ]
]
