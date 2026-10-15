defmodule Giggly.Scale.Discrete do
  @moduledoc """
  A trained discrete position scale, as `Giggly.panel_scales/2` returns it: the distinct values it
  has seen, in level order, and the continuous range of the positions it has been handed since its
  levels were placed, such as a bar's edges, `:none` before any: ggplot2's `range_c`, which can
  widen the axis past its levels.
  """

  # Use it through `Giggly.Scale`.

  alias Giggly.Scale.Continuous

  @enforce_keys [:levels, :continuous_range]
  defstruct @enforce_keys

  @type t :: %__MODULE__{levels: list(), continuous_range: :none | {number(), number()}}

  # The scale with the distinct `values` merged into its levels, as `Giggly.Scale.train/2`
  # describes; or, handed positions, its continuous range widened to cover them, as ggplot2's
  # discrete position scale trains a numeric column on `range_c` rather than its levels.
  @doc false
  @spec train(t(), list()) :: t()
  def train(%__MODULE__{continuous_range: range} = scale, values) do
    if Enum.any?(values, fn value -> is_number(value) end),
      do: %{scale | continuous_range: Continuous.train_range(range, values)},
      else: train_levels(scale, values)
  end

  defp train_levels(%__MODULE__{levels: levels} = scale, values) do
    merged =
      levels
      |> Enum.concat(values)
      |> Enum.uniq()
      |> Enum.sort_by(&Giggly.Scale.level_key/1)

    %{scale | levels: merged}
  end

  # Each value's level position counting from 1, as `Giggly.Scale.map/2` describes.
  @doc false
  @spec map(t(), list()) :: [pos_integer() | nil]
  def map(%__MODULE__{levels: levels}, values) do
    position_by_level =
      levels
      |> Enum.with_index(1)
      |> Map.new()

    Enum.map(values, fn value -> Map.get(position_by_level, value) end)
  end
end
