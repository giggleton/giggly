defmodule Giggly.Plot do
  @moduledoc """
  Describes a plot: its data, a mapping from aesthetics to columns, and layers added with a pipe.

      rows
      |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      |> Giggly.Plot.geom_point()

  A plot is a value and draws nothing itself: `Giggly.to_svg/2` draws it, and
  `Giggly.layer_data/2` shows the table a layer computes.

  ## Data

  The data is anything implementing `Table.Reader`: a list of maps, a map of columns, an Explorer
  data frame. `new/2` reads it once, into a `Giggly.DataFrame`. A layer can draw a table of its
  own instead, given by its `data:` option; under a facet, a table lacking the faceting columns
  is drawn in every panel:

      iex> mtcars = %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "cyl" => [6, 4, 8]}
      iex> frame =
      ...>   mtcars
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point(data: %{"wt" => [3.0], "mpg" => [20.0]}, colour: "#D9D9D9")
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.facet_wrap(:cyl)
      ...>   |> Giggly.layer_data(0)
      iex> Giggly.DataFrame.pull(frame, :panel)
      [1, 2, 3]

  ## Mapping and setting aesthetics

  Every layer function takes a mapping, a map, and options, a keyword list, either or both. A map
  maps an aesthetic to a column, `%{x: :wt}`, or to an expression or a constant, as
  `Giggly.Mapping` describes; a keyword list sets it to one value for every mark, `alpha: 0.4`.
  The plot's mapping applies to every layer, and a layer's own mapping is laid over it.

  A misspelt column, or an aesthetic a layer cannot use, raises from the function that names it.
  An aesthetic the plot maps that a layer cannot use is ignored by that layer, so a plot can map
  `:label` for its text and still draw points. Whether a column's type suits an axis is checked
  when the plot is run.

  ## Colours

  A colour is a CSS colour name, such as `"steelblue"`, a hex colour, such as `"#4682B4"`, or
  `"#4682B480"` with an alpha of its own, or `"transparent"`; `:none` draws nothing. A name CSS
  does not define raises. An alpha, set or mapped, replaces a colour's own.

  A discrete column mapped to `:color` (or `:colour`) or `:fill` gives each of its values a hue,
  evenly spaced round the colour wheel, so three values are `#F8766D`, `#00BA38` and `#619CFF`; a
  missing value is grey, `#7F7F7F`, and its key in the legend comes last, labelled `NA`.

      iex> plot =
      ...>   %{"wt" => [2.62, 2.875, 2.32], "mpg" => [21.0, 22.8, 22.8], "cyl" => ["6", "4", nil]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#00BFC4", "#F8766D", "#7F7F7F"]

  A column of numbers mapped to colour or fill gives each value a colour as far along a gradient
  from `#132B43` to `#56B1F7` as the value is through the column's range; a missing value is grey
  here too. Its guide is a colour bar.

      iex> plot =
      ...>   %{"wt" => [2.62, 2.875, 2.32], "mpg" => [21.0, 22.8, 22.8], "hp" => [110, 93, nil]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :hp})
      ...>   |> Giggly.Plot.geom_point()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#56B1F7", "#132B43", "#7F7F7F"]

  A legend or colour bar is drawn for each mapped aesthetic, stacked down the right of the panels
  in the order of the aesthetics' names (`alpha`, `color`, `fill`, `shape`, `size`). Two with the
  same title and labels, such as a colour and a fill mapped to one column, are drawn as one.

  ## Guides

  A guide reads a scale back: a legend, a key for each break, or, for a continuous colour or fill,
  a colour bar. Each scale function's `guide:` chooses its scale's, `:legend`, `:colorbar`,
  `:none` for none, or a legend `guide_legend/1` makes, whose keys may run in reverse; `guides/2`
  chooses them by aesthetic over whatever the scales say.

  ## Scales

  Each axis gets a scale from the type of what is mapped to it: a continuous scale for numbers, a
  discrete one for text, booleans and factors, a date one for dates. `scale_x_continuous/2`,
  `scale_x_discrete/2` and `scale_x_date/2`, and their y twins, set an axis's title, limits,
  breaks, labels and how far it reaches; `xlim/3`, `ylim/3` and `lims/2` set its limits alone, two
  ends for a continuous or a date axis and, with `xlim/2` and `ylim/2`, a list of values for a
  discrete one. A value outside the limits is missing, so its mark is not drawn. A continuous scale
  given a column of dates places each at its days since 1970-01-01.

  A colour, fill, alpha, shape or size scale chooses how values become colours, opacities, shapes or
  sizes, and sets its legend's title, limits, breaks and labels: `scale_color_manual/2` names each
  value's colour, `scale_color_hue/2` spaces hues round the colour wheel, `scale_color_gray/2`
  greys, `scale_color_discrete/2` either, and `scale_color_viridis_d/2` takes colours from a
  viridis palette, as an ordered factor gets by default; `scale_color_gradient/2`,
  `scale_color_gradient2/2`, `scale_color_gradientn/2` and `scale_color_continuous/2` blend a
  gradient through two, three or any number of colours, and `scale_color_viridis_c/2` through a
  viridis palette; each has a `scale_fill_` twin, and `scale_alpha_continuous/2` and
  `scale_alpha_discrete/2` set opacities. `scale_size_continuous/2` and `scale_size_area/2` size
  points by area, the second from 0, `scale_radius/2` by width, and `scale_size_discrete/2` a
  discrete column's values in order. `scale_shape_discrete/2` gives a discrete column's values six
  shapes, solid or open, and `scale_shape_manual/2` names each value's shape; shapes have no order,
  so a continuous column cannot be mapped to `:shape`. `lims/2` sets their limits alone. A value
  outside a colour scale's limits takes its `na_value:`, as a missing one does.

  ## Labels

  Each axis and legend is titled by what is mapped to it, as `Giggly.Mapping` describes. `labs/2`
  titles them otherwise, and gives the plot a title, a subtitle, a caption and a tag; a scale's
  name titles its axis over both.

  ## Theme

  Everything but the marks is drawn in ggplot2's default theme, a grey panel with white grid lines.
  `theme/2` changes any element of it by name, each inheriting what it leaves unset from its parent
  in ggplot2's tree, so setting `text: [size: 14]` makes every label bigger, and
  `axis_text_x: [color: "red"]` reddens only the x axis's labels. An element set to `:none` is
  removed, with everything that inherits from it, and `legend_position: :none` draws no legends.
  """

  # A plot is a description: it may use the aesthetic vocabulary, the data frame, the kinds of
  # facet, coordinate system, geom, stat and position, whose structs it builds and whose facts it
  # checks a layer against, the guides, whose legend's struct it builds, the scales, whose
  # untrained structs it writes, the theme, whose tree `theme/2` builds its schema from and whose
  # settings it merges, NimbleOptions, which validates its functions' options at the
  # call, the colour operations, which read a colour an option sets, and the mapping grammar, whose
  # checks resolve each mapping value as it enters (`Giggly.Mapping`; it calls those alone, never
  # the evaluation, which holds by review), and nothing that runs it. The six families' roots are
  # protocols that compute and draw, the guides' other modules that hold no struct draw, and the
  # scales' root trains and maps; `GigglyCredo.Check.PlotRunsNothing` keeps them all out of these
  # files, which boundary cannot, since a boundary always exports its root. A layer is read only
  # through `computed_mapping/2`, `layer_geom/1`, `layer_stat/1` and `layer_position/1`, so
  # `Layer` stays private.
  use Boundary,
    deps: [
      Giggly.Aesthetics,
      Giggly.ColorOperations,
      Giggly.Coord,
      Giggly.DataFrame,
      Giggly.Facet,
      Giggly.Geom,
      Giggly.Guide,
      Giggly.Mapping,
      Giggly.Position,
      Giggly.Scale,
      Giggly.Stat,
      Giggly.Theme,
      NimbleOptions
    ],
    exports: []

  alias Giggly.{
    Aesthetics,
    ColorOperations,
    Coord,
    DataFrame,
    Facet,
    Geom,
    Guide,
    Mapping,
    Position,
    Scale,
    Stat,
    Theme
  }

  alias Giggly.Plot.Layer

  @enforce_keys [
    :data,
    :mapping,
    :facet,
    :coord,
    :scales,
    :guides,
    :theme,
    :labels,
    :reversed_layers
  ]
  defstruct @enforce_keys

  @typedoc "An aesthetic's name, such as `:x`, `:y` or `:color`."
  @type aesthetic :: atom()

  @typedoc """
  A mapping as stored: aesthetic to its value resolved, each column it reads named as a string, in
  the table the layer draws.
  """
  @type mapping :: Mapping.t()

  @typedoc "How the plot's rows are split into panels: a facet's struct."
  @type facet :: struct()

  @typedoc "How positions are placed in each panel: a coordinate system's struct."
  @type coord :: struct()

  @typedoc "The scales the plot sets, by aesthetic: each a scale's struct, as yet untrained."
  @type scales :: %{optional(aesthetic()) => struct()}

  @typedoc """
  The guide that reads an aesthetic's scale back: `:legend`, `:colorbar`, `:none` for none, or a
  legend `guide_legend/1` makes.
  """
  @type guide :: :none | :legend | :colorbar | struct()

  @typedoc "The guides `guides/2` sets, by aesthetic, each winning over its scale's own."
  @type guides :: %{optional(aesthetic()) => guide()}

  @typedoc """
  The look everything but the marks is drawn in: the complete theme, by name, and the settings
  `theme/2` has laid over it, by element.
  """
  @type theme :: %{complete: :gray, settings: %{optional(atom()) => term()}}

  @typedoc """
  The labels `labs/2` sets, by what each titles: an aesthetic's guide, or the plot's `:title`,
  `:subtitle`, `:caption` or `:tag`; each its text, or `:none` for none.
  """
  @type labels :: %{optional(atom()) => String.t() | :none}

  @typedoc """
  A plot: its data, its mapping, its facet, coordinate system, scales, the guides `guides/2`
  sets, its theme, the labels `labs/2` sets, and its layers newest first (each function adds one at the front; they are
  assembled in the order they were added).
  """
  @type t :: %__MODULE__{
          data: DataFrame.t(),
          mapping: mapping(),
          facet: facet(),
          coord: coord(),
          scales: scales(),
          guides: guides(),
          theme: theme(),
          labels: labels(),
          reversed_layers: [struct()]
        }

  @typedoc "A column of a table as written: its name as an atom or a string."
  @type column_reference :: atom() | String.t()

  @typedoc "A mapping as written: aesthetic to a column, an expression or a constant."
  @type mapping_argument :: %{optional(aesthetic()) => Mapping.value()}

  # `facet_wrap/3`'s options, validated at the call as every public function's are.
  @facet_wrap_options NimbleOptions.new!(
                        nrow: [
                          type: :pos_integer,
                          doc: "How many rows to lay the panels out in."
                        ],
                        ncol: [
                          type: :pos_integer,
                          doc: "How many columns to lay the panels out in."
                        ],
                        scales: [
                          type: {:in, [:fixed, :free_x, :free_y, :free]},
                          default: :fixed,
                          doc:
                            "Whether the panels share each axis's scale (`:fixed`), or each " <>
                              "panel has its own x scale (`:free_x`), y scale (`:free_y`) or both " <>
                              "(`:free`), and draws its own axis for each."
                        ]
                      )

  # A table of a layer's own, an option of every function that adds a layer, as ggplot2's `data =`
  # gives one; read after validation, as `new/2` reads the plot's.
  @data_option [
    type: :any,
    doc:
      "A table for the layer to draw instead of the plot's data, anything implementing " <>
        "`Table.Reader`. The plot's mapping applies to it, so it must hold each column the " <>
        "plot's mapping names for an aesthetic the layer neither maps nor sets. Under a facet, " <>
        "a table lacking a faceting column is drawn in every panel of that column's values."
  ]

  # An aesthetic set to one value for every mark of a layer, an option of the function that adds
  # the layer, as ggplot2's `geom_point(alpha = 0.4)` sets it. A number from 0 to 1 is kept as a
  # float, as R keeps it.
  @alpha_option [
    type: {:custom, __MODULE__, :validate_alpha, []},
    doc: "How opaque every mark is, from 0, invisible, to 1, opaque."
  ]

  # A line's width set for every line of a layer, in millimetres, as ggplot2's `linewidth = 2`
  # sets it, kept as a float.
  @linewidth_option [
    type: {:custom, __MODULE__, :validate_linewidth, []},
    doc: "How wide every line is, in millimetres; 0.5 when not given."
  ]

  # The line types, by name in the order of their numbers, 0 to 6, each held as its dash pattern:
  # the lengths of its dashes and gaps in turn, `{}` for a solid line, and `:none` for a blank one,
  # which draws no line, as R's graphics engine reads `lty`.
  @line_types [
    blank: :none,
    solid: {},
    dashed: {4, 4},
    dotted: {1, 3},
    dotdash: {1, 3, 4, 3},
    longdash: {7, 3},
    twodash: {2, 2, 6, 2}
  ]
  @line_type_names Keyword.keys(@line_types)

  # A line type set for every line of a layer, as ggplot2's `linetype = "dashed"` sets it, held as
  # its dash pattern.
  @linetype_type {:custom, __MODULE__, :validate_linetype, []}

  # The line types an option that sets one takes.
  @linetype_forms "`:blank`, which draws no line, `:solid`, `:dashed`, `:dotted`, `:dotdash`, " <>
                    "`:longdash` or `:twodash`, or its number in that order, 0 to 6; or a dash " <>
                    "pattern, a tuple of 2, 4, 6 or 8 lengths from 1 to 15, a dash and a gap in " <>
                    "turn, which grow with the line's width, `{4, 4}` being `:dashed`"

  @linetype_option [
    type: @linetype_type,
    doc: "The line type of every line: " <> @linetype_forms <> "; `:solid` when not given."
  ]

  # A colour set for every mark of a layer, as ggplot2's `colour = "steelblue"` sets it, kept in the
  # one spelling `Giggly.ColorOperations` gives it: uppercase hex, or `:none`.
  @color_type {:custom, __MODULE__, :validate_color, []}

  # The colours an option that sets one takes.
  @color_forms ~S(a CSS colour name, such as `"steelblue"`, a hex colour, such as `"#4682B4"`, ) <>
                 ~S(or `"#4682B480"` with an alpha of its own, `"transparent"`, or `:none` ) <>
                 "for none"

  @point_color_option [
    type: @color_type,
    doc:
      "The colour of every point, written `colour:` or `color:`, which outlines its shape and " <>
        "fills the shapes filled in it: " <> @color_forms <> "; black when not given."
  ]

  # The shapes a point is drawn in, by name, in the order of their numbers, 0 to 25.
  @shapes Geom.Point.shapes()

  # A point's look set for every point of a layer, as ggplot2's `geom_point(shape = 21, size = 3)`
  # sets it: a shape a number names kept as its name, and a size or stroke as a float.
  @point_fill_option [
    type: @color_type,
    doc:
      "The colour every point of a shape with a fill of its own is filled with: " <>
        @color_forms <> "; none when not given."
  ]

  @point_shape_option [
    type: {:custom, __MODULE__, :validate_shape, []},
    doc:
      "The shape every point is drawn in, by its name or its number, as listed above, or " <>
        "`:none` for no point; `:circle` when not given."
  ]

  @point_size_option [
    type: {:custom, __MODULE__, :validate_size, []},
    doc: "How big every point is, in millimetres; 1.5 when not given."
  ]

  @point_stroke_option [
    type: {:custom, __MODULE__, :validate_stroke, []},
    doc:
      "How heavy every point's outline is, in millimetres, or `:none` for no outline and no " <>
        "lines; 0.5 when not given. The outline is drawn half that wide, and a heavier stroke " <>
        "makes the shape bigger too."
  ]

  @bar_color_option [
    type: @color_type,
    doc:
      "The colour of every bar's border, written `colour:` or `color:`: " <>
        @color_forms <>
        "; no border when not given. A border takes no alpha but its colour's own."
  ]

  @bar_fill_option [
    type: @color_type,
    doc: "The colour every bar is filled with: " <> @color_forms <> "; `#595959` when not given."
  ]

  @bar_linewidth_option [
    type: {:custom, __MODULE__, :validate_linewidth, []},
    doc: "How wide every bar's border is, in millimetres; 0.5 when not given."
  ]

  @bar_linetype_option [
    type: @linetype_type,
    doc:
      "The line type of every bar's border: " <> @linetype_forms <> "; `:solid` when not given."
  ]

  @line_color_option [
    type: @color_type,
    doc:
      "The colour of every line, written `colour:` or `color:`: " <>
        @color_forms <> "; black when not given."
  ]

  # How a layer's lines are drawn at their ends and corners: ggplot2's `lineend`, `linejoin` and
  # `linemitre`, grid's line parameters.
  @line_style_options [
    lineend: [
      type: {:in, [:butt, :round, :square]},
      default: :butt,
      doc:
        "How a line's ends are drawn: cut square at the end (`:butt`), rounded (`:round`), or " <>
          "cut square half the line's width beyond it (`:square`)."
    ],
    linejoin: [
      type: {:in, [:round, :mitre, :bevel]},
      default: :round,
      doc:
        "How a line turns a corner: rounded (`:round`), pointed (`:mitre`) or cut off (`:bevel`)."
    ],
    linemitre: [
      type: {:custom, __MODULE__, :validate_linemitre, []},
      default: 10.0,
      doc:
        "How far a pointed corner may reach, in widths of the line, before it is cut off; " <>
          "1 or more."
    ]
  ]

  @text_color_option [
    type: @color_type,
    doc:
      "The colour of every label, written `colour:` or `color:`: " <>
        @color_forms <> "; black when not given."
  ]

  # How a label is justified, along its baseline (`hjust`) or up its height (`vjust`): a number, or
  # one of ggplot2's words.
  @justification_forms "a number from 0 to 1, or one of the words `:left`, `:center` and " <>
                         "`:right`, `:bottom`, `:middle` and `:top`, or `:inward` and " <>
                         "`:outward`, which justify each label toward or away from the middle " <>
                         "of the panel by where it falls"

  # The options that set an aesthetic rather than choose how a layer is drawn.
  @fixed_aesthetics [
    :alpha,
    :color,
    :fill,
    :linewidth,
    :linetype,
    :shape,
    :size,
    :stroke,
    :angle,
    :hjust,
    :vjust,
    :family,
    :nudge_x,
    :nudge_y,
    :label,
    :xmin,
    :xmax,
    :ymin,
    :ymax,
    :width
  ]

  # `geom_point/3`'s options, validated at the call.
  @point_options NimbleOptions.new!(
                   data: @data_option,
                   alpha: @alpha_option,
                   color: @point_color_option,
                   fill: @point_fill_option,
                   shape: @point_shape_option,
                   size: @point_size_option,
                   stroke: @point_stroke_option
                 )

  # How every bar of a layer looks, set by its options.
  @bar_look_options [
    alpha: @alpha_option,
    color: @bar_color_option,
    fill: @bar_fill_option,
    linewidth: @bar_linewidth_option,
    linetype: @bar_linetype_option
  ]

  # Which of x and y a counting or binning layer runs along, ggplot2's `orientation`: a claim the
  # call checks against the one of them mapped, which decides it, so it is recorded nowhere.
  @runs_along_option [
    type: {:in, [:x, :y]},
    doc:
      "The axis the layer runs along, `:x` or `:y`, which must be the one of `:x` and `:y` " <>
        "mapped; it runs along that one when this is not given."
  ]

  # How wide every bar is, an option of `geom_bar/3` and `geom_col/3` that sets the aesthetic.
  @bar_width_option [
    type: {:custom, __MODULE__, :validate_width, []},
    doc:
      "How wide every bar is, in the units of the axis it stands on, any number; it replaces " <>
        "the width the bars would take otherwise, and a mapped `:width`."
  ]

  # Where every bar sits against its position, an option of `geom_bar/3` and `geom_col/3` that
  # chooses how the bar geom draws.
  @bar_just_option [
    type: {:custom, __MODULE__, :validate_just, []},
    default: 0.5,
    doc:
      "Where each bar sits against its position, a number from 0 to 1: 0 puts its lower edge " <>
        "there, 1 its upper edge, and 0.5 centres it."
  ]

  # How bars that share an `x` are placed, an option of `geom_bar/3` and `geom_col/3`.
  @bar_position_option [
    type: {:custom, __MODULE__, :validate_bar_position, []},
    default: :stack,
    doc:
      "How bars that share an `x` are placed: piled on one another (`:stack`), set side by " <>
        "side within the width one bar takes (`:dodge`), or set side by side, each its share " <>
        "of their widths, with a gap between them (`:dodge2`, or as `position_dodge2/1` says)."
  ]

  # `geom_col/3`'s options, validated at the call.
  @bar_options NimbleOptions.new!(
                 [
                   data: @data_option,
                   position: @bar_position_option,
                   width: @bar_width_option,
                   just: @bar_just_option
                 ] ++ @bar_look_options
               )

  # `geom_bar/3`'s options, validated at the call: a bar's, and the axis its counting runs along.
  @count_options NimbleOptions.new!(
                   [
                     data: @data_option,
                     position: @bar_position_option,
                     orientation: @runs_along_option,
                     width: @bar_width_option,
                     just: @bar_just_option
                   ] ++ @bar_look_options
                 )

  # How a binning layer cuts its axis into bins, options of every function that adds one.
  @binning_options [
    bins: [
      type: :pos_integer,
      default: 30,
      doc: "How many bins span the axis, when neither `binwidth:` nor `breaks:` is given."
    ],
    binwidth: [
      type: {:custom, __MODULE__, :validate_binwidth, []},
      doc:
        "How wide each bin is, a number above 0 in the axis's transformed units, which takes " <>
          "the place of `bins:`."
    ],
    center: [
      type: {:or, [:integer, :float]},
      doc: "Where one bin's middle falls, which places them all; not with `boundary:`."
    ],
    boundary: [
      type: {:or, [:integer, :float]},
      doc:
        "Where two bins meet, which places them all; not with `center:`. Without either, the " <>
          "outermost bins are centred on the axis's limits, or bins `binwidth:` wide meet half " <>
          "a width from 0."
    ],
    breaks: [
      type: {:custom, __MODULE__, :validate_bin_breaks, []},
      doc:
        "Where the bins meet, a list of two or more distinct numbers in the data's units, put " <>
          "through the axis's transformation, which takes the place of `bins:`, `binwidth:`, " <>
          "`center:` and `boundary:`; a row outside them is not counted."
    ],
    closed: [
      type: {:in, [:right, :left]},
      default: :right,
      doc:
        "Which end of a bin a value on its edge belongs to: the right end (`:right`), or the " <>
          "left (`:left`); the outermost bins hold their outer ends too."
    ],
    pad: [
      type: :boolean,
      default: false,
      doc: "Whether to add a bin of no rows at each end."
    ],
    drop: [
      type: {:in, [:none, :all, :extremes]},
      default: :none,
      doc:
        "Which bins of no rows to leave out: none (`:none`), every one (`:all`), or those " <>
          "before the first bin with rows and after the last (`:extremes`)."
    ],
    orientation: @runs_along_option
  ]

  # `geom_histogram/3`'s and `stat_bin/3`'s options, validated at the call: how the axis is cut
  # into bins, and a bar's.
  @bin_options NimbleOptions.new!(
                 [
                   data: @data_option,
                   position: [
                     type: {:custom, __MODULE__, :validate_bar_position, []},
                     default: :stack,
                     doc:
                       "How bars that share a bin are placed: piled on one another " <>
                         "(`:stack`), set side by side within the bin's width (`:dodge`), or " <>
                         "set side by side, each its share of the bin's width, with a gap " <>
                         "between them (`:dodge2`, or as `position_dodge2/1` says)."
                   ]
                 ] ++ @binning_options ++ @bar_look_options
               )

  # `geom_path/3`'s options, validated at the call.
  @path_options NimbleOptions.new!(
                  [
                    data: @data_option,
                    alpha: @alpha_option,
                    color: @line_color_option,
                    linewidth: @linewidth_option,
                    linetype: @linetype_option
                  ] ++ @line_style_options
                )

  # Which position a line's rows are put in order of, ggplot2's `orientation`.
  @orientation_option [
    type: {:in, [:x, :y]},
    default: :x,
    doc:
      "Which position the rows are put in order of: `x`, or `y` for a line that runs up the " <>
        "panel."
  ]

  # `geom_line/3`'s options, validated at the call.
  @line_options NimbleOptions.new!(
                  [
                    data: @data_option,
                    orientation: @orientation_option,
                    alpha: @alpha_option,
                    color: @line_color_option,
                    linewidth: @linewidth_option,
                    linetype: @linetype_option
                  ] ++ @line_style_options
                )

  # How a frequency polygon cuts its axis into bins: binning's options but `pad`, which a frequency
  # polygon always takes.
  @freqpoly_binning_options Keyword.delete(@binning_options, :pad)

  # `geom_freqpoly/3`'s options, validated at the call: how the axis is cut into bins, and a path's.
  @freqpoly_options NimbleOptions.new!(
                      [data: @data_option] ++
                        @freqpoly_binning_options ++
                        [
                          alpha: @alpha_option,
                          color: @line_color_option,
                          linewidth: @linewidth_option,
                          linetype: @linetype_option
                        ] ++ @line_style_options
                    )

  # A box plot's parts drawn as lines, each with a look of its own, and how its options' docs name
  # each.
  @boxplot_line_parts [
    whisker: "whiskers",
    staple: "staples",
    median: "median",
    box: "box's border"
  ]

  # The look of each line part, ggplot2's `whisker.colour` and the rest, R's dotted names
  # underscored.
  @boxplot_line_look_options Enum.flat_map(@boxplot_line_parts, fn {part, named} ->
                               [
                                 {:"#{part}_color",
                                  [
                                    type: @color_type,
                                    doc:
                                      "The colour of the #{named}, written `#{part}_colour:` " <>
                                        "or `#{part}_color:`: " <>
                                        @color_forms <> "; the box's colour when not given."
                                  ]},
                                 {:"#{part}_linetype",
                                  [
                                    type: @linetype_type,
                                    doc:
                                      "The line type of the #{named}: " <>
                                        @linetype_forms <> "; the box's when not given."
                                  ]},
                                 {:"#{part}_linewidth",
                                  [
                                    type: {:custom, __MODULE__, :validate_linewidth, []},
                                    doc:
                                      "How wide the #{named} is drawn, in millimetres; the " <>
                                        "box's line width when not given" <>
                                        if(part == :median, do: ", doubled.", else: ".")
                                  ]}
                               ]
                             end)

  # Each option giving a part of a box its look, by the part and the look it gives, which the box
  # geom holds by part.
  @boxplot_part_looks [
                        outlier_color: {:outlier, :color},
                        outlier_fill: {:outlier, :fill},
                        outlier_shape: {:outlier, :shape},
                        outlier_size: {:outlier, :size},
                        outlier_stroke: {:outlier, :stroke},
                        outlier_alpha: {:outlier, :alpha}
                      ] ++
                        for(
                          {part, _named} <- @boxplot_line_parts,
                          look <- [:color, :linetype, :linewidth],
                          do: {:"#{part}_#{look}", {part, look}}
                        )

  # `geom_boxplot/3`'s options, validated at the call: the box plot's summary's, how its boxes are
  # placed and drawn, and the look of every box and of each of its parts.
  @boxplot_options NimbleOptions.new!(
                     [
                       data: @data_option,
                       position: [
                         type: {:custom, __MODULE__, :validate_boxplot_position, []},
                         default: :dodge2,
                         doc:
                           "How boxes that share a position are placed: set side by side, " <>
                             "each its share of their widths, with a gap between them " <>
                             "(`:dodge2`, or as `position_dodge2/1` says), or within the width " <>
                             "one box takes (`:dodge`). With `varwidth: true`, every box keeps " <>
                             "its own width, as `position_dodge2(preserve: :single)` sets them, " <>
                             "whatever this says."
                       ],
                       coef: [
                         type: {:custom, __MODULE__, :validate_number, []},
                         default: 1.5,
                         doc:
                           "How far the whiskers may reach past the box, in heights of the " <>
                             "box; a value further out is an outlier."
                       ],
                       width: [
                         type: {:custom, __MODULE__, :validate_width, []},
                         doc:
                           "How wide a box is, in the units of the axis it stands on, any " <>
                             "number; it replaces a mapped `:width`, and gives way to 0.9 of " <>
                             "the range of a group spanning several positions. 0.75 times the " <>
                             "closest spacing of the positions, counting from zero, when not " <>
                             "given."
                       ],
                       orientation: [
                         type: {:in, [:x, :y]},
                         doc:
                           "The axis the boxes stand along, `:x` or `:y`, summarising the " <>
                             "other. Where one of `:x` and `:y` is mapped, the boxes summarise " <>
                             "it, so this must name the other; where both are, it chooses, and " <>
                             "when not given the boxes stand along the discrete one, or else " <>
                             "along the axis on which every group holds one value, or else " <>
                             "along x."
                       ],
                       outliers: [
                         type: :boolean,
                         default: true,
                         doc:
                           "Whether to keep the outliers, drawing them and fitting the axes " <>
                             "to them; `false` leaves them out, the axes fitting the whiskers. " <>
                             "`outlier_shape: :none` hides them and keeps the axes."
                       ],
                       outlier_color: [
                         type: @color_type,
                         doc:
                           "The outliers' colour, written `outlier_colour:` or " <>
                             "`outlier_color:`: " <> @color_forms <> "; the box's when not given."
                       ],
                       outlier_fill: [
                         type: @color_type,
                         doc:
                           "The colour outliers of a shape with a fill of their own are filled " <>
                             "with: " <> @color_forms <> "; the box's fill when not given."
                       ],
                       outlier_shape: [
                         type: {:custom, __MODULE__, :validate_shape, []},
                         doc:
                           "The shape the outliers are drawn in, by name or number, as " <>
                             "`geom_point/3` takes one, or `:none` for none; the box's `:shape`, " <>
                             "or `:circle`, when not given."
                       ],
                       outlier_size: [
                         type: {:custom, __MODULE__, :validate_size, []},
                         doc:
                           "How big the outliers are, in millimetres; the box's `:size`, or " <>
                             "1.5, when not given."
                       ],
                       outlier_stroke: [
                         type: {:custom, __MODULE__, :validate_stroke, []},
                         default: 0.5,
                         doc:
                           "How heavy the outliers' outlines are, in millimetres, or `:none` " <>
                             "for none."
                       ],
                       outlier_alpha: [
                         type: {:custom, __MODULE__, :validate_alpha, []},
                         doc:
                           "How opaque the outliers are, from 0 to 1; the box's alpha when not " <>
                             "given."
                       ]
                     ] ++
                       @boxplot_line_look_options ++
                       [
                         notch: [
                           type: :boolean,
                           default: false,
                           doc:
                             "Whether to notch each box at its median, the notches reaching " <>
                               "1.58 heights of the box over the square root of its rows either " <>
                               "side, so boxes whose notches do not overlap have medians that " <>
                               "differ."
                         ],
                         notchwidth: [
                           type: {:custom, __MODULE__, :validate_number, []},
                           default: 0.5,
                           doc: "How wide a notched box is at its median, a share of its width."
                         ],
                         staplewidth: [
                           type: {:custom, __MODULE__, :validate_number, []},
                           default: 0.0,
                           doc:
                             "How wide the staples across the whiskers' ends are, a share of " <>
                               "the box's width; 0 draws none."
                         ],
                         varwidth: [
                           type: :boolean,
                           default: false,
                           doc:
                             "Whether to draw each box as wide as the square root of its rows " <>
                               "makes it beside the widest."
                         ],
                         alpha: [
                           type: {:custom, __MODULE__, :validate_alpha, []},
                           doc:
                             "How opaque every box's fill and outliers are, from 0 to 1; its " <>
                               "lines take none."
                         ],
                         color: [
                           type: @color_type,
                           doc:
                             "The colour of every box's lines and outliers, written `colour:` " <>
                               "or `color:`: " <> @color_forms <> "; `#333333` when not given."
                         ],
                         fill: [
                           type: @color_type,
                           doc:
                             "The colour every box is filled with: " <>
                               @color_forms <> "; white when not given."
                         ],
                         linewidth: [
                           type: {:custom, __MODULE__, :validate_linewidth, []},
                           doc:
                             "How wide every box's lines are, in millimetres; 0.5 when not given."
                         ],
                         linetype: [
                           type: @linetype_type,
                           doc:
                             "The line type of every box's lines: " <>
                               @linetype_forms <> "; `:solid` when not given."
                         ],
                         shape: [
                           type: {:custom, __MODULE__, :validate_shape, []},
                           doc:
                             "The shape every box's outliers are drawn in, as `outlier_shape:` " <>
                               "takes one, which wins over it."
                         ],
                         size: [
                           type: {:custom, __MODULE__, :validate_size, []},
                           doc:
                             "How big every box's outliers are, in millimetres, as " <>
                               "`outlier_size:` takes it, which wins over it."
                         ]
                       ]
                   )

  # Whether text leaves out the labels that would cross one drawn before it.
  @check_overlap_option [
    type: :boolean,
    default: false,
    doc:
      "Whether to leave out each label that would cross one drawn before it, the rows taken " <>
        "in order."
  ]

  # How every label of a layer is drawn, each set once for the layer.
  @text_style_options [
    size: [
      type: {:custom, __MODULE__, :validate_size, []},
      doc:
        "How big every label is, in millimetres, each 2.85 points; 11 points, the theme's " <>
          "base size, when not given."
    ],
    angle: [
      type: {:custom, __MODULE__, :validate_angle, []},
      doc: "How far every label is turned, in degrees anticlockwise; 0 when not given."
    ],
    hjust: [
      type: {:custom, __MODULE__, :validate_justification, []},
      doc:
        "Where along its baseline every label is anchored on its place, 0 its start and 1 " <>
          "its end: " <> @justification_forms <> "; 0.5 when not given."
    ],
    vjust: [
      type: {:custom, __MODULE__, :validate_justification, []},
      doc:
        "Where up its height every label is anchored on its place, 0 its baseline and 1 " <>
          "the top of a capital letter: " <> @justification_forms <> "; 0.5 when not given."
    ],
    family: [
      type: :string,
      doc:
        "The font every label is drawn in, by name, such as `\"Times New Roman\"`; the " <>
          "default sans-serif when not given. A label is measured as the default font " <>
          "measures it, and drawn at that width."
    ]
  ]

  # `geom_text/3`'s options, validated at the call.
  @text_options NimbleOptions.new!(
                  [
                    data: @data_option,
                    check_overlap: @check_overlap_option,
                    alpha: @alpha_option,
                    color: @text_color_option
                  ] ++
                    @text_style_options ++
                    [
                      nudge_x: [
                        type: {:custom, __MODULE__, :validate_nudge, []},
                        doc:
                          "How far every label moves along x from its place, in the units of the " <>
                            "x axis; 0 when not given."
                      ],
                      nudge_y: [
                        type: {:custom, __MODULE__, :validate_nudge, []},
                        doc:
                          "How far every label moves along y from its place, in the units of the " <>
                            "y axis; 0 when not given."
                      ]
                    ]
                )

  @rect_color_option [
    type: @color_type,
    doc:
      "The colour of every rectangle's border, written `colour:` or `color:`: " <>
        @color_forms <>
        "; no border when not given. A border takes no alpha but its colour's own."
  ]

  @rect_fill_option [
    type: @color_type,
    doc:
      "The colour every rectangle is filled with: " <>
        @color_forms <> "; `#595959` when not given."
  ]

  @rect_linewidth_option [
    type: {:custom, __MODULE__, :validate_linewidth, []},
    doc: "How wide every rectangle's border is, in millimetres; 0.5 when not given."
  ]

  @rect_linetype_option [
    type: @linetype_type,
    doc:
      "The line type of every rectangle's border: " <>
        @linetype_forms <> "; `:solid` when not given."
  ]

  # A rectangle's corner set for every rectangle of a layer, as ggplot2's `xmin = 3` sets it.
  @corner_type {:custom, __MODULE__, :validate_corner, []}

  # `geom_rect/3`'s options, validated at the call.
  @rect_options NimbleOptions.new!(
                  data: @data_option,
                  alpha: @alpha_option,
                  color: @rect_color_option,
                  fill: @rect_fill_option,
                  linewidth: @rect_linewidth_option,
                  linetype: @rect_linetype_option,
                  xmin: [
                    type: @corner_type,
                    doc:
                      "Every rectangle's `xmin`, in the units of the x axis: a number, or " <>
                        "`:infinity` or `:neg_infinity`, which reach the panel's edge."
                  ],
                  xmax: [
                    type: @corner_type,
                    doc: "Every rectangle's `xmax`, as `xmin:` sets one."
                  ],
                  ymin: [
                    type: @corner_type,
                    doc:
                      "Every rectangle's `ymin`, in the units of the y axis, as `xmin:` sets " <>
                        "an `xmin`."
                  ],
                  ymax: [
                    type: @corner_type,
                    doc: "Every rectangle's `ymax`, as `ymin:` sets one."
                  ]
                )

  # An annotation's position, a value or a list of values, one per annotation, as ggplot2's
  # `annotate()` takes a vector.
  @annotation_position [
    type: {:custom, __MODULE__, :validate_per_annotation, [:validate_annotation_position]}
  ]

  # The aesthetics an annotation's geom draws row by row, as a mapped one, which may each be given a
  # list, one value per annotation, every value checked as a layer function checks the one it sets.
  @annotation_alpha [type: {:custom, __MODULE__, :validate_per_annotation, [:validate_alpha]}]
  @annotation_color [type: {:custom, __MODULE__, :validate_per_annotation, [:validate_color]}]
  @annotation_label [
    type: {:custom, __MODULE__, :validate_per_annotation, [:validate_annotation_label]}
  ]
  @annotation_shape [type: {:custom, __MODULE__, :validate_per_annotation, [:validate_shape]}]
  @annotation_size [type: {:custom, __MODULE__, :validate_per_annotation, [:validate_size]}]
  @annotation_stroke [
    type: {:custom, __MODULE__, :validate_per_annotation, [:validate_stroke]}
  ]
  @annotation_linewidth [
    type: {:custom, __MODULE__, :validate_per_annotation, [:validate_linewidth]}
  ]
  @annotation_linetype [
    type: {:custom, __MODULE__, :validate_per_annotation, [:validate_linetype]}
  ]
  @annotation_width [type: {:custom, __MODULE__, :validate_per_annotation, [:validate_width]}]
  @per_annotation_aesthetics [
    :alpha,
    :color,
    :fill,
    :label,
    :linetype,
    :linewidth,
    :shape,
    :size,
    :stroke,
    :width
  ]

  # `annotate/3`'s options for each geom it draws with, validated at the call: the positions the
  # geom draws at and the options its function takes but `data:` and `position:`, and nudging, which
  # ggplot2's annotations ignore.
  @point_annotation [
    x: @annotation_position,
    y: @annotation_position,
    alpha: @annotation_alpha,
    color: @annotation_color,
    fill: @annotation_color,
    shape: @annotation_shape,
    size: @annotation_size,
    stroke: @annotation_stroke
  ]
  @bar_annotation [
    x: @annotation_position,
    y: @annotation_position,
    alpha: @annotation_alpha,
    color: @annotation_color,
    fill: @annotation_color,
    linewidth: @annotation_linewidth,
    linetype: @annotation_linetype,
    width: @annotation_width,
    just: @bar_just_option
  ]
  @path_annotation [
                     x: @annotation_position,
                     y: @annotation_position,
                     alpha: @annotation_alpha,
                     color: @annotation_color,
                     linewidth: @annotation_linewidth,
                     linetype: @linetype_option
                   ] ++ @line_style_options
  @annotation_geoms [:point, :col, :bar, :path, :line, :text, :rect]
  @annotation_options %{
    point: NimbleOptions.new!(@point_annotation),
    col: NimbleOptions.new!(@bar_annotation),
    bar: NimbleOptions.new!(@bar_annotation),
    path: NimbleOptions.new!(@path_annotation),
    line: NimbleOptions.new!([orientation: @orientation_option] ++ @path_annotation),
    text:
      NimbleOptions.new!(
        [
          x: @annotation_position,
          y: @annotation_position,
          label: @annotation_label,
          check_overlap: @check_overlap_option,
          alpha: @annotation_alpha,
          color: @annotation_color
        ] ++ @text_style_options
      ),
    rect:
      NimbleOptions.new!(
        xmin: @annotation_position,
        xmax: @annotation_position,
        ymin: @annotation_position,
        ymax: @annotation_position,
        alpha: @annotation_alpha,
        color: @annotation_color,
        fill: @annotation_color,
        linewidth: @annotation_linewidth,
        linetype: @annotation_linetype
      )
  }

  # A continuous scale's limits, as `limits:`, `xlim/3`, `ylim/3` and `lims/2` take them.
  @limits_type {:custom, __MODULE__, :validate_limits, []}

  # Every scale function's `name:`.
  @scale_name_spec [
    type: {:custom, __MODULE__, :validate_label, []},
    doc: "The axis's title, or `:none` for none; the title its mapping gives when not given."
  ]

  # Every scale function's `expand:`, its default the scale's.
  @scale_expand_type {:custom, __MODULE__, :validate_expand, []}

  # The continuous scale functions' options, validated at the call; an option not given keeps the
  # scale's default, `Giggly.Scale.Continuous`'s. A transformed scale's function takes them all but
  # `transform:`, which it sets.
  @scale_option_specs [
    name: @scale_name_spec,
    limits: [
      type: @limits_type,
      doc:
        "`{low, high}`: the values the axis spans whatever the " <>
          "data, in data units, `nil` for an end the data decides; " <>
          "either order names the same axis. A value outside them is " <>
          "missing, so its mark is not drawn."
    ],
    breaks: [
      type: {:custom, __MODULE__, :validate_breaks, []},
      doc:
        "The values the axis marks with a tick, a label and a grid " <>
          "line, a list of numbers in data units, or `:none` for " <>
          "none; chosen from the limits when not given. A break is " <>
          "drawn wherever it falls inside the widened axis."
    ],
    minor_breaks: [
      type: {:custom, __MODULE__, :validate_breaks, []},
      doc:
        "The values the panel draws a minor grid line at, a list of " <>
          "numbers in data units, or `:none` for none; midway " <>
          "between the breaks, once transformed, when not given."
    ],
    labels: [
      type: {:custom, __MODULE__, :validate_scale_labels, []},
      doc:
        "The breaks' labels: a list of strings, one for each of " <>
          "`breaks:`; a function handed every break drawn, a list of " <>
          "numbers in data units, that returns a string for each, as " <>
          "`Giggly.Format`'s do; or `:none` for ticks with no labels."
    ],
    expand: [
      type: @scale_expand_type,
      doc:
        "How far the axis reaches beyond its limits, `[mult: m, add: " <>
          "a]`: at each end, that multiple of the limits' width plus " <>
          "that constant, each a number or `{low, high}` for the two " <>
          "ends; `[mult: 0.05]` when not given."
    ]
  ]

  @continuous_scale_options @scale_option_specs
                            |> Enum.concat(
                              transform: [
                                type: {:in, [:identity, :log10, :sqrt, :reverse, :reciprocal]},
                                doc:
                                  "What each value is put through before it is placed: " <>
                                    "`:identity`, the value itself; `:log10`, its base-10 " <>
                                    "logarithm; `:sqrt`, its square root; `:reverse`, so the " <>
                                    "axis runs from high to low; or `:reciprocal`, one over " <>
                                    "it. `:identity` when not given. The axis is marked and " <>
                                    "labelled in data units, and widened in transformed space."
                              ]
                            )
                            |> NimbleOptions.new!()

  @transformed_scale_options NimbleOptions.new!(@scale_option_specs)

  # The discrete scale functions' options; an option not given keeps the scale's default,
  # `Giggly.Scale.Discrete`'s.
  @discrete_scale_options NimbleOptions.new!(
                            name: @scale_name_spec,
                            limits: [
                              type: {:custom, __MODULE__, :validate_discrete_limits, []},
                              doc:
                                "The values the axis shows, a list in the order shown, " <>
                                  "whatever the data; each value as the column holds it, " <>
                                  "`nil` for the missing value, a number naming the value " <>
                                  "equal to it. A value not among them is missing, so its " <>
                                  "mark is not drawn; one the data lacks leaves its place " <>
                                  "empty. Every value the data holds, in order, when not given."
                            ],
                            breaks: [
                              type: {:custom, __MODULE__, :validate_discrete_breaks, []},
                              doc:
                                "The values the axis marks with a tick and a label, a list " <>
                                  "in the order given, those not among the limits left out, " <>
                                  "or `:none` for none; every one of the limits when not given."
                            ],
                            labels: [
                              type: {:custom, __MODULE__, :validate_discrete_labels, []},
                              doc:
                                "The breaks' labels: a list of strings, one for each break, " <>
                                  "or for each limit when no breaks are given; a map from a " <>
                                  "value to its label, a value it does not hold keeping its " <>
                                  "own; a function handed every break drawn, a list of " <>
                                  "values, that returns a string for each; or `:none` for " <>
                                  "ticks with no labels. Each value written as text when not " <>
                                  "given."
                            ],
                            expand: [
                              type: @scale_expand_type,
                              doc:
                                "How far the axis reaches beyond its first and last values, " <>
                                  "`[mult: m, add: a]`: at each end, that multiple of the " <>
                                  "distance between them plus that constant, each a number " <>
                                  "or `{low, high}` for the two ends; `[add: 0.6]` when not " <>
                                  "given."
                            ]
                          )

  # The date scale functions' options; an option not given keeps a date scale's default. A
  # `date_` option and its plain twin choose the same thing, so only one may be given.
  @date_step_type {:custom, __MODULE__, :validate_date_step, []}
  @date_scale_options NimbleOptions.new!(
                        name: @scale_name_spec,
                        limits: [
                          type: {:custom, __MODULE__, :validate_date_limits, []},
                          doc:
                            "`{low, high}`: the dates the axis spans whatever the data, `nil` " <>
                              "for an end the data decides; either order names the same axis. " <>
                              "A value outside them is missing, so its mark is not drawn."
                        ],
                        breaks: [
                          type: {:custom, __MODULE__, :validate_dates, []},
                          doc:
                            "The dates the axis marks with a tick, a label and a grid line, a " <>
                              "list, or `:none` for none; chosen from the limits when neither " <>
                              "this nor `date_breaks:` is given. A break is drawn wherever it " <>
                              "falls inside the widened axis."
                        ],
                        date_breaks: [
                          type: @date_step_type,
                          doc:
                            "A break every step, `[week: 1]`: one of `:day`, `:week`, `:month` " <>
                              "and `:year` and how many of it, laid from the widened axis's " <>
                              "start, rounded down to a multiple of the days since 1970-01-01, " <>
                              "a Monday, the 1st of a month or 1 January, to its end. Not with " <>
                              "`breaks:`."
                        ],
                        labels: [
                          type: {:custom, __MODULE__, :validate_scale_labels, []},
                          doc:
                            "The breaks' labels: a list of strings, one for each of " <>
                              "`breaks:`; a function handed every break drawn, a list of " <>
                              "dates, that returns a string for each; or `:none` for ticks " <>
                              "with no labels. Not with `date_labels:`. When neither is given, " <>
                              "the breaks the axis chooses are written as suits their step " <>
                              "(`Sep 21`, `2026`) and others in full (`2026-09-21`)."
                        ],
                        date_labels: [
                          type: {:custom, __MODULE__, :validate_date_format, []},
                          doc:
                            "The format every break's label is written in, as " <>
                              "`Calendar.strftime/3` takes it, such as `\"%b %d\"`. Not with " <>
                              "`labels:`."
                        ],
                        minor_breaks: [
                          type: {:custom, __MODULE__, :validate_dates, []},
                          doc:
                            "The dates the panel draws a minor grid line at, a list, or " <>
                              "`:none` for none; midway between the breaks when neither this " <>
                              "nor `date_minor_breaks:` is given."
                        ],
                        date_minor_breaks: [
                          type: @date_step_type,
                          doc:
                            "A minor grid line every step, as `date_breaks:` lays breaks. Not " <>
                              "with `minor_breaks:`."
                        ],
                        expand: [
                          type: @scale_expand_type,
                          doc:
                            "How far the axis reaches beyond its limits, `[mult: m, add: a]`: " <>
                              "at each end, that multiple of the limits' width plus that " <>
                              "constant, each a number or `{low, high}` for the two ends; " <>
                              "`[mult: 0.05]` when not given."
                        ]
                      )

  # A date scale's options that choose what their plain twins choose.
  @date_twins [breaks: :date_breaks, labels: :date_labels, minor_breaks: :date_minor_breaks]

  # The options of every scale function of an aesthetic other than position, whose guide is a
  # legend or a colour bar; an option not given keeps the scale's default.
  @legend_name_spec [
    type: {:custom, __MODULE__, :validate_label, []},
    doc:
      "The legend's or colour bar's title, or `:none` for none; the title its mapping gives " <>
        "when not given."
  ]

  @discrete_legend_option_specs [
    name: @legend_name_spec,
    limits: [
      type: {:custom, __MODULE__, :validate_discrete_limits, []},
      doc:
        "The values the scale shows, a list in the order shown, whatever the data; each value " <>
          "as the column holds it, `nil` for the missing value, a number naming the value equal " <>
          "to it. A value not among them takes `na_value:`. Every value the data holds, in " <>
          "order, when not given."
    ],
    breaks: [
      type: {:custom, __MODULE__, :validate_discrete_breaks, []},
      doc:
        "The values the legend shows a key for, a list in the order given, those not among " <>
          "the limits left out, or `:none` for no legend; every one of the limits when not given."
    ],
    labels: [
      type: {:custom, __MODULE__, :validate_discrete_labels, []},
      doc:
        "The keys' labels: a list of strings, one for each break, or for each limit when no " <>
          "breaks are given; a map from a value to its label, a value it does not hold keeping " <>
          "its own; a function handed every break, a list of values, that returns a string for " <>
          "each; or `:none` for keys with no labels. Each value written as text when not given."
    ]
  ]

  @continuous_legend_option_specs [
    name: @legend_name_spec,
    limits: [
      type: @limits_type,
      doc:
        "`{low, high}`: the values the scale spans whatever the data, `nil` for an end the " <>
          "data decides; either order names the same scale. A value outside them takes " <>
          "`na_value:`."
    ],
    breaks: [
      type: {:custom, __MODULE__, :validate_breaks, []},
      doc:
        "The values the legend or colour bar marks, a list of numbers, those outside the " <>
          "limits left out, or `:none` for no guide; chosen from the limits when not given."
    ],
    labels: [
      type: {:custom, __MODULE__, :validate_scale_labels, []},
      doc:
        "The breaks' labels: a list of strings, one for each of `breaks:`; a function handed " <>
          "every break, a list of numbers, that returns a string for each, as `Giggly.Format`'s " <>
          "do; or `:none` for no labels."
    ]
  ]

  # A scale's `guide:`, the guide that reads it back, checked by `validate_guide/2` for the kind of
  # scale it reads: a colour bar for a continuous colour or fill scale alone. Each default is the
  # one the scale gets with no scale function, a deliberate default recorded as a value.
  @guide_doc_tail "or a legend `guide_legend/1` makes, or `:none` for none; `guides/2` sets one " <>
                    "over it."

  @discrete_color_guide_spec [
    type: {:custom, __MODULE__, :validate_guide, [:discrete]},
    default: :legend,
    doc: "What reads the scale back: `:legend`, a key for each break, " <> @guide_doc_tail
  ]

  @continuous_color_guide_spec [
    type: {:custom, __MODULE__, :validate_guide, [:continuous]},
    default: :colorbar,
    doc:
      "What reads the scale back: `:colorbar`, a bar the colours run up; `:legend`, a key for " <>
        "each break; " <> @guide_doc_tail
  ]

  @alpha_guide_spec [
    type: {:custom, __MODULE__, :validate_guide, [:alpha]},
    default: :legend,
    doc: "What reads the scale back: `:legend`, a key for each break, " <> @guide_doc_tail
  ]

  @discrete_color_legend_option_specs Enum.concat(
                                        @discrete_legend_option_specs,
                                        guide: @discrete_color_guide_spec
                                      )
  @continuous_color_legend_option_specs Enum.concat(
                                          @continuous_legend_option_specs,
                                          guide: @continuous_color_guide_spec
                                        )

  # A colour scale's missing value, grey unless a function says otherwise.
  @color_na_value_doc "The colour of a missing value, or of one outside the limits, or `:none` for none, which draws nothing."
  @color_na_value_type {:custom, __MODULE__, :validate_color, []}
  @color_na_value_spec [type: @color_na_value_type, default: "#7F7F7F", doc: @color_na_value_doc]

  # The hue palette's defaults, which a discrete colour scale takes when given no palette: hues from
  # 15 degrees round the circle, chroma 100 and luminance 65, handed out in order.
  @hue_defaults [hue: {15.0, 375.0}, chroma: 100.0, luminance: 65.0, direction: 1]

  # The default gradient's ends, which a continuous colour scale takes when given no palette.
  @gradient_defaults [low: "#132B43", high: "#56B1F7"]

  # The viridis palettes' defaults, R's `viridis()`'s, which an ordered factor's colour and fill
  # scales take: the palette `:viridis` from its start to its end, opaque.
  @viridis_defaults [option: :viridis, begin: 0.0, end: 1.0, direction: 1, alpha: 1.0]

  # How many colours of a viridis palette a continuous scale's gradient runs through, as ggplot2's
  # `scale_colour_viridis_c()` takes `pal_viridis()(6)`.
  @viridis_gradient_colors 6

  # An alpha scale's default range, which leaves every value visible.
  @alpha_range_default {0.1, 1.0}

  @opaque_color_type {:custom, __MODULE__, :validate_opaque_color, []}

  @manual_scale_options NimbleOptions.new!(
                          [
                            values: [
                              type: {:custom, __MODULE__, :validate_manual_values, [:color]},
                              required: true,
                              doc:
                                "The colours: a list, given to the values in order, or to " <>
                                  "`breaks:` in order where they are a list; or a map from a " <>
                                  "value, as the column holds it, to its colour, whose scale " <>
                                  "shows only the values the data holds that it names, unless " <>
                                  "`limits:` gives others. A value with no colour takes " <>
                                  "`na_value:`."
                            ],
                            na_value: @color_na_value_spec
                          ] ++ @discrete_color_legend_option_specs
                        )

  @hue_scale_options NimbleOptions.new!(
                       [
                         hue: [
                           type: {:custom, __MODULE__, :validate_number_pair, []},
                           default: @hue_defaults[:hue],
                           doc:
                             "`{first, last}`: the hues the colours are spaced between, in " <>
                               "degrees round the colour wheel. A range spanning the whole " <>
                               "circle leaves its last share off, so the first and last colours " <>
                               "differ."
                         ],
                         chroma: [
                           type: {:custom, __MODULE__, :validate_number, []},
                           default: @hue_defaults[:chroma],
                           doc: "How vivid the colours are, from 0, grey."
                         ],
                         luminance: [
                           type: {:custom, __MODULE__, :validate_number, []},
                           default: @hue_defaults[:luminance],
                           doc: "How light the colours are, from 0, black, to 100, white."
                         ],
                         direction: [
                           type: {:in, [1, -1]},
                           default: @hue_defaults[:direction],
                           doc: "1 to give the colours to the values in order, -1 in reverse."
                         ],
                         na_value: @color_na_value_spec
                       ] ++ @discrete_color_legend_option_specs
                     )

  @gray_scale_options NimbleOptions.new!(
                        [
                          start: [
                            type: {:custom, __MODULE__, :validate_gray_level, []},
                            default: 0.2,
                            doc: "The first value's grey, from 0, black, to 1, white."
                          ],
                          end: [
                            type: {:custom, __MODULE__, :validate_gray_level, []},
                            default: 0.8,
                            doc: "The last value's grey, from 0, black, to 1, white."
                          ],
                          na_value: Keyword.put(@color_na_value_spec, :default, "#FF0000")
                        ] ++ @discrete_color_legend_option_specs
                      )

  # The options every viridis scale takes: the palette, and where in it and which way round its
  # colours are taken.
  @viridis_option_specs [
    option: [
      type: {:in, ColorOperations.viridis_options()},
      default: @viridis_defaults[:option],
      doc:
        "The palette: `:viridis`, `:magma`, `:inferno`, `:plasma`, `:cividis`, `:rocket`, " <>
          "`:mako` or `:turbo`."
    ],
    begin: [
      type: {:custom, __MODULE__, :validate_palette_place, []},
      default: @viridis_defaults[:begin],
      doc: "Where in the palette the colours begin, from 0, its start, to 1, its end."
    ],
    end: [
      type: {:custom, __MODULE__, :validate_palette_place, []},
      default: @viridis_defaults[:end],
      doc: "Where in the palette the colours end, from 0, its start, to 1, its end."
    ],
    direction: [
      type: {:in, [1, -1]},
      default: @viridis_defaults[:direction],
      doc: "1 to take the colours from `begin:` to `end:`, -1 from `end:` to `begin:`."
    ]
  ]

  @discrete_viridis_scale_options NimbleOptions.new!(
                                    @viridis_option_specs ++
                                      [
                                        alpha: [
                                          type: {:custom, __MODULE__, :validate_alpha, []},
                                          default: @viridis_defaults[:alpha],
                                          doc: "The colours' opacity, from 0 to 1."
                                        ],
                                        na_value:
                                          Keyword.put(@color_na_value_spec, :default, :none)
                                      ] ++ @discrete_color_legend_option_specs
                                  )

  @continuous_viridis_scale_options NimbleOptions.new!(
                                      @viridis_option_specs ++
                                        [na_value: @color_na_value_spec] ++
                                        @continuous_color_legend_option_specs
                                    )

  @discrete_color_scale_options NimbleOptions.new!(
                                  [
                                    palette: [
                                      type: {:custom, __MODULE__, :validate_palette_colors, []},
                                      doc:
                                        "A list of colours, given to the values in order; " <>
                                          "hues spaced evenly round the colour wheel when not " <>
                                          "given."
                                    ],
                                    na_value: @color_na_value_spec
                                  ] ++ @discrete_color_legend_option_specs
                                )

  @gradient_scale_options NimbleOptions.new!(
                            [
                              low: [
                                type: @opaque_color_type,
                                default: @gradient_defaults[:low],
                                doc: "The colour at the low end of the limits."
                              ],
                              high: [
                                type: @opaque_color_type,
                                default: @gradient_defaults[:high],
                                doc: "The colour at the high end of the limits."
                              ],
                              na_value: @color_na_value_spec
                            ] ++ @continuous_color_legend_option_specs
                          )

  @gradient2_scale_options NimbleOptions.new!(
                             [
                               low: [
                                 type: @opaque_color_type,
                                 default: "#832424",
                                 doc:
                                   "The colour the low side runs to, a dark red when not given."
                               ],
                               mid: [
                                 type: @opaque_color_type,
                                 default: "#FFFFFF",
                                 doc: "The colour at the midpoint, white when not given."
                               ],
                               high: [
                                 type: @opaque_color_type,
                                 default: "#3A3A98",
                                 doc:
                                   "The colour the high side runs to, a dark blue when not given."
                               ],
                               midpoint: [
                                 type: {:custom, __MODULE__, :validate_number, []},
                                 default: 0.0,
                                 doc: "The value the middle colour stands at."
                               ],
                               na_value: @color_na_value_spec
                             ] ++ @continuous_color_legend_option_specs
                           )

  @gradientn_scale_options NimbleOptions.new!(
                             [
                               colors: [
                                 type: {:custom, __MODULE__, :validate_gradient_colors, []},
                                 required: true,
                                 doc:
                                   "The colours, a list, spaced evenly from the low end of the " <>
                                     "limits to the high."
                               ],
                               na_value: @color_na_value_spec
                             ] ++ @continuous_color_legend_option_specs
                           )

  @continuous_color_scale_options NimbleOptions.new!(
                                    [
                                      palette: [
                                        type:
                                          {:custom, __MODULE__, :validate_gradient_colors, []},
                                        doc:
                                          "A list of colours, spaced evenly from the low end " <>
                                            "of the limits to the high; a gradient from " <>
                                            "`#132B43` to `#56B1F7` when not given."
                                      ],
                                      na_value: @color_na_value_spec
                                    ] ++ @continuous_color_legend_option_specs
                                  )

  @alpha_range_spec [
    type: {:custom, __MODULE__, :validate_alpha_range, []},
    default: @alpha_range_default,
    doc: "`{low, high}`: the opacities the values run between, each from 0 to 1."
  ]

  @alpha_na_value_spec [
    type: {:custom, __MODULE__, :validate_alpha, []},
    doc:
      "The opacity of a missing value, or of one outside the limits, from 0 to 1; its " <>
        "colour's own when not given."
  ]

  @continuous_alpha_scale_options NimbleOptions.new!(
                                    [range: @alpha_range_spec, na_value: @alpha_na_value_spec] ++
                                      Enum.concat(
                                        @continuous_legend_option_specs,
                                        guide: @alpha_guide_spec
                                      )
                                  )

  @discrete_alpha_scale_options NimbleOptions.new!(
                                  [range: @alpha_range_spec, na_value: @alpha_na_value_spec] ++
                                    Enum.concat(
                                      @discrete_legend_option_specs,
                                      guide: @alpha_guide_spec
                                    )
                                )

  # A size scale's guide, a legend unless it says otherwise, and its missing value's size, none
  # unless it says otherwise, drawing no point.
  @size_guide_spec [
    type: {:custom, __MODULE__, :validate_guide, [:size]},
    default: :legend,
    doc: "What reads the scale back: `:legend`, a key for each break, " <> @guide_doc_tail
  ]

  @size_na_value_spec [
    type: {:custom, __MODULE__, :validate_size, []},
    doc:
      "The size, in millimetres, of a missing value, or of one outside the limits, 0 or more; " <>
        "none, which draws nothing, when not given."
  ]

  # The size scales' default ranges, in millimetres, which leave the smallest value visible.
  @continuous_size_range_default {1.0, 6.0}
  @discrete_size_range_default {2.0, 6.0}

  @size_range_type {:custom, __MODULE__, :validate_size_range, []}

  # The options of a continuous size scale that takes no missing value's size, as ggplot2's
  # `scale_size_continuous()` and `scale_radius()` take none: a value outside its limits is not
  # drawn.
  @continuous_size_legend_option_specs @continuous_legend_option_specs
                                       |> Keyword.replace!(:limits,
                                         type: @limits_type,
                                         doc:
                                           "`{low, high}`: the values the scale spans whatever " <>
                                             "the data, `nil` for an end the data decides; " <>
                                             "either order names the same scale. A value " <>
                                             "outside them is not drawn."
                                       )
                                       |> Enum.concat(guide: @size_guide_spec)

  @continuous_size_scale_options NimbleOptions.new!(
                                   [
                                     range: [
                                       type: @size_range_type,
                                       default: @continuous_size_range_default,
                                       doc:
                                         "`{low, high}`: the sizes, in millimetres, the values " <>
                                           "run between by area, each 0 or more."
                                     ]
                                   ] ++ @continuous_size_legend_option_specs
                                 )

  @radius_scale_options NimbleOptions.new!(
                          [
                            range: [
                              type: @size_range_type,
                              default: @continuous_size_range_default,
                              doc:
                                "`{low, high}`: the sizes, in millimetres, the values run " <>
                                  "between, each 0 or more."
                            ]
                          ] ++ @continuous_size_legend_option_specs
                        )

  @area_size_scale_options NimbleOptions.new!(
                             [
                               max_size: [
                                 type: {:custom, __MODULE__, :validate_size, []},
                                 default: 6.0,
                                 doc:
                                   "The size, in millimetres, of a value at the high end of " <>
                                     "the limits, 0 or more."
                               ],
                               na_value: @size_na_value_spec
                             ] ++
                               Enum.concat(
                                 @continuous_legend_option_specs,
                                 guide: @size_guide_spec
                               )
                           )

  @discrete_size_scale_options NimbleOptions.new!(
                                 [
                                   range: [
                                     type: @size_range_type,
                                     default: @discrete_size_range_default,
                                     doc:
                                       "`{first, last}`: the sizes, in millimetres, of the " <>
                                         "first and last values, each 0 or more."
                                   ],
                                   na_value: @size_na_value_spec
                                 ] ++
                                   Enum.concat(
                                     @discrete_legend_option_specs,
                                     guide: @size_guide_spec
                                   )
                               )

  # A shape scale's guide, a legend unless it says otherwise, and its missing value's shape, none
  # unless it says otherwise, drawing no point.
  @shape_guide_spec [
    type: {:custom, __MODULE__, :validate_guide, [:shape]},
    default: :legend,
    doc: "What reads the scale back: `:legend`, a key for each break, " <> @guide_doc_tail
  ]

  @shape_na_value_spec [
    type: {:custom, __MODULE__, :validate_shape, []},
    doc:
      "The shape of a missing value, or of one not among the limits, by name or by number, or " <>
        "`:none`; none, which draws no point, when not given."
  ]

  @shape_legend_option_specs Enum.concat(@discrete_legend_option_specs, guide: @shape_guide_spec)

  @discrete_shape_scale_options NimbleOptions.new!(
                                  [
                                    solid: [
                                      type: :boolean,
                                      default: true,
                                      doc:
                                        "Whether the shapes are solid, `:circle_small`, " <>
                                          "`:triangle`, `:square`, `:plus`, `:square_cross` " <>
                                          "and `:asterisk` in order, or, `false`, open, " <>
                                          "`:circle_open`, `:triangle_open`, `:square_open` and " <>
                                          "the last three."
                                    ],
                                    na_value: @shape_na_value_spec
                                  ] ++ @shape_legend_option_specs
                                )

  @manual_shape_scale_options NimbleOptions.new!(
                                [
                                  values: [
                                    type:
                                      {:custom, __MODULE__, :validate_manual_values, [:shape]},
                                    required: true,
                                    doc:
                                      "The shapes, each by name or by number, or `:none`: a " <>
                                        "list, given to the values in order, or to `breaks:` " <>
                                        "in order where they are a list; or a map from a " <>
                                        "value, as the column holds it, to its shape, whose " <>
                                        "scale shows only the values the data holds that it " <>
                                        "names, unless `limits:` gives others. A value with no " <>
                                        "shape takes `na_value:`."
                                  ],
                                  na_value: @shape_na_value_spec
                                ] ++ @shape_legend_option_specs
                              )

  # A line type scale's guide, a legend unless it says otherwise, and its missing value's line type,
  # none unless it says otherwise, drawing no line.
  @linetype_guide_spec [
    type: {:custom, __MODULE__, :validate_guide, [:linetype]},
    default: :legend,
    doc: "What reads the scale back: `:legend`, a key for each break, " <> @guide_doc_tail
  ]

  @linetype_na_value_spec [
    type: @linetype_type,
    doc:
      "The line type of a missing value, or of one not among the limits: " <>
        @linetype_forms <> "; none, which draws no line, when not given."
  ]

  @linetype_legend_option_specs Enum.concat(
                                  @discrete_legend_option_specs,
                                  guide: @linetype_guide_spec
                                )

  @discrete_linetype_scale_options NimbleOptions.new!(
                                     [na_value: @linetype_na_value_spec] ++
                                       @linetype_legend_option_specs
                                   )

  @manual_linetype_scale_options NimbleOptions.new!(
                                   [
                                     values: [
                                       type:
                                         {:custom, __MODULE__, :validate_manual_values,
                                          [:linetype]},
                                       required: true,
                                       doc:
                                         "The line types, each " <>
                                           @linetype_forms <>
                                           ": a list, given to the values in order, or to " <>
                                           "`breaks:` in order where they are a list; or a " <>
                                           "map from a value, as the column holds it, to its " <>
                                           "line type, whose scale shows only the values the " <>
                                           "data holds that it names, unless `limits:` gives " <>
                                           "others. A value with no line type takes `na_value:`."
                                     ],
                                     na_value: @linetype_na_value_spec
                                   ] ++ @linetype_legend_option_specs
                                 )

  # A line width scale's guide, a legend unless it says otherwise, and its missing value's width,
  # none unless it says otherwise, drawing no line.
  @linewidth_guide_spec [
    type: {:custom, __MODULE__, :validate_guide, [:linewidth]},
    default: :legend,
    doc: "What reads the scale back: `:legend`, a key for each break, " <> @guide_doc_tail
  ]

  # The line width scales' default ranges, in millimetres, which leave the narrowest line visible.
  @continuous_linewidth_range_default {1.0, 6.0}
  @discrete_linewidth_range_default {2.0, 6.0}

  @linewidth_range_type {:custom, __MODULE__, :validate_linewidth_range, []}

  # The options of a continuous line width scale, which takes no missing value's width, as
  # ggplot2's `scale_linewidth_continuous()` takes none: a value outside its limits draws no line.
  @continuous_linewidth_scale_options NimbleOptions.new!(
                                        [
                                          range: [
                                            type: @linewidth_range_type,
                                            default: @continuous_linewidth_range_default,
                                            doc:
                                              "`{low, high}`: the widths, in millimetres, the " <>
                                                "values run between, each 0 or more."
                                          ]
                                        ] ++
                                          (@continuous_legend_option_specs
                                           |> Keyword.replace!(:limits,
                                             type: @limits_type,
                                             doc:
                                               "`{low, high}`: the values the scale spans " <>
                                                 "whatever the data, `nil` for an end the " <>
                                                 "data decides; either order names the same " <>
                                                 "scale. A value outside them draws no line."
                                           )
                                           |> Enum.concat(guide: @linewidth_guide_spec))
                                      )

  @discrete_linewidth_scale_options NimbleOptions.new!(
                                      [
                                        range: [
                                          type: @linewidth_range_type,
                                          default: @discrete_linewidth_range_default,
                                          doc:
                                            "`{first, last}`: the widths, in millimetres, of " <>
                                              "the first and last values, each 0 or more."
                                        ],
                                        na_value: [
                                          type: {:custom, __MODULE__, :validate_linewidth, []},
                                          doc:
                                            "The width, in millimetres, of a missing value, or " <>
                                              "of one not among the limits, 0 or more; none, " <>
                                              "which draws no line, when not given."
                                        ]
                                      ] ++
                                        Enum.concat(
                                          @discrete_legend_option_specs,
                                          guide: @linewidth_guide_spec
                                        )
                                    )

  # `position_dodge2/1`'s options.
  @position_dodge2_options NimbleOptions.new!(
                             preserve: [
                               type: {:in, [:total, :single]},
                               default: :total,
                               doc:
                                 "Whether the bars at a position share their whole width " <>
                                   "(`:total`), or each takes its width over the most bars any " <>
                                   "one position holds, so a position with fewer leaves room " <>
                                   "(`:single`)."
                             ],
                             padding: [
                               type: {:custom, __MODULE__, :validate_padding, []},
                               default: 0.1,
                               doc:
                                 "How much of its share each bar leaves as a gap, a fraction " <>
                                   "from 0 to 1, in every panel where some position holds two " <>
                                   "bars or more."
                             ],
                             reverse: [
                               type: :boolean,
                               default: false,
                               doc:
                                 "Whether the bars at a position run from the highest group to " <>
                                   "the lowest."
                             ]
                           )

  # `guide_legend/1`'s options.
  @guide_legend_options NimbleOptions.new!(
                          reverse: [
                            type: :boolean,
                            default: false,
                            doc:
                              "Whether the keys run from the last break down to the first, " <>
                                "the key of a missing value first."
                          ]
                        )

  # `guides/2`'s options: the guide of each aesthetic other than position, checked by
  # `validate_guide/2`; a colour bar for a colour or fill scale that turns out discrete is refused
  # when the plot is run, since which kind of scale it gets may be known only then.
  @guides_options NimbleOptions.new!(
                    color: [
                      type: {:custom, __MODULE__, :validate_guide, [:continuous]},
                      doc:
                        "The colour scale's guide (`colour:` too), as `scale_color_continuous/2`'s " <>
                          "`guide:` takes it; a colour bar for a continuous scale alone."
                    ],
                    fill: [
                      type: {:custom, __MODULE__, :validate_guide, [:continuous]},
                      doc:
                        "The fill scale's guide, as `scale_fill_continuous/2`'s `guide:` takes " <>
                          "it; a colour bar for a continuous scale alone."
                    ],
                    alpha: [
                      type: {:custom, __MODULE__, :validate_guide, [:alpha]},
                      doc:
                        "The alpha scale's guide, as `scale_alpha_continuous/2`'s `guide:` takes it."
                    ],
                    shape: [
                      type: {:custom, __MODULE__, :validate_guide, [:shape]},
                      doc:
                        "The shape scale's guide, as `scale_shape_discrete/2`'s `guide:` takes it."
                    ],
                    size: [
                      type: {:custom, __MODULE__, :validate_guide, [:size]},
                      doc:
                        "The size scale's guide, as `scale_size_continuous/2`'s `guide:` takes it."
                    ],
                    linetype: [
                      type: {:custom, __MODULE__, :validate_guide, [:linetype]},
                      doc:
                        "The line type scale's guide, as `scale_linetype_discrete/2`'s `guide:` " <>
                          "takes it."
                    ],
                    linewidth: [
                      type: {:custom, __MODULE__, :validate_guide, [:linewidth]},
                      doc:
                        "The line width scale's guide, as `scale_linewidth_continuous/2`'s " <>
                          "`guide:` takes it."
                    ]
                  )

  # `lims/2`'s options: each axis's limits, its ends or a discrete axis's values, and the limits
  # of a colour, fill, alpha, shape, size, line type or line width scale.
  @axis_limits_type {:custom, __MODULE__, :validate_axis_limits, []}
  @legend_limits_type {:custom, __MODULE__, :validate_legend_limits, []}
  @lims_options NimbleOptions.new!(
                  x: [
                    type: @axis_limits_type,
                    doc: "The x axis's limits, as `xlim/3` or `xlim/2` takes them."
                  ],
                  y: [
                    type: @axis_limits_type,
                    doc: "The y axis's limits, as `ylim/3` or `ylim/2` takes them."
                  ],
                  color: [
                    type: @legend_limits_type,
                    doc:
                      "The colour scale's limits (`colour:` too): `{low, high}`, low first, " <>
                        "for a continuous scale, as `scale_color_continuous/2` takes them, or " <>
                        "a list of values for a discrete one, as `scale_color_discrete/2` does."
                  ],
                  fill: [
                    type: @legend_limits_type,
                    doc:
                      "The fill scale's limits, as `scale_fill_continuous/2` or " <>
                        "`scale_fill_discrete/2` takes them."
                  ],
                  alpha: [
                    type: @legend_limits_type,
                    doc:
                      "The alpha scale's limits, as `scale_alpha_continuous/2` or " <>
                        "`scale_alpha_discrete/2` takes them."
                  ],
                  shape: [
                    type: {:custom, __MODULE__, :validate_unordered_limits, [:shape]},
                    doc:
                      "The shape scale's limits, a list of values, as `scale_shape_discrete/2` " <>
                        "takes them."
                  ],
                  size: [
                    type: @legend_limits_type,
                    doc:
                      "The size scale's limits, as `scale_size_continuous/2` or " <>
                        "`scale_size_discrete/2` takes them."
                  ],
                  linetype: [
                    type: {:custom, __MODULE__, :validate_unordered_limits, [:linetype]},
                    doc:
                      "The line type scale's limits, a list of values, as " <>
                        "`scale_linetype_discrete/2` takes them."
                  ],
                  linewidth: [
                    type: @legend_limits_type,
                    doc:
                      "The line width scale's limits, as `scale_linewidth_continuous/2` or " <>
                        "`scale_linewidth_discrete/2` takes them."
                  ]
                )

  # `labs/2`'s options: a title for each aesthetic a guide shows, and the plot's own.
  @label_option [type: {:custom, __MODULE__, :validate_label, []}]
  @labs_options NimbleOptions.new!(
                  x: [doc: "The x axis's title."] ++ @label_option,
                  y: [doc: "The y axis's title."] ++ @label_option,
                  color:
                    [doc: "The colour legend's or colour bar's title (`colour:` too)."] ++
                      @label_option,
                  fill: [doc: "The fill legend's or colour bar's title."] ++ @label_option,
                  alpha: [doc: "The alpha legend's title."] ++ @label_option,
                  shape: [doc: "The shape legend's title."] ++ @label_option,
                  size: [doc: "The size legend's title."] ++ @label_option,
                  linetype: [doc: "The line type legend's title."] ++ @label_option,
                  linewidth: [doc: "The line width legend's title."] ++ @label_option,
                  title: [doc: "The plot's title, above the panels."] ++ @label_option,
                  subtitle: [doc: "The plot's subtitle, below its title."] ++ @label_option,
                  caption: [doc: "The plot's caption, below the panels."] ++ @label_option,
                  tag: [doc: "The plot's tag, at its top left."] ++ @label_option
                )

  # The units a theme length may be given in, and a margin's sides, in ggplot2's order.
  @theme_units [:pt, :cm, :mm, :in, :lines]
  @theme_sides [:top, :right, :bottom, :left]
  @theme_no_margin Map.new(@theme_sides, fn side -> {side, {0, :pt}} end)

  # `theme/2`'s options: one for each element of the theme a setting may give, from the theme's
  # tree (`Giggly.Theme.elements/0`), each checked as its kind is: a line's, a rectangle's or a
  # text's properties, a length, or a margin.
  @theme_color [
    type: {:custom, __MODULE__, :validate_theme_color, []},
    doc: "Its colour, an opaque CSS colour (`colour:` too)."
  ]
  @theme_linewidth [
    type: {:custom, __MODULE__, :validate_theme_linewidth, []},
    doc: "How wide it is, in millimetres, or `{:rel, share}`, a share of its parent's."
  ]
  @theme_element_types %{
    line: [type: :keyword_list, keys: [color: @theme_color, linewidth: @theme_linewidth]],
    rect: [
      type: :keyword_list,
      keys: [
        fill: [
          type: {:custom, __MODULE__, :validate_theme_color, []},
          doc: "Its fill, an opaque CSS colour."
        ],
        color: [
          type: {:custom, __MODULE__, :validate_theme_border, []},
          doc:
            "Its border's colour, an opaque CSS colour, or `:none` for no border (`colour:` too)."
        ],
        linewidth: @theme_linewidth
      ]
    ],
    text: [
      type: :keyword_list,
      keys: [
        color: @theme_color,
        size: [
          type: {:custom, __MODULE__, :validate_theme_size, []},
          doc: "How big it is, in points, or `{:rel, share}`, a share of its parent's size."
        ],
        margin: [
          type: {:custom, __MODULE__, :validate_theme_margin, [:text]},
          doc:
            "The space on each side of it: one length for every side, or a keyword list of " <>
              "`:top`, `:right`, `:bottom` and `:left`, a side left out 0."
        ]
      ]
    ],
    length: [type: {:custom, __MODULE__, :validate_theme_length, [:element]}],
    margin: [type: {:custom, __MODULE__, :validate_theme_margin, [:element]}],
    position: [type: {:in, [:right, :none]}]
  }
  # The elements whose settings are a line's, a rectangle's or a text's properties, whose spelling
  # `theme/2` canonicalizes (`colour:`) before checking them.
  @theme_drawn_kinds for {name, kind, _parent, _description} <- Theme.elements(),
                         kind in [:line, :rect, :text],
                         into: %{},
                         do: {name, kind}
  # A root length or margin is checked as one with no parent to take a share of.
  @theme_root_types %{
    length: [type: {:custom, __MODULE__, :validate_theme_length, [:root]}],
    margin: [type: {:custom, __MODULE__, :validate_theme_margin, [:root]}]
  }
  @theme_options NimbleOptions.new!(
                   for {name, kind, parent, description} <- Theme.elements() do
                     inherits =
                       if parent == :none, do: "", else: " Inherits from `#{inspect(parent)}`."

                     type =
                       if parent == :none and is_map_key(@theme_root_types, kind),
                         do: Map.fetch!(@theme_root_types, kind),
                         else: Map.fetch!(@theme_element_types, kind)

                     {name, [doc: description <> inherits] ++ type}
                   end
                 )

  defguardp is_column_reference(reference) when is_binary(reference) or is_atom(reference)

  # An end of a date scale's limits: a date, or `nil` for one the data decides.
  defguardp is_date_limit(limit) when is_struct(limit, Date) or is_nil(limit)

  @doc """
  A plot of `data`, with `mapping` applying to every layer.

  The mapping's columns are checked by the layers that use them, so a misspelt column is reported
  by the first layer function to take it. Raises `ArgumentError` for a value that is not a column,
  an expression or a constant (`Giggly.Mapping`).

      iex> plot =
      ...>   Giggly.Plot.new(
      ...>     %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]},
      ...>     %{x: :wt, y: "mpg", colour: :cyl}
      ...>   )
      iex> plot.mapping
      %{x: "wt", y: "mpg", color: "cyl"}
  """
  @spec new(Table.Reader.t(), mapping_argument()) :: t()
  def new(data, mapping \\ %{}) when is_map(mapping) do
    frame = DataFrame.from_table(data)

    %__MODULE__{
      data: frame,
      mapping: references(mapping, "Plot.new/2"),
      facet: %Facet.Null{},
      coord: %Coord.Cartesian{},
      scales: %{},
      guides: %{},
      theme: %{complete: :gray, settings: %{}},
      labels: %{},
      reversed_layers: []
    }
  end

  @doc """
  Adds a layer of points, one per row, at `x` and `y`.

  Points use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:fill`, `:shape` and `:size`, and need
  `:x` and `:y`. A point's alpha applies to its colour and its fill alike; a colour or shape of
  `:none`, or a missing size or shape, draws no point.

  A point is drawn in one of 26 shapes, each named, and numbered 0 to 25:

    * outlined in the point's colour: `:square_open` (0), `:circle_open` (1), `:triangle_open`
      (2), `:plus` (3), `:cross` (4), `:diamond_open` (5), `:triangle_down_open` (6),
      `:square_cross` (7), `:asterisk` (8), `:diamond_plus` (9), `:circle_plus` (10), `:star`
      (11), `:square_plus` (12), `:circle_cross` (13) and `:square_triangle` (14);
    * filled with its colour: `:square` (15), `:circle_small` (16), `:triangle` (17) and
      `:diamond` (18), with no outline, and `:circle` (19) and the smaller `:bullet` (20),
      outlined in it too;
    * outlined in its colour and filled with its fill: `:circle_filled` (21), `:square_filled`
      (22), `:diamond_filled` (23), `:triangle_filled` (24) and `:triangle_down_filled` (25).

  ## Options

  #{NimbleOptions.docs(@point_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}
      ...>   |> Giggly.Plot.new()
      ...>   |> Giggly.Plot.geom_point(%{x: :wt, y: :mpg, group: :cyl})
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :x)
      [2.62, 2.875]
      iex> Giggly.DataFrame.pull(frame, :group)
      [2, 1]

  A value set for every point is in every row of the layer's table:

      iex> plot =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point(alpha: 0.4)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:alpha)
      [0.4, 0.4]

  A colour is kept as the hex it names:

      iex> plot =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point(colour: "steelblue")
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#4682B4", "#4682B4"]

  A shape given by its number is kept as its name:

      iex> plot =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point(shape: 21, fill: "white", size: 5, stroke: 2)
      iex> frame = Giggly.layer_data(plot)
      iex> {Giggly.DataFrame.pull(frame, :shape), Giggly.DataFrame.pull(frame, :fill)}
      {[:circle_filled, :circle_filled], ["#FFFFFF", "#FFFFFF"]}
  """
  @spec geom_point(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_point(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_point(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_point(plot, %{}, options)

  def geom_point(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @point_options)
    data = own_data(validated)

    layer = %Layer{
      geom: %Geom.Point{},
      stat: %Stat.Identity{},
      position: %Position.Identity{},
      data: data,
      mapping: resolve(mapping, plot, data, "Plot.geom_point/3"),
      fixed: fixed(validated),
      accepted: Geom.Point.accepted_aesthetics(),
      annotation: false
    }

    add_layer(plot, layer, "Plot.geom_point/3", required: Geom.Point.required_aesthetics())
  end

  @doc """
  Adds a layer of points counting the rows at each place: one point for each combination of `x`,
  `y` and the layer's other aesthetics that its rows hold, sized by how many rows hold it, or,
  where `:weight` is mapped, by the sum of their weights, and the size legend titled `n`. The
  points are drawn as `geom_point/3` draws them.

  Counting uses `:x`, `:y`, `:weight` and `:group`, and needs `:x` and `:y`. A `:weight` column must
  hold numbers, and a missing weight leaves its place's count missing, so no point is drawn there.
  The points also take `:alpha`, `:color`, `:fill`, `:shape` and `:size`; each is counted over, as
  `:group` is, so a discrete colour gives each of its values at a place a point of its own, and a
  mapped `:size` sizes the points by its column instead of the count. A row missing its `x` or `y`
  is not counted.

  Counting computes `n` and `prop`, the count's share of its group's total in its panel, which a
  mapping reads with an after_stat (`Giggly.Mapping`): `%{size: {:after_stat, [:prop]}, group: 1}`
  sizes each point by its share of all the rows.

  ## Options

  #{NimbleOptions.docs(@point_options)}

      iex> plot =
      ...>   %{"cty" => [18, 18, 21], "hwy" => [29, 29, 29]}
      ...>   |> Giggly.Plot.new(%{x: :cty, y: :hwy})
      ...>   |> Giggly.Plot.geom_count()
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :n)
      [2.0, 1.0]
      iex> Giggly.DataFrame.pull(frame, :size)
      [6.0, 1.0]
  """
  @spec geom_count(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_count(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_count(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_count(plot, %{}, options)

  def geom_count(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options),
      do: count_layer(plot, mapping, options, "Plot.geom_count/3")

  @doc """
  Adds the layer `geom_count/3` adds, points counting the rows at each place, from the same
  mapping and options.

      iex> plot =
      ...>   %{"cty" => [18, 18, 21], "hwy" => [29, 29, 29]}
      ...>   |> Giggly.Plot.new(%{x: :cty, y: :hwy})
      ...>   |> Giggly.Plot.stat_sum()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:prop)
      [0.6666666666666666, 0.3333333333333333]
  """
  @spec stat_sum(t(), mapping_argument() | keyword(), keyword()) :: t()
  def stat_sum(plot, mapping_or_options \\ %{}, options \\ [])

  def stat_sum(%__MODULE__{} = plot, options, []) when is_list(options),
    do: stat_sum(plot, %{}, options)

  def stat_sum(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options),
      do: count_layer(plot, mapping, options, "Plot.stat_sum/3")

  @doc """
  Adds a layer of bars counting the rows at each `x`. Each bar runs from 0 to the number of rows at
  its `x`, or, where `:weight` is mapped, to the sum of their weights, and the y axis is titled
  `count`. A row missing its `x` is not counted. The bars are drawn as `geom_col/3` draws them.

  Counting uses `:x` or `:y`, `:weight` and `:group`, and needs exactly one of `:x` and `:y`: it
  counts along the one mapped, so mapping `:y` alone draws horizontal bars. A `:weight` column must
  hold numbers. The bars also take `:alpha`, `:fill`, `:color`, `:linetype` and `:linewidth`; one
  reaches a bar only where it is the same in every row the bar counts, so a discrete one groups the
  rows and gives each group its own bar. Each bar is 0.9 times the closest spacing of the `x`
  positions wide, counting from zero, unless `width:` says otherwise; counting gives every bar its
  width, so `:width` is not mapped. `just:` places each bar against its `x`.

  Counting computes `count` and `prop`, the count's share of its group's total, which a mapping
  reads with an after_stat (`Giggly.Mapping`): `%{x: :class, y: {:after_stat, [:prop]}, group: 1}`
  draws each class's share of all the rows.

  ## Options

  #{NimbleOptions.docs(@count_options)}

      iex> plot =
      ...>   %{"class" => ["suv", "compact", "suv"]}
      ...>   |> Giggly.Plot.new(%{x: :class})
      ...>   |> Giggly.Plot.geom_bar()
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :count)
      [1.0, 2.0]
  """
  @spec geom_bar(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_bar(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_bar(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_bar(plot, %{}, options)

  def geom_bar(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @count_options)
    data = own_data(validated)

    layer = %Layer{
      geom: %Geom.Bar{just: Keyword.fetch!(validated, :just)},
      stat: %Stat.Count{width: Keyword.get(validated, :width, :none)},
      position: position(Keyword.fetch!(validated, :position)),
      data: data,
      mapping: resolve(mapping, plot, data, "Plot.geom_bar/3"),
      fixed: fixed(validated),
      accepted: counted_bar_aesthetics(Stat.Count.accepted_aesthetics()),
      annotation: false
    }

    plot
    |> add_layer(layer, "Plot.geom_bar/3",
      required: Stat.Count.required_aesthetics(),
      exclusive: Stat.Count.exclusive_aesthetics(),
      computed: Stat.Count.computed_variables(),
      dropped: Stat.Count.dropped_aesthetics()
    )
    |> check_weight(layer, "Plot.geom_bar/3")
    |> check_runs_along(layer, validated, "Plot.geom_bar/3", "count")
  end

  @doc """
  Adds a layer of bars counting the rows in each bin, a histogram: the `x` axis cut into bins, and
  for each group one bar per bin, from 0 to the number of rows in it, or, where `:weight` is
  mapped, to the sum of their weights, a bin with no rows counting 0. The y axis is titled `count`.
  The bins are 30 spanning each panel's x axis unless `bins:`, `binwidth:` or `breaks:` says
  otherwise; bars of different groups in one bin are stacked. A row missing its `x`, or outside the
  breaks given, is not counted. The bars are drawn as `geom_col/3` draws them.

  Binning uses `:x` or `:y`, `:weight` and `:group`, and needs exactly one of `:x` and `:y`, on a
  continuous axis: it bins along the one mapped, so mapping `:y` alone draws horizontal bars. A
  `:weight` column must hold numbers, and a missing weight adds nothing. The bars also take
  `:alpha`, `:fill`, `:color`, `:linetype` and `:linewidth`; one reaches a bar only where it is the
  same in every row of its group, so a discrete one groups the rows and gives each group its bars.

  Binning computes, for each bin, `count`; `density`, the count over the bin's width over the
  group's total, so a group's bars cover an area of 1; `ncount` and `ndensity`, the count and the
  density over the group's largest; and `width`. A mapping reads them with an after_stat
  (`Giggly.Mapping`): `%{x: :hwy, y: {:after_stat, [:density]}}` draws the density.

  ## Options

  #{NimbleOptions.docs(@bin_options)}

      iex> plot =
      ...>   %{"x" => [1.0, 1.5, 2.5, 4.0]}
      ...>   |> Giggly.Plot.new(%{x: :x})
      ...>   |> Giggly.Plot.geom_histogram(binwidth: 1, boundary: 0)
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :count)
      [2.0, 1.0, 1.0]
      iex> Giggly.DataFrame.pull(frame, :x)
      [1.5, 2.5, 3.5]
  """
  @spec geom_histogram(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_histogram(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_histogram(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_histogram(plot, %{}, options)

  def geom_histogram(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options),
      do: bin_layer(plot, mapping, options, "Plot.geom_histogram/3")

  @doc """
  Adds the layer `geom_histogram/3` adds, bars counting the rows in each bin, from the same mapping
  and options.

      iex> plot =
      ...>   %{"x" => [1.0, 1.5, 2.5, 4.0]}
      ...>   |> Giggly.Plot.new(%{x: :x})
      ...>   |> Giggly.Plot.stat_bin(binwidth: 1, boundary: 0)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:density)
      [0.5, 0.25, 0.25]
  """
  @spec stat_bin(t(), mapping_argument() | keyword(), keyword()) :: t()
  def stat_bin(plot, mapping_or_options \\ %{}, options \\ [])

  def stat_bin(%__MODULE__{} = plot, options, []) when is_list(options),
    do: stat_bin(plot, %{}, options)

  def stat_bin(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options),
      do: bin_layer(plot, mapping, options, "Plot.stat_bin/3")

  @doc """
  Adds a layer of frequency polygons: the `x` axis cut into bins, as `geom_histogram/3` cuts it,
  and for each group a line through the middle of each bin at the number of rows in it, or, where
  `:weight` is mapped, the sum of their weights. A bin of no rows is added at each end, so every
  line starts and ends at 0. The y axis is titled `count`. The lines of different groups are drawn
  over one another, not stacked, so a discrete colour compares the groups' distributions. A row
  missing its `x`, or outside the breaks given, is not counted. The lines are drawn as
  `geom_path/3` draws paths.

  Binning uses `:x` or `:y`, `:weight` and `:group`, and needs exactly one of `:x` and `:y`, on a
  continuous axis: it bins along the one mapped, so mapping `:y` alone draws lines that run up the
  panel. A `:weight` column must hold numbers, and a missing weight adds nothing. The lines also
  take `:alpha`, `:color`, `:linetype` and `:linewidth`; one reaches a line only where it is the
  same in every row of its group, so a discrete one groups the rows and gives each group its line.

  Binning computes what `geom_histogram/3` lists, which a mapping reads with an after_stat
  (`Giggly.Mapping`): `%{x: :price, y: {:after_stat, [:density]}, color: :cut}` draws each cut's
  density, comparable however many rows each cut has.

  ## Options

  #{NimbleOptions.docs(@freqpoly_options)}

      iex> plot =
      ...>   %{"x" => [1.0, 1.5, 2.5, 4.0]}
      ...>   |> Giggly.Plot.new(%{x: :x})
      ...>   |> Giggly.Plot.geom_freqpoly(binwidth: 1, boundary: 0)
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :x)
      [0.5, 1.5, 2.5, 3.5, 4.5]
      iex> Giggly.DataFrame.pull(frame, :count)
      [0.0, 2.0, 1.0, 1.0, 0.0]
  """
  @spec geom_freqpoly(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_freqpoly(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_freqpoly(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_freqpoly(plot, %{}, options)

  def geom_freqpoly(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @freqpoly_options)
    check_bin_placement(validated, "Plot.geom_freqpoly/3")
    data = own_data(validated)

    layer = %Layer{
      geom: path_geom(validated),
      stat: bin_stat(validated, true),
      position: %Position.Identity{},
      data: data,
      mapping: resolve(mapping, plot, data, "Plot.geom_freqpoly/3"),
      fixed: fixed(validated),
      accepted: Enum.uniq(Stat.Bin.accepted_aesthetics() ++ Geom.Path.accepted_aesthetics()),
      annotation: false
    }

    add_binning_layer(plot, layer, validated, "Plot.geom_freqpoly/3")
  end

  @doc """
  Adds a layer of box plots, a box for each group summarising its `y`: from its lower quartile to
  its upper, a line across it at its median, and whiskers out to the least and greatest `y` within
  `coef:` heights of the box beyond it, every value further out drawn as a point, an outlier. The
  quartiles are R's default (type 7). Each box stands at the middle of its group's `x` values,
  0.75 times the closest spacing of the `x` positions wide, counting from zero, or 0.9 of the
  range of its group's `x` values where they are several, or as wide as its group's first mapped
  `:width`, a number, or as `width:` says. A row missing its `x` or `y`, or at an infinite one, is
  left out.

  Boxes stand along the discrete one of `x` and `y`, so mapping a discrete `y` beside a numeric `x`
  draws horizontal boxes summarising `x`; mapping one of them alone summarises it, a single box at
  0; where both are continuous, they stand along the axis on which every group holds one value,
  or else along `x`, each group a box, so a numeric `x` takes a `:group` to draw more than one.
  `orientation:` says which. Boxes sharing a position are set side by side, as `position:` says.

  Box plots use `:x`, `:y`, `:group`, `:width`, `:alpha`, `:color`, `:fill`, `:linetype` and
  `:linewidth`, and `:shape` and `:size`, which the outliers take, and need `:x` or `:y`. A look
  reaches a box only where it is the same in every row of its group, so a discrete one groups the
  rows and gives each group its own box. A box plot is not weighted, so a `:weight` the plot's
  mapping gives is refused. The whiskers, staples, median and box's border each take a look of
  their own (`whisker_color:` and the like), and the outliers theirs (`outlier_color:` and the
  like), else the box's.

  ## Options

  #{NimbleOptions.docs(@boxplot_options)}

      iex> plot =
      ...>   %{"g" => ["a", "a", "a", "a", "a"], "y" => [1.0, 2.0, 3.0, 4.0, 20.0]}
      ...>   |> Giggly.Plot.new(%{x: :g, y: :y})
      ...>   |> Giggly.Plot.geom_boxplot()
      iex> frame = Giggly.layer_data(plot)
      iex> {Giggly.DataFrame.pull(frame, :middle), Giggly.DataFrame.pull(frame, :outliers)}
      {[3.0], [[20.0]]}
  """
  @spec geom_boxplot(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_boxplot(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_boxplot(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_boxplot(plot, %{}, options)

  def geom_boxplot(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @boxplot_options)
    data = own_data(validated)

    layer = %Layer{
      geom: boxplot_geom(validated),
      stat: %Stat.Boxplot{
        coef: Keyword.fetch!(validated, :coef),
        width: Keyword.get(validated, :width, :none),
        orientation: Keyword.get(validated, :orientation, :none)
      },
      position:
        boxplot_position(
          Keyword.fetch!(validated, :position),
          Keyword.fetch!(validated, :varwidth)
        ),
      data: data,
      mapping: resolve(mapping, plot, data, "Plot.geom_boxplot/3"),
      fixed: fixed(validated),
      accepted:
        Enum.uniq(Stat.Boxplot.accepted_aesthetics() ++ Geom.Boxplot.accepted_aesthetics()),
      annotation: false
    }

    plot
    |> add_layer(layer, "Plot.geom_boxplot/3",
      required: Stat.Boxplot.required_aesthetics(),
      computed: Stat.Boxplot.computed_variables(),
      dropped: Stat.Boxplot.dropped_aesthetics()
    )
    |> check_unweighted(layer, "Plot.geom_boxplot/3")
    |> check_numbers(layer, "Plot.geom_boxplot/3", :width, "a box is drawn as wide as its width")
    |> check_stands_along(layer, validated, "Plot.geom_boxplot/3")
  end

  @doc """
  Adds a layer of bars, one per row, each from 0 to its `y` and centred on its `x` unless `just:`
  says otherwise, for bars whose heights are in the data. Bars at the same `x` are stacked, those
  below zero downward, the highest group at the bottom; with `position: :dodge` they are set side
  by side within one bar's width, an `x` with one group keeping its whole width; with `position:
  :dodge2`, or as `position_dodge2/1` says, bars whose spans overlap are set side by side, each its
  share of their widths, with a gap between them.

  Each bar is 0.9 times the closest spacing of the `x` positions wide: 0.9 on a discrete axis, and
  on a continuous one 0.9 times the closest gap, a column of integers counting as 1 apart; or as
  wide as its mapped `:width`, a number, or as `width:` makes every bar, which wins over a mapped
  one. `just:` places each bar against its `x`, its lower edge there at 0 and its upper at 1. Bars
  of different widths at one `x` are dodged together only by `:dodge2`. The `y` axis reaches 0.

  Bars use `:x`, `:y`, `:group`, `:alpha`, `:fill`, `:color`, `:linetype`, `:linewidth` and
  `:width`, and need `:x` and `:y`. `:fill` fills a bar and takes its alpha; `:color` borders it,
  and bars have no border unless it is mapped or set; `:linewidth` and `:linetype` say how wide
  the border is and how it is dashed. With a discrete `y` and a continuous `x`, the bars are
  horizontal.

  ## Options

  #{NimbleOptions.docs(@bar_options)}

      iex> plot =
      ...>   %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
      ...>   |> Giggly.Plot.new(%{x: :trt, y: :outcome})
      ...>   |> Giggly.Plot.geom_col()
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :ymin)
      [0.0, 0.0, 0.0]
      iex> Giggly.DataFrame.pull(frame, :ymax)
      [2.3, 1.9, 3.2]

  Dodged, the two groups at `a` share its width, and `b`'s one group keeps all of it:

      iex> plot =
      ...>   %{"x" => ["a", "a", "b"], "y" => [1.0, 2.0, 3.0], "g" => ["p", "q", "p"]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y, group: :g})
      ...>   |> Giggly.Plot.geom_col(position: :dodge)
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :xmin)
      [0.55, 1.0, 1.55]
  """
  @spec geom_col(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_col(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_col(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_col(plot, %{}, options)

  def geom_col(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @bar_options)
    data = own_data(validated)

    layer = %Layer{
      geom: %Geom.Bar{just: Keyword.fetch!(validated, :just)},
      stat: %Stat.Identity{},
      position: position(Keyword.fetch!(validated, :position)),
      data: data,
      mapping: resolve(mapping, plot, data, "Plot.geom_col/3"),
      fixed: fixed(validated),
      accepted: Geom.Bar.accepted_aesthetics(),
      annotation: false
    }

    plot
    |> add_layer(layer, "Plot.geom_col/3", required: Geom.Bar.required_aesthetics())
    |> check_width(layer, "Plot.geom_col/3")
  end

  @doc """
  Adds a layer of paths: a line through each group's rows in the order the data gives them, for a
  line that may double back. `geom_line/3` puts the rows in order first.

  Paths use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:linetype` and `:linewidth`, and need `:x`
  and `:y`. Each group is a line of its own, and a discrete colour, line type or width groups the
  rows. A row missing `x` or `y` breaks its line; a group of one row draws nothing. Where colour,
  alpha or width changes along a line, each segment takes the colour, alpha and width of the row
  it starts from, and a missing width leaves its segment out; a line type cannot change along a
  line, and while any line is dashed, dotted or blank, drawing one whose colour, alpha or width
  changes raises `ArgumentError`. A colour of `:none` draws no line, and so does the line type
  `:blank`.

  ## Options

  #{NimbleOptions.docs(@path_options)}

      iex> plot =
      ...>   %{"unemploy" => [2.9, 4.1, 3.4], "psavert" => [12.6, 9.4, 11.1]}
      ...>   |> Giggly.Plot.new(%{x: :unemploy, y: :psavert})
      ...>   |> Giggly.Plot.geom_path(linewidth: 2)
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :x)
      [2.9, 4.1, 3.4]
      iex> Giggly.DataFrame.pull(frame, :linewidth)
      [2.0, 2.0, 2.0]

  A line type is held as its dash pattern, whichever way it is written:

      iex> frame =
      ...>   %{"unemploy" => [2.9, 4.1], "psavert" => [12.6, 9.4]}
      ...>   |> Giggly.Plot.new(%{x: :unemploy, y: :psavert})
      ...>   |> Giggly.Plot.geom_path(linetype: 2)
      ...>   |> Giggly.layer_data()
      iex> Giggly.DataFrame.pull(frame, :linetype)
      [{4, 4}, {4, 4}]
  """
  @spec geom_path(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_path(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_path(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_path(plot, %{}, options)

  def geom_path(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @path_options)
    data = own_data(validated)

    layer = %Layer{
      geom: path_geom(validated),
      stat: %Stat.Identity{},
      position: %Position.Identity{},
      data: data,
      mapping: resolve(mapping, plot, data, "Plot.geom_path/3"),
      fixed: fixed(validated),
      accepted: Geom.Path.accepted_aesthetics(),
      annotation: false
    }

    add_layer(plot, layer, "Plot.geom_path/3", required: Geom.Path.required_aesthetics())
  end

  @doc """
  Adds a layer of lines: a line through each group's rows in order of their `x`, as a series over
  time is drawn, or of their `y` with `orientation: :y`. Rows that share a position keep the order
  the data gives them. Lines are drawn as `geom_path/3` draws paths and take the same aesthetics.

  ## Options

  #{NimbleOptions.docs(@line_options)}

      iex> plot =
      ...>   %{"x" => [1.0, 3.0, 2.0], "y" => [1.0, 2.0, 4.0]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y})
      ...>   |> Giggly.Plot.geom_line()
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :x)
      [1.0, 2.0, 3.0]
      iex> Giggly.DataFrame.pull(frame, :y)
      [1.0, 4.0, 2.0]
  """
  @spec geom_line(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_line(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_line(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_line(plot, %{}, options)

  def geom_line(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @line_options)
    data = own_data(validated)

    layer = %Layer{
      geom: line_geom(validated),
      stat: %Stat.Identity{},
      position: %Position.Identity{},
      data: data,
      mapping: resolve(mapping, plot, data, "Plot.geom_line/3"),
      fixed: fixed(validated),
      accepted: Geom.Line.accepted_aesthetics(),
      annotation: false
    }

    add_layer(plot, layer, "Plot.geom_line/3", required: Geom.Line.required_aesthetics())
  end

  @doc """
  Adds a layer of text: each row's `label` at its `x` and `y`.

  Text is written as it is; a whole number has no decimal point (`21`, not `21.0`), any other
  number up to 15 significant digits, in scientific notation when that is shorter (`1e+05`), and a
  boolean is `TRUE` or `FALSE`. Each label is centred on its place, black and 11 points tall,
  unless the options say otherwise. A row missing its `x`, `y` or label draws nothing.

  Text uses `:x`, `:y`, `:label`, `:group`, `:alpha` and `:color`, and needs `:x`, `:y` and
  `:label`; a label never groups the rows. `nudge_x:` and `nudge_y:` move every label, in the
  units of each axis, and the axes reach the labels where they are drawn.

  ## Options

  #{NimbleOptions.docs(@text_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32], "mpg" => [21.0, 22.8], "model" => ["Mazda RX4", "Datsun 710"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, label: :model})
      ...>   |> Giggly.Plot.geom_text(hjust: :inward, size: 5)
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :label)
      ["Mazda RX4", "Datsun 710"]
      iex> Giggly.DataFrame.pull(frame, :hjust)
      [:inward, :inward]

  A whole number is labelled without a decimal point, and a large one in scientific notation:

      iex> svg =
      ...>   %{"x" => [1.0, 2.0], "y" => [1.0, 2.0], "count" => [21.0, 100_000.0]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y, label: :count})
      ...>   |> Giggly.Plot.geom_text()
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> {svg =~ ">21</text>", svg =~ ">1e+05</text>"}
      {true, true}

  Nudged labels sit off the points they name:

      iex> frame =
      ...>   %{"x" => [1.0, 2.0, 3.0], "y" => [1.0, 4.0, 2.0], "name" => ["a", "b", "c"]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y, label: :name})
      ...>   |> Giggly.Plot.geom_text(nudge_x: 0.1, nudge_y: -0.2)
      ...>   |> Giggly.layer_data()
      iex> {Giggly.DataFrame.pull(frame, :x), Giggly.DataFrame.pull(frame, :y)}
      {[1.1, 2.1, 3.1], [0.8, 3.8, 1.8]}
  """
  @spec geom_text(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_text(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_text(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_text(plot, %{}, options)

  def geom_text(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @text_options)
    data = own_data(validated)

    layer = %Layer{
      geom: text_geom(validated),
      stat: %Stat.Identity{},
      position: %Position.Nudge{},
      data: data,
      mapping: resolve(mapping, plot, data, "Plot.geom_text/3"),
      fixed: fixed(validated),
      accepted: Geom.Text.accepted_aesthetics(),
      annotation: false
    }

    add_layer(plot, layer, "Plot.geom_text/3", required: Geom.Text.required_aesthetics())
  end

  @doc """
  Adds a layer of rectangles, one per row, each from its `xmin` to its `xmax` and its `ymin` to its
  `ymax`.

  Each corner is mapped to a column, or set for every rectangle by the option of its name, in the
  units of its axis; a set corner widens the axes as a mapped one does. `:infinity` and
  `:neg_infinity` reach the panel's edge, so a band can shade the whole panel. A row missing a
  corner draws nothing.

  Rectangles use `:xmin`, `:xmax`, `:ymin`, `:ymax`, `:group`, `:alpha`, `:fill`, `:color`,
  `:linetype` and `:linewidth`, and need all four corners, each mapped or set. They look as
  `geom_col/3`'s bars do, their borders as wide and dashed as `:linewidth` and `:linetype` say.

  ## Options

  #{NimbleOptions.docs(@rect_options)}

      iex> frame =
      ...>   %{"start" => [1.0, 3.0], "end" => [2.0, 5.0], "low" => [0.0, 1.0], "high" => [4.0, 2.0]}
      ...>   |> Giggly.Plot.new(%{xmin: :start, xmax: :end, ymin: :low, ymax: :high})
      ...>   |> Giggly.Plot.geom_rect()
      ...>   |> Giggly.layer_data()
      iex> {Giggly.DataFrame.pull(frame, :xmin), Giggly.DataFrame.pull(frame, :ymax)}
      {[1.0, 3.0], [4.0, 2.0]}

  Corners set for every rectangle shade one band behind every row:

      iex> frame =
      ...>   %{"start" => [1.0, 3.0], "end" => [2.0, 5.0]}
      ...>   |> Giggly.Plot.new(%{xmin: :start, xmax: :end})
      ...>   |> Giggly.Plot.geom_rect(ymin: 0, ymax: :infinity)
      ...>   |> Giggly.layer_data()
      iex> {Giggly.DataFrame.pull(frame, :ymin), Giggly.DataFrame.pull(frame, :ymax)}
      {[0.0, 0.0], [:infinity, :infinity]}
  """
  @spec geom_rect(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_rect(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_rect(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_rect(plot, %{}, options)

  def geom_rect(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @rect_options)
    data = own_data(validated)

    layer = %Layer{
      geom: %Geom.Rect{},
      stat: %Stat.Identity{},
      position: %Position.Identity{},
      data: data,
      mapping: resolve(mapping, plot, data, "Plot.geom_rect/3"),
      fixed: fixed(validated),
      accepted: Geom.Rect.accepted_aesthetics(),
      annotation: false
    }

    add_layer(plot, layer, "Plot.geom_rect/3",
      required: Geom.Rect.required_aesthetics(),
      unmet: "neither its mapping nor the plot's maps it, and no option sets it"
    )
  end

  @doc """
  Adds an annotation: a layer drawn from values given here rather than from the data's columns,
  for a label, a shaded rectangle or a line placed by hand. `geom` names what draws it: `:point`,
  `:col` or `:bar`, `:path`, `:line`, `:text` or `:rect`.

  An annotation's positions widen the axes as the data's do. It takes nothing from the plot's
  mapping, titles no axis, is in no legend, and under a facet is drawn in every panel. It is drawn
  where it is placed: text is not nudged, and bars at one `x` are not stacked.

  Each option takes one value, or a list of them, one per annotation: every list holds as many
  values as the others, and a single value is used for every annotation, so
  `x: [2, 3, 4, 5], y: 25` places four. A position is a number, `:infinity` or `:neg_infinity`,
  which reach the panel's edge, `nil` for none, a string on a discrete axis, `true` or `false`, or
  a date on a date axis. Of the other options, `label:`, `colour:`, `alpha:` and `fill:` each take
  a list, its values of one type, and so do a point's `shape:`, `size:` and `stroke:`, a bar's or
  a rectangle's `linewidth:` and `linetype:`, whose list holds line types, a dash pattern among
  them a tuple, and a path's or a line's `linewidth:`, a line whose width changes along it drawn a
  segment from each annotation to the next; the rest take one value. Under a facet that makes more than one
  panel, an annotation given such a list raises when the plot is run.

  Each geom takes the positions it draws at and the options its own function takes but `data:`
  and `position:`, and `geom_text/3`'s nudging:

    * `:point`: `x:`, `y:`, `alpha:`, `colour:`, `fill:`, `shape:`, `size:` and `stroke:`;
    * `:col` and `:bar`, each a bar from 0 to its `y` as `geom_col/3` draws one: `x:`, `y:`,
      `alpha:`, `colour:`, `fill:`, `linewidth:`, `linetype:`, `width:` and `just:`;
    * `:path`: `x:`, `y:`, `alpha:`, `colour:`, `linewidth:`, `linetype:`, `lineend:`, `linejoin:`
      and `linemitre:`, and `:line` those and `orientation:`;
    * `:text`: `x:`, `y:`, `label:`, `check_overlap:`, `alpha:`, `colour:`, `size:`, `angle:`,
      `hjust:`, `vjust:` and `family:`;
    * `:rect`: `xmin:`, `xmax:`, `ymin:`, `ymax:`, `alpha:`, `colour:`, `fill:`, `linewidth:` and
      `linetype:`.

  Raises `ArgumentError` for a geom it does not draw with, for lists of different lengths, for a
  list whose values are not of one type, and for an aesthetic the geom needs and is not given;
  `NimbleOptions.ValidationError` for an option the geom does not take, or a value it cannot draw.

      iex> frame =
      ...>   %{"wt" => [2.62, 3.44], "mpg" => [21.0, 18.7]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.annotate(:text, x: [2.0, 3.0], y: 25.0, label: ["my label", "label 2"])
      ...>   |> Giggly.layer_data(1)
      iex> {Giggly.DataFrame.pull(frame, :y), Giggly.DataFrame.pull(frame, :label)}
      {[25.0, 25.0], ["my label", "label 2"]}
  """
  @spec annotate(t(), atom(), keyword()) :: t()
  def annotate(%__MODULE__{} = plot, geom, options)
      when geom in @annotation_geoms and is_list(options) do
    validated = layer_options(options, Map.fetch!(@annotation_options, geom))
    {kind, accepted, required} = annotation_geom(geom, validated)
    {positions, others} = Enum.split_with(validated, &position?/1)

    per_row = Keyword.take(others, @per_annotation_aesthetics)

    count =
      positions
      |> Enum.concat(per_row)
      |> annotation_count()

    table =
      positions
      |> Enum.map(fn {aesthetic, values} ->
        {Atom.to_string(aesthetic), recycled(values, count)}
      end)
      |> DataFrame.new()

    fixed =
      others
      |> fixed()
      |> Map.new(fn {aesthetic, value} -> {aesthetic, per_row(value)} end)

    check_columns(fixed)

    layer = %Layer{
      geom: kind,
      stat: %Stat.Identity{},
      position: %Position.Identity{},
      data: table,
      mapping:
        Map.new(positions, fn {aesthetic, _values} -> {aesthetic, Atom.to_string(aesthetic)} end),
      fixed: fixed,
      accepted: accepted,
      annotation: true
    }

    add_layer(plot, layer, "Plot.annotate/3",
      required: required,
      unmet: "#{inspect(geom)} is given no value for it"
    )
  end

  def annotate(%__MODULE__{}, geom, options) when is_list(options) do
    raise ArgumentError,
          "Plot.annotate/3 draws with :point, :col, :bar, :path, :line, :text or :rect, " <>
            "got: #{inspect(geom)}"
  end

  @doc """
  A position for the `position:` of `geom_bar/3`, `geom_col/3`, `geom_histogram/3` and
  `stat_bin/3`, with options: the bars at a position set side by side, as `position: :dodge2`
  sets them.

  Bars whose spans overlap or meet are dodged together, whatever their groups and widths: each
  takes its share of their widths, its own width over their number, and they are laid side by
  side in order of group, centred on the middle of the span they covered, each bar's `x` moving
  to its middle. In a panel where some position holds two bars or more, every bar is then
  narrowed by `padding:`, so neighbours stand apart. The layer's rows come out in that order: by
  panel, then by `x`, then by group.

  Raises `NimbleOptions.ValidationError` for an option it does not take or a value it cannot use.

  ## Options

  #{NimbleOptions.docs(@position_dodge2_options)}

      iex> plot =
      ...>   %{"x" => ["a", "a", "b"], "y" => [1.0, 2.0, 3.0], "g" => ["p", "q", "p"]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y, fill: :g})
      ...>   |> Giggly.Plot.geom_col(position: Giggly.Plot.position_dodge2(preserve: :single))
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :xmin)
      [0.5725, 1.0225000000000002, 1.7974999999999999]
  """
  @spec position_dodge2(keyword()) :: struct()
  def position_dodge2(options \\ []) when is_list(options) do
    validated = NimbleOptions.validate!(options, @position_dodge2_options)
    struct!(Position.Dodge2, validated)
  end

  @doc """
  Splits the plot into panels, one for each combination of values of the `facets` columns that
  occurs in the data, laid out in rows. `facets` is a column, or a list of columns, each named as
  a mapping names one: `facet_wrap(plot, :class)` or `facet_wrap(plot, [:cyl, :drv])`.

  Each layer's rows are drawn in the panel of their values. The panels are those the plot's data
  and every layer's own table make together; a table lacking some of the columns is drawn in every
  panel of the values it has, so one lacking them all is drawn in every panel. The panels are
  ordered by the first column's values, then the next's, as an axis orders its levels, with a
  missing value (`nil`) last, and fill the rows left to right. With neither `nrow:` nor `ncol:`,
  up to three panels make one row, up to six two rows, up to twelve three, and more a square or
  nearly one; given one of the two, the other is as many as the panels need.

  The panels share each axis's scale, and an axis is drawn only at the panels' outer edges. Free
  scales give each panel a scale of its own, trained on its rows alone, and its own axis.

  ## Options

  #{NimbleOptions.docs(@facet_wrap_options)}

  Raises `ArgumentError` for a column named twice or none at all, or a value that is not a column
  reference, and `NimbleOptions.ValidationError` for an option it does not take or a count that is
  not a positive whole number. When the plot is run, since a layer added later may bring a column,
  it raises `ArgumentError` unless the plot's data or some layer's own table holds every column,
  when `nrow:` and `ncol:` together hold fewer panels than there are, and when no table has a row
  to make a panel from.

      iex> plot =
      ...>   %{"wt" => [2.32, 2.62, 3.44, 2.2], "mpg" => [22.8, 21.0, 18.7, 32.4], "cyl" => [4, 6, 8, 4]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.facet_wrap(:cyl)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:panel)
      [1, 2, 3, 1]
  """
  @spec facet_wrap(t(), column_reference() | [column_reference()], keyword()) :: t()
  def facet_wrap(%__MODULE__{} = plot, facets, options \\ []) when is_list(options) do
    options = NimbleOptions.validate!(options, @facet_wrap_options)

    facet = %Facet.Wrap{
      facets: facet_columns(facets),
      nrow: Keyword.get(options, :nrow, :none),
      ncol: Keyword.get(options, :ncol, :none),
      scales: Keyword.fetch!(options, :scales)
    }

    %{plot | facet: facet}
  end

  @doc """
  Draws the plot in radial coordinates: x is the angle, running clockwise round a full circle from
  12 o'clock, and y the radius, out from the centre. A plot is cartesian until this is called.

  The scales are expanded as cartesian ones are, so the marks keep clear of the circle's edge and
  centre, and the first and last positions on x are a gap apart at 12 o'clock. Each panel is
  square, its grid a circle at each of y's breaks and a spoke at each of x's, on a disc; x's axis
  is drawn round the circle inside the panel, and y's to its left, up the radius at 12 o'clock.
  Nothing is clipped at the panel's edges.

      iex> svg =
      ...>   %{"wt" => [2.32, 2.62, 3.44], "mpg" => [22.8, 21.0, 18.7]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.coord_radial()
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> svg =~ "<polygon"
      true
  """
  @spec coord_radial(t()) :: t()
  def coord_radial(%__MODULE__{} = plot), do: %{plot | coord: %Coord.Radial{}}

  @doc """
  Gives the plot a continuous x scale with the given options, replacing any x scale it had.

  A value outside the limits is missing, so its mark is not drawn: a point, or a bar counted from
  it, and a bar whose ends the limits cut once it is placed. An end at `:infinity` or
  `:neg_infinity` is kept. The scale's name titles the axis whatever `labs/2` says. Raises
  `ArgumentError` for a list of labels without a list of breaks as long; a column on the axis
  that is not numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@continuous_scale_options)}

      iex> frame =
      ...>   %{"wt" => [1.5, 2.6, 3.4, 5.4], "mpg" => [30.4, 21.0, 18.7, 10.4]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_x_continuous(limits: {2, 5})
      ...>   |> Giggly.layer_data()
      iex> Giggly.DataFrame.pull(frame, :x)
      [nil, 2.6, 3.4, nil]
  """
  @spec scale_x_continuous(t(), keyword()) :: t()
  def scale_x_continuous(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: continuous_scale(plot, :x, options, "Plot.scale_x_continuous/2")

  @doc """
  Gives the plot a continuous y scale with the given options, replacing any y scale it had, as
  `scale_x_continuous/2` gives an x scale.

  ## Options

  #{NimbleOptions.docs(@continuous_scale_options)}

      iex> svg =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_y_continuous(name: "Miles per gallon", breaks: [21, 22])
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> {svg =~ ">Miles per gallon</text>", svg =~ ">21</text>", svg =~ ">22</text>"}
      {true, true, true}
  """
  @spec scale_y_continuous(t(), keyword()) :: t()
  def scale_y_continuous(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: continuous_scale(plot, :y, options, "Plot.scale_y_continuous/2")

  @doc """
  Gives the plot a continuous x scale through a base-10 logarithm, replacing any x scale it had,
  as `scale_x_continuous(plot, transform: :log10)` does: each value is placed at its logarithm,
  and the axis marked at powers of ten, or at multiples of them where too few powers fall on it,
  and labelled in data units. Zero is placed at minus infinity, the panel's edge, and a negative
  value is missing.

  ## Options

  #{NimbleOptions.docs(@transformed_scale_options)}

      iex> plot =
      ...>   %{"x" => [1, 10, 100], "y" => [3, 1, 2]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_x_log10()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:x)
      [0.0, 1.0, 2.0]
  """
  @spec scale_x_log10(t(), keyword()) :: t()
  def scale_x_log10(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: transformed_scale(plot, :x, :log10, options, "Plot.scale_x_log10/2")

  @doc """
  Gives the plot a continuous y scale through a base-10 logarithm, replacing any y scale it had,
  as `scale_x_log10/2` gives an x scale.

  ## Options

  #{NimbleOptions.docs(@transformed_scale_options)}

      iex> plot =
      ...>   %{"x" => [3, 1, 2], "y" => [1, 10, 100]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_y_log10()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:y)
      [0.0, 1.0, 2.0]
  """
  @spec scale_y_log10(t(), keyword()) :: t()
  def scale_y_log10(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: transformed_scale(plot, :y, :log10, options, "Plot.scale_y_log10/2")

  @doc """
  Gives the plot a continuous x scale through a square root, replacing any x scale it had, as
  `scale_x_continuous(plot, transform: :sqrt)` does: each value is placed at its square root, and
  the axis marked and labelled in data units. A negative value is missing.

  ## Options

  #{NimbleOptions.docs(@transformed_scale_options)}

      iex> plot =
      ...>   %{"x" => [1, 4, 9], "y" => [3, 1, 2]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_x_sqrt()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:x)
      [1.0, 2.0, 3.0]
  """
  @spec scale_x_sqrt(t(), keyword()) :: t()
  def scale_x_sqrt(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: transformed_scale(plot, :x, :sqrt, options, "Plot.scale_x_sqrt/2")

  @doc """
  Gives the plot a continuous y scale through a square root, replacing any y scale it had, as
  `scale_x_sqrt/2` gives an x scale.

  ## Options

  #{NimbleOptions.docs(@transformed_scale_options)}

      iex> plot =
      ...>   %{"x" => [3, 1, 2], "y" => [1, 4, 9]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_y_sqrt()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:y)
      [1.0, 2.0, 3.0]
  """
  @spec scale_y_sqrt(t(), keyword()) :: t()
  def scale_y_sqrt(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: transformed_scale(plot, :y, :sqrt, options, "Plot.scale_y_sqrt/2")

  @doc """
  Gives the plot a continuous x scale running from high to low, replacing any x scale it had, as
  `scale_x_continuous(plot, transform: :reverse)` does: each value is placed at its negation, and
  the axis marked and labelled in data units.

  ## Options

  #{NimbleOptions.docs(@transformed_scale_options)}

      iex> plot =
      ...>   %{"x" => [1.5, 2.5, 3.5], "y" => [3, 1, 2]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_x_reverse()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:x)
      [-1.5, -2.5, -3.5]
  """
  @spec scale_x_reverse(t(), keyword()) :: t()
  def scale_x_reverse(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: transformed_scale(plot, :x, :reverse, options, "Plot.scale_x_reverse/2")

  @doc """
  Gives the plot a continuous y scale running from high to low, replacing any y scale it had, as
  `scale_x_reverse/2` gives an x scale.

  ## Options

  #{NimbleOptions.docs(@transformed_scale_options)}

      iex> plot =
      ...>   %{"x" => [3, 1, 2], "y" => [1.5, 2.5, 3.5]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_y_reverse()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:y)
      [-1.5, -2.5, -3.5]
  """
  @spec scale_y_reverse(t(), keyword()) :: t()
  def scale_y_reverse(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: transformed_scale(plot, :y, :reverse, options, "Plot.scale_y_reverse/2")

  @doc """
  Gives the plot a discrete x scale with the given options, replacing any x scale it had.

  A discrete axis places each value at its own position, 1, 2, 3 and so on, in order: text
  alphabetically, numbers by size, the missing value last. `limits:` chooses which values it shows
  and in what order; a value it leaves out is missing, so its mark is not drawn, a point or a bar
  counted from it. Each value is named as the column holds it: `factor(cyl)`'s as `4`, `6` and
  `8`, a missing value as `nil`. The scale's name titles the axis whatever `labs/2` says. Raises
  `ArgumentError` for a list of labels not one for each break, or for each limit when no breaks
  are given; a column on the axis that is not discrete is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@discrete_scale_options)}

      iex> frame =
      ...>   %{"class" => ["suv", "compact", "midsize", "suv"], "hwy" => [17, 29, 26, 20]}
      ...>   |> Giggly.Plot.new(%{x: :class, y: :hwy})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_x_discrete(limits: ["suv", "compact"])
      ...>   |> Giggly.layer_data()
      iex> Giggly.DataFrame.pull(frame, :x)
      [1, 2, nil, 1]

  Labels given by value:

      iex> svg =
      ...>   %{"class" => ["suv", "compact"], "hwy" => [17, 29]}
      ...>   |> Giggly.Plot.new(%{x: :class, y: :hwy})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_x_discrete(labels: %{"suv" => "SUV"})
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> {svg =~ ">SUV</text>", svg =~ ">compact</text>"}
      {true, true}
  """
  @spec scale_x_discrete(t(), keyword()) :: t()
  def scale_x_discrete(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: discrete_scale(plot, :x, options, "Plot.scale_x_discrete/2")

  @doc """
  Gives the plot a discrete y scale with the given options, replacing any y scale it had, as
  `scale_x_discrete/2` gives an x scale.

  ## Options

  #{NimbleOptions.docs(@discrete_scale_options)}

      iex> frame =
      ...>   %{"hwy" => [17, 29, 26], "class" => ["suv", "compact", "midsize"]}
      ...>   |> Giggly.Plot.new(%{x: :hwy, y: :class})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_y_discrete(limits: ["suv", "midsize", "compact"])
      ...>   |> Giggly.layer_data()
      iex> Giggly.DataFrame.pull(frame, :y)
      [1, 3, 2]
  """
  @spec scale_y_discrete(t(), keyword()) :: t()
  def scale_y_discrete(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: discrete_scale(plot, :y, options, "Plot.scale_y_discrete/2")

  @doc """
  Gives the plot a date x scale with the given options, replacing any x scale it had.

  A date axis places each date at its days since 1970-01-01 and marks it on calendar boundaries:
  every day, week, month or year, as suits its span, or every step of `date_breaks:`. Its labels
  are written as suits the breaks, or in the format `date_labels:` gives. A value outside the
  limits is missing, so its mark is not drawn. The scale's name titles the axis whatever `labs/2`
  says. Raises `ArgumentError` for an option given beside its `date_` twin, or a list of labels
  without a list of breaks as long; a column on the axis that is not dates is refused when the
  plot is run.

  ## Options

  #{NimbleOptions.docs(@date_scale_options)}

      iex> svg =
      ...>   %{"day" => [~D[2026-09-20], ~D[2026-10-19]], "price" => [0.3, 0.8]}
      ...>   |> Giggly.Plot.new(%{x: :day, y: :price})
      ...>   |> Giggly.Plot.geom_line()
      ...>   |> Giggly.Plot.scale_x_date(date_breaks: [week: 2], date_labels: "%d %b")
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> {svg =~ ">28 Sep</text>", svg =~ ">12 Oct</text>"}
      {true, true}
  """
  @spec scale_x_date(t(), keyword()) :: t()
  def scale_x_date(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: date_scale(plot, :x, options, "Plot.scale_x_date/2")

  @doc """
  Gives the plot a date y scale with the given options, replacing any y scale it had, as
  `scale_x_date/2` gives an x scale.

  ## Options

  #{NimbleOptions.docs(@date_scale_options)}

      iex> frame =
      ...>   %{"price" => [0.3, 0.8, 0.5], "day" => [~D[2026-09-20], ~D[2026-10-19], ~D[2026-10-01]]}
      ...>   |> Giggly.Plot.new(%{x: :price, y: :day})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_y_date(limits: {~D[2026-10-01], nil})
      ...>   |> Giggly.layer_data()
      iex> Giggly.DataFrame.pull(frame, :y)
      [nil, 20745.0, 20727.0]
  """
  @spec scale_y_date(t(), keyword()) :: t()
  def scale_y_date(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do: date_scale(plot, :y, options, "Plot.scale_y_date/2")

  @doc """
  Gives the plot a discrete colour scale of the colours given, replacing any colour scale it had.

  `values:` gives the colours, a list handed to the values in order, or a map from a value to its
  colour. The legend shows a key for each value the scale shows, labelled. Raises
  `NimbleOptions.ValidationError` for an option it does not take or a colour CSS does not define,
  and `ArgumentError` for a list of labels not one for each break or limit given; a column of
  numbers, or more values than a list has colours, is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@manual_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "cyl" => ["6", "4", "8"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_color_manual(values: %{"4" => "steelblue", "6" => "orange", "8" => "red"})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#FFA500", "#4682B4", "#FF0000"]
  """
  @spec scale_color_manual(t(), keyword()) :: t()
  def scale_color_manual(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :color,
      options,
      @manual_scale_options,
      "Plot.scale_color_manual/2",
      &manual_scale/1
    )
  end

  @doc """
  Gives the plot a discrete fill scale of the colours given, replacing any fill scale it had, as
  `scale_color_manual/2` gives a colour scale.

  ## Options

  #{NimbleOptions.docs(@manual_scale_options)}

      iex> plot =
      ...>   %{"drv" => ["f", "r"], "hwy" => [28, 19]}
      ...>   |> Giggly.Plot.new(%{x: :drv, y: :hwy, fill: :drv})
      ...>   |> Giggly.Plot.geom_col()
      ...>   |> Giggly.Plot.scale_fill_manual(values: ["steelblue", "orange"])
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:fill)
      ["#4682B4", "#FFA500"]
  """
  @spec scale_fill_manual(t(), keyword()) :: t()
  def scale_fill_manual(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :fill,
      options,
      @manual_scale_options,
      "Plot.scale_fill_manual/2",
      &manual_scale/1
    )
  end

  @doc """
  Gives the plot a discrete colour scale of hues spaced evenly round the colour wheel, all of one
  chroma and luminance, replacing any colour scale it had.

  A discrete column mapped to colour gets these hues by default; the options choose others.
  Raises `NimbleOptions.ValidationError` for an option it does not take or a value it cannot use,
  and `ArgumentError` for a list of labels not one for each break or limit given; a column of
  numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@hue_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "cyl" => ["6", "4", "8"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_color_hue(luminance: 40, chroma: 30)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#3A6845", "#7F5351", "#515E7F"]
  """
  @spec scale_color_hue(t(), keyword()) :: t()
  def scale_color_hue(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do:
      legend_scale(
        plot,
        :color,
        options,
        @hue_scale_options,
        "Plot.scale_color_hue/2",
        &hue_scale/1
      )

  @doc """
  Gives the plot a discrete fill scale of hues spaced evenly round the colour wheel, replacing any
  fill scale it had, as `scale_color_hue/2` gives a colour scale.

  ## Options

  #{NimbleOptions.docs(@hue_scale_options)}

      iex> plot =
      ...>   %{"cyl" => ["6", "4", "8"], "mpg" => [19.7, 26.7, 15.1]}
      ...>   |> Giggly.Plot.new(%{x: :cyl, y: :mpg, fill: :cyl})
      ...>   |> Giggly.Plot.geom_col()
      ...>   |> Giggly.Plot.scale_fill_hue(direction: -1)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:fill)
      ["#00BA38", "#619CFF", "#F8766D"]
  """
  @spec scale_fill_hue(t(), keyword()) :: t()
  def scale_fill_hue(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do:
      legend_scale(
        plot,
        :fill,
        options,
        @hue_scale_options,
        "Plot.scale_fill_hue/2",
        &hue_scale/1
      )

  @doc """
  Gives the plot a discrete colour scale of greys, replacing any colour scale it had.

  The greys run from `start:` to `end:`, spaced evenly to the eye; a missing value is red.
  Raises `NimbleOptions.ValidationError` for an option it does not take or a grey's level outside
  0 to 1, and `ArgumentError` for a list of labels not one for each break or limit given; a column
  of numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@gray_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "cyl" => ["6", "4", "8"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_color_gray()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#989898", "#333333", "#CCCCCC"]
  """
  @spec scale_color_gray(t(), keyword()) :: t()
  def scale_color_gray(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do:
      legend_scale(
        plot,
        :color,
        options,
        @gray_scale_options,
        "Plot.scale_color_gray/2",
        &gray_scale/1
      )

  @doc """
  Gives the plot a discrete fill scale of greys, replacing any fill scale it had, as
  `scale_color_gray/2` gives a colour scale.

  ## Options

  #{NimbleOptions.docs(@gray_scale_options)}

      iex> plot =
      ...>   %{"drv" => ["f", "r"], "hwy" => [28, 19]}
      ...>   |> Giggly.Plot.new(%{x: :drv, y: :hwy, fill: :drv})
      ...>   |> Giggly.Plot.geom_col()
      ...>   |> Giggly.Plot.scale_fill_gray(start: 0, end: 1)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:fill)
      ["#000000", "#FFFFFF"]
  """
  @spec scale_fill_gray(t(), keyword()) :: t()
  def scale_fill_gray(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do:
      legend_scale(
        plot,
        :fill,
        options,
        @gray_scale_options,
        "Plot.scale_fill_gray/2",
        &gray_scale/1
      )

  @doc """
  Gives the plot a discrete colour scale from a viridis palette, replacing any colour scale it had.

  The palettes change evenly to the eye, in colour and in grey, and are made to be read by people
  with the common forms of colour blindness. The values take colours spaced evenly from `begin:`
  to `end:` of the palette `option:`, in order. An ordered factor mapped to colour gets
  this scale by default; a missing value has no colour, so its mark is not drawn, unless
  `na_value:` gives one. Raises `NimbleOptions.ValidationError` for an option it does not take or
  a value it cannot use, and `ArgumentError` for a list of labels not one for each break or limit
  given; a column of numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@discrete_viridis_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "cyl" => ["6", "4", "8"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_color_viridis_d(option: :magma)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#B63679", "#000004", "#FCFDBF"]
  """
  @spec scale_color_viridis_d(t(), keyword()) :: t()
  def scale_color_viridis_d(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do:
      legend_scale(
        plot,
        :color,
        options,
        @discrete_viridis_scale_options,
        "Plot.scale_color_viridis_d/2",
        &discrete_viridis_scale/1
      )

  @doc """
  Gives the plot a discrete fill scale from a viridis palette, replacing any fill scale it had, as
  `scale_color_viridis_d/2` gives a colour scale.

  ## Options

  #{NimbleOptions.docs(@discrete_viridis_scale_options)}

      iex> plot =
      ...>   %{"drv" => ["f", "r"], "hwy" => [28, 19]}
      ...>   |> Giggly.Plot.new(%{x: :drv, y: :hwy, fill: :drv})
      ...>   |> Giggly.Plot.geom_col()
      ...>   |> Giggly.Plot.scale_fill_viridis_d(direction: -1)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:fill)
      ["#FDE725", "#440154"]
  """
  @spec scale_fill_viridis_d(t(), keyword()) :: t()
  def scale_fill_viridis_d(%__MODULE__{} = plot, options \\ []) when is_list(options),
    do:
      legend_scale(
        plot,
        :fill,
        options,
        @discrete_viridis_scale_options,
        "Plot.scale_fill_viridis_d/2",
        &discrete_viridis_scale/1
      )

  @doc """
  Gives the plot a discrete colour scale, replacing any colour scale it had: hues spaced evenly
  round the colour wheel, as a discrete column gets by default, or the colours of `palette:`, in
  order.

  Raises `NimbleOptions.ValidationError` for an option it does not take or a colour CSS does not
  define, and `ArgumentError` for a list of labels not one for each break or limit given; a column
  of numbers, or more values than the palette has colours, is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@discrete_color_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "cyl" => ["6", "4", "8"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_color_discrete(palette: ["steelblue", "orange", "red"])
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#FFA500", "#4682B4", "#FF0000"]
  """
  @spec scale_color_discrete(t(), keyword()) :: t()
  def scale_color_discrete(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :color,
      options,
      @discrete_color_scale_options,
      "Plot.scale_color_discrete/2",
      &discrete_color_scale/1
    )
  end

  @doc """
  Gives the plot a discrete fill scale, replacing any fill scale it had, as
  `scale_color_discrete/2` gives a colour scale.

  ## Options

  #{NimbleOptions.docs(@discrete_color_scale_options)}

      iex> plot =
      ...>   %{"drv" => ["f", "r", "4"], "hwy" => [28, 19, 20]}
      ...>   |> Giggly.Plot.new(%{x: :drv, y: :hwy, fill: :drv})
      ...>   |> Giggly.Plot.geom_col()
      ...>   |> Giggly.Plot.scale_fill_discrete(limits: ["f", "r"])
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:fill)
      ["#F8766D", "#00BFC4", "#7F7F7F"]
  """
  @spec scale_fill_discrete(t(), keyword()) :: t()
  def scale_fill_discrete(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :fill,
      options,
      @discrete_color_scale_options,
      "Plot.scale_fill_discrete/2",
      &discrete_color_scale/1
    )
  end

  @doc """
  Gives the plot a continuous colour scale, a gradient from `low:` to `high:`, replacing any colour
  scale it had.

  Each value takes the colour as far along the gradient as the value is through the limits,
  blended in CIE L*a*b*, which spaces colours evenly to the eye; its guide is a colour bar unless
  `guide:` names another. Raises `NimbleOptions.ValidationError` for an option it does not take, a
  colour CSS does not define or one with an alpha of its own, and `ArgumentError` for a list of
  labels without a list of breaks as long; a column that is not numbers is refused when the plot is
  run.

  ## Options

  #{NimbleOptions.docs(@gradient_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [1, 2, 3]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :hp})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_color_gradient(low: "white", high: "black")
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#FFFFFF", "#777777", "#000000"]
  """
  @spec scale_color_gradient(t(), keyword()) :: t()
  def scale_color_gradient(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :color,
      options,
      @gradient_scale_options,
      "Plot.scale_color_gradient/2",
      &gradient_scale/1
    )
  end

  @doc """
  Gives the plot a continuous fill scale, a gradient from `low:` to `high:`, replacing any fill
  scale it had, as `scale_color_gradient/2` gives a colour scale.

  ## Options

  #{NimbleOptions.docs(@gradient_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [0, 5, 10]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, fill: :hp})
      ...>   |> Giggly.Plot.geom_col()
      ...>   |> Giggly.Plot.scale_fill_gradient(low: "white", high: "steelblue")
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:fill)
      ["#FFFFFF", "#A7BED9", "#4682B4"]
  """
  @spec scale_fill_gradient(t(), keyword()) :: t()
  def scale_fill_gradient(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :fill,
      options,
      @gradient_scale_options,
      "Plot.scale_fill_gradient/2",
      &gradient_scale/1
    )
  end

  @doc """
  Gives the plot a continuous colour scale diverging from `mid:` at `midpoint:`, toward `low:`
  below it and `high:` above, replacing any colour scale it had.

  A value's colour is as far toward its side's end as the value is from the midpoint, the end of
  the limits further from the midpoint taking its colour in full and the nearer only as far as it
  reaches; its guide is a colour bar unless `guide:` names another. Raises
  `NimbleOptions.ValidationError` for an option it does not take, a colour CSS does not define or
  one with an alpha of its own, and `ArgumentError` for a list of labels without a list of breaks
  as long; a column that is not numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@gradient2_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "change" => [-2, 0, 1]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :change})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_color_gradient2()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#832424", "#FFFFFF", "#A197CC"]
  """
  @spec scale_color_gradient2(t(), keyword()) :: t()
  def scale_color_gradient2(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :color,
      options,
      @gradient2_scale_options,
      "Plot.scale_color_gradient2/2",
      &gradient2_scale/1
    )
  end

  @doc """
  Gives the plot a continuous fill scale diverging from `mid:` at `midpoint:`, replacing any fill
  scale it had, as `scale_color_gradient2/2` gives a colour scale.

  ## Options

  #{NimbleOptions.docs(@gradient2_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [0, 5, 10]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, fill: :hp})
      ...>   |> Giggly.Plot.geom_col()
      ...>   |> Giggly.Plot.scale_fill_gradient2(midpoint: 4)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:fill)
      ["#B26D65", "#E0DBEE", "#3A3A98"]
  """
  @spec scale_fill_gradient2(t(), keyword()) :: t()
  def scale_fill_gradient2(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :fill,
      options,
      @gradient2_scale_options,
      "Plot.scale_fill_gradient2/2",
      &gradient2_scale/1
    )
  end

  @doc """
  Gives the plot a continuous colour scale, a gradient through the colours of `colors:`, replacing
  any colour scale it had.

  The colours are spaced evenly over the limits, the first at the low end and the last at the high,
  and blended in CIE L*a*b* between neighbours; its guide is a colour bar unless `guide:` names
  another. Raises `NimbleOptions.ValidationError` for an option it does not take, a colour CSS does
  not define or one with an alpha of its own, and `ArgumentError` for a list of labels without a
  list of breaks as long; a column that is not numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@gradientn_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [0, 5, 10]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :hp})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_color_gradientn(colors: ["red", "yellow", "blue"])
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#FF0000", "#FFFF00", "#0000FF"]
  """
  @spec scale_color_gradientn(t(), keyword()) :: t()
  def scale_color_gradientn(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :color,
      options,
      @gradientn_scale_options,
      "Plot.scale_color_gradientn/2",
      &gradientn_scale/1
    )
  end

  @doc """
  Gives the plot a continuous fill scale, a gradient through the colours of `colors:`, replacing
  any fill scale it had, as `scale_color_gradientn/2` gives a colour scale.

  ## Options

  #{NimbleOptions.docs(@gradientn_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [0, 5, 10]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, fill: :hp})
      ...>   |> Giggly.Plot.geom_col()
      ...>   |> Giggly.Plot.scale_fill_gradientn(colors: ["#FEE0D2", "#FC9272", "#DE2D26"])
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:fill)
      ["#FEE0D2", "#FC9272", "#DE2D26"]
  """
  @spec scale_fill_gradientn(t(), keyword()) :: t()
  def scale_fill_gradientn(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :fill,
      options,
      @gradientn_scale_options,
      "Plot.scale_fill_gradientn/2",
      &gradientn_scale/1
    )
  end

  @doc """
  Gives the plot a continuous colour scale, replacing any colour scale it had: a gradient from
  `#132B43` to `#56B1F7`, as a column of numbers gets by default, or through the colours of
  `palette:`, spaced evenly over the limits.

  Raises `NimbleOptions.ValidationError` for an option it does not take, a colour CSS does not
  define or one with an alpha of its own, and `ArgumentError` for a list of labels without a list
  of breaks as long; a column that is not numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@continuous_color_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [5, 12, 0]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :hp})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_color_continuous(limits: {0, 10})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#336A98", "#7F7F7F", "#132B43"]
  """
  @spec scale_color_continuous(t(), keyword()) :: t()
  def scale_color_continuous(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :color,
      options,
      @continuous_color_scale_options,
      "Plot.scale_color_continuous/2",
      &continuous_color_scale/1
    )
  end

  @doc """
  Gives the plot a continuous fill scale, replacing any fill scale it had, as
  `scale_color_continuous/2` gives a colour scale.

  ## Options

  #{NimbleOptions.docs(@continuous_color_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [0, 5, 10]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, fill: :hp})
      ...>   |> Giggly.Plot.geom_col()
      ...>   |> Giggly.Plot.scale_fill_continuous(palette: ["#FEE0D2", "#FC9272", "#DE2D26"])
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:fill)
      ["#FEE0D2", "#FC9272", "#DE2D26"]
  """
  @spec scale_fill_continuous(t(), keyword()) :: t()
  def scale_fill_continuous(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :fill,
      options,
      @continuous_color_scale_options,
      "Plot.scale_fill_continuous/2",
      &continuous_color_scale/1
    )
  end

  @doc """
  Gives the plot a continuous colour scale, a gradient through a viridis palette, replacing any
  colour scale it had.

  The gradient runs through six colours spaced evenly from `begin:` to `end:` of the palette
  `option:`, blended in CIE L*a*b* between neighbours, as `scale_color_gradientn/2` blends its
  colours; its guide is a colour bar unless `guide:` names another. Raises
  `NimbleOptions.ValidationError` for an option it does not take or a value it cannot use, and
  `ArgumentError` for a list of labels without a list of breaks as long; a column that is not
  numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@continuous_viridis_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [0, 5, 10]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :hp})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_color_viridis_c()
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:color)
      ["#440154", "#2B9089", "#FDE725"]
  """
  @spec scale_color_viridis_c(t(), keyword()) :: t()
  def scale_color_viridis_c(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :color,
      options,
      @continuous_viridis_scale_options,
      "Plot.scale_color_viridis_c/2",
      &continuous_viridis_scale/1
    )
  end

  @doc """
  Gives the plot a continuous fill scale, a gradient through a viridis palette, replacing any fill
  scale it had, as `scale_color_viridis_c/2` gives a colour scale.

  ## Options

  #{NimbleOptions.docs(@continuous_viridis_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [0, 5, 10]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, fill: :hp})
      ...>   |> Giggly.Plot.geom_col()
      ...>   |> Giggly.Plot.scale_fill_viridis_c(option: :plasma, begin: 0.2)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:fill)
      ["#6A00A8", "#E06663", "#F0F921"]
  """
  @spec scale_fill_viridis_c(t(), keyword()) :: t()
  def scale_fill_viridis_c(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :fill,
      options,
      @continuous_viridis_scale_options,
      "Plot.scale_fill_viridis_c/2",
      &continuous_viridis_scale/1
    )
  end

  @doc """
  Gives the plot a continuous alpha scale, replacing any alpha scale it had.

  Each value is drawn as opaque as it is far from the first of `range:` to the second through the
  limits; its guide is a legend unless `guide:` says otherwise. Raises
  `NimbleOptions.ValidationError` for an option it does not take or a value it cannot use, an
  opacity outside 0 to 1 or a `guide:` of `:colorbar`, and `ArgumentError` for a list of labels
  without a list of breaks as long; a column that is not numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@continuous_alpha_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [1, 2, 3]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, alpha: :hp})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_alpha_continuous(range: {0, 1})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:alpha)
      [0.0, 0.5, 1.0]
  """
  @spec scale_alpha_continuous(t(), keyword()) :: t()
  def scale_alpha_continuous(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :alpha,
      options,
      @continuous_alpha_scale_options,
      "Plot.scale_alpha_continuous/2",
      &continuous_alpha_scale/1
    )
  end

  @doc """
  Gives the plot a discrete alpha scale, replacing any alpha scale it had.

  The values' opacities are spaced evenly from the first of `range:` to the second, in order; its
  guide is a legend unless `guide:` says otherwise. Raises `NimbleOptions.ValidationError` for an
  option it does not take or a value it cannot use, an opacity outside 0 to 1 or a `guide:` of
  `:colorbar`, and `ArgumentError` for a list of labels not one for each break or limit given; a
  column of numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@discrete_alpha_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "cyl" => ["6", "4", "8"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, alpha: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_alpha_discrete(range: {0.25, 0.75})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:alpha)
      [0.5, 0.25, 0.75]
  """
  @spec scale_alpha_discrete(t(), keyword()) :: t()
  def scale_alpha_discrete(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :alpha,
      options,
      @discrete_alpha_scale_options,
      "Plot.scale_alpha_discrete/2",
      &discrete_alpha_scale/1
    )
  end

  @doc """
  Gives the plot a continuous size scale, replacing any size scale it had.

  Each value is drawn at a size between the first of `range:` and the second, in millimetres, by
  area: its size's square is as far between theirs as the value is through the limits, so a
  point's area grows with the value. Its guide is a legend unless `guide:` says otherwise. A value
  outside the limits, or missing, is not drawn. Raises `NimbleOptions.ValidationError` for an
  option it does not take or a value it cannot use, a size below 0 or a `guide:` of `:colorbar`,
  and `ArgumentError` for a list of labels without a list of breaks as long; a column that is not
  numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@continuous_size_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [110, 93, 175]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, size: :hp})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_size_continuous(range: {1, 10})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:size)
      [5.097887617642688, 1.0, 10.0]
  """
  @spec scale_size_continuous(t(), keyword()) :: t()
  def scale_size_continuous(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :size,
      options,
      @continuous_size_scale_options,
      "Plot.scale_size_continuous/2",
      &continuous_size_scale/1
    )
  end

  @doc """
  Gives the plot a continuous size scale that draws 0 at size 0, replacing any size scale it had.

  Each value is drawn at a size, in millimetres, whose square is as far toward the square of
  `max_size:` as the value is toward the high end of the limits from 0, so a point's area is in
  proportion to the value, and the high end is drawn at `max_size:`. A value below 0 is drawn as
  large as its distance from 0. Its guide is a legend unless `guide:` says otherwise. Raises
  `NimbleOptions.ValidationError` for an option it does not take or a value it cannot use, a size
  below 0 or a `guide:` of `:colorbar`, and `ArgumentError` for a list of labels without a list of
  breaks as long; a column that is not numbers, and a value below limits whose high end is 0,
  which would be drawn infinitely large, are refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@area_size_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [110, 93, 175]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, size: :hp})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_size_area(max_size: 10)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:size)
      [7.928249671720918, 7.289914755527471, 10.0]
  """
  @spec scale_size_area(t(), keyword()) :: t()
  def scale_size_area(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :size,
      options,
      @area_size_scale_options,
      "Plot.scale_size_area/2",
      &area_size_scale/1
    )
  end

  @doc """
  Gives the plot a continuous size scale by width, replacing any size scale it had.

  Each value is drawn at a size between the first of `range:` and the second, in millimetres, as
  far between them as the value is through the limits, so a point's width, not its area, grows
  with the value. Its guide is a legend unless `guide:` says otherwise. A value outside the limits,
  or missing, is not drawn. Raises `NimbleOptions.ValidationError` for an option it does not take
  or a value it cannot use, a size below 0 or a `guide:` of `:colorbar`, and `ArgumentError` for a
  list of labels without a list of breaks as long; a column that is not numbers is refused when
  the plot is run.

  ## Options

  #{NimbleOptions.docs(@radius_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "hp" => [110, 93, 175]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, size: :hp})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_radius(range: {2, 8})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:size)
      [3.2439024390243905, 2.0, 8.0]
  """
  @spec scale_radius(t(), keyword()) :: t()
  def scale_radius(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :size,
      options,
      @radius_scale_options,
      "Plot.scale_radius/2",
      &radius_scale/1
    )
  end

  @doc """
  Gives the plot a discrete size scale, replacing any size scale it had.

  The values are drawn at sizes from the first of `range:` to the second, in millimetres, in
  order, their squares, and so a point's area, evenly spaced. Its guide is a legend unless `guide:`
  says otherwise. Raises `NimbleOptions.ValidationError` for an option it does not take or a value
  it cannot use, a size below 0 or a `guide:` of `:colorbar`, and `ArgumentError` for a list of
  labels not one for each break or limit given; a column of numbers is refused when the plot is
  run.

  ## Options

  #{NimbleOptions.docs(@discrete_size_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "cyl" => ["6", "4", "8"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, size: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_size_discrete(range: {1, 3})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:size)
      [2.23606797749979, 1.0, 3.0]
  """
  @spec scale_size_discrete(t(), keyword()) :: t()
  def scale_size_discrete(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :size,
      options,
      @discrete_size_scale_options,
      "Plot.scale_size_discrete/2",
      &discrete_size_scale/1
    )
  end

  @doc """
  Gives the plot a discrete shape scale, replacing any shape scale it had.

  The values are drawn in six shapes, in order, easy to tell apart: solid, `:circle_small`,
  `:triangle`, `:square`, `:plus`, `:square_cross` and `:asterisk`, or, with `solid: false`, the
  first three open, `:circle_open`, `:triangle_open` and `:square_open`. Shapes have no order, so a
  shape scale is always discrete. Its guide is a legend unless `guide:` says otherwise. Raises
  `NimbleOptions.ValidationError` for an option it does not take or a value it cannot use, a
  `guide:` of `:colorbar` among them, and `ArgumentError` for a list of labels not one for each
  break or limit given; a continuous column, or more than six values, is refused when the plot is
  run, and `scale_shape_manual/2` gives as many shapes as a scale has values.

  ## Options

  #{NimbleOptions.docs(@discrete_shape_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "cyl" => ["6", "4", "8"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, shape: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_shape_discrete(solid: false)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:shape)
      [:triangle_open, :circle_open, :square_open]
  """
  @spec scale_shape_discrete(t(), keyword()) :: t()
  def scale_shape_discrete(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :shape,
      options,
      @discrete_shape_scale_options,
      "Plot.scale_shape_discrete/2",
      &discrete_shape_scale/1
    )
  end

  @doc """
  Gives the plot a discrete shape scale of the shapes given, replacing any shape scale it had.

  `values:` gives the shapes, each by name or by its number, as `geom_point/3` names them: a list
  handed to the values in order, or a map from a value to its shape. The legend shows a key for
  each value the scale shows, labelled. Raises `NimbleOptions.ValidationError` for an option it
  does not take or a value it cannot use, a shape no point is drawn in or a `guide:` of
  `:colorbar` among them, and `ArgumentError` for a list of labels not one for each break or limit
  given; a continuous column, or more values than a list has shapes, is refused when the plot is
  run.

  ## Options

  #{NimbleOptions.docs(@manual_shape_scale_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.32, 3.44], "mpg" => [21.0, 22.8, 18.7], "cyl" => ["6", "4", "8"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, shape: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.scale_shape_manual(values: %{"4" => 21, "6" => :diamond, "8" => 4})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:shape)
      [:diamond, :circle_filled, :cross]
  """
  @spec scale_shape_manual(t(), keyword()) :: t()
  def scale_shape_manual(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :shape,
      options,
      @manual_shape_scale_options,
      "Plot.scale_shape_manual/2",
      &manual_scale/1
    )
  end

  @doc """
  Gives the plot a discrete line type scale, replacing any line type scale it had.

  The values are drawn in 13 line types, in order, easy to tell apart: solid, then the dash
  patterns `{2, 2}`, `{4, 2}`, `{4, 4}`, `{1, 3}`, `{1, 3, 4, 3}`, `{7, 3}`, `{2, 2, 6, 2}`,
  `{1, 2, 2, 2, 3, 2, 4, 2}`, `{15, 2, 8, 2}`, `{15, 4, 4, 4, 8, 4, 4, 4}`,
  `{2, 2, 4, 2, 8, 2, 15, 2}` and `{15, 1}`. Line types have no order, so a line type scale is
  always discrete. Its guide is a legend unless `guide:` says otherwise. Raises
  `NimbleOptions.ValidationError` for an option it does not take or a value it cannot use, a
  `guide:` of `:colorbar` among them, and `ArgumentError` for a list of labels not one for each
  break or limit given; a continuous column, or more than 13 values, is refused when the plot is
  run, and `scale_linetype_manual/2` gives as many line types as a scale has values.

  ## Options

  #{NimbleOptions.docs(@discrete_linetype_scale_options)}

      iex> plot =
      ...>   %{"month" => [1, 2, 1, 2], "value" => [0.2, 0.4, 0.9, 0.7], "series" => ["pce", "pce", "pop", "pop"]}
      ...>   |> Giggly.Plot.new(%{x: :month, y: :value, linetype: :series})
      ...>   |> Giggly.Plot.geom_line()
      ...>   |> Giggly.Plot.scale_linetype_discrete(limits: ["pop", "pce"])
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:linetype)
      [{2, 2}, {2, 2}, {}, {}]
  """
  @spec scale_linetype_discrete(t(), keyword()) :: t()
  def scale_linetype_discrete(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :linetype,
      options,
      @discrete_linetype_scale_options,
      "Plot.scale_linetype_discrete/2",
      &discrete_linetype_scale/1
    )
  end

  @doc """
  Gives the plot a discrete line type scale of the line types given, replacing any line type scale
  it had.

  `values:` gives the line types, each by name, by its number or as a dash pattern, as
  `geom_line/3`'s `linetype:` takes one: a list handed to the values in order, or a map from a
  value to its line type. The legend shows a key for each value the scale shows, labelled. Raises
  `NimbleOptions.ValidationError` for an option it does not take or a value it cannot use, a line
  type no line is drawn in or a `guide:` of `:colorbar` among them, and `ArgumentError` for a list
  of labels not one for each break or limit given; a continuous column, or more values than a list
  has line types, is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@manual_linetype_scale_options)}

      iex> plot =
      ...>   %{"month" => [1, 2, 1, 2], "value" => [0.2, 0.4, 0.9, 0.7], "series" => ["pce", "pce", "pop", "pop"]}
      ...>   |> Giggly.Plot.new(%{x: :month, y: :value, linetype: :series})
      ...>   |> Giggly.Plot.geom_line()
      ...>   |> Giggly.Plot.scale_linetype_manual(values: %{"pce" => :dotted, "pop" => {3, 1}})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:linetype)
      [{1, 3}, {1, 3}, {3, 1}, {3, 1}]
  """
  @spec scale_linetype_manual(t(), keyword()) :: t()
  def scale_linetype_manual(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :linetype,
      options,
      @manual_linetype_scale_options,
      "Plot.scale_linetype_manual/2",
      &manual_scale/1
    )
  end

  @doc """
  Gives the plot a continuous line width scale, replacing any line width scale it had.

  Each value's line is drawn at a width between the first of `range:` and the second, in
  millimetres, as far between them as the value is through the limits. A line whose width changes
  along it is drawn a segment from each row to the next, each as wide as the row it starts from.
  Its guide is a legend unless `guide:` says otherwise. A value outside the limits, or missing,
  draws no line. Raises `NimbleOptions.ValidationError` for an option it does not take or a value
  it cannot use, a width below 0 or a `guide:` of `:colorbar`, and `ArgumentError` for a list of
  labels without a list of breaks as long; a column that is not numbers is refused when the plot
  is run.

  ## Options

  #{NimbleOptions.docs(@continuous_linewidth_scale_options)}

      iex> plot =
      ...>   %{"month" => [1, 2, 3], "unemploy" => [2944, 2945, 2958], "uempmed" => [4.5, 4.7, 4.6]}
      ...>   |> Giggly.Plot.new(%{x: :month, y: :unemploy, linewidth: :uempmed})
      ...>   |> Giggly.Plot.geom_line()
      ...>   |> Giggly.Plot.scale_linewidth_continuous(range: {0, 4})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:linewidth)
      [0.0, 4.0, 1.9999999999999911]
  """
  @spec scale_linewidth_continuous(t(), keyword()) :: t()
  def scale_linewidth_continuous(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :linewidth,
      options,
      @continuous_linewidth_scale_options,
      "Plot.scale_linewidth_continuous/2",
      &continuous_linewidth_scale/1
    )
  end

  @doc """
  Gives the plot a discrete line width scale, replacing any line width scale it had.

  The values' lines are drawn at widths spaced evenly from the first of `range:` to the second, in
  millimetres, in order. Its guide is a legend unless `guide:` says otherwise. Raises
  `NimbleOptions.ValidationError` for an option it does not take or a value it cannot use, a width
  below 0 or a `guide:` of `:colorbar`, and `ArgumentError` for a list of labels not one for each
  break or limit given; a column of numbers is refused when the plot is run.

  ## Options

  #{NimbleOptions.docs(@discrete_linewidth_scale_options)}

      iex> plot =
      ...>   %{"class" => ["suv", "compact", "pickup"], "hwy" => [18, 28, 16]}
      ...>   |> Giggly.Plot.new(%{x: :class, y: :hwy, linewidth: :class})
      ...>   |> Giggly.Plot.geom_col(colour: "black")
      ...>   |> Giggly.Plot.scale_linewidth_discrete(range: {1, 3})
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:linewidth)
      [3.0, 1.0, 2.0]
  """
  @spec scale_linewidth_discrete(t(), keyword()) :: t()
  def scale_linewidth_discrete(%__MODULE__{} = plot, options \\ []) when is_list(options) do
    legend_scale(
      plot,
      :linewidth,
      options,
      @discrete_linewidth_scale_options,
      "Plot.scale_linewidth_discrete/2",
      &discrete_linewidth_scale/1
    )
  end

  @doc """
  Gives the plot an x scale from `low` to `high`, replacing any x scale it had: a continuous scale
  for numbers, as `scale_x_continuous(plot, limits: {low, high})` gives, or a date scale for dates,
  as `scale_x_date(plot, limits: {low, high})` gives; `nil` leaves an end to the data. Numbers
  given high to low run the axis from high to low, as `transform: :reverse` runs it, each value
  placed at its negation; dates given so name the same axis as low to high. A discrete axis's
  limits are a list of its values, which `xlim/2` takes.

      iex> plot =
      ...>   %{"wt" => [1.5, 2.6, 3.4], "mpg" => [30.4, 21.0, 18.7]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.xlim(nil, 4)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:x)
      [1.5, 2.6, 3.4]

  A reversed axis:

      iex> plot =
      ...>   %{"mpg" => [21.0, 22.8, 18.7], "wt" => [2.62, 2.32, 3.44]}
      ...>   |> Giggly.Plot.new(%{x: :mpg, y: :wt})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.xlim(20, 15)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:x)
      [nil, nil, -18.7]

  Dates:

      iex> plot =
      ...>   %{"day" => [~D[2024-01-01], ~D[2024-01-11]], "value" => [1, 2]}
      ...>   |> Giggly.Plot.new(%{x: :day, y: :value})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.xlim(~D[2024-01-05], nil)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:x)
      [nil, 19733.0]
  """
  @spec xlim(t(), number() | Date.t() | nil, number() | Date.t() | nil) :: t()
  def xlim(%__MODULE__{} = plot, low, high), do: lims(plot, x: {low, high})

  @doc """
  Gives the plot a discrete x scale showing `values`, in the order given, replacing any x scale it
  had, as `scale_x_discrete(plot, limits: values)` does.

      iex> plot =
      ...>   %{"cut" => ["Fair", "Good", "Ideal"], "price" => [3000, 4000, 3500]}
      ...>   |> Giggly.Plot.new(%{x: :cut, y: :price})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.xlim(["Ideal", "Fair"])
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:x)
      [2, nil, 1]
  """
  @spec xlim(t(), list()) :: t()
  def xlim(%__MODULE__{} = plot, values) when is_list(values), do: lims(plot, x: values)

  @doc """
  Gives the plot a y scale from `low` to `high`, replacing any y scale it had, as `xlim/3` gives
  an x scale.

      iex> plot =
      ...>   %{"wt" => [1.5, 2.6, 3.4], "mpg" => [30.4, 21.0, 18.7]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.ylim(15, 25)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:y)
      [nil, 21.0, 18.7]
  """
  @spec ylim(t(), number() | Date.t() | nil, number() | Date.t() | nil) :: t()
  def ylim(%__MODULE__{} = plot, low, high), do: lims(plot, y: {low, high})

  @doc """
  Gives the plot a discrete y scale showing `values`, in the order given, replacing any y scale it
  had, as `xlim/2` gives an x scale.

      iex> plot =
      ...>   %{"price" => [3000, 4000, 3500], "cut" => ["Fair", "Good", "Ideal"]}
      ...>   |> Giggly.Plot.new(%{x: :price, y: :cut})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.ylim(["Good", "Fair"])
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:y)
      [2, 1, nil]
  """
  @spec ylim(t(), list()) :: t()
  def ylim(%__MODULE__{} = plot, values) when is_list(values), do: lims(plot, y: values)

  @doc """
  Gives the plot a scale with the given limits for each axis named, replacing any scale it had for
  it, as `xlim/3`, `xlim/2`, `ylim/3` and `ylim/2` do: `{low, high}` for a continuous or a date
  scale, a list of values for a discrete one.

  ## Options

  #{NimbleOptions.docs(@lims_options)}

      iex> plot =
      ...>   %{"wt" => [1.5, 2.6, 3.4], "mpg" => [30.4, 21.0, 18.7]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.lims(x: {2, 4}, y: {15, 25})
      iex> frame = Giggly.layer_data(plot)
      iex> {Giggly.DataFrame.pull(frame, :x), Giggly.DataFrame.pull(frame, :y)}
      {[nil, 2.6, 3.4], [nil, 21.0, 18.7]}
  """
  @spec lims(t(), keyword()) :: t()
  def lims(%__MODULE__{} = plot, options) when is_list(options) do
    options
    |> Aesthetics.canonicalize()
    |> NimbleOptions.validate!(@lims_options)
    |> Enum.reduce(plot, fn {aesthetic, limits}, limited ->
      put_scale(limited, aesthetic, limits_scale(aesthetic, limits))
    end)
  end

  # The scale limits give an aesthetic: on an axis, `axis_limits_scale/1`'s; for any other, the
  # scale its discrete or continuous scale function gives with those limits alone.
  defp limits_scale(aesthetic, limits) when aesthetic in [:x, :y], do: axis_limits_scale(limits)

  defp limits_scale(aesthetic, limits) do
    {schema, scale_of} = limited_scale(aesthetic, limits)

    [limits: limits]
    |> NimbleOptions.validate!(schema)
    |> scale_of.()
  end

  defp limited_scale(:alpha, values) when is_list(values),
    do: {@discrete_alpha_scale_options, &discrete_alpha_scale/1}

  defp limited_scale(:alpha, _ends),
    do: {@continuous_alpha_scale_options, &continuous_alpha_scale/1}

  defp limited_scale(:shape, _values),
    do: {@discrete_shape_scale_options, &discrete_shape_scale/1}

  defp limited_scale(:size, values) when is_list(values),
    do: {@discrete_size_scale_options, &discrete_size_scale/1}

  defp limited_scale(:size, _ends),
    do: {@continuous_size_scale_options, &continuous_size_scale/1}

  defp limited_scale(:linetype, _values),
    do: {@discrete_linetype_scale_options, &discrete_linetype_scale/1}

  defp limited_scale(:linewidth, values) when is_list(values),
    do: {@discrete_linewidth_scale_options, &discrete_linewidth_scale/1}

  defp limited_scale(:linewidth, _ends),
    do: {@continuous_linewidth_scale_options, &continuous_linewidth_scale/1}

  defp limited_scale(_color, values) when is_list(values),
    do: {@discrete_color_scale_options, &discrete_color_scale/1}

  defp limited_scale(_color, _ends),
    do: {@continuous_color_scale_options, &continuous_color_scale/1}

  # The axis's scale limits give: a discrete one for a list of values; a date one for dates; else
  # a continuous one.
  defp axis_limits_scale(values) when is_list(values), do: %Scale.Discrete{limits: values}

  defp axis_limits_scale({low, high} = limits) when is_struct(low, Date) or is_struct(high, Date),
    do: %Scale.Continuous{limits: limits, transform: :date}

  defp axis_limits_scale(limits),
    do: %Scale.Continuous{limits: limits, transform: limits_transform(limits)}

  # Limits given high to low reverse the axis, as ggplot2's `limits()` chooses
  # `transform = "reverse"` for them; any others leave it as it is.
  defp limits_transform({low, high}) when is_number(low) and is_number(high) and low > high,
    do: :reverse

  defp limits_transform(_limits), do: :identity

  @doc """
  Sets the plot's labels: the title of an axis or a legend, named by its aesthetic, and the plot's
  title, subtitle, caption and tag.

  An axis or legend is otherwise titled by what is mapped to it (`Giggly.Mapping`); a label set
  here replaces that title, whether the layer was added before or after. A label of `:none`
  removes the title and the room it took, and `""` keeps the room and draws nothing. A label for an
  aesthetic no layer maps titles nothing. Each call sets only the labels it is given, keeping the
  rest. A label breaking over several lines (`"Fuel\\neconomy"`) is drawn a line at a time.

  The title and subtitle are drawn above the panels, from their left edge; the caption below them,
  to their right edge; and the tag at the plot's top left.

  ## Options

  #{NimbleOptions.docs(@labs_options)}

      iex> svg =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.labs(x: "Weight (1000 lbs)", y: :none, title: "Fuel economy")
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> {svg =~ ">Weight (1000 lbs)</text>", svg =~ ">mpg</text>", svg =~ ">Fuel economy</text>"}
      {true, false, true}
  """
  @spec labs(t(), keyword()) :: t()
  def labs(%__MODULE__{labels: labels} = plot, options) when is_list(options) do
    validated =
      options
      |> Aesthetics.canonicalize()
      |> NimbleOptions.validate!(@labs_options)

    %{plot | labels: Map.merge(labels, Map.new(validated))}
  end

  @doc """
  Sets the guide that reads each aesthetic's scale back: `:legend`, a key for each break;
  `:colorbar`, a bar a continuous colour or fill scale's colours run up; a legend
  `guide_legend/1` makes; or `:none` for none.

  A guide set here wins over the one its scale's `guide:` chooses, before or after the scale is
  given. Each call sets only the guides it is given, keeping the rest. A colour bar for alpha,
  shape or size raises here, and one for a colour or fill scale that is discrete raises when the
  plot is run. A guide for an aesthetic no layer maps reads nothing.

  ## Options

  #{NimbleOptions.docs(@guides_options)}

      iex> svg =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.guides(color: :none)
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> svg =~ ">cyl</text>"
      false
  """
  @spec guides(t(), keyword()) :: t()
  def guides(%__MODULE__{guides: guides} = plot, options) when is_list(options) do
    validated =
      options
      |> Aesthetics.canonicalize()
      |> NimbleOptions.validate!(@guides_options)

    %{plot | guides: Map.merge(guides, Map.new(validated))}
  end

  @doc """
  A legend for a scale's `guide:` or for `guides/2`, with options: a key for each of the scale's
  breaks, labelled, as `:legend` draws, its keys in the order the options choose.

  Raises `NimbleOptions.ValidationError` for an option it does not take or a value it cannot use.

  ## Options

  #{NimbleOptions.docs(@guide_legend_options)}

      iex> svg =
      ...>   %{"wt" => [2.62, 2.875, 2.32], "mpg" => [21.0, 22.8, 22.8], "drv" => ["f", "r", "4"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg, colour: :drv})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.guides(color: Giggly.Plot.guide_legend(reverse: true))
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> Regex.scan(~r{>([fr4])</text>}, svg, capture: :all_but_first)
      [["r"], ["f"], ["4"]]
  """
  @spec guide_legend(keyword()) :: struct()
  def guide_legend(options \\ []) when is_list(options) do
    validated = NimbleOptions.validate!(options, @guide_legend_options)
    struct!(Guide.Legend, validated)
  end

  @doc """
  Changes the look everything but the marks is drawn in: its backgrounds, grid lines, axes,
  strips, legends and titles, each an element of the theme, set by name.

  The theme is a tree of elements, each inheriting what it leaves unset from its parent: every
  text inherits from `:text`, every line from `:line` and every rectangle from `:rect`, so
  `text: [size: 14]` makes every label bigger, and the x axis's tick labels below the panels,
  `:axis_text_x_bottom`, inherit from `:axis_text_x`, which inherits from `:axis_text`. A line,
  a rectangle or a text is a keyword list of the properties it sets; a size or a line width may be
  `{:rel, share}`, a share of its parent's. A setting replaces only the properties it gives, so
  `theme(axis_text: [color: "red"])` keeps the labels' size, and a later call's properties replace
  an earlier one's.

  A length is a number of ggplot2's points (1/72.27 inch), `{amount, unit}` in `:pt`, `:cm`,
  `:mm`, `:in` or `:lines`, a line of text, or `{:rel, share}`, a share of its parent's. A margin
  is one length for every side, a keyword list of `:top`, `:right`, `:bottom` and `:left`, a side
  left out 0, or `{:rel, share}`. `:spacing` and `:margins`, which inherit from nothing, take no
  share.

  A line, a rectangle or a text set to `:none` is removed: it draws nothing and takes no room, and
  the elements that inherit from it go with it, so `axis_text: :none` removes every axis's tick
  labels and the room they took. An element a setting gives is drawn all the same, inheriting from
  the nearest element above it that is not removed, so `theme(axis_text: :none, axis_text_x:
  [color: "red"])` keeps the x axis's labels, red and at the size of `:text`; a later setting of a
  removed element replaces the removal. Under a removed `:line`, `:rect` or `:text`, a property
  nothing above an element gives is drawn at the drawing's own default: black, filled white, a
  line 0.75 points wide with round ends, text 12 points with its lines 1.2 sizes apart, and no
  margin.
  `legend_position: :none` draws no legends.

  Raises `NimbleOptions.ValidationError` for an element it does not know or a value it cannot use,
  and `ArgumentError` for an element or a property given twice.

  ## Options

  #{NimbleOptions.docs(@theme_options)}

      iex> svg =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.theme(panel_background: [fill: "white"], axis_text: [color: "red"])
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> {svg =~ "fill: #EBEBEB", svg =~ "fill: #FF0000"}
      {false, true}

  Removing the panel's background and the tick labels leaves the axes' titles the only text:

      iex> svg =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.theme(panel_background: :none, axis_text: :none)
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> {svg =~ "fill: #EBEBEB", length(Regex.scan(~r/<text/, svg))}
      {false, 2}
  """
  @spec theme(t(), keyword()) :: t()
  def theme(%__MODULE__{theme: theme} = plot, settings) when is_list(settings) do
    # A removal is taken aside before the schema checks the rest, which keeps a mistake inside an
    # element reported at its property.
    {removals, given} =
      settings
      |> Aesthetics.canonicalize()
      |> Enum.split_with(fn {name, element} ->
        is_map_key(@theme_drawn_kinds, name) and element == :none
      end)

    validated =
      given
      |> Enum.map(fn
        {name, element} when is_map_key(@theme_drawn_kinds, name) and is_list(element) ->
          {name, Aesthetics.canonicalize(element)}

        setting ->
          setting
      end)
      |> NimbleOptions.validate!(@theme_options)
      |> Map.new(fn
        {name, element} when is_list(element) -> {name, Map.new(element)}
        setting -> setting
      end)
      |> Map.merge(Map.new(removals))

    %{plot | theme: %{theme | settings: Theme.merge(theme.settings, validated)}}
  end

  # The mapping `layer` draws with: its own mapping laid over the plot's, if both map an aesthetic,
  # the layer's column is used, and less any aesthetic the layer sets to one value, which wins over
  # a mapping, as ggplot2's `compute_aesthetics()` drops the aesthetics a layer's `aes_params` set.
  # An annotation takes nothing from the plot's mapping, as ggplot2's `annotate()` sets
  # `inherit.aes = FALSE`.
  @doc false
  @spec computed_mapping(t(), Layer.t()) :: mapping()
  def computed_mapping(%__MODULE__{} = plot, %Layer{} = layer) do
    plot
    |> inherited_mapping(layer)
    |> Map.merge(layer.mapping)
    |> Map.drop(Map.keys(layer.fixed))
  end

  defp inherited_mapping(%__MODULE__{}, %Layer{annotation: true}), do: %{}
  defp inherited_mapping(%__MODULE__{mapping: mapping}, %Layer{annotation: false}), do: mapping

  # The aesthetics `computed_mapping/2` maps for `layer`, in the order ggplot2 evaluates them: the
  # layer's own, then those it takes from the plot's mapping, as `defaults(layer$mapping,
  # plot$mapping)` lays them, each mapping's x and y first, as `aes()` takes them as its first two
  # arguments, and its others in name order, since a mapping is a map and keeps no written order.
  @doc false
  @spec mapping_order(t(), Layer.t()) :: [aesthetic()]
  def mapping_order(%__MODULE__{} = plot, %Layer{} = layer) do
    set = Map.keys(layer.fixed)

    own =
      layer.mapping
      |> Map.drop(set)
      |> Map.keys()
      |> in_aes_order()

    inherited =
      plot
      |> inherited_mapping(layer)
      |> Map.drop(Map.keys(layer.mapping))
      |> Map.drop(set)
      |> Map.keys()
      |> in_aes_order()

    Enum.concat(own, inherited)
  end

  defp in_aes_order(aesthetics),
    do: Enum.sort_by(aesthetics, fn aesthetic -> {aesthetic not in [:x, :y], aesthetic} end)

  # The geom `layer` draws with, a struct of its kind (`Giggly.Geom`).
  @doc false
  @spec layer_geom(Layer.t()) :: Layer.geom()
  def layer_geom(%Layer{geom: geom}), do: geom

  # The stat `layer` computes its table with, a struct of its kind (`Giggly.Stat`).
  @doc false
  @spec layer_stat(Layer.t()) :: Layer.stat()
  def layer_stat(%Layer{stat: stat}), do: stat

  # The position `layer` moves its marks with, a struct of its kind (`Giggly.Position`).
  @doc false
  @spec layer_position(Layer.t()) :: Layer.position()
  def layer_position(%Layer{position: position}), do: position

  # The aesthetics `layer` sets to one value for every mark, as ggplot2's `aes_params`.
  @doc false
  @spec layer_fixed(Layer.t()) :: Layer.fixed()
  def layer_fixed(%Layer{fixed: fixed}), do: fixed

  # The table `layer` draws: its own, which its function's `data:` option gave, or else the plot's.
  @doc false
  @spec layer_table(t(), Layer.t()) :: DataFrame.t()
  def layer_table(%__MODULE__{} = plot, %Layer{data: data}), do: drawn_table(plot, data)

  # The aesthetics `layer` can use, its geom's and its stat's.
  @doc false
  @spec layer_accepted(Layer.t()) :: [aesthetic()]
  def layer_accepted(%Layer{accepted: accepted}), do: accepted

  # Whether `layer` is an annotation, which `annotate/3` adds: its mapping, made from the values it
  # was given, titles no guide, as ggplot2's `aes_all()` mapping is unlabelled.
  @doc false
  @spec layer_annotation?(Layer.t()) :: boolean()
  def layer_annotation?(%Layer{annotation: annotation}), do: annotation

  # NimbleOptions' check of an `alpha:` option: a number from 0, invisible, to 1, opaque, kept as a
  # float.
  @doc false
  @spec validate_alpha(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_alpha(alpha) when is_number(alpha) and alpha >= 0 and alpha <= 1,
    do: {:ok, alpha / 1}

  def validate_alpha(alpha),
    do: {:error, "expected a number from 0 to 1, got: #{inspect(alpha)}"}

  # NimbleOptions' check of an option that sets a colour: a CSS colour, kept in its one spelling,
  # uppercase hex, or `:none`.
  @doc false
  @spec validate_color(term()) :: {:ok, ColorOperations.t()} | {:error, String.t()}
  def validate_color(color) do
    case ColorOperations.parse(color) do
      {:ok, spelling} ->
        {:ok, spelling}

      :error ->
        {:error,
         "expected a CSS colour: a name such as \"steelblue\", a hex colour such as " <>
           "\"#4682B4\", \"transparent\", or :none, got: #{inspect(color)}"}
    end
  end

  # NimbleOptions' check of a theme element's colour: an opaque CSS colour, kept in its one
  # spelling, uppercase hex.
  @doc false
  @spec validate_theme_color(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_theme_color(color) do
    case validate_color(color) do
      {:ok, <<"#", _digits::binary-size(6)>> = opaque} ->
        {:ok, opaque}

      {:ok, _not_opaque} ->
        {:error,
         "expected an opaque CSS colour, one with no alpha of its own, got: #{inspect(color)}"}

      {:error, _message} = error ->
        error
    end
  end

  # NimbleOptions' check of a theme rectangle's border colour: an opaque CSS colour, or `:none` for
  # no border.
  @doc false
  @spec validate_theme_border(term()) :: {:ok, String.t() | :none} | {:error, String.t()}
  def validate_theme_border(:none), do: {:ok, :none}
  def validate_theme_border(color), do: validate_theme_color(color)

  # NimbleOptions' check of a theme element's line width: millimetres, 0 or more, or a share of its
  # parent's, `{:rel, share}`, 0 or more.
  @doc false
  @spec validate_theme_linewidth(term()) ::
          {:ok, number() | {:rel, number()}} | {:error, String.t()}
  def validate_theme_linewidth(width), do: theme_amount(width, "a width in millimetres")

  # NimbleOptions' check of a theme text's size: points, 0 or more, or a share of its parent's,
  # `{:rel, share}`, 0 or more.
  @doc false
  @spec validate_theme_size(term()) :: {:ok, number() | {:rel, number()}} | {:error, String.t()}
  def validate_theme_size(size), do: theme_amount(size, "a size in points")

  defp theme_amount(amount, _what) when is_number(amount) and amount >= 0, do: {:ok, amount}

  defp theme_amount({:rel, share} = relative, _what) when is_number(share) and share >= 0,
    do: {:ok, relative}

  defp theme_amount(amount, what) do
    {:error,
     "expected #{what}, 0 or more, or {:rel, share}, a share of its parent's, " <>
       "got: #{inspect(amount)}"}
  end

  # NimbleOptions' check of a theme length: a number of ggplot2's points, or `{amount, unit}` in
  # one of `Giggly.Theme`'s units, kept as `{amount, unit}`; for an element with a parent, as `role`
  # says, a share of its parent's, `{:rel, share}`, too, which a root (`:root`) has none to take,
  # as ggplot2 refuses one there.
  @doc false
  @spec validate_theme_length(term(), :element | :root) ::
          {:ok, Theme.measure()} | {:error, String.t()}
  def validate_theme_length({:rel, share} = relative, :element) when is_number(share),
    do: {:ok, relative}

  def validate_theme_length(length, role) do
    case theme_length(length) do
      :error ->
        {:error,
         "expected a length: a number of points or {amount, unit} with a unit of " <>
           "#{inspect(@theme_units)}#{share_choice(role)}, got: #{inspect(length)}"}

      measure ->
        {:ok, measure}
    end
  end

  defp share_choice(:element), do: ", or {:rel, share}"
  defp share_choice(:root), do: ""

  # NimbleOptions' check of a theme margin: one length for every side, or a keyword list of
  # `:top`, `:right`, `:bottom` and `:left`, each a length, a side left out 0; for a margin
  # element with a parent, as `for` says, a share of its parent's, `{:rel, share}`, too, which a
  # text's margin never is and a root margin (`:root`) has none to take.
  @doc false
  @spec validate_theme_margin(term(), :element | :text | :root) ::
          {:ok, Theme.sides() | {:rel, number()}} | {:error, String.t()}
  def validate_theme_margin({:rel, share} = relative, :element) when is_number(share),
    do: {:ok, relative}

  def validate_theme_margin(margin, _for) when is_list(margin) do
    sides = Enum.map(margin, fn side -> theme_side(side) end)

    if :error in sides or
         length(Enum.uniq_by(sides, fn {side, _length} -> side end)) < length(sides),
       do: theme_margin_error(margin),
       else: {:ok, Map.merge(@theme_no_margin, Map.new(sides))}
  end

  def validate_theme_margin(margin, _for) do
    case theme_length(margin) do
      :error -> theme_margin_error(margin)
      measure -> {:ok, Map.new(@theme_sides, fn side -> {side, measure} end)}
    end
  end

  defp theme_margin_error(margin) do
    {:error,
     "expected a margin: one length for every side, or a keyword list of " <>
       "#{inspect(@theme_sides)}, each given once, each a number of points or {amount, unit} " <>
       "with a unit of #{inspect(@theme_units)}, got: #{inspect(margin)}"}
  end

  # A side of a margin given as a keyword list, `{side, length}` with its length as a theme holds
  # it; `:error` for anything else.
  defp theme_side({side, length}) when side in @theme_sides do
    case theme_length(length) do
      :error -> :error
      measure -> {side, measure}
    end
  end

  defp theme_side(_other), do: :error

  # A length as a theme holds it, `{amount, unit}`, a number being ggplot2's points; `:error` for
  # anything else.
  defp theme_length(amount) when is_number(amount), do: {amount, :pt}

  defp theme_length({amount, unit} = measure) when is_number(amount) and unit in @theme_units,
    do: measure

  defp theme_length(_other), do: :error

  # NimbleOptions' check of a `linewidth:` option: a width in millimetres, 0 or more, kept as a
  # float.
  @doc false
  @spec validate_linewidth(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_linewidth(width) when is_number(width) and width >= 0, do: {:ok, width / 1}

  def validate_linewidth(width),
    do: {:error, "expected a width in millimetres, 0 or more, got: #{inspect(width)}"}

  # NimbleOptions' check of a `linetype:` option: one of R's line types by name or by its number, 0
  # to 6, or a dash pattern, a tuple of 2, 4, 6 or 8 lengths from 1 to 15, as R's graphics engine
  # takes a string of hex digits; each held as its dash pattern, a blank line as `:none`.
  @doc false
  @spec validate_linetype(term()) :: {:ok, tuple() | :none} | {:error, String.t()}
  def validate_linetype(number) when number in 0..6 do
    {_name, pattern} = Enum.at(@line_types, number)
    {:ok, pattern}
  end

  def validate_linetype(name) when name in @line_type_names,
    do: {:ok, Keyword.fetch!(@line_types, name)}

  def validate_linetype(pattern) when tuple_size(pattern) in [2, 4, 6, 8] do
    lengths = Tuple.to_list(pattern)

    if Enum.all?(lengths, fn length -> length in 1..15 end),
      do: {:ok, pattern},
      else: linetype_error(pattern)
  end

  def validate_linetype(line_type), do: linetype_error(line_type)

  defp linetype_error(line_type) do
    {:error,
     "expected a line type: one of " <>
       Enum.map_join(@line_type_names, ", ", &inspect/1) <>
       ", its number, 0 to 6, or a dash pattern, a tuple of 2, 4, 6 or 8 lengths from 1 to " <>
       "15, such as {4, 4}, got: #{inspect(line_type)}"}
  end

  # NimbleOptions' check of a size, a text's or a point's `size:` or a size scale's: a size in
  # millimetres, 0 or more, kept as a float.
  @doc false
  @spec validate_size(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_size(size) when is_number(size) and size >= 0, do: {:ok, size / 1}

  def validate_size(size),
    do: {:error, "expected a size in millimetres, 0 or more, got: #{inspect(size)}"}

  # NimbleOptions' check of a size scale's `range:`: `{low, high}`, each a size in millimetres, 0
  # or more, kept as a float.
  @doc false
  @spec validate_size_range(term()) :: {:ok, {float(), float()}} | {:error, String.t()}
  def validate_size_range({low, high} = range) do
    case {validate_size(low), validate_size(high)} do
      {{:ok, low}, {:ok, high}} -> {:ok, {low, high}}
      _not_sizes -> size_range_error(range)
    end
  end

  def validate_size_range(range), do: size_range_error(range)

  defp size_range_error(range),
    do:
      {:error,
       "expected {low, high}, each a size in millimetres, 0 or more, got: #{inspect(range)}"}

  # NimbleOptions' check of a line width scale's `range:`: `{low, high}`, each a width in
  # millimetres, 0 or more, kept as a float.
  @doc false
  @spec validate_linewidth_range(term()) :: {:ok, {float(), float()}} | {:error, String.t()}
  def validate_linewidth_range({low, high} = range) do
    case {validate_linewidth(low), validate_linewidth(high)} do
      {{:ok, low}, {:ok, high}} -> {:ok, {low, high}}
      _not_widths -> linewidth_range_error(range)
    end
  end

  def validate_linewidth_range(range), do: linewidth_range_error(range)

  defp linewidth_range_error(range),
    do:
      {:error,
       "expected {low, high}, each a width in millimetres, 0 or more, got: #{inspect(range)}"}

  # NimbleOptions' check of a point's `shape:` option: one of the shapes a point is drawn in, by
  # name or by its number, 0 to 25, kept as its name, or `:none` for no point.
  @doc false
  @spec validate_shape(term()) :: {:ok, atom()} | {:error, String.t()}
  def validate_shape(number) when number in 0..25,
    do: {:ok, Enum.at(@shapes, number)}

  def validate_shape(shape) when shape in @shapes or shape == :none, do: {:ok, shape}

  def validate_shape(shape) do
    {:error,
     "expected one of a point's shapes, by name or by its number, 0 to 25, or :none, got: " <>
       "#{inspect(shape)}; the names are #{Enum.map_join(@shapes, ", ", &inspect/1)}"}
  end

  # NimbleOptions' check of a point's `stroke:` option: a width in millimetres, 0 or more, kept
  # as a float, or `:none` for no outline.
  @doc false
  @spec validate_stroke(term()) :: {:ok, float() | :none} | {:error, String.t()}
  def validate_stroke(stroke) when is_number(stroke) and stroke >= 0, do: {:ok, stroke / 1}
  def validate_stroke(:none), do: {:ok, :none}

  def validate_stroke(stroke),
    do: {:error, "expected a width in millimetres, 0 or more, or :none, got: #{inspect(stroke)}"}

  # NimbleOptions' check of an `angle:` option: any number of degrees, kept as a float.
  @doc false
  @spec validate_angle(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_angle(angle) when is_number(angle), do: {:ok, angle / 1}
  def validate_angle(angle), do: {:error, "expected a number of degrees, got: #{inspect(angle)}"}

  # NimbleOptions' check of a bar's `width:`: any number, kept as a float, as R keeps one; a
  # negative width puts a bar's edges the other way round, which draws it as wide.
  @doc false
  @spec validate_width(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_width(width) when is_number(width), do: {:ok, width / 1}
  def validate_width(width), do: {:error, "expected a width, a number, got: #{inspect(width)}"}

  # NimbleOptions' check of a bar's `just:`: where it sits against its position, from 0 to 1, kept
  # as a float.
  @doc false
  @spec validate_just(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_just(just) when is_number(just) and just >= 0 and just <= 1, do: {:ok, just / 1}

  def validate_just(just),
    do: {:error, "expected a number from 0 to 1, got: #{inspect(just)}"}

  # NimbleOptions' check of a bar's `position:`: one of the positions it takes by name, or a
  # position `position_dodge2/1` makes.
  @doc false
  @spec validate_bar_position(term()) :: {:ok, atom() | struct()} | {:error, String.t()}
  def validate_bar_position(position) when position in [:stack, :dodge, :dodge2],
    do: {:ok, position}

  def validate_bar_position(%Position.Dodge2{} = position), do: {:ok, position}

  def validate_bar_position(position) do
    {:error,
     "expected :stack, :dodge, :dodge2 or a position Plot.position_dodge2/1 makes, got: " <>
       inspect(position)}
  end

  # NimbleOptions' check of a box plot's `position:`: one of the positions it takes by name, or a
  # position `position_dodge2/1` makes. Boxes do not stack.
  @doc false
  @spec validate_boxplot_position(term()) :: {:ok, atom() | struct()} | {:error, String.t()}
  def validate_boxplot_position(position) when position in [:dodge, :dodge2],
    do: {:ok, position}

  def validate_boxplot_position(%Position.Dodge2{} = position), do: {:ok, position}

  def validate_boxplot_position(position) do
    {:error,
     "expected :dodge2, :dodge or a position Plot.position_dodge2/1 makes, got: " <>
       inspect(position)}
  end

  # NimbleOptions' check of `position_dodge2/1`'s `padding:`: the fraction of its share each bar
  # leaves as a gap, from 0 to 1, kept as a float.
  @doc false
  @spec validate_padding(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_padding(padding) when is_number(padding) and padding >= 0 and padding <= 1,
    do: {:ok, padding / 1}

  def validate_padding(padding),
    do: {:error, "expected a fraction from 0 to 1, got: #{inspect(padding)}"}

  # NimbleOptions' check of a `nudge_x:` or `nudge_y:` option: any distance along its axis, kept as
  # a float, as R keeps one.
  @doc false
  @spec validate_nudge(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_nudge(distance) when is_number(distance), do: {:ok, distance / 1}

  def validate_nudge(distance),
    do: {:error, "expected a distance along the axis, a number, got: #{inspect(distance)}"}

  # NimbleOptions' check of a scale's limits: `{low, high}`, each a number, kept as a float, or
  # `nil` for an end the data decides, in either order, which the scale sorts once transformed.
  @doc false
  @spec validate_limits(term()) ::
          {:ok, {float() | nil, float() | nil}} | {:error, String.t()}
  def validate_limits({low, high})
      when (is_number(low) or is_nil(low)) and (is_number(high) or is_nil(high)),
      do: {:ok, {limit(low), limit(high)}}

  def validate_limits(limits) do
    {:error,
     "expected {low, high}, each a number or nil for an end the data decides, got: " <>
       inspect(limits)}
  end

  defp limit(nil), do: nil
  defp limit(number), do: number / 1

  # NimbleOptions' check of a scale's breaks or minor breaks: a list of numbers, each kept as a
  # float, or `:none` for none.
  @doc false
  @spec validate_breaks(term()) :: {:ok, [float()] | :none} | {:error, String.t()}
  def validate_breaks(:none), do: {:ok, :none}

  def validate_breaks(breaks) when is_list(breaks) do
    case Enum.reject(breaks, &is_number/1) do
      [] -> {:ok, Enum.map(breaks, fn break -> break / 1 end)}
      [other | _rest] -> {:error, "expected a list of numbers, got: #{inspect(other)} in it"}
    end
  end

  def validate_breaks(breaks),
    do: {:error, "expected a list of numbers or :none, got: #{inspect(breaks)}"}

  # NimbleOptions' check of a scale's labels: a list of strings, a function of one argument, which
  # is handed the breaks, or `:none` for none.
  @doc false
  @spec validate_scale_labels(term()) ::
          {:ok, [String.t()] | (list() -> list()) | :none} | {:error, String.t()}
  def validate_scale_labels(:none), do: {:ok, :none}
  def validate_scale_labels(labeller) when is_function(labeller, 1), do: {:ok, labeller}

  def validate_scale_labels(labels) when is_list(labels) do
    case Enum.reject(labels, &is_binary/1) do
      [] -> {:ok, labels}
      [other | _rest] -> {:error, "expected a list of strings, got: #{inspect(other)} in it"}
    end
  end

  def validate_scale_labels(labels) do
    {:error,
     "expected a list of strings, a function of one argument or :none, got: " <>
       inspect(labels)}
  end

  # NimbleOptions' check of a scale's `expand:`: `mult:` and `add:`, each once, each a number or
  # `{low, high}`, kept as floats for each end, 0 for one not given; a negative one draws the axis
  # short of its limits, as R's `expansion()` allows.
  @doc false
  @spec validate_expand(term()) ::
          {:ok, [mult: {float(), float()}, add: {float(), float()}]} | {:error, String.t()}
  def validate_expand(expansion) when is_list(expansion) do
    with true <- Keyword.keyword?(expansion),
         [] <- Keyword.keys(expansion) -- [:mult, :add],
         {:ok, mult} <- expansion_ends(Keyword.get_values(expansion, :mult)),
         {:ok, add} <- expansion_ends(Keyword.get_values(expansion, :add)) do
      {:ok, [mult: mult, add: add]}
    else
      _invalid -> expansion_error(expansion)
    end
  end

  def validate_expand(expansion), do: expansion_error(expansion)

  defp expansion_ends([]), do: {:ok, {0.0, 0.0}}

  defp expansion_ends([amount]) when is_number(amount), do: {:ok, {amount / 1, amount / 1}}

  defp expansion_ends([{low, high}]) when is_number(low) and is_number(high),
    do: {:ok, {low / 1, high / 1}}

  defp expansion_ends(_invalid), do: :error

  defp expansion_error(expansion) do
    {:error,
     "expected [mult: m, add: a], each given once, a number or {low, high}, got: " <>
       inspect(expansion)}
  end

  # NimbleOptions' check of a discrete scale's limits: a list of at least one value, each named
  # once (`discrete_values/1`).
  @doc false
  @spec validate_discrete_limits(term()) :: {:ok, list()} | {:error, String.t()}
  def validate_discrete_limits([_first | _rest] = values), do: discrete_values(values)

  def validate_discrete_limits(values) do
    {:error,
     "expected a list of at least one value, each a string, a number, an atom or nil, got: " <>
       inspect(values)}
  end

  # NimbleOptions' check of a discrete scale's breaks: a list of values, each named once
  # (`discrete_values/1`), or `:none` for none.
  @doc false
  @spec validate_discrete_breaks(term()) :: {:ok, list() | :none} | {:error, String.t()}
  def validate_discrete_breaks(:none), do: {:ok, :none}
  def validate_discrete_breaks(values) when is_list(values), do: discrete_values(values)

  def validate_discrete_breaks(values) do
    {:error,
     "expected a list of values, each a string, a number, an atom or nil, or :none, got: " <>
       inspect(values)}
  end

  # A list of a discrete axis's values, each a string, a number or an atom, `nil` and the booleans
  # among them, as a discrete column holds them, and none named twice, a number and the float
  # equal to it being one value, as the scale matches them (`Scale.Discrete.key/1`).
  defp discrete_values(values) do
    case Enum.reject(values, &discrete_value?/1) do
      [] ->
        distinct_values(values)

      [other | _rest] ->
        {:error,
         "expected values, each a string, a number, an atom or nil, got: #{inspect(other)} in #{inspect(values)}"}
    end
  end

  defp distinct_values(values) do
    case values -- Enum.uniq_by(values, &Scale.Discrete.key/1) do
      [] ->
        {:ok, values}

      [repeated | _rest] ->
        {:error,
         "expected each value once, got: #{inspect(repeated)} more than once in #{inspect(values)}"}
    end
  end

  defp discrete_value?(value), do: is_binary(value) or is_number(value) or is_atom(value)

  # NimbleOptions' check of a discrete scale's labels: a list of strings, a map from a value
  # (`discrete_values/1`) to its label, a function of one argument, which is handed the breaks, or
  # `:none` for none.
  @doc false
  @spec validate_discrete_labels(term()) ::
          {:ok, [String.t()] | map() | (list() -> list()) | :none} | {:error, String.t()}
  def validate_discrete_labels(labels) when is_map(labels) and not is_struct(labels) do
    values = Map.keys(labels)
    texts = Map.values(labels)

    with {:ok, _values} <- discrete_values(values),
         [] <- Enum.reject(texts, &is_binary/1) do
      {:ok, labels}
    else
      {:error, _message} = error ->
        error

      [other | _rest] ->
        {:error, "expected each label a string, got: #{inspect(other)} in #{inspect(labels)}"}
    end
  end

  def validate_discrete_labels(labels)
      when is_list(labels) or is_function(labels, 1) or labels == :none,
      do: validate_scale_labels(labels)

  def validate_discrete_labels(labels) do
    {:error,
     "expected a list of strings, a map from a value to its label, a function of one argument " <>
       "or :none, got: #{inspect(labels)}"}
  end

  # NimbleOptions' check of a date scale's limits: `{low, high}`, each a date or `nil` for an end
  # the data decides, in either order, which the scale sorts once transformed.
  @doc false
  @spec validate_date_limits(term()) ::
          {:ok, {Date.t() | nil, Date.t() | nil}} | {:error, String.t()}
  def validate_date_limits({low, high} = limits) when is_date_limit(low) and is_date_limit(high),
    do: {:ok, limits}

  def validate_date_limits(limits) do
    {:error,
     "expected {low, high}, each a date or nil for an end the data decides, got: " <>
       inspect(limits)}
  end

  # NimbleOptions' check of a date scale's breaks or minor breaks: a list of dates, or `:none` for
  # none.
  @doc false
  @spec validate_dates(term()) :: {:ok, [Date.t()] | :none} | {:error, String.t()}
  def validate_dates(:none), do: {:ok, :none}

  def validate_dates(dates) when is_list(dates) do
    case Enum.reject(dates, fn date -> is_struct(date, Date) end) do
      [] -> {:ok, dates}
      [other | _rest] -> {:error, "expected a list of dates, got: #{inspect(other)} in it"}
    end
  end

  def validate_dates(dates),
    do: {:error, "expected a list of dates or :none, got: #{inspect(dates)}"}

  # NimbleOptions' check of a date scale's step between breaks: one of a day, a week, a month and a
  # year and how many of it, a positive whole number.
  @doc false
  @spec validate_date_step(term()) ::
          {:ok, [{:day | :week | :month | :year, pos_integer()}]} | {:error, String.t()}
  def validate_date_step([{unit, count}] = step)
      when unit in [:day, :week, :month, :year] and is_integer(count) and count > 0,
      do: {:ok, step}

  def validate_date_step(step) do
    {:error,
     "expected one of :day, :week, :month and :year and how many of it, a positive whole " <>
       "number, such as [week: 1], got: #{inspect(step)}"}
  end

  # NimbleOptions' check of a date scale's label format: a string `Calendar.strftime/3` writes a
  # date in, tried on one, so a format it cannot write raises at the call rather than when the
  # plot is run.
  @doc false
  @spec validate_date_format(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_date_format(format) when is_binary(format) do
    Calendar.strftime(~D[1970-01-01], format)
    {:ok, format}
  rescue
    exception ->
      {:error,
       "expected a format Calendar.strftime/3 can write a date in, got: #{inspect(format)}, " <>
         "which it cannot: #{Exception.message(exception)}"}
  end

  def validate_date_format(format),
    do: {:error, "expected a format, a string, got: #{inspect(format)}"}

  # NimbleOptions' check of an axis's limits as `lims/2` takes them: a list of a discrete axis's
  # values, `{low, high}` of dates or `nil` for a date axis, or else of numbers or `nil` for a
  # continuous one.
  @doc false
  @spec validate_axis_limits(term()) :: {:ok, list() | tuple()} | {:error, String.t()}
  def validate_axis_limits(values) when is_list(values), do: validate_discrete_limits(values)

  def validate_axis_limits({low, high} = limits)
      when is_struct(low, Date) or is_struct(high, Date),
      do: validate_date_limits(limits)

  def validate_axis_limits(limits) do
    case validate_limits(limits) do
      {:ok, _limits} = valid ->
        valid

      {:error, _message} ->
        {:error,
         "expected {low, high}, two numbers or two dates, each nil for an end the data " <>
           "decides, or a list of a discrete axis's values, got: #{inspect(limits)}"}
    end
  end

  # NimbleOptions' check of `lims/2`'s limits for a shape or line type scale (`aesthetic`): a list
  # of a discrete scale's values alone, since such a scale is always discrete, as ggplot2's
  # `lims(shape = c(1, 5))` and `lims(linetype = c(1, 5))` abort.
  @doc false
  @spec validate_unordered_limits(term(), :shape | :linetype) ::
          {:ok, list()} | {:error, String.t()}
  def validate_unordered_limits(values, _aesthetic) when is_list(values),
    do: validate_discrete_limits(values)

  def validate_unordered_limits(limits, aesthetic) do
    {:error,
     "expected a list of the values the scale shows, since a #{Aesthetics.in_words(aesthetic)} " <>
       "scale is discrete, got: #{inspect(limits)}"}
  end

  # NimbleOptions' check of `lims/2`'s limits for a colour, fill or alpha scale: a list of a
  # discrete scale's values, or `{low, high}`, two numbers, each kept as a float, or `nil` for an
  # end the data decides, low first, since such a scale has no transformation to run from high to
  # low.
  @doc false
  @spec validate_legend_limits(term()) ::
          {:ok, list() | {float() | nil, float() | nil}} | {:error, String.t()}
  def validate_legend_limits(values) when is_list(values), do: validate_discrete_limits(values)

  def validate_legend_limits({low, high} = limits)
      when is_number(low) and is_number(high) and low > high do
    {:error,
     "expected {low, high}, low first, since a colour, fill, alpha, size or line width scale " <>
       "cannot run from high to low, got: #{inspect(limits)}"}
  end

  def validate_legend_limits(limits) do
    case validate_limits(limits) do
      {:ok, _limits} = valid ->
        valid

      {:error, _message} ->
        {:error,
         "expected {low, high}, two numbers, each nil for an end the data decides, or a list of " <>
           "a discrete scale's values, got: #{inspect(limits)}"}
    end
  end

  # NimbleOptions' check of a number, kept as a float, as R keeps one.
  @doc false
  @spec validate_number(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_number(number) when is_number(number), do: {:ok, number / 1}
  def validate_number(other), do: {:error, "expected a number, got: #{inspect(other)}"}

  # NimbleOptions' check of `{first, last}`, two numbers, each kept as a float.
  @doc false
  @spec validate_number_pair(term()) :: {:ok, {float(), float()}} | {:error, String.t()}
  def validate_number_pair({first, last}) when is_number(first) and is_number(last),
    do: {:ok, {first / 1, last / 1}}

  def validate_number_pair(other),
    do: {:error, "expected {first, last}, two numbers, got: #{inspect(other)}"}

  # NimbleOptions' check of a place in a palette: a number from 0, its start, to 1, its end, kept
  # as a float.
  @doc false
  @spec validate_palette_place(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_palette_place(place) when is_number(place) and place >= 0 and place <= 1,
    do: {:ok, place / 1}

  def validate_palette_place(other),
    do:
      {:error,
       "expected a place in the palette, from 0, its start, to 1, its end, got: " <>
         inspect(other)}

  # NimbleOptions' check of a grey's level: a number from 0, black, to 1, white, kept as a float.
  @doc false
  @spec validate_gray_level(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_gray_level(level) when is_number(level) and level >= 0 and level <= 1,
    do: {:ok, level / 1}

  def validate_gray_level(other),
    do: {:error, "expected a grey's level, from 0, black, to 1, white, got: #{inspect(other)}"}

  # NimbleOptions' check of an alpha scale's `range:`: `{low, high}`, each an opacity from 0 to 1,
  # kept as a float.
  @doc false
  @spec validate_alpha_range(term()) :: {:ok, {float(), float()}} | {:error, String.t()}
  def validate_alpha_range({low, high} = range) do
    case {validate_alpha(low), validate_alpha(high)} do
      {{:ok, low}, {:ok, high}} -> {:ok, {low, high}}
      _not_opacities -> alpha_range_error(range)
    end
  end

  def validate_alpha_range(range), do: alpha_range_error(range)

  defp alpha_range_error(range),
    do: {:error, "expected {low, high}, each an opacity from 0 to 1, got: #{inspect(range)}"}

  # NimbleOptions' check of a gradient's colour: a colour (`validate_color/1`) with no alpha of its
  # own, since a gradient blends colours alone.
  @doc false
  @spec validate_opaque_color(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_opaque_color(color) do
    case validate_color(color) do
      {:ok, <<"#", _digits::binary-size(6)>> = opaque} ->
        {:ok, opaque}

      {:ok, _not_opaque} ->
        {:error,
         "expected a colour with no alpha of its own, since a gradient blends colours alone, " <>
           "got: #{inspect(color)}"}

      {:error, _message} = error ->
        error
    end
  end

  # NimbleOptions' check of a gradient's colours: a list of at least one, each opaque
  # (`validate_opaque_color/1`).
  @doc false
  @spec validate_gradient_colors(term()) :: {:ok, [String.t()]} | {:error, String.t()}
  def validate_gradient_colors([_first | _rest] = colors),
    do: checked_each(colors, &validate_opaque_color/1)

  def validate_gradient_colors(other),
    do: {:error, "expected a list of at least one colour, got: #{inspect(other)}"}

  # NimbleOptions' check of a discrete palette's colours: a list of at least one, each a colour or
  # `:none` (`validate_color/1`).
  @doc false
  @spec validate_palette_colors(term()) :: {:ok, [ColorOperations.t()]} | {:error, String.t()}
  def validate_palette_colors([_first | _rest] = colors),
    do: checked_each(colors, &validate_color/1)

  def validate_palette_colors(other),
    do: {:error, "expected a list of at least one colour, got: #{inspect(other)}"}

  # NimbleOptions' check of a manual scale's `values:` for `aesthetic`: a colour scale's a list of
  # colours (`validate_palette_colors/1`), a shape scale's a list of at least one shape
  # (`validate_shape/1`), a line type scale's a list of at least one line type
  # (`validate_linetype/1`), or any one's a map from a value (`discrete_values/1`) to its colour,
  # shape or line type.
  @doc false
  @spec validate_manual_values(term(), :color | :shape | :linetype) ::
          {:ok, list() | %{term() => ColorOperations.t() | atom() | tuple()}}
          | {:error, String.t()}
  def validate_manual_values(values, :color) when is_list(values),
    do: validate_palette_colors(values)

  def validate_manual_values([_first | _rest] = values, aesthetic),
    do: checked_each(values, manual_check(aesthetic))

  def validate_manual_values(values, aesthetic)
      when is_map(values) and not is_struct(values) and map_size(values) > 0 do
    {keys, mapped} = Enum.unzip(values)

    with {:ok, _keys} <- discrete_values(keys),
         {:ok, parsed} <- checked_each(mapped, manual_check(aesthetic)) do
      named =
        keys
        |> Enum.zip(parsed)
        |> Map.new()

      {:ok, named}
    end
  end

  def validate_manual_values(values, aesthetic) do
    noun = manual_noun(aesthetic)

    {:error,
     "expected a list of at least one #{noun}, or a map from a value to its #{noun}, got: " <>
       inspect(values)}
  end

  defp manual_check(:color), do: &validate_color/1
  defp manual_check(:shape), do: &validate_shape/1
  defp manual_check(:linetype), do: &validate_linetype/1

  defp manual_noun(:color), do: "colour"
  defp manual_noun(:shape), do: "shape"
  defp manual_noun(:linetype), do: "line type"

  # Each of `values` through `check`, all of them, or the first error.
  defp checked_each(values, check) do
    checked =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, spellings} ->
        case check.(value) do
          {:ok, spelling} -> {:cont, {:ok, [spelling | spellings]}}
          {:error, _message} = error -> {:halt, error}
        end
      end)

    case checked do
      {:ok, spellings} -> {:ok, Enum.reverse(spellings)}
      {:error, _message} = error -> error
    end
  end

  # NimbleOptions' check of a `labs/2` option: a label's text, or `:none` for none.
  @doc false
  @spec validate_label(term()) :: {:ok, String.t() | :none} | {:error, String.t()}
  def validate_label(label) when is_binary(label) or label == :none, do: {:ok, label}

  def validate_label(label),
    do: {:error, "expected a label, a string or :none, got: #{inspect(label)}"}

  # NimbleOptions' check of a guide, a scale's `guide:` or one of `guides/2`'s, for a scale of
  # `kind`: `:legend`, `:none` or a legend `guide_legend/1` made, for any; `:colorbar` for a
  # continuous colour or fill scale alone, as a colour bar shows a continuous scale's colours, so a
  # discrete scale's is refused, and an alpha, a shape, a size, a line type or a line width
  # scale's whatever its kind.
  @doc false
  @spec validate_guide(
          term(),
          :continuous | :discrete | :alpha | :shape | :size | :linetype | :linewidth
        ) ::
          {:ok, guide()} | {:error, String.t()}
  def validate_guide(%Guide.Legend{} = guide, _kind), do: {:ok, guide}
  def validate_guide(guide, _kind) when guide in [:legend, :none], do: {:ok, guide}
  def validate_guide(:colorbar, :continuous), do: {:ok, :colorbar}

  def validate_guide(:colorbar, :discrete),
    do: {:error, "a colour bar shows a continuous scale, and this one is discrete; give :legend"}

  def validate_guide(:colorbar, aesthetic),
    do:
      {:error,
       "a colour bar shows colour or fill, never #{Aesthetics.in_words(aesthetic)}; give :legend"}

  def validate_guide(guide, _kind) do
    {:error,
     "expected :legend, :colorbar, :none or a legend Plot.guide_legend/1 makes, got: " <>
       inspect(guide)}
  end

  # NimbleOptions' check of an `hjust:` or `vjust:` option: a number, kept as a float, as R keeps one
  # and grid takes any, or one of ggplot2's words, as an atom.
  @doc false
  @spec validate_justification(term()) :: {:ok, float() | atom()} | {:error, String.t()}
  def validate_justification(just) when is_number(just), do: {:ok, just / 1}

  def validate_justification(just)
      when just in [:left, :center, :right, :bottom, :middle, :top, :inward, :outward],
      do: {:ok, just}

  def validate_justification(just) do
    {:error,
     "expected a number, or one of :left, :center, :right, :bottom, :middle, :top, :inward " <>
       "and :outward, got: #{inspect(just)}"}
  end

  # NimbleOptions' check of a rectangle's corner set for every rectangle: a number, kept as a float,
  # or `:infinity` or `:neg_infinity`, R's `Inf` and `-Inf`.
  @doc false
  @spec validate_corner(term()) ::
          {:ok, float() | :infinity | :neg_infinity} | {:error, String.t()}
  def validate_corner(corner) when is_number(corner), do: {:ok, corner / 1}
  def validate_corner(corner) when corner in [:infinity, :neg_infinity], do: {:ok, corner}

  def validate_corner(corner) do
    {:error,
     "expected a position on the axis: a number, :infinity or :neg_infinity, got: " <>
       inspect(corner)}
  end

  # One of an annotation's positions: a number, kept as a float, as R keeps a number written in a
  # call, `:infinity` or `:neg_infinity`, `nil` for none, a string, `true` or `false`, or a date.
  @doc false
  @spec validate_annotation_position(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_annotation_position(value) when is_number(value), do: {:ok, value / 1}

  def validate_annotation_position(value)
      when is_binary(value) or is_boolean(value) or value in [nil, :infinity, :neg_infinity],
      do: {:ok, value}

  def validate_annotation_position(%Date{} = value), do: {:ok, value}

  def validate_annotation_position(value) do
    {:error,
     "expected a position, or a list of them: a number, :infinity or :neg_infinity, nil, a " <>
       "string, true or false, or a date, got: #{inspect(value)}"}
  end

  # NimbleOptions' check of an annotation's label: a string, a number, or `true` or `false`, which
  # text writes as R's `as.character()` does, kept as given.
  @doc false
  @spec validate_annotation_label(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_annotation_label(label)
      when is_binary(label) or is_number(label) or is_boolean(label),
      do: {:ok, label}

  def validate_annotation_label(label) do
    {:error, "expected a label: a string, a number, true or false, got: #{inspect(label)}"}
  end

  # NimbleOptions' check of an annotation's option that takes a list, one value per annotation:
  # each value checked by `check`, a check of this module's; a single value is checked alone.
  # Whether a list's values are of one type is the table's question (`check_columns/1`).
  @doc false
  @spec validate_per_annotation(term(), atom()) :: {:ok, term()} | {:error, String.t()}
  def validate_per_annotation(values, check) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, checked} ->
      case apply(__MODULE__, check, [value]) do
        {:ok, kept} -> {:cont, {:ok, [kept | checked]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> kept_in_order()
  end

  def validate_per_annotation(value, check), do: apply(__MODULE__, check, [value])

  defp kept_in_order({:ok, reversed}), do: {:ok, Enum.reverse(reversed)}
  defp kept_in_order(error), do: error

  # NimbleOptions' check of a `linemitre:` option: a number of line widths, 1 or more, as grid
  # refuses less, kept as a float.
  @doc false
  @spec validate_linemitre(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_linemitre(limit) when is_number(limit) and limit >= 1, do: {:ok, limit / 1}

  def validate_linemitre(limit),
    do: {:error, "expected a number of line widths, 1 or more, got: #{inspect(limit)}"}

  # NimbleOptions' check of a `binwidth:` option: a number above 0, kept as a float, as R keeps a
  # double.
  @doc false
  @spec validate_binwidth(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_binwidth(width) when is_number(width) and width > 0, do: {:ok, width / 1}

  def validate_binwidth(width),
    do: {:error, "expected a bin width, a number above 0, got: #{inspect(width)}"}

  # NimbleOptions' check of a `breaks:` option for bins: two or more numbers, no two the same, each
  # kept as a float, as R keeps doubles; a list of one break or a repeated one has no bins between.
  @doc false
  @spec validate_bin_breaks(term()) :: {:ok, [float()]} | {:error, String.t()}
  def validate_bin_breaks([_first, _second | _rest] = breaks) do
    floats = for break <- breaks, is_number(break), do: break / 1

    if length(floats) == length(breaks) and length(Enum.uniq(floats)) == length(floats),
      do: {:ok, floats},
      else: {:error, bin_breaks_error(breaks)}
  end

  def validate_bin_breaks(breaks), do: {:error, bin_breaks_error(breaks)}

  defp bin_breaks_error(breaks),
    do: "expected two or more distinct numbers where the bins meet, got: #{inspect(breaks)}"

  # A mapping as the plot holds it: its keys canonical and each value resolved
  # (`Giggly.Mapping`), a value the grammar refuses raising. The plot's mapping is held so, and
  # checked against a table by each layer that takes it.
  defp references(mapping, function_name) do
    mapping
    |> Aesthetics.canonicalize()
    |> Map.new(fn {aesthetic, value} ->
      {aesthetic, resolved_value(function_name, aesthetic, value)}
    end)
  end

  # A layer's own mapping, held as the plot's is, each column its values read checked against the
  # table the layer draws, its own `data` or else the plot's, a refusal naming the value as
  # written. An after_stat reads its stat's output, not the table, and is checked as the layer is
  # added.
  defp resolve(mapping, plot, data, function_name) do
    names =
      plot
      |> drawn_table(data)
      |> DataFrame.names()

    mapping
    |> Aesthetics.canonicalize()
    |> Map.new(fn {aesthetic, value} ->
      resolved = resolved_value(function_name, aesthetic, value)

      case missing_columns(resolved, names) do
        [] ->
          {aesthetic, resolved}

        [missing | _others] ->
          raise ArgumentError,
                "#{function_name} maps #{inspect(aesthetic)} to #{inspect(value)}, but " <>
                  missing_column_message(missing, data, names)
      end
    end)
  end

  defp resolved_value(function_name, aesthetic, value) do
    case Mapping.resolve(value) do
      {:ok, resolved} ->
        resolved

      {:error, reason} ->
        raise ArgumentError,
              "#{function_name} maps #{inspect(aesthetic)} to #{inspect(value)}, but #{reason}"
    end
  end

  defp missing_columns(value, names) do
    case Mapping.stage(value) do
      :start ->
        value
        |> Mapping.columns()
        |> Enum.reject(fn name -> name in names end)

      :after_stat ->
        []
    end
  end

  defp missing_column_message(name, data, names) do
    "#{table_name(data)} has no column #{inspect(name)}; its columns are #{inspect_all(names)}"
  end

  defp table_name(:none), do: "the plot's data"
  defp table_name(_own), do: "the layer's own data"

  # The table a layer function's `data:` option gives, read as `new/2` reads the plot's, or `:none`
  # when the layer draws the plot's data.
  defp own_data(validated) do
    case Keyword.fetch(validated, :data) do
      {:ok, table} -> DataFrame.from_table(table)
      :error -> :none
    end
  end

  defp drawn_table(%__MODULE__{data: data}, :none), do: data
  defp drawn_table(%__MODULE__{}, own), do: own

  # The plot with `layer` added, once its mappings are checked against what the function that adds
  # it, `function`, accepts and requires: its own mapping against what it accepts, and the mapping it
  # draws with, its own laid over the plot's, against what it requires and, for each after_stat in
  # it, against the variables its stat computes (`computed:`, none unless given) and the aesthetics
  # its stat consumes (`dropped:`). What a stat requires is met, and what it takes only one of is
  # counted, by the aesthetics mapped before it runs, never by an after_stat, as ggplot2's stats
  # see only those. An aesthetic it takes from the plot's mapping that it cannot use rides along
  # unused, as ggplot2 carries one, since the plot's mapping reaches every layer and not every
  # layer can use all of it. At the front, so adding a layer never walks the list.
  defp add_layer(plot, layer, function, facts) do
    combined_mapping = computed_mapping(plot, layer)

    {after_stat, before_stat} =
      Map.split_with(combined_mapping, fn {_aesthetic, value} ->
        Mapping.stage(value) == :after_stat
      end)

    given =
      before_stat
      |> Map.keys()
      |> Enum.concat(Map.keys(layer.fixed))

    unmet = Keyword.get(facts, :unmet, "neither its mapping nor the plot's maps it")
    check_inherited(plot, layer, before_stat, function)
    check_after_stat(layer, after_stat, function, facts)
    check_computable(plot, layer, combined_mapping, function)
    check_accepted(layer.mapping, layer.accepted, function)
    check_required(given, Keyword.fetch!(facts, :required), function, unmet, Map.keys(after_stat))
    check_exclusive(before_stat, Keyword.get(facts, :exclusive, []), function)

    %{plot | reversed_layers: [layer | plot.reversed_layers]}
  end

  # The layer `geom_count/3` and `stat_sum/3` add, points counting the rows at each place, its
  # mistakes named as `function`'s.
  defp count_layer(plot, mapping, options, function) do
    validated = layer_options(options, @point_options)
    data = own_data(validated)

    layer = %Layer{
      geom: %Geom.Point{},
      stat: %Stat.Sum{},
      position: %Position.Identity{},
      data: data,
      mapping: resolve(mapping, plot, data, function),
      fixed: fixed(validated),
      accepted: Enum.uniq(Stat.Sum.accepted_aesthetics() ++ Geom.Point.accepted_aesthetics()),
      annotation: false
    }

    plot
    |> add_layer(layer, function,
      required: Stat.Sum.required_aesthetics(),
      computed: Stat.Sum.computed_variables(),
      dropped: Stat.Sum.dropped_aesthetics()
    )
    |> check_weight(layer, function)
  end

  # The layer `geom_histogram/3` and `stat_bin/3` add, bars counting the rows in each bin, its
  # mistakes named as `function`'s.
  defp bin_layer(plot, mapping, options, function) do
    validated = layer_options(options, @bin_options)
    check_bin_placement(validated, function)
    data = own_data(validated)

    layer = %Layer{
      geom: %Geom.Bar{just: 0.5},
      stat: bin_stat(validated, Keyword.fetch!(validated, :pad)),
      position: position(Keyword.fetch!(validated, :position)),
      data: data,
      mapping: resolve(mapping, plot, data, function),
      fixed: fixed(validated),
      accepted: counted_bar_aesthetics(Stat.Bin.accepted_aesthetics()),
      annotation: false
    }

    add_binning_layer(plot, layer, validated, function)
  end

  # The plot with a binning layer added, once its mappings are checked against binning's, its
  # weight's type and its orientation.
  defp add_binning_layer(plot, layer, validated, function) do
    plot
    |> add_layer(layer, function,
      required: Stat.Bin.required_aesthetics(),
      exclusive: Stat.Bin.exclusive_aesthetics(),
      computed: Stat.Bin.computed_variables(),
      dropped: Stat.Bin.dropped_aesthetics()
    )
    |> check_weight(layer, function)
    |> check_runs_along(layer, validated, function, "bin")
  end

  # A layer function's options, validated against `schema`, their names put in their canonical
  # spelling first, so a repeated option is refused rather than one silently winning.
  defp layer_options(options, schema) do
    options
    |> Aesthetics.canonicalize()
    |> NimbleOptions.validate!(schema)
  end

  # The aesthetics a layer's validated options set for every mark.
  defp fixed(validated) do
    validated
    |> Keyword.take(@fixed_aesthetics)
    |> Map.new()
  end

  # Binning's struct from a layer function's validated options, each not given recorded as `:none`,
  # padded as `pad` says.
  defp bin_stat(validated, pad) do
    center = Keyword.get(validated, :center, :none)
    boundary = Keyword.get(validated, :boundary, :none)

    %Stat.Bin{
      bins: Keyword.fetch!(validated, :bins),
      binwidth: Keyword.get(validated, :binwidth, :none),
      center: as_float(center),
      boundary: as_float(boundary),
      breaks: Keyword.get(validated, :breaks, :none),
      closed: Keyword.fetch!(validated, :closed),
      pad: pad,
      drop: Keyword.fetch!(validated, :drop)
    }
  end

  defp as_float(:none), do: :none
  defp as_float(number), do: number / 1

  # A bin's middle and its edge each place every bin, so a layer takes one of `center:` and
  # `boundary:`, as ggplot2's `stat_bin()` refuses both.
  defp check_bin_placement(validated, function) do
    if Keyword.has_key?(validated, :center) and Keyword.has_key?(validated, :boundary) do
      raise ArgumentError,
            "#{function} takes center: or boundary:, not both, since each places every bin"
    end
  end

  defp position(:stack), do: %Position.Stack{}
  defp position(:dodge), do: %Position.Dodge{}
  defp position(:dodge2), do: position_dodge2()
  defp position(%Position.Dodge2{} = position), do: position

  # A box plot's position: the one given, or, where each box keeps a width of its own, dodging by
  # clusters at each box's own width, as ggplot2's `geom_boxplot()` makes any position named by a
  # string `position_dodge2(preserve = "single")` and switches a `position_dodge2()` that
  # preserves the total, keeping its padding and order (design-log §4, the entry beginning "A box
  # layer dodges by clusters").
  defp boxplot_position(position, false), do: position(position)
  defp boxplot_position(%Position.Dodge2{} = position, true), do: %{position | preserve: :single}
  defp boxplot_position(_named, true), do: position_dodge2(preserve: :single)

  # The box geom's struct from `geom_boxplot/3`'s validated options, each part's look holding only
  # those given.
  defp boxplot_geom(validated) do
    parts = Map.new([:outlier, :whisker, :staple, :median, :box], fn part -> {part, %{}} end)

    looks =
      Enum.reduce(@boxplot_part_looks, parts, fn {option, {part, look}}, given ->
        case Keyword.fetch(validated, option) do
          {:ok, value} -> put_in(given, [part, look], value)
          :error -> given
        end
      end)

    struct!(
      Geom.Boxplot,
      Map.merge(looks, %{
        outliers: Keyword.fetch!(validated, :outliers),
        notch: Keyword.fetch!(validated, :notch),
        notchwidth: Keyword.fetch!(validated, :notchwidth),
        staplewidth: Keyword.fetch!(validated, :staplewidth),
        varwidth: Keyword.fetch!(validated, :varwidth)
      })
    )
  end

  defp path_geom(validated) do
    %Geom.Path{
      line_end: Keyword.fetch!(validated, :lineend),
      line_join: Keyword.fetch!(validated, :linejoin),
      mitre_limit: Keyword.fetch!(validated, :linemitre)
    }
  end

  defp line_geom(validated) do
    %Geom.Line{
      orientation: Keyword.fetch!(validated, :orientation),
      line_end: Keyword.fetch!(validated, :lineend),
      line_join: Keyword.fetch!(validated, :linejoin),
      mitre_limit: Keyword.fetch!(validated, :linemitre)
    }
  end

  defp text_geom(validated),
    do: %Geom.Text{check_overlap: Keyword.fetch!(validated, :check_overlap)}

  # The geom an annotation draws with, a struct of its kind, with the aesthetics it accepts and
  # those it needs, as a layer function of the same geom records them.
  defp annotation_geom(:point, _validated),
    do: {%Geom.Point{}, Geom.Point.accepted_aesthetics(), Geom.Point.required_aesthetics()}

  defp annotation_geom(bar, validated) when bar in [:col, :bar] do
    geom = %Geom.Bar{just: Keyword.fetch!(validated, :just)}
    {geom, Geom.Bar.accepted_aesthetics(), Geom.Bar.required_aesthetics()}
  end

  defp annotation_geom(:path, validated),
    do: {path_geom(validated), Geom.Path.accepted_aesthetics(), Geom.Path.required_aesthetics()}

  defp annotation_geom(:line, validated),
    do: {line_geom(validated), Geom.Line.accepted_aesthetics(), Geom.Line.required_aesthetics()}

  defp annotation_geom(:text, validated),
    do: {text_geom(validated), Geom.Text.accepted_aesthetics(), Geom.Text.required_aesthetics()}

  defp annotation_geom(:rect, _validated),
    do: {%Geom.Rect{}, Geom.Rect.accepted_aesthetics(), Geom.Rect.required_aesthetics()}

  defp position?({aesthetic, _values}), do: Aesthetics.family(aesthetic) != :none

  # How many annotations the options give, as ggplot2's `annotate()` counts them: every option
  # given several values holds as many as each other such, a single value counting once, so their
  # count is the one, or 1 where none has several.
  defp annotation_count(options) do
    several =
      options
      |> Enum.map(fn {aesthetic, values} -> {aesthetic, value_count(values)} end)
      |> Enum.reject(fn {_aesthetic, count} -> count == 1 end)

    case Enum.uniq_by(several, fn {_aesthetic, count} -> count end) do
      [] ->
        1

      [{_aesthetic, count}] ->
        count

      _unequal ->
        raise ArgumentError,
              "Plot.annotate/3 gives " <>
                Enum.map_join(several, " and ", fn {aesthetic, count} ->
                  "#{inspect(aesthetic)} #{count} values"
                end) <>
                "; an option takes one value, or one per annotation, and these disagree on how " <>
                "many annotations there are"
    end
  end

  defp value_count(values) when is_list(values), do: length(values)
  defp value_count(_value), do: 1

  # A position's values, one per annotation: a list of `count` as given, or one value repeated.
  defp recycled(values, count) when is_list(values) and length(values) == count, do: values
  defp recycled([value], count), do: List.duplicate(value, count)
  defp recycled(value, count), do: List.duplicate(value, count)

  # An aesthetic's set value: one value, or a list of several, one per row of the annotation's
  # table, a colour's `:none` in it held as `nil`, the missing value of the column it becomes, as
  # R's `c(NA, "red")` holds `NA`, so it sits beside a colour; a geom reads a missing colour as
  # none.
  defp per_row([value]), do: value
  defp per_row(values) when is_list(values), do: Enum.map(values, &missing_for_none/1)
  defp per_row(value), do: value

  defp missing_for_none(:none), do: nil
  defp missing_for_none(value), do: value

  # Each list an annotation's aesthetic is given becomes a column of the layer's table when the plot
  # is run, so its values are checked here, at the call, as a table checks a column's, of one type,
  # by building that column: `Giggly.DataFrame` raises naming two values that disagree.
  defp check_columns(fixed) do
    fixed
    |> Enum.filter(fn {_aesthetic, value} -> is_list(value) end)
    |> DataFrame.new()

    :ok
  end

  # A weight is summed, so the column a layer's weight comes from must hold numbers, missing ones
  # included, where the call can tell its type: a column's or a constant's. An expression's is its
  # function's to decide, and the layer's stat refuses one that is not a number when the plot is
  # run.
  defp check_weight(plot, layer, function),
    do: check_numbers(plot, layer, function, :weight, "a weight is summed")

  # A mapped width is how wide a bar is drawn, so it must hold numbers, as a weight must; an
  # expression's the bar geom refuses when the plot is run.
  defp check_width(plot, layer, function),
    do: check_numbers(plot, layer, function, :width, "a bar is drawn as wide as its width")

  # The plot, once the column the layer maps `aesthetic` to, where the call can tell its type, is
  # found to hold numbers, as `reason` says it must.
  defp check_numbers(plot, layer, function, aesthetic, reason) do
    mapping = computed_mapping(plot, layer)
    table = drawn_table(plot, layer.data)

    with {:ok, value} <- Map.fetch(mapping, aesthetic),
         dtype when dtype not in [:integer, :float, :null, :computed] <-
           Mapping.dtype(value, table) do
      raise ArgumentError,
            "#{function} maps #{inspect(aesthetic)} to #{inspect(value)}, a #{inspect(dtype)} " <>
              "column, but #{reason}, so it must be a number"
    end

    plot
  end

  # What a layer of bars a stat counts can use: its stat's aesthetics and the bar geom's, but a
  # mapped `:width`, since counting and binning write each bar's width, as ggplot2's do, so a
  # mapped one would do nothing.
  defp counted_bar_aesthetics(statistic_aesthetics) do
    (statistic_aesthetics ++ Geom.Bar.accepted_aesthetics())
    |> Enum.uniq()
    |> Enum.reject(fn aesthetic -> aesthetic == :width end)
  end

  # A counting or binning layer runs along the one of x and y it maps before its stat, so an
  # orientation it is given must name that one; one that does says nothing more, so it is recorded
  # nowhere. `verb` is what the layer does along it, `"count"` or `"bin"`.
  defp check_runs_along(plot, layer, validated, function, verb) do
    [mapped] =
      plot
      |> computed_mapping(layer)
      |> Map.take([:x, :y])
      |> Enum.reject(fn {_aesthetic, value} -> Mapping.stage(value) == :after_stat end)
      |> Enum.map(fn {aesthetic, _value} -> aesthetic end)

    case Keyword.fetch(validated, :orientation) do
      {:ok, given} when given != mapped ->
        raise ArgumentError,
              "#{function} #{verb}s along #{mapped} here, because #{inspect(mapped)} is mapped, " <>
                "so orientation: #{inspect(given)} cannot apply. To #{verb} along #{given}, map " <>
                "#{inspect(given)} instead of #{inspect(mapped)}; orientation: " <>
                "#{inspect(given)} can then stay or be left out."

      _agreeing_or_not_given ->
        plot
    end
  end

  # A box plot is not weighted, so a weight the plot's mapping gives it, which would ride along
  # unused, is refused, where a weighted box would differ (design-log §4, the entry beginning "A
  # weight in the plot's mapping"); one the layer maps itself it cannot use, refused as any such.
  defp check_unweighted(plot, layer, function) do
    mapping = computed_mapping(plot, layer)

    case Map.fetch(mapping, :weight) do
      {:ok, value} ->
        raise ArgumentError,
              "#{function} takes :weight from the plot's mapping, which maps it to " <>
                "#{inspect(value)}, but a box plot is not weighted: each box summarises its " <>
                "rows as they are. Map :weight on the layers that count with it rather than on " <>
                "the plot."

      :error ->
        plot
    end
  end

  # A box plot summarises the one of x and y it maps, where it maps one, its boxes standing along
  # the other, so an orientation it is given must name that other; where it maps both, the
  # orientation chooses (design-log §4, the entry beginning "A box plot's orientation"). Neither
  # is an after_stat here: the summary consumes both, so the layer has refused one already.
  defp check_stands_along(plot, layer, validated, function) do
    mapped =
      plot
      |> computed_mapping(layer)
      |> Map.take([:x, :y])
      |> Map.keys()

    case {mapped, Keyword.fetch(validated, :orientation)} do
      {[summarised], {:ok, summarised}} ->
        other = if summarised == :x, do: :y, else: :x

        raise ArgumentError,
              "#{function} summarises #{summarised} here, because #{inspect(summarised)} alone " <>
                "is mapped, so its boxes stand along #{other} and orientation: " <>
                "#{inspect(summarised)} cannot apply. To stand the boxes along #{summarised}, " <>
                "map #{inspect(other)} instead of #{inspect(summarised)}; orientation: " <>
                "#{inspect(summarised)} can then stay or be left out."

      _agreeing_chosen_or_not_given ->
        plot
    end
  end

  # Each column the layer takes from the plot's mapping, for an aesthetic it neither maps nor sets,
  # must be in the table it draws, as ggplot2 evaluates them there and fails with "object not
  # found"; one the layer cannot use is evaluated too, so it is checked as well. `before_stat` is
  # the mapping it draws with less its after_stats, which read the stat's output instead.
  defp check_inherited(plot, layer, before_stat, function) do
    names =
      plot
      |> drawn_table(layer.data)
      |> DataFrame.names()

    missing =
      before_stat
      |> Map.drop(Map.keys(layer.mapping))
      |> Enum.sort()
      |> Enum.flat_map(fn {aesthetic, value} ->
        value
        |> missing_columns(names)
        |> Enum.map(fn name -> {aesthetic, value, name} end)
      end)

    case missing do
      [] ->
        :ok

      [{aesthetic, value, name} | _others] ->
        raise ArgumentError,
              "#{function} takes #{inspect(aesthetic)} from the plot's mapping, which maps it " <>
                "to #{inspect(value)}, but " <> missing_column_message(name, layer.data, names)
    end
  end

  # Each after_stat the layer draws with, its own or one it takes from the plot's mapping, reads
  # only the variables its stat computes, as ggplot2 documents them, where ggplot2 fails when the
  # plot is built ("Aesthetics must be valid computed stats", or "object not found"); and gives no
  # aesthetic its stat consumes, such as counting's weight, which ggplot2 puts in after the stat,
  # where it does nothing.
  defp check_after_stat(layer, after_stat, function, facts) do
    computed =
      facts
      |> Keyword.get(:computed, [])
      |> Enum.map(&Atom.to_string/1)

    dropped = Keyword.get(facts, :dropped, [])

    after_stat
    |> Enum.sort()
    |> Enum.each(fn {aesthetic, value} ->
      unread =
        value
        |> Mapping.columns()
        |> Enum.reject(fn name -> name in computed end)

      case {aesthetic in dropped, unread} do
        {true, _unread} ->
          raise ArgumentError,
                "#{given_message(layer, aesthetic, value, function)}, but its stat consumes " <>
                  "#{inspect(aesthetic)} as it computes, so a value given after it reaches nothing"

        {false, []} ->
          :ok

        {false, [name | _others]} ->
          raise ArgumentError,
                "#{given_message(layer, aesthetic, value, function)}, but " <>
                  uncomputed_message(name, computed)
      end
    end)
  end

  # Each value the layer draws with, its own or one it takes from the plot's mapping, its columns
  # found, can be computed from the table it draws, as far as the call can tell
  # (`Mapping.check/2`): each function it names by an atom one the table's engine runs, and given
  # numbers where it takes them, where R fails when the plot is built ("non-numeric argument to
  # mathematical function").
  defp check_computable(plot, layer, mapping, function) do
    table = drawn_table(plot, layer.data)

    mapping
    |> Enum.sort()
    |> Enum.each(fn {aesthetic, value} ->
      case Mapping.check(value, table) do
        :ok ->
          :ok

        {:error, reason} ->
          raise ArgumentError,
                "#{given_message(layer, aesthetic, value, function)}, but #{reason}"
      end
    end)
  end

  # How the layer comes to draw `aesthetic` with `value`: its own mapping, or the plot's.
  defp given_message(layer, aesthetic, value, function) do
    if Map.has_key?(layer.mapping, aesthetic),
      do: "#{function} maps #{inspect(aesthetic)} to #{inspect(value)}",
      else:
        "#{function} takes #{inspect(aesthetic)} from the plot's mapping, which maps it to " <>
          inspect(value)
  end

  defp uncomputed_message(_name, []),
    do: "its stat computes no variables, so an after_stat has none to read"

  defp uncomputed_message(name, computed) do
    "its stat computes no variable #{inspect(name)}; an after_stat reads one it computes: " <>
      inspect_all(computed)
  end

  # An aesthetic a layer maps itself that it cannot use would silently do nothing, so it raises.
  defp check_accepted(mapping, accepted, function) do
    unaccepted =
      mapping
      |> Map.keys()
      |> Enum.reject(fn aesthetic -> aesthetic in accepted end)

    case unaccepted do
      [] ->
        :ok

      unaccepted ->
        raise ArgumentError,
              "#{function} cannot use #{inspect_all(unaccepted)}, which its mapping maps; " <>
                "it accepts #{inspect_all(accepted)}"
    end
  end

  # A required aesthetic is a name, or a list of names of which one is enough, as ggplot2 writes
  # `"x|y"`, and is met by an aesthetic the layer maps before its stat or sets, `given`, as ggplot2
  # checks the layer's columns and its `aes_params` together; `unmet` says why one is missing,
  # unless the layer maps it only after its stat (`late`), which needed it to compute, as ggplot2's
  # `stat_count()` "requires an x or y aesthetic".
  defp check_required(given, required, function, unmet, late) do
    case Enum.reject(required, fn needed -> given?(given, needed) end) do
      [] ->
        :ok

      missing ->
        raise ArgumentError,
              "#{function} needs #{Enum.map_join(missing, ", ", &needed_message/1)}, but " <>
                unmet_message(missing, late, unmet)
    end
  end

  defp unmet_message(missing, late, unmet) do
    mapped_late =
      Enum.filter(late, fn aesthetic ->
        Enum.any?(missing, fn needed -> given?([aesthetic], needed) end)
      end)

    case mapped_late do
      [] ->
        unmet

      _mapped ->
        "it maps #{inspect_all(mapped_late)} only after its stat, which needs it to compute"
    end
  end

  defp given?(given, alternatives) when is_list(alternatives),
    do: Enum.any?(alternatives, fn aesthetic -> aesthetic in given end)

  defp given?(given, aesthetic), do: aesthetic in given

  defp needed_message(alternatives) when is_list(alternatives),
    do: "one of #{inspect_all(alternatives)}"

  defp needed_message(aesthetic), do: inspect(aesthetic)

  # Aesthetics of which a layer maps at most one, as counting maps x or y but not both.
  defp check_exclusive(mapping, exclusive, function) do
    Enum.each(exclusive, fn alternatives -> check_one_of(mapping, alternatives, function) end)
  end

  defp check_one_of(mapping, alternatives, function) do
    case Enum.filter(alternatives, fn aesthetic -> Map.has_key?(mapping, aesthetic) end) do
      [_first, _second | _rest] = both ->
        raise ArgumentError,
              "#{function} maps #{inspect_all(both)}, but takes only one of them, " <>
                "since it counts along one and the count is the other"

      _one_or_none ->
        :ok
    end
  end

  # The plot with a continuous scale for `aesthetic` from the options `function` was given,
  # replacing any scale it had for it, as ggplot2 replaces a scale added for an aesthetic that has
  # one. A list of labels needs a list of breaks as long, since the default breaks are not known
  # until the plot is run.
  defp continuous_scale(plot, aesthetic, options, function) do
    validated = NimbleOptions.validate!(options, @continuous_scale_options)
    check_scale_labels(validated, function)
    put_scale(plot, aesthetic, struct!(Scale.Continuous, validated))
  end

  # The plot with a continuous scale for `aesthetic` through `transform`, from the options a
  # transformed scale's function was given, as `continuous_scale/4` makes one.
  defp transformed_scale(plot, aesthetic, transform, options, function) do
    validated = NimbleOptions.validate!(options, @transformed_scale_options)
    check_scale_labels(validated, function)
    put_scale(plot, aesthetic, struct!(Scale.Continuous, [{:transform, transform} | validated]))
  end

  # The plot with a discrete scale for `aesthetic` from the options `function` was given. A list
  # of labels is one for each break given, or else for each limit given; with neither, the number
  # of values is known only when the plot is run.
  defp discrete_scale(plot, aesthetic, options, function) do
    validated = NimbleOptions.validate!(options, @discrete_scale_options)
    check_discrete_labels(validated, function)
    put_scale(plot, aesthetic, struct!(Scale.Discrete, validated))
  end

  # The plot with a date scale for `aesthetic` from the options `function` was given, a width
  # recorded as the breaks or minor breaks it lays and a format as the labels it writes. An option
  # and its `date_` twin choose the same thing, so both are refused.
  defp date_scale(plot, aesthetic, options, function) do
    validated = NimbleOptions.validate!(options, @date_scale_options)
    Enum.each(@date_twins, fn twins -> check_twins(validated, twins, function) end)
    check_scale_labels(validated, function)

    recorded =
      Enum.map(validated, fn
        {:date_breaks, step} -> {:breaks, {:width, step}}
        {:date_minor_breaks, step} -> {:minor_breaks, {:width, step}}
        {:date_labels, format} -> {:labels, {:format, format}}
        option -> option
      end)

    put_scale(plot, aesthetic, struct!(Scale.Continuous, [{:transform, :date} | recorded]))
  end

  defp put_scale(%__MODULE__{scales: scales} = plot, aesthetic, scale),
    do: %{plot | scales: Map.put(scales, aesthetic, scale)}

  # The plot with a scale for `aesthetic`, one other than position, from the options `function` was
  # given, validated against `schema` and built by `scale_of`, replacing any scale it had for it;
  # its labels are checked as a continuous or a discrete scale's are.
  defp legend_scale(plot, aesthetic, options, schema, function, scale_of) do
    validated = NimbleOptions.validate!(options, schema)
    scale = scale_of.(validated)
    check_labels(scale, validated, function)
    put_scale(plot, aesthetic, scale)
  end

  defp check_labels(%Scale.Continuous{}, validated, function),
    do: check_scale_labels(validated, function)

  defp check_labels(%Scale.Discrete{}, validated, function),
    do: check_discrete_labels(validated, function)

  # A discrete scale, its palette `palette`, the rest of its fields, its guide among them,
  # `options`.
  defp discrete_legend(palette, options),
    do: struct!(Scale.Discrete, [{:palette, palette} | options])

  # A continuous scale, its palette `palette`, the rest of its fields, its guide among them,
  # `options`.
  defp continuous_legend(palette, options),
    do: struct!(Scale.Continuous, [{:palette, palette} | options])

  defp manual_scale(validated) do
    {values, options} = Keyword.pop!(validated, :values)
    discrete_legend(manual_palette(values, Keyword.get(options, :breaks)), options)
  end

  # A manual scale's palette: a list of values beside a list of breaks, the values named by the
  # breaks, as ggplot2's `manual_scale()` names them, which leaves the scale's limits its levels;
  # a map, or a list beside no list of breaks, as given.
  defp manual_palette(values, breaks) when is_list(values) and is_list(breaks),
    do: {:manual, values, breaks}

  defp manual_palette(values, _breaks), do: {:manual, values}

  defp hue_scale(validated) do
    {hue, options} = Keyword.split(validated, Keyword.keys(@hue_defaults))
    discrete_legend({:hue, Map.new(hue)}, options)
  end

  defp gray_scale(validated) do
    {start, options} = Keyword.pop!(validated, :start)
    {finish, options} = Keyword.pop!(options, :end)
    discrete_legend({:gray, {start, finish}}, options)
  end

  defp discrete_viridis_scale(validated) do
    {viridis, options} = Keyword.split(validated, Keyword.keys(@viridis_defaults))
    discrete_legend({:viridis, Map.new(viridis)}, options)
  end

  # A continuous colour scale, a gradient through a viridis palette's colours, opaque, as ggplot2's
  # `scale_colour_viridis_c()` takes `pal_gradient_n()` through them.
  defp continuous_viridis_scale(validated) do
    {viridis, options} = Keyword.split(validated, Keyword.keys(@viridis_defaults))

    parameters =
      viridis
      |> Map.new()
      |> Map.put(:alpha, @viridis_defaults[:alpha])

    continuous_legend(
      {:gradient, ColorOperations.viridis(@viridis_gradient_colors, parameters)},
      options
    )
  end

  # A discrete colour scale of its palette's colours, or of the default hues.
  defp discrete_color_scale(validated) do
    case Keyword.pop(validated, :palette) do
      {nil, options} -> discrete_legend({:hue, Map.new(@hue_defaults)}, options)
      {colors, options} -> discrete_legend({:manual, colors}, options)
    end
  end

  defp gradient_scale(validated), do: gradient_through(validated, [:low, :high])
  # A diverging scale, each value placed by its distance from the midpoint, ggplot2's
  # `rescale_mid()`.
  defp gradient2_scale(validated) do
    {midpoint, options} = Keyword.pop!(validated, :midpoint)
    gradient_through([{:rescaler, {:mid, midpoint}} | options], [:low, :mid, :high])
  end

  # A continuous colour scale with a gradient through the colours of the options `names`, in that
  # order.
  defp gradient_through(validated, names) do
    {colors, options} = Keyword.split(validated, names)
    ordered = Enum.map(names, fn name -> Keyword.fetch!(colors, name) end)
    continuous_legend({:gradient, ordered}, options)
  end

  defp gradientn_scale(validated) do
    {colors, options} = Keyword.pop!(validated, :colors)
    continuous_legend({:gradient, colors}, options)
  end

  # A continuous colour scale through its palette's colours, or the default gradient.
  defp continuous_color_scale(validated) do
    {colors, options} = Keyword.pop(validated, :palette, Keyword.values(@gradient_defaults))
    continuous_legend({:gradient, colors}, options)
  end

  defp continuous_alpha_scale(validated) do
    {range, options} = Keyword.pop!(validated, :range)
    continuous_legend({:rescale, range}, options)
  end

  defp discrete_alpha_scale(validated) do
    {range, options} = Keyword.pop!(validated, :range)
    discrete_legend({:sequence, range}, options)
  end

  defp continuous_size_scale(validated) do
    {range, options} = Keyword.pop!(validated, :range)
    continuous_legend({:area, range}, options)
  end

  # A size scale placing each value at its share of the limits' high end, ggplot2's
  # `rescale_max()`, through the square root of that share.
  defp area_size_scale(validated) do
    {max_size, options} = Keyword.pop!(validated, :max_size)
    continuous_legend({:abs_area, max_size}, [{:rescaler, :max} | options])
  end

  defp radius_scale(validated) do
    {range, options} = Keyword.pop!(validated, :range)
    continuous_legend({:rescale, range}, options)
  end

  defp discrete_size_scale(validated) do
    {range, options} = Keyword.pop!(validated, :range)
    discrete_legend({:area_sequence, range}, options)
  end

  defp discrete_shape_scale(validated) do
    {solid, options} = Keyword.pop!(validated, :solid)
    discrete_legend({:shape, shape_fill(solid)}, options)
  end

  defp shape_fill(true), do: :solid
  defp shape_fill(false), do: :open

  defp discrete_linetype_scale(validated), do: discrete_legend(:linetype, validated)

  defp continuous_linewidth_scale(validated) do
    {range, options} = Keyword.pop!(validated, :range)
    continuous_legend({:rescale, range}, options)
  end

  defp discrete_linewidth_scale(validated) do
    {range, options} = Keyword.pop!(validated, :range)
    discrete_legend({:sequence, range}, options)
  end

  defp check_twins(validated, {plain, dated}, function) do
    if Keyword.has_key?(validated, plain) and Keyword.has_key?(validated, dated) do
      raise ArgumentError,
            "#{function} is given both #{inspect(plain)} and #{inspect(dated)}, which choose " <>
              "the same thing; give one"
    end
  end

  defp check_discrete_labels(validated, function) do
    labels = Keyword.get(validated, :labels)

    counted =
      case {Keyword.fetch(validated, :breaks), Keyword.fetch(validated, :limits)} do
        {{:ok, breaks}, _limits} when is_list(breaks) -> {"breaks", breaks}
        {:error, {:ok, limits}} -> {"limits", limits}
        _no_list -> :unknown
      end

    case counted do
      {name, values} when is_list(labels) and length(labels) != length(values) ->
        raise ArgumentError,
              "#{function} is given #{length(labels)} labels, which must be one for each of its " <>
                "#{length(values)} #{name}, #{inspect(values)}"

      _matched ->
        :ok
    end
  end

  defp check_scale_labels(validated, function) do
    case {Keyword.get(validated, :labels), Keyword.fetch(validated, :breaks)} do
      {labels, {:ok, breaks}}
      when is_list(labels) and is_list(breaks) and
             length(labels) == length(breaks) ->
        :ok

      {labels, breaks} when is_list(labels) ->
        raise ArgumentError,
              "#{function} is given #{length(labels)} labels, which need breaks: a list of " <>
                "#{length(labels)} breaks to label, #{given_breaks(breaks)}"

      _no_list ->
        :ok
    end
  end

  defp given_breaks({:ok, breaks}), do: "got: #{inspect(breaks)}"
  defp given_breaks(:error), do: "and it has none"

  # The columns a facet splits on, by name as strings, in the order written. Whether a table holds
  # them is the facet's question, answered when the plot is run, since a layer added later may
  # bring one, as ggplot2 asks it.
  defp facet_columns(facets) do
    references = List.wrap(facets)
    columns = Enum.map(references, &facet_column/1)
    check_facet_columns(columns, references)
    columns
  end

  defp facet_column(reference) when is_column_reference(reference), do: to_string(reference)

  defp facet_column(reference) do
    raise ArgumentError,
          "Plot.facet_wrap/3 facets by #{inspect(reference)}, " <>
            "but a facet names a column, as an atom or a string"
  end

  defp check_facet_columns([], _references) do
    raise ArgumentError, "Plot.facet_wrap/3 needs a column to facet by, and was given none"
  end

  defp check_facet_columns(columns, references) do
    case columns -- Enum.uniq(columns) do
      [] ->
        :ok

      [repeated | _others] ->
        raise ArgumentError,
              "Plot.facet_wrap/3 facets by #{inspect_all(references)}, which names the column " <>
                "#{inspect(repeated)} more than once"
    end
  end

  defp inspect_all(terms), do: Enum.map_join(terms, ", ", &inspect/1)
end
