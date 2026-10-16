defmodule Giggly.ColorOperations do
  @moduledoc false

  # Colour operations: reading a colour as a user writes one, and, as the palettes arrive, the
  # conversions R's palettes make between colour spaces. It is the one module that calls the
  # `color` library, so the library and R's colour constants each have one home.
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

  # The library's one caller: it may call `Color` and nothing else, and only a boundary that lists
  # it may call it. `Giggly` lists `Color` too, as boundary lets a sub-boundary list only what its
  # parent does; no other domain lists it.
  use Boundary, deps: [Color], exports: []

  alias Color.CSS.Names

  @typedoc "A colour: uppercase `#RRGGBB`, or `#RRGGBBAA` with an alpha of its own, or `:none`."
  @type t :: String.t() | :none

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
