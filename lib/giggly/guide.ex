defprotocol Giggly.Guide do
  @moduledoc false

  # Guides: what lets a reader turn marks back into data. In ggplot2, axes and legends are both
  # guides (`guide_axis()`, `guide_legend()`), each drawing what it is given of a scale's breaks.
  # Giggly draws axes (`Giggly.Guide.Axis`), the axis around a radial panel's circle among them
  # (`Giggly.Guide.AxisTheta`, ggplot2's `guide_axis_theta()`); the panel's background and grid
  # lines (`Giggly.Guide.Grid`), which ggplot2 draws with `guide_grid()`; the strips that label a
  # facet's panels with their values (`Giggly.Guide.Strip`), which ggplot2's facets draw with
  # `render_strips()`: a strip, like an axis, tells a reader what data the marks beside it show;
  # and the guides of the aesthetics other than position, whose kinds this protocol draws, stacked
  # in a box (`Giggly.Guide.Box`), as ggplot2's guides package theirs. It also draws the plot's own
  # labels (`Giggly.Guide.Title`), its title, subtitle, caption and tag, as the axes' titles are
  # drawn here, each of which, like every title a guide draws, may run over several lines.
  #
  # A scale records its guide by name, as ggplot2's scale carries `guide`, and the assembly turns
  # the name into a struct of its kind: a legend (`Giggly.Guide.Legend`), `guide_legend()`, so far
  # the one kind. A kind is one module holding its struct, whose fields are its parameters, and its
  # drawing, in a `defimpl Giggly.Guide` whose first line classifies it into this boundary. A guide
  # never sees a scale or calls a geom: the assembly works out its keys from the scale, and
  # rendering has each layer's geom draw its glyphs in them.
  #
  # When a plot is rendered, the axes, their titles, the grid and the strips are drawn through
  # their modules, each handed the plot's coordinate system and a panel's params, or a panel's
  # labels, and the plot's complete theme (`Giggly.Theme`); each comes back as a size and
  # primitives, ready to be cells of the scene beside or in the panel.

  # A guide asks the coordinate system where the breaks go, reads its look from the theme,
  # measures text, and draws primitives. It exports the modules rendering draws a panel's axes,
  # grid and strips and the plot's labels with and stacks the guides of other aesthetics in, and
  # the kinds, whose structs the assembly builds, and nothing a kind draws with: that is in the
  # kinds' protocol implementations.
  use Boundary,
    deps: [Giggly.Coord, Giggly.Font, Giggly.Scene, Giggly.Theme],
    exports: [Axis, Box, Colorbar, Grid, Legend, Strip, Title]

  alias Giggly.{Scene, Theme}

  @typedoc """
  Something drawn beside the panel: how far it reaches out, in points (its width beside the panel
  or its height above or below it), and what it draws, placed in a cell that deep and as long as
  the panel's side.
  """
  @type drawn :: {float(), [Scene.primitive()]}

  @typedoc """
  A guide of an aesthetic other than position, as rendering hands it over: its title and its keys,
  each its label and the glyphs the layers drawing in it draw, among what the assembly gave each
  key and the guide.
  """
  @type legend :: %{
          required(:title) => String.t(),
          required(:keys) => [%{required(:label) => String.t(), required(:glyphs) => list()}],
          optional(atom()) => term()
        }

  # The guide `guide` draws for `legend`, in `theme`'s look: its width in points and its table, a
  # nested `Giggly.Scene` sized in points, for the box of guides right of the panels.
  @doc false
  @spec draw(t(), legend(), Theme.t()) :: {float(), Scene.t()}
  def draw(guide, legend, theme)
end
