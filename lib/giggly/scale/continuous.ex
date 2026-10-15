defmodule Giggly.Scale.Continuous do
  @moduledoc """
  A trained continuous position scale, as `Giggly.panel_scales/2` returns it: the range of the
  finite numbers it has seen, or `:none` before it has seen any, and the name of the
  transformation its values are put through before it sees them.
  """

  # Use it through `Giggly.Scale`; the transformation is resolved by `Giggly.Scale.Transform`.

  alias Giggly.Scale.Transform

  @enforce_keys [:range, :transform]
  defstruct @enforce_keys

  @type t :: %__MODULE__{range: :none | {number(), number()}, transform: atom()}

  # The values put through the scale's transformation, as `Giggly.Scale.transform/2` describes.
  @doc false
  @spec transform(t(), list()) :: list()
  def transform(%__MODULE__{transform: name}, values), do: Transform.transform(name, values)

  # The scale widened to cover the finite numbers in `values`, as `Giggly.Scale.train/2` describes.
  @doc false
  @spec train(t(), list()) :: t()
  def train(%__MODULE__{range: range} = scale, values) do
    %{scale | range: train_range(range, values)}
  end

  # A range, `:none` for none, widened to cover the finite numbers among `values`: R's
  # `scales::train_continuous()`, which a discrete scale's continuous range trains by too.
  @doc false
  @spec train_range(:none | {number(), number()}, list()) :: :none | {number(), number()}
  def train_range(range, values), do: Enum.reduce(values, range, &widen/2)

  # The values unchanged, as `Giggly.Scale.map/2` describes, until limits can censor them.
  @doc false
  @spec map(t(), list()) :: list()
  def map(%__MODULE__{}, values), do: values

  # `nil` and Explorer's non-finite float atoms are not numbers, so only a number widens the range.
  defp widen(value, :none) when is_number(value), do: {value, value}

  defp widen(value, {low, high}) when is_number(value),
    do: {min(low, value), max(high, value)}

  defp widen(_not_a_finite_number, range), do: range
end
