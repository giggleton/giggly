defmodule Giggly.Scale.MinorBreaks do
  @moduledoc false

  # Where a continuous axis's minor breaks go, between its breaks: R's
  # `scales::regular_minor_breaks()`, which a transformation carries as its `minor_breaks` and
  # ggplot2 calls asking for two intervals between neighbouring breaks. Use it through
  # `Giggly.Scale`.
  #
  # Each gap between neighbouring breaks, in the order the transformation gives them, gets a minor
  # break at its middle. Where the extent reaches past the breaks at an end, the breaks are first
  # extended by one more step there, the first gap's, so that minor breaks can fall between the
  # outermost break and the edge of the axis. Which end is which follows the breaks' order: a
  # reversed transformation's breaks descend, and R's `reverse = TRUE` adds the step above the
  # first break and below the last. The result holds the breaks themselves and the added steps too,
  # as R's does; which to keep is the caller's.

  # The minor breaks between `breaks` on an axis showing `{low, high}`, in R's order, with the
  # breaks and any added step among them: each gap's middle, found as R's `seq()` finds it, the
  # gap's start plus half its width. Fewer than two breaks have no gap, and so no minor breaks.
  @doc false
  @spec regular([float()], {float(), float()}, boolean()) :: [float()]
  def regular(breaks, extent, reverse \\ false)

  def regular([first, second | _later] = breaks, extent, reverse) do
    step = second - first

    breaks
    |> extended(step, extent, reverse)
    |> Enum.chunk_every(2, 1)
    |> Enum.flat_map(fn
      [from, to] -> [from, from + (to - from) / 2]
      [final] -> [final]
    end)
  end

  def regular(_breaks, _extent, _reverse), do: []

  # R adds the step before the first break, then asks of the breaks as they then stand whether to
  # add one after the last.
  defp extended(breaks, step, {low, high}, false) do
    breaks
    |> step_before(step, low < Enum.min(breaks))
    |> then(fn stepped -> step_after(stepped, step, high > Enum.max(stepped)) end)
  end

  defp extended(breaks, step, {low, high}, true) do
    breaks
    |> step_before(step, high > Enum.max(breaks))
    |> then(fn stepped -> step_after(stepped, step, low < Enum.min(stepped)) end)
  end

  defp step_before([first | _rest] = breaks, step, true), do: [first - step | breaks]
  defp step_before(breaks, _step, false), do: breaks

  defp step_after(breaks, step, true), do: Enum.concat(breaks, [List.last(breaks) + step])
  defp step_after(breaks, _step, false), do: breaks
end
