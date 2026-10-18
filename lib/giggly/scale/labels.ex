defmodule Giggly.Scale.Labels do
  @moduledoc false

  # How an axis writes its breaks. Use it through `Giggly.Scale`.
  #
  # Numbers are written as Elixir shows a float in IEx (`inspect/1`), in plain decimals, with what
  # an axis read at a glance needs on top: every label on an axis gets as many decimals as the most
  # precise one needs (`0.0 2.5 5.0`), none when every break is whole (`2 3 4`), never scientific
  # notation and no thousands separators. Each break is first rounded to 15 significant digits,
  # which drops the rounding error that adding up steps leaves in the last digits (`0.3`, not
  # `0.30000000000000004`), and a negative zero is written `0`. This differs from ggplot2, whose
  # labels come from R's `format()` (`1e+05` where this writes `100000`).
  #
  # A discrete level is written as R's `as.character()` writes its value (`Giggly.AsCharacter`),
  # as `factor()` labels its levels: `4` for a whole float, `TRUE` for `true`; a missing one
  # (`nil`) as `NA`, as ggplot2 labels a missing level.

  alias Giggly.AsCharacter

  @significant_digits 15

  # The labels of continuous breaks, in the order given. Rounding error can reach the 16th
  # significant digit, as in some breaks R's `labeling::extended()` returns, and rounding to 15
  # digits drops it there too; a break that needs all 15 digits keeps them.
  @doc false
  @spec numbers([float()]) :: [String.t()]
  def numbers(breaks) do
    rounded = Enum.map(breaks, &round_significant/1)

    decimals =
      rounded
      |> Enum.map(&decimals_needed/1)
      |> Enum.max(fn -> 0 end)

    Enum.map(rounded, fn value -> :erlang.float_to_binary(value, decimals: decimals) end)
  end

  # The labels of discrete levels, in the order given.
  @doc false
  @spec levels(list()) :: [String.t()]
  def levels(levels), do: Enum.map(levels, &level/1)

  defp level(nil), do: "NA"
  defp level(value), do: AsCharacter.text(value)

  # Rounds through the 15-significant-digit scientific form; a zero of either sign becomes 0.0.
  # `:erlang.float_to_binary/2` takes a negative `scientific:` precision without complaint and uses
  # its default of six decimals, where a negative `decimals:` raises, so the example with a break
  # needing all fifteen digits is what pins the precision.
  defp round_significant(value) when value == 0, do: 0.0

  defp round_significant(value) do
    value
    |> :erlang.float_to_binary(scientific: @significant_digits - 1)
    |> String.to_float()
  end

  # How many decimals the shortest form that reads back as `value` has, counted from its
  # significand and exponent (`2.5e4` needs none, `-1.0e-5` five).
  defp decimals_needed(value) do
    {significand, exponent} =
      value
      |> :erlang.float_to_binary([:short])
      |> split_exponent()

    [_whole, fraction] = String.split(significand, ".")

    fraction_digits =
      fraction
      |> String.trim_trailing("0")
      |> String.length()

    max(fraction_digits - exponent, 0)
  end

  defp split_exponent(short) do
    case String.split(short, "e") do
      [significand, exponent] -> {significand, String.to_integer(exponent)}
      [significand] -> {significand, 0}
    end
  end
end
