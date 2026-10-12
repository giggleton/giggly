defmodule Giggly.Scale.Transform do
  @moduledoc """
  The transformation a continuous scale puts its values through before it trains on them: R's
  `scales` transformation objects (`new_transform()`), which ggplot2's continuous scales hold as
  their `transform`. A scale records its transformation by name, and the name is resolved here.

  There is one transformation so far, the identity (`Giggly.Scale.Transform.Identity`), which
  every continuous scale records until a plot can choose another, as ggplot2's continuous scales
  default to `transform = "identity"`. Each transformation is a module implementing this
  behaviour; what else R's object carries (the inverse, the axis's default breaks and labels, the
  domain) joins the behaviour with its first reader.
  """

  alias Giggly.Scale.Transform

  @typedoc "A transformation's name, as a continuous scale records it."
  @type name :: :identity

  @doc "The values in transformed space."
  @callback transform(values :: list()) :: list()

  @doc """
  The values put through the transformation named `name`.
  """
  @spec transform(name(), list()) :: list()
  def transform(:identity, values), do: Transform.Identity.transform(values)
end
