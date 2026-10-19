defmodule Giggly.Scale.Discrete do
  @moduledoc """
  A trained discrete scale, as `Giggly.panel_scales/2` returns an axis's. Its fields:

    * `levels`: the distinct values it has seen, in level order.
    * `continuous_range`: the range of the positions it has been handed since its levels were
      placed, such as a bar's edges, which can widen the axis past its levels; `:none` before any.
    * `palette`: what turns a level into its aesthetic's value: `:identity` for a position, each
      level at its place counting from 1; `{:sequence, {low, high}}` for an aesthetic such as
      alpha, the levels spread evenly from `low` to `high` in level order; and
      `{:hue, %{hue: {low, high}, chroma: chroma, luminance: luminance}}` for colour and fill, a
      colour for each level, its hue spaced evenly round the circle from `low`.
    * `na_value`: what a missing value maps to: `nil` for alpha, grey, `"#7F7F7F"`, for colour and
      fill. A missing value takes no share of the palette; a position scale puts it at its last
      level, and its `na_value` is `nil`.
    * `guide`: the guide that draws it: `:axis` for a position and `:legend` for an aesthetic such
      as alpha or colour.
  """

  # Use it through `Giggly.Scale`.

  alias Giggly.Scale.{Continuous, Palette}

  @enforce_keys [:levels, :continuous_range, :palette, :na_value, :guide]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          levels: list(),
          continuous_range: :none | {number(), number()},
          palette:
            :identity
            | {:sequence, {number(), number()}}
            | {:hue, %{hue: {number(), number()}, chroma: number(), luminance: number()}},
          na_value: nil | String.t(),
          guide: :axis | :legend
        }

  # The scale with the distinct `values` merged into its levels, as `Giggly.Scale.train/2`
  # describes.
  @doc false
  @spec train(t(), list()) :: t()
  def train(%__MODULE__{levels: levels} = scale, values) do
    merged =
      levels
      |> Enum.concat(values)
      |> Enum.uniq()
      |> Enum.sort_by(&Giggly.Scale.level_key/1)

    %{scale | levels: merged}
  end

  # The scale with its continuous range widened to cover the positions `values`, its levels left
  # alone, as `Giggly.Scale.train_positions/2` describes.
  @doc false
  @spec train_positions(t(), list()) :: t()
  def train_positions(%__MODULE__{continuous_range: range} = scale, values),
    do: %{scale | continuous_range: Continuous.train_range(range, values)}

  # Each value as `Giggly.Scale.map/2` describes: a position at its level's place counting from 1;
  # for any other palette, its level's value from the palette, which spreads the present levels,
  # `nil` taking none of them and mapping to the scale's `na_value`, as ggplot2's mapping gives `NA`
  # its `na.value`.
  @doc false
  @spec map(t(), list()) :: list()
  def map(%__MODULE__{levels: levels, palette: :identity}, values) do
    position_by_level =
      levels
      |> Enum.with_index(1)
      |> Map.new()

    Enum.map(values, fn value -> Map.get(position_by_level, value) end)
  end

  def map(%__MODULE__{levels: levels, palette: palette, na_value: na_value}, values) do
    present = Enum.reject(levels, &is_nil/1)

    value_by_level =
      present
      |> Enum.zip(Palette.discrete(palette, length(present)))
      |> Map.new()

    Enum.map(values, fn value -> Map.get(value_by_level, value, na_value) end)
  end
end
