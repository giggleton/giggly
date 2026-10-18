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
  and Kino all read as a table. A column takes R's type: integers where R stores integers, floats
  where it stores doubles, names strings and dates `Date`s (`diamonds`' `table`, `economics`'
  `unemploy` and every `mtcars` column but its names are whole but doubles), so a bar's width,
  which R's `resolution()` takes from a column's type, is R's, and a whole double is written `4`
  wherever a value is written as text (`Giggly.AsCharacter`).
  R's row names become a first column, and a factor its labels, in no order until level order
  exists.
- **The file is read once, at compile time** (`@external_resource` and `File.read!/1`), so asking
  for a dataset does no IO. The file's header gives the column order; the module holds only how
  each column is read.
- **A dataset too big to hold as columns is kept compressed** (`:erlang.term_to_binary/2` at level
  9) and decoded each time it is asked for, still with no IO: `diamonds` as columns would be some
  18 MB held wherever the module is loaded, and a release loads every module at boot, where
  compressed it is half a megabyte decoded in a few tens of milliseconds. The small ones stay
  columns; whether they join it is open (design-log §4, the entry beginning "ggplot2's
  `diamonds` is shipped whole").
- **Each dataset's file has a read and a `CorePurity` waiver of its own**, worded as
  `Giggly.Font`'s, so adding a dataset adds a waiver, which stops and asks (design-log §4, the
  entry beginning "Each dataset's file is read behind a waiver of its own"). Only the parsing is
  shared.
- **A dataset is public API with no caller in Giggly**, and its boundary lists nothing. Each
  arrives with the first notebook example that draws it.
