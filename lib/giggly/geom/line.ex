defmodule Giggly.Geom.Line do
  @moduledoc false

  # Lines, ggplot2's `GeomLine`, which `geom_line()` draws with: a path through each group's rows
  # in order of their `x`, or of their `y` when its `orientation` is `:y`, a line running up the
  # panel. It is ggplot2's `GeomPath` with its rows put in order first, so it is drawn as a path
  # (`Giggly.Geom.Path`), with the same ends, corners and mitre limit. Use it through
  # `Giggly.Geom`.
  #
  # Lines use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:linetype` and `:linewidth`, and need `:x`
  # and `:y`; an aesthetic joins the accepted list with the scale that maps it, so a mapping never
  # silently does nothing.
  #
  # While the plot is assembled, after the stat and before the position, the rows are put in order
  # of panel, group and then the position along the line (`setup_data/3`), as ggplot2's
  # `GeomLine$setup_data()` orders them: rows that tie keep their order, an infinite position sorts
  # at its end, and a missing one last, as R's `order()` puts `NA` last. The orientation is the
  # layer's to give; ggplot2 would also take it from a stat that names one, and no stat a line
  # takes yet does.

  @enforce_keys [:orientation, :line_end, :line_join, :mitre_limit]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          orientation: :x | :y,
          line_end: Giggly.Scene.Polylines.line_end(),
          line_join: Giggly.Scene.Polylines.line_join(),
          mitre_limit: float()
        }

  # The aesthetics a layer of lines can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :color, :group, :linetype, :linewidth, :x, :y]

  # The aesthetics a layer of lines cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{DataFrame, Geom}

    @impl Giggly.Geom
    def setup_data(%{orientation: orientation}, frame, _axis_kinds) do
      order =
        [
          DataFrame.pull(frame, :panel),
          DataFrame.pull(frame, :group),
          DataFrame.pull(frame, orientation)
        ]
        |> Enum.zip_with(fn [panel, group, position] -> {panel, group, sort_key(position)} end)
        |> Enum.with_index()
        |> Enum.sort_by(fn {key, _index} -> key end)
        |> Enum.map(fn {_key, index} -> index end)

      DataFrame.slice(frame, order)
    end

    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params) do
      geom
      |> path()
      |> Geom.draw_panel(frame, coord, panel_params)
    end

    @impl Giggly.Geom
    def draw_key(geom, key) do
      geom
      |> path()
      |> Geom.draw_key(key)
    end

    @impl Giggly.Geom
    def key_size(geom, key) do
      geom
      |> path()
      |> Geom.key_size(key)
    end

    # The path a line is drawn as.
    defp path(geom) do
      %Geom.Path{
        line_end: geom.line_end,
        line_join: geom.line_join,
        mitre_limit: geom.mitre_limit
      }
    end

    # Where a position sorts, as R's `order()` sorts a double: minus infinity first, then the
    # numbers, then plus infinity, and a missing value last.
    defp sort_key(:neg_infinity), do: {0, 0}
    defp sort_key(position) when is_number(position), do: {1, position}
    defp sort_key(:infinity), do: {2, 0}
    defp sort_key(missing) when missing in [nil, :nan], do: {3, 0}
  end
end
