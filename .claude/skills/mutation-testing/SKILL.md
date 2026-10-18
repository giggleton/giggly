---
name: mutation-testing
description: Mutation-tests the lines the last commit changed, with muex, and triages every surviving mutant — a behavior no test pins, unreachable or redundant code, an equivalent mutant, a message's wording — then writes the fixes and reports what it found. Run it right after every commit that changes `lib/` or `.credo/checks/` code; an after-commit hook names the commit, and the commit gate denies the next commit until this skill's final step has marked it. Also use it when the user asks for a mutation run, or asks which of a commit's lines no test pins.
---

# Mutation testing — after a commit, over the lines it changed

muex breaks the code one small edit at a time (a guard replaced with `true`, `==` with `!=`, a
clause deleted) and reruns the tests against each mutant. A mutant that survives is a behavior no
test pins — found from the code, not from the tests already written, which is the hole a
hand-picked mutant misses.

It runs after the commit, not in the review before it, and over the lines the commit changed, not
the whole files it touched: over whole files a run took 30–60 minutes, and the unchanged lines
added almost nothing (design-log §4, "Mutation testing runs after each commit").

## Scope

The lines the last commit added or changed in `lib/**/*.ex` (and `.credo/checks/**/*.ex`, below).
A commit that changes only tests, docs or configuration has nothing to mutate, and a merge has
none of its own: the commits it brings in had their passes.

Before starting, `lib/`, `test/` and `.credo/` must match the commit. This must print nothing:

```bash
git status --porcelain -- lib test .credo
```

muex reads the changed line numbers from the commit but mutates and tests the files on disk, so an
uncommitted edit there shifts the lines it mutates and changes the tests it runs. If it prints
anything, stop and say so: the pass is of the commit, not of the working tree.

## Running it

```bash
mix muex --since HEAD~1 --no-optimize --no-filter --verbose --coverage-guided \
  --format json --output <scratchpad>/muex.json \
  --files "$(git diff --name-only --diff-filter=d HEAD~1 HEAD -- 'lib/*.ex' | paste -sd, -)"
```

Run it in the background, and edit nothing under `lib/` or `test/` until it finishes: its
sandboxes symlink the project, so an edit lands in every mutant still to be built.

Every flag there carries weight:
- **`--since HEAD~1`** — mutates only the lines the commit added or changed: muex diffs
  `HEAD~1...HEAD` with no context lines and drops every mutant on another line. It reads committed
  history only, which is why the pass follows the commit.
- **`--files`, the commit's changed `lib/` files** — `--since` alone loads every file under `lib/`
  and keeps the changed ones without saying how many; naming them makes `--verbose`'s count
  checkable. `--diff-filter=d` leaves out a file the commit deleted, which cannot load. The value is
  **one `--files`, comma-separated**: given `--files` twice, muex keeps only the last, so naming
  each file in a flag of its own silently mutates only the last one. It splits the value on
  commas, which is also why a brace glob (`lib/{a,b}.ex`) crashes its loader.
- **`--no-optimize`** — the default optimizer discards most mutants, so a bare `mix muex` can
  report a perfect score over a handful of them: a confident false pass.
- **`--no-filter`** — the default filter skips modules it takes for framework code, including any
  declaring several `@callback`s, which a behaviour module with real logic beside its callbacks
  does.
- **`--verbose`** — prints `Found <n> file(s)` before any mutant runs. Check that it counts every
  file named: a file that never loads is never mutated, and the summary line does not say so. Its
  `Scoping to <n> file(s) changed since HEAD~1` counts every file the commit added lines to, tests
  and docs included, so it is not the number to check.
- **`--coverage-guided`** — runs each test file once under `:cover` first, then runs against each
  mutant exactly the test files that execute its line. Without it, muex picks a mutant's tests by
  scanning test sources for module names, and the scan is blind to a grouped alias
  (`alias Giggly.{DataFrame, Plot}`, after which `Plot.new` reads as a module named `Plot`) and to
  `doctest Mod`. A module linked to some test files then runs only those, so a test file that
  exercises it under a grouped alias never runs against its mutants and they "survive" it; that
  happened to `Plot.computed_mapping/2`. Coverage also reports the lines no test executes at all.
  The run leaves `cover/muex_cov_*.coverdata`, which git ignores.
