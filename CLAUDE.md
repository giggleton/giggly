# CLAUDE.md — giggly

Guidance for Claude Code (or any agent) working in this repo.

## What this is

Giggly is a grammar-of-graphics plotting library for Elixir, modelled on R's ggplot2 and succeeding the earlier ggity library. Plots are built by mapping tabular data to aesthetics and composing layers (geoms, stats, positions), scales, facets and coordinate systems, then rendered to SVG for Phoenix LiveView, Livebook and static output. It is for Elixir developers, particularly those already fluent in ggplot2, who want declarative, composable charts without a JavaScript rendering step.

## Where the documentation lives

- **Area rules** (`.claude/rules/*.md`) — one file per area of the code, each with a `paths:`
  frontmatter so it loads only when a file matching its globs is read: the area's rules first,
  then how it works. **A feature's invariants and mechanism live there, not here.** This file
  holds only what applies to every session, plus the status map below. A change to an area
  updates its rules file; this file changes only for a cross-cutting rule or a status-map line.
- **[notes/design-log.md](notes/design-log.md)** — the design overview, decision log, and milestone
  log. **Read it first to get oriented.** New work gets its full write-up there (§6), decisions with
  their rejected alternatives go in §4, and open questions in §7, with at most a one-line update
  here. §6 keeps only recent entries (~two weeks) in full; older ones compact to a one-line index
  after their durable content is confirmed housed in §4 and the evergreen surfaces, with the full
  write-ups remaining in git history.
- **Plans do not live in this repo.** A working plan file goes in **`~/.claude/plans/`**, never
  under `notes/` and never inside a worktree — it is scaffolding for one piece of work, not a
  documentation surface. Anything durable a plan contains (a ratified decision, a rejected
  alternative and its reason) must be copied into design-log.md §4/§6 **before** the work is
  reported done, because that is the only copy that survives: a plan in a worktree dies with
  `git worktree remove`.
- **Skills** (`.claude/skills/`) — task-triggered instructions: `dependency-updates` (taking
  anything `mix hex.outdated` offers — read the package diffs, never trust semver or the
  changelog), `docs-sync` (run after any substantive change, before reporting done — routes the
  change to the doc surfaces it must update), `elixir-code-review` (run before reporting done on
  any change touching `test/` or a GenServer — and on any new lint/security
  waiver; not only when a review is asked for), `test-timing` (measuring the suite, on demand
  only). **`docs-sync` and `elixir-code-review` are harness-enforced**:
  `.claude/hooks/commit-gate.sh` (a PreToolUse hook) denies `git commit` on any diff touching
  those gated paths until both skills' final steps have recorded a pass for the exact working-tree
  state — a mark that goes stale if any file changes after it.
- Moduledocs are the per-module contract and are kept accurate; trust them.

## Status map

Everything below is **built and merged to `main`** unless marked otherwise. Full histories:
design-log.md §6. Each line names the area's rules file, which carries its invariants and how it
works. Add a line here when an area gets its rules file; nothing else about the area belongs here.

- **Dependencies, toolchain, lint and security waivers** — `.claude/rules/dependencies.md`; the
  `dependency-updates` skill.
- **The documentation system** (what goes where, the ratchet) — `.claude/rules/docs.md`; the
  `docs-sync` skill.
- **Open items** — design-log.md §7.

## Approach & architecture

- **Functional-core-first, and the compiler holds it.** The architecture is declared with
  `boundary` (`use Boundary` in the namespace root modules; `compilers: [:boundary]` in `mix.exs`),
  so a forbidden cross-namespace call is a compiler warning and therefore a gate failure under
  `--warnings-as-errors`. The shape to grow into: the pure domain rules are their own boundary
  (`Giggly.Core`, `type: :strict`, so a core module reaching a context, config or any
  external library fails the build); each namespace's root module is its public API and the
  modules beneath it are implementation; one `Settings` module is the only place application
  config is read; callers reach the library through its root modules, and nothing inside reaches
  back out.
  **`mix boundary.spec` prints the graph**, and no list here restates it — a hand-maintained list
  of what is pure goes wrong in every copy of it. Widening a boundary's `deps:` or `exports:` is a
  decision for the user, and `.claude/hooks/waiver-gate.sh` stops the edit until it has been
  explained in conversation (`.claude/rules/dependencies.md`).
- **Determinism via injected seeds.** All randomness derives from injected integer seeds (the
  state-passing `:rand` API, `:erlang.phash2`), so every run is reproducible and fully
  unit-testable with no network. No clock read in the core either: a `Clock` module at the boundary
  reads "now" and hands the instant to a pure function.
- **External services are flavor, behind a behaviour boundary.** Anything that talks to the
  network — an HTTP client, an LLM, a mail adapter — sits behind a behaviour with a stub for tests,
  and never decides domain logic. The suite runs offline, always.
- **Pipes in the core, `with`s at the boundary.** Pure-core builders are **assertive**: they take
  already-validated data, return **plain structs**, and raise (`FunctionClauseError`, via guards)
  on programmer error — so they chain cleanly with `|>`. Untrusted input is validated at the
  **boundary** shells (contexts, controllers), where errors become data: those return
  `{:ok, t} | {:error, reason}` and thread the happy path with `with`. Validation uses guards
  (incl. custom `defguard`s) rather than `cond`. `:none` is the "absent" sentinel (not `nil`).

## Conventions

