defmodule Giggly.Format.Fixed do
  @moduledoc false

  # Numbers written in plain decimals as R's `format(x, nsmall = decimals, scientific = FALSE)`
  # writes them, for `Giggly.Format`, which hands it each group of non-negative numbers that
  # share a decimal count. It is R's `formatReal()` and `prettyNum()`, rule for rule:
  #
  # - The group takes the most decimals any of its numbers needs to show its first seven
  #   significant digits (R's default `digits`), and at least `decimals`; seven significant
  #   digits are counted as R's `scientific()` in `format.c` counts them.
  # - Each number is printed as C's `sprintf("%.*f")` prints it, rounding its exact binary value
  #   half to even, here in integer arithmetic from the float's bits: Erlang's
  #   `float_to_binary/2` with `decimals:` rounds a tie away from zero (`0.125` to `0.13`, where
  #   R writes `0.12`).
  # - `big_mark` goes between each three digits of the whole part, `decimal_mark` before the
  #   decimals.
  # - Untrimmed, each is padded on the left to the width `formatReal()` estimates from the whole
  #   digits, which is one wider than printed when rounding to seven digits carries a number to a
  #   power of ten its printed form does not reach (` 99999999.9` at one decimal); when marks
  #   lengthen any number, all are padded to the longest, counting characters. No number prints
  #   wider than the estimate, so padding every number to the longest after marking is the same,
  #   and a number below 1, which R counts as one whole digit, needs no such floor here.
  #
  # R falls back to scientific notation when a plain number would be some hundred characters
  # wider than its scientific form (beyond about 1e105, or an accuracy below about 1e-100); this
  # always writes plain decimals.

  # How a group is written: the marks, and whether to leave out the padding.
  @type settings :: %{
          required(:big_mark) => String.t(),
          required(:decimal_mark) => String.t(),
          required(:trim) => boolean(),
          optional(atom()) => term()
        }

  # R's `getOption("digits")`: the significant digits `format()` shows.
  @significant_digits 7

  # R's `KP_MAX`, the largest power of ten `formatReal()` checks for a number that rounding widens.
  @largest_power 27

  # A double's significand has 52 stored bits and an implicit leading one.
  @implicit_bit 2 ** 52

  # Non-negative numbers written together: the decimals any needs at seven significant digits,
  # at least `decimals`, marked, and padded to a common width unless `trim` is set.
  @doc false
  @spec write([float()], non_neg_integer(), settings()) :: [String.t()]
  def write(values, decimals, settings) do
    digits = Enum.map(values, &significant/1)

    right =
      digits
      |> Enum.map(fn {whole_digits, significant} -> significant - whole_digits end)
      |> Enum.max()

    shown = max(right, decimals)
    plain = Enum.map(values, fn value -> fixed(value, shown) end)

    if settings.trim do
      Enum.map(plain, fn text -> marked(text, settings) end)
    else
      padded(plain, digits, shown, settings)
    end
  end

  # Padding to the width R estimates from the whole digits, then, once marked, to the longest.
  defp padded(plain, digits, shown, settings) do
    whole =
      digits
      |> Enum.map(fn {whole_digits, _significant} -> whole_digits end)
      |> Enum.max()

    width = whole + shown + if(shown > 0, do: 1, else: 0)

    marked =
      Enum.map(plain, fn text ->
        text
        |> String.pad_leading(width)
        |> marked(settings)
      end)

    longest =
      marked
      |> Enum.map(&String.length/1)
      |> Enum.max()

    Enum.map(marked, fn text -> String.pad_leading(text, longest) end)
  end

  # A plain number with `big_mark` between each three digits of its whole part and
  # `decimal_mark` before its decimals.
  defp marked(text, settings) do
    {whole, decimals} =
      case String.split(text, ".") do
        [whole] -> {whole, :none}
        [whole, decimals] -> {whole, decimals}
      end

    digits = String.trim_leading(whole)
    blanks = String.duplicate(" ", String.length(whole) - String.length(digits))
    marked_whole = blanks <> thousands(digits, settings.big_mark)

    case decimals do
      :none -> marked_whole
      decimals -> marked_whole <> settings.decimal_mark <> decimals
    end
  end

  defp thousands(digits, big_mark) do
    lead = rem(String.length(digits) - 1, 3) + 1
    {first, rest} = String.split_at(digits, lead)

    groups =
      rest
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1)

    Enum.join([first | groups], big_mark)
  end

  # R's `scientific()` in `format.c` at seven significant digits, for a non-negative number: how
  # many digits it shows left of the point in plain notation, and how many significant digits
  # it has, the zeros after its last one dropped. R scales the number into seven digits in long
  # double precision; here the scaling is exact.
  defp significant(value) when value == 0, do: {1, 1}

  defp significant(value) do
    {numerator, denominator} = exact(value)

    estimate =
      value
      |> :math.log10()
      |> Float.floor()
      |> trunc()

    power = estimate - @significant_digits + 1
    {scaled_numerator, scaled_denominator} = scaled(numerator, denominator, power)
    alpha = round_ratio(scaled_numerator, scaled_denominator)
    {significant, power} = significant_count(alpha, power)
    exponent = power + @significant_digits - 1
    widened = if widens?(numerator, denominator, exponent), do: 1, else: 0
    {exponent + 1 - widened, significant}
  end

  # The number divided by 10^power. R multiplies by ten more when that leaves it under seven
  # digits, which the floor of its log10 never does here: log10 is exact at a power of ten and
  # rounds up only within a float's error below one, where six digits round to 10^6 as seven
  # round to 10^7, and give the same count.
  defp scaled(numerator, denominator, power) when power >= 0,
    do: {numerator, denominator * 10 ** power}

  defp scaled(numerator, denominator, power), do: {numerator * 10 ** -power, denominator}

  # The significant digits of a seven-digit integer, its trailing zeros dropped; when rounding
  # carried it to 10^7, one digit a power higher.
  defp significant_count(alpha, power) do
    zeros = trailing_zeros(alpha, 0)

    case @significant_digits - zeros do
      0 -> {1, power + 1}
      count -> {count, power}
    end
  end

  defp trailing_zeros(alpha, count) when rem(alpha, 10) == 0,
    do: trailing_zeros(div(alpha, 10), count + 1)

  defp trailing_zeros(_alpha, count), do: count

  # Whether rounding to seven digits carried the number to a power of ten it does not reach in
  # plain notation, so it shows one whole digit fewer than its exponent says. R asks whether the
  # number is more than `0.5 / 10^max(7 - exponent, 0)` below 10^exponent, up to its `KP_MAX`;
  # below 10^8 that margin is the half of a seventh digit whose carry gave the exponent, so no
  # such number is ever below it, and from 10^8 the margin is a half.
  defp widens?(numerator, denominator, exponent)
       when exponent > @significant_digits and exponent <= @largest_power,
       do: 2 * numerator < denominator * (2 * 10 ** exponent - 1)

  defp widens?(_numerator, _denominator, _exponent), do: false

  # A non-negative float in plain notation with `decimals` decimals, rounded half to even from
  # its exact value, as C's `sprintf("%.*f")` writes it.
  defp fixed(value, decimals) do
    {numerator, denominator} = exact(value)

    digits =
      (numerator * 10 ** decimals)
      |> round_ratio(denominator)
      |> Integer.to_string()
      |> String.pad_leading(decimals + 1, "0")

    case decimals do
      0 ->
        digits

      _decimals ->
        {whole, fraction} = String.split_at(digits, -decimals)
        whole <> "." <> fraction
    end
  end

  # A non-negative float's exact value as a numerator over a power of two.
  defp exact(value) do
    <<0::1, exponent::11, fraction::52>> = <<value::float>>

    {significand, power} =
      case exponent do
        0 -> {fraction, -1074}
        _normal -> {fraction + @implicit_bit, exponent - 1075}
      end

    if power >= 0, do: {significand * 2 ** power, 1}, else: {significand, 2 ** -power}
  end

  # A non-negative ratio rounded to an integer, a half to the even one.
  defp round_ratio(numerator, denominator) do
    quotient = div(numerator, denominator)
    twice_remainder = 2 * rem(numerator, denominator)

    cond do
      twice_remainder > denominator -> quotient + 1
      twice_remainder < denominator -> quotient
      rem(quotient, 2) == 0 -> quotient
      true -> quotient + 1
    end
  end
end
