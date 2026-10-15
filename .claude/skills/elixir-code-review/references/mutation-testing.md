# Mutation testing

**Applies to:** `lib/**/*.ex` the change touches, and the module under test of any changed
`test/**/*_test.exs`.

muex breaks the code one small edit at a time (a guard replaced with `true`, `==` with `!=`, a
clause deleted) and reruns the tests against each mutant. A mutant that survives is a behavior no
test pins — found from the code, not from the tests already written, which is the hole a
hand-picked mutant misses.

## Running it

The files are the `lib/` ones in scope: the command under the skill's Scope, piped through
`grep '^lib/.*\.ex$' | paste -sd, -`, which joins them into the one comma-separated value
`--files` takes. When only a test file changed, the file to mutate is its module under test.

```bash
mix muex --no-optimize --no-filter --verbose --coverage-guided \
  --format json --output <scratchpad>/muex.json \
  --files lib/giggly/one.ex,lib/giggly/two.ex
```

Every flag there carries weight:
- **`--no-optimize`** — the default optimizer discards most mutants, so a bare `mix muex` can
  report a perfect score over a handful of them: a confident false pass.
- **`--no-filter`** — the default filter skips modules it takes for framework code, including any
  declaring several `@callback`s, which a behaviour module with real logic beside its callbacks
  does.
- **One `--files`, comma-separated** — given `--files` twice, muex keeps only the last, so naming
  each file in a flag of its own silently mutates only the last one. It splits the value on
  commas, which is also why a brace glob (`lib/{a,b}.ex`) crashes its loader. Not `--since`: it
  diffs `<ref>...HEAD`, so it sees committed work only.
- **`--verbose`** — prints `Found <n> file(s)` before any mutant runs. Check that it counts every
  file you named: a file that never loads is never mutated, and the summary line does not say so.
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

**A repo-local credo check** (`.credo/checks/`) is run with `--mirror .credo` and **without**
`--coverage-guided`: muex writes a mutant only into a directory the sandbox mirrors, and refuses
to write through the symlink otherwise; and `:cover` cannot see a module the test loads with
`Code.require_file`, so every mutant would be reported uncovered. muex then picks the test file by
the module's name, which `test/credo_checks_test.exs` gives through a single `alias`.

It takes minutes, not seconds — one sandboxed `mix test` per mutant — which is why it runs on the
changed files and is not a `mix quality` step.

## Findings

The output to act on is the **survivors** and the **uncovered mutants**, not the score. Each
survivor is one of three things, and the report says which; each uncovered mutant is a fourth.

### 1. A behavior no test pins — report under test quality

A test-quality finding, and the High "coverage hole on a documented contract" when a `@doc`
promises the behavior. The fix is a test naming the bug the mutant introduced — a doctest only
on an API function. Prove the new test by applying the survivor's `patch` by hand to a copy and
watching the test fail, then restore it; a test that passes with the mutant applied has not
closed the hole.

### 2. Code the mutant shows is unreachable or redundant — Low

Such as a guard its only caller already enforces — a finding on the code, not a missing test.

### 3. Equivalent — not a finding, but named

The mutant cannot change behavior: map keys reordered, `Map.put` → `Map.put_new` where a guard
already excludes the key, a type guard whose removal only changes which exception a programmer
error raises, a range of one row or column with its ends swapped (`3..3`), dropping a stage that
runs an identity (the identity stat or position). muex never mutates documentation or typespec
attributes, so a survivor that seems to delete a `@moduledoc` is a neighbouring statement. Named with the reason, so the call can be checked; a survivor is never dismissed
silently. Diff the `patch`'s `before` and `after` to see what a mutant changed, never a glance at
the code around it.

### 4. A line no test executes — report under test quality

An uncovered mutant (`status: "no_coverage"`) was skipped because no test runs its line at all,
which is a stronger finding than a survivor: nothing exercises that code. Find what the line is
before judging it. It may be a clause or default argument no caller uses yet (`Plot.new/1`, the
clause a default argument generates, was one), which wants an example or a test; or code nothing
can reach, which is a finding on the code (Low).

## Not a finding

- **Invalid mutants** (they did not compile) need nothing.
- **Message wording.** Literal and argument-order mutants inside an error or log string, when the
  tests assert the message's datum: `test-quality.md` pins the datum, not the sentence, so these
  survive by design, and in a module with careful messages they are most of the survivors. A
  mutant that drops a datum the tests assert is killed; one that drops a datum the message states
  only once and no test asserts is judged as a behavior no test pins. **Only messages:** a string
  the code produces as its output — an SVG element or attribute, a label, a class name — is
  behavior, and a literal mutant surviving there is a finding. No mutator's survivors are set aside
  as a kind; each one is judged where it landed.
- **A deletion the gate catches instead of the tests.** muex compiles mutants without
  `--warnings-as-errors`, so deleting an `alias` the module still uses survives as warnings that
  `mix quality` would fail. Deleting a `use Boundary` declaration survives too; the waiver gate
  denies that edit (design-log §4).
- **The score.** Equivalent mutants count against it, so it measures noise as well as holes; the
  survivor list is the signal. muex also exits non-zero when the score falls below its default
  `--fail-at` of 80; that exit status is not a failure of the review.

## What it cannot tell you

muex stops at the first failing test, so it shows that some test catches each mutant — not that
each test catches something no other does. Duplication stays the judgment in `test-quality.md`.

## Overlap

A survivor that is a missing test is reported **once**, under test quality, where its fix (a test)
applies; this file contributes only its line in the survivors section.

## Report

The report ends with the survivors and the uncovered mutants, each with what it is (a finding
above, or equivalent and why); when there are none, one line says so. Message-wording survivors
are grouped, one line per message.

```markdown
### Mutation survivors (<n> of <total> mutants)
- `lib/my_lib/parser.ex:31` guard → `true` — finding above (High: no test pins the refusal)
- `lib/my_lib/parser.ex:48` map keys reordered — equivalent: key order means nothing
- `lib/my_lib/parser.ex:60` no coverage — finding above (no test runs the `parse/1` clause)
```
