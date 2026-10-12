# giggly — Design Notes

The canonical design overview, decision log and milestone log. CLAUDE.md says what applies to
every session; the area files under `.claude/rules/` say how each area works; this file says
**why** — what was decided, what was rejected, and what shipped when. The `docs-sync` skill routes
changes here; `.claude/rules/docs.md` is the shape.

## 1. What we're building

Giggly is a grammar-of-graphics plotting library for Elixir, modelled on R's ggplot2 and the
from-scratch successor to ggity. A plot is an immutable spec built with a pipe — data, a mapping
from aesthetics to columns, layers (each a geom, a stat and a position), scales, a facet and a
coordinate system — which a build step turns into per-panel layer tables and trained scales, and a
render step turns into a scene graph and then SVG. It is for Elixir developers, especially those
already fluent in ggplot2, who want declarative, composable charts in Phoenix LiveView, Livebook
and static files without a JavaScript rendering step.

The pre-design research — how ggplot2's build pipeline, scales, layout, facets and coords fit
together; why ggity could not grow facets or coordinate systems; and what the Elixir ecosystem
offers — is working material outside the repo, in `~/.claude/plans/giggly-research/` (its
`00-synthesis.md` is the proposed build order), as CLAUDE.md asks of plans. Nothing from it has
been ratified yet; decisions and their rejected alternatives move into §4 as they are made.

## 2. Architecture & principles

_The shape of the system in prose: the boundaries (`mix boundary.spec` prints the graph), the
pure core and what sits around it, where external services are kept, how time and randomness are
handled. Principles that span areas go here; an area's own rules go in its `.claude/rules` file._

## 3. Module map

_A short orientation to the tree, by namespace. Point at directories and moduledocs rather than
listing modules — a hand-maintained list goes stale._

## 4. Key design decisions (the "why", so we don't relitigate)

Each entry: **the decision (date, whose call)**, then *Rejected: the alternative* — and why. Newest
first. A decision belongs here when someone could plausibly propose undoing it; the entry is what
stops the question being reopened from scratch.

## 5. Testing approach

_The tiers (exhaustive at the pure core, thin smoke above it), what runs offline and how, the
fixture builders, and the suite's conventions that `elixir-code-review`'s `test-quality.md`
enforces._

## 6. Milestone log & roadmap

Entries older than about two weeks are compacted into the one-line index below; newer ones are kept
in full and compact on the same schedule as they age. Before an entry is compacted its durable
content is verified to live in the evergreen surfaces — decisions and rejected alternatives in §4,
current behaviour in CLAUDE.md / the rules files / the skills / moduledocs — so the index is a
finding aid, not the record. The full text is one `git log -S "<its title>"` away.

**Compacted index:**

_(none yet)_

**Full entries (newest first):**

- **2026-10-11 — The coding harness installed.** `mix tack.install --profile library` wrote
  CLAUDE.md, the `.claude/` rules, skills and hooks, `.credo.exs` and the `boundary`
  declarations, the `mix quality` gate and CI. It ran directly rather than through
  `mix igniter.install tack@git:…` because igniter's `git:` form splits on `@` to read a ref, so
  an SSH URL (`git@github.com:…`) is unusable there and the HTTPS form has no credentials on this
  machine; igniter was added to `mix.exs` for the run and removed after. The `mix new` placeholder
  (`Giggly.hello/0` and its test) was deleted rather than given a `@spec`, which is what brought the
  first `mix quality` run to green. Nothing about the product has been decided yet; the pre-design
  research is in `~/.claude/plans/giggly-research/` (§1).

## 7. Deferred / open questions

- **`tack` is a git dependency with no `ref`/`tag`.** `mix.lock` pins the commit, so builds are
  reproducible, but `mix deps.update tack` floats to the branch head. Settled by pinning a `tag:`
  once Tack publishes releases.
