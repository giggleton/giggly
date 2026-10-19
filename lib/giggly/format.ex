defmodule Giggly.Format do
  @moduledoc """
  Labels for a scale's breaks: numbers with a mark between thousands (`comma/2`), percentages
  (`percent/2`) and amounts of money (`currency/2`).

  Each formatter is handed every break an axis draws and returns a label for each, in order, so
  the labels can share their decimals: `0.5`, `1` and `1.25` are labelled `0.50`, `1.00` and
  `1.25`. Give one to a scale's `labels:`, inside a function when it takes options:

      plot
      |> Plot.scale_y_continuous(labels: &Format.percent/1)
      |> Plot.scale_x_continuous(labels: fn breaks -> Format.comma(breaks, accuracy: 0.1) end)

  ## How a label is written

  Each number is multiplied by `scale:`, then rounded to a multiple of `accuracy:`, a half going
  to the even neighbour (`2.5` to `2`, `3.5` to `4`). A number that rounds to zero has no sign.
  It is written in plain decimals, never scientific notation, with as many decimals as the
  accuracy has (`0.01` writes two, `1` or more none) up to twenty, or more if a label needs them
  to show its first seven significant digits (an accuracy of `0.25` writes `0.25` and `0.50`); every
  label shares the most any needs. `big_mark:` goes between each three digits of the whole part
  and `decimal_mark:` before the decimals; then `prefix:` and `suffix:` go around the number,
  and the sign outside the prefix (`-$13.50`).

  Left out, the accuracy is worked out from the breaks themselves: the power of ten at or below
  the smallest gap between two of them when every break is a multiple of it, a tenth of it
  otherwise, and never more than 1. One break, or breaks closer than about 1.5e-8, take an
  accuracy of 1.

  Every formatter takes the same options, listed with its own defaults in its documentation.

  ## Shortening by steps

  `scale_cut:` divides each label by the largest step it reaches and writes the step's suffix
  after the number, before `suffix:`: under `cut_short_scale/1`, 1500 is written `1.5K` and two
  million `2M`. A label that is not a whole number of its step, but is a whole number of the step
  below, is written in the step below when the two steps are not a power of ten apart: under
  `cut_time_scale/1`, 90 seconds is `90s`, not `1.5m`. Labels in each step share their decimals,
  worked out from that step's labels alone when `accuracy:` is not given. The steps must include
  one at threshold 0, whose suffix is written after the labels below every other step, and no
  threshold may be negative or repeated. `cut_short_scale/1`, `cut_long_scale/1`, `cut_si/1`
  and `cut_time_scale/1` give the common sets.
  """

  # This writes a label as scales 1.4.0's `number()` and `label_currency()` do, step for step, so
  # each label is R's to the character (every example in the tests is R's output):
  #
  # - The default accuracy is `precision(x * scale)` (`scales:::precision`); the rounding is
  #   `round(x / (accuracy / scale)) * (accuracy / scale)`, R's `round()` going half to even, in
  #   R's order of floating-point operations, since that order can move a label (two and a half
  #   billion under the short scale is `3B`, as 1/1e-9 is not exact). The sign is taken after
  #   rounding.
  # - The decimals are `-floor(log10(accuracy))`, from 0 to 20, and the numbers sharing a count
  #   are written together, as R's `format(scale * abs(x), nsmall = decimals, scientific =
  #   FALSE)` writes them, by `Giggly.Format.Fixed`; then prefix, number and suffix, the sign
  #   outside them.
  # - `scale_cut` is `scales:::scale_cut`: steps are sorted by threshold; a step is looked up by
  #   its suffix as R indexes a named vector, the first step with it and never an empty suffix;
  #   a zero threshold never refines and divides by 1 below. R requires no zero step, but without
  #   one its lookup of the step below misaligns its vectors (`c(m = 60, h = 3600)` writes 5400
  #   as `5 400NA`), so one is required here (design-log §4, the entry beginning
  #   "`Giggly.Format`'s").
  #
  # Its own boundary. Its options are checked by NimbleOptions, as every public option in Giggly
  # is, so it lists that library, as the root's comment allows a domain with options of its own
  # to, and nothing else. Nothing in Giggly calls it: it is a library a user hands to `labels:`.
  use Boundary, deps: [NimbleOptions], exports: []

  alias Giggly.Format.Fixed

  @typedoc "A step for `scale_cut:`: the suffix written after a label, and the threshold it starts at."
  @type step :: {String.t(), number()}

  # The largest decimal count R's `number()` asks for.
  @max_decimals 20

  # `sqrt(.Machine$double.eps)`: gaps below it are rounding error, so the accuracy is 1.
  @smallest_gap :math.sqrt(2.220446049250313e-16)

  # Every formatter's options, before each sets its defaults.
  @formatter_options [
    accuracy: [
      type: {:custom, __MODULE__, :validate_positive, []},
      doc:
        "A positive number each label is rounded to a multiple of, in the label's own units, " <>
          "after `scale:`; worked out from the breaks when not given (see the module's " <>
          "documentation)."
    ],
    scale: [
      type: {:custom, __MODULE__, :validate_positive, []},
      doc: "A positive number each break is multiplied by before it is written."
    ],
    prefix: [type: :string, doc: "Text written before the number, after a negative's sign."],
    suffix: [type: :string, doc: "Text written after the number."],
    big_mark: [type: :string, doc: "Text written between each three digits of the whole part."],
    decimal_mark: [
      type: {:custom, __MODULE__, :validate_decimal_mark, []},
      doc: "Text written before the decimals, at least one character."
    ],
    trim: [
      type: :boolean,
      doc:
        "`false` pads each number on the left with spaces to the width of the widest, before " <>
          "its prefix and its sign: `\"-$    1\"` beside `\"$1,000\"`."
    ],
    style_negative: [
      type: {:in, [:hyphen, :minus, :parens]},
      doc:
        "How a negative is marked: `:hyphen` (`-1`), `:minus`, a true minus sign (`−1`), or " <>
          "`:parens` (`(1)`)."
    ],
    style_positive: [
      type: {:in, [:none, :plus, :space]},
      doc: "How a positive is marked: `:none` (`1`), `:plus` (`+1`) or `:space` (`\" 1\"`)."
    ],
    scale_cut: [
      type: {:custom, __MODULE__, :validate_steps, []},
      doc:
        "Steps to shorten each label by, a list of `{suffix, threshold}` pairs (see the " <>
          "module's documentation)."
    ]
  ]

  @comma_defaults [
    scale: 1,
    prefix: "",
    suffix: "",
    big_mark: ",",
    decimal_mark: ".",
    trim: true,
    style_negative: :hyphen,
    style_positive: :none
  ]

  @percent_defaults Keyword.merge(@comma_defaults, scale: 100, suffix: "%", big_mark: " ")

  @currency_defaults Keyword.put(@comma_defaults, :prefix, "$")

  @currency_options [
    largest_with_fractional: [
      type: {:custom, __MODULE__, :validate_number, []},
      default: 100_000,
      doc:
        "The largest amount that shows cents when neither `accuracy:` nor `scale_cut:` is given."
    ]
  ]

  # Each formatter's options: the shared ones with its defaults, and currency's own.
  @formatter_schemas Map.new(
                       [
                         {:comma, @comma_defaults, []},
                         {:percent, @percent_defaults, []},
                         {:currency, @currency_defaults, @currency_options}
                       ],
                       fn {formatter, defaults, own} ->
                         options =
                           Enum.map(@formatter_options, fn {name, spec} ->
                             case Keyword.fetch(defaults, name) do
                               {:ok, default} -> {name, Keyword.put(spec, :default, default)}
                               :error -> {name, spec}
                             end
                           end)

                         {formatter, NimbleOptions.new!(options ++ own)}
                       end
                     )

  # A set of steps' option.
  @space_options NimbleOptions.new!(
                   space: [
                     type: :boolean,
                     default: false,
                     doc: "`true` puts a space before each suffix (`2 K`)."
                   ]
                 )

  @short_scale [
    {"", 0},
    {"K", 1_000},
    {"M", 1_000_000},
    {"B", 1_000_000_000},
    {"T", 1_000_000_000_000}
  ]

  @long_scale [
    {"", 0},
    {"K", 1_000},
    {"M", 1_000_000},
    {"B", 1_000_000_000_000},
    {"T", 1_000_000_000_000_000_000}
  ]

  # The micro sign of `cut_time_scale/1` is the Greek mu (U+03BC); `cut_si/1`'s is the micro sign
  # (U+00B5), as in R.
  @time_scale [
    {"", 0},
    {"ns", 1.0e-9},
    {"μs", 1.0e-6},
    {"ms", 1.0e-3},
    {"s", 1},
    {"m", 60},
    {"h", 3_600},
    {"d", 86_400},
    {"w", 604_800}
  ]

  # The SI prefixes from 1e-24 to 1e24, a power of a thousand apart.
  @si_prefixes [
    "y",
    "z",
    "a",
    "f",
    "p",
    "n",
    "µ",
    "m",
    "",
    "k",
    "M",
    "G",
    "T",
    "P",
    "E",
    "Z",
    "Y"
  ]

  @doc """
  Labels numbers with a comma between each three digits of the whole part.

  ## Options

  #{NimbleOptions.docs(@formatter_schemas.comma)}

  ## Examples

      iex> Giggly.Format.comma([-100_000, 1_234_567.891, 0.125])
      ["-100,000", "1,234,568", "0"]

      iex> Giggly.Format.comma([0.5, 1, 1.25])
      ["0.50", "1.00", "1.25"]

      iex> Giggly.Format.comma([0, 1250, 2500], accuracy: 0.1, scale: 0.001, suffix: "k")
      ["0.0k", "1.2k", "2.5k"]

      iex> Giggly.Format.comma([0, 1500, 1.0e6], scale_cut: Giggly.Format.cut_short_scale())
      ["0", "2K", "1M"]
  """
  @spec comma([number()], keyword()) :: [String.t()]
  def comma(breaks, options \\ []) do
    settings = settings!(options, :comma)

    breaks
    |> numbers!("Format.comma/2")
    |> label(settings)
  end

  @doc """
  Labels proportions as percentages: each is multiplied by 100 and written with a `%`.

  Thousands are marked with a space (`1 234%`).

  ## Options

  #{NimbleOptions.docs(@formatter_schemas.percent)}

  ## Examples

      iex> Giggly.Format.percent([0, 0.25, 0.5, 0.75, 1])
      ["0%", "25%", "50%", "75%", "100%"]

      iex> Giggly.Format.percent([0.1234, 0.5], accuracy: 0.1)
      ["12.3%", "50.0%"]

      iex> Giggly.Format.percent([-0.5, 0.125, 12.345])
      ["-50%", "12%", "1 234%"]
  """
  @spec percent([number()], keyword()) :: [String.t()]
  def percent(breaks, options \\ []) do
    settings = settings!(options, :percent)

    breaks
    |> numbers!("Format.percent/2")
    |> label(settings)
  end

  @doc """
  Labels amounts of money, in dollars unless `prefix:` and `suffix:` say otherwise.

  Without `accuracy:` or `scale_cut:`, labels show cents when some amount is not whole and none
  is larger than `largest_with_fractional:`, and whole amounts otherwise. When both marks would
  be a comma, the thousands are marked with a space instead.

  ## Options

  #{NimbleOptions.docs(@formatter_schemas.currency)}

  ## Examples

      iex> Giggly.Format.currency([0, 50, 100])
      ["$0", "$50", "$100"]

      iex> Giggly.Format.currency([-13.5, 0, 13.5])
      ["-$13.50", "$0.00", "$13.50"]

      iex> Giggly.Format.currency([1234.5, 1], big_mark: ".", decimal_mark: ",", prefix: "", suffix: " €")
      ["1.234,50 €", "1,00 €"]

      iex> Giggly.Format.currency([0, 2.5e5, 5.0e5, 1.0e6], scale_cut: Giggly.Format.cut_short_scale())
      ["$0", "$250K", "$500K", "$1M"]
  """
  @spec currency([number()], keyword()) :: [String.t()]
  def currency(breaks, options \\ []) do
    values = numbers!(breaks, "Format.currency/2")

    settings =
      options
      |> settings!(:currency)
      |> with_cents(values)
      |> without_mark_collision()

    label(values, settings)
  end

  @doc """
  The short scale's steps for `scale_cut:`: thousands `K`, millions `M`, billions `B` (1e9) and
  trillions `T` (1e12).

  ## Options

  #{NimbleOptions.docs(@space_options)}

  ## Examples

      iex> Giggly.Format.cut_short_scale()
      [{"", 0}, {"K", 1000}, {"M", 1000000}, {"B", 1000000000}, {"T", 1000000000000}]

      iex> Giggly.Format.comma([-2000, 0, 2000], scale_cut: Giggly.Format.cut_short_scale(space: true))
      ["-2 K", "0 ", "2 K"]
  """
  @spec cut_short_scale(keyword()) :: [step()]
  def cut_short_scale(options \\ []), do: spaced(@short_scale, options)

  @doc """
  The long scale's steps for `scale_cut:`: thousands `K`, millions `M`, billions `B` (1e12) and
  trillions `T` (1e18).

  ## Options

  #{NimbleOptions.docs(@space_options)}

  ## Examples

      iex> Giggly.Format.currency([0, 1.0e9, 2.0e12], scale_cut: Giggly.Format.cut_long_scale())
      ["$0", "$1,000M", "$2B"]
  """
  @spec cut_long_scale(keyword()) :: [step()]
  def cut_long_scale(options \\ []), do: spaced(@long_scale, options)

  @doc """
  The SI prefixes' steps for `scale_cut:`, from yocto (1e-24) to yotta (1e24), each written with
  a space and `unit` after it (`" kg"`), and `unit` alone below a yocto and from 1 to 1000.

  ## Examples

      iex> Giggly.Format.comma([0.001, 1, 1500], scale_cut: Giggly.Format.cut_si("g"))
      ["1 mg", "1 g", "2 kg"]
  """
  @spec cut_si(String.t()) :: [step()]
  def cut_si(unit) when is_binary(unit) do
    steps =
      Enum.zip_with(@si_prefixes, -24..24//3, fn prefix, power ->
        {" " <> prefix <> unit, 10.0 ** power}
      end)

    [{" " <> unit, 0} | steps]
  end

  def cut_si(unit) do
    raise ArgumentError, "Format.cut_si/1 takes the unit as a string, got: #{inspect(unit)}"
  end

  @doc """
  Steps of time for `scale_cut:`, for labels in seconds: nanoseconds `ns`, microseconds `μs`,
  milliseconds `ms`, seconds `s`, minutes `m`, hours `h`, days `d` and weeks `w`.

  ## Options

  #{NimbleOptions.docs(@space_options)}

  ## Examples

      iex> Giggly.Format.comma([0, 45, 90, 120, 5400], scale_cut: Giggly.Format.cut_time_scale())
      ["0", "45s", "90s", "2m", "90m"]
  """
  @spec cut_time_scale(keyword()) :: [step()]
  def cut_time_scale(options \\ []), do: spaced(@time_scale, options)

  # NimbleOptions' check of `accuracy:` and `scale:`: a positive number.
  @doc false
  @spec validate_positive(term()) :: {:ok, number()} | {:error, String.t()}
  def validate_positive(value) when is_number(value) and value > 0, do: {:ok, value}
  def validate_positive(value), do: {:error, "expected a positive number, got: #{inspect(value)}"}

  # NimbleOptions' check of `decimal_mark:`: a string of at least one character.
  @doc false
  @spec validate_decimal_mark(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_decimal_mark(mark) when is_binary(mark) and mark != "", do: {:ok, mark}

  def validate_decimal_mark(mark),
    do: {:error, "expected a string of at least one character, got: #{inspect(mark)}"}

  # NimbleOptions' check of `largest_with_fractional:`: a number.
  @doc false
  @spec validate_number(term()) :: {:ok, number()} | {:error, String.t()}
  def validate_number(value) when is_number(value), do: {:ok, value}
  def validate_number(value), do: {:error, "expected a number, got: #{inspect(value)}"}

  # NimbleOptions' check of `scale_cut:`: `{suffix, threshold}` pairs, each threshold at least 0
  # and none given twice, one of them 0.
  @doc false
  @spec validate_steps(term()) :: {:ok, [step()]} | {:error, String.t()}
  def validate_steps(steps) do
    cond do
      not steps?(steps) ->
        {:error,
         "expected a list of {suffix, threshold} pairs, each suffix a string and each " <>
           "threshold a number of at least 0, got: #{inspect(steps)}"}

      repeated_threshold?(steps) ->
        {:error, "expected no threshold given twice, got: #{inspect(steps)}"}

      not zero_step?(steps) ->
        {:error,
         "expected a step at threshold 0, whose suffix the labels below every other step " <>
           "take, as {\"\", 0}, got: #{inspect(steps)}"}

      true ->
        {:ok, steps}
    end
  end

  # The breaks as floats, R's doubles, a negative zero made zero as R's `unique()` makes it.
  defp numbers!(breaks, function) when is_list(breaks) do
    if Enum.all?(breaks, &is_number/1) do
      Enum.map(breaks, fn value -> :erlang.float(value) + 0.0 end)
    else
      raise ArgumentError, "#{function} takes a list of numbers, got: #{inspect(breaks)}"
    end
  end

  defp numbers!(breaks, function) do
    raise ArgumentError, "#{function} takes a list of numbers, got: #{inspect(breaks)}"
  end

  # The options given, checked, with the formatter's defaults; `accuracy:` and `scale_cut:` have
  # none, so each is absent from the settings when not given.
  defp settings!(options, formatter) do
    options
    |> NimbleOptions.validate!(Map.fetch!(@formatter_schemas, formatter))
    |> Map.new()
  end

  defp steps?(steps), do: is_list(steps) and steps != [] and Enum.all?(steps, &step?/1)

  defp step?({suffix, threshold}),
    do: is_binary(suffix) and is_number(threshold) and threshold >= 0

  defp step?(_step), do: false

  defp repeated_threshold?(steps) do
    thresholds = thresholds(steps)
    Enum.uniq(thresholds) != thresholds
  end

  defp zero_step?(steps), do: 0.0 in thresholds(steps)

  defp thresholds(steps),
    do: Enum.map(steps, fn {_suffix, threshold} -> threshold * 1.0 + 0.0 end)

  # Currency's accuracy when neither `accuracy:` nor `scale_cut:` is given: cents when some
  # amount is not whole and none is larger than `largest_with_fractional:`, whole amounts
  # otherwise.
  defp with_cents(settings, _values) when is_map_key(settings, :accuracy), do: settings
  defp with_cents(settings, _values) when is_map_key(settings, :scale_cut), do: settings

  defp with_cents(settings, values) do
    amounts = Enum.map(values, fn value -> value * settings.scale end)
    small = Enum.all?(amounts, fn amount -> abs(amount) <= settings.largest_with_fractional end)
    accuracy = if small and not Enum.all?(amounts, &whole?/1), do: 0.01, else: 1
    Map.put(settings, :accuracy, accuracy)
  end

  defp without_mark_collision(%{big_mark: ",", decimal_mark: ","} = settings),
    do: %{settings | big_mark: " "}

  defp without_mark_collision(settings), do: settings

  # A set of steps, with a space before each suffix when `space:` says so.
  defp spaced(steps, options) do
    space =
      options
      |> NimbleOptions.validate!(@space_options)
      |> Keyword.fetch!(:space)

    if space,
      do: Enum.map(steps, fn {suffix, threshold} -> {" " <> suffix, threshold} end),
      else: steps
  end

  # A label for each value, in order.
  defp label(values, settings) do
    values
    |> scaled(settings)
    |> with_accuracy(settings)
    |> Enum.map(&rounded/1)
    |> texts(settings)
    |> Enum.map(fn {number, text} ->
      signed(settings.prefix <> text <> number.suffix, number.sign, settings)
    end)
  end

  # Each value with the scale it is written at and the suffix it takes: the formatter's own, or
  # under `scale_cut:` its step's.
  defp scaled(values, %{scale_cut: steps} = settings) do
    scale = settings.scale * 1.0

    sorted = Enum.sort_by(steps, fn {_suffix, threshold} -> threshold end)

    Enum.map(values, fn value ->
      name = refined_step(value, scale, step_reached(value, scale, sorted), sorted)
      threshold = step_threshold(sorted, name)
      %{value: value, scale: step_scale(value, scale, threshold), suffix: name <> settings.suffix}
    end)
  end

  defp scaled(values, settings) do
    scale = settings.scale * 1.0
    Enum.map(values, fn value -> %{value: value, scale: scale, suffix: settings.suffix} end)
  end

  # The suffix of the last step whose threshold the value's magnitude reaches.
  defp step_reached(value, scale, steps) do
    magnitude = abs(value * scale)

    {name, _threshold} =
      steps
      |> Enum.take_while(fn {_name, threshold} -> threshold <= magnitude end)
      |> List.last()

    name
  end

  # A step's threshold found by its suffix, as R indexes a named vector: the first step with it,
  # and `:none` for an empty suffix, which R never matches.
  defp step_threshold(_steps, ""), do: :none

  defp step_threshold(steps, name) do
    {^name, threshold} = List.keyfind(steps, name, 0)
    threshold
  end

  # A value that is not a whole number of its step takes the step below when it is a whole
  # number of that one and the two are not a power of ten apart.
  defp refined_step(value, scale, name, steps),
    do: refined_step(value, scale, name, step_threshold(steps, name), steps)

  defp refined_step(_value, _scale, name, :none, _steps), do: name
  defp refined_step(_value, _scale, name, threshold, _steps) when threshold == 0, do: name

  defp refined_step(value, scale, name, threshold, steps) do
    if whole?(value * scale / threshold) do
      name
    else
      index = Enum.find_index(steps, fn {step_name, _threshold} -> step_name == name end)
      {lower_name, lower_threshold} = Enum.at(steps, index - 1)
      divisor = if lower_threshold == 0, do: 1.0, else: lower_threshold
      ratio = :math.log10(threshold / divisor)

      if whole?(value * scale / divisor) and not whole?(ratio), do: lower_name, else: name
    end
  end

  # The scale a value under `scale_cut:` is written at: its step's, the formatter's below the
  # first step, and 1 for zero.
  defp step_scale(value, _scale, _threshold) when value == 0, do: 1.0
  defp step_scale(_value, scale, :none), do: scale
  defp step_scale(_value, scale, threshold) when threshold == 0, do: scale
  defp step_scale(_value, scale, threshold), do: scale * (1 / threshold)

  # Each value's accuracy: `accuracy:`, or worked out over the values written at its scale.
  defp with_accuracy(numbers, %{accuracy: accuracy}),
    do: Enum.map(numbers, fn number -> Map.put(number, :accuracy, accuracy) end)

  defp with_accuracy(numbers, _settings) do
    accuracies =
      numbers
      |> Enum.group_by(fn number -> number.scale end, fn number -> number.value * number.scale end)
      |> Map.new(fn {scale, scaled} -> {scale, precision(scaled)} end)

    Enum.map(numbers, fn number -> Map.put(number, :accuracy, accuracies[number.scale]) end)
  end

  # The power of ten at or below the smallest gap when every value is a multiple of it, a tenth
  # of it otherwise, at most 1: R computes the tenth and multiplies by ten.
  defp precision(values) do
    sorted =
      values
      |> Enum.uniq()
      |> Enum.sort()

    case sorted do
      [_one] ->
        1.0

      _several ->
        smallest =
          sorted
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [low, high] -> high - low end)
          |> Enum.min()

        if smallest < @smallest_gap, do: 1.0, else: power_precision(sorted, smallest)
    end
  end

  defp power_precision(values, smallest) do
    power =
      smallest
      |> :math.log10()
      |> Float.floor()

    precision = 10.0 ** (power - 1)

    tenfold =
      Enum.all?(values, fn value ->
        multiple = round_half_even(value / precision)
        rem(trunc(multiple), 10) == 0
      end)

    if tenfold, do: min(precision * 10, 1.0), else: min(precision, 1.0)
  end

  # The value rounded to its accuracy, its sign after rounding, the number written (scaled and
  # without its sign) and the decimals its accuracy asks for.
  defp rounded(number) do
    step = number.accuracy / number.scale
    value = round_half_even(number.value / step) * step

    sign =
      cond do
        value > 0 -> 1
        value < 0 -> -1
        true -> 0
      end

    power =
      number.accuracy
      |> :math.log10()
      |> Float.floor()
      |> trunc()

    decimals =
      -power
      |> max(0)
      |> min(@max_decimals)

    Map.merge(number, %{sign: sign, magnitude: number.scale * abs(value), decimals: decimals})
  end

  # Each number with its text, written with the others sharing its decimal count.
  defp texts(numbers, settings) do
    texts =
      numbers
      |> Enum.with_index()
      |> Enum.group_by(fn {number, _index} -> number.decimals end)
      |> Enum.flat_map(fn {decimals, group} ->
        {group_numbers, indices} = Enum.unzip(group)
        magnitudes = Enum.map(group_numbers, fn number -> number.magnitude end)
        Enum.zip(indices, Fixed.write(magnitudes, decimals, settings))
      end)
      |> Map.new()

    Enum.with_index(numbers, fn number, index -> {number, Map.fetch!(texts, index)} end)
  end

  defp signed(text, -1, %{style_negative: :hyphen}), do: "-" <> text
  defp signed(text, -1, %{style_negative: :minus}), do: "−" <> text
  defp signed(text, -1, %{style_negative: :parens}), do: "(" <> text <> ")"
  defp signed(text, 1, %{style_positive: :plus}), do: "+" <> text
  defp signed(text, 1, %{style_positive: :space}), do: " " <> text
  defp signed(text, _sign, _settings), do: text

  # R's `round()`: to the nearest whole number, a half to the even one.
  defp round_half_even(value) do
    floor = Float.floor(value)

    case value - floor do
      fraction when fraction > 0.5 -> floor + 1
      fraction when fraction < 0.5 -> floor
      _half -> if rem(trunc(floor), 2) == 0, do: floor, else: floor + 1
    end
  end

  defp whole?(value), do: value == Float.floor(value)
end
