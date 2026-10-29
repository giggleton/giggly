defmodule Scales.ColorOperations do
  @moduledoc """
  Colours as a user writes them and as R's palettes make them: a colour read as CSS reads one
  (`parse/1`); one made from a hue, chroma and luminance (`from_hcl/3`) or from CIE L*a*b*
  (`from_lab/2`), and a colour's L*a*b* (`to_lab/1`) and alpha (`opacity/1`), each exactly as R's
  farver makes it; two mixed (`mix/3`), R's `col_mix()`; one changed, R's colour helpers: its
  alpha set (`alpha/2`), its hue, chroma or luminance set (`with_hcl/2`, `muted/2`), made
  lighter, darker or more saturated (`lighter/2`, `darker/2`, `saturate/2`) or its hue turned
  (`shift/2`); and the viridis palettes' colours (`viridis/2`), R's `viridisLite::viridis()`.

  A colour is uppercase `#RRGGBB`, or `#RRGGBBAA` with an alpha of its own, an alpha of `FF`
  dropped as opaque, so a colour has one spelling; or `:none`, R's `NA`, no colour. A helper
  takes one colour, as `mix/3` takes two, and gives no colour back for none, as R gives `NA`.
  """

  # Colour operations: reading a colour as a user writes one, and the conversions R's palettes make
  # between colour spaces. It is the one module that calls the `color` library, so the library and
  # R's colour constants each have one home.
  #
  # A colour is a string in one spelling, uppercase `#RRGGBB`, or `#RRGGBBAA` when it carries an
  # alpha of its own, the form R, CSS and the scene all use, or `:none`, R's `NA`, which draws
  # nothing. An alpha of FF is opaque, and is dropped, so a colour has one spelling.
  #
  # `parse/1` reads a colour as CSS reads one: a CSS colour name, in any case, as CSS matches its
  # keywords, from the library's table of them (`Color.CSS.Names`) less the two names it adds that
  # CSS does not define; a hex colour in one of CSS's four forms, `#RGB`, `#RGBA`, `#RRGGBB` and
  # `#RRGGBBAA`, its digits in either case; `transparent`, R's white with no alpha, where CSS's is
  # black; or `:none`. A name CSS does not define, such as R's `grey50`, is refused, and so is
  # anything else, CSS's functions (`rgb()`) and the spellings the library forgives (a hex colour
  # without its `#`, a name with spaces) among them.
  #
  # `from_hcl/3` is the colour farver encodes from a hue, chroma and luminance, as `pal_hue()` asks
  # it with `encode_colour(from = "hcl")`: CIE LCh(uv) to Luv, to XYZ against farver's white point,
  # to sRGB through farver's matrix, each channel companded, times 255, rounded half to even and
  # clamped to a byte, as farver writes one. `to_lab/1` is a colour's CIE L*a*b* as farver decodes
  # it (`decode_colour(to = "lab")`), each byte over 255 expanded from sRGB's companding, to XYZ
  # through farver's matrix the other way, to Lab against its white point; and `from_lab/2` the
  # colour farver encodes from L*a*b*, to XYZ and then as `from_hcl/3` goes on, as R's gradients
  # (`scales::colour_ramp()`) blend their colours in Lab, an alpha's byte appended as `mix/3`
  # writes it. The conversions are the library's
  # (`Color.Conversion.Lindbloom`), handed farver's constants: its white point, made from D65's
  # chromaticity in its own arithmetic rather than the textbook 95.047 and 108.883, and its sRGB
  # matrices. With them it gives R's colours exactly but where L* is below 8, where farver's
  # conversion from Lab keeps the rounded 0.008856 and 7.787 and the library the exact fractions
  # (one colour in 35,007 of seven R gradients' samples).
  #
  # `mix/3` is scales' `col_mix()` in its default space, as ggplot2's geoms mix their default
  # colours from the theme's ink and paper: each colour's red, green and blue as farver decodes
  # them, bytes, and its alpha, its byte over 255, each a share of the way from the one to the
  # other, `from * (1 - amount) + to * amount`; then each channel, and the alpha times 255, rounded
  # to a byte as farver writes one, a half to the even byte, the alpha dropped when it is opaque.
  #
  # The helpers are R's `alpha()`, `col2hcl()` (`with_hcl/2`), `muted()`, `col_lighter()`,
  # `col_darker()`, `col_saturate()` and `col_shift()`, one colour a call; each matched R on every
  # colour of a grid of 10,336 colours, a cube, the greys and random colours with and without an
  # alpha, and of tens of thousands of random arguments, but where said below. A colour's hue,
  # chroma and luminance are farver's decoding, its XYZ to Luv in polar form, black's hue 180
  # degrees as farver's arithmetic gives it; set, or turned modulo 360 as R's `%%` turns it, and
  # encoded by `from_hcl/3`, which takes each into farver's bounds first as farver caps them. R's
  # `col2hcl()`, so `muted()`, encodes no alpha unless one is given, and `with_hcl/2` drops the
  # colour's own as R does; `col_shift()` and the HSL helpers keep it. An alpha is written as
  # `mix/3` writes it, its byte clamped, so an alpha outside 0 to 1 is the nearer end, as R's is.
  # farver checks whether an alpha is opaque after scaling it by 255, so R writes one colour whose
  # alpha's byte is 1 opaque and several `01`; the byte is written here, R's answer for several.
  #
  # `lighter/2`, `darker/2` and `saturate/2` add to the colour's HSL lightness or saturation, on
  # farver's scale of 0 to 100, taken into 0 to 100, as farver's `add_to_channel()` does. The HSL
  # is the library's (`Color.HSL`), taken onto farver's scales, degrees and percents, and back.
  # farver works the hue out as `60 * h' mod 360` and the saturation as `C / (1 - |2L - 1|)`, the
  # library as fractions of a turn and `C / (2 - max - min)`, which agree to the last bit or so; a
  # channel landing exactly between two bytes is then rounded the other way, one to three channels
  # a byte from R's in 65 to 116 of 10,395 calls at the default amount of 10, whose steps of
  # 25.5 bytes make such ties common, and in about one of a thousand at random amounts (Steve,
  # 2026-10-28, the library over the textbook formula written out here).
  #
  # `viridis/2` is R's `viridisLite::viridis(n, alpha, begin, end, direction, option)`: `count`
  # places spaced from `begin` to `end` by R's `seq()`, the two swapped for a `direction` of -1;
  # the palette's colour at each place, its L*, a* and b* each a cubic spline evaluated there; that
  # colour converted back to sRGB as grDevices' `convertColor()` converts it; and the alpha
  # appended. The splines are R's own, the "fmm" splines `grDevices::colorRamp(space = "Lab",
  # interpolate = "spline")` fits through a palette's 256 colours, their coefficients copied into
  # `priv/palettes/viridis_splines.csv`, whose header says how R wrote them, and read when Giggly
  # compiles; a place's value is `y + dx * (b + dx * (c + dx * d))` at the knot at or before it,
  # found by bisection as R's `spline_eval()` finds it. R keeps the last place's knot while it
  # still holds the next place, which changes no colour. The conversion is the library's again,
  # handed grDevices' constants this time: its white point made from its own D65, (0.3137, 0.3291),
  # by its `c2to3()`, and the sRGB matrix it inverts from that, which are not farver's; then each
  # channel companded, rounded to five decimals as R's `round()` rounds, clipped to 0 to 1, and
  # written as `rgb()` writes it, the byte `255 * channel + 0.5` truncated. R multiplies each
  # channel by 255 and divides it again on the way, which changes no byte of any value the
  # rounding gives, and is left out. The alpha is `rgb()`'s byte too, dropped when it is opaque.
  # It matched R on every colour of every palette for every count to 256, and on thousands of
  # beginnings, ends, directions and alphas. R multiplies by the matrix through its BLAS, whose
  # last bit depends on the library and the processor, so where a channel lands exactly on a
  # rounding tie R's own answer varies: of 1,003 such places a search found, R with OpenBLAS gives
  # Giggly's colour at 885 and R's internal product at 875. Giggly adds the three products left to
  # right, as the sum written out in R does.

  # The library's one caller: the `Scales` boundary lists `Color` for it, and nothing else in the
  # package or in Giggly calls it.
  alias Color.Conversion.Lindbloom
  alias Color.CSS.Names

  @typedoc "A colour: uppercase `#RRGGBB`, or `#RRGGBBAA` with an alpha of its own, or `:none`."
  @type t :: String.t() | :none

  # farver's white point, from D65's chromaticity as its `as_white_ref()` makes one:
  # `c(100 / y * x, 100, 100 / y * (1 - (x + y)))`.
  @d65_x 0.31271
  @d65_y 0.32902
  @white_point {100 / @d65_y * @d65_x, 100.0, 100 / @d65_y * (1 - (@d65_x + @d65_y))}

  # 1.5 times 2^52, farver's rounding constant.
  @rounding 6_755_399_441_055_744.0

  # farver's matrices from XYZ to linear sRGB, and back.
  @to_srgb [
    [3.2404542, -1.5371385, -0.4985314],
    [-0.9692660, 1.8760108, 0.0415560],
    [0.0556434, -0.2040259, 1.0572252]
  ]

  @from_srgb [
    [0.4124564, 0.3575761, 0.1804375],
    [0.2126729, 0.7151522, 0.0721750],
    [0.0193339, 0.1191920, 0.9503041]
  ]

  # grDevices' white point, its D65 made into XYZ by `c2to3()`: `c(x / y, 1, (1 - sum(c(x, y))) /
  # y)`.
  @grdevices_d65_x 0.3137
  @grdevices_d65_y 0.3291
  @grdevices_white_point {@grdevices_d65_x / @grdevices_d65_y, 1.0,
                          (1 - (@grdevices_d65_x + @grdevices_d65_y)) / @grdevices_d65_y}

  # grDevices' matrix from XYZ to linear sRGB, `solve(M)` of its sRGB converter's `M`, each row a
  # channel's.
  @grdevices_to_srgb [
    [3.2065205171444631, -1.5210417837736552, -0.49331084879145581],
    [-0.97198254620123181, 1.8812686516084869, 0.041672484599589325],
    [0.055838338593097898, -0.20474057484135891, 1.0609284332688589]
  ]

  # viridisLite's palettes, in the order of its options A to H, which the splines' file holds.
  @viridis_options [:magma, :inferno, :plasma, :viridis, :cividis, :rocket, :mako, :turbo]

  @viridis_splines_path Application.app_dir(:giggly, "priv/palettes/viridis_splines.csv")
  @external_resource @viridis_splines_path

  # why: the splines are read once, at compile time; no IO happens when a colour is made
  # instead of: the coefficients as literals in this module — rejected because they are R's
  #   numbers, kept as the file R writes so they can be regenerated and diffed against their
  #   source apart from the code
  # credo:disable-for-next-line Tack.Credo.Check.CorePurity
  @viridis_splines_text File.read!(@viridis_splines_path)

  # Each palette's knots, a tuple, and its three channels' splines, L*, a* and b*, each a tuple of
  # the values and the coefficients b, c and d, each a tuple in knot order, by the palette's name;
  # the file's comment lines skipped, and its header the columns in the order they are read.
  @viridis_splines @viridis_splines_text
                   |> String.split("\n", trim: true)
                   |> Enum.reject(fn line -> String.starts_with?(line, "#") end)
                   |> then(fn ["palette,x,L.y,L.b,L.c,L.d,a.y,a.b,a.c,a.d,b.y,b.b,b.c,b.d" | rows] ->
                     rows
                   end)
                   |> Enum.map(fn line ->
                     [palette | numbers] = String.split(line, ",")

                     values =
                       Enum.map(numbers, fn number ->
                         {value, ""} = Float.parse(number)
                         value
                       end)

                     {String.to_existing_atom(palette), values}
                   end)
                   |> Enum.chunk_by(fn {palette, _values} -> palette end)
                   |> Map.new(fn [{palette, _values} | _rows] = rows ->
                     [knots | coefficients] =
                       rows
                       |> Enum.map(fn {_palette, values} -> values end)
                       |> Enum.zip_with(&List.to_tuple/1)

                     channels =
                       coefficients
                       |> Enum.chunk_every(4)
                       |> Enum.map(&List.to_tuple/1)

                     {palette, {knots, channels}}
                   end)

  # The names the library's table holds that CSS does not define: chroma-key colours.
  @not_css ["chromablue", "chromagreen"]

  # A hex colour's digits. Checked here, since the library reads each pair with `Integer.parse/2`,
  # which takes a sign, so `#+f+f+f` would pass it.
  @hex_digits ~r/\A[0-9a-fA-F]+\z/

  # A CSS colour name: ASCII letters alone.
  @name_letters ~r/\A[a-z]+\z/

  # The amount R's `col_lighter()`, `col_darker()`, `col_saturate()` and `col_shift()` take by
  # default.
  @default_amount 10

  # The options of `with_hcl/2`, R's `col2hcl()`'s `h`, `c`, `l` and `alpha`, and `muted/2`'s,
  # R's `muted()`'s `l` and `c` and their defaults. They are checked by NimbleOptions, which the
  # `Scales` boundary lists.
  @hcl_options [
    hue: [
      type: {:or, [:integer, :float]},
      doc: "The hue in degrees; one outside 0 to 360 is the nearer end."
    ],
    chroma: [type: {:or, [:integer, :float]}, doc: "The chroma, from 0, grey; one below 0 is 0."],
    luminance: [
      type: {:or, [:integer, :float]},
      doc: "The luminance, from 0, black, to 100, white; one outside them is the nearer."
    ]
  ]

  @with_hcl_schema @hcl_options
                   |> Enum.concat(
                     alpha: [
                       type: {:or, [:integer, :float, nil]},
                       doc:
                         "An alpha from 0 to 1, as `alpha/2` takes it; `nil`, or none given, " <>
                           "writes the colour opaque."
                     ]
                   )
                   |> NimbleOptions.new!()

  @muted_schema NimbleOptions.new!(
                  luminance: Keyword.put(@hcl_options[:luminance], :default, 30),
                  chroma: Keyword.put(@hcl_options[:chroma], :default, 70)
                )

  @doc """
  The colour `color` names, in its one spelling, or `:error` where CSS names none: a CSS colour
  name in any case; a hex colour in one of CSS's four forms, `#RGB`, `#RGBA`, `#RRGGBB` and
  `#RRGGBBAA`, its digits in either case; `transparent`, R's white with no alpha, `#FFFFFF00`,
  where CSS's is black; or `:none`.
  R's own names that CSS lacks (`grey50`), CSS's functions (`rgb()`) and hex without its `#` are
  refused.

  ## Examples

      iex> Scales.ColorOperations.parse("SteelBlue")
      {:ok, "#4682B4"}

      iex> Scales.ColorOperations.parse("#abc")
      {:ok, "#AABBCC"}

      iex> Scales.ColorOperations.parse("grey50")
      :error
  """
  @spec parse(term()) :: {:ok, t()} | :error
  def parse(:none), do: {:ok, :none}

  def parse("#" <> digits = hex) when byte_size(digits) in [3, 4, 6, 8] do
    if String.match?(digits, @hex_digits), do: spelled(hex), else: :error
  end

  def parse(name) when is_binary(name) do
    name
    |> String.downcase()
    |> keyword()
  end

  def parse(_other), do: :error

  # R's `transparent` is white with no alpha, as a gradient blends from it.
  defp keyword("transparent"), do: {:ok, "#FFFFFF00"}
  defp keyword(name) when name in @not_css, do: :error

  defp keyword(name) do
    if String.match?(name, @name_letters) and Names.known?(name), do: spelled(name), else: :error
  end

  @doc """
  The colour, uppercase `#RRGGBB`, that R's farver encodes from `hue` in degrees, `chroma` and
  `luminance`, CIE LCh(uv), as R's `pal_hue()` makes its colours: each first taken into farver's
  bounds as farver caps it, a hue outside 0 to 360 and a luminance outside 0 to 100 at the nearer
  end, a chroma below 0 at 0.

  ## Examples

      iex> Scales.ColorOperations.from_hcl(15.0, 100.0, 65.0)
      "#F8766D"

      iex> Scales.ColorOperations.from_hcl(15.0, -40.0, 65.0)
      "#9E9E9E"
  """
  @spec from_hcl(number(), number(), number()) :: String.t()
  def from_hcl(hue, chroma, luminance)
      when is_number(hue) and is_number(chroma) and is_number(luminance) do
    {bounded(luminance, 100), max(chroma, 0), bounded(hue, 360)}
    |> Lindbloom.lchuv_to_luv()
    |> Lindbloom.luv_to_xyz(@white_point)
    |> from_xyz()
  end

  # `value` taken into 0 to `top`, at the nearer end outside it, as farver caps a channel.
  defp bounded(value, top) do
    value
    |> max(0)
    |> min(top)
  end

  @doc """
  The CIE L*a*b* of a `#RRGGBB` or `#RRGGBBAA` colour, as R's farver decodes it; an alpha is not
  part of it (`opacity/1`).

  ## Examples

      iex> Scales.ColorOperations.to_lab("#4682B4")
      {52.46551718768575, -4.073239774469551, -32.18862480122369}
  """
  @spec to_lab(String.t()) :: {float(), float(), float()}
  def to_lab(<<"#", digits::binary-size(6), _alpha::binary-size(2)>>), do: to_lab("#" <> digits)

  def to_lab(<<"#", _digits::binary-size(6)>> = color) do
    color
    |> to_xyz()
    |> Lindbloom.xyz_to_lab(@white_point)
  end

  # A colour's XYZ on farver's scale, Y of 100 for white, as farver decodes it: each byte over 255
  # expanded from sRGB's companding, through its matrix; an alpha is not part of it.
  defp to_xyz(<<"#", digits::binary-size(6), _alpha::binary>>) do
    {:ok, <<red, green, blue>>} = Base.decode16(digits)

    [red, green, blue]
    |> Enum.map(fn channel -> Lindbloom.srgb_inverse_compand(channel / 255) * 100 end)
    |> List.to_tuple()
    |> Lindbloom.rgb_to_xyz(@from_srgb)
  end

  @doc """
  The colour that R's farver encodes from CIE L*, a* and b* and an `alpha` from 0 to 1, as R's
  gradients blend their colours in L*a*b*: uppercase `#RRGGBB`, its alpha's byte appended unless
  it is opaque, `alpha` times 255 rounded half to even.

  ## Examples

      iex> Scales.ColorOperations.from_lab({52.4664, -4.0763, -32.1991})
      "#4682B4"

      iex> Scales.ColorOperations.from_lab({52.4664, -4.0763, -32.1991}, 0.5)
      "#4682B480"
  """
  @spec from_lab({number(), number(), number()}, number()) :: String.t()
  def from_lab({_lightness, _a, _b} = lab, alpha \\ 1) when is_number(alpha) do
    color =
      lab
      |> Lindbloom.lab_to_xyz(@white_point)
      |> from_xyz()

    color <> farver_alpha_digits(alpha)
  end

  @doc """
  A colour's own alpha, from 0 to 1, its byte over 255 as R's farver decodes it; 1 for a colour
  without one.

  ## Examples

      iex> Scales.ColorOperations.opacity("#4682B4")
      1.0

      iex> Scales.ColorOperations.opacity("#FFFFFF00")
      0.0
  """
  @spec opacity(String.t()) :: float()
  def opacity(<<"#", _digits::binary>> = color) do
    {_channels, alpha} = channels(color)
    alpha
  end

  @doc """
  The colour `amount` of the way from `from` to `to`, each in its one spelling, R's `col_mix()`:
  each of red, green, blue and alpha that share of the way from the one to the other, rounded to
  a byte; 0 is `from` and 1 is `to`.

  ## Examples

      iex> Scales.ColorOperations.mix("#000000", "#FFFFFF", 0.5)
      "#808080"
  """
  @spec mix(String.t(), String.t(), number()) :: String.t()
  def mix(<<"#", _from_digits::binary>> = from, <<"#", _to_digits::binary>> = to, amount)
      when is_number(amount) and amount >= 0 and amount <= 1 do
    {from_channels, from_alpha} = channels(from)
    {to_channels, to_alpha} = channels(to)

    digits =
      Enum.zip_with(from_channels, to_channels, fn from_channel, to_channel ->
        hex_pair(rounded_byte(from_channel * (1 - amount) + to_channel * amount))
      end)

    alpha = from_alpha * (1 - amount) + to_alpha * amount
    Enum.join(["#" | digits]) <> farver_alpha_digits(alpha)
  end

  @doc """
  The colour with its alpha set to `alpha`, from 0 to 1, R's `alpha()`: one below 0 is 0 and one
  above 1 is 1, as farver writes the byte; `nil`, R's `NA`, keeps the colour's own; no colour
  stays none. An alpha whose byte is 1 is written `01`, as R writes it for several colours, where
  R writes one colour opaque.

  ## Examples

      iex> Scales.ColorOperations.alpha("#4682B4", 0.5)
      "#4682B480"

      iex> Scales.ColorOperations.alpha("#4682B480", nil)
      "#4682B480"
  """
  @spec alpha(t(), number() | nil) :: t()
  def alpha(:none, alpha) when is_nil(alpha) or is_number(alpha), do: :none
  def alpha(<<"#", _digits::binary>> = color, nil), do: color

  def alpha(<<"#", digits::binary-size(6), _alpha::binary>>, alpha) when is_number(alpha),
    do: "#" <> digits <> farver_alpha_digits(alpha)

  @doc """
  The colour of the same hue at another chroma and luminance, R's `muted()`: `with_hcl/2` with
  the chroma and luminance given, its own alpha dropped, as R drops it; no colour stays none.

  ## Options

  #{NimbleOptions.docs(@muted_schema)}

  ## Examples

      iex> Scales.ColorOperations.muted("#FF0000")
      "#832424"

      iex> Scales.ColorOperations.muted("#4682B480", luminance: 60, chroma: 40)
      "#7094BA"
  """
  @spec muted(t(), keyword()) :: t()
  def muted(color, options \\ []) when is_list(options) do
    validated = NimbleOptions.validate!(options, @muted_schema)
    with_hcl(color, validated)
  end

  @doc """
  The colour with its hue, chroma or luminance set, R's `col2hcl()`: the colour's own, as farver
  decodes it, where an option is not given; each taken into farver's bounds as `from_hcl/3`
  says. The colour's own alpha is dropped, as R drops it, unless `alpha:` sets one, from 0 to 1,
  as `alpha/2` does; no colour stays none.

  Black's hue is 180 degrees, as farver decodes it.

  ## Options

  #{NimbleOptions.docs(@with_hcl_schema)}

  ## Examples

      iex> Scales.ColorOperations.with_hcl("#4682B4", hue: 320)
      "#B162A0"

      iex> Scales.ColorOperations.with_hcl("#4682B480", [])
      "#4682B4"

      iex> Scales.ColorOperations.with_hcl("#4682B4", luminance: 120)
      "#D4FFFF"
  """
  @spec with_hcl(t(), keyword()) :: t()
  def with_hcl(color, options) when is_list(options) do
    validated = NimbleOptions.validate!(options, @with_hcl_schema)
    hcl_set(color, validated)
  end

  defp hcl_set(:none, _options), do: :none

  defp hcl_set(<<"#", _digits::binary>> = color, options) do
    {hue, chroma, luminance} = to_hcl(color)

    set =
      from_hcl(
        Keyword.get(options, :hue, hue),
        Keyword.get(options, :chroma, chroma),
        Keyword.get(options, :luminance, luminance)
      )

    case Keyword.get(options, :alpha) do
      nil -> set
      alpha -> set <> farver_alpha_digits(alpha)
    end
  end

  @doc """
  The colour `amount` lighter, R's `col_lighter()`: its HSL lightness, from 0 to 100, raised by
  `amount` and taken into 0 to 100, its alpha kept; no colour stays none. The library's HSL,
  which R's farver works out in another order, lands a byte away from R's where a channel falls
  exactly between two, as the module's opening comment says.

  ## Examples

      iex> Scales.ColorOperations.lighter("#4682B4")
      "#699BC4"

      iex> Scales.ColorOperations.lighter("#4682B480", 200)
      "#FFFFFF80"
  """
  @spec lighter(t(), number()) :: t()
  def lighter(color, amount \\ @default_amount) when is_number(amount),
    do: added_to_hsl(color, :l, amount)

  @doc """
  The colour `amount` darker, R's `col_darker()`: `lighter/2` by minus `amount`.

  ## Examples

      iex> Scales.ColorOperations.darker("#4682B4")
      "#38678F"
  """
  @spec darker(t(), number()) :: t()
  def darker(color, amount \\ @default_amount) when is_number(amount),
    do: added_to_hsl(color, :l, -amount)

  @doc """
  The colour `amount` more saturated, R's `col_saturate()`: its HSL saturation, from 0 to 100,
  raised by `amount` and taken into 0 to 100, its alpha kept; no colour stays none. A byte may
  land away from R's as `lighter/2` says.

  ## Examples

      iex> Scales.ColorOperations.saturate("#4682B4")
      "#3983C1"

      iex> Scales.ColorOperations.saturate("#4682B4", -200)
      "#7D7D7D"
  """
  @spec saturate(t(), number()) :: t()
  def saturate(color, amount \\ @default_amount) when is_number(amount),
    do: added_to_hsl(color, :s, amount)

  # The colour with `amount` added to an HSL channel: the library's HSL taken onto farver's scales,
  # the hue in degrees and the saturation and lightness 0 to 100, `amount` added to the one, and
  # back, which lands on R's byte at more ties than the library's fractions alone; each channel a
  # byte as farver writes one, the colour's own alpha kept.
  defp added_to_hsl(:none, _channel, _amount), do: :none

  defp added_to_hsl(<<"#", _digits::binary>> = color, channel, amount) do
    {[red, green, blue], _alpha} = channels(color)
    {:ok, hsl} = Color.HSL.from_srgb(%Color.SRGB{r: red / 255, g: green / 255, b: blue / 255})
    farver = %{h: hsl.h * 360, s: hsl.s * 100, l: hsl.l * 100}
    added = Map.update!(farver, channel, fn value -> bounded(value + amount, 100) end)
    back = %Color.HSL{h: added.h / 360, s: added.s / 100, l: added.l / 100}
    {:ok, srgb} = Color.HSL.to_srgb(back)

    [srgb.r, srgb.g, srgb.b]
    |> Enum.map_join(fn intensity -> hex_pair(rounded_byte(intensity * 255)) end)
    |> then(fn digits -> "#" <> digits <> own_alpha_digits(color) end)
  end

  @doc """
  The colour with its hue turned `amount` degrees round the circle, R's `col_shift()`: its hue,
  as farver decodes it, plus `amount`, taken modulo 360 as R's `%%` takes it, its chroma,
  luminance and alpha kept; `nil`, R's `NA`, gives none, and no colour stays none.

  ## Examples

      iex> Scales.ColorOperations.shift("#4682B4")
      "#5E7DB7"

      iex> Scales.ColorOperations.shift("#4682B4", -30)
      "#008CA2"
  """
  @spec shift(t(), number() | nil) :: t()
  def shift(color, amount \\ @default_amount)
  def shift(:none, amount) when is_nil(amount) or is_number(amount), do: :none
  def shift(<<"#", _digits::binary>>, nil), do: :none

  def shift(<<"#", _digits::binary>> = color, amount) when is_number(amount) do
    {hue, chroma, luminance} = to_hcl(color)
    shifted = modulo(hue + amount, 360)
    from_hcl(shifted, chroma, luminance) <> own_alpha_digits(color)
  end

  # A colour's hue in degrees, chroma and luminance, CIE LCh(uv), as farver decodes them: its XYZ
  # to Luv against farver's white point, in polar form. farver takes black's chromaticity as 0
  # less the white's, times its luminance of 0, so its u and v are negative zeros and its hue
  # their angle, 180 degrees; the library's Luv of black is positive zeros, at 0 degrees.
  defp to_hcl(<<"#000000", _alpha::binary>>), do: {180.0, 0.0, 0.0}

  defp to_hcl(color) do
    {luminance, chroma, hue} =
      color
      |> to_xyz()
      |> Lindbloom.xyz_to_luv(@white_point)
      |> Lindbloom.luv_to_lchuv()

    {hue, chroma, luminance}
  end

  # `value` modulo `divisor`, its sign the divisor's, as R's `%%` takes it, as `Scales.Palette`
  # takes it too, which this module cannot call.
  defp modulo(value, divisor), do: value - Float.floor(value / divisor) * divisor

  # A colour's own alpha digits, none when it has none.
  defp own_alpha_digits(<<"#", _digits::binary-size(6)>>), do: ""
  defp own_alpha_digits(<<"#", _digits::binary-size(6), alpha::binary-size(2)>>), do: alpha

  # The digits an alpha from 0 to 1 adds to a colour as farver writes it, its byte times 255
  # rounded half to even, none when it is opaque.
  defp farver_alpha_digits(alpha) do
    case rounded_byte(alpha * 255) do
      255 -> ""
      byte -> hex_pair(byte)
    end
  end

  # A colour's red, green and blue as bytes, and its alpha from 0 to 1, as farver decodes them,
  # opaque for a colour without one.
  defp channels(<<"#", digits::binary-size(6)>>), do: channels("#" <> digits <> "FF")

  defp channels(<<"#", digits::binary-size(8)>>) do
    {:ok, <<red, green, blue, alpha>>} = Base.decode16(digits)
    {[red, green, blue], alpha / 255}
  end

  @doc """
  viridisLite's palettes by name, in the order of its options A to H.

  ## Examples

      iex> Scales.ColorOperations.viridis_options()
      [:magma, :inferno, :plasma, :viridis, :cividis, :rocket, :mako, :turbo]
  """
  @spec viridis_options() :: [atom(), ...]
  def viridis_options, do: @viridis_options

  @doc """
  `count` colours of the viridis palette `option`, one of `viridis_options/0`, as R's
  `viridisLite::viridis()` makes them: spaced from `begin` to `end`, each from 0 to 1, in that
  order for a `direction` of 1 and the other for -1, with an alpha from 0 to 1.

  ## Examples

      iex> Scales.ColorOperations.viridis(3, %{option: :viridis, begin: 0.0, end: 1.0, direction: 1, alpha: 1.0})
      ["#440154", "#21908C", "#FDE725"]
  """
  @spec viridis(non_neg_integer(), %{
          option: atom(),
          begin: number(),
          end: number(),
          direction: 1 | -1,
          alpha: number()
        }) :: [t()]
  def viridis(count, %{option: option, begin: begin, end: finish} = parameters)
      when is_integer(count) and count >= 0 do
    {knots, channels} = Map.fetch!(@viridis_splines, option)
    {from, to} = directed({begin, finish}, parameters.direction)
    alpha = alpha_digits(parameters.alpha)

    from
    |> places(to, count)
    |> Enum.map(fn place -> viridis_color(place, knots, channels) <> alpha end)
  end

  defp directed(ends, 1), do: ends
  defp directed({begin, finish}, -1), do: {finish, begin}

  # `count` places from `from` to `to`, as R's `seq(from, to, length.out = count)` spaces them:
  # the first `from` and the last `to` exactly, each one between `from` plus its index times the
  # step, in that order of operations, as `Scales.Palette` spaces a palette's levels, which
  # this boundary cannot call; one place is `from`.
  defp places(_from, _to, 0), do: []
  defp places(from, _to, 1), do: [from]

  defp places(from, to, count) do
    step = (to - from) / (count - 1)
    between = Enum.map(1..(count - 2)//1, fn index -> from + index * step end)
    Enum.concat([[from], between, [to]])
  end

  # The palette's colour at `place`, uppercase `#RRGGBB`: each channel's spline at the place, from
  # the knot at or before it, converted to sRGB as grDevices converts it.
  defp viridis_color(place, knots, channels) do
    knot = knot_before(place, knots, 0, tuple_size(knots))
    distance = place - elem(knots, knot)

    channels
    |> Enum.map(fn {values, linear, quadratic, cubic} ->
      elem(values, knot) +
        distance *
          (elem(linear, knot) + distance * (elem(quadratic, knot) + distance * elem(cubic, knot)))
    end)
    |> List.to_tuple()
    |> Lindbloom.lab_to_xyz(@grdevices_white_point)
    |> Lindbloom.xyz_to_rgb(@grdevices_to_srgb)
    |> Tuple.to_list()
    |> Enum.map_join(fn channel -> hex_pair(grdevices_byte(channel)) end)
    |> then(fn digits -> "#" <> digits end)
  end

  # The last knot at or before `place`, found by bisection as R's `spline_eval()` finds it, between
  # `low`, at or before the place, and `high`, after it or past the last knot.
  defp knot_before(place, knots, low, high) when high > low + 1 do
    middle = div(low + high, 2)

    if place < elem(knots, middle),
      do: knot_before(place, knots, low, middle),
      else: knot_before(place, knots, middle, high)
  end

  defp knot_before(_place, _knots, low, _high), do: low

  # A linear sRGB channel as grDevices writes it: companded, rounded to five decimals and clipped
  # to 0 to 1, as `convertColor()` trims it, then `rgb()`'s byte.
  defp grdevices_byte(linear) do
    linear
    |> Lindbloom.srgb_compand()
    |> round_to_five_decimals()
    |> max(0.0)
    |> min(1.0)
    |> rgb_byte()
  end

  # `value` rounded to five decimals as R's `round(value, 5)` rounds it: of the two five-decimal
  # numbers either side, each found by dividing by 100,000, the nearer, or, as near as each other,
  # the one whose last decimal is even. R rounds a negative value's magnitude and puts its sign
  # back; a negative channel is clipped to 0 whichever way it rounds, so that is left out.
  defp round_to_five_decimals(value) do
    scaled = value * 100_000
    floor = Float.floor(scaled)
    lower = floor / 100_000
    upper = Float.ceil(scaled) / 100_000
    above = upper - value
    below = value - lower

    if above < below or (above == below and :math.fmod(floor, 2.0) == 1.0),
      do: upper,
      else: lower
  end

  # The digits an alpha from 0 to 1 adds to a colour, `rgb()`'s byte, none when it is opaque.
  defp alpha_digits(alpha) do
    case rgb_byte(alpha) do
      255 -> ""
      byte -> hex_pair(byte)
    end
  end

  # An intensity from 0 to 1 as `rgb()` writes it: the byte `255 * intensity + 0.5` truncated.
  defp rgb_byte(intensity), do: trunc(255 * intensity + 0.5)

  # The colour farver writes for XYZ on its scale, Y of 100 for white: through its matrix, each
  # channel a byte.
  defp from_xyz({x, y, z}) do
    {x / 100, y / 100, z / 100}
    |> Lindbloom.xyz_to_rgb(@to_srgb)
    |> Tuple.to_list()
    |> Enum.map_join(fn channel -> hex_pair(byte(channel)) end)
    |> then(fn digits -> "#" <> digits end)
  end

  # A linear sRGB channel as farver writes it: companded, times 255, and a byte.
  defp byte(linear), do: rounded_byte(Lindbloom.srgb_compand(linear) * 255)

  # A value on a byte's scale as farver writes it: rounded to the nearest whole number, a half to
  # the even one, and clamped to a byte. farver rounds as its `double2int()` does, by adding 1.5
  # times 2^52, which leaves a double no fraction, rounded as IEEE arithmetic rounds, so taking it
  # away again leaves the rounded number.
  defp rounded_byte(scaled) do
    (scaled + @rounding - @rounding)
    |> trunc()
    |> max(0)
    |> min(255)
  end

  defp hex_pair(byte) do
    byte
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
  end

  # The library reads the colour into sRGB channels, each a byte over 255, and writes them back as
  # hex, the alpha left out when it is opaque; the bytes come back as they went in.
  defp spelled(colour) do
    {:ok, srgb} = Color.SRGB.parse(colour)

    spelling =
      srgb
      |> Color.SRGB.to_hex()
      |> String.upcase()

    {:ok, spelling}
  end
end
