defmodule Scales.Labels do
  @moduledoc """
  Labels for a scale's breaks: numbers written plainly (`plain/1`), in decimals (`number/2`),
  with a comma between thousands (`comma/2`), as percentages (`percent/2`) and as amounts of
  money (`currency/2`).

  Each labeller is handed every break an axis or a legend draws and returns a label for each, in
  order, so the labels can share their decimals: `0.5`, `1` and `1.25` are labelled `0.50`,
  `1.00` and `1.25`. A missing break, `nil`, has no label, `nil`, as R's `NA` has none. One that
  takes options is handed on inside a function:

      fn breaks -> Scales.Labels.comma(breaks, accuracy: 0.1) end

  Labellers are composed by piping one's labels into the next, where R composes them with
  `compose_label()`:

      fn breaks ->
        breaks
        |> Scales.Labels.number(accuracy: 0.1)
        |> Enum.map(fn label -> label && label <> " m" end)
      end

  `plain/1` writes numbers as Elixir shows them, with what an axis read at a glance needs on top;
  the others write them as R's scales does, each a label to the character.

  ## How a label is written

  Each number is multiplied by `scale:`, then rounded to a multiple of `accuracy:`, a half going
  to the even neighbour (`2.5` to `2`, `3.5` to `4`). A number that rounds to zero has no sign.
  It is written in plain decimals, with as many decimals as the accuracy has (`0.01` writes two,
  `1` or more none) up to twenty, or more if a label needs them to show its first seven
  significant digits (an accuracy of `0.25` writes `0.25` and `0.50`); every label shares the
  most any needs. Only labels more than 310 characters longer than their scientific form, past
  about 1e290, are written in scientific notation, as R writes them. `big_mark:` goes between
  each three digits of the whole part
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
  #   FALSE)` writes them, by `Scales.Labels.Format`; then prefix, number and suffix, the sign
  #   outside them.
  # - `scale_cut` is `scales:::scale_cut`: steps are sorted by threshold; a step is looked up by
  #   its suffix as R indexes a named vector, the first step with it and never an empty suffix;
  #   a zero threshold never refines and divides by 1 below. R requires no zero step, but without
  #   one its lookup of the step below misaligns its vectors (`c(m = 60, h = 3600)` writes 5400
  #   as `5 400NA`), so one is required here (design-log §4, the entry beginning
  #   "`Scales.Labels`'s").
  #
  # Its options are checked by NimbleOptions, which the `Scales` boundary lists for it.

  alias Scales.Labels.Format

  @typedoc "A step for `scale_cut:`: the suffix written after a label, and the threshold it starts at."
  @type step :: {String.t(), number()}

  # The largest decimal count R's `number()` asks for.
  @max_decimals 20

  # R's `getOption("digits")`: the significant digits `format()` shows.
  @format_digits 7

  # The significant digits `plain/1` rounds each break to.
  @significant_digits 15

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
      doc:
        "How a positive is marked: `:none` (`1`), `:plus` (`+1`) or `:space`, a figure space " <>
          "as wide as a digit (`\"\\u20071\"`)."
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

  @number_defaults Keyword.put(@comma_defaults, :big_mark, " ")

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
                         {:number, @number_defaults, []},
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
  Labels numbers in decimals, R's `label_number()`, with a space between each three digits of the
  whole part.

  ## Options

  #{NimbleOptions.docs(@formatter_schemas.number)}

  ## Examples

      iex> Scales.Labels.number([-2.5, 0, 1.0e6])
      ["-2.5", "0.0", "1 000 000.0"]

      iex> Scales.Labels.number([1, nil, 1.5])
      ["1.0", nil, "1.5"]

      iex> Scales.Labels.number([0.001, 0.0025], scale: 1000, suffix: " ms")
      ["1.0 ms", "2.5 ms"]
  """
  @spec number([number() | nil], keyword()) :: [String.t() | nil]
  def number(breaks, options \\ []) do
    settings = settings!(options, :number)

    breaks
    |> numbers!("Labels.number/2")
    |> label(settings)
  end

  @doc """
  Labels numbers with a comma between each three digits of the whole part, R's `label_comma()`.

  ## Options

  #{NimbleOptions.docs(@formatter_schemas.comma)}

  ## Examples

      iex> Scales.Labels.comma([-100_000, 1_234_567.891, 0.125])
      ["-100,000", "1,234,568", "0"]

      iex> Scales.Labels.comma([0.5, 1, 1.25])
      ["0.50", "1.00", "1.25"]

      iex> Scales.Labels.comma([0, 1250, 2500], accuracy: 0.1, scale: 0.001, suffix: "k")
      ["0.0k", "1.2k", "2.5k"]

      iex> Scales.Labels.comma([0, 1500, 1.0e6], scale_cut: Scales.Labels.cut_short_scale())
      ["0", "2K", "1M"]
  """
  @spec comma([number() | nil], keyword()) :: [String.t() | nil]
  def comma(breaks, options \\ []) do
    settings = settings!(options, :comma)

    breaks
    |> numbers!("Labels.comma/2")
    |> label(settings)
  end

  @doc """
  Labels proportions as percentages, R's `label_percent()`: each is multiplied by 100 and written
  with a `%`.

  Thousands are marked with a space (`1 234%`).

  ## Options

  #{NimbleOptions.docs(@formatter_schemas.percent)}

  ## Examples

      iex> Scales.Labels.percent([0, 0.25, 0.5, 0.75, 1])
      ["0%", "25%", "50%", "75%", "100%"]

      iex> Scales.Labels.percent([0.1234, 0.5], accuracy: 0.1)
      ["12.3%", "50.0%"]

      iex> Scales.Labels.percent([-0.5, 0.125, 12.345])
      ["-50%", "12%", "1 234%"]
  """
  @spec percent([number() | nil], keyword()) :: [String.t() | nil]
  def percent(breaks, options \\ []) do
    settings = settings!(options, :percent)

    breaks
    |> numbers!("Labels.percent/2")
    |> label(settings)
  end

  @doc """
  Labels amounts of money, R's `label_currency()`, in dollars unless `prefix:` and `suffix:` say
  otherwise.

  Without `accuracy:` or `scale_cut:`, labels show cents when some amount is not whole and none
  is larger than `largest_with_fractional:`, and whole amounts otherwise. When both marks would
  be a comma, the thousands are marked with a space instead.

  ## Options

  #{NimbleOptions.docs(@formatter_schemas.currency)}

  ## Examples

      iex> Scales.Labels.currency([0, 50, 100])
      ["$0", "$50", "$100"]

      iex> Scales.Labels.currency([-13.5, 0, 13.5])
      ["-$13.50", "$0.00", "$13.50"]

      iex> Scales.Labels.currency([1234.5, 1], big_mark: ".", decimal_mark: ",", prefix: "", suffix: " €")
      ["1.234,50 €", "1,00 €"]

      iex> Scales.Labels.currency([0, 2.5e5, 5.0e5, 1.0e6], scale_cut: Scales.Labels.cut_short_scale())
      ["$0", "$250K", "$500K", "$1M"]
  """
  @spec currency([number() | nil], keyword()) :: [String.t() | nil]
  def currency(breaks, options \\ []) do
    values = numbers!(breaks, "Labels.currency/2")

    settings =
      options
      |> settings!(:currency)
      |> with_cents(values)
      |> without_mark_collision()

    label(values, settings)
  end

  @doc """
  The short scale's steps for `scale_cut:`, R's `cut_short_scale()`: thousands `K`, millions `M`,
  billions `B` (1e9) and trillions `T` (1e12).

  ## Options

  #{NimbleOptions.docs(@space_options)}

  ## Examples

      iex> Scales.Labels.cut_short_scale()
      [{"", 0}, {"K", 1000}, {"M", 1000000}, {"B", 1000000000}, {"T", 1000000000000}]

      iex> Scales.Labels.comma([-2000, 0, 2000], scale_cut: Scales.Labels.cut_short_scale(space: true))
      ["-2 K", "0 ", "2 K"]
  """
  @spec cut_short_scale(keyword()) :: [step()]
  def cut_short_scale(options \\ []), do: spaced(@short_scale, options)

  @doc """
  The long scale's steps for `scale_cut:`, R's `cut_long_scale()`: thousands `K`, millions `M`,
  billions `B` (1e12) and trillions `T` (1e18).

  ## Options

  #{NimbleOptions.docs(@space_options)}

  ## Examples

      iex> Scales.Labels.currency([0, 1.0e9, 2.0e12], scale_cut: Scales.Labels.cut_long_scale())
      ["$0", "$1,000M", "$2B"]
  """
  @spec cut_long_scale(keyword()) :: [step()]
  def cut_long_scale(options \\ []), do: spaced(@long_scale, options)

  @doc """
  The SI prefixes' steps for `scale_cut:`, R's `cut_si()`, from yocto (1e-24) to yotta (1e24),
  each written with a space and `unit` after it (`" kg"`), and `unit` alone below a yocto and
  from 1 to 1000.

  ## Examples

      iex> Scales.Labels.comma([0.001, 1, 1500], scale_cut: Scales.Labels.cut_si("g"))
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
    raise ArgumentError, "Labels.cut_si/1 takes the unit as a string, got: #{inspect(unit)}"
  end

  @doc """
  Steps of time for `scale_cut:`, R's `cut_time_scale()`, for labels in seconds: nanoseconds `ns`,
  microseconds `μs`, milliseconds `ms`, seconds `s`, minutes `m`, hours `h`, days `d` and weeks
  `w`.

  ## Options

  #{NimbleOptions.docs(@space_options)}

  ## Examples

      iex> Scales.Labels.comma([0, 45, 90, 120, 5400], scale_cut: Scales.Labels.cut_time_scale())
      ["0", "45s", "90s", "2m", "90m"]
  """
  @spec cut_time_scale(keyword()) :: [step()]
  def cut_time_scale(options \\ []), do: spaced(@time_scale, options)

  @doc """
  Labels numbers plainly, as Elixir shows a float, with what an axis read at a glance needs on
  top: every label gets as many decimals as the most precise one needs, none when every break is
  whole, never scientific notation and no thousands separators. Each break is first rounded to 15
  significant digits, which drops the rounding error that adding up steps leaves in the last
  digits (`0.3`, not `0.30000000000000004`), and a negative zero is written `0`. R's default
  labels come from `format()` instead, which writes `1e+05` where this writes `100000`.

  ## Examples

      iex> Scales.Labels.plain([0.0, 2.5, 5.0])
      ["0.0", "2.5", "5.0"]

      iex> Scales.Labels.plain([0.0, 250_000.0])
      ["0", "250000"]
  """
  @spec plain([float()]) :: [String.t()]
  def plain(breaks) do
    rounded = Enum.map(breaks, &round_significant/1)

    decimals =
      rounded
      |> Enum.map(&decimals_needed/1)
      |> Enum.max(fn -> 0 end)

    Enum.map(rounded, fn value -> :erlang.float_to_binary(value, decimals: decimals) end)
  end

  # Rounds through the 15-significant-digit scientific form; a zero of either sign becomes 0.0.
  # `:erlang.float_to_binary/2` takes a negative `scientific:` precision without complaint and uses
  # its default of six decimals, where a negative `decimals:` raises, so the example with a break
  # needing all fifteen digits is what pins the precision. Rounding error can reach the 16th
  # significant digit, as in some breaks R's `labeling::extended()` returns, and rounding to 15
  # digits drops it there too; a break that needs all 15 digits keeps them.
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

  # The breaks as floats, R's doubles, a negative zero made zero as R's `unique()` makes it, and
  # a missing one `nil`.
  defp numbers!(breaks, function) when is_list(breaks) do
    if Enum.all?(breaks, fn value -> is_number(value) or is_nil(value) end) do
      Enum.map(breaks, fn value -> value && :erlang.float(value) + 0.0 end)
    else
      raise ArgumentError,
            "#{function} takes a list of numbers and nils, got: #{inspect(breaks)}"
    end
  end

  defp numbers!(breaks, function) do
    raise ArgumentError, "#{function} takes a list of numbers and nils, got: #{inspect(breaks)}"
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
    amounts = for value <- values, value != nil, do: value * settings.scale
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
    |> Enum.map(fn
      {%{value: nil}, _text} -> nil
      {number, text} -> signed(settings.prefix <> text <> number.suffix, number.sign, settings)
    end)
  end

  # Each value with the scale it is written at and the suffix it takes: the formatter's own, or
  # under `scale_cut:` its step's.
  defp scaled(values, %{scale_cut: steps} = settings) do
    scale = settings.scale * 1.0

    sorted = Enum.sort_by(steps, fn {_suffix, threshold} -> threshold end)

    Enum.map(values, fn
      nil ->
        %{value: nil, scale: scale, suffix: settings.suffix}

      value ->
        name = refined_step(value, scale, step_reached(value, scale, sorted), sorted)
        threshold = step_threshold(sorted, name)

        %{
          value: value,
          scale: step_scale(value, scale, threshold),
          suffix: name <> settings.suffix
        }
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
      |> Enum.group_by(fn number -> number.scale end, fn number -> number.value end)
      |> Map.new(fn {scale, values} ->
        {scale, precision(for value <- values, value != nil, do: value * scale)}
      end)

    Enum.map(numbers, fn number -> Map.put(number, :accuracy, accuracies[number.scale]) end)
  end

  # The power of ten at or below the smallest gap when every value is a multiple of it, a tenth
  # of it otherwise, at most 1: R computes the tenth and multiplies by ten. Fewer than two values
  # take 1.
  defp precision(values) do
    sorted =
      values
      |> Enum.uniq()
      |> Enum.sort()

    case sorted do
      [] ->
        1.0

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
  # without its sign) and the decimals its accuracy asks for; a missing one has no sign and is
  # written missing.
  defp rounded(number) do
    {sign, magnitude} = rounded_value(number)

    power =
      number.accuracy
      |> :math.log10()
      |> Float.floor()
      |> trunc()

    decimals =
      -power
      |> max(0)
      |> min(@max_decimals)

    Map.merge(number, %{sign: sign, magnitude: magnitude, decimals: decimals})
  end

  defp rounded_value(%{value: nil}), do: {0, nil}

  defp rounded_value(number) do
    step = number.accuracy / number.scale
    value = round_half_even(number.value / step) * step

    sign =
      cond do
        value > 0 -> 1
        value < 0 -> -1
        true -> 0
      end

    {sign, number.scale * abs(value)}
  end

  # Each number with its text, written with the others sharing its decimal count, as R's
  # `format()` writes them in plain decimals; a missing one widens the others' padding to its
  # `NA`, as in R.
  defp texts(numbers, settings) do
    texts =
      numbers
      |> Enum.with_index()
      |> Enum.group_by(fn {number, _index} -> number.decimals end)
      |> Enum.flat_map(fn {decimals, group} ->
        {group_numbers, indices} = Enum.unzip(group)
        magnitudes = Enum.map(group_numbers, fn number -> number.magnitude end)

        written =
          Format.write(
            magnitudes,
            Map.merge(settings, %{digits: @format_digits, nsmall: decimals, notation: :fixed})
          )

        Enum.zip(indices, written)
      end)
      |> Map.new()

    Enum.with_index(numbers, fn number, index -> {number, Map.fetch!(texts, index)} end)
  end

  defp signed(text, -1, %{style_negative: :hyphen}), do: "-" <> text
  defp signed(text, -1, %{style_negative: :minus}), do: "−" <> text
  defp signed(text, -1, %{style_negative: :parens}), do: "(" <> text <> ")"
  defp signed(text, 1, %{style_positive: :plus}), do: "+" <> text
  defp signed(text, 1, %{style_positive: :space}), do: " " <> text
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
