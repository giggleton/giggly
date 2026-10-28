defmodule Scales.MinorBreaks do
  @moduledoc """
  Where a continuous axis's minor breaks go, between its breaks (`regular/3`).
  """

  # R's `scales::regular_minor_breaks()`, which a transformation carries as its `minor_breaks` and
  # ggplot2 calls asking for two intervals between neighbouring breaks.

  @regular_options NimbleOptions.new!(
                     reverse: [
                       type: :boolean,
                       default: false,
                       doc:
                         "Whether the breaks run from high to low, as a reversing " <>
                           "transformation's do, so the step added before the first break goes " <>
                           "above it and the one after the last below it."
                     ]
                   )

  @doc """
  The minor breaks between `breaks` on an axis showing the limits `{low, high}`, R's
  `regular_minor_breaks()`: each gap between neighbouring breaks, in the order given, gets a minor
  break at its middle, the gap's start plus half its width, as R's `seq()` finds it. Where the
  limits reach past the breaks at an end, the breaks are first extended by one more step there,
  the first gap's, so minor breaks can fall between the outermost break and the edge of the axis.

  The result holds the breaks themselves and the added steps too, as R's does, and may reach past
  the limits; which to keep is the caller's. Fewer than two breaks have no gap, and so no minor
  breaks.

  ## Options

  #{NimbleOptions.docs(@regular_options)}

  ## Examples

      iex> Scales.MinorBreaks.regular([10.0, 20.0, 30.0], {5.0, 35.0})
      [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0]

      iex> Scales.MinorBreaks.regular([30.0, 20.0, 10.0], {5.0, 35.0}, reverse: true)
      [40.0, 35.0, 30.0, 25.0, 20.0, 15.0, 10.0, 5.0, 0.0]
  """
  @spec regular([float()], {float(), float()}, keyword()) :: [float()]
  def regular(breaks, limits, options \\ []) do
    %{reverse: reverse} =
      options
      |> NimbleOptions.validate!(@regular_options)
      |> Map.new()

    regular_breaks(breaks, limits, reverse)
  end

  defp regular_breaks([first, second | _later] = breaks, limits, reverse) do
    step = second - first

    breaks
    |> extended(step, limits, reverse)
    |> Enum.chunk_every(2, 1)
    |> Enum.flat_map(fn
      [from, to] -> [from, from + (to - from) / 2]
      [final] -> [final]
    end)
  end

  defp regular_breaks(_breaks, _limits, _reverse), do: []

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
