defmodule Giggly.Scale.OutOfBounds do
  @moduledoc false

  # A continuous or binned scale's `oob`, run as ggplot2 runs a scale's `oob` on one column's
  # values and the scale's limits, both in transformed space: a name is one of R's `oob_*`
  # functions, `Scales.Bounds`'s, and a function is called with the values and the limits.
  #
  # What a function returns is one value for each value handed it, each a number, read as a
  # float, as R's doubles are, `:infinity`, `:neg_infinity`, `nil` or `:nan`, anything else raising
  # when run, where R would recycle a shorter result, cut a longer one and coerce a string or a
  # boolean. NaN, `:nan`, is missing wherever the result is read, so it comes back `nil`, from a
  # name's run as from a function's.

  alias Scales.Bounds

  # The values as `oob` leaves them, on `limits`, `{low, high}`.
  @doc false
  @spec run(Giggly.Scale.Continuous.oob(), list(), {Scales.double(), Scales.double()}) :: list()
  def run(oob, values, limits) do
    oob
    |> bounded(values, limits)
    |> Enum.map(fn
      :nan -> nil
      value -> value
    end)
  end

  defp bounded(:censor, values, limits), do: Bounds.censor(values, limits)
  defp bounded(:censor_any, values, limits), do: Bounds.censor_any(values, limits)
  defp bounded(:squish, values, limits), do: Bounds.squish(values, limits)
  defp bounded(:squish_any, values, limits), do: Bounds.squish_any(values, limits)
  defp bounded(:squish_infinite, values, limits), do: Bounds.squish_infinite(values, limits)
  defp bounded(:keep, values, limits), do: Bounds.keep(values, limits)

  defp bounded(function, values, limits) when is_function(function, 2) do
    returned = function.(values, limits)
    counted!(returned, length(values))
    Enum.map(returned, &read!/1)
  end

  defp counted!(returned, count) when is_list(returned) and length(returned) == count, do: :ok

  defp counted!(returned, count) when is_list(returned) do
    raise ArgumentError,
          "a scale's oob: function returned a list of #{length(returned)} for the #{count} " <>
            "values it was handed; it must return a value for each"
  end

  defp counted!(returned, count) do
    raise ArgumentError,
          "a scale's oob: function must return a list of a value for each of the #{count} it " <>
            "was handed, got: #{inspect(returned)}"
  end

  defp read!(value) when is_number(value), do: value / 1
  defp read!(value) when value in [:infinity, :neg_infinity, nil, :nan], do: value

  defp read!(value) do
    raise ArgumentError,
          "a scale's oob: function returned #{inspect(value)}, which is not a number, " <>
            ":infinity, :neg_infinity, nil or :nan"
  end
end
