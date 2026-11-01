defmodule Scales.Transform do
  @moduledoc """
  The transformation a continuous scale puts its values through before it trains on them, named
  by a value (`t:name/0`): values into transformed space (`transform/2`) and back
  (`inverse/2`), and an axis's default breaks (`breaks/3`), minor breaks (`minor_breaks/3`) and
  labels (`format/3`) there, as R's transformation objects carry them; for a transformation of
  numbers, also the derivatives both ways (`derivative/2`, `inverse_derivative/2`) and the range
  data takes in transformed space (`trim_to_domain/2`).

  Breaks are found as on an axis showing an extent in transformed space: the extent is squished
  into the transformation's domain (`squish/2`), turned back into data units and broken there,
  and the breaks transformed back, in the order that leaves them, so a reversing transformation's
  descend. Some may fall outside the extent; which to keep is the caller's. Labels are written
  from the breaks turned back, `10^x` under log10; a date's depend on the step chosen for the
  whole axis, so `format/3` is handed the extent too. A date, date-time or time transformation
  also lays breaks a calendar or clock step apart (`width/3`).

  A value the transformation cannot place, below log10's or the square root's domain, becomes
  `:nan`, R's `NaN`; a value placed at an infinity is `:infinity` or `:neg_infinity`, and a
  missing one stays `nil`.
  """

  # The transformation a continuous scale puts its values through before it trains on them: R's
  # `scales` transformation objects (`new_transform()`), which ggplot2's continuous scales hold as
  # their `transform`. A scale records its transformation by name, and the name is resolved here.
  #
  # A transformation carries what R's object carries and a scale reads: the transformation and its
  # inverse, its domain, and its axis's default breaks, minor breaks and labels (R's `breaks`,
  # `minor_breaks` and `format`): a log axis wants powers of ten, a date axis calendar dates. One
  # of numbers carries its derivatives too (R's `d_transform` and `d_inverse`), which the date,
  # date-time and time transformations have none of, as R's have none.
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

  alias Scales.{Bounds, Double, Transform}

  @breaks_options NimbleOptions.new!(
                    n: [
                      type: :non_neg_integer,
                      doc:
                        "The number of breaks wanted, five when not given, for every " <>
                          "transformation but `:time`: from 2 for the identity, square root, " <>
                          "reverse and reciprocal, from 1 for log10, and from 0 for dates and " <>
                          "date-times, as R's own breaks take it."
                    ]
                  )

  @typedoc """
  A transformation, by name: `:identity`, R's `transform_identity()`; `:log10`, `:sqrt`,
  `:reverse` (each value negated) and `:reciprocal`, R's `transform_log10()` and its kin; `:date`,
  a `Date` as its days since 1970-01-01, R's `transform_date()`; `{:datetime, zone, database}`, a
  `DateTime` or `NaiveDateTime` as its seconds since 1970-01-01 00:00 UTC, its breaks laid on
  the clock of `zone`, read by the time zone database `database`, R's `transform_time(tz)`, the
  zone `:default` until a column settles it and `:naive` for naive date-times; and `:time`, a
  `Time` as its seconds since midnight, R's `transform_hms()`.
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

  # The date, date-time and time transformations, whose data are not numbers; the date-time one
  # is the only name a tuple.
  defguardp is_temporal(name) when name in [:date, :time] or is_tuple(name)

  # The values in transformed space: a number, `nil`, `:infinity`, `:neg_infinity` or `:nan` each,
  # a value outside the domain `:nan`, R's NaN.
  @doc false
  @callback transform(transformation :: name(), values :: list()) :: list()

  # Positions turned back into data units.
  @doc false
  @callback inverse(transformation :: name(), positions :: [number()]) :: list()

  # The domain in data units, R's `domain`: `{:neg_infinity, :infinity}` for one that bounds
  # nothing, every date for the date transformation.
  @doc false
  @callback domain(transformation :: name()) :: Scales.Bounds.range()

  # The breaks of an axis showing `extent`, in transformed space, in the transformation's order;
  # some may fall outside it. `options` are `breaks/3`'s, validated, and always `[]` for the time
  # transformation, which counts no breaks.
  @doc false
  @callback breaks(transformation :: name(), extent :: {float(), float()}, options :: keyword()) ::
              [float()]

  # The minor breaks between `breaks` on an axis showing `extent`; the breaks themselves may be
  # among them, and some may fall outside the extent.
  @doc false
  @callback minor_breaks(
              transformation :: name(),
              breaks :: [float()],
              extent :: {float(), float()}
            ) :: [float()]

  # The derivative of the transformation at each value, and of its inverse at each position, R's
  # `d_transform` and `d_inverse`, each a double (`t:Scales.double/0`) taken as R's arithmetic
  # takes it. A transformation of numbers alone has them.
  @doc false
  @callback derivative(transformation :: name(), values :: [Scales.double()]) ::
              [Scales.double()]

  @doc false
  @callback inverse_derivative(transformation :: name(), positions :: [Scales.double()]) ::
              [Scales.double()]

  @optional_callbacks derivative: 2, inverse_derivative: 2

  # Each break's label, in the order given: the transformation's own breaks on an axis showing
  # `extent`, found with `options`, `breaks/3`'s, validated, or, for `:given`, breaks a plot gave
  # or a width laid.
  @doc false
  @callback format(
              transformation :: name(),
              breaks :: [float()],
              extent :: {float(), float()} | :given,
              options :: keyword()
            ) :: [String.t()]

  @doc """
  The values put through the transformation `name`.

  ## Examples

      iex> Scales.Transform.transform(:log10, [1, 10, 100, 0, -1, nil])
      [0.0, 1.0, 2.0, :neg_infinity, :nan, nil]

      iex> Scales.Transform.transform(:date, [~D[1970-01-11], nil])
      [10.0, nil]
  """
  @spec transform(name(), list()) :: list()
  def transform(name, values), do: module(name).transform(name, values)

  @doc """
  Positions in transformed space turned back into data units by the transformation `name`.

  ## Examples

      iex> Scales.Transform.inverse(:log10, [0.0, 1.0, 2.0])
      [1.0, 10.0, 100.0]
  """
  @spec inverse(name(), [number()]) :: list()
  def inverse(name, positions), do: module(name).inverse(name, positions)

  # As ggplot2's `get_breaks()` squishes its limits with `oob_squish()` into the domain
  # transformed. A domain that bounds nothing squishes nothing: transformed, its ends are the
  # infinities or, the reciprocal's, two zeros, a domain of no width, which R leaves unsquished.
  # Every transformation with a bounded domain rises, so its transformed ends need no sorting.
  @doc """
  The extent `{low, high}`, in transformed space, squished into the domain of the transformation
  `name`, transformed: each end outside it moved onto it, as R's `oob_squish()` moves it, so
  log10's breaks are not sought below `-100`.

  ## Examples

      iex> Scales.Transform.squish(:log10, {-200.0, 2.0})
      {-100.0, 2.0}
  """
  @spec squish(name(), {float(), float()}) :: {float(), float()}
  def squish(name, extent) do
    case module(name).domain(name) do
      {:neg_infinity, :infinity} -> extent
      domain -> squished(extent, transform(name, Tuple.to_list(domain)))
    end
  end

  defp squished({low, high}, [domain_low, domain_high]) do
    [squished_low, squished_high] = Bounds.squish([low, high], {domain_low, domain_high})
    {squished_low, squished_high}
  end

  @doc """
  The range `values` take in transformed space under the transformation `name`, R's
  `trim_to_domain()`: their range, `nil` and `:nan` left out, squished into the domain and its
  ends transformed, as `{low, high}`; `:none` with no value to range over, where R warns. Only a
  transformation of numbers takes one: a date's, date-time's or time's raises
  `FunctionClauseError`.

  The range is taken before the transformation, so the reciprocal of a range across zero is the
  reciprocals of its ends, and an infinity is kept, not squished, so one outside the domain
  transforms to `:nan`, which makes both ends `:nan`, as R's `range()` makes them.

  ## Examples

      iex> Scales.Transform.trim_to_domain(:log10, [-5, 0, 10, 1000, nil])
      {-100.0, 3.0}

      iex> Scales.Transform.trim_to_domain(:reciprocal, [-5, 0, 10, 1000])
      {-0.2, 0.001}

      iex> Scales.Transform.trim_to_domain(:log10, [:neg_infinity, 5])
      {:nan, :nan}

      iex> Scales.Transform.trim_to_domain(:sqrt, [nil, :nan])
      :none
  """
  @spec trim_to_domain(name(), [Scales.double()]) :: {Scales.double(), Scales.double()} | :none
  def trim_to_domain(name, values) when not is_temporal(name) do
    case Enum.reduce(values, :none, &widened/2) do
      :none -> :none
      {low, high} -> trimmed(name, [low, high])
    end
  end

  # A range widened to cover a value, R's `range(na.rm = TRUE)`: each end kept where the value
  # is not beyond it, so of `-0.0` and `0.0` the first is both ends, as R's.
  defp widened(value, range) when value in [nil, :nan], do: range
  defp widened(value, :none), do: {value, value}

  defp widened(value, {low, high}),
    do: {Double.minimum(low, value), Double.maximum(high, value)}

  defp trimmed(name, ends) do
    [first, last] = transform(name, Bounds.squish(ends, module(name).domain(name)))
    {Double.minimum(first, last), Double.maximum(first, last)}
  end

  @doc """
  The derivative of the transformation `name` at each of `values`, R's `d_transform`, each a
  double (`t:Scales.double/0`), its infinities and NaN as R's arithmetic gives them. Only a
  transformation of numbers has one: a date's, date-time's or time's raises
  `FunctionClauseError`.

  ## Examples

      iex> Scales.Transform.derivative(:sqrt, [0.25, 0, -1, nil])
      [1.0, :infinity, :nan, nil]

      iex> Scales.Transform.derivative(:identity, [3, nil])
      [1.0, 1.0]
  """
  @spec derivative(name(), [Scales.double()]) :: [Scales.double()]
  def derivative(name, values) when not is_temporal(name),
    do: module(name).derivative(name, values)

  @doc """
  The derivative of the inverse of the transformation `name` at each of `positions`, in
  transformed space, R's `d_inverse`, as `derivative/2` gives the transformation's.

  ## Examples

      iex> Scales.Transform.inverse_derivative(:sqrt, [0.5, -2, :infinity])
      [1.0, -4.0, :infinity]
  """
  @spec inverse_derivative(name(), [Scales.double()]) :: [Scales.double()]
  def inverse_derivative(name, positions) when not is_temporal(name),
    do: module(name).inverse_derivative(name, positions)

  @doc """
  The default breaks, in transformed space, of an axis showing `extent` under the transformation
  `name`, in the order the transformation leaves them: extended breaks (`Scales.Breaks`) on the
  extent in data units, powers of ten under log10, calendar dates under the date
  transformation and clock times under the date-time one, as R's `pretty()` finds them, and
  spans of time under the time one, as `Scales.Breaks.timespan/2` finds them.

  `n:` asks for that many: of `Scales.Breaks.extended/2` under the identity, square root, reverse
  and reciprocal transformations, of `Scales.Breaks.log/2` under log10, and of R's `pretty()`
  under the date and date-time ones. The time transformation counts no breaks, as R's takes no
  number, and raises `ArgumentError` for it; `Scales.Breaks.timespan/2` takes one.

  ## Options

  #{NimbleOptions.docs(@breaks_options)}

  ## Examples

      iex> Scales.Transform.breaks(:identity, {9.225, 35.075})
      [10.0, 15.0, 20.0, 25.0, 30.0, 35.0]

      iex> Scales.Transform.breaks(:identity, {9.225, 35.075}, n: 10)
      [10.0, 12.5, 15.0, 17.5, 20.0, 22.5, 25.0, 27.5, 30.0, 32.5, 35.0]

      iex> Scales.Transform.breaks(:log10, {0.0, 3.0})
      [0.0, 1.0, 2.0, 3.0]

      iex> Scales.Transform.breaks(:log10, {0.0, 6.0}, n: 2)
      [0.0, 4.0]
  """
  @spec breaks(name(), {float(), float()}, keyword()) :: [float()]
  def breaks(name, extent, options \\ []) do
    validated = counted!(name, options)
    module(name).breaks(name, extent, validated)
  end

  # The options validated, but for the time transformation, which counts no breaks, as R's
  # `transform_hms()` takes no number.
  defp counted!(name, options) do
    case NimbleOptions.validate!(options, @breaks_options) do
      [] ->
        []

      validated when name == :time ->
        raise ArgumentError,
              "the :time transformation counts no breaks, so it takes no " <>
                "#{inspect(Keyword.keys(validated))}; Scales.Breaks.timespan/2 takes a number " <>
                "of breaks between seconds"

      validated ->
        validated
    end
  end

  @doc """
  The default minor breaks between `breaks` on an axis showing `extent` under the transformation
  `name`, in transformed space: `Scales.MinorBreaks.regular/3`'s, reversed for `:reverse`.

  ## Examples

      iex> Scales.Transform.minor_breaks(:identity, [10.0, 20.0, 30.0], {5.0, 35.0})
      [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0]
  """
  @spec minor_breaks(name(), [float()], {float(), float()}) :: [float()]
  def minor_breaks(name, breaks, extent), do: module(name).minor_breaks(name, breaks, extent)

  @doc """
  The default labels of `breaks`, in transformed space, under the transformation `name`: its own
  breaks on an axis showing `extent`, found with `options`, `breaks/3`'s, or, for `:given`, breaks
  it did not choose. A number's are `Scales.Labels.plain/1`'s, written from the breaks turned
  back; a date's in the format of the step its breaks were chosen at, so a date's or date-time's
  breaks found with `n:` are labelled when given the same `n:`, and a given date written in full.

  ## Options

  `breaks/3`'s.

  ## Examples

      iex> Scales.Transform.format(:log10, [0.0, 1.0, 2.0], {0.0, 2.0})
      ["1", "10", "100"]

      iex> extent = {19723.0, 19726.0}
      iex> Scales.Transform.format(:date, Scales.Transform.breaks(:date, extent), extent)
      ["Dec 31", "Jan 01", "Jan 02", "Jan 03", "Jan 04", "Jan 05"]

      iex> Scales.Transform.format(:date, [19723.0], :given)
      ["2024-01-01"]

      iex> extent = {18262.0, 18993.0}
      iex> breaks = Scales.Transform.breaks(:date, extent, n: 20)
      iex> :date |> Scales.Transform.format(breaks, extent, n: 20) |> Enum.take(3)
      ["Jan 2020", "Feb 2020", "Mar 2020"]
  """
  @spec format(name(), [float()], {float(), float()} | :given, keyword()) :: [String.t()]
  def format(name, breaks, extent, options \\ []) do
    validated = counted!(name, options)
    module(name).format(name, breaks, extent, validated)
  end

  @doc """
  The breaks a step lays, written as `Date.shift/2` takes one (`[week: 2]`), on an axis showing
  `extent` under the date, date-time or time transformation `name`, in transformed space, some
  outside it, as R's `breaks_width()` lays them: from the extent's start rounded down to the
  step's unit (a week to its Monday), every step. Only those three transformations have steps.

  ## Examples

      iex> Scales.Transform.width(:date, [week: 2], {19723.0, 19750.0})
      [19723.0, 19737.0, 19751.0]
  """
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
end
