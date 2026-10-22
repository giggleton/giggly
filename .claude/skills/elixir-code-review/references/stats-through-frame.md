# Stats compute through the frame

**Applies to:** `lib/giggly/stat/**/*.ex`

Review only the code the change adds or alters in a stat's computing (its `defimpl Giggly.Stat`).

## The rule

A stat never pulls a column of its input, only of a table it has already summarised
(`.claude/rules/stat.md`; design-log §4, the entry beginning "A stat computes only through frame
operations"). The work that scales with a layer's rows runs through the frame's operations, so an
engine holding the table could run it and nothing of the table crosses into Elixir. No credo
check enforces this, since a pull of the input and a pull of a summarised table look alike to
one; this review is the only thing that does.

## What is a finding

Follow each frame a pull reads back to where it came from. A row-keeping operation (`filter/2`,
`mutate/2`, `select/2`, `slice/2`, `split/2`, `put/3`) keeps a table the input's size, so its
result is still the input:

- `DataFrame.pull/2` of the frame `compute_layer/2` was handed, or of one made from it by
  row-keeping operations, including through a helper that takes the frame as an argument;
- a list as long as the input built in Elixir and put back (`List.duplicate(1.0,
  DataFrame.row_count(frame))`), where `mutate/2` with a constant does it;
- rows chosen by indices worked out from a pulled column and `slice/2`, where `filter/2` does it;
- a whole-column computation on a pulled input column (`Resolution.of/2`, a sort, a group-by in
  `Enum`) that the summarised table can answer, as counting's width reads its counted table's x.

Severity: **Medium**. It is contained in one stat, and the output is still right, but it moves the
work an engine should do into Elixir and is copied by the next stat written beside it.

## What is not a finding

- A pull of a table `summarise/3` returned, or of one made from it: its rows are groups, small by
  construction, so shares, densities, fences and widths may be worked out on its lists and put
  back.
- `names/1`, `dtypes/1` and `row_count/1` of the input: what a table is, not its values.
- A table built with `new/1` from numbers the stat worked out (a break table from two limits).
- A frame operation the vocabulary lacks: a stat that needs one raises it as a question, since an
  operation arrives with its first caller (`.claude/rules/data_frame.md`); the finding, if any, is
  the workaround, not the missing operation.
