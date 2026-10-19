defmodule Giggly.Scale.Transform do
  @moduledoc false

  # The transformation a continuous scale puts its values through before it trains on them: R's
  # `scales` transformation objects (`new_transform()`), which ggplot2's continuous scales hold as
  # their `transform`. A scale records its transformation by name, and the name is resolved here.
  #
  # A transformation carries what R's object carries and a scale reads: the transformation and its
  # inverse, its domain, and its axis's default breaks, minor breaks and labels (R's `breaks`,
  # `minor_breaks` and `format`): a log axis wants powers of ten, a date axis calendar dates.
  #
  # Each is a module implementing this behaviour: the identity (`Transform.Identity`), which a
  # continuous scale of numbers records, as ggplot2's continuous scales default to
  # `transform = "identity"`; the date transformation (`Transform.Date`), which a scale of dates
  # records; and log10, square root, reverse and reciprocal (`Transform.Log10`, `Transform.Sqrt`,
  # `Transform.Reverse`, `Transform.Reciprocal`), which a plot's scale names. Each finds its
  # breaks as ggplot2's `get_breaks()` does, on the extent turned back into data units, and returns
  # them transformed, in the order that leaves them, so a reversing transformation's descend; its
  # labels are written from the breaks turned back. A default break's label may depend on the
  # extent as well as the break, as a date's format does on the step chosen for the whole axis, so
  # `format/2` is handed both, or `:given` for breaks it did not choose, which a date writes in
  # full.

  alias Giggly.Scale.Transform

  @typedoc "A transformation's name, as a continuous scale records it."
  @type name :: :identity | :date | :log10 | :sqrt | :reverse | :reciprocal

  @typedoc "The low end of a domain: a number, or none."
  @type domain_low :: number() | :neg_infinity

  # The values in transformed space: a number, `nil`, `:infinity` or `:neg_infinity` each, a value
  # outside the domain `nil`, as R's NaN is missing.
  @doc false
  @callback transform(values :: list()) :: list()

  # Positions turned back into data units.
  @doc false
  @callback inverse(positions :: [number()]) :: list()

  # The domain in transformed space, R's `transform(domain)` sorted, which an extent is squished
  # into before its breaks are found.
  @doc false
  @callback domain() :: {domain_low(), :infinity}

  # The breaks of an axis showing `extent`, in transformed space, in the transformation's order;
  # some may fall outside it.
  @doc false
  @callback breaks(extent :: {float(), float()}) :: [float()]

  # The minor breaks between `breaks` on an axis showing `extent`; the breaks themselves may be
  # among them, and some may fall outside the extent.
  @doc false
  @callback minor_breaks(breaks :: [float()], extent :: {float(), float()}) :: [float()]

  # Each break's label, in the order given: the transformation's own breaks on an axis showing
  # `extent`, or, for `:given`, breaks a plot gave or a width laid.
  @doc false
  @callback format(breaks :: [float()], extent :: {float(), float()} | :given) :: [String.t()]

  # The values put through the transformation named `name`.
  @doc false
  @spec transform(name(), list()) :: list()
  def transform(name, values), do: module(name).transform(values)

  # Positions turned back into data units by the transformation named `name`.
  @doc false
  @spec inverse(name(), [number()]) :: list()
  def inverse(name, positions), do: module(name).inverse(positions)

  # `extent` squished into the domain of the transformation named `name`, as ggplot2's
  # `get_breaks()` squishes its limits with `oob_squish()` before finding breaks: each end below
  # the domain moved up to it. No domain has an upper end yet.
  @doc false
  @spec squish(name(), {float(), float()}) :: {float(), float()}
  def squish(name, {low, high}) do
    {domain_low, :infinity} = module(name).domain()
    {squished(low, domain_low), squished(high, domain_low)}
  end

  # The default breaks of an axis showing `extent` under the transformation named `name`.
  @doc false
  @spec breaks(name(), {float(), float()}) :: [float()]
  def breaks(name, extent), do: module(name).breaks(extent)

  # The default minor breaks between `breaks` on an axis showing `extent` under the transformation
  # named `name`.
  @doc false
  @spec minor_breaks(name(), [float()], {float(), float()}) :: [float()]
  def minor_breaks(name, breaks, extent), do: module(name).minor_breaks(breaks, extent)

  # The default labels of `breaks` under the transformation named `name`: its own breaks on an axis
  # showing `extent`, or, for `:given`, breaks it did not choose.
  @doc false
  @spec format(name(), [float()], {float(), float()} | :given) :: [String.t()]
  def format(name, breaks, extent), do: module(name).format(breaks, extent)

  defp module(:identity), do: Transform.Identity
  defp module(:date), do: Transform.Date
  defp module(:log10), do: Transform.Log10
  defp module(:sqrt), do: Transform.Sqrt
  defp module(:reverse), do: Transform.Reverse
  defp module(:reciprocal), do: Transform.Reciprocal

  defp squished(value, low) when is_number(low) and value < low, do: low / 1
  defp squished(value, _low), do: value
end
