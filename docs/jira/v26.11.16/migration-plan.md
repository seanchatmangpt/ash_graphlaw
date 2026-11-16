# ash_graphlaw migration plan v26.11.16

Standing: UNVERIFIED

## Identity
- path: /Users/sac/ash_graphlaw
- remote: https://github.com/seanchatmangpt/ash_graphlaw
- branch@sha: main@9ef416b (tracks origin/main)
- last commit: 2026-11-10; commits: 70; size: 116 MB
- languages/build: Elixir (mix.exs, mix.lock), ggen (ggen.toml, ontology.ttl), REUSE/SPDX
- nested repos: none

## Observed state
- dirty: 0; untracked: 1 (`docs/jira/v26.11.12/`)
- ahead/behind origin/main: 0/0; stash: 0; unpushed local branches: 0
- local branches `docs/doc-hdit-remediation-round-1`, `docs/scaffold-cell-repair-94` both pushed
- ~9 remote-only `factory-b/*`, `factory-e/*`, dependabot branches not merged into main
- build/dep dirs: `_build`, `deps` absent at measurement time
- local-only artifacts: `ash_graphlaw-26.11.10.tar` (282 KB), `ash_graphlaw-26.9.30.tar`
  (226 KB) — hex package tarballs at repo root, untracked/ignored
- submodules: none

## What it is
Ash extension for graphlaw: hex-published Elixir library (hexdocs badge), README and docs are
ggen-generated from `ontology.ttl` — "DO NOT EDIT" surfaces. Last wave adopted graphlaw
v26.10.28 blake3 digest keys.

## Classification
ACTIVE (census agrees; commits through 2026-11-10, two jira dirs this month).

## Migration risk
- untracked `docs/jira/v26.11.12/` would be lost
- two hex tarballs are reproducible from tags; low value
Rate: LOW

## Recommended action
COMMIT-PUSH
1. `cd /Users/sac/ash_graphlaw && git add docs/jira && git commit -m "docs: jira v26.11.12 + v26.11.16"`
2. `git push origin main`
3. `rm -rf _build deps` (if present) and `rm -f ash_graphlaw-*.tar` (reproducible via `mix hex.build`).
4. DECISION: the `factory-b/*` and `factory-e/*` remote branches — keep or delete on GitHub.
5. On new machine: clone fresh; do not rsync.

## First commands on the new machine
`git clone https://github.com/seanchatmangpt/ash_graphlaw && cd ash_graphlaw && mix deps.get && mix test`

## See Also
- ../v26.11.12/
- /Users/sac/docs/jira/v26.11.16/README.md
