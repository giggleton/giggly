defmodule Giggly.Scale.Discrete do
  @moduledoc """
  A trained discrete position scale, as `Giggly.panel_scales/2` returns it: the distinct values it
  has seen, in level order.
  """

  # Use it through `Giggly.Scale`.

  @enforce_keys [:levels]
  defstruct @enforce_keys

  @type t :: %__MODULE__{levels: list()}

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
