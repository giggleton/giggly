defmodule Giggly.Scale do
  @moduledoc """
  Position scales: what kind of axis a column's values need, the range or levels those values span
  once trained, and where each value sits on the axis.

  A scale works on plain values, never on frames or plots: the assembly pulls a column and hands
  its values here, so this namespace depends on nothing else in Giggly and could stand alone, as
  R's `scales` package does beside ggplot2.

  ## Kinds

  A column's type decides its scale's kind, as ggplot2's `scale_type()` does:

    * `:integer` and `:float` get a continuous scale (`Giggly.Scale.Continuous`), and so does an
      all-`nil` (`:null`) column, matching ggplot2's continuous fallback;
    * `:string`, `:boolean` and `:atom` get a discrete scale (`Giggly.Scale.Discrete`);
    * dates, times and `:term` get none yet.

  ## Transformation

  A continuous scale records, by name, the transformation its values are put through before it
  trains on them (`Giggly.Scale.Transform`), so it trains, and maps, in transformed space. Every
  continuous scale records the identity until a plot can choose another, as ggplot2's continuous
  scales default to `transform = "identity"`: an untransformed axis says so rather than leaving it
  out. A discrete scale has no transformation, as in ggplot2.

  ## Training and mapping

  Training follows R's `scales` package. A continuous scale's range spans the finite numbers it
  sees; `nil` and the non-finite floats are skipped. A discrete scale's levels are the distinct
  values it sees, sorted with `nil` last and otherwise in Erlang term order, so strings sort by
  their bytes. Mapping leaves a continuous value as it is, and puts a discrete value at its level's
  position, counting from 1, as ggplot2 does before the coordinate system rescales anything.
  """

  # Values in, values out: a scale depends on nothing, so it stays extractable.
  use Boundary, deps: [], exports: []

  alias Giggly.Scale.{Continuous, Discrete, Labels, Transform}

  @typedoc "A trained position scale."
  @type t :: Continuous.t() | Discrete.t()

  @typedoc "A break on an axis: its position and its label."
  @type break :: {number(), String.t()}

  @typedoc "Which kind of scale a column needs, or `:none` when no scale can place it yet."
  @type kind :: :continuous | :discrete | :none

  @continuous_dtypes [:integer, :float, :null]
  @discrete_dtypes [:string, :boolean, :atom]

  # ggplot2's default expansion, as {multiple of the width, constant}: `expansion(mult = 0.05)`
  # for a continuous scale and `expansion(add = 0.6)` for a discrete one.
  @continuous_expansion {0.05, 0}
  @discrete_expansion {0, 0.6}

  # R's `zero_range()` tolerance: 1000 times the double-precision machine epsilon.
  @zero_range_tolerance 1000 * 2.220446049250313e-16

  @doc """
  The kind of scale a column of type `dtype` (a `Giggly.DataFrame` type) needs.

      iex> dtypes = [:integer, :float, :null, :string, :boolean, :atom, :date, :time, :term]
      iex> Enum.map(dtypes, &Giggly.Scale.kind/1)
      [:continuous, :continuous, :continuous, :discrete, :discrete, :discrete, :none, :none, :none]
  """
  @spec kind(atom()) :: kind()
  def kind(dtype) when dtype in @continuous_dtypes, do: :continuous
  def kind(dtype) when dtype in @discrete_dtypes, do: :discrete
  def kind(dtype) when is_atom(dtype), do: :none

  @doc """
  An untrained scale of the given kind; a continuous one records the identity transformation.
  """
  @spec new(:continuous | :discrete) :: t()
  def new(:continuous), do: %Continuous{range: :none, transform: :identity}
  def new(:discrete), do: %Discrete{levels: []}

  @doc """
  The values in the space the scale trains and maps in: put through a continuous scale's
  transformation, and as given to a discrete scale, which has none.
  """
  @spec transform(t(), list()) :: list()
  def transform(%Continuous{} = scale, values), do: Continuous.transform(scale, values)
  def transform(%Discrete{}, values), do: values

  @doc """
  The scale widened to cover `values`.

      iex> scale = Giggly.Scale.new(:continuous)
      iex> scale |> Giggly.Scale.train([nil, 3, :infinity, 1.5]) |> Giggly.Scale.train([2])
      %Giggly.Scale.Continuous{range: {1.5, 3}, transform: :identity}

      iex> scale = Giggly.Scale.new(:discrete)
      iex> scale |> Giggly.Scale.train(["b", nil, "a"]) |> Giggly.Scale.train(["c", "a"])
      %Giggly.Scale.Discrete{levels: ["a", "b", "c", nil]}
  """
  @spec train(t(), list()) :: t()
  def train(%Continuous{} = scale, values), do: Continuous.train(scale, values)
  def train(%Discrete{} = scale, values), do: Discrete.train(scale, values)

  @doc """
  Each value's position on the scale's axis: a continuous value unchanged, a discrete one at its
  level's position counting from 1.

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:discrete), ["6", "4", nil])
      iex> Giggly.Scale.map(scale, ["6", "4", "6", nil])
      [2, 1, 2, 3]

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [2.62, 2.875])
      iex> Giggly.Scale.map(scale, [2.62, 2.875])
      [2.62, 2.875]
  """
  @spec map(t(), list()) :: list()
  def map(%Continuous{} = scale, values), do: Continuous.map(scale, values)
  def map(%Discrete{} = scale, values), do: Discrete.map(scale, values)

  @doc """
  The extent of the axis in positions, widened as ggplot2 widens it by default before drawing: a
  continuous range by 5% of its width at each end, and discrete levels, at positions 1 to n, by
  0.6. A range of zero width is widened as though its width were 1, as R's `expand_range()` does,
  so one value, zero included, spans 0.05 either side of it; an untrained continuous scale spans 0 to 1 before it
  is widened, ggplot2's default for an empty axis. It is ggplot2's `dimension()` with the default
  expansion, and the coordinate system maps it onto the panel.

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [1, 3])
      iex> Giggly.Scale.dimension(scale)
      {0.9, 3.1}

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [0])
      iex> Giggly.Scale.dimension(scale)
      {-0.05, 0.05}

  Ends that differ only by rounding error, relative to their size, count as one value:

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [1000.0, 1000.0000000000001])
      iex> Giggly.Scale.dimension(scale)
      {999.95, 1000.0500000000001}

      iex> Giggly.Scale.dimension(Giggly.Scale.new(:continuous))
      {-0.05, 1.05}

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:discrete), ["6", "4", "8"])
      iex> Giggly.Scale.dimension(scale)
      {0.4, 3.6}
  """
  @spec dimension(t()) :: {number(), number()}
  def dimension(%Continuous{range: :none}), do: expand({0, 1}, @continuous_expansion)
  def dimension(%Continuous{range: range}), do: expand(range, @continuous_expansion)
  def dimension(%Discrete{levels: levels}), do: expand({1, length(levels)}, @discrete_expansion)

  @doc """
  The breaks an axis showing `extent` of the scale draws, each its position and its label, in
  ascending order: ggplot2's `get_breaks()` and `get_labels()` as its view scale calls them.

  A continuous scale takes its transformation's breaks (`Giggly.Scale.Transform`), keeps those
  inside `extent` (ggplot2 computes breaks on the widened extent and drops the rest), and writes
  them as its transformation writes them. An untrained one has none, and an extent of zero width
  has one break, at its end, as in ggplot2.

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [0, 10])
      iex> Giggly.Scale.breaks(scale, Giggly.Scale.dimension(scale))
      [{0.0, "0.0"}, {2.5, "2.5"}, {5.0, "5.0"}, {7.5, "7.5"}, {10.0, "10.0"}]

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [1.513, 5.424])
      iex> Giggly.Scale.breaks(scale, Giggly.Scale.dimension(scale))
      [{2.0, "2"}, {3.0, "3"}, {4.0, "4"}, {5.0, "5"}]

  A break exactly at an end of the extent is kept:

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [3, 17])
      iex> Giggly.Scale.breaks(scale, {0.0, 20.0})
      [{0.0, "0"}, {5.0, "5"}, {10.0, "10"}, {15.0, "15"}, {20.0, "20"}]

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [1.0e16])
      iex> Giggly.Scale.breaks(scale, Giggly.Scale.dimension(scale))
      [{1.0e16, "10000000000000000"}]

      iex> Giggly.Scale.breaks(Giggly.Scale.new(:continuous), {-0.05, 1.05})
      []

  A discrete scale has a break at each level, whatever the extent, labelled as
  `Giggly.Scale.Labels` writes a level:

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:discrete), ["6", nil, "4"])
      iex> Giggly.Scale.breaks(scale, Giggly.Scale.dimension(scale))
      [{1, "4"}, {2, "6"}, {3, "NA"}]
  """
  @spec breaks(t(), {float(), float()}) :: [break()]
  def breaks(%Continuous{range: :none}, _extent), do: []

  def breaks(%Continuous{transform: transform}, {low, high} = extent) do
    positions =
      if zero_range?(low, high) do
        [low]
      else
        transform
        |> Transform.breaks(extent)
        |> Enum.filter(fn position -> position >= low and position <= high end)
      end

    Enum.zip(positions, Transform.format(transform, positions))
  end

  def breaks(%Discrete{levels: levels}, _extent) do
    levels
    |> Labels.levels()
    |> Enum.with_index(1)
    |> Enum.map(fn {label, position} -> {position, label} end)
  end

  @doc """
  The minor breaks an axis showing `extent` of the scale draws between `breaks`, the breaks
  `breaks/2` gives on that extent, in ascending order: ggplot2's `get_breaks_minor()` as its view
  scale calls it, less the breaks themselves, which ggplot2's grid leaves out of its minor lines.

  A continuous scale takes its transformation's minor breaks (`Giggly.Scale.Transform`) and keeps
  those inside `extent`, its ends included. Midway between breaks, and between the outermost
  breaks and the extent's ends:

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [0, 10])
      iex> extent = Giggly.Scale.dimension(scale)
      iex> Giggly.Scale.minor_breaks(scale, Giggly.Scale.breaks(scale, extent), extent)
      [1.25, 3.75, 6.25, 8.75]

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [1.513, 5.424])
      iex> extent = Giggly.Scale.dimension(scale)
      iex> Giggly.Scale.minor_breaks(scale, Giggly.Scale.breaks(scale, extent), extent)
      [1.5, 2.5, 3.5, 4.5, 5.5]

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [0, 10])
      iex> breaks = [{2.5, "2.5"}, {5.0, "5.0"}, {7.5, "7.5"}]
      iex> Giggly.Scale.minor_breaks(scale, breaks, {1.25, 8.75})
      [1.25, 3.75, 6.25, 8.75]

  An axis with fewer than two breaks has none, and so does a discrete scale, as in ggplot2:

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:continuous), [1.0e16])
      iex> extent = Giggly.Scale.dimension(scale)
      iex> Giggly.Scale.minor_breaks(scale, Giggly.Scale.breaks(scale, extent), extent)
      []

      iex> scale = Giggly.Scale.train(Giggly.Scale.new(:discrete), ["a", "b", "c"])
      iex> extent = Giggly.Scale.dimension(scale)
      iex> Giggly.Scale.minor_breaks(scale, Giggly.Scale.breaks(scale, extent), extent)
      []
  """
  @spec minor_breaks(t(), [break()], {float(), float()}) :: [float()]
  def minor_breaks(%Continuous{transform: transform}, breaks, {low, high} = extent) do
    positions = Enum.map(breaks, fn {position, _label} -> position end)

    transform
    |> Transform.minor_breaks(positions, extent)
    |> Enum.filter(fn position -> position >= low and position <= high end)
    |> Enum.reject(fn position -> position in positions end)
  end

  def minor_breaks(%Discrete{}, _breaks, _extent), do: []

  # Widens each end by a multiple of the range's width plus a constant: R's `expand_range()`.
  defp expand({low, high}, {multiple, constant}) do
    width = if zero_range?(low, high), do: 1, else: high - low
    padding = width * multiple + constant
    {low - padding, high + padding}
  end

  # R's `zero_range()`: equal ends, or ends so close, relative to the smaller, that their
  # difference is rounding error.
  defp zero_range?(low, high) when low == high, do: true

  defp zero_range?(low, high) do
    smaller = min(abs(low), abs(high))
    smaller != 0 and abs((low - high) / smaller) < @zero_range_tolerance
  end

  @doc """
  The key that orders discrete values: `nil` after every present value, which compare in Erlang
  term order. Grouping orders its combinations by the same key, so group ids and axis positions
  agree.
  """
  @spec level_key(term()) :: {0, term()} | {1, nil}
  def level_key(nil), do: {1, nil}
  def level_key(value), do: {0, value}
end
