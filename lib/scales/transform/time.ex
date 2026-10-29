defmodule Scales.Transform.Time do
  @moduledoc false

  # The time-of-day transformation, R's `transform_hms()`: a time as its seconds since midnight, a
  # double, as R's `hms` stores one, its whole microseconds divided once by a million; a missing
  # one missing. It is what a scale of times records, ggplot2's `scale_x_time()`. Use it through
  # `Scales.Transform`, and never alias it down to its last segment, which is Elixir's
  # `Time`.
  #
  # Its axis takes R's `breaks_hms()` breaks, `scales::breaks_timespan()` on seconds
  # (`Scales.Breaks.timespan/2`), five wanted, so they fall on round seconds, minutes or hours.
  # Its labels are written as hms writes a time: hours, minutes and seconds, two digits each at
  # least, the hours counting on past 24 and a time before midnight negative (`24:30:00`,
  # `-00:00:30`), with as many decimals of a second as the most precise break needs, up to six,
  # each break first rounded to the microsecond, half to even, as hms rounds it. Two of hms's
  # marks are left out (design-log §4, the entry beginning "A time of day's labels"): six zero
  # decimals on every label where a break is a rounding error off a whole second
  # (`10:24:00.000000`), and spaces padding every label to the widest. Breaks given or laid by a
  # width are written alike. Its minor breaks are R's regular ones on the seconds, midway between
  # them (`Scales.MinorBreaks`), as `transform_hms()` keeps the default. A break turned back
  # is a `Time` wrapped past midnight, so `24:00:00` is `~T[00:00:00]`, as R's `format()` of a time
  # as a date-time writes it, to the second where it is a whole second and else to the
  # microsecond.

  @behaviour Scales.Transform

  alias Scales.{Breaks, MinorBreaks}

  @microseconds 1_000_000
  @minute 60
  @hour 3600
  @day 86_400

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &seconds/1)

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &time/1)

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def breaks(_transformation, extent, []), do: Breaks.timespan(extent)

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent, _options) do
    counts = Enum.map(breaks, &microseconds/1)

    decimals =
      counts
      |> Enum.map(&decimals/1)
      |> Enum.max(fn -> 0 end)

    Enum.map(counts, fn count -> written(count, decimals) end)
  end

  # A break every step of `step`, one of a second, a minute and an hour and how many of it
  # (`[minute: 30]`), on an axis showing `extent`, in seconds since midnight, in ascending order,
  # some outside it: R's `breaks_width()` for times (`fullseq()` of a `difftime`), every multiple
  # of the step's seconds from the extent's start rounded down to one to its end rounded up, as
  # R's `round_any()` rounds them.
  @doc false
  @spec width(Scales.Transform.name(), keyword(pos_integer()), {float(), float()}) ::
          [float()]
  def width(_transformation, [{unit, count}], {low, high}) do
    size = count * step_seconds(unit)
    first = Float.floor(low / size) * size
    last = Float.ceil(high / size) * size
    steps = trunc((last - first) / size + 1.0e-10)
    Enum.map(0..steps//1, fn index -> min(first + index * size, last) end)
  end

  defp step_seconds(:second), do: 1
  defp step_seconds(:minute), do: @minute
  defp step_seconds(:hour), do: @hour

  # A time's seconds since midnight, a double as R's `hms` stores it.
  @doc false
  @spec seconds(Time.t() | nil) :: float() | nil
  def seconds(nil), do: nil

  def seconds(%Time{} = time) do
    {seconds, microseconds} = Time.to_seconds_after_midnight(time)
    (seconds * @microseconds + microseconds) / @microseconds
  end

  # The time of day a position names, wrapped past midnight.
  defp time(position) do
    count =
      position
      |> microseconds()
      |> Integer.mod(@day * @microseconds)

    fraction = rem(count, @microseconds)
    precision = if fraction == 0, do: 0, else: 6

    count
    |> div(@microseconds)
    |> Time.from_seconds_after_midnight({fraction, precision})
  end

  # A position's whole microseconds, as hms rounds it, half to even.
  defp microseconds(position) do
    scaled = position * @microseconds
    whole = Float.floor(scaled)
    fraction = scaled - whole
    count = trunc(whole)

    cond do
      fraction < 0.5 -> count
      fraction > 0.5 -> count + 1
      rem(count, 2) == 0 -> count
      true -> count + 1
    end
  end

  # The decimals of a second a count of microseconds needs: none for a whole second, else six less
  # the zeros its fraction ends in.
  defp decimals(count) do
    case rem(abs(count), @microseconds) do
      0 -> 0
      fraction -> 6 - trailing_zeros(fraction)
    end
  end

  defp trailing_zeros(number) when rem(number, 10) == 0, do: 1 + trailing_zeros(div(number, 10))
  defp trailing_zeros(_number), do: 0

  # A count of microseconds written as hms writes it, with `decimals` decimals of a second.
  defp written(count, decimals) do
    magnitude = abs(count)
    sign = if count < 0, do: "-", else: ""
    hours = div(magnitude, @hour * @microseconds)
    minutes = rem(div(magnitude, @minute * @microseconds), @minute)
    seconds = rem(div(magnitude, @microseconds), @minute)
    fraction = fraction(rem(magnitude, @microseconds), decimals)
    "#{sign}#{padded(hours, 2)}:#{padded(minutes, 2)}:#{padded(seconds, 2)}#{fraction}"
  end

  # A whole number written with at least `digits` digits, zeros leading.
  defp padded(number, digits) do
    number
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  defp fraction(_microseconds, 0), do: ""

  defp fraction(microseconds, decimals) do
    digits = padded(microseconds, 6)
    "." <> String.slice(digits, 0, decimals)
  end
end
