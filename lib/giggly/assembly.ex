defmodule Giggly.Assembly do
  @moduledoc """
  The assembly of a plot: the fixed sequence of stages that turns a `Giggly.Plot`, a description,
  into what is drawn. The name is the middle of Wilkinson's three stages of making a graphic
  (specification, assembly, display); a plot is the specification, and drawing is the display.

  The stages run in one fixed order, each adjacent pair a semantic chosen on purpose, and they
  arrive one at a time. Today the assembly evaluates each layer's mapping against the plot's data
  and adds the `:group` column (`Giggly.Group.add/1`), giving one `Giggly.DataFrame` per layer in
  the order the layers were added. Its columns are named by aesthetic; the data's own column names
  do not appear.

  Nothing outside Giggly calls this module: the functions in `Giggly` take a plot and run it here.
  """

  # The assembly reads a plot and hands each stage its input; what it may call is the plot, the
  # data frame and the stages, each named as it arrives.
  use Boundary, deps: [Giggly.DataFrame, Giggly.Group, Giggly.Plot], exports: []

  alias Giggly.{DataFrame, Group, Plot}
  alias Giggly.Plot.Layer

  @doc """
  Assembles `plot` into one table per layer, in the order the layers were added.

  Each layer's mapping is laid over the plot's (the layer's column wins), chooses and renames the
  data's columns, and `Giggly.Group.add/1` adds the `:group` column. The columns come out in
  aesthetic-name order, since a mapping is a map and has no written order to keep, and `:group` is
  last.
  """
  @spec run(Plot.t()) :: [DataFrame.t()]
  def run(%Plot{data: data, mapping: plot_mapping, reversed_layers: reversed_layers}) do
    reversed_layers
    |> Enum.reverse()
    |> Enum.map(fn layer ->
      data
      |> evaluate(plot_mapping, layer)
      |> Group.add()
    end)
  end

  defp evaluate(data, plot_mapping, %Layer{mapping: layer_mapping}) do
    renames =
      plot_mapping
      |> Map.merge(layer_mapping)
      |> Enum.sort()

    DataFrame.select(data, renames)
  end
end
