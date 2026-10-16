---
paths:
  - "notebooks/**"
---

# Notebooks

`notebooks/` holds Livebook notebooks that follow ggplot2's reference pages, one notebook per
page. Why they are documentation first, show no ggplot2 drawings and cover every example:
design-log §4, the entry beginning "The notebooks follow ggplot2's reference pages".

## Rules

- **A notebook follows its ggplot2 reference page: every example, in the page's order**, each
  with ggplot2's code first. One Giggly can draw is drawn with Giggly's code; one it cannot keeps
  its ggplot2 code and names what it waits for, so the notebook is also the page's list of what
  remains. When a feature lands, the examples waiting for it are drawn.
- **Documentation first: no ggplot2 drawings beside Giggly's.** Checking a drawing against
  ggplot2 is review's job (`test/golden/point.R`), not the notebook's.
- **Data comes from `Giggly.Datasets`**, the same table the ggplot2 example uses; a small table
  the example writes out in R, the cell writes out too. Where an example draws random numbers in
  R, the notebook takes the rows R actually produced and says so.
- **A notebook installs Giggly by path** (`Path.join(__DIR__, "..")`) and Kino, and shows a plot
  with `Kino.Image.new(svg, :svg)` until a plot can show itself. A `livebook` escript built with an
  older Elixir than `mix.exs` requires cannot run them; reinstall it under `.tool-versions`.
- **The setup cell aliases `Giggly.Datasets` and `Giggly.Plot`**, so the cells read
  `Plot.facet_wrap(plot, :class)`, as a user's code would; the prose keeps full module names.
- **Reviewing a notebook is the user's job, not a gate.** Nothing runs the notebooks: not the
  suite, not review, not docs-sync, and no change waits on one.
