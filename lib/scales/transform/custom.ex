defmodule Scales.Transform.Custom do
  @moduledoc false

  # A transformation of a user's own, R's `new_transform()`: the functions and domain a
  # `%Scales.Transform{}` holds, made by `Scales.Transform.new/2`. Use it through
  # `Scales.Transform`.
  #
  # Each function takes one value. The transformation, and its derivative, are handed every value
  # in the domain, its ends and an infinite end among them, as R's functions are handed the
  # domain; `nil` and `:nan` are kept without a call, as R's arithmetic keeps NA and NaN, and a
  # value outside the domain is `:nan` without one, as every transformation here gives it, where
  # R's would call the function anyway (design-log §4, the entry beginning "A transformation of
  # your own"). The inverse, and its derivative, are handed every position but `nil` and `:nan`.
  # An integer is handed as a float, an integer returned made one, and anything returned but a
  # number, an infinity, `:nan` or `nil` raises `ArgumentError` naming the transformation.
  #
  # Its breaks are its `breaks` function's on the extent turned back into data units, an end
  # turning back to anything but a number set aside, as the Box-Cox family's are (the entry
  # beginning "An axis past a bound"), and transformed; `n:` reaches a function of two arguments
  # and is refused by one of one, as the time transformation refuses it. Its minor breaks are its
  # `minor_breaks` function's, and its labels its `labels` function's of the breaks turned back.

  @behaviour Scales.Transform

  alias Scales.{Double, Transform}

  @impl Scales.Transform
  def transform(%Transform{domain: domain} = transformation, values),
    do: Enum.map(values, fn value -> placed(transformation, :transform, value, domain) end)

  @impl Scales.Transform
  def inverse(transformation, positions),
    do: Enum.map(positions, fn position -> handed(transformation, :inverse, position) end)

  @impl Scales.Transform
  def domain(%Transform{domain: domain}), do: domain

  @impl Scales.Transform
  def derivative(%Transform{domain: domain} = transformation, values) do
    given!(transformation, :derivative)
    Enum.map(values, fn value -> placed(transformation, :derivative, value, domain) end)
  end

  @impl Scales.Transform
  def inverse_derivative(transformation, positions) do
    given!(transformation, :inverse_derivative)
    Enum.map(positions, fn position -> handed(transformation, :inverse_derivative, position) end)
  end

  @impl Scales.Transform
  def breaks(%Transform{breaks: breaks} = transformation, {low, high}, options) do
    counted!(transformation, options)

    turned_back = inverse(transformation, [low, high])

    case Enum.filter(turned_back, &is_number/1) do
      [] ->
        []

      ends ->
        limits = Enum.min_max(ends)
        found = if is_function(breaks, 2), do: breaks.(limits, options), else: breaks.(limits)
        transform(transformation, found)
    end
  end

  @impl Scales.Transform
  def minor_breaks(%Transform{minor_breaks: minor_breaks}, breaks, extent),
    do: minor_breaks.(breaks, extent)

  @impl Scales.Transform
  def format(%Transform{labels: labels} = transformation, breaks, _extent, options) do
    counted!(transformation, options)

    transformation
    |> inverse(breaks)
    |> labels.()
  end

  # A value through the function under `key` if it is in the domain, `:nan` if it is not, and
  # `nil` and `:nan` kept.
  defp placed(_transformation, _key, value, _domain) when value in [nil, :nan], do: value

  defp placed(transformation, key, value, {low, high}) do
    if Double.less?(value, low) or Double.less?(high, value),
      do: :nan,
      else: called(transformation, key, value)
  end

  defp handed(_transformation, _key, position) when position in [nil, :nan], do: position
  defp handed(transformation, key, position), do: called(transformation, key, position)

  defp called(transformation, key, value) do
    function = Map.fetch!(transformation, key)

    answer =
      value
      |> as_float()
      |> function.()

    answered(transformation, key, value, answer)
  end

  defp as_float(value) when is_integer(value), do: value / 1
  defp as_float(value), do: value

  defp answered(_transformation, _key, _value, answer) when is_integer(answer), do: answer / 1

  defp answered(_transformation, _key, _value, answer)
       when is_float(answer) or answer in [:infinity, :neg_infinity, :nan, nil],
       do: answer

  defp answered(%Transform{name: name}, key, value, answer) do
    raise ArgumentError,
          "the #{inspect(name)} transformation's #{key} function returned #{inspect(answer)} " <>
            "for #{inspect(value)}; it returns a number, :infinity, :neg_infinity, :nan or nil"
  end

  defp given!(%Transform{name: name} = transformation, key) do
    if is_nil(Map.fetch!(transformation, key)) do
      raise ArgumentError,
            "the #{inspect(name)} transformation has no #{key}; " <>
              "give Scales.Transform.new/2 a #{inspect(key)} function"
    end
  end

  # `n:` refused by a breaks function of one argument, which takes no number.
  defp counted!(_transformation, []), do: :ok
  defp counted!(%Transform{breaks: breaks}, _options) when is_function(breaks, 2), do: :ok

  defp counted!(%Transform{name: name}, options) do
    raise ArgumentError,
          "the #{inspect(name)} transformation's breaks function takes one argument, so it " <>
            "counts no breaks and takes no #{inspect(Keyword.keys(options))}"
  end
end
