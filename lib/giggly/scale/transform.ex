defmodule Giggly.Scale.Transform do
  @moduledoc false

  # The transformation a continuous scale puts its values through before it trains on them: R's
  # `scales` transformation objects (`new_transform()`), which ggplot2's continuous scales hold as
  # their `transform`. A scale records its transformation by name, and the name is resolved here.
  #
  # A transformation also carries its axis's default breaks, minor breaks and labels, as R's object
  # carries `breaks`, `minor_breaks` and `format`: a log axis wants powers of ten, a date axis
  # calendar dates.
  #
  # There are two so far: the identity (`Giggly.Scale.Transform.Identity`), which a continuous
  # scale of numbers records, as ggplot2's continuous scales default to `transform = "identity"`,
  # and the date transformation (`Giggly.Scale.Transform.Date`), R's `transform_date()`, which a
  # scale of dates records. Each is a module implementing this behaviour. A break's label may
  # depend on the extent as well as the break, as a date's format does on the step chosen for the
  # whole axis, so `format/2` is handed both. What else R's object carries (the inverse, the
  # domain) joins the behaviour with its first reader outside a transformation: the date
  # transformation finds its breaks in days and turns them back into dates itself.

  alias Giggly.Scale.Transform

  @typedoc "A transformation's name, as a continuous scale records it."
  @type name :: :identity | :date

  # The values in transformed space.
  @doc false
  @callback transform(values :: list()) :: list()

  # The breaks of an axis showing `extent`, ascending; some may fall outside it.
  @doc false
  @callback breaks(extent :: {float(), float()}) :: [float()]

  # The minor breaks between `breaks` on an axis showing `extent`, ascending; the breaks themselves
  # may be among them, and some may fall outside the extent.
  @doc false
  @callback minor_breaks(breaks :: [float()], extent :: {float(), float()}) :: [float()]

  # Each break's label, in the order given, on an axis showing `extent`.
  @doc false
  @callback format(breaks :: [float()], extent :: {float(), float()}) :: [String.t()]

  # The values put through the transformation named `name`.
  @doc false
  @spec transform(name(), list()) :: list()
  def transform(:identity, values), do: Transform.Identity.transform(values)
  def transform(:date, values), do: Transform.Date.transform(values)

  # The default breaks of an axis showing `extent` under the transformation named `name`.
  @doc false
  @spec breaks(name(), {float(), float()}) :: [float()]
  def breaks(:identity, extent), do: Transform.Identity.breaks(extent)
  def breaks(:date, extent), do: Transform.Date.breaks(extent)

  # The default minor breaks between `breaks` on an axis showing `extent` under the transformation
  # named `name`.
  @doc false
  @spec minor_breaks(name(), [float()], {float(), float()}) :: [float()]
  def minor_breaks(:identity, breaks, extent), do: Transform.Identity.minor_breaks(breaks, extent)
  def minor_breaks(:date, breaks, extent), do: Transform.Date.minor_breaks(breaks, extent)

  # The default labels of `breaks` on an axis showing `extent` under the transformation named
  # `name`.
  @doc false
  @spec format(name(), [float()], {float(), float()}) :: [String.t()]
  def format(:identity, breaks, extent), do: Transform.Identity.format(breaks, extent)
  def format(:date, breaks, extent), do: Transform.Date.format(breaks, extent)
end
