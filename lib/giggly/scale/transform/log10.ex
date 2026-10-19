defmodule Giggly.Scale.Transform.Log10 do
  @moduledoc false

  # The base-10 logarithm, R's `transform_log10()`. Use it through `Giggly.Scale.Transform`.
  #
  # A positive number becomes its logarithm, zero minus infinity, as R's `log10(0)` is `-Inf`, and
  # a negative number missing, R's NaN; plus infinity stays itself. Its domain is R's, 1e-100 up,
  # so an axis reaching below 10^-100 finds its breaks from there.
  #
  # Its breaks are R's `breaks_log()`, five wanted (`log_breaks/1`): the powers of ten at or around
  # the data's range, every one, or every second, third and so on, the widest step that leaves at
  # least three inside the range; where no step does, R's `log_sub_breaks()` adds multiples of
  # each power, one at a time, each the one that keeps the steps evenest in log space (3 first,
  # nearest the middle of a decade), until three fall inside; and where even nine multiples
  # leave fewer than three, extended Wilkinson breaks on the range itself. Its minor breaks are
  # R's regular ones in log space, and its labels the breaks in data units, plain decimals
  # (`Giggly.Scale.Labels`).

  @behaviour Giggly.Scale.Transform

  alias Giggly.Scale.{Breaks, Labels, MinorBreaks}

  # How many breaks R's `breaks_log()` asks for, and how many fewer it settles for.
  @wanted 5
  @enough @wanted - 2

  # The multiples `log_sub_breaks()` adds to each power, the first always there.
  @multiples Enum.to_list(2..9)

  @impl Giggly.Scale.Transform
  def transform(values), do: Enum.map(values, &log10/1)

  @impl Giggly.Scale.Transform
  def inverse(positions), do: Enum.map(positions, &power/1)

  @impl Giggly.Scale.Transform
  def domain, do: {-100.0, :infinity}

  # The breaks found on the extent in data units, then put back into log space.
  @impl Giggly.Scale.Transform
  def breaks({low, high}) do
    {power(low), power(high)}
    |> log_breaks()
    |> transform()
  end

  @impl Giggly.Scale.Transform
  def minor_breaks(breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Giggly.Scale.Transform
  def format(breaks, _extent) do
    breaks
    |> inverse()
    |> Labels.numbers()
  end

  defp log10(value) when is_number(value) and value > 0, do: :math.log10(value)
  defp log10(value) when value == 0, do: :neg_infinity
  defp log10(:infinity), do: :infinity
  defp log10(_negative_or_missing), do: nil

  defp power(exponent), do: :math.pow(10.0, exponent)

  # R's `breaks_log(n = 5, base = 10)` on a range in data units, as its closure runs. R returns one
  # power where both ends round to it, which only an extent of zero width does, and that is
  # answered before any transformation's breaks are asked for.
  defp log_breaks({data_low, data_high}) do
    low = :math.log10(data_low)
    high = :math.log10(data_high)
    first = Float.floor(low)
    last = Float.ceil(high)
    step = trunc(Float.floor((last - first) / @wanted)) + 1
    every_power(first, last, step, {low, high})
  end

  # Every `step`th power from `first` to `last`, or a smaller step's, while it leaves fewer than
  # three inside the range; with a step of one too few, the multiples in between.
  defp every_power(first, last, step, range) do
    breaks =
      first
      |> exponents(last, step)
      |> Enum.map(&power/1)

    cond do
      inside_count(breaks, range) >= @enough -> breaks
      step > 1 -> every_power(first, last, step - 1, range)
      true -> sub_breaks(first, last, range)
    end
  end

  # R's `seq(first, last, by = step)`, whole numbers apart.
  defp exponents(first, last, step) do
    count = trunc((last - first) / step)
    Enum.map(0..count, fn index -> first + index * step end)
  end

  # R's `log_sub_breaks()`: multiples added to each power, one at a time, until three fall inside
  # the range, all of them in order; or, failing that, extended Wilkinson breaks on the range in
  # data units. R keeps only those inside and one more each side, which the scale drops with
  # every break outside the extent.
  defp sub_breaks(first, last, range) do
    case add_multiples([1], @multiples, first, last, range) do
      {:enough, breaks} -> Enum.sort(breaks)
      :too_few -> extended(range)
    end
  end

  defp add_multiples(_steps, [], _first, _last, _range), do: :too_few

  defp add_multiples(steps, candidates, first, last, range) do
    best = Enum.max_by(candidates, fn candidate -> evenness([candidate | steps]) end)
    added = Enum.concat(steps, [best])

    breaks =
      for multiple <- added, exponent <- exponents(first, last, 1) do
        power(exponent) * multiple
      end

    if inside_count(breaks, range) >= @enough,
      do: {:enough, breaks},
      else: add_multiples(added, List.delete(candidates, best), first, last, range)
  end

  # The smallest gap in log space between the multiples and ten, R's `delta()`.
  defp evenness(multiples) do
    [10 | multiples]
    |> Enum.sort()
    |> Enum.map(&:math.log10/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [lower, upper] -> upper - lower end)
    |> Enum.min()
  end

  defp extended({low, high}), do: Breaks.extended({power(low), power(high)})

  defp inside_count(breaks, {low, high}),
    do: Enum.count(breaks, fn value -> power(low) <= value and value <= power(high) end)
end
