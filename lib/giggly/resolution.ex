defmodule Giggly.Resolution do
  @moduledoc false

  # How finely positions are spaced, ggplot2's `resolution()`: the smallest gap between two of
  # them. A mark with a width in data units and no width given takes it from here, as a bar is 0.9
  # of it wide, so neighbouring marks never overlap: positions 1, 2 and 3 are 1 apart, and 2.9, 3.1
  # and 4.5 are 0.2 apart, the closest pair deciding for every mark.
  #
  # Its rules are R's. Positions that are all integers are 1 apart, whatever their gaps, as R treats
  # an integer column; so are positions whose range R's `zero_range()` calls zero wide, one value
  # among them. Counting from zero (`zero: true`, `stat_count()`'s choice) adds 0 to the positions
  # first, so the gap from 0 to the nearest one counts too; a geom's own fallback (`zero: false`)
  # counts only the gaps between them. Gaps smaller than R's tolerance, the square root of the
  # machine epsilon, are rounding error and left out, a repeated position's gap of 0 among them, and
  # with none left the positions are 1 apart. A missing or infinite position is left out, as R's
  # `sort()` drops a missing one.

  # ggplot2's arithmetic on plain positions, asking the scales only whether a range is zero wide,
  # the one home of R's `zero_range()`.
  use Boundary, deps: [Giggly.Scale], exports: []

  alias Giggly.Scale

  # R's `sqrt(.Machine$double.eps)`.
  @tolerance :math.sqrt(2.220446049250313e-16)

  # The smallest gap between `positions`, counting from zero when `zero` is true.
  @doc false
  @spec of(list(), zero: boolean()) :: number()
  def of(positions, zero: zero) when is_boolean(zero) do
    numbers = Enum.filter(positions, fn position -> is_number(position) end)

    if Enum.all?(numbers, fn number -> is_integer(number) end) or zero_width?(numbers),
      do: 1,
      else: smallest_gap(numbers, zero)
  end

  defp zero_width?(numbers) do
    {low, high} = Enum.min_max(numbers)
    Scale.zero_range?(low, high)
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
