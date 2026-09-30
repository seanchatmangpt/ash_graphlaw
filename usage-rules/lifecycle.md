<!--
SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Lifecycle

- Lifecycle modules: `Validation.Shacl`, `Change.Canonicalize`, `Calculation.Conforms`,
  `Calculation.CanonicalId`, `Calculation.Sparql`. All project the subject through
  `AshGraphLaw.Projection` and call a typed op via `AshGraphLaw.Lifecycle`.
- Options are validated at compile time (`init/1`); required: `:shapes` (Conforms, Shacl), `:query`
  (Sparql), `:attribute` (Canonicalize). Shared: `:projection`, `:server`, `:timeout`, `:lease`,
  and `:lease_key` for changeset modules.
- A refusal becomes `AshGraphLaw.Error.Refused` with the typed refusal inside; never raise from
  inside these modules and never drop a refusal.
- Trust anchors and clocks are never read from options.
- The projection's default subject IRI contains the primary key: `CanonicalId` depends on it.
- Use `AshGraphLaw.Admissions`, not the generated `Info`, from hand-written code.
- Reactor steps (`AshGraphLaw.Reactor.Hooks`, `.Capability`) need the optional `:reactor`
  dependency, define no compensation or undo, and never request retry.

See [use capability calculations](../documentation/how_to/use_capability_calculations.md).
