defmodule Giggly do
  @moduledoc """
  Giggly is a grammar-of-graphics plotting library for Elixir, modelled on ggplot2.

  A plot is described with `Giggly.Plot`, which builds a value and runs nothing, and the functions
  here take a finished plot and run it, as ggplot2's `ggsave()` and `get_layer_data()` take a
  finished ggplot. `layer_data/2` shows the table a layer computes; drawing to SVG will be one of
  these functions too.
  """

  # The umbrella: the run functions here, with the description (`Plot`) and every internal domain
  # a sub-boundary beneath it. Like every boundary it is strict (`mix.exs`). It lists
  # `Giggly.DataFrame`, which owns an outside library and so sits at the top level, because a
  # sub-boundary may only list what its parent does; the functions here do not call it. It exports
  # `Plot`, which with this module is what a user of Giggly calls.
  use Boundary, deps: [Giggly.DataFrame], exports: [Plot]

  alias Giggly.{Assembly, DataFrame, Plot}

  @doc """
  The table the layer at `index` computes, counting from 0 in the order the layers were added; the
  first layer when no index is given. It is ggplot2's `get_layer_data()`.

  Its columns are named by aesthetic, plus the `:panel` each row is drawn in (`Giggly.Facet`) and
  its `:group` (`Giggly.Group`); the data's own column names do not appear. Raises `ArgumentError` when the plot has no layer at `index`; a
  negative index is refused too, not counted from the end.

      iex> plot =
      ...>   %{"cyl" => ["6", "4", "6"], "mpg" => [21.0, 22.8, 21.4]}
      ...>   |> Giggly.Plot.new(%{x: :cyl, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.names(frame)
      [:x, :y, :panel, :group]
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
      plot
      |> Assembly.run()
      |> Enum.at(index)
    else
      raise ArgumentError,
            "the plot has #{layer_count} layer(s), counted from 0, so it has no layer #{index}"
    end
  end
end
