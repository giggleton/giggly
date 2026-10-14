defmodule Giggly.Facet do
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
  # A plot records its facet by name, and the facet is resolved here; each facet is a module
  # implementing this behaviour. There is one so far, ggplot2's null facet (`Giggly.Facet.Null`):
  # a single panel, so every row is in panel 1, at row 1 and column 1, on scale 1 of each axis.
  # Faceting by a variable (`facet_wrap`) arrives as a second.

  # The facet reads and writes the plot's data frame and nothing else.
  use Boundary, deps: [Giggly.DataFrame], exports: []

  alias Giggly.{DataFrame, Facet}

  @typedoc "A facet's name, as a plot records it."
  @type name :: :null

  # The layout table: one row per panel, as `layout/1` describes.
  @doc false
  @callback layout() :: DataFrame.t()

  # The frame with each row's `:panel`, as `assign_panels/2` describes.
  @doc false
  @callback assign_panels(DataFrame.t()) :: DataFrame.t()

  # The layout table of the facet named `name`: one row per panel, with its `:panel` id, the `:row`
  # and `:column` it is rendered at, and the `:scale_x` and `:scale_y` ids of the scales it uses,
  # as ggplot2's layout has `PANEL`, `ROW`, `COL`, `SCALE_X` and `SCALE_Y`.
  @doc false
  @spec layout(name()) :: DataFrame.t()
  def layout(:null), do: Facet.Null.layout()

  # The frame with a `:panel` column giving each row's panel under the facet named `name`:
  # ggplot2's `map_data()`.
  @doc false
  @spec assign_panels(DataFrame.t(), name()) :: DataFrame.t()
  def assign_panels(frame, :null), do: Facet.Null.assign_panels(frame)
end
