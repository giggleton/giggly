defmodule Giggly.FontSymbolTest do
  # Not async: it registers a font as "symbol" with Pica, an app-wide singleton every measure of the
  # symbol face reads, so no other test may measure while it is registered; ExUnit runs this module
  # after the async ones.
  use ExUnit.Case, async: false

  # svglite 2.2.2 draws a plotmath sign in the font its `symbol` alias names, as
  # `user_fonts = list(symbol = ...)` sets it, measured from that font as any other.
  if Code.ensure_loaded?(Pica) do
    alias Giggly.Font

    @tag :pica
    test "the symbol face is measured and drawn from the font registered as symbol" do
      {:ok, font} = Pica.lookup("Lato", :plain, installed: false)
      table_width = Font.width("+", 12, "", :symbol, false)
      :ok = Pica.register("symbol", plain: font)

      try do
        assert {Font.width("+", 12, "Lobster", :symbol, false),
                Font.glyphs(["+"], 12, "", :symbol, false)} ===
                 {Font.width("+", 12, "Lato", :plain, false),
                  Font.glyphs(["+"], 12, "Lato", :plain, false)}

        refute Font.width("+", 12, "Lato", :plain, false) === table_width
      after
        Pica.unregister("symbol")
      end
    end
  end
end
