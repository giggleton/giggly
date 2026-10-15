---
paths:
  - "lib/giggly/datasets.ex"
  - "priv/datasets/**"
---

# Datasets

`Giggly.Datasets` gives the tables R and ggplot2 ship, for the notebooks' examples and for users'
own plots. Why a module rather than files beside the notebooks, and why its data is a file read
at compile time: design-log §4, the entry beginning "The notebooks follow ggplot2's reference
pages".

## Rules

- **A dataset is R's own data, copied, never recomputed.** Its file in `priv/datasets/` is what R
  writes (`write.csv()`), with a header saying where it came from, which R wrote it and how to
  regenerate it; a value that differs from R's is a bug in the copy.
- **A dataset is a keyword list of columns, in the dataset's order**, which `Plot.new/2`, Explorer
  and Kino all read as a table. Whole numbers are integers, measurements floats, names strings;
  R's row names become a first column.
- **The file is read once, at compile time** (`@external_resource` and `File.read!/1`), so asking
  for a dataset does no IO. The file's header gives the column order; the module holds only how
  each column is read.
- **Each dataset's file has a read and a `CorePurity` waiver of its own**, worded as
  `Giggly.Font`'s, so adding a dataset adds a waiver, which stops and asks (design-log §4, the
  entry beginning "Each dataset's file is read behind a waiver of its own"). Only the parsing is
  shared.
- **A dataset is public API with no caller in Giggly**, and its boundary lists nothing. Each
  arrives with the first notebook example that draws it.

## How it works

`mtcars/0` and `mpg/0` each return a dataset from a module attribute built when Giggly
compiles: for each file read, its lines, less its `#` comments, split on commas and turned into
columns, each named by its header (an existing atom, from the dataset's table of column types)
and read as a string, an integer or a float.
