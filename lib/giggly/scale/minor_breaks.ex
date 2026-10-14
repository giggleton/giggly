defmodule Giggly.Scale.MinorBreaks do
  @moduledoc false

  # Where a continuous axis's minor breaks go, between its breaks: R's
  # `scales::regular_minor_breaks()`, which a transformation carries as its `minor_breaks` and
  # ggplot2 calls asking for two intervals between neighbouring breaks. Use it through
  # `Giggly.Scale`.
  #
  # Each gap between neighbouring breaks gets a minor break at its middle. Where the extent reaches
  # past the first break, or past the last, the breaks are first extended by one more step at that
  # end, so that minor breaks can fall between the outermost break and the edge of the axis. The
  # result holds the breaks themselves and the added steps too, as R's does; which to keep is the
  # caller's.

  # The minor breaks between `breaks`, ascending breaks on an axis showing `{low, high}`, with the
  # breaks and any added step among them, in ascending order: each gap's middle, found as R's
  # `seq()` finds it, the gap's start plus half its width.
  #
  # A step is added below the first break when the extent reaches below it, and above the last
  # when it reaches above. Fewer than two breaks have no gap between them, and so no minor breaks.
  @doc false
  @spec regular([float()], {float(), float()}) :: [float()]
  def regular([first, second | _later] = breaks, {low, high}) do
    step = second - first
    last = List.last(breaks)

    # Each break followed by its gap's middle, and the last break alone.
    [step_below(first, step, low), breaks, step_above(last, step, high)]
    |> Enum.concat()
    |> Enum.chunk_every(2, 1)
    |> Enum.flat_map(fn
      [from, to] -> [from, from + (to - from) / 2]
      [final] -> [final]
    end)
  end

  def regular(_breaks, _extent), do: []

  defp step_below(first, step, low) when low < first, do: [first - step]
  defp step_below(_first, _step, _low), do: []

  defp step_above(last, step, high) when high > last, do: [last + step]
  defp step_above(_last, _step, _high), do: []
end
