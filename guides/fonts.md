# Fonts

A plot names the fonts its text is drawn in by family name, and nothing else: no font file or
value travels in a plot. Where the project lists Pica, the optional package that shapes text,
Giggly measures and draws a label in the font Pica holds for its family and face. Without Pica,
every label is measured with Giggly's built-in metrics, those of Liberation Sans, and written as
text naming its family.

## Naming a family

A complete theme takes `base_family:`, the family of all its text and of its layers' text, and
`header_family:`, the family of its titles: the axes' titles, the legends' titles and the plot's
title.

```elixir
alias Giggly.Plot

Giggly.Datasets.mpg()
|> Plot.new(%{x: :displ, y: :hwy})
|> Plot.geom_point()
|> Plot.theme_gray(base_family: "Lato", header_family: "Lobster")
|> Giggly.to_svg()
```

`Giggly.Plot.theme/2` sets a family on any text, inherited as any property is:
`text: [family: "Lato"]` reaches every text but a layer's, and `title: [family: "Lobster"]` the
titles. `Giggly.Plot.geom_text/3` takes its own `family:`, and otherwise the complete theme's base
family.

`""` is the default sans-serif, and `"sans"`, `"serif"` and `"mono"` are the generic families.
Any other name is a font's family name, such as `"Times New Roman"`.

## Without Pica

Every label is measured with the built-in metrics and written as SVG text naming its family,
stretched or squeezed to the width measured, so the layout holds whatever font the viewer's
browser draws it in. A viewer whose machine has the font sees it, at Liberation Sans's widths; a
viewer without it sees the browser's fallback.

## With Pica

List Pica in the project's dependencies. Giggly lists it as optional, so a project that wants it
lists it itself:

```elixir
def deps do
  [
    {:giggly, "~> 0.1.0"},
    {:pica, "~> 0.1.0"}
  ]
end
```

A label whose family and face Pica holds a font for is then measured from that font, and drawn as
the font's outlines (see [Outlines or text](#outlines-or-text)). Every other label is measured
and drawn as without Pica.

### Registering fonts

Register a family's font files with Pica once, as the project starts:

```elixir
{:ok, regular} = Pica.load(File.read!("priv/fonts/Lato-Regular.ttf"))
{:ok, bold} = Pica.load(File.read!("priv/fonts/Lato-Bold.ttf"))
:ok = Pica.register("Lato", plain: regular, bold: bold)
```

The name a family is registered under is the name a plot gives it. Where to register in an
application, and what registering costs: Pica's guide,
[Registering fonts](`e:pica:registering-fonts.md`).

### Installed fonts

A family no font is registered under is looked for among the fonts installed on the machine, by
its exact family name. The first such search reads every font file on the machine, once for the
life of the VM. `""` and the generic names are never looked for, and stay on the built-in metrics
unless a font is registered under that exact name.

To draw with the registered fonts alone, so that a drawing never depends on the machine it is
made on, pass `installed_fonts: false`:

```elixir
Giggly.to_svg(plot, installed_fonts: false)
```

### Faces

A text's `face:` asks for `:plain`, `:bold`, `:italic` or `:bold_italic`. Each face is its own
font: a face no font is registered or installed for is measured with the built-in metrics, never
with another face's font.

## Outlines or text

`Giggly.to_svg/2`'s `text:` says how a label in a font Pica holds is written:

* `:outlines`, the default, draws it as the font's own glyph shapes, each glyph defined once in
  the drawing, so it looks the same to every viewer, whatever fonts their machine has. Its words
  are kept as unseen text, so a screen reader reads them, and they can be selected and found in
  the page.
* `:text` writes it as text naming its family, fitted to the width measured: a smaller drawing,
  which a viewer without the font sees in the browser's fallback.

```elixir
Giggly.to_svg(plot, text: :text)
```

A label in a family Pica holds no font for is written as text either way.
