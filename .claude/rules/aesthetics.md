---
paths:
  - "lib/giggly/aesthetics.ex"
  - "test/giggly/aesthetics_test.exs"
---

# The aesthetic vocabulary

`Giggly.Aesthetics` decides how aesthetic names are spelled and which of them are x or y positions.
Why it is shaped this way, and what was rejected: design-log §4, the entry beginning "Aesthetics are
atoms with ggplot2's names".

## Rules

- **One spelling past the public API.** `canonicalize/1` runs where a mapping or fixed options
  enter, and nothing after that point matches on an alias. A new alias is an entry in the alias
  table — never a substring rule, which in Elixir would mean creating atoms from caller input.
- **Two keys naming one aesthetic raise.** Either value winning silently is a plot the caller did
  not write.
- **Spelling only, not membership.** An unknown name passes through `canonical/1` unchanged; which
  aesthetics a layer accepts is declared by its geom, stat and position, and checked there.
- **The vocabulary depends on nothing.** Its boundary lists no `deps:`, so nothing it could call
  can change what a name means; every domain that needs a name's family lists it instead.
- **`panel` is not an aesthetic and must not become one** — the pipeline reserves it for the panel
  id column.
- **Anything that treats x and y differently asks `family/1`**, never `name == :x`. That is the
  difference between `:xmin` and `:xend` training the x scale and silently not, which is how ggity
  annotations failed to widen the axis.

## How it works

The families are derived at compile time from one list of x/y pairs; `family/1` matches them in
guards, and `counterpart/1` reads a map built from the pairs in both directions. `canonicalize/1` folds over
the pairs once, recording which name first claimed each canonical aesthetic so a collision can name
both spellings.
