defmodule Giggly.Geom.Errorbar do
  @moduledoc false

  # Error bars, ggplot2's `GeomErrorbar`, which `geom_errorbar()` draws with: for each row a
  # vertical line from its `ymin` to its `ymax` at its `x`, with a whisker across each end as wide
  # as its `width`, or, turned, a horizontal line from its `xmin` to its `xmax` at its `y`. Its
  # parameters are which way it runs (`orientation`: `:x`, `:y`, or `:none` to take it from the
  # ranges given) and how a line's ends are drawn (`line_end`, ggplot2's `lineend`). Crossbars
  # (`Giggly.Geom.Crossbar`) are set up as error bars are, as ggplot2's `GeomCrossbar` calls
  # `GeomErrorbar$setup_data()`. Use it through `Giggly.Geom`.
  #
  # Error bars use a line range's aesthetics and `:width`, and need what a line range needs, one of
  # `:x` and `:y`, one of `:ymin` and `:xmin` and one of `:ymax` and `:xmax`; `Giggly.Plot` makes
  # sure a layer has the three its orientation draws with.
  #
  # While the plot is assembled (`setup_data/3`), an error bar takes its orientation as a line range
  # does, writing it in `flipped_aes`, and then, along it, its sides, `xmin` and `xmax`, its `x`
  # less and plus half its width, in R's arithmetic (`Giggly.DataFrame.Arithmetic`): the `width` the
  # layer maps or sets, or else 0.9 of the closest spacing of its x positions in any panel, not
  # counting from zero, 1 apart on a discrete axis (`Giggly.Resolution`), as ggplot2's
  # `compute_data_size(zero = FALSE, discrete = TRUE)` reads them; the `width` is then dropped, and
  # R's default width, which ggplot2 puts back into its table, is left out. A width that is not a
  # number is refused, as ggplot2 fails at `x - width / 2`.
  #
  # Each panel is drawn as ggplot2's `GeomErrorbar` draws it: each row a path of its own, its top
  # whisker from `{xmin, ymax}` to `{xmax, ymax}`, its stem from `{x, ymax}` to `{x, ymin}` and its
  # bottom whisker from `{xmin, ymin}` to `{xmax, ymin}`, broken between them by missing points, and
  # turned for a horizontal layer, drawn as `Giggly.Geom.Path` draws one with the layer's line
  # ends, round corners and no arrowheads. An error bar the layer neither maps nor sets a look for
  # looks as a path does; its legend key is a path's, a line across the key, as ggplot2's
  # `GeomErrorbar` draws its key with `draw_key_path()`, either way.

  alias Giggly.{Aesthetics, DataFrame, Resolution}
  alias Giggly.DataFrame.Arithmetic
  alias Giggly.Geom.{Linerange, Ribbon}

  @enforce_keys [:orientation, :line_end]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          orientation: :none | :x | :y,
          line_end: Giggly.Scene.Polylines.line_end()
        }

  # ggplot2's default error bar, its share of the spacing of the x positions.
  @width_share 0.9

  # The aesthetics a layer of error bars can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: Enum.sort([:width | Linerange.accepted_aesthetics()])

  # The aesthetics a layer of error bars cannot be drawn without, a line range's.
  @doc false
  @spec required_aesthetics() :: [[atom()]]
  def required_aesthetics, do: Linerange.required_aesthetics()

  # `frame` set up as an error bar or a crossbar is, ggplot2's `GeomErrorbar$setup_data()`: its
  # orientation as `orientation` says, written in `flipped_aes`, and along it each row's sides, its
  # x less and plus half its width, `axis_kinds` saying whether the axis it is placed along is
  # discrete.
  @doc false
  @spec with_sides(DataFrame.t(), :none | :x | :y, Giggly.Geom.axis_kinds()) :: DataFrame.t()
  def with_sides(frame, orientation, axis_kinds) do
    check_width(frame)
    oriented = Linerange.oriented(frame, orientation)
    flipped = Linerange.flipped_aes(oriented)
    along = if flipped, do: :y, else: :x

    oriented
    |> Ribbon.flip(flipped)
    |> sides(Map.fetch!(axis_kinds, along) == :discrete)
    |> Ribbon.flip(flipped)
  end

  # An error bar is drawn as wide as its width, so a width must be a number. `Giggly.Plot` refuses
  # a column or a constant that is not at the call; an expression's type is known only once it has
  # run, so one that computes anything else is refused here, where ggplot2 fails at
  # `x - width / 2`.
  defp check_width(frame) do
    case DataFrame.dtypes(frame) do
      %{width: dtype} when dtype not in [:integer, :float, :null] ->
        raise ArgumentError,
              "an error bar or crossbar is drawn as wide as its width, so a width must be a " <>
                "number, but the layer's width is a #{inspect(dtype)} column"

      _numbers_or_no_width ->
        :ok
    end
  end

  defp sides(frame, discrete) do
    x_positions = DataFrame.pull(frame, :x)

    halves =
      frame
      |> widths(discrete)
      |> Enum.map(fn width -> Arithmetic.divide(width, 2) end)

    kept =
      frame
      |> DataFrame.names()
      |> Enum.reject(fn name -> name == :width end)
      |> Enum.map(fn name -> {name, name} end)

    frame
    |> DataFrame.select(kept)
    |> DataFrame.put(:xmin, Enum.zip_with(x_positions, halves, &Arithmetic.subtract/2))
    |> DataFrame.put(:xmax, Enum.zip_with(x_positions, halves, &Arithmetic.add/2))
  end

  # Each row's width, ggplot2's `compute_data_size()` across panels: the one the layer maps or
  # sets, or else the closest spacing of the x positions in each panel, the smallest of them, times
  # the error bar's share.
  defp widths(frame, discrete) do
    if :width in DataFrame.names(frame) do
      DataFrame.pull(frame, :width)
    else
      width = own_width(frame, discrete)
      List.duplicate(width, DataFrame.row_count(frame))
    end
  end

  defp own_width(frame, discrete) do
    resolution =
      frame
      |> DataFrame.pull(:panel)
      |> Enum.zip(DataFrame.pull(frame, :x))
      |> Enum.group_by(fn {panel, _x} -> panel end, fn {_panel, x} -> x end)
      |> Enum.map(fn {_panel, panel_positions} ->
        Resolution.of(panel_positions, zero: false, discrete: discrete)
      end)
      |> Enum.min(fn -> 1 end)

    resolution * @width_share
  end

  # Each row's three lines as one path of eight points, its top whisker, its stem and its bottom
  # whisker broken apart by missing points, in a group of its own numbered by its place, every
  # other column the row's, as `GeomErrorbar$draw_panel()` interleaves them; turned back where the
  # rows run along y.
  @doc false
  @spec paths(DataFrame.t()) :: DataFrame.t()
  def paths(frame) do
    flipped = Linerange.flipped_aes(frame)
    vertical = Ribbon.flip(frame, flipped)
    count = DataFrame.row_count(vertical)
    repeated = Enum.flat_map(0..(count - 1)//1, fn index -> List.duplicate(index, 8) end)

    [x_positions, xmins, xmaxes, ymins, ymaxes] =
      Enum.map([:x, :xmin, :xmax, :ymin, :ymax], fn name -> DataFrame.pull(vertical, name) end)

    points =
      [x_positions, xmins, xmaxes, ymins, ymaxes]
      |> Enum.zip_with(fn [x, xmin, xmax, ymin, ymax] ->
        [
          {xmin, ymax},
          {xmax, ymax},
          {nil, nil},
          {x, ymax},
          {x, ymin},
          {nil, nil},
          {xmin, ymin},
          {xmax, ymin}
        ]
      end)
      |> Enum.concat()

    looks =
      vertical
      |> DataFrame.names()
      |> Enum.filter(fn name -> Aesthetics.family(name) == :none end)
      |> Enum.reject(fn name -> name == :group end)
      |> Enum.map(fn name -> {name, name} end)

    vertical
    |> DataFrame.slice(repeated)
    |> DataFrame.select(looks)
    |> DataFrame.put(:x, Enum.map(points, fn {x, _y} -> x end))
    |> DataFrame.put(:y, Enum.map(points, fn {_x, y} -> y end))
    |> DataFrame.put(:group, repeated)
    |> Ribbon.flip(flipped)
  end

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.Geom

    @impl Giggly.Geom
    def default_aesthetics(geom, element) do
      geom
      |> path()
      |> Geom.default_aesthetics(element)
    end

    @impl Giggly.Geom
    def setup_data(geom, frame, axis_kinds),
      do: Geom.Errorbar.with_sides(frame, geom.orientation, axis_kinds)

    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params, installed_fonts) do
      geom
      |> path()
      |> Geom.draw_panel(Geom.Errorbar.paths(frame), coord, panel_params, installed_fonts)
    end

    @impl Giggly.Geom
    def draw_key(geom, key, installed_fonts) do
      geom
      |> path()
      |> Geom.draw_key(key, installed_fonts)
    end

    @impl Giggly.Geom
    def key_size(geom, key, installed_fonts) do
      geom
      |> path()
      |> Geom.key_size(key, installed_fonts)
    end

    # The path an error bar is drawn and keyed as, with the layer's ends and round corners,
    # ggplot2's `GeomErrorbar` handing its paths to `GeomPath$draw_panel()` with its `lineend`
    # alone.
    defp path(geom) do
      %Geom.Path{line_end: geom.line_end, line_join: :round, mitre_limit: 10.0, arrow: :none}
    end
  end
end
