defmodule Giggly.DataFrame.LongDouble do
  @moduledoc false

  # R's long double, in which R's `sum()`, `cumsum()` and `mean()` add and divide: the x87's
  # extended precision, 64
  # significant bits where a double has 53, every result rounded to the nearest, a tie to the even
  # one. A finite value is held exactly as `{mantissa, exponent}`, the integer `mantissa` times 2 to
  # the `exponent`, and each operation computes its result exactly and rounds it to 64 bits, so the
  # digits are the x87's, which ordinary floats cannot give and a compensated sum only
  # approximates. The x87's exponent reaches far past a double's both ways, so no sum or quotient of
  # doubles overflows or underflows one, and none is checked; only a double made from one
  # (`to_double/1`) can. Zero has no sign, as R's long double sums from plus zero.

  import Bitwise

  @typedoc "A finite long double: the integer mantissa times 2 to the exponent."
  @type t :: {integer(), integer()}

  @significant_bits 64

  @zero {0, 0}

  # A double's bits: its significand's 52 stored bits, the 53rd implied by a normal exponent.
  @fraction_bits 52
  @implied_bit 1 <<< @fraction_bits

  # The exponent of a double's last place below its smallest normal value and above its largest.
  @least_exponent -1074
  @overflow_exponent 1024

  @doc false
  @spec zero() :: t()
  def zero, do: @zero

  # A finite double as a long double, exactly, as the x87 loads one.
  @doc false
  @spec from_double(float()) :: t()
  def from_double(double) when is_float(double) do
    <<sign::1, exponent::11, fraction::@fraction_bits>> = <<double::float-64>>

    if exponent == 0,
      do: signed(sign, fraction, @least_exponent),
      else: signed(sign, fraction + @implied_bit, exponent + @least_exponent - 1)
  end

  # An integer as a long double, rounded to 64 bits where it has more.
  @doc false
  @spec from_integer(integer()) :: t()
  def from_integer(integer) when is_integer(integer), do: rounded({integer, 0})

  defp signed(1, magnitude, exponent), do: {-magnitude, exponent}
  defp signed(0, magnitude, exponent), do: {magnitude, exponent}

  # `left + right`, rounded.
  @doc false
  @spec add(t(), t()) :: t()
  def add({0, _exponent}, right), do: right
  def add(left, {0, _exponent}), do: left

  def add({left, left_exponent}, {right, right_exponent}) do
    exponent = min(left_exponent, right_exponent)
    sum = (left <<< (left_exponent - exponent)) + (right <<< (right_exponent - exponent))
    rounded({sum, exponent})
  end

  # `left - right`, rounded.
  @doc false
  @spec subtract(t(), t()) :: t()
  def subtract(left, {right, exponent}), do: add(left, {-right, exponent})

  # Whether `left` is below, equal to or above `right`, exactly.
  @doc false
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare({left, left_exponent}, {right, right_exponent}) do
    exponent = min(left_exponent, right_exponent)
    difference = (left <<< (left_exponent - exponent)) - (right <<< (right_exponent - exponent))

    cond do
      difference < 0 -> :lt
      difference > 0 -> :gt
      true -> :eq
    end
  end

  # `value / count` for a count of one or more, rounded once from the exact quotient.
  @doc false
  @spec divide(t(), pos_integer()) :: t()
  def divide({0, _exponent}, _count), do: @zero

  def divide({mantissa, exponent}, count) when is_integer(count) and count > 0 do
    # Enough bits that the quotient has at least two below the last it keeps, and a sticky bit
    # below them saying whether anything was left over, so it rounds as the exact quotient would.
    shift = max(0, @significant_bits + 2 + bit_length(count) - bit_length(abs(mantissa)))
    scaled = abs(mantissa) <<< shift
    sticky = if rem(scaled, count) == 0, do: 0, else: 1
    magnitude = (div(scaled, count) <<< 1) + sticky
    rounded({if(mantissa < 0, do: -magnitude, else: magnitude), exponent - shift - 1})
  end

  # The double nearest the value, a tie to the even one, as R's `(double)` cast rounds it: to 53
  # bits, or to fewer below the smallest normal double, or an infinity past the largest.
  @doc false
  @spec to_double(t()) :: float() | :infinity | :neg_infinity
  def to_double({0, _exponent}), do: 0.0

  def to_double(value) do
    {mantissa, exponent} = rounded(value, @fraction_bits + 1, @least_exponent)
    magnitude = abs(mantissa)
    sign = if mantissa < 0, do: 1, else: 0

    if bit_length(magnitude) + exponent > @overflow_exponent,
      do: infinity(sign),
      else: double(sign, magnitude, exponent)
  end

  defp infinity(0), do: :infinity
  defp infinity(1), do: :neg_infinity

  # The double of a magnitude of 53 bits or fewer: shifted up to 53 while its exponent stays at
  # or above the least, then a normal double's stored bits or, where it stays short, a subnormal's.
  defp double(sign, magnitude, exponent) do
    shift = min(@fraction_bits + 1 - bit_length(magnitude), exponent - @least_exponent)
    magnitude = magnitude <<< shift
    exponent = exponent - shift

    biased =
      if magnitude >= @implied_bit, do: exponent - @least_exponent + 1, else: 0

    fraction = magnitude &&& @implied_bit - 1
    <<double::float-64>> = <<sign::1, biased::11, fraction::@fraction_bits>>
    double
  end

  # The value rounded to `bits` significant bits, never to a last place below 2 to the `least`.
  defp rounded(value, bits \\ @significant_bits, least \\ :none)
  defp rounded({0, _exponent}, _bits, _least), do: @zero

  defp rounded({mantissa, exponent}, bits, least) do
    magnitude = abs(mantissa)
    dropped = dropped(bit_length(magnitude) - bits, exponent, least)

    if dropped <= 0 do
      {mantissa, exponent}
    else
      kept = magnitude >>> dropped
      rest = magnitude &&& (1 <<< dropped) - 1
      half = 1 <<< (dropped - 1)
      kept = if rest > half or (rest == half and odd?(kept)), do: kept + 1, else: kept
      {if(mantissa < 0, do: -kept, else: kept), exponent + dropped}
    end
  end

  defp dropped(beyond, _exponent, :none), do: beyond
  defp dropped(beyond, exponent, least), do: max(beyond, least - exponent)

  defp odd?(integer), do: (integer &&& 1) == 1

  # How many bits a magnitude takes: its bytes' bits, less the leading zeros of the first.
  defp bit_length(0), do: 0

  defp bit_length(magnitude) do
    <<first, _rest::binary>> = bytes = :binary.encode_unsigned(magnitude)
    (byte_size(bytes) - 1) * 8 + length(Integer.digits(first, 2))
  end
end
