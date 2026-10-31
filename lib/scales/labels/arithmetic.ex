defmodule Scales.Labels.Arithmetic do
  @moduledoc false

  # R's rounding and logarithms as `Scales.Labels` needs them, each in R's order of
  # floating-point operations, since another order lands a bit away and moves a label:
  #
  # - `signif/2` is R's `signif()`, `fprec()` in `nmath/fprec.c`: the number scaled by a power
  #   of ten into its significant digits, rounded half to even there and scaled back, multiplying
  #   by the power where it is above 1 and dividing where it is below, so the power is always
  #   exact up to 1e22; a number from 1e306 up or 1e-306 down scaled in two steps and rounded
  #   half up, as R scales and rounds it. `signif(0.15, 1)` is 0.2, as `0.15 * 10` rounds to
  #   1.5, where `format(0.15, digits = 1)`, from the exact value, writes `0.1`.
  # - `round_to/2` is R's `round(x, digits)`, `fround()` in `nmath/fround.c`: the digits rounded
  #   half up, then the nearer of the number rounded down and up to them, measured in floats, a
  #   tie to the even; a zero comes out a zero, as R returns it. Only `zapsmall()`'s digits
  #   reach it, which leave every number at most about seven significant digits, so R's
  #   branches for a number already within 15 of them and for digits past 308 are never taken
  #   and are left out.
  # - A power of ten is R's `R_pow_di()`, by repeated squaring, which is exact to 1e22 and lands
  #   on R's own double past it.
  # - A logarithm is R's `log(x, base)`: base 10 and 2 their own functions, any other the ratio
  #   of natural ones.
  # - `product/2`, `quotient/2` and `difference/2` are a double's `*`, `/` and `-`, a result
  #   past the largest double the infinity of its sign, `:infinity` or `:neg_infinity`, as R's
  #   is, where Erlang raises; each takes numbers alone, so the rescue never takes a missing or
  #   infinite operand for an overflow. `signif/2` keeps an infinity, as R does.

  # R's `MAX_DIGITS` for `signif()`, and `DBL_MAX_10_EXP`.
  @max_digits 22
  @max_power 308

  # `log10(DBL_MAX)`.
  @log10_largest :math.log10(1.797_693_134_862_315_7e308)

  # `value` rounded to `digits` significant digits, as R's `signif()` rounds it.
  @doc false
  @spec signif(float() | :infinity | :neg_infinity, 1..22) :: float() | :infinity | :neg_infinity
  def signif(value, _digits) when value == 0, do: value
  def signif(value, _digits) when value in [:infinity, :neg_infinity], do: value

  def signif(value, digits) do
    sign = if value < 0, do: -1.0, else: 1.0
    magnitude = abs(value)
    log10 = :math.log10(magnitude)
    power = digits - 1 - trunc(Float.floor(log10))

    if abs(log10) < @max_power - 2,
      do: sign * scaled_round(magnitude, power),
      else: sign * extreme_round(magnitude, log10, power, digits)
  end

  defp scaled_round(magnitude, power) when power > @max_power do
    rest = power_of_ten(power - @max_power)
    scale = power_of_ten(@max_power)
    nearest(magnitude * scale * rest) / scale / rest
  end

  defp scaled_round(magnitude, power) when power > 0 do
    scale = power_of_ten(power)
    nearest(magnitude * scale) / scale
  end

  defp scaled_round(magnitude, power) do
    scale = power_of_ten(-power)
    nearest(magnitude / scale) * scale
  end

  # R's branch for a number from 1e306 up or 1e-306 down: scaled in two steps, a half added
  # unless the number is within `10^-digits` of the largest double's power, then rounded down.
  defp extreme_round(magnitude, log10, power, digits) do
    round_up = @log10_largest - log10 >= power_of_ten(-digits)
    first = digits + if(power > 0, do: 1, else: -1) * @max_digits
    first_scale = power_of_ten(first)
    second_scale = power_of_ten(power - first)
    scaled = magnitude * first_scale * second_scale
    scaled = if round_up, do: scaled + 0.5, else: scaled
    Float.floor(scaled) / first_scale / second_scale
  end

  # `value` rounded to `digits` decimals, as R's `round()` rounds it.
  @doc false
  @spec round_to(float(), number()) :: float()
  def round_to(value, digits) when digits == 0, do: nearest(value)

  def round_to(value, digits) do
    decimals = trunc(Float.floor(digits + 0.5))
    sign = if value < 0, do: -1.0, else: 1.0
    magnitude = abs(value)
    scale = power_of_ten(decimals)
    scaled = magnitude * scale
    whole = Float.floor(scaled)
    down = whole / scale
    up = Float.ceil(scaled) / scale
    above = up - magnitude
    below = magnitude - down
    odd = rem(trunc(whole), 2) == 1
    if above < below or (odd and above == below), do: sign * up, else: sign * down
  end

  # `left * right` as a double, or the infinity of its sign past the largest.
  @doc false
  @spec product(float(), float()) :: float() | :infinity | :neg_infinity
  def product(left, right) when is_number(left) and is_number(right) do
    left * right
  rescue
    ArithmeticError -> infinity(left, right)
  end

  # `left / right` as a double, or the infinity of its sign past the largest.
  @doc false
  @spec quotient(float(), float()) :: float() | :infinity | :neg_infinity
  def quotient(left, right) when is_number(left) and is_number(right) do
    left / right
  rescue
    ArithmeticError -> infinity(left, right)
  end

  # `high - low`, `high` the larger, as a double, or `:infinity` past the largest.
  @doc false
  @spec difference(float(), float()) :: float() | :infinity
  def difference(high, low) when is_number(high) and is_number(low) do
    high - low
  rescue
    ArithmeticError -> :infinity
  end

  defp infinity(left, right) when left < 0 != right < 0, do: :neg_infinity
  defp infinity(_left, _right), do: :infinity

  # C's `nearbyint()`: the nearest whole number, a half to the even one.
  @doc false
  @spec nearest(float()) :: float()
  def nearest(value) do
    floor = Float.floor(value)

    case value - floor do
      fraction when fraction > 0.5 -> floor + 1
      fraction when fraction < 0.5 -> floor
      _half -> if rem(trunc(floor), 2) == 0, do: floor, else: floor + 1
    end
  end

  # R's `log(value, base)` of a positive number.
  @doc false
  @spec logarithm(float(), number()) :: float()
  def logarithm(value, base) when base == 10, do: :math.log10(value)
  def logarithm(value, base) when base == 2, do: :math.log2(value)
  def logarithm(value, base), do: :math.log(value) / :math.log(base)

  # R's `R_pow_di(10, power)`: ten to a whole power by repeated squaring, a negative power the
  # reciprocal of the positive.
  defp power_of_ten(power) when power < 0, do: 1 / power_of_ten(-power)
  defp power_of_ten(power), do: squared(10.0, power, 1.0)

  defp squared(base, power, product) do
    product = if rem(power, 2) == 1, do: product * base, else: product
    rest = div(power, 2)
    if rest == 0, do: product, else: squared(base * base, rest, product)
  end
end
