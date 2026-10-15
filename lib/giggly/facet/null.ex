defmodule Giggly.Facet.Null do
  @moduledoc false

  # The null facet, ggplot2's `facet_null()`: one panel, which every row is drawn in, with an axis
  # below it and to its left and no strip. It takes no parameters. Run it through `Giggly.Facet`.

  defstruct []

  @type t :: %__MODULE__{}

  defimpl Giggly.Facet, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Facet

    alias Giggly.DataFrame

    # The one panel, where it sits, and the one scale of each axis it uses.
    @only_panel 1
    @only_row 1
    @only_column 1
    @only_scale 1

    @impl Giggly.Facet
    def layout(_facet, _frame, _order_key) do
      DataFrame.new(
        panel: [@only_panel],
        row: [@only_row],
        column: [@only_column],
        scale_x: [@only_scale],
        scale_y: [@only_scale],
        axis_bottom: [true],
        axis_left: [true],
        strip: [[]]
      )
    end

    @impl Giggly.Facet
    def assign_panels(_facet, frame, _layout) do
      panels = List.duplicate(@only_panel, DataFrame.row_count(frame))
      DataFrame.put(frame, :panel, panels)
    end
  end
end
