defmodule Giggly.ColorOperations do
  @moduledoc false

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
  # `#RRGGBBAA`, its digits in either case; `transparent`, CSS's black with no alpha, where R's is
  # white; or `:none`. A name CSS does not define, such as R's `grey50`, is refused, and so is
  # anything else, CSS's functions (`rgb()`) and the spellings the library forgives (a hex colour
  # without its `#`, a name with spaces) among them.
  #
  # `from_hcl/3` is the colour farver encodes from a hue, chroma and luminance, as `pal_hue()` asks
  # it with `encode_colour(from = "hcl")`: CIE LCh(uv) to Luv, to XYZ against farver's white point,
  # to sRGB through farver's matrix, each channel companded, times 255, rounded half to even and
  # clamped to a byte, as farver writes one. `to_lab/1` is a colour's CIE L*a*b* as farver decodes
  # it (`decode_colour(to = "lab")`), each byte over 255 expanded from sRGB's companding, to XYZ
  # through farver's matrix the other way, to Lab against its white point; and `from_lab/1` the
  # colour farver encodes from L*a*b*, to XYZ and then as `from_hcl/3` goes on, as R's gradients
  # (`scales::colour_ramp()`) blend their colours in Lab. The conversions are the library's
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

  # The library's one caller: it may call `Color` and nothing else, and only a boundary that lists
  # it may call it. `Giggly` lists `Color` too, as boundary lets a sub-boundary list only what its
  # parent does; no other domain lists it.
  use Boundary, deps: [Color], exports: []

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

  # The colour `colour` writes, in its one spelling, or `:error` when it is not a CSS colour.
  @doc false
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

  # CSS's `transparent` is black with no alpha.
  defp keyword("transparent"), do: {:ok, "#00000000"}
  defp keyword(name) when name in @not_css, do: :error

  defp keyword(name) do
    if String.match?(name, @name_letters) and Names.known?(name), do: spelled(name), else: :error
  end

  # The colour, uppercase `#RRGGBB`, that farver encodes from `hue` in degrees, `chroma` and
  # `luminance`, as the opening comment says.
  @doc false
  @spec from_hcl(number(), number(), number()) :: String.t()
  def from_hcl(hue, chroma, luminance)
      when is_number(hue) and is_number(chroma) and is_number(luminance) do
    {luminance, chroma, hue}
    |> Lindbloom.lchuv_to_luv()
    |> Lindbloom.luv_to_xyz(@white_point)
    |> from_xyz()
  end

  # The CIE L*a*b* of `colour`, an opaque `#RRGGBB`, as the opening comment says.
  @doc false
  @spec to_lab(String.t()) :: {float(), float(), float()}
  def to_lab(<<"#", digits::binary-size(6)>>) do
    {:ok, <<red, green, blue>>} = Base.decode16(digits)

    [red, green, blue]
    |> Enum.map(fn channel -> Lindbloom.srgb_inverse_compand(channel / 255) * 100 end)
    |> List.to_tuple()
    |> Lindbloom.rgb_to_xyz(@from_srgb)
    |> Lindbloom.xyz_to_lab(@white_point)
  end

  # The colour, uppercase `#RRGGBB`, that farver encodes from `lab`, its L*, a* and b*, as the
  # opening comment says.
  @doc false
  @spec from_lab({number(), number(), number()}) :: String.t()
  def from_lab({_lightness, _a, _b} = lab) do
    lab
    |> Lindbloom.lab_to_xyz(@white_point)
    |> from_xyz()
  end

  # The colour `amount` of the way from `from` to `to`, each a colour in its one spelling, as the
  # opening comment says: 0 is `from` and 1 is `to`.
  @doc false
  @spec mix(String.t(), String.t(), number()) :: String.t()
  def mix(<<"#", _from_digits::binary>> = from, <<"#", _to_digits::binary>> = to, amount)
      when is_number(amount) and amount >= 0 and amount <= 1 do
    {from_channels, from_alpha} = channels(from)
    {to_channels, to_alpha} = channels(to)

    digits =
      Enum.zip_with(from_channels, to_channels, fn from_channel, to_channel ->
        hex_pair(rounded_byte(from_channel * (1 - amount) + to_channel * amount))
      end)

    alpha = rounded_byte((from_alpha * (1 - amount) + to_alpha * amount) * 255)
    Enum.join(["#" | digits]) <> if(alpha == 255, do: "", else: hex_pair(alpha))
  end

  # A colour's red, green and blue as bytes, and its alpha from 0 to 1, as farver decodes them,
  # opaque for a colour without one.
  defp channels(<<"#", digits::binary-size(6)>>), do: channels("#" <> digits <> "FF")

  defp channels(<<"#", digits::binary-size(8)>>) do
    {:ok, <<red, green, blue, alpha>>} = Base.decode16(digits)
    {[red, green, blue], alpha / 255}
  end

  # viridisLite's palettes by name, in the order of its options A to H.
  @doc false
  @spec viridis_options() :: [atom(), ...]
  def viridis_options, do: @viridis_options

  # `count` colours of the viridis palette `option`, one of `viridis_options/0`, as R's
  # `viridis()` makes them, as the opening comment says: from `begin` to `end`, each from 0 to 1,
  # in that order for a `direction` of 1 and the other for -1, with an alpha from 0 to 1.
  @doc false
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
  # step, in that order of operations, as `Giggly.Scale.Palette` spaces a palette's levels, which
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
