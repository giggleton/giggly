defmodule Giggly.Geom.Raster do
  @moduledoc false

  # A raster, ggplot2's `GeomRaster`: equal cells on a regular grid, one per row, drawn as one
  # image. Use it through `Giggly.Geom`.
  #
  # Rasters use `:x`, `:y`, `:group`, `:alpha` and `:fill`, and need `:x` and `:y`; ggplot2's
  # raster ignores `colour`, so it is not taken.
  #
  # While the plot is assembled, each row becomes a cell in data space (`setup_data/3`), as
  # ggplot2's `GeomRaster$setup_data()` makes one, over the layer's rows whatever their panel: as
  # wide as the gap between the x positions, the first where every gap is the same, within R's
  # tolerance, the square root of the machine epsilon, and otherwise the smallest, 1 with one x
  # alone, and placed against its x as `hjust` says, `x - width * (1 - hjust)` to `x + width *
  # hjust`; as tall likewise from the y positions and `vjust`. Where the gaps differ, a value
  # that is not a whole number of cells from the least, within that tolerance, is refused, naming
  # the axis and `geom_tile/3`: ggplot2 warns and draws such cells shifted from their places,
  # which a pure pipeline cannot say; a grid with holes, whose values all are, is drawn as
  # ggplot2 draws it. A row missing its x or y has no cell.
  #
  # Each panel's cells are drawn as one image (`Giggly.Scene.Raster`), as `GeomRaster` draws a
  # `rasterGrob()`: a cell at each position counted in the closest spacing of the panel's
  # positions (`Giggly.Resolution`, not counting from zero) from its least, rows from the top, each
  # in its fill at its opacity, as `alpha()` makes it, a place no row fills left clear, the image
  # spanning the cells' edges, smoothed between cells when `interpolate` says so. In a coordinate
  # system whose straight lines bend (`Giggly.Coord.linear?/1`), where an image cannot follow,
  # the cells are drawn as rectangles (`Giggly.Geom.Rect`), each bordered in its own fill 0.3 mm
  # wide so they meet, as ggplot2 falls back to `GeomRect`. A raster the layer neither maps nor
  # sets a fill for is filled with the theme's ink mixed 20% toward its paper, `#333333` on white
  # paper. Its legend key is the key's fill over the whole key, unbordered, as
  # `draw_key_polygon()` draws a key with no border's width.

  # Every field is given by the function that adds the layer, its defaults there.
  @enforce_keys [:hjust, :vjust, :interpolate]
  defstruct @enforce_keys

  @type t :: %__MODULE__{hjust: float(), vjust: float(), interpolate: boolean()}

  # The aesthetics a layer of rasters can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :fill, :group, :x, :y]

  # The aesthetics a layer of rasters cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame, Geom, Resolution}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Geom.{Mark, Rect}
    alias Giggly.Scene.Raster
    alias Scales.ColorOperations

    # How far a raster's default fill is mixed from the theme's ink toward its paper, ggplot2's
    # `col_mix(ink, paper, 0.2)`.
    @fill_toward_paper 0.2

    # R's `sqrt(.Machine$double.eps)`, within which ggplot2's raster calls two gaps equal.
    @precision :math.sqrt(2.220446049250313e-16)

    # The border ggplot2 gives each cell drawn as a rectangle, in millimetres, its own fill's
    # colour, so neighbouring cells meet.
    @fallback_border 0.3

    @impl Giggly.Geom
    def setup_data(geom, frame, _axis_kinds) do
      sides = [{:x, geom.hjust, :xmin, :xmax}, {:y, geom.vjust, :ymin, :ymax}]

      Enum.reduce(sides, frame, fn {axis, just, low, high}, edged ->
        positions = DataFrame.pull(frame, axis)
        size = cell_size(positions, axis)

        lows = Enum.map(positions, fn value -> edge(value, -size * (1 - just)) end)
        highs = Enum.map(positions, fn value -> edge(value, size * just) end)

        edged
        |> DataFrame.put(low, lows)
        |> DataFrame.put(high, highs)
      end)
    end

    # A cell's size along `axis`, ggplot2's raster's: the gap between the sorted distinct
    # positions, the first where every gap is the same within R's precision and otherwise the
    # smallest, a value off that grid refused; 1 with one position alone.
    defp cell_size(positions, axis) do
      distinct =
        positions
        |> Enum.filter(&is_number/1)
        |> Enum.map(fn value -> value / 1 end)
        |> Enum.uniq()
        |> Enum.sort()

      gaps =
        distinct
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [low, high] -> high - low end)

      cond do
        gaps == [] -> 1.0
        even?(gaps) -> hd(gaps)
        true -> check_grid(distinct, Enum.min(gaps), axis)
      end
    end

    defp even?(gaps) do
      gaps
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [first, second] -> abs(second - first) <= @precision end)
    end

    # The smallest gap, where every distinct position is a whole number of it from the least, as
    # a grid with holes is; otherwise a refusal, since ggplot2 would draw the cells shifted.
    defp check_grid([least | _rest] = distinct, size, axis) do
      case Enum.find(distinct, fn value -> off_grid?(value - least, size) end) do
        nil ->
          size

        value ->
          raise ArgumentError,
                "a raster's cells sit on a grid of its #{axis} positions' smallest gap, " <>
                  "#{size}, but #{axis} #{value} is not a whole number of gaps from the least, " <>
                  "#{least}, so its cell would be drawn away from it; draw cells at uneven " <>
                  "positions with geom_tile/3"
      end
    end

    defp off_grid?(distance, size), do: abs(distance - round(distance / size) * size) > @precision

    # A position moved by `distance` to an edge, in R's arithmetic, so an infinite cell's edge is
    # at its infinity; a missing one stays missing.
    defp edge(value, distance), do: Arithmetic.add(value, distance)

    # ggplot2's `GeomRaster$default_aes`: a fill of the theme's ink mixed toward its paper, and no
    # alpha of its own.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element) do
      [
        fill: ColorOperations.mix(element.ink, element.paper, @fill_toward_paper),
        alpha: nil
      ]
    end

    # The panel's cells as one image where straight lines stay straight, else as rectangles.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params, installed_fonts) do
      placed = drawn_rows(frame)

      cond do
        DataFrame.row_count(placed) == 0 ->
          []

        Coord.linear?(coord) ->
          [image(geom, placed, coord, panel_params)]

        true ->
          fallback = rectangles(placed)
          Geom.draw_panel(%Rect{}, fallback, coord, panel_params, installed_fonts)
      end
    end

    # The rows with a cell to draw, as ggplot2 leaves out a row missing its position or its edges.
    defp drawn_rows(frame) do
      DataFrame.filter(
        frame,
        {:and,
         [
           {:and, [{:is_finite, [:x]}, {:is_finite, [:y]}]},
           {:and, [{:is_finite, [:xmin]}, {:is_finite, [:ymin]}]}
         ]}
      )
    end

    defp image(geom, frame, coord, panel_params) do
      columns = cell_places(frame, :x)
      rows = cell_places(frame, :y)
      height = Enum.max(rows) + 1
      fills = Mark.colors(frame, :fill)
      opacities = Mark.opacities(frame, fills)

      cells =
        [columns, rows, fills, opacities]
        |> Enum.zip_with(fn [column, row, fill, opacity] ->
          {{height - 1 - row, column}, {Mark.hex(fill), opacity}}
        end)
        |> Map.new()

      grid =
        for row <- 0..(height - 1) do
          for column <- 0..Enum.max(columns),
              do: Map.get(cells, {row, column}, {:none, 0.0})
        end

      corners = Coord.transform(coord, DataFrame.select(frame, edges()), panel_params)
      [xmin, xmax, ymin, ymax] = Enum.map(edges(), fn {name, name} -> corner(corners, name) end)

      %Raster{
        xmin: xmin,
        xmax: xmax,
        ymin: ymin,
        ymax: ymax,
        fill: Enum.map(grid, fn line -> Enum.map(line, fn {fill, _opacity} -> fill end) end),
        fill_opacity:
          Enum.map(grid, fn line -> Enum.map(line, fn {_fill, opacity} -> opacity end) end),
        interpolate: geom.interpolate
      }
    end

    defp edges, do: [xmin: :xmin, xmax: :xmax, ymin: :ymin, ymax: :ymax]

    # The image's edge in the cell: the least of the cells' lower edges, or the greatest of their
    # upper ones.
    defp corner(corners, name) do
      edges = DataFrame.pull(corners, name)
      if name in [:xmin, :ymin], do: Enum.min(edges), else: Enum.max(edges)
    end

    # Each row's place along `axis`, counted in the closest spacing of the panel's positions from
    # its least, as ggplot2's raster truncates `(x - min(x)) / resolution(x, FALSE)`.
    defp cell_places(frame, axis) do
      positions = DataFrame.pull(frame, axis)
      least = Enum.min(positions)
      spacing = Resolution.of(positions, zero: false, discrete: false)
      Enum.map(positions, fn value -> trunc((value - least) / spacing) end)
    end

    # The cells as ggplot2's fallback rectangles: bordered in their own fill, solid, 0.3 mm wide.
    defp rectangles(frame) do
      frame
      |> DataFrame.put(:color, DataFrame.pull(frame, :fill))
      |> DataFrame.put(:linewidth, List.duplicate(@fallback_border, DataFrame.row_count(frame)))
      |> DataFrame.put(:linetype, List.duplicate({}, DataFrame.row_count(frame)))
    end

    # A legend's key, and the room it needs, as `draw_key_polygon()` draws a raster's: the key's
    # fill over the whole key, with no border, since a raster has no border's width.
    @impl Giggly.Geom
    def draw_key(_geom, key, installed_fonts),
      do: Geom.draw_key(%Rect{}, unbordered(key), installed_fonts)

    @impl Giggly.Geom
    def key_size(_geom, key, installed_fonts),
      do: Geom.key_size(%Rect{}, unbordered(key), installed_fonts)

    defp unbordered(key), do: Map.merge(key, %{color: nil, linewidth: 0.0, linetype: {}})
  end
end
