defmodule Giggly.Scale.Transform do
  @moduledoc """
  The transformation a continuous scale puts its values through before it trains on them: R's
  `scales` transformation objects (`new_transform()`), which ggplot2's continuous scales hold as
  their `transform`. A scale records its transformation by name, and the name is resolved here.

  A transformation also carries its axis's default breaks, minor breaks and labels, as R's object
  carries `breaks`, `minor_breaks` and `format`: a log axis wants powers of ten, a date axis
  calendar dates.

  There is one transformation so far, the identity (`Giggly.Scale.Transform.Identity`), which
  every continuous scale records until a plot can choose another, as ggplot2's continuous scales
  default to `transform = "identity"`. Each transformation is a module implementing this
  behaviour; what else R's object carries (the inverse, the domain) joins the behaviour with its
  first reader.
  """

  alias Giggly.Scale.Transform

  @typedoc "A transformation's name, as a continuous scale records it."
  @type name :: :identity

  @doc "The values in transformed space."
  @callback transform(values :: list()) :: list()

  @doc "The breaks of an axis showing `extent`, ascending; some may fall outside it."
  @callback breaks(extent :: {float(), float()}) :: [float()]

  @doc """
  The minor breaks between `breaks` on an axis showing `extent`, ascending; the breaks themselves
  may be among them, and some may fall outside the extent.
  """
  @callback minor_breaks(breaks :: [float()], extent :: {float(), float()}) :: [float()]

  @doc "Each break's label, in the order given."
  @callback format(breaks :: [float()]) :: [String.t()]

  @doc """
  The values put through the transformation named `name`.
  """
  @spec transform(name(), list()) :: list()
  def transform(:identity, values), do: Transform.Identity.transform(values)

  @doc """
  The default breaks of an axis showing `extent` under the transformation named `name`.
  """
  @spec breaks(name(), {float(), float()}) :: [float()]
  def breaks(:identity, extent), do: Transform.Identity.breaks(extent)

  @doc """
  The default minor breaks between `breaks` on an axis showing `extent` under the transformation
  named `name`.
  """
  @spec minor_breaks(name(), [float()], {float(), float()}) :: [float()]
  def minor_breaks(:identity, breaks, extent), do: Transform.Identity.minor_breaks(breaks, extent)

  @doc """
  The default labels of `breaks` under the transformation named `name`.
  """
  @spec format(name(), [float()]) :: [String.t()]
  def format(:identity, breaks), do: Transform.Identity.format(breaks)
end
