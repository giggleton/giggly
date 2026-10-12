# Mutation testing

**Applies to:** `lib/**/*.ex` the change touches, and the module under test of any changed
`test/**/*_test.exs`.

muex breaks the code one small edit at a time (a guard replaced with `true`, `==` with `!=`, a
clause deleted) and reruns the tests against each mutant. A mutant that survives is a behavior no
test pins — found from the code, not from the tests already written, which is the hole a
hand-picked mutant misses.

## Running it

The files are the `lib/` ones in scope: the command under the skill's Scope, piped through
`grep '^lib/.*\.ex$'`. When only a test file changed, the file to mutate is its module under
test.

```bash
mix muex --no-optimize --no-filter --files lib/giggly/one.ex --files lib/giggly/two.ex
```

Every flag there carries weight:
- **`--no-optimize`** — the default optimizer discards most mutants, so a bare `mix muex` can
  report a perfect score over a handful of them: a confident false pass.
- **`--no-filter`** — the default filter skips modules it takes for framework code, including any
  declaring several `@callback`s, which a behaviour module with real logic beside its callbacks
  does.
- **One `--files` per file** — a brace glob (`lib/{a,b}.ex`) crashes muex's loader. Not
  `--since`: it diffs `<ref>...HEAD`, so it sees committed work only.

It takes minutes, not seconds — one sandboxed `mix test` per mutant — which is why it runs on the
changed files and is not a `mix quality` step.

## Findings

The output to act on is the **survivors**, not the score. Each one is one of three things, and the
report says which.

### 1. A behavior no test pins — report under test quality

A test-quality finding, and the High "coverage hole on a documented contract" when a `@doc`
promises the behavior. The fix is a test or doctest naming the bug the mutant introduced.

### 2. Code the mutant shows is unreachable or redundant — Low

Such as a guard its only caller already enforces — a finding on the code, not a missing test.

### 3. Equivalent — not a finding, but named

The mutant cannot change behavior: map keys reordered, a `@moduledoc` deleted, `Map.put` →
`Map.put_new` where a guard already excludes the key, a type guard whose removal only changes
which exception a programmer error raises. Named with the reason, so the call can be checked; a
survivor is never dismissed silently.

## Not a finding

- **Invalid mutants** (they did not compile) need nothing.
- **The score.** Equivalent mutants count against it, so it measures noise as well as holes; the
  survivor list is the signal.

## What it cannot tell you

muex stops at the first failing test, so it shows that some test catches each mutant — not that
each test catches something no other does. Duplication stays the judgment in `test-quality.md`.

## Overlap

A survivor that is a missing test is reported **once**, under test quality, where its fix (a test)
applies; this file contributes only its line in the survivors section.

## Report

The report ends with the survivors, each with what it is (a finding above, or equivalent and why);
when none survived, one line says so.

```markdown
### Mutation survivors (<n> of <total> mutants)
- `lib/my_lib/parser.ex:31` guard → `true` — finding above (High: no test pins the refusal)
- `lib/my_lib/parser.ex:48` map keys reordered — equivalent: key order means nothing
```