- **Quality gate — run `mix quality` before every commit and keep it green.** The alias runs
  `mix tack.quality`, which executes every step in the `quality_steps` list in `mix.exs`,
  in order, each in its own `mix` subprocess, and **stops at the first failing step** with a
  `❌ mix quality FAILED at step: <name>` banner as its final lines. That list is the single source
  of truth: CI runs `mix quality --check` (the same list minus the formatting write), so a step
  added there is picked up by CI with no second list to keep in sync. What the steps are for:
  - `mix format` runs **first**, so an unformatted file is fixed up front instead of surfacing only
    at the trailing `--check-formatted` step after the whole suite has already run.
  - **`mix hex.audit` runs every time**, not just when `mix.exs`/`mix.lock` change: a new advisory
    can be published against a dependency you already have, so an unchanged tree can go from
    clean to vulnerable with no code change. It fails on retired packages as well as advisories.
    Triage a false positive via the `:hex` project key's `ignore_advisories` list in `mix.exs`,
    never by skipping the step. **Requires Hex ≥ 2.5** — older Hex checks retirements only and
    exits 0, so the gate refuses to run under it (`mix local.hex --force` to update).
  - `mix deps.unlock --check-unused` fails when `mix.lock` carries an entry for a package `mix.exs`
    no longer declares. This is the one failure that **cannot** surface locally otherwise: the
    stale `deps/` directory stays on disk, so every other step is happy, while CI fetches only the
    declared tree and finds it missing. Offline and instant; fix with `mix deps.unlock --unused`.
  - Both `mix compile --warnings-as-errors` (in `:dev` and in `:test`) warm the two build dirs; a
    compile warning is a hard failure, matching CI. `mix test --warnings-as-errors` makes a warning
    in any test file fail the gate too, so stray test-file warnings can't pile up unnoticed. A
    guard test that deliberately calls a function with the wrong type to assert it raises routes
    the bad argument through a small `@spec`'d type-erasing identity helper, so the set-theoretic
    type checker doesn't flag the deliberate misuse.
  - `mix credo --strict` **must report no issues.** The checks are an explicit allowlist in
    `.credo.exs`; new ones are adopted deliberately, never by plugin default.
  - `mix tack.rules_check` keeps the agent-facing docs from regrowing into the shape that
    rots: CLAUDE.md may not exceed the line budget in `.claude/rules/BUDGET`; every `paths:` glob
    in `.claude/rules/*.md` must match an existing file (an orphan glob is a rule that silently
    never loads); and the count of `lib/**/*.ex` files no glob covers may not rise. The budgets
    are ratchets — `--tighten` only lowers them, and an edit that raises one stops and asks the
    user (`.claude/hooks/waiver-gate.sh`).

  **Run `mix quality` bare — never pipe it (or any single step) through `tail`, `head`, or
  `grep`.** A pipe hides the failing step's output and makes the shell report the *pipe's* exit
  status (`0`), masking the gate's failure. When a step fails, read the output directly ABOVE the
  final `❌ … FAILED` banner. To iterate on one check in isolation, run that single `mix` task
  directly — still bare.
- Do not commit or ask the user to commit changes. The user will prompt you to commit and does not
  want to be reminded/encouraged to do so. Similarly do not merge or deploy without a prompt from
  the user.
- **Merging a feature branch:** if the branch has just one commit, merge it fast-forward (no merge
  commit). Use a `--no-ff` merge commit only when the branch carries two or more commits.
- Work in **small, verifiable increments** and keep the suite green. Prefer async tests wherever
  possible; a file that is `async: false` says in its header what stops it.
- **Document public API.** Every module gets a `@moduledoc` and every public function a `@doc`
  (and a `@spec`); these are the pure core's contract and feed `ex_doc`. Use `@moduledoc false`
  only for modules with no public surface. Private functions (`defp`) don't need `@doc`; clarify
  them with a brief comment when non-obvious.
- **Configuration is read in one place** — a `Settings` module with one documented accessor per
  switch, carrying its default and where it is set. Nothing else under `lib/` calls
  `Application.get_env`; the core reads no config at all and takes the value as an argument.
- **Follow credo conventions.** If credo flags a style requirement, remember that and don't make
  the same mistake again. **A new lint or security waiver stops and asks the user** —
  `.claude/rules/dependencies.md`.
- **Follow mix format conventions.** Don't write code that isn't consistent with the mix format
  rules.
- **No capture-operator anonymous functions.** Always write anonymous functions as
  `fn descriptive_name -> body end` — never the `&`/`&1` shorthand (e.g. `& &1.id`, `&(&1 + 1)`).
  `&Mod.fun/arity` references are ok. Prefer descriptive argument names over positional `&1`.
- **Descriptive names; no abbreviations or single letters.** Spell names out: `position` not
  `pos`, `points` not `pts`, `value` not `v`. Never single-letter variables (no `p`, `s`, `n`,
  `r`). Spell out domain terms in code too; acronyms are fine only in prose where defined.
- **One name per module kind; no two in a family share a last segment** — a shared tail collides
  silently at `alias`. A process module ends in `Server`, `Worker`, `Watcher` or `Poller`; a
  singular name is a pure type or fold, its plural the context owning the table.

## Deployment

- **Claude never has access to the keys** — if a task needs a secret (an API key, a signing key,
  a deploy token), prompt the user to run that step.
- Everything else about deployment belongs in `.claude/rules/deploy.md` once there is a deployment
  to describe. Never state a deployed value from this repo; say where to look.
