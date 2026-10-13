defmodule Giggly do
  @moduledoc """
  Giggly is a grammar-of-graphics plotting library for Elixir, modelled on ggplot2.

  A plot is described with `Giggly.Plot`, which builds a value and runs nothing, and the functions
  here take a finished plot and run it, as ggplot2's `ggsave()` and `get_layer_data()` take a
  finished ggplot. `layer_data/2` shows the table a layer computes, `panel_scales/2` the scales
  a panel is drawn on, and `to_svg/1` draws the plot.
  """

  # The umbrella: the run functions here, with the description (`Plot`) and every internal domain
  # a sub-boundary beneath it. Like every boundary it is strict (`mix.exs`). It lists
  # `Giggly.DataFrame`, which owns an outside library and so sits at the top level: a sub-boundary
  # may only list what its parent does, and `panel_scales/2` reads the layout table. It exports
  # `Plot`, which with this module is what a user of Giggly calls.
  use Boundary, deps: [Giggly.DataFrame], exports: [Plot]

  alias Giggly.{Assembly, DataFrame, Plot, Render, SVG}

  # The size every plot is drawn at until a size can be given: 10 by 8 inches, in points, the size
  # of the SVG ggplot2's own visual tests snapshot (vdiffr's default).
  @width 720
  @height 576

  @doc """
  The table the layer at `index` computes, counting from 0 in the order the layers were added; the
  first layer when no index is given. It is ggplot2's `get_layer_data()`.

  Its columns are named by aesthetic, plus the `:panel` each row is drawn in (`Giggly.Facet`) and
  its `:group` (`Giggly.Group`); the data's own column names do not appear. Its x and y columns
  hold positions on the panel's scales: a discrete value is its level's position, counting from
  1, as in ggplot2. Raises `ArgumentError` when the plot has no layer at `index`; a
  negative index is refused too, not counted from the end.

      iex> plot =
      ...>   %{"cyl" => ["6", "4", "6"], "mpg" => [21.0, 22.8, 21.4]}
      ...>   |> Giggly.Plot.new(%{x: :cyl, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.names(frame)
      [:x, :y, :panel, :group]
      iex> Giggly.DataFrame.pull(frame, :x)
      [2, 1, 2]
      iex> Giggly.DataFrame.pull(frame, :panel)
      [1, 1, 1]
      iex> Giggly.DataFrame.pull(frame, :group)
      [2, 1, 2]
  """
  @spec layer_data(Plot.t(), integer()) :: DataFrame.t()
  def layer_data(%Plot{reversed_layers: reversed_layers} = plot, index \\ 0)
      when is_integer(index) do
    layer_count = length(reversed_layers)

    if index >= 0 and index < layer_count do
      %Assembly{layer_data: layer_data} = Assembly.run(plot)
      Enum.at(layer_data, index)
    else
      raise ArgumentError,
            "the plot has #{layer_count} layer(s), counted from 0, so it has no layer #{index}"
    end
  end

  @doc """
  The trained x and y scales of the panel with id `panel`, the first panel when no id is given. It
  is ggplot2's `get_panel_scales()`, which finds a panel by its row and column; here a panel is
  found by its id, counting from 1 as panel ids do. Raises `ArgumentError` when the plot has no
  such panel.

      iex> plot =
      ...>   %{"cyl" => ["6", "4", "6"], "mpg" => [21.0, 22.8, 21.4]}
      ...>   |> Giggly.Plot.new(%{x: :cyl, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      iex> Giggly.panel_scales(plot)
      %{
        x: %Giggly.Scale.Discrete{levels: ["4", "6"]},
        y: %Giggly.Scale.Continuous{range: {21.0, 22.8}, transform: :identity}
      }
  """
  @spec panel_scales(Plot.t(), integer()) :: %{x: Giggly.Scale.t(), y: Giggly.Scale.t()}
  def panel_scales(%Plot{} = plot, panel \\ 1) when is_integer(panel) do
    %Assembly{layout: layout, x_scales: x_scales, y_scales: y_scales} = Assembly.run(plot)
    panels = DataFrame.pull(layout, :panel)
    scale_x_ids = DataFrame.pull(layout, :scale_x)
    scale_y_ids = DataFrame.pull(layout, :scale_y)

    rows = Enum.zip([panels, scale_x_ids, scale_y_ids])

    case List.keyfind(rows, panel, 0) do
      {^panel, scale_x_id, scale_y_id} ->
        %{x: Map.fetch!(x_scales, scale_x_id), y: Map.fetch!(y_scales, scale_y_id)}

      nil ->
        raise ArgumentError,
              "the plot has panel(s) #{Enum.join(panels, ", ")}, so it has no panel #{panel}"
    end
  end

  @doc """
  The plot drawn as an SVG document, 720 by 576 points (10 by 8 inches), the size of the SVG
  ggplot2's own visual tests snapshot. It is ggplot2's `ggsave()` to an SVG file, returned as
  iodata rather than written.

  Today a plot is drawn as its panel and its axes in its theme's look: each layer's marks, placed
  by the coordinate system in the panel over its background and grid lines, with the x axis below
  it and the y axis to its left, each a tick and a label at every break and titled by the column
  it shows, inside the theme's plot margin, on the theme's plot background. The plot's title
  arrives in turn.
  """
  @spec to_svg(Plot.t()) :: iodata()
  def to_svg(%Plot{} = plot) do
    plot
    |> Assembly.run()
    |> Render.scene()
    |> SVG.draw(@width, @height)
  end
end
