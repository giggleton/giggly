defmodule Scales.Transform do
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
  # records; the date-time transformation (`Transform.Datetime`), which a scale of date-times
  # records with its time zone and the database that reads it, `{:datetime, zone, database}`, as
  # R's `transform_time(tz)` holds its zone; the time-of-day transformation (`Transform.Time`),
  # which a scale of times records, as ggplot2's `scale_x_time()` records `transform_hms()`; and
  # log10, square root, reverse and reciprocal (`Transform.Log10`, `Transform.Sqrt`,
  # `Transform.Reverse`, `Transform.Reciprocal`), which a plot's scale names. Every callback is
  # handed the transformation as the scale records it, so one that holds more than its name reads
  # it, as R's object's functions close over theirs. Each finds its
  # breaks as ggplot2's `get_breaks()` does, on the extent turned back into data units, and returns
  # them transformed, in the order that leaves them, so a reversing transformation's descend; its
  # labels are written from the breaks turned back. A default break's label may depend on the
  # extent as well as the break, as a date's format does on the step chosen for the whole axis, so
  # `format/2` is handed both, or `:given` for breaks it did not choose, which a date writes in
  # full.

  alias Scales.Transform

  @typedoc """
  A transformation as a continuous scale records it: its name, or the date-time transformation
  with its time zone, `:default` until a column settles it and `:naive` for naive date-times, and
  the time zone database that reads the zone.
  """
  @type name ::
          :identity
          | :date
          | {:datetime, String.t() | :default | :naive, module()}
          | :time
          | :log10
          | :sqrt
          | :reverse
          | :reciprocal

  @typedoc "The low end of a domain: a number, or none."
  @type domain_low :: number() | :neg_infinity

  # The values in transformed space: a number, `nil`, `:infinity` or `:neg_infinity` each, a value
  # outside the domain `nil`, as R's NaN is missing.
  @doc false
  @callback transform(transformation :: name(), values :: list()) :: list()

  # Positions turned back into data units.
  @doc false
  @callback inverse(transformation :: name(), positions :: [number()]) :: list()

  # The domain in transformed space, R's `transform(domain)` sorted, which an extent is squished
  # into before its breaks are found.
  @doc false
  @callback domain(transformation :: name()) :: {domain_low(), :infinity}

  # The breaks of an axis showing `extent`, in transformed space, in the transformation's order;
  # some may fall outside it.
  @doc false
  @callback breaks(transformation :: name(), extent :: {float(), float()}) :: [float()]

  # The minor breaks between `breaks` on an axis showing `extent`; the breaks themselves may be
  # among them, and some may fall outside the extent.
  @doc false
  @callback minor_breaks(
              transformation :: name(),
              breaks :: [float()],
              extent :: {float(), float()}
            ) :: [float()]

  # Each break's label, in the order given: the transformation's own breaks on an axis showing
  # `extent`, or, for `:given`, breaks a plot gave or a width laid.
  @doc false
  @callback format(
              transformation :: name(),
              breaks :: [float()],
              extent :: {float(), float()} | :given
            ) :: [String.t()]

  # The values put through the transformation named `name`.
  @doc false
  @spec transform(name(), list()) :: list()
  def transform(name, values), do: module(name).transform(name, values)

  # Positions turned back into data units by the transformation named `name`.
  @doc false
  @spec inverse(name(), [number()]) :: list()
  def inverse(name, positions), do: module(name).inverse(name, positions)

  # `extent` squished into the domain of the transformation named `name`, as ggplot2's
  # `get_breaks()` squishes its limits with `oob_squish()` before finding breaks: each end below
  # the domain moved up to it. No domain has an upper end yet.
  @doc false
  @spec squish(name(), {float(), float()}) :: {float(), float()}
  def squish(name, {low, high}) do
    {domain_low, :infinity} = module(name).domain(name)
    {squished(low, domain_low), squished(high, domain_low)}
  end

  # The default breaks of an axis showing `extent` under the transformation named `name`.
  @doc false
  @spec breaks(name(), {float(), float()}) :: [float()]
  def breaks(name, extent), do: module(name).breaks(name, extent)

  # The default minor breaks between `breaks` on an axis showing `extent` under the transformation
  # named `name`.
  @doc false
  @spec minor_breaks(name(), [float()], {float(), float()}) :: [float()]
  def minor_breaks(name, breaks, extent), do: module(name).minor_breaks(name, breaks, extent)

  # The default labels of `breaks` under the transformation named `name`: its own breaks on an axis
  # showing `extent`, or, for `:given`, breaks it did not choose.
  @doc false
  @spec format(name(), [float()], {float(), float()} | :given) :: [String.t()]
  def format(name, breaks, extent), do: module(name).format(name, breaks, extent)

  # The breaks a step lays, `[week: 1]`, on an axis showing `extent` under the date, date-time or
  # time-of-day transformation `name`, in transformed space, some outside it: only those three
  # have steps, which a plot's date, date-time and time scales record as a width.
  @doc false
  @spec width(
          :date | {:datetime, term(), module()} | :time,
          keyword(pos_integer()),
          {float(), float()}
        ) :: [float()]
  def width(:date = name, step, extent), do: Transform.Date.width(name, step, extent)

  def width({:datetime, _zone, _database} = name, step, extent),
    do: Transform.Datetime.width(name, step, extent)

  def width(:time = name, step, extent), do: Transform.Time.width(name, step, extent)

  defp module(:identity), do: Transform.Identity
  defp module(:date), do: Transform.Date
  defp module({:datetime, _zone, _database}), do: Transform.Datetime
  defp module(:time), do: Transform.Time
  defp module(:log10), do: Transform.Log10
  defp module(:sqrt), do: Transform.Sqrt
  defp module(:reverse), do: Transform.Reverse
  defp module(:reciprocal), do: Transform.Reciprocal

  defp squished(value, low) when is_number(low) and value < low, do: low / 1
  defp squished(value, _low), do: value
end
