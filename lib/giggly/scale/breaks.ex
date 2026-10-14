defmodule Giggly.Scale.Breaks do
  @moduledoc false

  # Where a continuous axis's breaks go: the extended Wilkinson algorithm of Talbot, Lin and
  # Hanrahan (2010), as R's `labeling::extended()` implements it and `scales::breaks_extended()`
  # calls it, with five breaks wanted, which is ggplot2's default for a continuous axis. Use it
  # through `Giggly.Scale`.
  #
  # It searches for the evenly spaced sequence that scores best on four counts, weighted 0.25,
  # 0.2, 0.5 and 0.05: simplicity (a step from the nice numbers 1, 5, 2, 2.5, 4 and 3 times a power
  # of ten, early in that list, and zero among the breaks), coverage (the sequence spans the range
  # without overshooting it far), density (close to the number of breaks wanted) and legibility
  # (which `labeling` scores as 1 for every sequence). The breaks may fall outside the range; the
  # caller decides what to keep.
  #
  # Three ranges are handled as R handles them. One narrower than 100 times the machine epsilon,
  # or wider than the square root of the largest float (where Elixir's arithmetic would overflow
  # rather than reach infinity), gets the number of breaks wanted spaced evenly from end to end. And
  # a best sequence whose span is within that tolerance of its ends' size, as on a narrow range of
  # large numbers, is its first break alone, as R's `seq()` returns it.
  #
  # R computes some intermediate steps in extended precision; here every step is a double, which
  # can differ only where a sum lands within rounding error of a whole multiple of the step. Over
  # 813 ranges, random and degenerate, it gives exactly R's breaks.

  # The number of breaks wanted: `scales::breaks_extended()`'s `n`.
  @wanted 5

  # `labeling::extended()`'s defaults: the nice numbers, in order of preference, and the weights of
  # simplicity, coverage, density and legibility.
  @nice_numbers [1, 5, 2, 2.5, 4, 3]
  @simplicity_weight 0.25
  @coverage_weight 0.2
  @density_weight 0.5
  @legibility_weight 0.05

  # `labeling`'s legibility score, the same for every sequence.
  @legibility 1

  # `labeling`'s tolerance: 100 times the double-precision machine epsilon.
  @epsilon 100 * 2.220446049250313e-16

  # R's `sqrt(.Machine$double.xmax)`, beyond which `labeling` stops searching.
  @widest_searched 1.340_780_792_994_259_6e154

  # The breaks of the extended Wilkinson sequence that scores best over `{low, high}`, `low` below
  # `high`, in ascending order: on an ordinary range a nice number of nice steps (`{9.225, 35.075}`
  # gives 10 to 35 by 5), and on the degenerate ranges what the comment above describes.
  @doc false
  @spec extended({float(), float()}) :: [float()]
  def extended({low, high}) when high - low < @epsilon or high - low > @widest_searched,
    do: spaced_evenly(low, high)

  def extended(range) do
    %{first: first, last: last, step: step} = search(range, 1, %{score: -2})
    sequence(first, last, step)
  end

  # The outer loop, over `j`, the number of steps a nice number is skipped by: it stops when no
  # nice number at this `j` could beat the best sequence so far even with perfect coverage and
  # density.
  defp search(range, skip, best) do
    case search_nice_numbers(range, skip, @nice_numbers, best) do
      {:halt, best} -> best
      {:cont, best} -> search(range, skip + 1, best)
    end
  end

  defp search_nice_numbers(_range, _skip, [], best), do: {:cont, best}

  defp search_nice_numbers(range, skip, [nice | rest], %{score: best_score} = best) do
    simplicity_bound = simplicity_max(nice, skip)

    if bound(simplicity_bound, 1, 1) < best_score do
      {:halt, best}
    else
      best = search_counts(range, skip, nice, simplicity_bound, 2, best)
      search_nice_numbers(range, skip, rest, best)
    end
  end

  # Over `k`, the number of breaks, until no count this large could win on density.
  defp search_counts({low, high} = range, skip, nice, simplicity_bound, count, best) do
    %{score: best_score} = best
    density_bound = density_max(count)

    if bound(simplicity_bound, 1, density_bound) < best_score do
      best
    else
      delta = (high - low) / (count + 1) / skip / nice
      power = ceil(:math.log10(delta))
      candidate = {skip, nice, simplicity_bound, count, density_bound}
      best = search_powers(range, candidate, power, best)
      search_counts(range, skip, nice, simplicity_bound, count + 1, best)
    end
  end

  # Over `z`, the power of ten the nice number is scaled by, until the step overshoots the range
  # by too much to cover it well.
  defp search_powers(range, candidate, power, best) do
    {skip, nice, simplicity_bound, count, density_bound} = candidate
    %{score: best_score} = best
    step = skip * nice * :math.pow(10, power)
    coverage_bound = coverage_max(range, step * (count - 1))

    if bound(simplicity_bound, coverage_bound, density_bound) < best_score do
      best
    else
      best =
        range
        |> starts(step, skip, count)
        |> Enum.reduce(best, fn start, best_so_far ->
          consider(range, candidate, step, start, best_so_far)
        end)

      search_powers(range, candidate, power + 1, best)
    end
  end

  # Where the sequence may start, counted in steps of `step / skip`, so that it can still reach the
  # range's top and start at or below its bottom.
  defp starts({low, high}, step, skip, count) do
    first = trunc(:math.floor(high / step) * skip - (count - 1) * skip)
    last = trunc(:math.ceil(low / step) * skip)
    if first > last, do: [], else: Enum.to_list(first..last//1)
  end

  defp consider(range, candidate, step, start, best) do
    {skip, nice, _simplicity_bound, count, _density_bound} = candidate
    %{score: best_score} = best
    first = start * (step / skip)
    last = first + step * (count - 1)

    score =
      @simplicity_weight * simplicity(nice, skip, first, last, step) +
        @coverage_weight * coverage(range, first, last) +
        @density_weight * density(count, range, first, last) +
        @legibility_weight * @legibility

    if score > best_score, do: %{score: score, first: first, last: last, step: step}, else: best
  end

  defp bound(simplicity, coverage, density) do
    @simplicity_weight * simplicity + @coverage_weight * coverage + @density_weight * density +
      @legibility_weight
  end

  # `.simplicity()`: earlier nice numbers and fewer skips score higher, and a sequence through zero
  # scores 1 more.
  defp simplicity(nice, skip, first, last, step) do
    remainder = modulo(first, step)

    through_zero =
      if (remainder < @epsilon or step - remainder < @epsilon) and first <= 0 and last >= 0,
        do: 1,
        else: 0

    1 - preference(nice) - skip + through_zero
  end

  defp simplicity_max(nice, skip), do: 1 - preference(nice) - skip + 1

  # A nice number's place in the list, from 0 for the first to 1 for the last.
  defp preference(nice) do
    index = Enum.find_index(@nice_numbers, fn candidate -> candidate == nice end)
    index / (length(@nice_numbers) - 1)
  end

  defp coverage({low, high}, first, last) do
    range = high - low
    1 - 0.5 * ((high - last) ** 2 + (low - first) ** 2) / (0.1 * range) ** 2
  end

  defp coverage_max({low, high}, span) do
    range = high - low

    if span > range do
      half = (span - range) / 2
      1 - 0.5 * (half ** 2 + half ** 2) / (0.1 * range) ** 2
    else
      1
    end
  end

  defp density(count, {low, high}, first, last) do
    ratio = (count - 1) / (last - first)
    target = (@wanted - 1) / (max(last, high) - min(low, first))
    2 - max(ratio / target, target / ratio)
  end

  defp density_max(count) when count >= @wanted, do: 2 - (count - 1) / (@wanted - 1)
  defp density_max(_count), do: 1

  # R's `%%` on doubles: the remainder with the sign of the divisor.
  defp modulo(dividend, divisor), do: dividend - :math.floor(dividend / divisor) * divisor

  # R's `seq(from, to, by = step)`: whole steps from `first`, none past `last`; just `first` when
  # the span is within 100 epsilons of the ends' size, where R's steps would be rounding error.
  defp sequence(first, last, step) do
    if abs(last - first) / max(abs(last), abs(first)) < @epsilon do
      [first]
    else
      steps = trunc((last - first) / step + 1.0e-10)
      Enum.map(0..steps//1, fn index -> min(first + index * step, last) end)
    end
  end

  # R's `seq(from, to, length.out = n)`: `n` values from end to end, the ends exact.
  defp spaced_evenly(low, high) do
    width = (high - low) / (@wanted - 1)
    inner = Enum.map(1..(@wanted - 2)//1, fn index -> low + index * width end)
    Enum.concat([[low], inner, [high]])
  end
end
