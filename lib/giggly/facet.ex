defprotocol Giggly.Facet do
  @moduledoc false

  # Which panel each row of a plot's data is drawn in, and where each panel sits.
  #
  # The facet runs first in the assembly, against the plot's data as it was read, before any
  # layer's mapping is evaluated: a facet splits on the data's own columns, which evaluation
  # discards. It writes a `:panel` column of integer panel ids, which every later stage reads to
  # work panel by panel; the stages never see the facet itself.
  #
  # The facet also lays the panels out, in a layout table with one row per panel. Its `:row` and
  # `:column` say where the panel sits among the others when the plot is rendered; its `:scale_x`
  # and `:scale_y` say which x and y scale it uses, so that panels sharing an axis share a scale and
  # free scales are only more of them. The stages read nothing else about panels.
  #
  # A plot records its facet as a struct of its kind, and the assembly runs it here. Each facet is
  # one module holding everything about it: its struct, whose fields are the facet's parameters,
  # and its computing, in a `defimpl Giggly.Facet` whose first line classifies it into this
  # boundary, since boundary checks nothing a protocol implementation calls until it is classified.
  # There are two: ggplot2's null facet (`Giggly.Facet.Null`), a single panel, so every row is in
  # panel 1, at row 1 and column 1, on scale 1 of each axis; and `facet_wrap`
  # (`Giggly.Facet.Wrap`), a panel for each combination of some columns' values, laid out in rows.
  #
  # A facet that orders its panels by values orders them as a discrete scale orders its levels,
  # by the key the assembly hands it, so panels and axes agree while this namespace names nothing
  # about scales.

  # The facet reads and writes the plot's data frame and nothing else.
  # It exports its kinds, whose structs a plot records, and nothing they compute with: that is in
  # their protocol implementations, which no boundary exports.
  use Boundary, deps: [Giggly.DataFrame], exports: [Null, Wrap]

  alias Giggly.DataFrame

  # The layout table of `facet` over the plot's data `frame`: one row per panel, with its `:panel`
  # id, the `:row` and `:column` it is rendered at, any columns the facet splits on, by the names
  # the data gives them, and the `:scale_x` and `:scale_y` ids of the scales it uses, as ggplot2's
  # layout has `PANEL`, `ROW`, `COL`, the facet's variables, `SCALE_X` and `SCALE_Y`: ggplot2's
  # `compute_layout()`. `order_key` orders values as a discrete scale orders its levels.
  @doc false
  @spec layout(t(), DataFrame.t(), (term() -> term())) :: DataFrame.t()
  def layout(facet, frame, order_key)

  # The frame with a `:panel` column giving each row's panel under `facet`, by the `layout` it
  # built from that frame: ggplot2's `map_data()`.
  @doc false
  @spec assign_panels(t(), DataFrame.t(), DataFrame.t()) :: DataFrame.t()
  def assign_panels(facet, frame, layout)
end
