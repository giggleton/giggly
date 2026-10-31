defmodule Giggly.Resolution do
  @moduledoc false

  # How finely positions are spaced, ggplot2's `resolution()`: the smallest gap between two of
  # them. A mark with a width in data units and no width given takes it from here, as a bar is 0.9
  # of it wide, so neighbouring marks never overlap: positions 1, 2 and 3 are 1 apart, and 2.9, 3.1
  # and 4.5 are 0.2 apart, the closest pair deciding for every mark.
  #
  # Its rules are R's, for positions as a scale has mapped them, which is how every mark reads its
  # spacing. A discrete axis's positions are 1 apart, whatever levels a panel holds, where the
  # caller says so (`discrete: true`), as R's `resolution(discrete = TRUE)` reads a mapped discrete
  # position, which jittering, counting, the box plot's summary and tiles pass and bars do not.
  # Otherwise positions are spaced by their gaps as R's doubles, integers too: R's continuous scale
  # makes every position a double, so R's rule that an integer column is 1 apart never applies in a
  # plot, and mpg's years 1999 and 2008 are 9 apart. Positions whose range R's `zero_range()` calls
  # zero wide, one value among them, are 1 apart, and so are none. Counting from zero (`zero:
  # true`, `stat_count()`'s choice) adds 0 to the positions first, so the gap from 0 to the nearest
  # one counts too; a geom's own fallback (`zero: false`) counts only the gaps between them. Gaps
  # smaller than R's tolerance, the square root of the machine epsilon, are rounding error and left
  # out, a repeated position's gap of 0 among them, and with none left the positions are 1 apart. A
  # missing or infinite position is left out, as R's `sort()` drops a missing one.

  # ggplot2's arithmetic on plain positions, asking R's scales half only whether a range is zero
  # wide (`Scales.Bounds.zero_range?/1`), the one home of R's `zero_range()`.
  use Boundary, deps: [Scales], exports: []

  alias Scales.Bounds

  # R's `sqrt(.Machine$double.eps)`.
  @tolerance :math.sqrt(2.220446049250313e-16)

  # The smallest gap between `positions`, counting from zero when `zero` is true, or 1 when they are
  # a discrete axis's (`discrete`).
  @doc false
  @spec of(list(), zero: boolean(), discrete: boolean()) :: number()
  def of(_positions, zero: zero, discrete: true) when is_boolean(zero), do: 1

  def of(positions, zero: zero, discrete: false) when is_boolean(zero) do
    numbers = for position <- positions, is_number(position), do: position / 1

    if numbers == [] or zero_width?(numbers),
      do: 1,
      else: smallest_gap(numbers, zero)
  end

  defp zero_width?(numbers) do
    numbers
    |> Enum.min_max()
    |> Bounds.zero_range?()
  end

  defp smallest_gap(numbers, zero) do
    gaps =
      numbers
      |> counted_from(zero)
      |> Enum.sort()
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [low, high] -> high - low end)
      |> Enum.filter(fn gap -> gap > @tolerance end)

    case gaps do
      [] -> 1
      gaps -> Enum.min(gaps)
    end
  end

  defp counted_from(numbers, true), do: [0.0 | numbers]
  defp counted_from(numbers, false), do: numbers
end