- **`--format json --output`** — the terminal report gives only a count of the uncovered
  mutants. The JSON report gives every mutant its `status`, `location`, the `test_files` that ran,
  and a `patch` of the mutated node `before` and `after`. A statement deletion's node is the whole
  enclosing block, so diff the two to see the line that went.
  Write it outside the repository (the session's scratchpad); the terminal then prints one summary
  line.

**A repo-local credo check** (`.credo/checks/`) the commit changed is run on its own, with
`--files .credo/checks/<check>.ex --since HEAD~1 --mirror .credo` and **without**
`--coverage-guided`: muex writes a mutant only into a directory the sandbox mirrors, and refuses
to write through the symlink otherwise; and `:cover` cannot see a module the test loads with
`Code.require_file`, so every mutant would be reported uncovered. muex then picks the test file by
the module's name, which `test/credo_checks_test.exs` gives through a single `alias`.

Each mutant is one sandboxed `mix test`, so even a commit's lines take minutes, which is why it is
not a `mix quality` step.

## Findings

The output to act on is the **survivors** and the **uncovered mutants**, not the score. Each
survivor is one of three things, and the report says which; each uncovered mutant is a fourth.

### 1. A behavior no test pins

A coverage hole, and the worst kind when a `@doc` promises the behavior. The fix is a test naming
the bug the mutant introduced — a doctest only on an API function. Prove the new test by applying
the survivor's `patch` by hand and watching the test fail: copy the file aside first, apply the
mutant, run the test, copy the original back, `cmp` it against the copy, then `touch` it — a
restore within the same second as the mutant's compile leaves the mutant's `.beam` in place. Never
loop `sed -i.bak`. A test that passes with the mutant applied has not closed the hole.

Coverage-guided selection misses code read only at compile time (a module attribute table, such
as `Aesthetics`' pairs): a survivor there is checked by hand against the full suite before it is
called a hole.

### 2. Code the mutant shows is unreachable or redundant

Such as a guard its only caller already enforces — a finding on the code, not a missing test.

### 3. Equivalent — not a finding, but named

The mutant cannot change behavior: map keys reordered, `Map.put` → `Map.put_new` where a guard
already excludes the key, a type guard whose removal only changes which exception a programmer
error raises, a range of one row or column with its ends swapped (`3..3`), dropping a stage that
runs an identity (the identity stat or position). muex never mutates documentation or typespec
attributes, so a survivor that seems to delete a `@moduledoc` is a neighbouring statement. Named with the reason, so the call can be checked; a survivor is never dismissed
silently. Diff the `patch`'s `before` and `after` to see what a mutant changed, never a glance at
the code around it.

### 4. A line no test executes

An uncovered mutant (`status: "no_coverage"`) was skipped because no test runs its line at all,
which is a stronger finding than a survivor: nothing exercises that code. Find what the line is
before judging it. It may be a clause or default argument no caller uses yet (`Plot.new/1`, the
clause a default argument generates, was one), which wants an example or a test; or code nothing
can reach, which is a finding on the code.

## Not a finding

- **Invalid mutants** (they did not compile) need nothing.
- **Message wording.** Literal and argument-order mutants inside an error or log string, when the
  tests assert the message's datum: `elixir-code-review`'s `test-quality.md` pins the datum, not
  the sentence, so these survive by design, and in a module with careful messages they are most of
  the survivors. A mutant that drops a datum the tests assert is killed; one that drops a datum the
  message states only once and no test asserts is judged as a behavior no test pins. **Only
  messages:** a string the code produces as its output — an SVG element or attribute, a label, a
  class name — is behavior, and a literal mutant surviving there is a finding. No mutator's
  survivors are set aside as a kind; each one is judged where it landed.
- **A deletion the gate catches instead of the tests.** muex compiles mutants without
  `--warnings-as-errors`, so deleting an `alias` the module still uses survives as warnings that
  `mix quality` would fail. Deleting a `use Boundary` declaration survives too; the waiver gate
  denies that edit (design-log §4).
- **The score.** Equivalent mutants count against it, so it measures noise as well as holes; the
  survivor list is the signal. muex also exits non-zero when the score falls below its default
  `--fail-at` of 80; that exit status is not a failure of the pass.

## What it cannot tell you

muex stops at the first failing test, so it shows that some test catches each mutant — not that
each test catches something no other does. Duplication stays the judgment in
`elixir-code-review`'s `test-quality.md`. And it mutates only the lines the commit changed, so a
test the commit deleted or weakened that was the only pin on an unchanged line goes unseen; that
is the review's question about every deleted test, asked before the commit.

## After the triage

1. **Write the fixes:** a test for each behavior no test pins and each line no test executes, each
   new test proven against its mutant as above; a change to the code for what is unreachable or
   redundant. A fix that needs the user's decision under the usual rules (a boundary widening, a
   change of behavior) goes to them first.
2. **Run the gates over the fixes**, which are a change like any other: `mix quality`, then
   `elixir-code-review` when they touch `test/`, then `docs-sync`, each recording its mark.
3. **Record the pass for the commit gate**, once every survivor is triaged — when there were
   none, too:

   ```bash
   bash .claude/hooks/commit-gate.sh mark mutation
   ```

   It marks `HEAD`, the commit this pass ran over. The commit gate denies every commit while the
   last commit changed code and has no mark, so the fixes cannot be committed before it. This
   step is the **only** sanctioned way to produce the mark: running it without having triaged the
   run is falsifying the record, not passing the gate.
4. **Report**, below. The fixes stay uncommitted until the user says to commit: what muex found
   that changed something is what they decide on. Once committed, a fix that changed `lib/` lines
   gets a pass of its own, like any commit.

## Report

In plain words: what each number counts, and for each change, the mutant that prompted it and
what now catches it. When nothing survived, one line says so. Message-wording survivors are
grouped, one line per message.

```markdown
## Mutation pass: <short sha> <subject>
<n> mutants on the <m> changed lines of <files>; <k> survived, <u> on lines no test runs.

### What it found that changed something
- `lib/my_lib/parser.ex:31` guard → `true` survived: no test pinned the refusal of an empty
  name. Added "refuses an empty name" to `test/my_lib/parser_test.exs`; it fails with the
  mutant applied.

### Survivors left as they are
- `lib/my_lib/parser.ex:48` map keys reordered — equivalent: key order means nothing
- `lib/my_lib/parser.ex:52` error message wording (4 mutants) — the tests assert the column name
```
