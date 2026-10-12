defmodule Giggly.Assembly do
  @moduledoc """
  The assembly of a plot: the fixed sequence of stages that turns a `Giggly.Plot`, a description,
  into what is drawn. The name is the middle of Wilkinson's three stages of making a graphic
  (specification, assembly, display); a plot is the specification, and drawing is the display.

  The stages run in one fixed order, each adjacent pair a semantic chosen on purpose, and they
  arrive one at a time. Today the assembly assigns each row of the plot's data its panel
  (`Giggly.Facet.assign_panels/1`), evaluates each layer's mapping against that data, and adds the
  `:group` column (`Giggly.Group.add/1`), giving one `Giggly.DataFrame` per layer in the order the
  layers were added. Its columns are named by aesthetic, plus `:panel` and `:group`; the data's own
  column names do not appear.

  Nothing outside Giggly calls this module: the functions in `Giggly` take a plot and run it here.
  """

  # The assembly reads a plot and hands each stage its input; what it may call is the plot, the
  # data frame and the stages, each named as it arrives.
  use Boundary, deps: [Giggly.DataFrame, Giggly.Facet, Giggly.Group, Giggly.Plot], exports: []

  alias Giggly.{DataFrame, Facet, Group, Plot}
  alias Giggly.Plot.Layer

  @doc """
  Assembles `plot` into one table per layer, in the order the layers were added.

  The facet first gives each row of the plot's data its panel. Then each layer's mapping is laid
  over the plot's (the layer's column wins), chooses and renames the data's columns, the panel
  column is carried across, and `Giggly.Group.add/1` adds the `:group` column. The aesthetics come
  out in name order, since a mapping is a map and has no written order to keep, followed by
  `:panel` and `:group`, as ggplot2 orders them.
  """
  @spec run(Plot.t()) :: [DataFrame.t()]
  def run(%Plot{data: data, mapping: plot_mapping, reversed_layers: reversed_layers}) do
    paneled_data = Facet.assign_panels(data)

    reversed_layers
    |> Enum.reverse()
    |> Enum.map(fn layer ->
      paneled_data
      |> evaluate(plot_mapping, layer)
      |> Group.add()
    end)
  end

  # Evaluation keeps only the mapped aesthetics, so the panel the facet assigned is carried across
  # by name: it is the one raw column every layer keeps.
  defp evaluate(paneled_data, plot_mapping, %Layer{mapping: layer_mapping}) do
    renames =
      plot_mapping
      |> Map.merge(layer_mapping)
      |> Enum.sort()

    panels = DataFrame.pull(paneled_data, :panel)

    paneled_data
    |> DataFrame.select(renames)
    |> DataFrame.put(:panel, panels)
  end
end
