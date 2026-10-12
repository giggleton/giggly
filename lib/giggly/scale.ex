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

  ## Training and mapping

  Training follows R's `scales` package. A continuous scale's range spans the finite numbers it
  sees; `nil` and the non-finite floats are skipped. A discrete scale's levels are the distinct
  values it sees, sorted with `nil` last and otherwise in Erlang term order, so strings sort by
  their bytes. Mapping leaves a continuous value as it is, and puts a discrete value at its level's
  position, counting from 1, as ggplot2 does before the coordinate system rescales anything.
  """

  # Values in, values out: a scale depends on nothing, so it stays extractable.
  use Boundary, deps: [], exports: []

  alias Giggly.Scale.{Continuous, Discrete}

  @typedoc "A trained position scale."
  @type t :: Continuous.t() | Discrete.t()

  @typedoc "Which kind of scale a column needs, or `:none` when no scale can place it yet."
  @type kind :: :continuous | :discrete | :none

  @continuous_dtypes [:integer, :float, :null]
  @discrete_dtypes [:string, :boolean, :atom]

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
  An untrained scale of the given kind.
  """
  @spec new(:continuous | :discrete) :: t()
  def new(:continuous), do: %Continuous{range: :none}
  def new(:discrete), do: %Discrete{levels: []}

  @doc """
  The scale widened to cover `values`.

      iex> scale = Giggly.Scale.new(:continuous)
      iex> scale |> Giggly.Scale.train([nil, 3, :infinity, 1.5]) |> Giggly.Scale.train([2])
      %Giggly.Scale.Continuous{range: {1.5, 3}}

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
  The key that orders discrete values: `nil` after every present value, which compare in Erlang
  term order. Grouping orders its combinations by the same key, so group ids and axis positions
  agree.
  """
  @spec level_key(term()) :: {0, term()} | {1, nil}
  def level_key(nil), do: {1, nil}
  def level_key(value), do: {0, value}
end
