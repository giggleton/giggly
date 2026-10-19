# CLAUDE.md — giggly

Guidance for Claude Code (or any agent) working in this repo.

## What this is

Giggly is a grammar-of-graphics plotting library for Elixir, modelled on R's ggplot2 and succeeding the earlier ggity library. Plots are built by mapping tabular data to aesthetics and composing layers (geoms, stats, positions), scales, facets and coordinate systems, then rendered to SVG for Phoenix LiveView, Livebook and static output. It is for Elixir developers, particularly those already fluent in ggplot2, who want declarative, composable charts without a JavaScript rendering step.

## Where the documentation lives

- **Area rules** (`.claude/rules/*.md`) — one file per area of the code, each with a `paths:`
  frontmatter so it loads only when a file matching its globs is read. **A feature's invariants
  live there, not here; its mechanism lives in the module's documentation.** This file holds
  only what applies to every session, plus the status map below. A change to an area updates its
  rules file; this file changes only for a cross-cutting rule or a status-map line.
- **[notes/design-log.md](notes/design-log.md)** — the design overview and decision log. **It is
  reference, not reading:** orient from the plan's "Where we are", and read a §4 entry when a rules
  file or the plan names it. A decision with its rejected alternatives goes in §4 (about 150
  words); a milestone is one §6 line naming its commit, whose message tells the story; open
  questions go in §7.
- **Plans do not live in this repo.** A working plan file goes in **`~/.claude/plans/`**, never
  under `notes/` and never inside a worktree — it is scaffolding for the current work, its "Where
  we are" a few hundred words, not a documentation surface. Anything durable a plan contains (a
  ratified decision, a rejected alternative and its reason) must be copied into design-log.md §4
  **before** the work is reported done, because that is the only copy that survives.
- **Skills** (`.claude/skills/`) — task-triggered instructions: `dependency-updates` (taking
  anything `mix hex.outdated` offers — read the package diffs, never trust semver or the
  changelog), `docs-sync` (run after any substantive change, before reporting done — routes the
  change to the doc surfaces it must update), `elixir-code-review` (run before reporting done on
  any change touching `test/` or a GenServer — and on any new lint/security waiver; not only when
  a review is asked for), `mutation-testing` (after each commit, over the code lines it changed),
  `test-timing` (measuring the suite, on demand only). **`docs-sync`, `elixir-code-review` and
  `mutation-testing` are harness-enforced**: `.claude/hooks/commit-gate.sh` (a PreToolUse hook)
  denies `git commit` on a diff touching those gated paths until the review and docs passes are
  marked for its exact state, and denies any commit while the last one's mutation pass is not.
- Module documentation is the per-module contract and is kept accurate; trust it: an API
  module's `@moduledoc`, or the comment block at the top of an internal module.

## Status map

Everything below is **built and merged to `main`** unless marked otherwise. Histories: the commit
messages, indexed in design-log.md §6. Each line names the area's rules file, which carries its
invariants. Add a line here when an area gets its rules file; nothing else about it belongs here.

- **Dependencies, toolchain, the quality gate's steps, lint and security waivers** —
  `.claude/rules/dependencies.md`; the `dependency-updates` skill.
- **The documentation system** (what goes where, the ratchet) — `.claude/rules/docs.md`; the
  `docs-sync` skill.
- **The aesthetic vocabulary** (spelling, the x/y position families) — `.claude/rules/aesthetics.md`.
- **The data frame** (layer data, input tables, column types) — `.claude/rules/data_frame.md`.
- **The plot spec and its public API** (`Giggly.Plot`, layers, checking mappings at the call) —
  `.claude/rules/plot.md`.
- **Mapping values** (`Giggly.Mapping`, expressions, constants) — `.claude/rules/mapping.md`.
- **The assembly** (`Giggly.Assembly`, the stage order, the `group` column, the run functions in
  `Giggly`) — `.claude/rules/assembly.md`.
- **The facet** (`Giggly.Facet`, the `panel` column, the layout table) — `.claude/rules/facet.md`.
- **Scales** (`Giggly.Scale`, kinds, transformations, training, mapping, palettes) —
  `.claude/rules/scale.md`.
