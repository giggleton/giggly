defmodule Giggly.Facet do
  @moduledoc """
  Which panel each row of a plot's data is drawn in.

  The facet runs first in the assembly, against the plot's data as it was read, before any
  layer's mapping is evaluated: a facet splits on the data's own columns, which evaluation
  discards. It writes a `:panel` column of integer panel ids, which every later stage reads to
  work panel by panel; the stages never see the facet itself.

  There is one facet so far, ggplot2's null facet: a single panel, so every row is in panel 1.
  Faceting by a variable (`facet_wrap`) arrives as a second kind of facet.
  """

  # The facet reads and writes the plot's data frame and nothing else.
  use Boundary, deps: [Giggly.DataFrame], exports: []

  alias Giggly.DataFrame

  # The null facet's one panel.
  @only_panel 1

  @doc """
  The frame with a `:panel` column giving each row's panel: ggplot2's `map_data()`. With one
  panel, every row is in panel 1.
  """
  @spec assign_panels(DataFrame.t()) :: DataFrame.t()
  def assign_panels(frame) do
    panels = List.duplicate(@only_panel, DataFrame.row_count(frame))
    DataFrame.put(frame, :panel, panels)
  end
end
