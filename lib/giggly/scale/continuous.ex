defmodule Giggly.Scale.Continuous do
  @moduledoc """
  A trained continuous position scale: the range of the finite numbers it has seen, or `:none`
  before it has seen any. Use it through `Giggly.Scale`.
  """

  @enforce_keys [:range]
  defstruct @enforce_keys

  @type t :: %__MODULE__{range: :none | {number(), number()}}

  @doc "The scale widened to cover the finite numbers in `values`, as `Giggly.Scale.train/2` describes."
  @spec train(t(), list()) :: t()
  def train(%__MODULE__{range: range} = scale, values) do
    %{scale | range: Enum.reduce(values, range, &widen/2)}
  end

  @doc "The values unchanged, as `Giggly.Scale.map/2` describes."
  @spec map(t(), list()) :: list()
  def map(%__MODULE__{}, values), do: values

  # `nil` and Explorer's non-finite float atoms are not numbers, so only a number widens the range.
  defp widen(value, :none) when is_number(value), do: {value, value}

  defp widen(value, {low, high}) when is_number(value),
    do: {min(low, value), max(high, value)}

  defp widen(_not_a_finite_number, range), do: range
end