- **Colours** (`Giggly.ColorOperations`, reading a colour) — `.claude/rules/color_operations.md`.
- **Stats** (`Giggly.Stat`, the protocol a layer's stat runs through) — `.claude/rules/stat.md`.
- **Positions** (`Giggly.Position`, the protocol positions run through) — `.claude/rules/position.md`.
- **The coordinate system** (`Giggly.Coord`, panel params, the only route to the unit panel) —
  `.claude/rules/coord.md`.
- **Geoms** (`Giggly.Geom`, drawing a panel's rows as primitives) — `.claude/rules/geom.md`.
- **Resolution** (`Giggly.Resolution`, ggplot2's `resolution()`) — `.claude/rules/resolution.md`.
- **Values as R writes them** (`Giggly.AsCharacter`) — `.claude/rules/as_character.md`.
- **Guides** (`Giggly.Guide`, axes, legends, every title) — `.claude/rules/guide.md`.
- **The theme** (`Giggly.Theme`, the complete theme everything but the marks is drawn in) —
  `.claude/rules/theme.md`.
- **Text measurement** (`Giggly.Font`, the glyph table ggplot2's snapshots measure with) —
  `.claude/rules/font.md`.
- **Rendering** (`Giggly.Render`, an assembled plot into a scene) — `.claude/rules/render.md`.
- **The scene** (`Giggly.Scene`, the table of cells and its primitives) — `.claude/rules/scene.md`.
- **The SVG backend** (`Giggly.SVG`, `Giggly.to_svg/2`, the goldens) — `.claude/rules/svg.md`.
- **Datasets** (`Giggly.Datasets`, R's tables for examples and users) — `.claude/rules/datasets.md`.
- **Notebooks** (`notebooks/`, Livebooks following ggplot2's reference pages) —
  `.claude/rules/notebooks.md`.

## Approach & architecture

- **The whole library is the pure core, and the compiler holds its shape.** The architecture is
  declared with `boundary` (`use Boundary` in each domain's root module; `compilers: [:boundary]`
  in `mix.exs`), so a forbidden reference is a compiler warning and therefore a gate failure under
  `--warnings-as-errors`. Every boundary is strict (the `mix.exs` default, pinned by
  `boundary_declarations_test.exs`), so a boundary's `deps:` is the whole of what it may call,
  outside libraries included. A plot is a value built by `Giggly.Plot` and run by the functions
  in `Giggly`; every other domain is its own boundary, carved when its first module lands, and
  its `deps:` is its contract. A domain that owns an outside library lists it, as the root must
  too; no other domain lists it. Arrows run one way, from what runs a plot toward
  the data; nothing calls back up. What boundary cannot see — the standard library — the
  `CorePurity` credo check covers over all of `lib/`: no clock, config, unseeded randomness,
  process or IO, an impure module excluded by name.
  **`mix boundary.spec` prints the graph**, and no list here restates it. Widening a boundary's
  `deps:` or `exports:` is a decision for the user, and `.claude/hooks/waiver-gate.sh` stops the
  edit until it has been explained in conversation (`.claude/rules/dependencies.md`).
- **The pipeline is pure: no application config, no clock, no unseeded randomness.** Every option
  is an argument, and the one random step (jitter) takes an injected integer seed, so a render is
  reproducible and the suite runs offline.
- **The public API raises; everything beneath it is assertive and pipes.** The `Giggly.Plot`
  functions validate their options with NimbleOptions and raise on anything invalid, since a pipe
  cannot carry `{:error, reason}`. The functions beneath take already-validated data, return
  **plain structs**, and raise (`FunctionClauseError`, via guards) on programmer error. Validation
  uses guards (incl. custom `defguard`s) rather than `cond`. `:none` is the "absent" sentinel,
  not `nil`; a limit the data supplies is `nil` (design-log §4, the entry beginning "Absent").

## Conventions

- **Quality gate — run `mix quality` before every commit and keep it green.** It runs the
  `quality_steps` list in `mix.exs` in order and **stops at the first failing step**, ending with a
  `❌ mix quality FAILED at step: <name>` banner; CI runs the same list with `mix quality --check`.
  Why each step is there is in `.claude/rules/dependencies.md`. The two failures ordinary work
  hits: `deps (unused)`, fixed with `mix deps.unlock --unused`; and a `hex.audit` advisory against
  an unchanged tree, which goes to the user — never a skipped step.

  **Run `mix quality` bare — never pipe it (or any single step) through `tail`, `head`, or
  `grep`.** A pipe hides the failing step's output and makes the shell report the *pipe's* exit
  status (`0`), masking the gate's failure. When a step fails, read the output directly ABOVE the
  final `❌ … FAILED` banner. To iterate on one check in isolation, run that single `mix` task
  directly — still bare.
- Do not commit or ask the user to commit changes. The user will prompt you to commit and does not
  want to be reminded/encouraged to do so. Similarly do not merge or publish without a prompt from
  the user.
- **Merging a feature branch:** if the branch has just one commit, merge it fast-forward (no merge
  commit). Use a `--no-ff` merge commit only when the branch carries two or more commits.
- Work in **small, verifiable increments** and keep the suite green. Prefer async tests wherever
  possible; a file that is `async: false` says in its header what stops it.
- **Document the public API, and mark everything else as not API.** The API is what a user
  calls. An API module has a `@moduledoc`; an internal module has `@moduledoc false` and keeps its
  documentation as a comment block at its top. Every public function has a `@spec` and says
  whether it is API, wherever it is: a `@doc` string, whose examples run as doctests, or
  `@doc false`, its explanation a comment. A function that is not API is tested by ordinary
  tests, never doctests. Private functions (`defp`) don't need `@doc`; clarify them with a brief
  comment when non-obvious. API docs never compare with ggplot2; the notebooks do.
- **Follow credo conventions.** If credo flags a style requirement, remember that and don't make
  the same mistake again. **A new lint or security waiver stops and asks the user** —
  `.claude/rules/dependencies.md`.
- **No capture-operator anonymous functions.** Always write anonymous functions as
  `fn descriptive_name -> body end` — never the `&`/`&1` shorthand (e.g. `& &1.id`, `&(&1 + 1)`).
  `&Mod.fun/arity` references are ok. Prefer descriptive argument names over positional `&1`.
- **Zip and map in one pass:** `Enum.zip_with/2,3`, never `Enum.zip` piped or passed into
  `Enum.map`. `GigglyCredo.Check.ZipMap` (`.credo/checks/`) fails the gate on it.
- **Descriptive names; no abbreviations or single letters.** Spell names out: `position` not
  `pos`, `points` not `pts`, `value` not `v`. Never single-letter variables (no `p`, `s`, `n`,
  `r`). Spell out domain terms in code too; acronyms are fine only in prose where defined.
- **One name per module kind; no two in a family share a last segment** — a shared tail collides
  silently at `alias`. Where ggplot2's names repeat a tail across families (`Stat.Identity`,
  `Position.Identity`, `Transform.Identity`), alias the family and write `Stat.Identity`; never
  alias such a module down to its last segment. A process module ends in `Server`, `Worker`,
  `Watcher` or `Poller`; a singular name is a pure type or fold, its plural the context owning the
  table.

## Publishing

- **Claude never has access to the keys** — publishing to Hex (`mix hex.publish`), and anything
  else that needs a secret, is a step the user runs.
