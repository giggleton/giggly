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
  # clamped to a byte, as farver writes one. The conversions are the library's
  # (`Color.Conversion.Lindbloom`), handed farver's constants: its white point, made from D65's
  # chromaticity in its own arithmetic rather than the textbook 95.047 and 108.883, and its sRGB
  # matrix. With them it gives R's colours exactly.

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

  # farver's matrix from XYZ to linear sRGB.
  @to_srgb [
    [3.2404542, -1.5371385, -0.4985314],
    [-0.9692660, 1.8760108, 0.0415560],
    [0.0556434, -0.2040259, 1.0572252]
  ]

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
    |> unit_tristimulus()
    |> Lindbloom.xyz_to_rgb(@to_srgb)
    |> Tuple.to_list()
    |> Enum.map_join(fn channel -> hex_pair(byte(channel)) end)
    |> then(fn digits -> "#" <> digits end)
  end

  # XYZ on farver's scale, Y of 100 for white, as farver hands its matrix: Y of 1.
  defp unit_tristimulus({x, y, z}), do: {x / 100, y / 100, z / 100}

  # A linear sRGB channel as farver writes it: companded, times 255, rounded to the nearest whole
  # number, a half to the even one, and clamped to a byte. farver rounds as its `double2int()` does,
  # by adding 1.5 times 2^52, which leaves a double no fraction, rounded as IEEE arithmetic rounds,
  # so taking it away again leaves the rounded number.
  defp byte(linear) do
    scaled = Lindbloom.srgb_compand(linear) * 255

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
