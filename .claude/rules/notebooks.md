---
paths:
  - "notebooks/**"
---

# Notebooks

`notebooks/` holds Livebook notebooks that follow ggplot2's reference pages, one notebook per
page, named after the page, and `index.livemd`, which follows ggplot2's reference index. Why they
are documentation first, show no ggplot2 drawings and cover every example: design-log §4, the
entry beginning "The notebooks follow ggplot2's reference pages"; why every page and the index:
the entry beginning "Every page of ggplot2's function reference has a notebook".

## Rules

- **A notebook follows its ggplot2 reference page: every example, in the page's order**, each
  with ggplot2's code first, verbatim: every line of the page's examples, comments included,
  appears once across the notebook's R blocks. One Giggly can draw is drawn with Giggly's code;
  one it cannot keeps its ggplot2 code and names what it waits for, so the notebook is also the
  page's list of what remains. Drawn means the same plot built with Giggly's own counterparts of
  the example's functions, checked against R; a plot Giggly could only imitate (`qplot()`, a
  computed column standing in for `cut_width(carat, 0.25)`) waits. An argument ggplot2 does not
  recognise, and so draws as its default (`hjust = 'outside'`, centred), is left out of Giggly's
  cell, and the prose says so (design-log §4, the entry beginning "A notebook leaves out an
  argument").
- **"Not in Giggly yet:" names each missing piece by its ggplot2 function or argument, in the same
  words in every notebook** ("mapping `shape`", "a fixed `size`", "`geom_boxplot()`", "a
  whole-column function in a mapping", "a point's `fill`"), so when a feature lands, searching the
  notebooks for its name finds every example waiting for it, and those are drawn; a verdict still
  waiting drops the pieces that landed and keeps the rest (design-log §4, the entry beginning "A
  verdict names a missing expression"). **An About sentence says what Giggly has and
  names what it lacks by that name** ("maps no `shape`", "no binned scales"), never "no X but
  <what exists>", which a search for the next feature cannot find.
- **An expression is written as a capture wherever one function computes it**
  (`{&:math.log10/1, [:carat]}`), so its guide is titled by the call; a closure only beside
  `labs/2`, which titles it. The prose says where the title differs from R's (`:math.log10(carat)`
  for `log10(carat)`, `unemploy / pop` for `unemploy/pop`), as the drawing otherwise matches.
- **A colour is written as Giggly takes it**: a ggplot2 example's colour name keeps its name with
  CSS's meaning, and the prose notes where the drawing differs from R's (CSS's `"green"` is
  `#008000`, R's `#00FF00`); a name only R has is written as its hex, naming R's colour (`"grey50"`
  as `"#7F7F7F"`).
- **`index.livemd` follows ggplot2's reference index**: its sections, their descriptions and its
  entries in its order, each entry a relative link to its page's notebook. It installs nothing.
  A notebook for a new page arrives with its line there.
- **Documentation first: no ggplot2 drawings beside Giggly's.** Checking a drawing against
  ggplot2 is review's job (`test/golden/point.R`), not the notebook's.
- **Data comes from `Giggly.Datasets`**, the same table the ggplot2 example uses; a small table
  the example writes out in R, the cell writes out too. Where an example draws random numbers in
  R, the notebook takes the rows R actually produced and says so.
- **A notebook installs Giggly by path** (`Path.join(__DIR__, "..")`) and Kino, and shows a plot
  with `Kino.Image.new(svg, :svg)`, through the setup cell's `render`, until a plot can show
  itself. A `livebook` escript built with an older Elixir than `mix.exs` requires cannot run
  them; reinstall it under `.tool-versions`.
- **The setup cell aliases `Giggly.Plot`, binds each dataset the notebook uses to R's name for
  it** (`mpg = Giggly.Datasets.mpg()`), **and defines `render`**, a function that draws a plot
  with `Giggly.to_svg/2` and shows it with `Kino.Image`. So the cells read
  `Plot.new(mpg, %{x: :class})` as ggplot2's read `ggplot(mpg, aes(class))`, and each drawing
  ends `|> render.()`; the prose keeps full module names. A notebook that draws nothing yet
  keeps only `Mix.install`, since Livebook warns about an unused alias.
- **Reviewing a notebook is the user's job, not a gate.** Nothing runs the notebooks: not the
  suite, not review, not docs-sync, and no change waits on one.
