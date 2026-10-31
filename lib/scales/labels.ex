defmodule Scales.Labels do
  @moduledoc """
  Labels for a scale's breaks: numbers written plainly (`plain/1`), in decimals (`number/2`),
  with a comma between thousands (`comma/2`), as percentages (`percent/2`), as amounts of money
  (`currency/2`), in scientific notation (`scientific/2`), in whichever way suits their size
  (`number_auto/1`), as powers (`log/2`, or as text, `format_log/2`), as bytes (`bytes/2`), as
  ordinals (`ordinal/2`), as p-values (`pvalue/2`), as spans of time (`timespan/2`), and dates,
  date-times and times of day in a format (`date/2`, `time/2`) or by what changed from the break
  before (`date_short/2`).

  Each labeller is handed every break an axis or a legend draws and returns a label for each, in
  order, so the labels can share their decimals: `0.5`, `1` and `1.25` are labelled `0.50`,
  `1.00` and `1.25`. A label is text, but for `log/2`'s powers (`t:power_label/0`). A missing
  break, `nil`, has no label, `nil`, as R's `NA` has none, but where `number_auto/1` writes it
  `"NA"`. One that takes options is handed on inside a function:

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
  One that `scale:` takes past the largest float is labelled `Inf` or `-Inf`, without
  `prefix:` and `suffix:` where rounding takes it past (and inside them where only the scaling
  does), and takes no part in the others' accuracy, cents or step.
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
  #   outside them. Where R's `round_any()` takes a break to an infinity, `number()` writes
  #   `as.character(x)` over the label, so `Inf` loses its prefix and suffix but keeps its sign;
  #   R's `cut()` finds no step for an infinite break, `needs_cents()` no cents, and
  #   `precision()` drops it, or takes an infinite gap to 1. Erlang raises where R reaches an
  #   infinity, so those operations are `Scales.Labels.Arithmetic`'s.
  # - `scale_cut` is `scales:::scale_cut`: steps are sorted by threshold; a step is looked up by
  #   its suffix as R indexes a named vector, the first step with it and never an empty suffix;
  #   a zero threshold never refines and divides by 1 below. R requires no zero step, but without
  #   one its lookup of the step below misaligns its vectors (`c(m = 60, h = 3600)` writes 5400
  #   as `5 400NA`), so one is required here (design-log §4, the entry beginning
  #   "`Scales.Labels`'s").
  # - `scientific/2` is `label_scientific()`: `signif(x * scale, digits)`, `Scales.Labels.Arithmetic`
  #   in R's order of floating-point operations, then `format(scientific = TRUE)` at R's default
  #   7 digits, trimmed. `label_scientific()` never hands `scientific()` its `trim`, so there is
  #   no `trim:`; nor `big_mark:` or `nsmall:`, which R's `...` takes and scientific notation
  #   never shows.
  # - `number_auto/1` is `label_number_auto()`'s branches in R's order, `format_shortest()` each
  #   label's shorter, the first on a tie. A missing break is R's `"NA"` where R writes them with
  #   `format(trim = TRUE)`, and `nil` from `number()` and where R breaks: its years test reads
  #   the numbers alone, where R fails on an `NA`, and its shortest is `nil` where R's
  #   `which.min()` finds no label (design-log §4, the entry beginning "A missing break's label").
  # - `format_log/2` is `format_log()`: signed when any finite break is at or below zero, the
  #   exponents `format(zapsmall(log(x, base)), digits)`, untrimmed, after R's `paste0()` of the
  #   sign and the base, written as `as.character()` writes a number, in 15 digits. `log/2` is
  #   `label_log()`: that text parsed and each number deparsed, again in 15 digits, so `10^ 0`
  #   is `{:power, "10", "0"}` and an exponent of `6.91e+06` is `"6910000"`; a sign is R's unary
  #   call around the power. R's answers for a base of 0, 1 or below 0, and for an unsigned break
  #   at or below zero, are not powers of anything (`1^NaN`, `10^-Inf`, and `zapsmall()` rounding
  #   every exponent whole beside an infinite one), so each is refused (design-log §4, the entry
  #   beginning "`log/2` refuses").
  # - `bytes/2` is `label_bytes()`: `number()` under R's `cut_bytes()` steps, or a fixed unit's
  #   suffix and `scale / base^power`, R's order. R's binary steps write plain bytes `" iB"`,
  #   which R's NEWS says is always `"B"`, so this writes `" B"` (design-log §4, the entry
  #   beginning "Plain bytes under binary units").
  # - `ordinal/2` is `ordinal()`: `round(x)`, a missing break written as 1 and dropped, then
  #   `number(accuracy = 1)` and the first matching rule's suffix. R pastes the suffixes in the
  #   order the rules matched, not the breaks', so a break no rule matches takes another's; that
  #   raises here. R matches `as.character()`, scientific for a round number where shorter; the
  #   digits are matched here (design-log §4, the entries beginning "`ordinal/2`'s rules are
  #   matched" and "`ordinal/2` takes").
  # - `pvalue/2` is `pvalue()`: `number(x, accuracy)`, the bounds' labels written alone the same
  #   way. Above an accuracy of 0.5 a p-value can be both below it and above 1 less it, and R's
  #   label then says what is false, so the accuracy is at most 0.5; R lets `prefix` silently
  #   win over `add_p`, which raises here (design-log §4, the entry beginning "`pvalue/2`'s
  #   accuracy").
  # - `timespan/2` is `label_timespan()`: each break times its unit's seconds, R's `difftime`
  #   conversion, then `number()` under `cut_time_scale()`; a break the unit takes past the
  #   largest double is R's `Inf`, which `number()` writes as its own `as.character()`.
  # - `date/2`, `date_short/2` and `time/2` are `label_date()`, `label_date_short()` and
  #   `label_time()`, R's `format()` of a date or date-time in `tz`, written by
  #   `Calendar.strftime/3` with an unpadded year (`Scales.Labels.DateFormat`, design-log §4, the
  #   entry beginning "The date labellers take"). R recycles a vector of formats and reads `""`
  #   as `format()`'s default; one non-empty string is taken. R's `locale` is left out, and an
  #   unknown `tz`, which R writes as UTC under a made-up abbreviation, raises.
  #
  # Its options are checked by NimbleOptions, which the `Scales` boundary lists for it.

  alias Scales.DateBreaks
  alias Scales.Labels.{Arithmetic, DateFormat, Format}

  @typedoc "A step for `scale_cut:`: the suffix written after a label, and the threshold it starts at."
  @type step :: {String.t(), number()}

  @typedoc """
  A power `log/2` labels a break with, its base and its exponent each written as text: `10^3`
  is `{:power, "10", "3"}`.
  """
  @type power :: {:power, String.t(), String.t()}

  @typedoc """
  A label of `log/2`: a power, a power with a sign before it (`-10^3` is
  `{:signed, "-", {:power, "10", "3"}}`), the text `"0"` for a signed zero, or `nil` for a
  missing break.
  """
  @type power_label :: power() | {:signed, String.t(), power()} | String.t() | nil

  # The largest decimal count R's `number()` asks for.
  @max_decimals 20

  # R's `getOption("digits")`: the significant digits `format()` shows.
  @format_digits 7

  # The significant digits `plain/1` rounds each break to.
  @significant_digits 15

  # The significant digits R writes a number in when it writes one alone, as `as.character()`
  # and `deparse()` do.
  @alone_digits 15

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

  # The shared options named, in their order, each with its default in `defaults` where it has
  # one.
  defaulted = fn names, defaults ->
    @formatter_options
    |> Keyword.take(names)
    |> Enum.map(fn {name, spec} ->
      case Keyword.fetch(defaults, name) do
        {:ok, default} -> {name, Keyword.put(spec, :default, default)}
        :error -> {name, spec}
      end
    end)
  end

  # Each formatter's options: the shared ones with its defaults, and currency's own.
  @formatter_schemas Map.new(
                       [
                         {:number, @number_defaults, []},
                         {:comma, @comma_defaults, []},
                         {:percent, @percent_defaults, []},
                         {:currency, @currency_defaults, @currency_options}
                       ],
                       fn {formatter, defaults, own} ->
                         options = defaulted.(Keyword.keys(@formatter_options), defaults)
                         {formatter, NimbleOptions.new!(options ++ own)}
                       end
                     )

  # The prefixes of `bytes/2`'s units, each a power of 1000 or 1024 above the last.
  @byte_prefixes ~w(k M G T P E Z Y)

  # `bytes/2`'s fixed units, R's spelling, each with its base and power.
  @byte_units Map.new(
                for {base, symbol} <- [{1000.0, "B"}, {1024.0, "iB"}],
                    {prefix, power} <- Enum.with_index(@byte_prefixes, 1),
                    do: {prefix <> symbol, {base, power}}
              )

  @byte_unit_names for symbol <- ["B", "iB"], prefix <- @byte_prefixes, do: prefix <> symbol

  # `bytes/2`'s automatic units, R's `cut_bytes()`, but for plain bytes' suffix under binary
  # units, `" B"` where R writes `" iB"`.
  @byte_steps Map.new([auto_si: {1000.0, "B"}, auto_binary: {1024.0, "iB"}], fn {units,
                                                                                 {base, symbol}} ->
                steps =
                  for {prefix, power} <- Enum.with_index(@byte_prefixes, 1),
                      do: {" " <> prefix <> symbol, base ** power}

                {units, [{" B", 0} | steps]}
              end)

  @bytes_options NimbleOptions.new!(
                   [
                     units: [
                       type: {:custom, __MODULE__, :validate_units, []},
                       default: :auto_si,
                       doc:
                         "`:auto_si`, each label in the SI unit, a power of 1000, that suits " <>
                           "it; `:auto_binary`, in the binary unit, a power of 1024; or a unit " <>
                           "every label is written in, spelt as R spells it: " <>
                           Enum.map_join(@byte_unit_names, ", ", fn name ->
                             "`#{inspect(name)}`"
                           end) <>
                           "."
                     ]
                   ] ++
                     Keyword.update!(
                       defaulted.(
                         [
                           :accuracy,
                           :scale,
                           :prefix,
                           :big_mark,
                           :decimal_mark,
                           :trim,
                           :style_negative,
                           :style_positive
                         ],
                         Keyword.put(@number_defaults, :accuracy, 1)
                       ),
                       :accuracy,
                       fn spec ->
                         Keyword.merge(spec,
                           type: {:or, [{:custom, __MODULE__, :validate_positive, []}, nil]},
                           doc:
                             "A positive number each label is rounded to a multiple of, in " <>
                               "its unit, or `nil` to work it out from the breaks (see the " <>
                               "module's documentation)."
                         )
                       end
                     )
                 )

  @ordinal_options NimbleOptions.new!(
                     [
                       rules: [
                         type: {:custom, __MODULE__, :validate_rules, []},
                         doc:
                           "A list of `{suffix, regex}` pairs, each break taking the suffix " <>
                             "of the first whose regex matches it (see the function's " <>
                             "documentation); `ordinal_english/0`'s when not given."
                       ]
                     ] ++
                       Keyword.update!(
                         defaulted.(
                           [:prefix, :suffix, :big_mark, :trim, :style_negative, :style_positive],
                           @number_defaults
                         ),
                         :suffix,
                         fn spec ->
                           Keyword.put(spec, :doc, "Text written after the ordinal's.")
                         end
                       )
                   )

  @pvalue_options NimbleOptions.new!(
                    accuracy: [
                      type: {:custom, __MODULE__, :validate_pvalue_accuracy, []},
                      default: 0.001,
                      doc:
                        "A positive number no larger than 0.5 each label is rounded to a " <>
                          "multiple of; below it a p-value is written as less than it, and " <>
                          "above 1 less it as more than that."
                    ],
                    decimal_mark: Keyword.put(@formatter_options[:decimal_mark], :default, "."),
                    prefix: [
                      type: {:custom, __MODULE__, :validate_pvalue_prefix, []},
                      doc:
                        "Three strings, `{below, between, above}`, written before a p-value " <>
                          "below the accuracy, one between, and one above 1 less it; " <>
                          ~s(`{"<", "", ">"}` when not given.)
                    ],
                    add_p: [
                      type: :boolean,
                      default: false,
                      doc:
                        ~s(`true` writes the prefixes `{"p<", "p=", "p>"}`; not taken with ) <>
                          "`prefix:`."
                    ]
                  )

  # The seconds in each unit `timespan/2` counts its breaks in.
  @unit_seconds %{second: 1.0, minute: 60.0, hour: 3600.0, day: 86_400.0, week: 604_800.0}

  @timespan_options NimbleOptions.new!(
                      [
                        unit: [
                          type: {:in, [:second, :minute, :hour, :day, :week]},
                          default: :second,
                          doc:
                            "The unit the breaks are counted in, `:second`, `:minute`, " <>
                              "`:hour`, `:day` or `:week`."
                        ],
                        space: [
                          type: :boolean,
                          default: false,
                          doc: "`true` puts a space before each unit's suffix (`90 s`)."
                        ]
                      ] ++
                        defaulted.(
                          Keyword.keys(@formatter_options) -- [:scale_cut],
                          @number_defaults
                        )
                    )

  @time_zone_options [
    tz: [
      type: :string,
      default: "Etc/UTC",
      doc:
        "The time zone each `DateTime` is shifted into before it is written, one " <>
          "`time_zone_database:` knows; a `Date` is written at midnight UTC and a " <>
          "`NaiveDateTime` or `Time` as it is."
    ],
    time_zone_database: [
      type: :atom,
      default: Calendar.UTCOnlyTimeZoneDatabase,
      doc:
        "The time zone database that reads `tz:`, such as `Tz.TimeZoneDatabase`; Elixir's " <>
          "own, which knows UTC alone, when not given."
    ]
  ]

  # `date/2`'s and `time/2`'s options, each with its default format.
  @date_schemas Map.new([date: "%Y-%m-%d", time: "%H:%M:%S"], fn {function, default} ->
                  format = [
                    type: {:custom, __MODULE__, :validate_date_format, []},
                    default: default,
                    doc:
                      "The format each break is written in, as `Calendar.strftime/3` takes it, " <>
                        "but for `%Y`, the year unpadded."
                  ]

                  {function, NimbleOptions.new!([format: format] ++ @time_zone_options)}
                end)

  # `date_short/2`'s part formats, each R's default.
  @short_parts [year: "%Y", month: "%b", day: "%d", time: "%H:%M"]

  @date_short_options NimbleOptions.new!(
                        [
                          format: [
                            type: :keyword_list,
                            default: [],
                            keys:
                              Enum.map(@short_parts, fn {part, default} ->
                                {part,
                                 [
                                   type:
                                     {:or,
                                      [nil, {:custom, __MODULE__, :validate_date_format, []}]},
                                   default: default,
                                   doc:
                                     "The #{part}'s format, or `nil` for a #{part} never " <>
                                       "written."
                                 ]}
                              end),
                            doc:
                              "Each part's format, as `Calendar.strftime/3` takes it, but for " <>
                                "`%Y`, the year unpadded; a part left out keeps its default."
                          ],
                          sep: [
                            type: :string,
                            default: "\n",
                            doc: "The text written between the parts."
                          ],
                          leading: [
                            type: :string,
                            default: "0",
                            doc:
                              "The text that replaces a `0` at the start of each part: `\" \"` " <>
                                "writes the 5th `\" 5\"`, `\"\"` writes it `\"5\"`."
                          ]
                        ] ++ @time_zone_options
                      )

  # The significant digits each label of `scientific/2` and each exponent of `log/2` and
  # `format_log/2` is written in, R's `format()` range.
  @digits_option [
    type: {:in, 1..22},
    doc:
      "An integer from 1 to 22, the most significant digits shown, though no label shows more " <>
        "than 7 (see the function's documentation)."
  ]

  @scientific_options NimbleOptions.new!(
                        digits: Keyword.put(@digits_option, :default, 3),
                        scale: Keyword.put(@formatter_options[:scale], :default, 1),
                        prefix: [
                          type: :string,
                          default: "",
                          doc: "Text written before the number."
                        ],
                        suffix: [
                          type: :string,
                          default: "",
                          doc: "Text written after the number."
                        ],
                        decimal_mark:
                          Keyword.put(@formatter_options[:decimal_mark], :default, ".")
                      )

  @log_options [
    base: [
      type: {:custom, __MODULE__, :validate_base, []},
      default: 10,
      doc: "The base of the logarithm, a positive number other than 1."
    ],
    signed: [
      type: {:in, [:auto, true, false]},
      default: :auto,
      doc:
        "Whether each label is signed, `+` or `-` before its power and a zero `\"0\"`; " <>
          "`:auto` signs them when any break is zero or negative. Unsigned, a break at or " <>
          "below zero raises."
    ]
  ]

  # `log/2`'s and `format_log/2`'s options, each with its default digits.
  @log_schemas Map.new([log: 3, format_log: 7], fn {function, default} ->
                 digits = Keyword.put(@digits_option, :default, default)

                 schema =
                   @log_options
                   |> Keyword.merge(digits: digits)
                   |> NimbleOptions.new!()

                 {function, schema}
               end)

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
  Labels numbers in scientific notation, R's `label_scientific()`.

  Each break is multiplied by `scale:` and rounded to `digits:` significant digits, a half to the
  even neighbour of the number as a float scaled into its digits (`0.15` to one digit is `2e-01`).
  The labels are then written together, their mantissas sharing the most decimals any needs, in
  at most 7 significant digits: `digits:` above 7 shows 7. They are never padded. A break that
  `scale:` takes past the largest float is written `Inf` or `-Inf`.

  ## Options

  #{NimbleOptions.docs(@scientific_options)}

  ## Examples

      iex> Scales.Labels.scientific([0.15, 1.5, 12345])
      ["1.50e-01", "1.50e+00", "1.23e+04"]

      iex> Scales.Labels.scientific([1, 10, nil, 100])
      ["1e+00", "1e+01", nil, "1e+02"]

      iex> Scales.Labels.scientific([1234, 5], decimal_mark: ",", suffix: " m")
      ["1,23e+03 m", "5,00e+00 m"]
  """
  @spec scientific([number() | nil], keyword()) :: [String.t() | nil]
  def scientific(breaks, options \\ []) do
    settings =
      options
      |> NimbleOptions.validate!(@scientific_options)
      |> Map.new()

    rounded =
      breaks
      |> numbers!("Labels.scientific/2")
      |> Enum.map(fn value ->
        value &&
          value
          |> Arithmetic.product(settings.scale)
          |> Arithmetic.signif(settings.digits)
      end)

    rounded
    |> Format.write(format_settings(@format_digits, :scientific, settings.decimal_mark))
    |> Enum.zip_with(rounded, fn text, value ->
      value && settings.prefix <> text <> settings.suffix
    end)
  end

  @doc """
  Labels numbers in whichever way suits their size, R's `label_number_auto()`.

  The way is chosen by the largest and smallest magnitudes of the breaks other than zero:

  - any above a million: each label in whole numbers with a space between each three digits, as
    `number(breaks, accuracy: 1)` writes it, or in scientific notation, whichever is shorter,
    the whole number on a tie;
  - any below 0.001: each in plain decimals or in scientific notation, whichever is shorter,
    plain on a tie;
  - all positive, from 1000 to 2200, as years are: in plain decimals, with no mark between
    thousands;
  - any above 1000: as `number(breaks, accuracy: 1)` writes them;
  - otherwise in plain decimals, or in scientific notation where that is narrower for all.

  Plain decimals and scientific notation are written with every label sharing its decimals, in
  up to 7 significant digits, each way on its own when the shorter of two is taken. A missing
  break is labelled with the text `"NA"` in the years' way and the last, and has no label in the
  others.

  ## Examples

      iex> Scales.Labels.number_auto([0, 2.5e6, 5.0e6])
      ["0", "2.5e+06", "5.0e+06"]

      iex> Scales.Labels.number_auto([1990, 2000, 2010])
      ["1990", "2000", "2010"]

      iex> Scales.Labels.number_auto([0, 5000, 10_000, nil])
      ["0", "5 000", "10 000", nil]

      iex> Scales.Labels.number_auto([0, 0.5, nil])
      ["0.0", "0.5", "NA"]
  """
  @spec number_auto([number() | nil]) :: [String.t() | nil]
  def number_auto(breaks) do
    values = numbers!(breaks, "Labels.number_auto/1")

    case automatic_way(values) do
      :large -> shortest(number(values, accuracy: 1), written_alone(values, :scientific))
      :small -> shortest(written_alone(values, :fixed), written_alone(values, :scientific))
      :whole -> number(values, accuracy: 1)
      :together -> Format.write(values, format_settings(@format_digits, :auto, "."))
    end
  end

  @doc """
  Labels numbers as powers of `base:`, R's `label_log()`: `1000` is `{:power, "10", "3"}`, drawn
  as a superscript.

  Each break's exponent, its logarithm in `base:`, is rounded to the seventh significant digit
  of the largest exponent's, then the exponents are written together in up to `digits:`
  significant digits, sharing their decimals, and each is read back and written alone in up to
  15, its zeros after the last significant digit dropped: `2` is `{:power, "10", "0.301"}`, and
  `1` beside it `{:power, "10", "0"}`. No exponent shows more than 7 significant digits. The
  base is written in up to 15 significant digits too, in plain or scientific notation,
  whichever is shorter (`"2.71828182845905"` for e, `"1e+06"`).

  Signed, each power has its sign before it, `{:signed, "-", power}` or `{:signed, "+", power}`,
  and a zero is labelled `"0"`. A missing break has no label.

  ## Options

  #{NimbleOptions.docs(@log_schemas.log)}

  ## Examples

      iex> Scales.Labels.log([0.01, 1, 100])
      [{:power, "10", "-2"}, {:power, "10", "0"}, {:power, "10", "2"}]

      iex> Scales.Labels.log([1, 2, 8], base: 2)
      [{:power, "2", "0"}, {:power, "2", "1"}, {:power, "2", "3"}]

      iex> Scales.Labels.log([-100, 0, 100])
      [{:signed, "-", {:power, "10", "2"}}, "0", {:signed, "+", {:power, "10", "2"}}]
  """
  @spec log([number() | nil], keyword()) :: [power_label()]
  def log(breaks, options \\ []) do
    {base, parts} = powers(breaks, options, :log)

    Enum.map(parts, fn
      nil -> nil
      :zero -> "0"
      {"", exponent} -> {:power, base, read_back(exponent)}
      {sign, exponent} -> {:signed, sign, {:power, base, read_back(exponent)}}
    end)
  end

  @doc """
  Writes numbers as powers of `base:` in text, R's `format_log()`: `log/2`'s labels each written
  `base^exponent`, its exponent as the exponents are written together, padded on the left to the
  widest, in up to `digits:` significant digits.

  ## Options

  #{NimbleOptions.docs(@log_schemas.format_log)}

  ## Examples

      iex> Scales.Labels.format_log([0.01, 1, 100])
      ["10^-2", "10^ 0", "10^ 2"]

      iex> Scales.Labels.format_log([0.5, 2, 8], digits: 3)
      ["10^-0.301", "10^ 0.301", "10^ 0.903"]

      iex> Scales.Labels.format_log([-100, 0, 100])
      ["-10^2", "0", "+10^2"]
  """
  @spec format_log([number() | nil], keyword()) :: [String.t() | nil]
  def format_log(breaks, options \\ []) do
    {base, parts} = powers(breaks, options, :format_log)

    Enum.map(parts, fn
      nil -> nil
      :zero -> "0"
      {sign, exponent} -> sign <> base <> "^" <> exponent
    end)
  end

  @doc """
  Labels numbers of bytes, R's `label_bytes()`: in the unit that suits each, `1500` is `2 kB`, or
  all in one unit.

  Each label is written as `number/2` writes it, the unit its suffix. Under `:auto_si` and
  `:auto_binary`, each break takes the largest unit it reaches, as `scale_cut:` does, and plain
  bytes are `B`, a break that is not a whole number of its unit but is of plain bytes written in
  bytes (`1500` is `1 500 B` under `:auto_binary`); in one unit, `scale:` is divided by the
  unit's size. Labels are rounded to whole units unless `accuracy:` says otherwise.

  ## Options

  #{NimbleOptions.docs(@bytes_options)}

  ## Examples

      iex> Scales.Labels.bytes([0, 1500, 2.0e6, nil])
      ["0 B", "2 kB", "2 MB", nil]

      iex> Scales.Labels.bytes([512, 1024, 1_048_576], units: :auto_binary)
      ["512 B", "1 kiB", "1 MiB"]

      iex> Scales.Labels.bytes([1500, 2500, 1.0e6], accuracy: nil)
      ["1.5 kB", "2.5 kB", "1 MB"]

      iex> Scales.Labels.bytes([1.0e6, 2.5e6], units: "kB", big_mark: ",")
      ["1,000 kB", "2,500 kB"]
  """
  @spec bytes([number() | nil], keyword()) :: [String.t() | nil]
  def bytes(breaks, options \\ []) do
    settings =
      options
      |> NimbleOptions.validate!(@bytes_options)
      |> Map.new()
      |> in_units()
      |> without_given_accuracy()

    breaks
    |> numbers!("Labels.bytes/2")
    |> label(settings)
  end

  @doc """
  Labels numbers as ordinals, R's `label_ordinal()`: `1st`, `2nd`, `3rd`, `4th`.

  Each break is rounded to a whole number, a half to the even one, and written as `number/2`
  writes it with an accuracy of 1, then the suffix of the first rule whose regex matches the
  whole number's digits: unmarked and unpadded, a negative's with a `-` before them (`"-12"`).
  R matches the text it writes a number in alone, which for a round number is scientific
  notation wherever that is shorter (`2e+05`); the digits are matched here, so a rule reading the
  last digit sees `200000`'s `0`, and English ordinals from 1e21 up, which R writes `...st` from
  `1e+21`, are `...th`. A break no rule matches raises, so the rules end with one every break
  matches, as `ordinal_english/0`'s do.

  ## Options

  #{NimbleOptions.docs(@ordinal_options)}

  ## Examples

      iex> Scales.Labels.ordinal([1, 2, 3, 4, 11, 12, 13, 21, nil])
      ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", nil]

      iex> Scales.Labels.ordinal([1, 1001, 2.5], big_mark: ",", prefix: "#")
      ["#1st", "#1,001st", "#2nd"]

      iex> Scales.Labels.ordinal([1, 2], rules: [{"º", ~r/./}])
      ["1º", "2º"]
  """
  @spec ordinal([number() | nil], keyword()) :: [String.t() | nil]
  def ordinal(breaks, options \\ []) do
    settings =
      options
      |> NimbleOptions.validate!(@ordinal_options)
      |> Map.new()

    rules = Map.get_lazy(settings, :rules, &ordinal_english/0)

    rounded =
      breaks
      |> numbers!("Labels.ordinal/2")
      |> Enum.map(fn value -> value && Arithmetic.nearest(value) end)

    # A missing break is written as 1 and its label dropped, as R writes it, so it widens no
    # padding to `NA`'s width.
    numbers =
      rounded
      |> Enum.map(fn value -> value || 1.0 end)
      |> label(Map.merge(settings, %{accuracy: 1, scale: 1, suffix: "", decimal_mark: "."}))

    Enum.zip_with(rounded, numbers, fn
      nil, _number -> nil
      value, number -> number <> ordinal_suffix(value, rules) <> settings.suffix
    end)
  end

  @doc """
  English ordinals' rules for `ordinal/2`, R's `ordinal_english()`: `st` after a 1, `nd` after a
  2 and `rd` after a 3, but for 11, 12 and 13, and `th` after anything else.

  ## Examples

      iex> Scales.Labels.ordinal_english() |> Enum.map(fn {suffix, _rule} -> suffix end)
      ["st", "nd", "rd", "th", "th", "th"]
  """
  @spec ordinal_english() :: [{String.t(), Regex.t()}]
  def ordinal_english do
    [
      {"st", ~r/(?<!1)1$/},
      {"nd", ~r/(?<!1)2$/},
      {"rd", ~r/(?<!1)3$/},
      {"th", ~r/(?<=1)[123]$/},
      {"th", ~r/[0456789]$/},
      {"th", ~r/./}
    ]
  end

  @doc """
  Labels p-values, R's `label_pvalue()`: each rounded to `accuracy:` as `number/2` rounds it,
  one below the accuracy written as less than it (`<0.001`) and one above 1 less the accuracy
  as more than that (`>0.999`).

  ## Options

  #{NimbleOptions.docs(@pvalue_options)}

  ## Examples

      iex> Scales.Labels.pvalue([0.0001, 0.05, 0.5, 0.9999, nil])
      ["<0.001", "0.050", "0.500", ">0.999", nil]

      iex> Scales.Labels.pvalue([0.001, 0.123, 0.999], accuracy: 0.01, add_p: true)
      ["p<0.01", "p=0.12", "p>0.99"]

      iex> Scales.Labels.pvalue([0.0001, 0.05], prefix: {"less than ", "", "more than "})
      ["less than 0.001", "0.050"]
  """
  @spec pvalue([number() | nil], keyword()) :: [String.t() | nil]
  def pvalue(breaks, options \\ []) do
    settings =
      options
      |> NimbleOptions.validate!(@pvalue_options)
      |> Map.new()

    {below, between, above} = pvalue_prefix(settings)
    values = numbers!(breaks, "Labels.pvalue/2")
    accuracy = settings.accuracy
    highest = 1 - accuracy

    written = fn numbers ->
      number(numbers, accuracy: accuracy, decimal_mark: settings.decimal_mark)
    end

    [lowest_label] = written.([accuracy])
    [highest_label] = written.([highest])

    values
    |> written.()
    |> Enum.zip_with(values, fn
      _label, nil -> nil
      _label, value when value < accuracy -> below <> lowest_label
      _label, value when value > highest -> above <> highest_label
      label, _value -> between <> label
    end)
  end

  @doc """
  Labels spans of time, R's `label_timespan()`: each break, counted in `unit:`, turned into
  seconds and written as `number/2` writes it under `cut_time_scale/1`'s steps, `90` minutes
  being `90m` and `120` `2h`.

  ## Options

  #{NimbleOptions.docs(@timespan_options)}

  ## Examples

      iex> Scales.Labels.timespan([0, 30, 90, 3600, 86_400])
      ["0", "30s", "90s", "1h", "1d"]

      iex> Scales.Labels.timespan([0.5, 1.5, 36], unit: :hour)
      ["30m", "90m", "36h"]

      iex> Scales.Labels.timespan([1, 60, nil], space: true, suffix: " ago")
      ["1 s ago", "1 m ago", nil]
  """
  @spec timespan([number() | nil], keyword()) :: [String.t() | nil]
  def timespan(breaks, options \\ []) do
    settings =
      options
      |> NimbleOptions.validate!(@timespan_options)
      |> Map.new()

    seconds = Map.fetch!(@unit_seconds, settings.unit)
    steps = cut_time_scale(space: settings.space)

    breaks
    |> numbers!("Labels.timespan/2")
    |> Enum.map(fn value -> value && Arithmetic.product(value, seconds) end)
    |> label(Map.put(settings, :scale_cut, steps))
  end

  @doc """
  Labels dates and date-times in a format, R's `label_date()`, by `Calendar.strftime/3`, but for
  `%Y`, the year unpadded (the year 900 is `900`).

  A `DateTime` is shifted into `tz:` first, UTC unless given; a `NaiveDateTime` is written as it
  is, its zone UTC, and a `Date` at midnight UTC, so `%H` writes `00` and `%Z` `UTC`.

  ## Options

  #{NimbleOptions.docs(@date_schemas.date)}

  ## Examples

      iex> Scales.Labels.date([~D[2020-01-01], nil, ~D[2021-06-15]])
      ["2020-01-01", nil, "2021-06-15"]

      iex> Scales.Labels.date([~N[2020-03-05 14:07:09]], format: "%d %b %H:%M")
      ["05 Mar 14:07"]

      iex> Scales.Labels.date([~U[2021-03-14 06:30:00Z], ~U[2021-03-14 07:30:00Z]],
      ...>   format: "%H:%M %Z",
      ...>   tz: "America/New_York",
      ...>   time_zone_database: Tz.TimeZoneDatabase
      ...> )
      ["01:30 EST", "03:30 EDT"]
  """
  @spec date([Date.t() | NaiveDateTime.t() | DateTime.t() | nil], keyword()) ::
          [String.t() | nil]
  def date(breaks, options \\ []) do
    {format, clock} = date_settings!(options, :date, "Labels.date/2")

    breaks
    |> dates!("Labels.date/2", [Date, NaiveDateTime, DateTime], "dates, date-times")
    |> DateFormat.write(format, clock)
  end

  @doc """
  Labels dates and date-times with what changed from the break before, R's
  `label_date_short()`: each part, a year, a month, a day and a time of day, written where it or
  a coarser part changed, finest first, one part to a line.

  The first break, and one after a missing break, show every part. The time is left out where
  every break is at midnight, then the day where every break is a 1st, then the month where every
  break is in January. A break with no part to write, as a date repeated, is written in full,
  `2020-01-05`, or `2020-01-05 10:00:00` where one such break is not at midnight in `tz:`.

  What changed is read on each break's own clock, a `DateTime` in its own zone; each part is
  written as `date/2` writes it, a `DateTime` shifted into `tz:`.

  ## Options

  #{NimbleOptions.docs(@date_short_options)}

  ## Examples

      iex> Scales.Labels.date_short([~D[2019-11-01], ~D[2019-12-01], ~D[2020-01-01], ~D[2020-02-01]])
      ["Nov\\n2019", "Dec", "Jan\\n2020", "Feb"]

      iex> Scales.Labels.date_short([~N[2020-01-01 18:00:00], ~N[2020-01-01 21:00:00], ~N[2020-01-02 00:00:00]])
      ["18:00\\n01\\nJan\\n2020", "21:00", "00:00\\n02"]

      iex> Scales.Labels.date_short([~D[2020-01-05], ~D[2020-01-06], ~D[2020-02-07]],
      ...>   format: [month: "%B"],
      ...>   sep: " ",
      ...>   leading: ""
      ...> )
      ["5 January 2020", "6", "7 February"]
  """
  @spec date_short([Date.t() | NaiveDateTime.t() | DateTime.t() | nil], keyword()) ::
          [String.t() | nil]
  def date_short(breaks, options \\ []) do
    settings =
      options
      |> NimbleOptions.validate!(@date_short_options)
      |> Map.new()

    clock = {settings.tz, settings.time_zone_database}
    DateFormat.check_zone!("Labels.date_short/2", settings.tz, settings.time_zone_database)

    breaks
    |> dates!("Labels.date_short/2", [Date, NaiveDateTime, DateTime], "dates, date-times")
    |> DateFormat.short(settings.format, settings.sep, settings.leading, clock)
  end

  @doc """
  Labels times of day and date-times in a format, R's `label_time()`, by `Calendar.strftime/3`.

  A `DateTime` is shifted into `tz:` first, UTC unless given; a `NaiveDateTime` is written as it
  is, its zone UTC, and a `Time` as it is. A format writing a part of a date (`%Y`, `%d`) raises
  on a `Time`.

  ## Options

  #{NimbleOptions.docs(@date_schemas.time)}

  ## Examples

      iex> Scales.Labels.time([~T[00:00:00], ~T[01:01:01], ~T[23:59:59], nil])
      ["00:00:00", "01:01:01", "23:59:59", nil]

      iex> Scales.Labels.time([~T[00:00:59], ~T[00:59:59.9]], format: "%H:%M")
      ["00:00", "00:59"]

      iex> Scales.Labels.time([~U[2020-01-01 03:00:00Z]],
      ...>   tz: "America/New_York",
      ...>   time_zone_database: Tz.TimeZoneDatabase
      ...> )
      ["22:00:00"]
  """
  @spec time([NaiveDateTime.t() | DateTime.t() | Time.t() | nil], keyword()) ::
          [String.t() | nil]
  def time(breaks, options \\ []) do
    {format, clock} = date_settings!(options, :time, "Labels.time/2")

    breaks
    |> dates!("Labels.time/2", [NaiveDateTime, DateTime, Time], "date-times, times of day")
    |> DateFormat.write(format, clock)
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

  # NimbleOptions' check of `base:`: a positive number other than 1.
  @doc false
  @spec validate_base(term()) :: {:ok, number()} | {:error, String.t()}
  def validate_base(base) when is_number(base) and base > 0 and base != 1, do: {:ok, base}

  def validate_base(base),
    do: {:error, "expected a positive number other than 1, got: #{inspect(base)}"}

  # NimbleOptions' check of `units:`: an automatic unit, or a fixed one as R spells it.
  @doc false
  @spec validate_units(term()) :: {:ok, atom() | String.t()} | {:error, String.t()}
  def validate_units(units) when units in [:auto_si, :auto_binary], do: {:ok, units}
  def validate_units(units) when is_map_key(@byte_units, units), do: {:ok, units}

  def validate_units(units) do
    {:error,
     "expected :auto_si, :auto_binary or one of #{Enum.map_join(@byte_unit_names, ", ", &inspect/1)}, " <>
       "got: #{inspect(units)}"}
  end

  # NimbleOptions' check of `rules:`: a list of at least one `{suffix, regex}` pair.
  @doc false
  @spec validate_rules(term()) :: {:ok, [{String.t(), Regex.t()}]} | {:error, String.t()}
  def validate_rules(rules) do
    if is_list(rules) and rules != [] and Enum.all?(rules, &rule?/1),
      do: {:ok, rules},
      else:
        {:error,
         "expected a list of at least one {suffix, regex} pair, each suffix a string, got: " <>
           inspect(rules)}
  end

  # NimbleOptions' check of `pvalue/2`'s `accuracy:`: a positive number no larger than 0.5, so
  # no p-value is both below it and above 1 less it.
  @doc false
  @spec validate_pvalue_accuracy(term()) :: {:ok, number()} | {:error, String.t()}
  def validate_pvalue_accuracy(accuracy)
      when is_number(accuracy) and accuracy > 0 and accuracy <= 0.5,
      do: {:ok, accuracy}

  def validate_pvalue_accuracy(accuracy),
    do: {:error, "expected a positive number no larger than 0.5, got: #{inspect(accuracy)}"}

  # NimbleOptions' check of `pvalue/2`'s `prefix:`: three strings.
  @doc false
  @spec validate_pvalue_prefix(term()) :: {:ok, tuple()} | {:error, String.t()}
  def validate_pvalue_prefix({below, between, above} = prefix)
      when is_binary(below) and is_binary(between) and is_binary(above),
      do: {:ok, prefix}

  def validate_pvalue_prefix(prefix),
    do: {:error, "expected three strings, {below, between, above}, got: #{inspect(prefix)}"}

  # NimbleOptions' check of a date labeller's format: a string of at least one character that
  # `Calendar.strftime/3` writes a date-time in, tried on one, so a format it cannot write raises
  # at the call.
  @doc false
  @spec validate_date_format(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_date_format(format) when is_binary(format) and format != "" do
    DateBreaks.label(~U[1970-01-01 00:00:00Z], format)
    {:ok, format}
  rescue
    exception ->
      {:error,
       "expected a format Calendar.strftime/3 can write a date-time in, got: " <>
         "#{inspect(format)}, which it cannot: #{Exception.message(exception)}"}
  end

  def validate_date_format(format),
    do: {:error, "expected a format, a string of at least one character, got: #{inspect(format)}"}

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

  # The breaks, each of one of the structs `kinds` or a missing one, `nil`.
  defp dates!(breaks, function, kinds, named) when is_list(breaks) do
    if Enum.all?(breaks, fn value ->
         is_nil(value) or (is_struct(value) and value.__struct__ in kinds)
       end) do
      breaks
    else
      raise ArgumentError,
            "#{function} takes a list of #{named} and nils, got: #{inspect(breaks)}"
    end
  end

  defp dates!(breaks, function, _kinds, named) do
    raise ArgumentError, "#{function} takes a list of #{named} and nils, got: #{inspect(breaks)}"
  end

  # `date/2`'s or `time/2`'s format and the clock it writes on, its zone checked.
  defp date_settings!(options, function, name) do
    settings = NimbleOptions.validate!(options, Map.fetch!(@date_schemas, function))
    zone = Keyword.fetch!(settings, :tz)
    database = Keyword.fetch!(settings, :time_zone_database)
    DateFormat.check_zone!(name, zone, database)
    {Keyword.fetch!(settings, :format), {zone, database}}
  end

  # The options given, checked, with the formatter's defaults; `accuracy:` and `scale_cut:` have
  # none, so each is absent from the settings when not given.
  defp settings!(options, formatter) do
    options
    |> NimbleOptions.validate!(Map.fetch!(@formatter_schemas, formatter))
    |> Map.new()
  end

  defp rule?({suffix, rule}), do: is_binary(suffix) and is_struct(rule, Regex)
  defp rule?(_rule), do: false

  # `bytes/2`'s settings for its units: an automatic unit's steps, or a fixed unit's suffix and
  # the scale divided by its size, as R divides it.
  defp in_units(%{units: units} = settings) when is_map_key(@byte_steps, units),
    do: Map.merge(settings, %{suffix: "", scale_cut: Map.fetch!(@byte_steps, units)})

  defp in_units(%{units: units} = settings) do
    {base, power} = Map.fetch!(@byte_units, units)
    Map.merge(settings, %{suffix: " " <> units, scale: settings.scale / base ** power})
  end

  # An accuracy of `nil` is one worked out from the breaks, as one not given is.
  defp without_given_accuracy(%{accuracy: nil} = settings), do: Map.delete(settings, :accuracy)
  defp without_given_accuracy(settings), do: settings

  # The suffix of the first rule matching a whole number's digits.
  defp ordinal_suffix(value, rules) do
    digits = whole_digits(value)

    case Enum.find(rules, fn {_suffix, rule} -> Regex.match?(rule, digits) end) do
      {suffix, _rule} ->
        suffix

      nil ->
        raise ArgumentError,
              "Labels.ordinal/2 found no rule matching #{inspect(digits)}, a break rounded; " <>
                "the rules need one every break matches, as ordinal_english/0's last, " <>
                "{\"th\", ~r/./}, is, got: #{inspect(rules)}"
    end
  end

  # A whole number's digits, unmarked, a negative's with a `-` before them.
  defp whole_digits(value) do
    [digits] = Format.write([abs(value)], format_settings(@format_digits, :fixed, "."))
    if value < 0, do: "-" <> digits, else: digits
  end

  # `pvalue/2`'s three prefixes.
  defp pvalue_prefix(%{prefix: prefix, add_p: true}) do
    raise ArgumentError,
          "Labels.pvalue/2 takes add_p: true or prefix:, not both, since add_p: writes the " <>
            "prefixes {\"p<\", \"p=\", \"p>\"}, got: prefix: #{inspect(prefix)}"
  end

  defp pvalue_prefix(%{prefix: prefix}), do: prefix
  defp pvalue_prefix(%{add_p: true}), do: {"p<", "p=", "p>"}
  defp pvalue_prefix(_settings), do: {"<", "", ">"}

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
    amounts = for value <- values, value != nil, do: Arithmetic.product(value, settings.scale)

    small =
      Enum.all?(amounts, fn amount ->
        is_float(amount) and abs(amount) <= settings.largest_with_fractional
      end)

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
      {%{infinite: true} = number, _text} -> signed("Inf", number.sign, settings)
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
        name = step_name(value, scale, sorted)
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

  # The suffix of the step a value takes: none for an infinite value, or past the largest double
  # once scaled, where R's `cut()` finds no step for an infinity.
  defp step_name(value, _scale, _steps) when is_atom(value), do: ""

  defp step_name(value, scale, steps) do
    case Arithmetic.product(value, scale) do
      scaled when is_float(scaled) ->
        refined_step(value, scale, step_reached(abs(scaled), steps), steps)

      _infinite ->
        ""
    end
  end

  # The suffix of the last step whose threshold the value's magnitude reaches.
  defp step_reached(magnitude, steps) do
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
        accuracy =
          values
          |> finite_scaled(scale)
          |> precision()

        {scale, accuracy}
      end)

    Enum.map(numbers, fn number -> Map.put(number, :accuracy, accuracies[number.scale]) end)
  end

  # The values scaled, as R's `precision()` takes them: the missing and infinite ones and those
  # past the largest double left out.
  defp finite_scaled(values, scale) do
    values
    |> Enum.filter(&is_float/1)
    |> Enum.map(fn value -> Arithmetic.product(value, scale) end)
    |> Enum.filter(&is_float/1)
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
          |> Enum.map(fn [low, high] -> Arithmetic.difference(high, low) end)
          |> Enum.min()

        # A gap past the largest double is R's infinity, an atom, which sorts after every number,
        # so it is the smallest only when every gap is; R's `precision()` takes that through an
        # infinite power of ten to 1.
        cond do
          smallest == :infinity -> 1.0
          smallest < @smallest_gap -> 1.0
          true -> power_precision(sorted, smallest)
        end
    end
  end

  defp power_precision(values, smallest) do
    power =
      smallest
      |> :math.log10()
      |> Float.floor()

    precision = 10.0 ** (power - 1)

    # R's `round(x / precision) %% 10 == 0`, where a quotient past the largest double is `NA`:
    # beside a break that is no multiple R's `all()` is false, and beside multiples alone R
    # fails, so such a quotient is left out (design-log §4, the entry beginning "A break whose
    # quotient").
    tenfold =
      values
      |> Enum.map(fn value -> Arithmetic.quotient(value, precision) end)
      |> Enum.filter(&is_float/1)
      |> Enum.all?(fn quotient -> rem(trunc(Arithmetic.nearest(quotient)), 10) == 0 end)

    if tenfold, do: min(precision * 10, 1.0), else: min(precision, 1.0)
  end

  # The value rounded to its accuracy, its sign after rounding, the number written (scaled and
  # without its sign), whether rounding took it past the largest double, and the decimals its
  # accuracy asks for; a missing one has no sign and is written missing.
  defp rounded(number) do
    {sign, magnitude, infinite} = rounded_value(number)

    power =
      number.accuracy
      |> :math.log10()
      |> Float.floor()
      |> trunc()

    decimals =
      -power
      |> max(0)
      |> min(@max_decimals)

    Map.merge(number, %{
      sign: sign,
      magnitude: magnitude,
      infinite: infinite,
      decimals: decimals
    })
  end

  defp rounded_value(%{value: nil}), do: {0, nil, false}

  # A value already infinite, as `timespan/2`'s unit can take a break, rounds to itself.
  defp rounded_value(%{value: infinite}) when is_atom(infinite),
    do: {sign_of(infinite), :infinity, true}

  # Either step can pass the largest double, as R's `round_any()` and `scale * x` can: rounded
  # past it, the number is infinite; only scaled past it, it is written `Inf`.
  defp rounded_value(number) do
    step = number.accuracy / number.scale

    case Arithmetic.quotient(number.value, step) do
      quotient when is_float(quotient) ->
        rounded =
          quotient
          |> Arithmetic.nearest()
          |> Arithmetic.product(step)

        case rounded do
          value when is_float(value) ->
            {sign_of(value), Arithmetic.product(number.scale, abs(value)), false}

          infinite ->
            {sign_of(infinite), :infinity, true}
        end

      infinite ->
        {sign_of(infinite), :infinity, true}
    end
  end

  defp sign_of(:infinity), do: 1
  defp sign_of(:neg_infinity), do: -1
  defp sign_of(value) when is_float(value) and value > 0, do: 1
  defp sign_of(value) when is_float(value) and value < 0, do: -1
  defp sign_of(_zero), do: 0

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

  # How `Format` writes numbers together with R's `format()` defaults: untrimmed under
  # `log/2`, trimmed otherwise.
  defp format_settings(digits, notation, decimal_mark, trim \\ true) do
    %{
      digits: digits,
      nsmall: 0,
      notation: notation,
      big_mark: "",
      decimal_mark: decimal_mark,
      trim: trim
    }
  end

  # `number_auto/1`'s way of writing the breaks, from the magnitudes of those other than zero;
  # R's test that all are positive reads the numbers alone.
  defp automatic_way(values) do
    magnitudes = for value <- values, value != nil and value != 0, do: abs(value)
    automatic_way(values, magnitudes)
  end

  defp automatic_way(_values, []), do: :together

  defp automatic_way(values, magnitudes) do
    {smallest, largest} = Enum.min_max(magnitudes)

    cond do
      largest > 1.0e6 -> :large
      smallest < 1.0e-3 -> :small
      years?(values, smallest, largest) -> :together
      largest > 1000 -> :whole
      true -> :together
    end
  end

  defp years?(values, smallest, largest) do
    smallest >= 1000 and largest <= 2200 and
      Enum.all?(values, fn value -> value == nil or value > 0 end)
  end

  # The breaks written together in one notation, trimmed, a missing one with no label.
  defp written_alone(values, notation) do
    values
    |> Format.write(format_settings(@format_digits, notation, "."))
    |> Enum.zip_with(values, fn text, value -> value && text end)
  end

  # Each label the shorter of the two, the first on a tie.
  defp shortest(firsts, seconds) do
    Enum.zip_with(firsts, seconds, fn first, second ->
      if first && String.length(second) < String.length(first), do: second, else: first
    end)
  end

  # `log/2`'s and `format_log/2`'s base as text, and each break's sign and exponent as text,
  # written together: `nil` for a missing break and `:zero` for a signed zero.
  defp powers(breaks, options, function) do
    settings =
      options
      |> NimbleOptions.validate!(Map.fetch!(@log_schemas, function))
      |> Map.new()

    name = "Labels.#{function}/2"
    values = numbers!(breaks, name)
    signed = signed?(values, settings.signed)
    if not signed, do: Enum.each(values, fn value -> unsigned!(value, name) end)

    exponents =
      Enum.map(values, fn value ->
        value && Arithmetic.logarithm(logged(value, signed), settings.base)
      end)

    texts =
      exponents
      |> zapped()
      |> Format.write(format_settings(settings.digits, :auto, ".", false))

    parts =
      Enum.zip_with(values, texts, fn
        nil, _text -> nil
        value, _text when signed and value == 0 -> :zero
        value, text -> {sign(value, signed), text}
      end)

    {alone(settings.base * 1.0), parts}
  end

  defp signed?(values, :auto), do: Enum.any?(values, fn value -> value != nil and value <= 0 end)
  defp signed?(_values, signed), do: signed

  defp unsigned!(value, name) when is_float(value) and value <= 0 do
    raise ArgumentError,
          "#{name} labels a break at or below zero only when signed, with signed: true or " <>
            ":auto, got: #{inspect(value)} with signed: false"
  end

  defp unsigned!(_value, _name), do: :ok

  # The number whose logarithm is the exponent: signed, the magnitude, a zero's 1.
  defp logged(value, true) when value == 0, do: 1.0
  defp logged(value, true), do: abs(value)
  defp logged(value, false), do: value

  # Signed, a zero is labelled `"0"` before its sign is asked for.
  defp sign(value, true) when value > 0, do: "+"
  defp sign(_negative, true), do: "-"
  defp sign(_value, false), do: ""

  # R's `zapsmall()`: each exponent rounded to the decimals that leave the largest seven
  # significant digits; every one 0, or missing, is left as it is, as rounding leaves it.
  defp zapped(exponents) do
    largest =
      exponents
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&abs/1)
      |> Enum.max(fn -> 0 end)

    if largest == 0 do
      exponents
    else
      decimals = max(0, @format_digits - :math.log10(largest))
      Enum.map(exponents, fn exponent -> exponent && Arithmetic.round_to(exponent, decimals) end)
    end
  end

  # An exponent's text as R reads it back and writes it alone.
  defp read_back(text) do
    {value, ""} =
      text
      |> String.trim_leading()
      |> Float.parse()

    alone(value)
  end

  # A number written alone, as R's `as.character()` and `deparse()` write it.
  defp alone(value) do
    [text] = Format.write([value], format_settings(@alone_digits, :auto, "."))
    text
  end

  defp whole?(value), do: value == Float.floor(value)
end
