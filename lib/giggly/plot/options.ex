defmodule Giggly.Plot.Options do
  @moduledoc false

  # The options `Giggly.Plot`'s functions take: each function's NimbleOptions schema, the values
  # its defaults share with the function that reads them (a colour scale's palette when given none,
  # the options that set an aesthetic for every mark, the geoms an annotation draws with), and the
  # checks NimbleOptions calls by name (`{:custom, Giggly.Plot.Options, :validate_alpha, []}`),
  # which are public for that reason alone. `Giggly.Plot` validates every call against a schema
  # here and writes each schema into its functions' documentation while compiling, so an edit here
  # recompiles it.
  #
  # Inside `Giggly.Plot`'s boundary, it reads what its checks need, a colour, a point's shapes, the
  # theme's element tree, a guide's legend and a discrete scale's keys, and nothing that runs a
  # plot, which `GigglyCredo.Check.PlotRunsNothing` holds here as in `Giggly.Plot`.

  alias Giggly.{Aesthetics, ElementTree, Geom, Guide, Theme}
  alias Scales.{ColorOperations, DataRange, Palette, Transform}

  # The values of a continuous or binned scale's `oob:` given by name, R's `oob_*` functions but
  # `oob_discard()`.
  @oob_names [:censor, :censor_any, :squish, :squish_any, :squish_infinite, :keep]

  # A facet's strip labels, ggplot2's labellers: each kind's options, and whether a labeller given
  # alone puts each column's label in a strip of its own. In a keyword list of labellers,
  # `multi_line:` is the list's, as ggplot2's `labeller()` hands its `.multi_line` to each.
  @labeller_kind_options %{
    value: [],
    both: [
      sep: [type: :string, default: ": ", doc: "What goes between a column's name and its value."]
    ],
    context: [],
    wrap: [
      width: [
        type: :pos_integer,
        default: 25,
        doc: "How many columns a line of a label is kept under."
      ]
    ]
  }

  @multi_line_option [
    type: :boolean,
    default: true,
    doc:
      "Whether each column's label is a strip of its own (`true`), or one strip holds them " <>
        "all, joined by `\", \"`."
  ]

  @labeller_kind_schemas Map.new(@labeller_kind_options, fn {kind, options} ->
                           {kind, NimbleOptions.new!(options)}
                         end)

  @labeller_alone_schemas Map.new(@labeller_kind_options, fn {kind, options} ->
                            {kind,
                             options
                             |> Keyword.put(:multi_line, @multi_line_option)
                             |> NimbleOptions.new!()}
                          end)

  @labellers_schema NimbleOptions.new!(
                      rows: [
                        type: {:custom, __MODULE__, :validate_labeller_entry, []},
                        doc: "The labeller of every strip of the rows of panels."
                      ],
                      cols: [
                        type: {:custom, __MODULE__, :validate_labeller_entry, []},
                        doc: "The labeller of every strip of the columns of panels."
                      ],
                      columns: [
                        type: {:custom, __MODULE__, :validate_column_labellers, []},
                        default: %{},
                        doc: "A labeller for each column named, by the column."
                      ],
                      default: [
                        type: {:custom, __MODULE__, :validate_labeller_entry, []},
                        default: :value,
                        doc: "The labeller of every other column."
                      ],
                      multi_line: @multi_line_option
                    )

  @labeller_doc "How each strip is labelled from its panel's values: `:value`, `:both`, " <>
                  "`:context`, `:wrap`, one of them with its options, a function, a map, or a " <>
                  "keyword list labelling each side or column apart, as \"Labelling the " <>
                  "strips\" says."

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
                        ],
                        labeller: [
                          type: {:custom, __MODULE__, :validate_labeller, [:wrap]},
                          default: :value,
                          doc: @labeller_doc
                        ]
                      )

  # `coord_cartesian/2`'s options.
  @coord_cartesian_options NimbleOptions.new!(
                             clip: [
                               type: {:in, [:on, :off]},
                               default: :on,
                               doc:
                                 "Whether what is drawn in each panel is cut off at its edges " <>
                                   "(`:on`), or may run past them (`:off`)."
                             ]
                           )

  # `facet_grid/2`'s options.
  @facet_grid_options NimbleOptions.new!(
                        rows: [
                          type: {:or, [:atom, :string, {:list, {:or, [:atom, :string]}}]},
                          default: [],
                          doc:
                            "The column, or list of columns, whose values give the rows of " <>
                              "panels, each named as a mapping names one."
                        ],
                        cols: [
                          type: {:or, [:atom, :string, {:list, {:or, [:atom, :string]}}]},
                          default: [],
                          doc:
                            "The column, or list of columns, whose values give the columns of " <>
                              "panels, each named as a mapping names one."
                        ],
                        scales: [
                          type: {:in, [:fixed, :free_x, :free_y, :free]},
                          default: :fixed,
                          doc:
                            "Whether the panels share each axis's scale (`:fixed`), or each " <>
                              "column of panels has its own x scale (`:free_x`), each row its " <>
                              "own y scale (`:free_y`), or both (`:free`)."
                        ],
                        labeller: [
                          type: {:custom, __MODULE__, :validate_labeller, [:grid]},
                          default: :value,
                          doc: @labeller_doc
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
    doc:
      "How wide every line is, in millimetres; the theme's `base_line_size` when not given, 0.5 " <>
        "at its default sizes."
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
  # one spelling `Scales.ColorOperations` gives it: uppercase hex, or `:none`.
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
    doc:
      "How big every point is, in millimetres; 1.5 times the theme's `base_size` over 11 when " <>
        "not given, 1.5 at its default sizes."
  ]

  @point_stroke_option [
    type: {:custom, __MODULE__, :validate_stroke, []},
    doc:
      "How heavy every point's outline is, in millimetres, or `:none` for no outline and no " <>
        "lines; the theme's `base_line_size` when not given, 0.5 at its default sizes. The " <>
        "outline is drawn half that wide, and a heavier stroke makes the shape bigger too."
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
    doc:
      "The colour every bar is filled with: " <>
        @color_forms <>
        "; when not given, the theme's ink mixed 35% toward its paper, `#595959`, or " <>
        "`#000000A6` under `theme_void/2`, whose paper is clear."
  ]

  @bar_linewidth_option [
    type: {:custom, __MODULE__, :validate_linewidth, []},
    doc:
      "How wide every bar's border is, in millimetres; the theme's `base_line_size` when not " <>
        "given, 0.5 at its default sizes."
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

  # The units an arrowhead's length may be given in: the theme's but lines of text, which grid
  # measures by the font of the line drawn.
  @arrow_units [:pt, :cm, :mm, :in]

  # An arrowhead's own options, ggplot2's `arrow()` and `arrow.fill`, checked inside `arrow:`.
  @arrow_schema NimbleOptions.new!(
                  angle: [
                    type: {:custom, __MODULE__, :validate_angle, []},
                    default: 30.0,
                    doc: "The angle of each arm from the line, in degrees."
                  ],
                  length: [
                    type: {:custom, __MODULE__, :validate_arrow_length, []},
                    default: {0.25, :in},
                    doc:
                      "How long each arm is, `{amount, unit}` with a unit of " <>
                        "#{inspect(@arrow_units)}."
                  ],
                  ends: [
                    type: {:in, [:last, :first, :both]},
                    default: :last,
                    doc: "Which ends of a line get a head."
                  ],
                  type: [
                    type: {:in, [:open, :closed]},
                    default: :open,
                    doc: "The arms alone (`:open`), or a triangle (`:closed`)."
                  ],
                  fill: [
                    type: {:custom, __MODULE__, :validate_own_color, []},
                    default: :color,
                    doc:
                      "The fill of a closed head: a CSS colour, `:none` for none, or `:color`, " <>
                        "the line's own."
                  ]
                )

  # A layer's arrowheads on its lines, ggplot2's `arrow` and `arrow.fill`.
  @arrow_option [
    type: {:custom, __MODULE__, :validate_arrow, []},
    doc:
      "An arrowhead on each line: `true` for the defaults, or a keyword list of its options, " <>
        "`angle:` (30), `length:` (`{0.25, :in}`, in `:pt`, `:cm`, `:mm` or `:in`), `ends:` " <>
        "(`:last`, `:first` or `:both`), `type:` (`:open` or `:closed`) and `fill:`, a closed " <>
        "head's, a colour, `:none`, or `:color`, the line's colour and the default; none when " <>
        "not given."
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
    :width,
    :height
  ]

  # How far every mark moves from its place, as ggplot2's `nudge_x` and `nudge_y` move it, read
  # only by nudging, so options of every layer function whose marks it moves.
  @nudge_x_option [
    type: {:custom, __MODULE__, :validate_nudge, []},
    doc:
      "How far every mark moves along x from its place, in the units of the x axis, beside " <>
        "`position: :nudge`, which reads it, and refused beside another position; 0 when not " <>
        "given."
  ]

  @nudge_y_option [
    type: {:custom, __MODULE__, :validate_nudge, []},
    doc:
      "How far every mark moves along y from its place, in the units of the y axis, beside " <>
        "`position: :nudge`, which reads it, and refused beside another position; 0 when not " <>
        "given."
  ]

  @nudge_options [nudge_x: @nudge_x_option, nudge_y: @nudge_y_option]

  # How every point of a layer looks, set by its options.
  @point_look_options [
    alpha: @alpha_option,
    color: @point_color_option,
    fill: @point_fill_option,
    shape: @point_shape_option,
    size: @point_size_option,
    stroke: @point_stroke_option
  ]

  # How far a jittered point moves at most along one axis, an option of `geom_jitter/3` and of
  # jittering.
  @jitter_amount_type {:custom, __MODULE__, :validate_jitter_amount, []}

  @jitter_width_option [
    type: @jitter_amount_type,
    doc:
      "How far each point moves at most to either side, in the units of the x axis, 0 or " <>
        "more; 0.4 of the closest spacing of each panel's `x` positions when not given, 0.4 on " <>
        "a discrete axis."
  ]

  @jitter_height_option [
    type: @jitter_amount_type,
    doc:
      "How far each point moves at most up or down, in the units of the y axis, 0 or more; 0.4 " <>
        "of the closest spacing of each panel's `y` positions when not given."
  ]

  # Stacking's options, which filling shares, as ggplot2's `position_fill()` takes
  # `position_stack()`'s.
  @stack_options [
    vjust: [
      type: {:custom, __MODULE__, :validate_number, []},
      default: 1.0,
      doc:
        "Where in its stretch of the pile each mark's `y` moves, any number: 0 its bottom, 0.5 " <>
          "its middle, 1 its top."
    ],
    reverse: [
      type: :boolean,
      default: false,
      doc: "Whether the pile runs from the lowest group at the bottom to the highest."
    ]
  ]

  # Each position's options, by its name, as a layer's `position:` takes it: the name alone, or the
  # name in a tuple with a keyword list of its options, as ggplot2's `position_dodge(width = 0.9)`
  # gives them. A position with no options takes an empty list.
  @position_kind_options %{
    identity: [],
    stack: @stack_options,
    fill: @stack_options,
    dodge: [
      width: [
        type: {:custom, __MODULE__, :validate_width, []},
        doc:
          "How wide the space is that the marks at one position share, in the units of the " <>
            "axis they are dodged along, any number; the panel's first mark's width when not " <>
            "given, so marks with no width of their own, such as line ranges, are not moved."
      ],
      preserve: [
        type: {:in, [:total, :single]},
        default: :total,
        doc:
          "Whether the marks at a position share the whole width (`:total`), or each takes the " <>
            "share it would among the most groups any one position holds, the first share first, " <>
            "so a position with fewer leaves room after them (`:single`)."
      ],
      orientation: [
        type: {:in, [:x, :y]},
        default: :x,
        doc:
          "The axis the marks are dodged along where neither the layer nor its data says which " <>
            "way they run: points or text over two continuous axes, say, which `:y` dodges up " <>
            "the panel. Marks whose one discrete axis is `y` are dodged along y whatever this " <>
            "says, and a layer whose marks always say which way they run, bars, box plots, " <>
            "ranges, lines and areas, takes none."
      ],
      reverse: [
        type: :boolean,
        default: false,
        doc: "Whether the marks at a position run from the highest group to the lowest."
      ]
    ],
    dodge2: [
      width: [
        type: {:custom, __MODULE__, :validate_width, []},
        doc:
          "How wide each mark with no width of its own, such as a point or a line range, is " <>
            "taken to be, in the units of the axis it is dodged along, any number, so each is " <>
            "set side by side with the marks it overlaps, whatever their groups; a layer whose " <>
            "marks have widths of their own, bars, box plots and error bars, takes none."
      ],
      preserve: [
        type: {:in, [:total, :single]},
        default: :total,
        doc:
          "Whether the bars at a position share their whole width (`:total`), or each takes " <>
            "its width over the most bars any one position holds, so a position with fewer " <>
            "leaves room (`:single`)."
      ],
      padding: [
        type: {:custom, __MODULE__, :validate_padding, []},
        default: 0.1,
        doc:
          "How much of its share each bar leaves as a gap, a fraction from 0 to 1, in every " <>
            "panel where some position holds two bars or more."
      ],
      reverse: [
        type: :boolean,
        default: false,
        doc: "Whether the bars at a position run from the highest group to the lowest."
      ]
    ],
    jitter: [
      width: @jitter_width_option,
      height: @jitter_height_option,
      seed: [
        type: :integer,
        default: 0,
        doc:
          "The seed the random distances are drawn from, any integer: the same seed moves the " <>
            "same rows the same way, so another seed draws other distances."
      ]
    ],
    jitterdodge: [
      jitter_width: [
        type: @jitter_amount_type,
        doc:
          "How far each mark moves at most to either side of its share, in the units of the " <>
            "axis it is dodged along, 0 or more, before it is divided by the most groups at one " <>
            "position in any panel plus 2; 0.4 of the closest spacing of the layer's positions " <>
            "along that axis, over every panel, when not given, 0.4 on a discrete axis."
      ],
      jitter_height: [
        type: @jitter_amount_type,
        default: 0.0,
        doc:
          "How far each mark moves at most along the other axis, up or down for marks dodged " <>
            "along x, in that axis's units, 0 or more, so marks move only to the side unless " <>
            "given."
      ],
      dodge_width: [
        type: {:custom, __MODULE__, :validate_width, []},
        default: 0.75,
        doc:
          "How wide the space is that the groups at one position share, in the units of the " <>
            "axis they are dodged along, any number."
      ],
      seed: [
        type: :integer,
        default: 0,
        doc:
          "The seed the random distances are drawn from, any integer: the same seed moves the " <>
            "same rows the same way, so another seed draws other distances."
      ]
    ],
    nudge: []
  }

  # The options a position refuses whatever the marks, each with why it would change nothing,
  # checked before its schema, which holds none of them.
  @position_kind_refused_options %{
    jitterdodge: [
      reverse:
        "the groups at a position are set side by side lowest first whatever it says, as " <>
          "ggplot2's position_jitterdodge() sets them, so it would change nothing"
    ]
  }

  @position_kind_schemas Map.new(@position_kind_options, fn {kind, options} ->
                           {kind, NimbleOptions.new!(options)}
                         end)

  # The positions each family of layers takes, as ggplot2's take them, and those it refuses, each
  # with why R fails or moves nothing (`validate_position/2`). Marks with a width of their own,
  # tiles and rasters, take every position, but no width for dodging by clusters, which R reads
  # only for marks without edges.
  @all_positions [:identity, :stack, :fill, :dodge, :dodge2, :jitter, :jitterdodge, :nudge]

  @width_unread "the marks have edges of their own, which it sets side by side, so a width would " <>
                  "change nothing"
  @orientation_unread "the marks say which way they run, which dodging reads first, so an " <>
                        "orientation would change nothing"

  @positions_with_width [takes: @all_positions, refuses_options: [dodge2: [width: @width_unread]]]

  # Marks with a width of their own that say which way they run, bars, bins, error bars, crossbars
  # and frequency polygons' bins, whose stat or geom writes it in `flipped_aes`, so dodging reads
  # no `orientation`, as R ignores it.
  @oriented_positions_with_width [
    takes: @all_positions,
    refuses_options: [dodge: [orientation: @orientation_unread], dodge2: [width: @width_unread]]
  ]

  # Marks with no width of their own, points, text, paths, segments, rugs, counts and hexagons, are
  # dodged only within a width given, where ggplot2 warns "Width not defined" and moves none.
  @positions_without_width [
    takes: @all_positions,
    needs_width: "the marks have no width of their own to share, so none would move"
  ]

  # Marks with no width of their own that say which way they run, lines, line and point ranges,
  # ribbons, areas, densities and smooths.
  @oriented_positions_without_width [
    takes: @all_positions,
    refuses_options: [dodge: [orientation: @orientation_unread]],
    needs_width: "the marks have no width of their own to share, so none would move"
  ]

  # A box plot's rows have no y once its stat has run, where ggplot2 fails.
  @boxplot_positions [
    takes: [:identity, :dodge, :dodge2, :nudge],
    refuses: [
      stack: "a box plot's rows have no y once its stat has run, which stacking piles",
      fill: "a box plot's rows have no y once its stat has run, which filling piles",
      jitter: "a box plot's rows have no y once its stat has run, which jittering moves",
      jitterdodge:
        "a box plot's rows have no y once its stat has run, which jittering beside dodging moves"
    ],
    refuses_options: [dodge: [orientation: @orientation_unread], dodge2: [width: @width_unread]]
  ]

  # A rectangle has corners and no x or y, so ggplot2 stacks none and fails to jitter one.
  @rect_positions [
    takes: [:identity, :dodge, :dodge2, :nudge],
    refuses: [
      stack: "a rectangle has no x, at which stacking piles marks, so none would move",
      fill: "a rectangle has no x, at which filling piles marks",
      jitter: "a rectangle has no x or y, which jittering moves",
      jitterdodge: "a rectangle has no x or y, which jittering beside dodging moves"
    ],
    refuses_options: [dodge2: [width: @width_unread]]
  ]

  # A reference line has only its intercept, so ggplot2 moves one only by nudging it, stacks none
  # and fails to dodge or jitter one.
  @hline_positions [
    takes: [:identity, :nudge],
    refuses: [
      stack: "a horizontal line has no y, which stacking piles, so none would move",
      fill: "a horizontal line has no y, which filling piles",
      dodge: "a horizontal line has no x, along which dodging sets marks side by side",
      dodge2: "a horizontal line has no x, along which dodging sets marks side by side",
      jitter: "a horizontal line has no x or y, which jittering moves",
      jitterdodge: "a horizontal line has no x or y, which jittering beside dodging moves"
    ]
  ]

  @vline_positions [
    takes: [:identity, :nudge],
    refuses: [
      stack: "a vertical line has no y, which stacking piles, so none would move",
      fill: "a vertical line has no y, which filling piles, so none would move",
      dodge: "a vertical line has no x, along which dodging sets marks side by side",
      dodge2: "a vertical line has no x, along which dodging sets marks side by side",
      jitter: "a vertical line has no x or y, which jittering moves",
      jitterdodge: "a vertical line has no x or y, which jittering beside dodging moves"
    ]
  ]

  # Where a layer's marks are moved once its stat has run, ggplot2's `position`, for marks with a
  # width of their own; its default the function's.
  @position_with_width_option [
    type: {:custom, __MODULE__, :validate_position, [@positions_with_width]},
    doc:
      "Where the marks are moved once the stat has run: left at their positions (`:identity`), " <>
        "piled on one another (`:stack`), piled to the same height (`:fill`), set side by side " <>
        "within the width one mark takes or the width given (`:dodge`), set side by side, each " <>
        "its share of their widths, with a gap between them (`:dodge2`), each moved a small " <>
        "random distance (`:jitter`), set side by side and then each moved a small random " <>
        "distance (`:jitterdodge`), or nudged (`:nudge`), each alone or with its options, as " <>
        "[Positions](#module-positions) says."
  ]

  # The same for marks with no width of their own.
  @position_without_width_option [
    type: {:custom, __MODULE__, :validate_position, [@positions_without_width]},
    doc:
      "Where the marks are moved once the stat has run: left at their positions (`:identity`), " <>
        "piled on one another (`:stack`), piled to the same height (`:fill`), set side by side " <>
        "within the width given, `{:dodge, width: width}`, or each taken as that wide and set " <>
        "side by side with the marks it overlaps, `{:dodge2, width: width}`, having no width of " <>
        "their own to share, each moved a small random distance (`:jitter`), set side by side " <>
        "and then each moved a small random distance (`:jitterdodge`), or nudged (`:nudge`), " <>
        "each alone or with its options, as [Positions](#module-positions) says."
  ]

  # The same two for marks that say which way they run.
  @oriented_position_with_width_option Keyword.put(
                                         @position_with_width_option,
                                         :type,
                                         {:custom, __MODULE__, :validate_position,
                                          [@oriented_positions_with_width]}
                                       )
  @oriented_position_without_width_option Keyword.put(
                                            @position_without_width_option,
                                            :type,
                                            {:custom, __MODULE__, :validate_position,
                                             [@oriented_positions_without_width]}
                                          )

  # Where a layer's marks are drawn, ggplot2's `position`, `:identity` unless given: for marks with
  # a width of their own, error bars and crossbars, tiles and frequency polygons, and for those
  # with none, line ranges, point ranges, lines, segments, ribbons, smooths and hexagons.
  @identity_position_with_width_option Keyword.put(
                                         @position_with_width_option,
                                         :default,
                                         :identity
                                       )
  @identity_position_without_width_option Keyword.put(
                                            @position_without_width_option,
                                            :default,
                                            :identity
                                          )
  @identity_oriented_position_with_width_option Keyword.put(
                                                  @oriented_position_with_width_option,
                                                  :default,
                                                  :identity
                                                )
  @identity_oriented_position_without_width_option Keyword.put(
                                                     @oriented_position_without_width_option,
                                                     :default,
                                                     :identity
                                                   )

  # Where a point layer's points are placed, ggplot2's `position`.
  @point_position_option Keyword.put(@position_without_width_option, :default, :identity)

  # `geom_point/3`'s options, validated at the call.
  @point_options NimbleOptions.new!(
                   [
                     data: @data_option,
                     position: @point_position_option
                   ] ++ @point_look_options ++ @nudge_options
                 )

  # `geom_jitter/3`'s options, validated at the call: a point's, and how far its points move,
  # given either as `width:` and `height:` or as a position.
  @jitter_options NimbleOptions.new!(
                    [
                      data: @data_option,
                      width: @jitter_width_option,
                      height: @jitter_height_option,
                      position: [
                        type:
                          {:custom, __MODULE__, :validate_position, [@positions_without_width]},
                        doc:
                          "Where the points are moved: any position the points of " <>
                            "`geom_point/3` take, as [Positions](#module-positions) says; " <>
                            "refused beside `width:` or `height:`. They move as `width:` and " <>
                            "`height:` say when not given."
                      ]
                    ] ++ @point_look_options ++ @nudge_options
                  )

  # `geom_count/3`'s and `stat_sum/3`'s options, validated at the call.
  @sum_options NimbleOptions.new!(
                 [data: @data_option, position: @point_position_option] ++
                   @point_look_options ++ @nudge_options
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

  # How bars that share an `x` are placed, an option of `geom_bar/3`, `geom_col/3` and the binning
  # functions.
  @bar_position_option Keyword.put(@oriented_position_with_width_option, :default, :stack)

  # `geom_col/3`'s options, validated at the call.
  @bar_options NimbleOptions.new!(
                 [
                   data: @data_option,
                   position: @bar_position_option,
                   width: @bar_width_option,
                   just: @bar_just_option
                 ] ++ @bar_look_options ++ @nudge_options
               )

  # `geom_bar/3`'s options, validated at the call: a bar's, and the axis its counting runs along.
  @count_options NimbleOptions.new!(
                   [
                     data: @data_option,
                     position: @bar_position_option,
                     orientation: @runs_along_option,
                     width: @bar_width_option,
                     just: @bar_just_option
                   ] ++ @bar_look_options ++ @nudge_options
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
                   position: @bar_position_option
                 ] ++ @binning_options ++ @bar_look_options ++ @nudge_options
               )

  # `geom_hex/3`'s and `stat_bin_hex/3`'s options, validated at the call: how the plane is cut into
  # hexagons, how they look, and how their borders are drawn, their corners pointed by default, as
  # ggplot2's `geom_hex()` draws them.
  @hex_options NimbleOptions.new!(
                 [
                   data: @data_option,
                   position: @identity_position_without_width_option,
                   bins: [
                     type: {:custom, __MODULE__, :validate_hex_bins, []},
                     default: 30,
                     doc:
                       "How many hexagons span each axis, when `binwidth:` is not given: a " <>
                         "whole number above 0 for both, or `{x_bins, y_bins}`."
                   ],
                   binwidth: [
                     type: {:custom, __MODULE__, :validate_hex_binwidth, []},
                     doc:
                       "How wide and how high each hexagon is, in the axes' transformed units, " <>
                         "which takes the place of `bins:`: a number above 0 for both, or " <>
                         "`{width, height}`."
                   ],
                   alpha: [
                     type: {:custom, __MODULE__, :validate_alpha, []},
                     doc:
                       "How opaque every hexagon's fill is, from 0, invisible, to 1, opaque; " <>
                         "its border keeps its colour's own alpha."
                   ],
                   color: [
                     type: @color_type,
                     doc:
                       "The colour of every hexagon's border, written `colour:` or `color:`: " <>
                         @color_forms <> "; no border when not given."
                   ],
                   fill: [
                     type: @color_type,
                     doc:
                       "The colour every hexagon is filled with: " <>
                         @color_forms <>
                         "; when not given, each hexagon is filled by its count, through the fill scale."
                   ],
                   linewidth: [
                     type: {:custom, __MODULE__, :validate_linewidth, []},
                     doc:
                       "How wide every hexagon's border is, in millimetres; the theme's " <>
                         "`base_line_size` when not given, 0.5 at its default sizes."
                   ],
                   linetype: [
                     type: @linetype_type,
                     doc:
                       "The line type of every hexagon's border: " <>
                         @linetype_forms <> "; `:solid` when not given."
                   ]
                 ] ++
                   Keyword.replace!(@line_style_options, :linejoin,
                     type: {:in, [:round, :mitre, :bevel]},
                     default: :mitre,
                     doc:
                       "How a border turns a corner: pointed (`:mitre`), rounded (`:round`) or " <>
                         "cut off (`:bevel`)."
                   ) ++ @nudge_options
               )

  # `geom_path/3`'s options, validated at the call.
  @path_options NimbleOptions.new!(
                  [
                    data: @data_option,
                    position: @identity_position_without_width_option,
                    alpha: @alpha_option,
                    color: @line_color_option,
                    linewidth: @linewidth_option,
                    linetype: @linetype_option,
                    arrow: @arrow_option
                  ] ++ @line_style_options ++ @nudge_options
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
                    position: @identity_oriented_position_without_width_option,
                    orientation: @orientation_option,
                    alpha: @alpha_option,
                    color: @line_color_option,
                    linewidth: @linewidth_option,
                    linetype: @linetype_option,
                    arrow: @arrow_option
                  ] ++ @line_style_options ++ @nudge_options
                )

  # How a layer's segments are drawn at their ends and corners: a line's but `linemitre`, which
  # ggplot2's segments do not take, drawing at grid's limit.
  @segment_line_style_options Keyword.take(@line_style_options, [:lineend, :linejoin])

  # `geom_segment/3`'s options, validated at the call.
  @segment_options NimbleOptions.new!(
                     [
                       data: @data_option,
                       position: @identity_position_without_width_option,
                       alpha: @alpha_option,
                       color: @line_color_option,
                       linewidth: @linewidth_option,
                       linetype: @linetype_option,
                       arrow: @arrow_option
                     ] ++ @segment_line_style_options ++ @nudge_options
                   )

  # Which way a layer's ranges run, ggplot2's `orientation`, taken from the ranges given when not
  # given.
  @range_orientation_option [
    type: {:in, [:x, :y]},
    doc:
      "Which way each range runs: `:x`, up the panel from `ymin` to `ymax` at each `x`, or `:y`, " <>
        "across it from `xmin` to `xmax` at each `y`; when not given, `:y` where the layer is " <>
        "given neither `:ymin` nor `:ymax`, and `:x` otherwise."
  ]

  # How every line of a line range or point range layer looks, set by its options.
  @range_look_options [
    alpha: @alpha_option,
    color: @line_color_option,
    linewidth: @linewidth_option,
    linetype: @linetype_option,
    lineend: Keyword.fetch!(@line_style_options, :lineend)
  ]

  # `geom_linerange/3`'s options, validated at the call.
  @linerange_options NimbleOptions.new!(
                       [
                         data: @data_option,
                         position: @identity_oriented_position_without_width_option,
                         orientation: @range_orientation_option
                       ] ++ @range_look_options ++ @nudge_options
                     )

  # How every point of a point range layer looks, set by its options: a point's, but its size and
  # stroke, whose defaults are the point range's own.
  @pointrange_point_options [
    color: [
      type: @color_type,
      doc:
        "The colour of every line and point, written `colour:` or `color:`, which outlines the " <>
          "point's shape and fills the shapes filled in it: " <>
          @color_forms <> "; black when not given."
    ],
    fill: @point_fill_option,
    shape: @point_shape_option,
    size: [
      type: {:custom, __MODULE__, :validate_size, []},
      doc:
        "How big every point is, in millimetres, each drawn four times as big; a third of the " <>
          "theme's points' size when not given, 0.5 at its default sizes."
    ],
    stroke: [
      type: {:custom, __MODULE__, :validate_stroke, []},
      doc:
        "How heavy every point's outline is, in millimetres, or `:none` for no outline and no " <>
          "lines; twice the theme's `base_line_size` when not given, 1 at its default sizes. " <>
          "The outline is drawn half that wide, and a heavier stroke makes the shape bigger too."
    ]
  ]

  # `geom_pointrange/3`'s options, validated at the call.
  @pointrange_options NimbleOptions.new!(
                        [
                          data: @data_option,
                          position: @identity_oriented_position_without_width_option,
                          orientation: @range_orientation_option
                        ] ++
                          Keyword.merge(@range_look_options, @pointrange_point_options) ++
                          @nudge_options
                      )

  # How wide every error bar's or crossbar's whiskers or box are, set by its options.
  @range_width_option [
    type: {:custom, __MODULE__, :validate_width, []},
    doc:
      "How wide every mark is, in the units of the axis it is placed along, x, or y for one " <>
        "that runs across the panel, any number; 0.9 of the closest spacing of the positions " <>
        "there when not given, 0.9 on a discrete axis. It replaces a mapped `:width`."
  ]

  # `geom_errorbar/3`'s options, validated at the call.
  @errorbar_options NimbleOptions.new!(
                      [
                        data: @data_option,
                        position: @identity_oriented_position_with_width_option,
                        orientation: @range_orientation_option,
                        width: @range_width_option
                      ] ++ @range_look_options ++ @nudge_options
                    )

  # A crossbar's parts drawn as lines, each with a look of its own, and how its options' docs name
  # each.
  @crossbar_line_parts [middle: "line across each box", box: "box's border"]

  # The look of each line part, ggplot2's `middle.colour` and the rest, R's dotted names
  # underscored.
  @crossbar_line_look_options Enum.flat_map(@crossbar_line_parts, fn {part, named} ->
                                [
                                  {:"#{part}_color",
                                   [
                                     type: @color_type,
                                     doc:
                                       "The colour of the #{named}, written " <>
                                         "`#{part}_colour:` or `#{part}_color:`: " <>
                                         @color_forms <> "; the crossbar's colour when not given."
                                   ]},
                                  {:"#{part}_linetype",
                                   [
                                     type: @linetype_type,
                                     doc:
                                       "The line type of the #{named}: " <>
                                         @linetype_forms <> "; the crossbar's when not given."
                                   ]},
                                  {:"#{part}_linewidth",
                                   [
                                     type: {:custom, __MODULE__, :validate_linewidth, []},
                                     doc:
                                       "How wide the #{named} is drawn, in millimetres; the " <>
                                         "crossbar's line width when not given" <>
                                         if(part == :middle,
                                           do: ", times 2.5.",
                                           else: "."
                                         )
                                   ]}
                                ]
                              end)

  # Each option giving a part of a crossbar its look, by the part and the look it gives, which the
  # crossbar geom holds by part.
  @crossbar_part_looks for(
                         {part, _named} <- @crossbar_line_parts,
                         look <- [:color, :linetype, :linewidth],
                         do: {:"#{part}_#{look}", {part, look}}
                       )

  # How every crossbar looks, set by its options.
  @crossbar_look_options [
    alpha: [
      type: {:custom, __MODULE__, :validate_alpha, []},
      doc:
        "How opaque every box's fill is, from 0, invisible, to 1, opaque; its lines keep their " <>
          "colour's own alpha."
    ],
    color: [
      type: @color_type,
      doc:
        "The colour of every box's border and line across, written `colour:` or `color:`: " <>
          @color_forms <> "; black when not given."
    ],
    fill: [
      type: @color_type,
      doc: "The colour every box is filled with: " <> @color_forms <> "; none when not given."
    ],
    linewidth: [
      type: {:custom, __MODULE__, :validate_linewidth, []},
      doc:
        "How wide every box's border is, in millimetres, its line across 2.5 times as wide; the " <>
          "theme's `base_line_size` when not given, 0.5 at its default sizes."
    ],
    linetype: [
      type: @linetype_type,
      doc:
        "The line type of every box's border and line across: " <>
          @linetype_forms <> "; `:solid` when not given."
    ]
  ]

  # How a crossbar's lines are drawn at their ends and corners, its corners mitred by default, as
  # ggplot2's `GeomCrossbar` draws them.
  @crossbar_line_style_options [
    lineend: Keyword.fetch!(@line_style_options, :lineend),
    linejoin: [
      type: {:in, [:round, :mitre, :bevel]},
      default: :mitre,
      doc:
        "How a box's border turns a corner: pointed (`:mitre`), rounded (`:round`) or cut off " <>
          "(`:bevel`)."
    ]
  ]

  # `geom_crossbar/3`'s options, validated at the call.
  @crossbar_options NimbleOptions.new!(
                      [
                        data: @data_option,
                        position: @identity_oriented_position_with_width_option,
                        orientation: @range_orientation_option,
                        width: @range_width_option
                      ] ++
                        @crossbar_look_options ++
                        @crossbar_line_look_options ++
                        @crossbar_line_style_options ++ @nudge_options
                    )

  # The sides a rug may be drawn along.
  @rug_sides [:top, :right, :bottom, :left]

  # The units a rug's length may be given in: a share of the panel, or an arrowhead's.
  @rug_length_units [:npc | @arrow_units]

  # How a layer's rugs are drawn: along which sides, how long, which way from the edge and how
  # their ends are cut, ggplot2's `sides`, `length`, `outside` and `lineend`.
  @rug_drawing_options [
    sides: [
      type: {:custom, __MODULE__, :validate_rug_sides, []},
      default: [:bottom, :left],
      doc:
        "The sides of the panel the rugs are drawn along, a list of `:top`, `:right`, " <>
          "`:bottom` and `:left`, each given once: an `x` along the bottom and top, a `y` along " <>
          "the left and right."
    ],
    length: [
      type: {:custom, __MODULE__, :validate_rug_length, []},
      default: {0.03, :npc},
      doc:
        "How long each line is, `{amount, unit}`: a share of the panel (`:npc`), or a length " <>
          "in `:pt`, `:cm`, `:mm` or `:in`."
    ],
    outside: [
      type: :boolean,
      default: false,
      doc:
        "Whether each line runs out from the panel's edge rather than in, which shows only " <>
          "where the panel is not clipped (`coord_cartesian/2`'s `clip: :off`)."
    ],
    lineend: Keyword.fetch!(@line_style_options, :lineend)
  ]

  # How every line of a rug layer looks, set by its options.
  @rug_look_options [
    alpha: @alpha_option,
    color: @line_color_option,
    linewidth: @linewidth_option,
    linetype: @linetype_option
  ]

  # `geom_rug/3`'s options, validated at the call.
  @rug_options NimbleOptions.new!(
                 [
                   data: @data_option,
                   position:
                     Keyword.update!(
                       @identity_position_without_width_option,
                       :doc,
                       fn doc -> doc <> " Jittering needs both `:x` and `:y`." end
                     )
                 ] ++ @rug_look_options ++ @rug_drawing_options ++ @nudge_options
               )

  # How every band of a ribbon or area layer looks, set by its options.
  @band_look_options [
    alpha: [
      type: {:custom, __MODULE__, :validate_alpha, []},
      doc:
        "How opaque every band's fill is, from 0, invisible, to 1, opaque; its outline keeps " <>
          "its colour's own alpha."
    ],
    color: [
      type: @color_type,
      doc:
        "The colour of every band's outline, written `colour:` or `color:`: " <>
          @color_forms <> "; no outline when not given."
    ],
    fill: [
      type: @color_type,
      doc:
        "The colour every band is filled with: " <>
          @color_forms <>
          "; when not given, the theme's ink mixed 20% toward its paper, `#333333`, or " <>
          "`#000000CC` under `theme_void/2`, whose paper is clear."
    ],
    linewidth: [
      type: {:custom, __MODULE__, :validate_linewidth, []},
      doc:
        "How wide every band's outline is, in millimetres; the theme's `base_line_size` when " <>
          "not given, 0.5 at its default sizes."
    ],
    linetype: [
      type: @linetype_type,
      doc:
        "The line type of every band's outline: " <>
          @linetype_forms <> "; `:solid` when not given."
    ]
  ]

  # Which of a band's edges are outlined, ggplot2's `outline.type`, its default the function's own.
  @outline_type_option [
    type: {:in, [:both, :upper, :lower, :full]},
    doc:
      "Which of each band's edges its outline draws: the upper and the lower, each a line " <>
        "(`:both`), the upper alone (`:upper`), the lower alone (`:lower`), or the band's whole " <>
        "border (`:full`)."
  ]

  # `geom_ribbon/3`'s options, validated at the call.
  @ribbon_options NimbleOptions.new!(
                    [
                      data: @data_option,
                      position: @identity_oriented_position_without_width_option,
                      orientation: [
                        type: {:in, [:x, :y]},
                        doc:
                          "The axis each band runs along, `:x` or `:y`; when not given, along " <>
                            "y where the layer is given neither `:ymin` nor `:ymax`, and along " <>
                            "x otherwise. A band along x needs `:ymin` or `:ymax`, and one along " <>
                            "y `:xmin` or `:xmax`."
                      ],
                      outline_type: [default: :both] ++ @outline_type_option
                    ] ++ @band_look_options ++ @line_style_options ++ @nudge_options
                  )

  # `geom_area/3`'s options, validated at the call.
  @area_options NimbleOptions.new!(
                  [
                    data: @data_option,
                    position:
                      Keyword.put(@oriented_position_without_width_option, :default, :stack),
                    orientation: [
                      type: {:in, [:x, :y]},
                      default: :x,
                      doc:
                        "The axis each area runs along: `:x`, from 0 up to its `y`, or `:y`, " <>
                          "from 0 across to its `x`, for areas that run up the panel."
                    ],
                    outline_type: [default: :upper] ++ @outline_type_option
                  ] ++ @band_look_options ++ @line_style_options ++ @nudge_options
                )

  # The geoms `stat_summary/3` draws with, as `geom:` names them, its default first.
  @summary_geoms [:pointrange, :point, :line, :bar, :crossbar, :errorbar, :linerange, :ribbon]

  # The whole summaries `fun_data:` names, each with the arguments it takes and their defaults,
  # Hmisc's and ggplot2's, in the order it records them; `:mean_cl_normal` takes `mult:` too, in
  # place of `conf_int:`, and R's `B` is `resamples:`.
  @summary_data_arguments %{
    mean_se: [mult: 1.0],
    mean_cl_normal: [conf_int: 0.95],
    mean_sdl: [mult: 2.0],
    median_hilow: [conf_int: 0.95],
    mean_cl_boot: [conf_int: 0.95, resamples: 1000, seed: 0]
  }

  # One of a summary's values, `fun:`, `fun_min:` or `fun_max:`.
  @summary_function_type {:custom, __MODULE__, :validate_summary_function, []}

  # The options of `stat_summary/3` whatever its geom: the table, the geom, the summary and which
  # way it runs.
  @summary_stat_options [
    data: @data_option,
    geom: [
      type: {:in, @summary_geoms},
      default: :pointrange,
      doc:
        "What each summary is drawn as: a point range (`:pointrange`), a point (`:point`), a " <>
          "line through each group's (`:line`), a bar from 0 (`:bar`), a crossbar " <>
          "(`:crossbar`), an error bar (`:errorbar`), a line range (`:linerange`), or a band " <>
          "through each group's ranges (`:ribbon`). The other options are those the geom's " <>
          "own function takes, but its `orientation:`, which is the summary's."
    ],
    fun_data: [
      type: {:custom, __MODULE__, :validate_summary_data, []},
      doc:
        "The whole summary at each position, its `y`, `ymin` and `ymax`, by name, alone or in " <>
          "a tuple with its arguments, `{:mean_sdl, mult: 1}`: `:mean_se`, the mean less and " <>
          "plus `mult:` standard errors (1); `:mean_cl_normal`, the mean and its confidence " <>
          "interval at `conf_int:` (0.95, from 0, below 1) from the t distribution, or `mult:` " <>
          "standard errors in place of the t; `:mean_sdl`, the mean less and plus `mult:` " <>
          "standard deviations (2); `:median_hilow`, the median and the quantiles holding " <>
          "`conf_int:` (0.95, 0 to 1) of the values between them, as many either side; and " <>
          "`:mean_cl_boot`, the mean and its bootstrap interval at `conf_int:` (0.95, 0 to " <>
          "1), from `resamples:` (1000) resamples drawn from `seed:` (0), any integer. A " <>
          "`mult:` is any number. Refused beside `fun:`, `fun_min:` or `fun_max:`; `:mean_se` " <>
          "when none of them is given."
    ],
    fun: [
      type: @summary_function_type,
      doc:
        "The summary's `y` at each position: `:mean`, `:median`, `:min` or `:max`, or a " <>
          "function given the values there, a list of numbers in their rows' order, returning " <>
          "a number. Missing when not given beside `fun_min:` or `fun_max:`."
    ],
    fun_min: [
      type: @summary_function_type,
      doc: "The summary's `ymin` at each position, as `fun:` gives its `y`."
    ],
    fun_max: [
      type: @summary_function_type,
      doc: "The summary's `ymax` at each position, as `fun:` gives its `y`."
    ],
    orientation: [
      type: {:in, [:x, :y]},
      doc:
        "Which way the summary runs: `:x`, the `y` values summarised at each `x`, or `:y`, the " <>
          "`x` values at each `y`; when not given, `:y` where `y` alone is discrete, and `:x` " <>
          "otherwise."
    ]
  ]

  # `stat_summary/3`'s options for each geom it draws with, validated at the call: the summary's,
  # and the geom's function's but its orientation.
  @summary_options %{
    pointrange:
      NimbleOptions.new!(
        @summary_stat_options ++
          [position: @identity_oriented_position_without_width_option] ++
          Keyword.merge(@range_look_options, @pointrange_point_options) ++
          @nudge_options
      ),
    point:
      NimbleOptions.new!(
        @summary_stat_options ++
          [position: @identity_oriented_position_without_width_option] ++
          @point_look_options ++
          @nudge_options
      ),
    line:
      NimbleOptions.new!(
        @summary_stat_options ++
          [
            position: @identity_oriented_position_without_width_option,
            alpha: @alpha_option,
            color: @line_color_option,
            linewidth: @linewidth_option,
            linetype: @linetype_option,
            arrow: @arrow_option
          ] ++
          @line_style_options ++
          @nudge_options
      ),
    bar:
      NimbleOptions.new!(
        @summary_stat_options ++
          [
            position: @identity_oriented_position_with_width_option,
            width: @bar_width_option,
            just: @bar_just_option
          ] ++
          @bar_look_options ++
          @nudge_options
      ),
    crossbar:
      NimbleOptions.new!(
        @summary_stat_options ++
          [position: @identity_oriented_position_with_width_option, width: @range_width_option] ++
          @crossbar_look_options ++
          @crossbar_line_look_options ++
          @crossbar_line_style_options ++
          @nudge_options
      ),
    errorbar:
      NimbleOptions.new!(
        @summary_stat_options ++
          [position: @identity_oriented_position_with_width_option, width: @range_width_option] ++
          @range_look_options ++
          @nudge_options
      ),
    linerange:
      NimbleOptions.new!(
        @summary_stat_options ++
          [position: @identity_oriented_position_without_width_option] ++
          @range_look_options ++
          @nudge_options
      ),
    ribbon:
      NimbleOptions.new!(
        @summary_stat_options ++
          [
            position: @identity_oriented_position_without_width_option,
            outline_type: [default: :both] ++ @outline_type_option
          ] ++
          @band_look_options ++ @line_style_options ++ @nudge_options
      )
  }

  # How a layer of densities estimates each group's, options of `geom_density/3` and
  # `stat_density/3`.
  @density_estimate_options [
    bw: [
      type: {:custom, __MODULE__, :validate_bandwidth, []},
      default: :nrd0,
      doc:
        "How smooth each curve is, its bandwidth, the kernel's standard deviation in the axis's " <>
          "transformed units: a number above 0, or a rule worked out from each group's rows, " <>
          "taking no weight: Silverman's rule of thumb (`:nrd0`), 0.9 times the lesser of the " <>
          "rows' standard deviation and their interquartile range over 1.34, times the rows to " <>
          "the power -0.2, or Scott's variation of it (`:nrd`), 1.06 times the lesser."
    ],
    adjust: [
      type: {:custom, __MODULE__, :validate_adjust, []},
      default: 1.0,
      doc:
        "A multiple of the bandwidth, above 0: `adjust: 0.5` halves it, for a curve that " <>
          "follows the rows more closely, and `adjust: 2` doubles it, for a smoother one."
    ],
    kernel: [
      type:
        {:in,
         [:gaussian, :epanechnikov, :rectangular, :triangular, :biweight, :cosine, :optcosine]},
      default: :gaussian,
      doc:
        "The shape put at each row and summed, scaled so its standard deviation is the " <>
          "bandwidth: a normal curve (`:gaussian`), a parabola (`:epanechnikov`), a block " <>
          "(`:rectangular`), a tent (`:triangular`), a parabola squared (`:biweight`), or a " <>
          "cosine's hump (`:cosine`) or a narrower one (`:optcosine`)."
    ],
    n: [
      type: :pos_integer,
      default: 512,
      doc:
        "How many evenly spaced places each curve is worked out at, twice as many with one " <>
          "finite bound and three times with two."
    ],
    trim: [
      type: :boolean,
      default: false,
      doc:
        "Whether each curve spans only its own group's extent rather than the panel's axis, " <>
          "short of its widening; trimmed curves no longer share their places, so they do not " <>
          "stack."
    ],
    bounds: [
      type: {:custom, __MODULE__, :validate_bounds, []},
      default: {:neg_infinity, :infinity},
      doc:
        "Limits the rows are known to lie within, `{low, high}`, the low a number or " <>
          "`:neg_infinity`, the high a number or `:infinity`, not below the low: the rows " <>
          "outside them are left out, and each curve's part beyond a finite one is folded back " <>
          "inside it, so the curve does not spill past a limit the data cannot."
    ],
    orientation: @runs_along_option
  ]

  # How every curve of a `geom_density/3` layer looks, set by its options.
  @density_look_options [
    alpha: [
      type: {:custom, __MODULE__, :validate_alpha, []},
      doc:
        "How opaque every curve's fill is, from 0, invisible, to 1, opaque; its outline keeps " <>
          "its colour's own alpha."
    ],
    color: [
      type: @color_type,
      doc:
        "The colour of every curve's outline, written `colour:` or `color:`: " <>
          @color_forms <> "; the theme's ink, black, when not given."
    ],
    fill: [
      type: @color_type,
      doc:
        "The colour every curve is filled with down to 0: " <>
          @color_forms <> "; none when not given."
    ],
    linewidth: [
      type: {:custom, __MODULE__, :validate_linewidth, []},
      doc:
        "How wide every curve's outline is, in millimetres; the theme's `base_line_size` when " <>
          "not given, 0.5 at its default sizes."
    ],
    linetype: [
      type: @linetype_type,
      doc:
        "The line type of every curve's outline: " <>
          @linetype_forms <> "; `:solid` when not given."
    ]
  ]

  # `geom_density/3`'s options, validated at the call: how each curve is estimated, and how it
  # looks.
  @density_options NimbleOptions.new!(
                     [
                       data: @data_option,
                       position: @identity_oriented_position_without_width_option,
                       outline_type: [default: :upper] ++ @outline_type_option
                     ] ++
                       @density_estimate_options ++
                       @density_look_options ++ @line_style_options ++ @nudge_options
                   )

  # How an area of densities' outline is drawn, `stat_density/3`'s: a line's, its corners given no
  # default, so a key's are mitred where the layer gives none.
  @stat_density_line_style_options Keyword.replace!(@line_style_options, :linejoin,
                                     type: {:in, [:round, :mitre, :bevel]},
                                     doc:
                                       "How a line turns a corner: rounded (`:round`), pointed " <>
                                         "(`:mitre`) or cut off (`:bevel`); when not given, " <>
                                         "rounded, and pointed in a legend's keys."
                                   )

  # `stat_density/3`'s options, validated at the call: how each curve is estimated, and how its
  # area looks.
  @stat_density_options NimbleOptions.new!(
                          [
                            data: @data_option,
                            position:
                              Keyword.put(
                                @oriented_position_without_width_option,
                                :default,
                                :stack
                              ),
                            outline_type: [default: :both] ++ @outline_type_option
                          ] ++
                            @density_estimate_options ++
                            @band_look_options ++
                            @stat_density_line_style_options ++ @nudge_options
                        )

  # How every violin of a layer looks, set by its options.
  @violin_look_options [
    alpha: [
      type: {:custom, __MODULE__, :validate_alpha, []},
      doc:
        "How opaque every violin's fill and quantile lines are, from 0, invisible, to 1, " <>
          "opaque; its border keeps its colour's own alpha."
    ],
    color: [
      type: @color_type,
      doc:
        "The colour of every violin's border, written `colour:` or `color:`: " <>
          @color_forms <>
          "; when not given, the theme's ink mixed 20% toward its paper, `#333333`, or " <>
          "`#000000CC` under `theme_void/2`."
    ],
    fill: [
      type: @color_type,
      doc:
        "The colour every violin is filled with: " <>
          @color_forms <>
          "; the theme's paper when not given, white, or clear under `theme_void/2`."
    ],
    linewidth: [
      type: {:custom, __MODULE__, :validate_linewidth, []},
      doc:
        "How wide every violin's border is, in millimetres; the theme's `base_line_size` when " <>
          "not given, 0.5 at its default sizes."
    ],
    linetype: [
      type: @linetype_type,
      doc:
        "The line type of every violin's border: " <>
          @linetype_forms <> "; `:solid` when not given."
    ]
  ]

  # How a violin's lines across it at its quantiles look, set by its options: hidden unless a line
  # type is given, each other look its violin's where not given.
  @violin_quantile_options [
    quantile_color: [
      type: @color_type,
      doc:
        "The colour of the lines across each violin at the quantiles its densities mark, " <>
          "written `quantile_colour:` or `quantile_color:`: " <>
          @color_forms <> "; its violin's border colour when not given."
    ],
    quantile_linetype: [
      type: @linetype_type,
      default: :blank,
      doc:
        "The line type of the lines across each violin at the quantiles its densities mark " <>
          "(`quantiles:`): " <>
          @linetype_forms <> "; `:blank`, drawing none, when not given."
    ],
    quantile_linewidth: [
      type: {:custom, __MODULE__, :validate_linewidth, []},
      doc:
        "How wide the quantile lines are, in millimetres; their violin's border width when not " <>
          "given."
    ]
  ]

  # Each option giving a violin's quantile lines a look, by the look it gives, which the violin
  # geom holds.
  @violin_quantile_looks [
    quantile_color: :color,
    quantile_linetype: :linetype,
    quantile_linewidth: :linewidth
  ]

  # How a violin layer's legend keys are drawn: the violins themselves are always drawn with butt
  # ends and round corners, as ggplot2 never hands a violin its layer's `lineend` and `linejoin`,
  # and no mitre limit is taken, as ggplot2 reads none for a violin or its key.
  @violin_line_style_options [
    lineend: [
      type: {:in, [:butt, :round, :square]},
      default: :butt,
      doc:
        "How the borders of the legend's keys end: cut square at the end (`:butt`), rounded " <>
          "(`:round`), or cut square half the line's width beyond it (`:square`); the violins' " <>
          "own borders are always cut square at the end."
    ],
    linejoin: [
      type: {:in, [:round, :mitre, :bevel]},
      default: :mitre,
      doc:
        "How the borders of the legend's keys turn a corner: pointed (`:mitre`), rounded " <>
          "(`:round`) or cut off (`:bevel`); the violins' own borders always turn rounded."
    ]
  ]

  # `geom_violin/3`'s and `stat_ydensity/3`'s options, validated at the call: how each group's
  # densities are estimated and scaled, where its violin stands, and how it looks.
  @violin_options NimbleOptions.new!(
                    [
                      data: @data_option,
                      position:
                        Keyword.put(@oriented_position_with_width_option, :default, :dodge)
                    ] ++
                      Keyword.take(@density_estimate_options, [:bw, :adjust, :kernel]) ++
                      [
                        trim: [
                          type: :boolean,
                          default: true,
                          doc:
                            "Whether each violin spans only its own group's extent; `false` " <>
                              "reaches three of the rule's bandwidths, before `adjust:`, past " <>
                              "it either end, so its tails show."
                        ],
                        bounds: Keyword.fetch!(@density_estimate_options, :bounds),
                        scale: [
                          type: {:in, [:area, :count, :width]},
                          default: :area,
                          doc:
                            "How the violins are sized beside one another: each the same area " <>
                              "(`:area`), as wide as its density makes it beside the panel's " <>
                              "greatest; that times its rows over the panel's most, so a violin " <>
                              "of more rows is bigger (`:count`); or each as wide at its widest " <>
                              "(`:width`)."
                        ],
                        quantiles: [
                          type: {:custom, __MODULE__, :validate_quantiles, []},
                          default: [0.25, 0.5, 0.75],
                          doc:
                            "The quantiles of each group's `y` the densities mark, each a row " <>
                              "of its own whose `quantile` is its probability, a list of numbers " <>
                              "from 0 to 1, or `:none` for no `quantile` column at all."
                        ],
                        drop: [
                          type: :boolean,
                          default: true,
                          doc:
                            "Whether to leave out a group of fewer than two rows, or, `false`, " <>
                              "keep it as one row of missing densities, so a position makes room " <>
                              "for it."
                        ],
                        width: [
                          type: {:custom, __MODULE__, :validate_width, []},
                          doc:
                            "How wide a violin's room is, in the units of the axis it stands " <>
                              "on, any number; it replaces a mapped `:width`, and gives way to " <>
                              "0.9 of the range of a group spanning several positions. 0.9 times " <>
                              "the closest spacing of the positions, counting from zero, when " <>
                              "not given."
                        ],
                        orientation: [
                          type: {:in, [:x, :y]},
                          doc:
                            "The axis the violins stand along, `:x` or `:y`, estimating the " <>
                              "other; when not given they stand along the discrete one, or else " <>
                              "along the axis on which every group holds one value, or else " <>
                              "along x."
                        ]
                      ] ++
                      @violin_look_options ++
                      @violin_quantile_options ++
                      @violin_line_style_options ++ @nudge_options
                  )

  # `geom_smooth/3`'s and `stat_smooth/3`'s options, validated at the call: how each curve is
  # fitted, and how its line and band look.
  @smooth_options NimbleOptions.new!(
                    [
                      data: @data_option,
                      position: @identity_oriented_position_without_width_option,
                      method: [
                        type: {:in, [:lm, :loess, :gam]},
                        doc:
                          "How each curve is fitted: `:lm`, a straight line by least squares; " <>
                            "`:loess`, at each place a quadratic fitted to the nearest rows, " <>
                            "nearer ones weighing more; or `:gam`, a smoothing spline, its " <>
                            "wiggliness chosen from the rows; each row weighted too by its " <>
                            "`:weight` where one is mapped. When not given, loess where the " <>
                            "largest group in any panel holds under 1,000 rows, and gam from there."
                      ],
                      se: [
                        type: :boolean,
                        default: true,
                        doc:
                          "Whether each curve is drawn over its band, the confidence interval " <>
                            "around it at `level:`."
                      ],
                      level: [
                        type: {:custom, __MODULE__, :validate_level, []},
                        default: 0.95,
                        doc: "How confident each band is, above 0 and below 1."
                      ],
                      n: [
                        type: :pos_integer,
                        default: 80,
                        doc: "How many evenly spaced places along x each curve is worked out at."
                      ],
                      span: [
                        type: {:custom, __MODULE__, :validate_span, []},
                        default: 0.75,
                        doc:
                          "How much of a group each loess fit reads, above 0: the share of its " <>
                            "rows nearest each place, so a smaller span follows the rows more " <>
                            "closely; only loess reads it."
                      ],
                      fullrange: [
                        type: :boolean,
                        default: false,
                        doc:
                          "Whether each curve spans the panel's axis it runs along, short of its " <>
                            "widening, rather than its own group's extent along it."
                      ],
                      orientation: [
                        type: {:in, [:x, :y]},
                        default: :x,
                        doc:
                          "The axis each curve runs along: `:x`, y fitted to x, or `:y`, x " <>
                            "fitted to y, for a curve that runs up the panel."
                      ],
                      alpha: [
                        type: {:custom, __MODULE__, :validate_alpha, []},
                        doc:
                          "How opaque every band's fill is, from 0, invisible, to 1, opaque; 0.4 " <>
                            "when not given. The line keeps its colour's own alpha."
                      ],
                      color: [
                        type: @color_type,
                        doc:
                          "The colour of every curve's line, written `colour:` or `color:`: " <>
                            @color_forms <> "; the theme's accent, `#3366FF`, when not given."
                      ],
                      fill: [
                        type: @color_type,
                        doc:
                          "The colour every band is filled with: " <>
                            @color_forms <>
                            "; when not given, the theme's ink mixed 60% toward its paper, " <>
                            "`#999999`, or `#00000066` under `theme_void/2`, whose paper is clear."
                      ],
                      linewidth: [
                        type: {:custom, __MODULE__, :validate_linewidth, []},
                        doc:
                          "How wide every curve's line is, in millimetres; twice the theme's " <>
                            "`base_line_size` when not given, 1 at its default sizes."
                      ],
                      linetype: @linetype_option
                    ] ++ @line_style_options ++ @nudge_options
                  )

  # How a frequency polygon cuts its axis into bins: binning's options but `pad`, which a frequency
  # polygon always takes.
  @freqpoly_binning_options Keyword.delete(@binning_options, :pad)

  # `geom_freqpoly/3`'s options, validated at the call: how the axis is cut into bins, and a path's.
  @freqpoly_options NimbleOptions.new!(
                      [
                        data: @data_option,
                        position: @identity_oriented_position_with_width_option
                      ] ++
                        @freqpoly_binning_options ++
                        [
                          alpha: @alpha_option,
                          color: @line_color_option,
                          linewidth: @linewidth_option,
                          linetype: @linetype_option,
                          arrow: @arrow_option
                        ] ++ @line_style_options ++ @nudge_options
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
                         type: {:custom, __MODULE__, :validate_position, [@boxplot_positions]},
                         default: :dodge2,
                         doc:
                           "Where the boxes are moved once the stat has run: set side by side, " <>
                             "each its share of their widths, with a gap between them " <>
                             "(`:dodge2`), set side by side within the width one box takes or " <>
                             "the width given (`:dodge`), left at their positions " <>
                             "(`:identity`), or nudged (`:nudge`), each alone or with its " <>
                             "options, as [Positions](#module-positions) says. With " <>
                             "`varwidth: true`, every box keeps its own width, which only " <>
                             "`:dodge2` lays side by side, and so it is the only position " <>
                             "taken, its `preserve:` `:single`."
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
                             "`geom_point/3` takes one, or `:none` for none; the box's `:shape` " <>
                             "when not given."
                       ],
                       outlier_size: [
                         type: {:custom, __MODULE__, :validate_size, []},
                         doc:
                           "How big the outliers are, in millimetres; the box's `:size`, " <>
                             "the theme's points' size unless the layer sets one, when not given."
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
                               "or `color:`: " <>
                               @color_forms <>
                               "; when not given, the theme's ink mixed 20% toward its paper, " <>
                               "`#333333`, or `#000000CC` under `theme_void/2`."
                         ],
                         fill: [
                           type: @color_type,
                           doc:
                             "The colour every box is filled with: " <>
                               @color_forms <>
                               "; the theme's paper when not given, white, or clear under " <>
                               "`theme_void/2`."
                         ],
                         linewidth: [
                           type: {:custom, __MODULE__, :validate_linewidth, []},
                           doc:
                             "How wide every box's lines are, in millimetres; the theme's " <>
                               "`base_line_size` when not given, 0.5 at its default sizes."
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
                       ] ++ @nudge_options
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
        "How big every label is, in millimetres, each 2.85 points; the theme's `base_size` " <>
          "when not given, 11 points at its default sizes."
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
        ~s(The font every label is drawn in, by name, such as `"Times New Roman"`, or one ) <>
          ~s(of the generic families `"sans"`, `"serif"` and `"mono"`; the theme's ) <>
          "`base_family` when not given, the default sans-serif at its default. How a label " <>
          "is measured and drawn in it: the [fonts guide](fonts.md)."
    ]
  ]

  # `geom_text/3`'s options, validated at the call.
  @text_options NimbleOptions.new!(
                  [
                    data: @data_option,
                    position: Keyword.put(@position_without_width_option, :default, :nudge),
                    check_overlap: @check_overlap_option,
                    alpha: @alpha_option,
                    color: @text_color_option
                  ] ++ @text_style_options ++ @nudge_options
                )

  # A label's colour, its text's and its border's unless the layer gives them apart.
  @label_color_option [
    type: @color_type,
    doc:
      "The colour of every label's text and border, written `colour:` or `color:`: " <>
        @color_forms <> "; black when not given. Neither takes `alpha:`, only its colour's own."
  ]

  # How every label's box is drawn, options of `geom_label/3` and its annotation.
  @label_box_options [
    label_padding: [
      type: {:custom, __MODULE__, :validate_label_padding, []},
      default: {0.25, :lines},
      doc:
        "The room round every label's text inside its box: one length for " <>
          "every side, or a keyword list of `:top`, `:right`, `:bottom` and " <>
          "`:left`, a side left out 0; each a number of points or " <>
          "`{amount, unit}` with a unit of `:pt`, `:cm`, `:mm`, `:in` or " <>
          "`:lines`, lines of the label's own text. The text sits the " <>
          "bottom's padding above the box's bottom, its descent within it, " <>
          "and the top's is at least the descent."
    ],
    label_r: [
      type: {:custom, __MODULE__, :validate_label_r, []},
      default: {0.15, :lines},
      doc:
        "The radius of every label's box's corners, a length as " <>
          "`label_padding:` takes one; 0 for square corners."
    ],
    border_color: [
      type: {:custom, __MODULE__, :validate_own_color, []},
      default: :color,
      doc:
        "The colour of every label's border apart from its text, written " <>
          "`border_colour:` or `border_color:`: " <>
          @color_forms <>
          ", or `:color`, the label's own colour, when not given."
    ],
    text_color: [
      type: {:custom, __MODULE__, :validate_own_color, []},
      default: :color,
      doc:
        "The colour of every label's text apart from its border, written " <>
          "`text_colour:` or `text_color:`: " <>
          @color_forms <>
          ", or `:color`, the label's own colour, when not given."
    ]
  ]

  # `geom_label/3`'s options, validated at the call.
  @label_options NimbleOptions.new!(
                   [
                     data: @data_option,
                     position: Keyword.put(@position_without_width_option, :default, :nudge),
                     alpha: [
                       type: {:custom, __MODULE__, :validate_alpha, []},
                       doc:
                         "How opaque every label's box is, from 0, invisible, to 1, opaque; its " <>
                           "text and border keep their colour's own."
                     ],
                     color: @label_color_option,
                     fill: [
                       type: @color_type,
                       doc:
                         "The colour every label's box is filled with: " <>
                           @color_forms <>
                           "; the theme's paper, white, when not given."
                     ],
                     linewidth: [
                       type: {:custom, __MODULE__, :validate_linewidth, []},
                       doc:
                         "How wide every label's border is, in millimetres, 0 for none; half " <>
                           "the theme's `base_line_size` when not given, 0.25 at its default " <>
                           "sizes."
                     ],
                     linetype: [
                       type: @linetype_type,
                       doc:
                         "The line type of every label's border: " <>
                           @linetype_forms <> "; `:solid` when not given."
                     ]
                   ] ++
                     @text_style_options ++
                     @label_box_options ++ @nudge_options
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
        @color_forms <>
        "; when not given, the theme's ink mixed 35% toward its paper, `#595959`, or " <>
        "`#000000A6` under `theme_void/2`, whose paper is clear."
  ]

  @rect_linewidth_option [
    type: {:custom, __MODULE__, :validate_linewidth, []},
    doc:
      "How wide every rectangle's border is, in millimetres; the theme's `base_line_size` when " <>
        "not given, 0.5 at its default sizes."
  ]

  @rect_linetype_option [
    type: @linetype_type,
    doc:
      "The line type of every rectangle's border: " <>
        @linetype_forms <> "; `:solid` when not given."
  ]

  @tile_fill_option [
    type: @color_type,
    doc:
      "The colour every tile is filled with: " <>
        @color_forms <>
        "; when not given, the theme's ink mixed 20% toward its paper, `#333333`, or " <>
        "`#000000CC` under `theme_void/2`, whose paper is clear."
  ]

  @tile_linewidth_option [
    type: {:custom, __MODULE__, :validate_linewidth, []},
    doc:
      "How wide every tile's border is, in millimetres; 0.4 times the theme's " <>
        "`base_line_size` when not given, 0.2 at its default sizes."
  ]

  # `geom_tile/3`'s options, validated at the call.
  @tile_options NimbleOptions.new!(
                  data: @data_option,
                  position: @identity_position_with_width_option,
                  alpha: @alpha_option,
                  color: [
                    type: @color_type,
                    doc:
                      "The colour of every tile's border, written `colour:` or `color:`: " <>
                        @color_forms <>
                        "; no border when not given. A border takes no alpha but its colour's " <>
                        "own."
                  ],
                  fill: @tile_fill_option,
                  linewidth: @tile_linewidth_option,
                  linetype: [
                    type: @linetype_type,
                    doc:
                      "The line type of every tile's border: " <>
                        @linetype_forms <> "; `:solid` when not given."
                  ],
                  width: [
                    type: {:custom, __MODULE__, :validate_width, []},
                    doc:
                      "How wide every tile is, in the units of the x axis, any number; it " <>
                        "replaces the width the tiles would take otherwise, and a mapped `:width`."
                  ],
                  height: [
                    type: {:custom, __MODULE__, :validate_height, []},
                    doc:
                      "How tall every tile is, in the units of the y axis, as `width:` sets a " <>
                        "width."
                  ],
                  nudge_x: @nudge_x_option,
                  nudge_y: @nudge_y_option
                )

  # Where every raster cell sits against its position, along one axis: an option of
  # `geom_raster/3` that chooses how the raster geom draws.
  @raster_just_doc "a number from 0 to 1: 0 puts the cell's right or top edge there, 1 its left " <>
                     "or bottom edge, and 0.5 centres it."

  # `geom_raster/3`'s options, validated at the call.
  @raster_options NimbleOptions.new!(
                    data: @data_option,
                    position: @identity_position_with_width_option,
                    alpha: @alpha_option,
                    fill: [
                      type: @color_type,
                      doc:
                        "The colour every cell is filled with: " <>
                          @color_forms <>
                          "; when not given, the theme's ink mixed 20% toward its paper, " <>
                          "`#333333`, or `#000000CC` under `theme_void/2`, whose paper is clear."
                    ],
                    hjust: [
                      type: {:custom, __MODULE__, :validate_just, []},
                      default: 0.5,
                      doc: "Where each cell sits across against its `x`, " <> @raster_just_doc
                    ],
                    vjust: [
                      type: {:custom, __MODULE__, :validate_just, []},
                      default: 0.5,
                      doc: "Where each cell sits up against its `y`, " <> @raster_just_doc
                    ],
                    interpolate: [
                      type: :boolean,
                      default: false,
                      doc:
                        "Whether a viewer blends neighbouring cells' colours, smoothing the " <>
                          "image, rather than drawing each cell as a block of its colour."
                    ],
                    nudge_x: @nudge_x_option,
                    nudge_y: @nudge_y_option
                  )

  # A rectangle's corner set for every rectangle of a layer, as ggplot2's `xmin = 3` sets it.
  @corner_type {:custom, __MODULE__, :validate_corner, []}

  # `geom_rect/3`'s options, validated at the call.
  @rect_options NimbleOptions.new!(
                  data: @data_option,
                  position: [
                    type: {:custom, __MODULE__, :validate_position, [@rect_positions]},
                    default: :identity,
                    doc:
                      "Where the rectangles are moved: left at their positions (`:identity`), " <>
                        "set side by side within the width one takes or the width given " <>
                        "(`:dodge`), set side by side, each its share of their widths, with a " <>
                        "gap between them (`:dodge2`), or nudged (`:nudge`), each alone or " <>
                        "with its options, as [Positions](#module-positions) says."
                  ],
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
                  ],
                  nudge_x: @nudge_x_option,
                  nudge_y: @nudge_y_option
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
                     linetype: @linetype_option,
                     arrow: @arrow_option
                   ] ++ @line_style_options
  @segment_annotation [
                        x: @annotation_position,
                        y: @annotation_position,
                        xend: @annotation_position,
                        yend: @annotation_position,
                        alpha: @annotation_alpha,
                        color: @annotation_color,
                        linewidth: @annotation_linewidth,
                        linetype: @annotation_linetype,
                        arrow: @arrow_option
                      ] ++ @segment_line_style_options
  @rug_annotation [
                    x: @annotation_position,
                    y: @annotation_position,
                    alpha: @annotation_alpha,
                    color: @annotation_color,
                    linewidth: @annotation_linewidth,
                    linetype: @annotation_linetype
                  ] ++ @rug_drawing_options
  @linerange_annotation [
    x: @annotation_position,
    y: @annotation_position,
    xmin: @annotation_position,
    xmax: @annotation_position,
    ymin: @annotation_position,
    ymax: @annotation_position,
    orientation: @range_orientation_option,
    alpha: @annotation_alpha,
    color: @annotation_color,
    linewidth: @annotation_linewidth,
    linetype: @annotation_linetype,
    lineend: Keyword.fetch!(@line_style_options, :lineend)
  ]
  @pointrange_annotation @linerange_annotation ++
                           [
                             fill: @annotation_color,
                             shape: @annotation_shape,
                             size: @annotation_size,
                             stroke: @annotation_stroke
                           ]
  @errorbar_annotation Keyword.put(@linerange_annotation, :width, @annotation_width)
  @crossbar_annotation [
                         x: @annotation_position,
                         y: @annotation_position,
                         xmin: @annotation_position,
                         xmax: @annotation_position,
                         ymin: @annotation_position,
                         ymax: @annotation_position,
                         orientation: @range_orientation_option,
                         width: @annotation_width,
                         alpha: @annotation_alpha,
                         color: @annotation_color,
                         fill: @annotation_color,
                         linewidth: @annotation_linewidth,
                         linetype: @annotation_linetype
                       ] ++ @crossbar_line_look_options ++ @crossbar_line_style_options
  # A reference line layer's own table, which its mapping reads, as ggplot2's `data =` gives one;
  # it takes nothing from the plot's mapping, so it need hold only what its own mapping names.
  @reference_line_data_option [
    type: :any,
    doc:
      "A table for the layer's mapping to draw from instead of the plot's data, anything " <>
        "implementing `Table.Reader`; refused beside the options giving lines as values, which " <>
        "draw lines of their own. Under a facet, a table lacking a faceting column is drawn in " <>
        "every panel."
  ]

  # How every reference line looks, each set by an option: one value, or beside the intercept's
  # option a list, one per line, as ggplot2's `geom_hline(yintercept = 1:3, colour = ...)` takes
  # a vector.
  @reference_line_look_options [
    alpha:
      Keyword.put(
        @annotation_alpha,
        :doc,
        "How opaque each line is, from 0, invisible, to 1, opaque."
      ),
    color:
      Keyword.put(
        @annotation_color,
        :doc,
        "The colour of each line, written `colour:` or `color:`: " <>
          @color_forms <> "; black when not given."
      ),
    linewidth:
      Keyword.put(
        @annotation_linewidth,
        :doc,
        "How wide each line is, in millimetres; the theme's `base_line_size` when not " <>
          "given, 0.5 at its default sizes."
      ),
    linetype:
      Keyword.put(
        @annotation_linetype,
        :doc,
        "The line type of each line: " <> @linetype_forms <> "; `:solid` when not given."
      ),
    lineend: Keyword.fetch!(@line_style_options, :lineend)
  ]

  # `geom_hline/3`'s options, validated at the call.
  @hline_options NimbleOptions.new!(
                   [
                     data: @reference_line_data_option,
                     position: [
                       type: {:custom, __MODULE__, :validate_position, [@hline_positions]},
                       default: :identity,
                       doc:
                         "Where the lines are moved: left where they cross the axis " <>
                           "(`:identity`), or nudged (`:nudge`), as " <>
                           "[Positions](#module-positions) says."
                     ],
                     yintercept:
                       Keyword.put(
                         @annotation_position,
                         :doc,
                         "Where each line crosses the y axis, in its units: a value, or a " <>
                           "list of them, a line for each, drawn in every panel. Given, the " <>
                           "layer takes no mapping and no `data:`."
                       ),
                     nudge_y: @nudge_y_option
                   ] ++ @reference_line_look_options
                 )

  # `geom_vline/3`'s options, validated at the call.
  @vline_options NimbleOptions.new!(
                   [
                     data: @reference_line_data_option,
                     position: [
                       type: {:custom, __MODULE__, :validate_position, [@vline_positions]},
                       default: :identity,
                       doc:
                         "Where the lines are moved: left where they cross the axis " <>
                           "(`:identity`), or nudged (`:nudge`), as " <>
                           "[Positions](#module-positions) says."
                     ],
                     xintercept:
                       Keyword.put(
                         @annotation_position,
                         :doc,
                         "Where each line crosses the x axis, in its units: a value, or a " <>
                           "list of them, a line for each, drawn in every panel. Given, the " <>
                           "layer takes no mapping and no `data:`."
                       ),
                     nudge_x: @nudge_x_option
                   ] ++ @reference_line_look_options
                 )

  # A diagonal line's intercept or slope, given as a value: a number, or a list of them, one per
  # line.
  @abline_coefficient [
    type: {:custom, __MODULE__, :validate_per_annotation, [:validate_coefficient]}
  ]

  # `geom_abline/3`'s options, validated at the call.
  @abline_options NimbleOptions.new!(
                    [
                      data: @reference_line_data_option,
                      intercept:
                        Keyword.put(
                          @abline_coefficient,
                          :doc,
                          "Where each line crosses x = 0, in the y axis's positions, the units " <>
                            "its scale transforms into: a number, or a list of them, a line for " <>
                            "each, drawn in every panel; 0 when only `slope:` is given. Given, " <>
                            "the layer takes no mapping and no `data:`."
                        ),
                      slope:
                        Keyword.put(
                          @abline_coefficient,
                          :doc,
                          "How far each line rises along y for each unit along x, in the " <>
                            "axes' positions: a number, or a list of them, a line for each; 1 " <>
                            "when only `intercept:` is given. Given, the layer takes no mapping " <>
                            "and no `data:`."
                        )
                    ] ++ @reference_line_look_options
                  )

  @annotation_geoms [
    :point,
    :col,
    :bar,
    :path,
    :line,
    :segment,
    :rug,
    :linerange,
    :pointrange,
    :errorbar,
    :crossbar,
    :text,
    :label,
    :rect
  ]
  @annotation_options %{
    point: NimbleOptions.new!(@point_annotation),
    col: NimbleOptions.new!(@bar_annotation),
    bar: NimbleOptions.new!(@bar_annotation),
    path: NimbleOptions.new!(@path_annotation),
    line: NimbleOptions.new!([orientation: @orientation_option] ++ @path_annotation),
    segment: NimbleOptions.new!(@segment_annotation),
    rug: NimbleOptions.new!(@rug_annotation),
    linerange: NimbleOptions.new!(@linerange_annotation),
    pointrange: NimbleOptions.new!(@pointrange_annotation),
    errorbar: NimbleOptions.new!(@errorbar_annotation),
    crossbar: NimbleOptions.new!(@crossbar_annotation),
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
    label:
      NimbleOptions.new!(
        [
          x: @annotation_position,
          y: @annotation_position,
          label: @annotation_label,
          alpha: @annotation_alpha,
          color: @annotation_color,
          fill: @annotation_color,
          linewidth: @annotation_linewidth,
          linetype: @annotation_linetype
        ] ++ @text_style_options ++ @label_box_options
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

  # The transformations `transform:` takes, as its documentation and its refusal name them.
  @transform_names_doc "`:identity`, `:log`, `:log2`, `:log10`, `{:log, base}`, `:log1p`, " <>
                         "`:exp`, `{:exp, base}`, `:asinh`, `:pseudo_log`, " <>
                         "`{:pseudo_log, sigma: sigma, base: base}`, `:sqrt`, `:reverse`, " <>
                         "`:reciprocal`, `:asn`, `:atanh`, `:logit`, `:probit`, " <>
                         "`{:probability, :normal, mean: mean, sd: sd}`, " <>
                         "`{:probability, :logistic, location: location, scale: scale}`, " <>
                         "`{:boxcox, exponent}`, `{:boxcox, exponent, offset: offset}`, " <>
                         "`{:modulus, exponent}`, `{:modulus, exponent, offset: offset}`, " <>
                         "`{:yj, exponent}`, `:timespan`, `{:timespan, unit}`, a composition " <>
                         "`{:compose, [part, ...]}` or one `Scales.Transform.new/2` makes"

  # A continuous scale's `transform:`, ggplot2's `transform`, on an axis and on a scale of another
  # aesthetic alike, its default the scale's, the identity.
  @transform_spec [
    type: {:custom, __MODULE__, :validate_transform, []},
    doc:
      "What each value is put through before the scale sees it, a transformation of " <>
        "`Scales.Transform`'s: " <>
        @transform_names_doc <>
        "; `:identity` when not given. The scale trains, breaks and places in transformed " <>
        "space, its limits and breaks given in data units, and labels its breaks in data units."
  ]

  # Every scale function's `name:`.
  @scale_name_spec [
    type: {:custom, __MODULE__, :validate_label, []},
    doc: "The axis's title, or `:none` for none; the title its mapping gives when not given."
  ]

  # Every scale function's `expand:`, its default the scale's.
  @scale_expand_type {:custom, __MODULE__, :validate_expand, []}

  # A continuous or binned scale's `oob:`, R's `oob`: what happens to a value outside its limits,
  # run in transformed space, a position scale's at both of its maps. Its default is the scale's,
  # `:censor`, a binned one's `:squish`. The names' meanings are `Scales.Bounds`'s.
  @oob_type {:custom, __MODULE__, :validate_oob, []}
  @oob_names_doc "`:censor`, a finite number outside made missing; `:censor_any`, an infinity " <>
                   "too; `:squish`, a finite number moved onto the nearer limit; " <>
                   "`:squish_any`, an infinity too; `:squish_infinite`, an infinity alone moved " <>
                   "onto its limit; `:keep`, every value kept; or a function handed the values " <>
                   "and the limits, `{low, high}`, both transformed, that returns a value for " <>
                   "each, a number, an infinity, `nil` or `:nan`"

  @position_oob_spec [
    type: @oob_type,
    doc:
      "What happens to a value outside the limits: " <>
        @oob_names_doc <>
        ". Run on the " <>
        "positions as given and again once the stat and position have moved them, so a bar " <>
        "whose base the limits leave out is missing; a value kept outside is drawn past the " <>
        "panel's edge and cut off there. `:censor` when not given."
  ]

  @legend_oob_spec [
    type: @oob_type,
    doc:
      "What happens to a value outside the limits: " <>
        @oob_names_doc <>
        ". A value left " <>
        "outside, or left missing, takes `na_value:`, but an opacity or a size kept outside " <>
        "runs on past its range. `:censor` when not given."
  ]

  @binned_oob_spec [
    type: @oob_type,
    doc:
      "What happens to a value outside the limits before it is binned: " <>
        @oob_names_doc <>
        ". A value left outside, or left missing, takes `na_value:`. `:squish` when not given, " <>
        "so a value outside takes the colour of the bin at the nearer end."
  ]

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
          "missing, so its mark is not drawn, unless `oob:` says otherwise."
    ],
    oob: @position_oob_spec,
    breaks: [
      type: {:custom, __MODULE__, :validate_breaks, []},
      doc:
        "The values the axis marks with a tick, a label and a grid " <>
          "line, a list of numbers in data units; a function that " <>
          "returns them, or `{break, label}` pairs, handed the axis's " <>
          "extent in data units, `{low, high}`, and, taking two " <>
          "arguments, `[n: n]` as `n_breaks:` asks, `[]` when not " <>
          "given, such as `&Scales.Breaks.extended/2`; or `:none` for " <>
          "none; chosen from the limits when not given. A break is " <>
          "drawn wherever it falls inside the widened axis."
    ],
    minor_breaks: [
      type: {:custom, __MODULE__, :validate_breaks, []},
      doc:
        "The values the panel draws a minor grid line at, a list of " <>
          "numbers in data units; a function that returns them, " <>
          "handed the axis's extent in data units, `{low, high}`, and, " <>
          "taking two arguments, the breaks drawn; or `:none` for none; " <>
          "midway between the breaks, once transformed, when not given."
    ],
    n_breaks: [
      type: :pos_integer,
      doc:
        "How many breaks are wanted, of the breaks chosen when " <>
          "`breaks:` is not given, 2 or more but on a log axis, or of " <>
          "a `breaks:` function of two arguments; not beside " <>
          "`breaks:` a list, `:none` or a function of one argument, " <>
          "which wants no number."
    ],
    labels: [
      type: {:custom, __MODULE__, :validate_scale_labels, []},
      doc:
        "The breaks' labels: a list of strings, `nil` drawn `NA`, one for each of `breaks:`, or " <>
          "of the breaks its function returns; a function handed every break drawn, a list of " <>
          "numbers in data units, that returns a label for each, a string, a power or `nil`, as " <>
          "`Scales.Labels`'s do; or `:none` for ticks with no labels. A pair's label when a " <>
          "`breaks:` function returns pairs."
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
                            |> Enum.concat(transform: @transform_spec)
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
                                  "in the order given, those not among the limits left out; " <>
                                  "a function of one argument handed the limits that returns " <>
                                  "them, or `{value, label}` pairs; or `:none` for none; " <>
                                  "every one of the limits when not given."
                            ],
                            minor_breaks: [
                              type: {:custom, __MODULE__, :validate_breaks, []},
                              doc:
                                "The positions the panel draws a minor grid line at, the " <>
                                  "values placed at 1, 2, 3 and on: a list of numbers; a " <>
                                  "function that returns them, handed the axis's extent, " <>
                                  "`{low, high}`, and, taking two arguments, the breaks' " <>
                                  "positions; or `:none` for none; none when not given."
                            ],
                            labels: [
                              type: {:custom, __MODULE__, :validate_discrete_labels, []},
                              doc:
                                "The breaks' labels: a list of strings, `nil` drawn `NA`, one " <>
                                  "for each break, or for each limit when no breaks are given; a " <>
                                  "map from a value to its label, a value it does not hold " <>
                                  "keeping its own; a function handed every break drawn, a list " <>
                                  "of values, that returns a label for each, a string, a power or " <>
                                  "`nil`; or `:none` for ticks with no labels. A pair's label " <>
                                  "when a `breaks:` function returns pairs, else each value " <>
                                  "written as text, when not given."
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
                              "A value outside them is missing, so its mark is not drawn, " <>
                              "unless `oob:` says otherwise."
                        ],
                        oob: @position_oob_spec,
                        breaks: [
                          type: {:custom, __MODULE__, :validate_dates, []},
                          doc:
                            "The dates the axis marks with a tick, a label and a grid line, a " <>
                              "list; a function that returns them, or `{date, label}` pairs, " <>
                              "handed the axis's extent, `{low, high}`, its ends rounded out " <>
                              "to whole days, and, taking two arguments, `[]`, such as " <>
                              "`&Scales.Breaks.pretty/2`; or `:none` for none; chosen from the " <>
                              "limits when neither this nor `date_breaks:` is given. A break " <>
                              "is drawn wherever it falls inside the widened axis."
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
                            "The breaks' labels: a list of strings, `nil` drawn `NA`, one for " <>
                              "each of `breaks:`, or of the breaks its function returns; a " <>
                              "function handed every break drawn, a list of dates, that returns a " <>
                              "label for each, a string, a power or `nil`; or `:none` for ticks " <>
                              "with no labels. Not with `date_labels:`. When neither is given, " <>
                              "the breaks the axis chooses are written as suits their step (`Sep " <>
                              "21`, `2026`), a `breaks:` function's pairs by their labels, and " <>
                              "others in full (`2026-09-21`)."
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
                            "The dates the panel draws a minor grid line at, a list; a " <>
                              "function that returns them, handed the axis's extent as " <>
                              "`breaks:`'s is, and, taking two arguments, the breaks drawn; or " <>
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

  # The date-time scale functions' options; an option not given keeps a date-time scale's
  # default. A `date_` option and its plain twin choose the same thing, so only one may be given.
  @datetime_step_type {:custom, __MODULE__, :validate_datetime_step, []}
  @datetime_scale_options NimbleOptions.new!(
                            name: @scale_name_spec,
                            limits: [
                              type: {:custom, __MODULE__, :validate_datetime_limits, []},
                              doc:
                                "`{low, high}`: the date-times the axis spans whatever the " <>
                                  "data, `DateTime`s or `NaiveDateTime`s as its column holds, " <>
                                  "`nil` for an end the data decides; either order names the " <>
                                  "same axis. A value outside them is missing, so its mark is " <>
                                  "not drawn, unless `oob:` says otherwise."
                            ],
                            oob: @position_oob_spec,
                            breaks: [
                              type: {:custom, __MODULE__, :validate_datetimes, []},
                              doc:
                                "The date-times the axis marks with a tick, a label and a grid " <>
                                  "line, a list; a function that returns them, or " <>
                                  "`{date_time, label}` pairs, handed the axis's extent, " <>
                                  "`{low, high}`, as the column holds date-times, and, taking " <>
                                  "two arguments, `[]`, such as `&Scales.Breaks.pretty/2`; or " <>
                                  "`:none` for none; chosen from the limits when neither this " <>
                                  "nor `date_breaks:` is given. A break is drawn wherever it " <>
                                  "falls inside the widened axis."
                            ],
                            date_breaks: [
                              type: @datetime_step_type,
                              doc:
                                "A break every step, `[hour: 6]`: one of `:second`, `:minute`, " <>
                                  "`:hour`, `:day`, `:week`, `:month` and `:year` and how many " <>
                                  "of it, laid from the widened axis's start, rounded to the " <>
                                  "nearest multiple of the step since 1970-01-01 for seconds " <>
                                  "and minutes, else down to the start of its hour, its day, " <>
                                  "the Monday of its week, the 1st of its month or 1 January, " <>
                                  "to its end. Not with `breaks:`."
                            ],
                            labels: [
                              type: {:custom, __MODULE__, :validate_scale_labels, []},
                              doc:
                                "The breaks' labels: a list of strings, `nil` drawn `NA`, one " <>
                                  "for each of `breaks:`, or of the breaks its function returns; " <>
                                  "a function handed every break drawn, a list of date-times as " <>
                                  "the column holds them, that returns a label for each, a " <>
                                  "string, a power or `nil`; or `:none` for ticks with no labels. " <>
                                  "Not with `date_labels:`. When neither is given, the breaks the " <>
                                  "axis chooses are written as suits their step (`06:00`, `Mar 10 " <>
                                  "06:00`, `Mar 10`), a `breaks:` function's pairs by their " <>
                                  "labels, and others in full, the date alone where every one is " <>
                                  "a midnight (`2024-03-10`), else to the second (`2024-03-10 " <>
                                  "06:30:00`)."
                            ],
                            date_labels: [
                              type: {:custom, __MODULE__, :validate_datetime_format, []},
                              doc:
                                "The format every break's label is written in, as " <>
                                  "`Calendar.strftime/3` takes it, such as `\"%H:%M\"`. Not " <>
                                  "with `labels:`."
                            ],
                            minor_breaks: [
                              type: {:custom, __MODULE__, :validate_datetimes, []},
                              doc:
                                "The date-times the panel draws a minor grid line at, a list; " <>
                                  "a function that returns them, handed the axis's extent as " <>
                                  "`breaks:`'s is, and, taking two arguments, the breaks drawn; " <>
                                  "or `:none` for none; midway between the breaks when neither " <>
                                  "this nor `date_minor_breaks:` is given."
                            ],
                            date_minor_breaks: [
                              type: @datetime_step_type,
                              doc:
                                "A minor grid line every step, as `date_breaks:` lays breaks. " <>
                                  "Not with `minor_breaks:`."
                            ],
                            timezone: [
                              type: :string,
                              doc:
                                "The time zone the axis lays its breaks and writes its labels " <>
                                  "in, such as `\"America/New_York\"`, which " <>
                                  "`time_zone_database:` must know; the first date-time " <>
                                  "column's when not given. Naive date-times are in no time " <>
                                  "zone, so a column of them is refused beside it."
                            ],
                            time_zone_database: [
                              type: :atom,
                              doc:
                                "The time zone database that reads the axis's time zone, a " <>
                                  "module implementing `Calendar.TimeZoneDatabase`, such as " <>
                                  "the tz package's `Tz.TimeZoneDatabase`; " <>
                                  "`Calendar.UTCOnlyTimeZoneDatabase`, which knows UTC alone, " <>
                                  "when not given, never the one the application configures."
                            ],
                            expand: [
                              type: @scale_expand_type,
                              doc:
                                "How far the axis reaches beyond its limits, `[mult: m, add: " <>
                                  "a]`: at each end, that multiple of the limits' width plus " <>
                                  "that constant, in seconds, each a number or `{low, high}` " <>
                                  "for the two ends; `[mult: 0.05]` when not given."
                            ]
                          )

  # The time scale functions' options; an option not given keeps a time scale's default. A `date_`
  # option and its plain twin choose the same thing, so only one may be given.
  @time_step_type {:custom, __MODULE__, :validate_time_step, []}
  @time_scale_options NimbleOptions.new!(
                        name: @scale_name_spec,
                        limits: [
                          type: {:custom, __MODULE__, :validate_time_limits, []},
                          doc:
                            "`{low, high}`: the times of day the axis spans whatever the data, " <>
                              "`nil` for an end the data decides; either order names the same " <>
                              "axis. A value outside them is missing, so its mark is not " <>
                              "drawn, unless `oob:` says otherwise."
                        ],
                        oob: @position_oob_spec,
                        breaks: [
                          type: {:custom, __MODULE__, :validate_times, []},
                          doc:
                            "The times of day the axis marks with a tick, a label and a grid " <>
                              "line, a list; a function that returns them, or `{time, label}` " <>
                              "pairs, handed the axis's extent, `{low, high}`, as times of day " <>
                              "wrapped past midnight, and, taking two arguments, `[]`; or " <>
                              "`:none` for none; chosen from the limits when neither this nor " <>
                              "`date_breaks:` is given. A break is drawn wherever it falls " <>
                              "inside the widened axis."
                        ],
                        date_breaks: [
                          type: @time_step_type,
                          doc:
                            "A break every step, `[minute: 30]`: one of `:second`, `:minute` " <>
                              "and `:hour` and how many of it, laid from the widened axis's " <>
                              "start, rounded down to a multiple of the step since midnight, " <>
                              "to its end. Not with `breaks:`."
                        ],
                        labels: [
                          type: {:custom, __MODULE__, :validate_scale_labels, []},
                          doc:
                            "The breaks' labels: a list of strings, `nil` drawn `NA`, one for " <>
                              "each of `breaks:`, or of the breaks its function returns, a pair's " <>
                              "label when it returns pairs; a function handed every break drawn, " <>
                              "a list of times of day, wrapped past midnight, so a break at the " <>
                              "end of the day is `~T[00:00:00]`, that returns a label for each, a " <>
                              "string, a power or `nil`; or `:none` for ticks with no labels. Not " <>
                              "with `date_labels:`. When neither is given, each break is written " <>
                              "in hours, minutes and seconds, with as many decimals of a second " <>
                              "as the most precise needs, the hours counting on past midnight and " <>
                              "a break before it negative (`10:30:00`, `24:00:00`, `-00:00:30`)."
                        ],
                        date_labels: [
                          type: {:custom, __MODULE__, :validate_time_format, []},
                          doc:
                            "The format every break's label is written in, as " <>
                              "`Calendar.strftime/3` writes a time of day, such as " <>
                              "`\"%H:%M\"`, a break past midnight wrapped round it, so the end " <>
                              "of the day is written as its start. Not with `labels:`."
                        ],
                        minor_breaks: [
                          type: {:custom, __MODULE__, :validate_times, []},
                          doc:
                            "The times of day the panel draws a minor grid line at, a list; " <>
                              "a function that returns them, handed the axis's extent as " <>
                              "`breaks:`'s is, and, taking two arguments, the breaks drawn; or " <>
                              "`:none` for none; midway between the breaks when neither this " <>
                              "nor `date_minor_breaks:` is given."
                        ],
                        date_minor_breaks: [
                          type: @time_step_type,
                          doc:
                            "A minor grid line every step, as `date_breaks:` lays breaks. Not " <>
                              "with `minor_breaks:`."
                        ],
                        expand: [
                          type: @scale_expand_type,
                          doc:
                            "How far the axis reaches beyond its limits, `[mult: m, add: a]`: " <>
                              "at each end, that multiple of the limits' width plus that " <>
                              "constant, in seconds, each a number or `{low, high}` for the two " <>
                              "ends; `[mult: 0.05]` when not given."
                        ]
                      )

  # The transformation a date-time scale records when given no time zone or database, its zone
  # left for its first column to settle and read by the standard library's time zone database,
  # which knows UTC alone: the value `Giggly.Scale.new(:datetime)` records, which a test pins.
  @datetime_transform {:datetime, :default, Calendar.UTCOnlyTimeZoneDatabase}

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
          "the limits left out; a function of one argument handed the limits that returns " <>
          "them, or `{value, label}` pairs, a pair's label its key's; or `:none` for no legend; " <>
          "every one of the limits when not given."
    ],
    labels: [
      type: {:custom, __MODULE__, :validate_discrete_labels, []},
      doc:
        "The keys' labels: a list of strings, `nil` drawn `NA`, one for each break, or for each " <>
          "limit when no breaks are given; a map from a value to its label, a value it does not " <>
          "hold keeping its own; a function handed every break, a list of values, that returns a " <>
          "label for each, a string, a power or `nil`; or `:none` for keys with no labels. Each " <>
          "value written as text when not given."
    ]
  ]

  @continuous_legend_option_specs [
    name: @legend_name_spec,
    limits: [
      type: @limits_type,
      doc:
        "`{low, high}`: the values the scale spans whatever the data, `nil` for an end the " <>
          "data decides; either order names the same scale. A value outside them takes " <>
          "`na_value:`, unless `oob:` says otherwise where the scale takes it."
    ],
    breaks: [
      type: {:custom, __MODULE__, :validate_breaks, []},
      doc:
        "The values the legend or colour bar marks, a list of numbers, those outside the " <>
          "limits left out; a function that returns them, or `{break, label}` pairs, handed the " <>
          "limits, `{low, high}`, and, taking two arguments, `[n: n]` as `n_breaks:` asks, `[]` " <>
          "when not given; or `:none` for no guide; chosen from the limits when not given."
    ],
    n_breaks: [
      type: :pos_integer,
      doc:
        "How many breaks are wanted, 2 or more, of the breaks chosen when `breaks:` is not " <>
          "given, or of a `breaks:` function of two arguments; not beside `breaks:` a list, " <>
          "`:none` or a function of one argument, which wants no number."
    ],
    labels: [
      type: {:custom, __MODULE__, :validate_scale_labels, []},
      doc:
        "The breaks' labels: a list of strings, `nil` drawn `NA`, one for each of `breaks:`, or " <>
          "of the breaks its function returns; a function handed every break, a list of numbers, " <>
          "that returns a label for each, a string, a power or `nil`, as `Scales.Labels`'s do; or " <>
          "`:none` for no labels. A pair's label when a `breaks:` function returns pairs."
    ],
    transform: @transform_spec
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
      "What reads the scale back: `:colorbar`, a bar the colours run up; `:colorsteps`, a bar " <>
        "of one block of colour between each break and the next; `:legend`, a key for each " <>
        "break; " <> @guide_doc_tail
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
                                          oob: @legend_oob_spec,
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

  # How many colours of a brewer palette a distiller's gradient runs through, as ggplot2's
  # `scale_colour_distiller()` takes `pal_brewer()(7)`.
  @distiller_colors 7

  # ColorBrewer's palettes' names, every type's, as R spells them.
  @brewer_names Enum.flat_map([:seq, :div, :qual], &Palette.brewer_palettes/1)

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

  # A viridis palette's opacity, which the scales giving its colours one by one take.
  @viridis_alpha_spec [
    type: {:custom, __MODULE__, :validate_alpha, []},
    default: @viridis_defaults[:alpha],
    doc: "The colours' opacity, from 0 to 1."
  ]

  @discrete_viridis_scale_options NimbleOptions.new!(
                                    @viridis_option_specs ++
                                      [
                                        alpha: @viridis_alpha_spec,
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
                                      type: {:custom, __MODULE__, :validate_discrete_palette, []},
                                      doc:
                                        "A palette's name, one of scales' in any case " <>
                                          "(`Scales.Palette.named/1`), such as `\"Set1\"` or " <>
                                          "`\"viridis\"`, or a list of colours, its colours " <>
                                          "given to the values in order; hues spaced evenly " <>
                                          "round the colour wheel when not given."
                                    ],
                                    na_value: @color_na_value_spec
                                  ] ++ @discrete_color_legend_option_specs
                                )

  # A two-colour gradient's ends, which a gradient scale and a steps scale take.
  @gradient_end_specs [
    low: [
      type: @opaque_color_type,
      default: @gradient_defaults[:low],
      doc: "The colour at the low end of the limits."
    ],
    high: [
      type: @opaque_color_type,
      default: @gradient_defaults[:high],
      doc: "The colour at the high end of the limits."
    ]
  ]

  # A diverging gradient's colours and midpoint, which a gradient2 scale and a steps2 scale take.
  @diverging_gradient_specs [
    low: [
      type: @opaque_color_type,
      default: "#832424",
      doc: "The colour the low side runs to, a dark red when not given."
    ],
    mid: [
      type: @opaque_color_type,
      default: "#FFFFFF",
      doc: "The colour at the midpoint, white when not given."
    ],
    high: [
      type: @opaque_color_type,
      default: "#3A3A98",
      doc: "The colour the high side runs to, a dark blue when not given."
    ],
    midpoint: [
      type: {:custom, __MODULE__, :validate_number, []},
      default: 0.0,
      doc: "The value the middle colour stands at."
    ]
  ]

  @gradient_scale_options NimbleOptions.new!(
                            @gradient_end_specs ++
                              [na_value: @color_na_value_spec] ++
                              @continuous_color_legend_option_specs
                          )

  @gradient2_scale_options NimbleOptions.new!(
                             @diverging_gradient_specs ++
                               [na_value: @color_na_value_spec] ++
                               @continuous_color_legend_option_specs
                           )

  # A gradient's `values:`, which move a value's place in the limits before its colour is taken.
  @gradient_values_spec [
    type: {:custom, __MODULE__, :validate_gradient_values, []},
    doc:
      "Where the colours sit: places from 0, the low end of the limits, to 1, the high, one " <>
        "for each colour, so each colour sits at its place and those between are blended; of " <>
        "another count, the colours are spread over them evenly. A value beyond the first or " <>
        "last place takes `na_value:`. The colours are spaced evenly when not given."
  ]

  # A gradient's colours, placed by `values:`, which a gradientn scale and a stepsn scale take.
  @gradient_colors_specs [
    colors: [
      type: {:custom, __MODULE__, :validate_gradient_colors, []},
      required: true,
      doc:
        "The colours, a list, spaced evenly from the low end of the limits to the high unless " <>
          "`values:` places them."
    ],
    values: @gradient_values_spec
  ]

  @gradientn_scale_options NimbleOptions.new!(
                             @gradient_colors_specs ++
                               [na_value: @color_na_value_spec] ++
                               @continuous_color_legend_option_specs
                           )

  @continuous_color_scale_options NimbleOptions.new!(
                                    [
                                      palette: [
                                        type:
                                          {:custom, __MODULE__, :validate_continuous_palette, []},
                                        doc:
                                          "A palette's name, one of scales' in any case " <>
                                            "(`Scales.Palette.named/1`), such as `\"Blues\"` " <>
                                            "or `\"viridis\"`, its colours blended in order, or " <>
                                            "a list of colours, spaced evenly from the low end " <>
                                            "of the limits to the high; a gradient from " <>
                                            "`#132B43` to `#56B1F7` when not given."
                                      ],
                                      na_value: @color_na_value_spec
                                    ] ++ @continuous_color_legend_option_specs
                                  )

  # The options every brewer scale takes, R's `pal_brewer()`'s: the palette, by name or by its
  # number among its type's.
  @brewer_option_specs [
    type: [
      type: {:in, [:seq, :div, :qual]},
      default: :seq,
      doc:
        "The palettes a number in `palette:` counts among: `:seq`, sequential; `:div`, " <>
          "diverging; or `:qual`, qualitative. A name is not counted, so this is not read " <>
          "beside one."
    ],
    palette: [
      type: {:custom, __MODULE__, :validate_brewer_palette, []},
      default: 1,
      doc:
        "The ColorBrewer palette: its name, spelled as `Scales.Palette.brewer_palettes/1` " <>
          "spells it, or its number among the palettes of `type:`, counting from 1."
    ]
  ]

  @brewer_scale_options NimbleOptions.new!(
                          @brewer_option_specs ++
                            [
                              direction: [
                                type: {:in, [1, -1]},
                                default: 1,
                                doc:
                                  "1 to give the palette's colours to the values in order, -1 " <>
                                    "in reverse."
                              ],
                              na_value: Keyword.put(@color_na_value_spec, :default, :none)
                            ] ++ @discrete_color_legend_option_specs
                        )

  @distiller_scale_options NimbleOptions.new!(
                             @brewer_option_specs ++
                               [
                                 direction: [
                                   type: {:in, [1, -1]},
                                   default: -1,
                                   doc:
                                     "-1 to blend the palette's colours from its last at the " <>
                                       "low end of the limits to its first at the high, 1 the " <>
                                       "other way."
                                 ],
                                 values: @gradient_values_spec,
                                 na_value: @color_na_value_spec
                               ] ++ @continuous_color_legend_option_specs
                           )

  # A binned scale's `guide:`, colour steps unless given.
  @binned_guide_spec [
    type: {:custom, __MODULE__, :validate_guide, [:binned]},
    default: :colorsteps,
    doc:
      "What reads the scale back: `:colorsteps`, a bar of one block of colour for each bin; " <>
        "`:legend`, a key for each break; " <> @guide_doc_tail
  ]

  # The options of every binned colour or fill scale function, ggplot2's `binned_scale()`'s that a
  # colour scale reads; an option not given keeps `Giggly.Scale.Binned`'s default, which those
  # with one record as a value.
  @binned_legend_option_specs [
    name: @legend_name_spec,
    limits: [
      type: @limits_type,
      doc:
        "`{low, high}`: the values the bins span whatever the data, `nil` for an end the data " <>
          "decides; either order names the same scale. A value outside them takes the colour of " <>
          "the bin at the nearer end, unless `oob:` says otherwise. The data's range, widened so " <>
          "the end bins are as wide as their neighbours, when neither this nor `breaks:` is given."
    ],
    oob: @binned_oob_spec,
    breaks: [
      type: {:custom, __MODULE__, :validate_breaks, []},
      doc:
        "The values the bins are cut at, a list of numbers, those outside the limits left out; " <>
          "a function that returns them, or `{break, label}` pairs, handed the limits, `{low, " <>
          "high}`, and, taking two arguments, `[n: n_breaks]`; or `:none` for one bin and no " <>
          "guide; chosen from the limits as `n_breaks:` and `nice_breaks:` say when not given."
    ],
    labels: [
      type: {:custom, __MODULE__, :validate_scale_labels, []},
      doc:
        "The breaks' labels: a list of strings, `nil` drawn `NA`, one for each of `breaks:`, or " <>
          "of the breaks its function returns; a function handed every break, a list of numbers, " <>
          "that returns a label for each, a string, a power or `nil`, as `Scales.Labels`'s do, " <>
          "and handed the limits too where `show_limits:` shows them; or `:none` for no labels. A " <>
          "pair's label when a `breaks:` function returns pairs."
    ],
    n_breaks: [
      type: :pos_integer,
      default: 5,
      doc:
        "How many breaks are wanted when `breaks:` is not given: 2 or more for nice breaks, " <>
          "which may number a few more or fewer, 1 or more otherwise; or of a `breaks:` function " <>
          "of two arguments. When given, not beside `breaks:` a list, `:none` or a function of " <>
          "one argument, which wants no number."
    ],
    nice_breaks: [
      type: :boolean,
      default: true,
      doc:
        "Whether breaks not given are round numbers, chosen as a continuous scale's are, or " <>
          "`n_breaks:` spaced evenly between the ends of the limits."
    ],
    right: [
      type: :boolean,
      default: true,
      doc: "Where a value on a break falls: `true` in the bin below it, `false` in the bin above."
    ],
    show_limits: [
      type: :boolean,
      default: false,
      doc:
        "Whether colour steps label the ends of the bar with the limits, unless a break is " <>
          "already there; not beside a list of `labels:`, which labels the breaks alone."
    ],
    guide: @binned_guide_spec
  ]

  @binned_scale_options NimbleOptions.new!(
                          [
                            palette: [
                              type: {:custom, __MODULE__, :validate_discrete_palette, []},
                              doc:
                                "A palette's name, one of scales' in any case " <>
                                  "(`Scales.Palette.named/1`), such as `\"Blues\"` or " <>
                                  "`\"viridis\"`, its colours for as many bins as there are " <>
                                  "given to them in order, or a list of colours, given to the " <>
                                  "bins in order, at least one for each; a gradient from " <>
                                  "`#132B43` to `#56B1F7`, each bin the colour at its middle, " <>
                                  "when not given."
                            ],
                            na_value: @color_na_value_spec
                          ] ++ @binned_legend_option_specs
                        )

  @steps_scale_options NimbleOptions.new!(
                         @gradient_end_specs ++
                           [na_value: @color_na_value_spec] ++ @binned_legend_option_specs
                       )

  @steps2_scale_options NimbleOptions.new!(
                          @diverging_gradient_specs ++
                            [na_value: @color_na_value_spec] ++ @binned_legend_option_specs
                        )

  @stepsn_scale_options NimbleOptions.new!(
                          @gradient_colors_specs ++
                            [na_value: @color_na_value_spec] ++ @binned_legend_option_specs
                        )

  @binned_viridis_scale_options NimbleOptions.new!(
                                  @viridis_option_specs ++
                                    [alpha: @viridis_alpha_spec, na_value: @color_na_value_spec] ++
                                    @binned_legend_option_specs
                                )

  @fermenter_scale_options NimbleOptions.new!(
                             @brewer_option_specs ++
                               [
                                 direction: [
                                   type: {:in, [1, -1]},
                                   default: -1,
                                   doc:
                                     "-1 to give the palette's colours to the bins from its last " <>
                                       "at the lowest to its first at the highest, 1 the other way."
                                 ],
                                 na_value: @color_na_value_spec
                               ] ++ @binned_legend_option_specs
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
                                        oob: @legend_oob_spec,
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
                                 oob: @legend_oob_spec,
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
  # `validate_guide/2`; a colour bar or colour steps for a colour or fill scale that turns out
  # discrete, or a colour bar for a binned one, is refused when the plot is run, since which kind of
  # scale it gets may be known only then.
  @guides_options NimbleOptions.new!(
                    color: [
                      type: {:custom, __MODULE__, :validate_guide, [:continuous]},
                      doc:
                        "The colour scale's guide (`colour:` too), as `scale_color_continuous/2`'s " <>
                          "`guide:` takes it; a colour bar for a continuous scale alone, colour " <>
                          "steps for a binned or continuous one."
                    ],
                    fill: [
                      type: {:custom, __MODULE__, :validate_guide, [:continuous]},
                      doc:
                        "The fill scale's guide, as `scale_fill_continuous/2`'s `guide:` takes " <>
                          "it; a colour bar for a continuous scale alone, colour steps for a " <>
                          "binned or continuous one."
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
                      "The colour scale's limits (`colour:` too): `{low, high}` for a " <>
                        "continuous scale, as `scale_color_continuous/2` takes them, two " <>
                        "numbers high to low running it from high to low, as `transform: " <>
                        ":reverse` runs it, or a list of values for a discrete one, as " <>
                        "`scale_color_discrete/2` does."
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
  @theme_justification_names [:center, :left, :right, :top, :bottom]
  @theme_no_margin Map.new(@theme_sides, fn side -> {side, {0, :pt}} end)

  # `theme/2`'s options: one for each element of the theme a setting may give, from the theme's
  # tree (`Giggly.ElementTree.elements/0`), each checked as its kind is: a line's, a rectangle's or
  # a text's properties, a length, or a margin.
  @theme_color [
    type: {:custom, __MODULE__, :validate_theme_color, []},
    doc: "Its colour, a CSS colour, which may have an alpha of its own (`colour:` too)."
  ]
  @theme_linewidth [
    type: {:custom, __MODULE__, :validate_theme_linewidth, []},
    doc: "How wide it is, in millimetres, or `{:rel, share}`, a share of its parent's."
  ]
  @theme_linetype [
    type: @linetype_type,
    doc: "Its line type: " <> @linetype_forms <> "."
  ]
  @theme_element_types %{
    line: [
      type: :keyword_list,
      keys: [
        color: @theme_color,
        linewidth: @theme_linewidth,
        linetype: @theme_linetype,
        lineend: [
          type: {:in, [:butt, :round, :square]},
          doc:
            "How its ends are drawn: cut square at the end (`:butt`), rounded (`:round`), or " <>
              "cut square half its width beyond it (`:square`)."
        ]
      ]
    ],
    rect: [
      type: :keyword_list,
      keys: [
        fill: [
          type: {:custom, __MODULE__, :validate_theme_rect_color, []},
          doc: "Its fill, a CSS colour, which may have an alpha of its own, or `:none` for none."
        ],
        color: [
          type: {:custom, __MODULE__, :validate_theme_rect_color, []},
          doc:
            "Its border's colour, a CSS colour, which may have an alpha of its own, or `:none` " <>
              "for no border (`colour:` too)."
        ],
        linewidth: @theme_linewidth,
        linetype: @theme_linetype
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
        family: [
          type: :string,
          doc:
            ~s(The font it is drawn in, by name, such as `"Lobster"`, or one of the generic ) <>
              ~s(families `"sans"`, `"serif"` and `"mono"`; `""` is the default sans-serif. ) <>
              "How it is measured and drawn: the [fonts guide](fonts.md)."
        ],
        face: [
          type: {:in, [:plain, :bold, :italic, :bold_italic]},
          doc: "Its face: `:plain`, `:bold`, `:italic` or `:bold_italic`."
        ],
        angle: [
          type: {:custom, __MODULE__, :validate_angle, []},
          doc: "How far it is turned, in degrees anticlockwise, any number."
        ],
        hjust: [
          type: {:custom, __MODULE__, :validate_text_justification, []},
          doc:
            "Where it sits across, any number: 0 at its left, 0.5 centred, 1 at its right, in " <>
              "its own turned frame."
        ],
        vjust: [
          type: {:custom, __MODULE__, :validate_text_justification, []},
          doc:
            "Where it sits up, any number: 0 at its bottom, 0.5 centred, 1 at its top, in its " <>
              "own turned frame."
        ],
        lineheight: [
          type: {:custom, __MODULE__, :validate_lineheight, []},
          doc:
            "How far apart its lines are, 0 or more, a share of 1.2 times its size: a text's " <>
              "lines are 0.9 apart unless given."
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
    position: [type: {:in, [:right, :left, :top, :bottom, :inside, :none]}],
    point: [type: {:custom, __MODULE__, :validate_theme_point, []}],
    justification: [type: {:custom, __MODULE__, :validate_theme_justification, [:shares]}],
    box_justification: [type: {:custom, __MODULE__, :validate_theme_justification, [:names]}],
    direction: [type: {:in, [:horizontal, :vertical]}],
    location: [type: {:in, [:panel, :plot]}],
    boolean: [type: :boolean]
  }
  # The elements whose settings are a line's, a rectangle's or a text's properties, whose spelling
  # `theme/2` canonicalizes (`colour:`) before checking them.
  @theme_drawn_kinds for {name, kind, _parent, _description} <- ElementTree.elements(),
                         kind in [:line, :rect, :text],
                         into: %{},
                         do: {name, kind}
  # A root length or margin is checked as one with no parent to take a share of.
  @theme_root_types %{
    length: [type: {:custom, __MODULE__, :validate_theme_length, [:root]}],
    margin: [type: {:custom, __MODULE__, :validate_theme_margin, [:root]}]
  }
  @theme_options NimbleOptions.new!(
                   for {name, kind, parent, description} <- ElementTree.elements() do
                     inherits =
                       if parent == :none, do: "", else: " Inherits from `#{inspect(parent)}`."

                     type =
                       if parent == :none and is_map_key(@theme_root_types, kind),
                         do: Map.fetch!(@theme_root_types, kind),
                         else: Map.fetch!(@theme_element_types, kind)

                     {name, [doc: description <> inherits] ++ type}
                   end
                 )

  # The options of the functions choosing a complete theme: its base sizes and families, each one
  # the theme works out its own default for where it is not given.
  @complete_theme_options NimbleOptions.new!(
                            base_size: [
                              type: {:custom, __MODULE__, :validate_base_size, []},
                              doc:
                                "How big its text is, in points, 0 or more: every text's size " <>
                                  "is a share of it, and the space between parts of the plot " <>
                                  "half of it. 11 unless given."
                            ],
                            base_line_size: [
                              type: {:custom, __MODULE__, :validate_linewidth, []},
                              doc:
                                "How wide its lines are, in millimetres, 0 or more. " <>
                                  "`base_size / 22` unless given."
                            ],
                            base_rect_size: [
                              type: {:custom, __MODULE__, :validate_linewidth, []},
                              doc:
                                "How wide its rectangles' borders are, in millimetres, 0 or " <>
                                  "more. `base_size / 22` unless given."
                            ],
                            base_family: [
                              type: :string,
                              doc:
                                "The font its text and its layers' text are drawn in, by " <>
                                  "name, as `theme/2`'s `family:` takes one. `\"\"`, the " <>
                                  "default sans-serif, unless given."
                            ],
                            header_family: [
                              type: :string,
                              doc:
                                "The font its titles are drawn in, by name: the axes' and " <>
                                  "the legends' titles and the plot's title. The base " <>
                                  "family unless given."
                            ]
                          )

  # A theme justification's point across or up: its name, or, where it `takes` `:shares`, a
  # number.
  defguardp is_justification_across(across, takes)
            when across in [:left, :center, :right] or (takes == :shares and is_number(across))

  defguardp is_justification_up(up, takes)
            when up in [:bottom, :center, :top] or (takes == :shares and is_number(up))

  # An end of a date scale's limits: a date, or `nil` for one the data decides.
  defguardp is_date_limit(limit) when is_struct(limit, Date) or is_nil(limit)

  defguardp is_time_limit(limit) when is_struct(limit, Time) or is_nil(limit)

  # A date-time, naive or not.
  defguardp is_datetime(value) when is_struct(value, DateTime) or is_struct(value, NaiveDateTime)

  # A continuous or binned scale's breaks or minor breaks function, ggplot2's: of one argument, the
  # limits, or of two, the limits and the breaks wanted or the breaks, as R counts them.
  defguardp is_breaks_function(term) when is_function(term, 1) or is_function(term, 2)

  # Each `Giggly.Plot` function's schema, named after the function, or after the family of scale
  # functions whose options are checked against it.
  @doc false
  @spec facet_wrap() :: NimbleOptions.t()
  def facet_wrap, do: @facet_wrap_options

  @doc false
  @spec facet_grid() :: NimbleOptions.t()
  def facet_grid, do: @facet_grid_options

  @doc false
  @spec coord_cartesian() :: NimbleOptions.t()
  def coord_cartesian, do: @coord_cartesian_options

  @doc false
  @spec point() :: NimbleOptions.t()
  def point, do: @point_options

  @doc false
  @spec jitter() :: NimbleOptions.t()
  def jitter, do: @jitter_options

  @doc false
  @spec sum() :: NimbleOptions.t()
  def sum, do: @sum_options

  @doc false
  @spec bar() :: NimbleOptions.t()
  def bar, do: @bar_options

  @doc false
  @spec count() :: NimbleOptions.t()
  def count, do: @count_options

  @doc false
  @spec bin() :: NimbleOptions.t()
  def bin, do: @bin_options

  @doc false
  @spec hex() :: NimbleOptions.t()
  def hex, do: @hex_options

  @doc false
  @spec ribbon() :: NimbleOptions.t()
  def ribbon, do: @ribbon_options

  @doc false
  @spec area() :: NimbleOptions.t()
  def area, do: @area_options

  @doc false
  @spec path() :: NimbleOptions.t()
  def path, do: @path_options

  @doc false
  @spec smooth() :: NimbleOptions.t()
  def smooth, do: @smooth_options

  @doc false
  @spec density() :: NimbleOptions.t()
  def density, do: @density_options

  @doc false
  @spec stat_density() :: NimbleOptions.t()
  def stat_density, do: @stat_density_options

  @doc false
  @spec violin() :: NimbleOptions.t()
  def violin, do: @violin_options

  @doc false
  @spec line() :: NimbleOptions.t()
  def line, do: @line_options

  @doc false
  @spec segment() :: NimbleOptions.t()
  def segment, do: @segment_options

  @doc false
  @spec rug() :: NimbleOptions.t()
  def rug, do: @rug_options

  @doc false
  @spec linerange() :: NimbleOptions.t()
  def linerange, do: @linerange_options

  @doc false
  @spec pointrange() :: NimbleOptions.t()
  def pointrange, do: @pointrange_options

  @doc false
  @spec errorbar() :: NimbleOptions.t()
  def errorbar, do: @errorbar_options

  @doc false
  @spec crossbar() :: NimbleOptions.t()
  def crossbar, do: @crossbar_options

  @doc false
  @spec abline() :: NimbleOptions.t()
  def abline, do: @abline_options

  @doc false
  @spec hline() :: NimbleOptions.t()
  def hline, do: @hline_options

  @doc false
  @spec vline() :: NimbleOptions.t()
  def vline, do: @vline_options

  @doc false
  @spec freqpoly() :: NimbleOptions.t()
  def freqpoly, do: @freqpoly_options

  @doc false
  @spec boxplot() :: NimbleOptions.t()
  def boxplot, do: @boxplot_options

  @doc false
  @spec text() :: NimbleOptions.t()
  def text, do: @text_options

  @doc false
  @spec label() :: NimbleOptions.t()
  def label, do: @label_options

  @doc false
  @spec rect() :: NimbleOptions.t()
  def rect, do: @rect_options

  @doc false
  @spec tile() :: NimbleOptions.t()
  def tile, do: @tile_options

  @doc false
  @spec raster() :: NimbleOptions.t()
  def raster, do: @raster_options

  @doc false
  @spec continuous_scale() :: NimbleOptions.t()
  def continuous_scale, do: @continuous_scale_options

  @doc false
  @spec transformed_scale() :: NimbleOptions.t()
  def transformed_scale, do: @transformed_scale_options

  @doc false
  @spec discrete_scale() :: NimbleOptions.t()
  def discrete_scale, do: @discrete_scale_options

  @doc false
  @spec date_scale() :: NimbleOptions.t()
  def date_scale, do: @date_scale_options

  @doc false
  @spec datetime_scale() :: NimbleOptions.t()
  def datetime_scale, do: @datetime_scale_options

  @doc false
  @spec time_scale() :: NimbleOptions.t()
  def time_scale, do: @time_scale_options

  @doc false
  @spec manual_scale() :: NimbleOptions.t()
  def manual_scale, do: @manual_scale_options

  @doc false
  @spec hue_scale() :: NimbleOptions.t()
  def hue_scale, do: @hue_scale_options

  @doc false
  @spec gray_scale() :: NimbleOptions.t()
  def gray_scale, do: @gray_scale_options

  @doc false
  @spec discrete_viridis_scale() :: NimbleOptions.t()
  def discrete_viridis_scale, do: @discrete_viridis_scale_options

  @doc false
  @spec continuous_viridis_scale() :: NimbleOptions.t()
  def continuous_viridis_scale, do: @continuous_viridis_scale_options

  @doc false
  @spec discrete_color_scale() :: NimbleOptions.t()
  def discrete_color_scale, do: @discrete_color_scale_options

  @doc false
  @spec gradient_scale() :: NimbleOptions.t()
  def gradient_scale, do: @gradient_scale_options

  @doc false
  @spec gradient2_scale() :: NimbleOptions.t()
  def gradient2_scale, do: @gradient2_scale_options

  @doc false
  @spec gradientn_scale() :: NimbleOptions.t()
  def gradientn_scale, do: @gradientn_scale_options

  @doc false
  @spec continuous_color_scale() :: NimbleOptions.t()
  def continuous_color_scale, do: @continuous_color_scale_options

  @doc false
  @spec brewer_scale() :: NimbleOptions.t()
  def brewer_scale, do: @brewer_scale_options

  @doc false
  @spec distiller_scale() :: NimbleOptions.t()
  def distiller_scale, do: @distiller_scale_options

  @doc false
  @spec binned_scale() :: NimbleOptions.t()
  def binned_scale, do: @binned_scale_options

  @doc false
  @spec steps_scale() :: NimbleOptions.t()
  def steps_scale, do: @steps_scale_options

  @doc false
  @spec steps2_scale() :: NimbleOptions.t()
  def steps2_scale, do: @steps2_scale_options

  @doc false
  @spec stepsn_scale() :: NimbleOptions.t()
  def stepsn_scale, do: @stepsn_scale_options

  @doc false
  @spec binned_viridis_scale() :: NimbleOptions.t()
  def binned_viridis_scale, do: @binned_viridis_scale_options

  @doc false
  @spec fermenter_scale() :: NimbleOptions.t()
  def fermenter_scale, do: @fermenter_scale_options

  @doc false
  @spec continuous_alpha_scale() :: NimbleOptions.t()
  def continuous_alpha_scale, do: @continuous_alpha_scale_options

  @doc false
  @spec discrete_alpha_scale() :: NimbleOptions.t()
  def discrete_alpha_scale, do: @discrete_alpha_scale_options

  @doc false
  @spec continuous_size_scale() :: NimbleOptions.t()
  def continuous_size_scale, do: @continuous_size_scale_options

  @doc false
  @spec radius_scale() :: NimbleOptions.t()
  def radius_scale, do: @radius_scale_options

  @doc false
  @spec area_size_scale() :: NimbleOptions.t()
  def area_size_scale, do: @area_size_scale_options

  @doc false
  @spec discrete_size_scale() :: NimbleOptions.t()
  def discrete_size_scale, do: @discrete_size_scale_options

  @doc false
  @spec discrete_shape_scale() :: NimbleOptions.t()
  def discrete_shape_scale, do: @discrete_shape_scale_options

  @doc false
  @spec manual_shape_scale() :: NimbleOptions.t()
  def manual_shape_scale, do: @manual_shape_scale_options

  @doc false
  @spec discrete_linetype_scale() :: NimbleOptions.t()
  def discrete_linetype_scale, do: @discrete_linetype_scale_options

  @doc false
  @spec manual_linetype_scale() :: NimbleOptions.t()
  def manual_linetype_scale, do: @manual_linetype_scale_options

  @doc false
  @spec continuous_linewidth_scale() :: NimbleOptions.t()
  def continuous_linewidth_scale, do: @continuous_linewidth_scale_options

  @doc false
  @spec discrete_linewidth_scale() :: NimbleOptions.t()
  def discrete_linewidth_scale, do: @discrete_linewidth_scale_options

  # The schema of the options of the position named `kind`.
  @doc false
  @spec position_kind(atom()) :: NimbleOptions.t()
  def position_kind(kind), do: Map.fetch!(@position_kind_schemas, kind)

  @doc false
  @spec guide_legend() :: NimbleOptions.t()
  def guide_legend, do: @guide_legend_options

  @doc false
  @spec guides() :: NimbleOptions.t()
  def guides, do: @guides_options

  @doc false
  @spec lims() :: NimbleOptions.t()
  def lims, do: @lims_options

  @doc false
  @spec labs() :: NimbleOptions.t()
  def labs, do: @labs_options

  @doc false
  @spec theme() :: NimbleOptions.t()
  def theme, do: @theme_options

  @doc false
  @spec complete_theme() :: NimbleOptions.t()
  def complete_theme, do: @complete_theme_options

  # The schema of `annotate/3`'s options for an annotation drawn with `geom`.
  @doc false
  @spec annotation(atom()) :: NimbleOptions.t()
  def annotation(geom), do: Map.fetch!(@annotation_options, geom)

  # The options that set an aesthetic for every mark rather than choose how a layer is drawn.
  @doc false
  @spec fixed_aesthetics() :: [atom()]
  def fixed_aesthetics, do: @fixed_aesthetics

  # Each option giving a part of a box its look, by the part and the look it gives.
  @doc false
  @spec boxplot_part_looks() :: keyword({atom(), atom()})
  def boxplot_part_looks, do: @boxplot_part_looks

  # Each option giving a violin's quantile lines a look, by the look it gives.
  @doc false
  @spec violin_quantile_looks() :: keyword(atom())
  def violin_quantile_looks, do: @violin_quantile_looks

  # Each option giving a part of a crossbar its look, by the part and the look it gives.
  @doc false
  @spec crossbar_part_looks() :: keyword({atom(), atom()})
  def crossbar_part_looks, do: @crossbar_part_looks

  # The aesthetics an annotation draws row by row, which take a list of values.
  @doc false
  @spec per_annotation_aesthetics() :: [atom()]
  def per_annotation_aesthetics, do: @per_annotation_aesthetics

  # The geoms `annotate/3` draws with, by name.
  @doc false
  @spec annotation_geoms() :: [atom()]
  def annotation_geoms, do: @annotation_geoms

  # `stat_summary/3`'s options drawing with `geom`, one of `summary_geoms/0`.
  @doc false
  @spec summary(atom()) :: NimbleOptions.t()
  def summary(geom), do: Map.fetch!(@summary_options, geom)

  # The options `stat_summary/3` takes whatever its geom, for its documentation.
  @doc false
  @spec summary_stat() :: NimbleOptions.t()
  def summary_stat, do: NimbleOptions.new!(@summary_stat_options)

  # The geoms `stat_summary/3` draws with.
  @doc false
  @spec summary_geoms() :: [atom()]
  def summary_geoms, do: @summary_geoms

  # A date, date-time or time scale's options that choose what their plain twins choose.
  @doc false
  @spec date_twins() :: keyword(atom())
  def date_twins, do: @date_twins

  # The transformation a date-time scale records until its first column settles its zone.
  @doc false
  @spec datetime_transform() :: {:datetime, :default, module()}
  def datetime_transform, do: @datetime_transform

  # The hue palette's defaults, which a discrete colour scale takes when given no palette.
  @doc false
  @spec hue_defaults() :: keyword()
  def hue_defaults, do: @hue_defaults

  # The default gradient's ends, which a continuous colour scale takes when given no palette.
  @doc false
  @spec gradient_defaults() :: keyword(String.t())
  def gradient_defaults, do: @gradient_defaults

  # The viridis palettes' defaults, which an ordered factor's colour and fill scales take.
  @doc false
  @spec viridis_defaults() :: keyword()
  def viridis_defaults, do: @viridis_defaults

  # How many colours of a viridis palette a continuous scale's gradient runs through.
  @doc false
  @spec viridis_gradient_colors() :: pos_integer()
  def viridis_gradient_colors, do: @viridis_gradient_colors

  # How many colours of a brewer palette a distiller's gradient runs through.
  @doc false
  @spec distiller_colors() :: pos_integer()
  def distiller_colors, do: @distiller_colors

  # The theme's elements whose settings are a line's, a rectangle's or a text's properties, by kind.
  @doc false
  @spec theme_drawn_kinds() :: %{atom() => ElementTree.kind()}
  def theme_drawn_kinds, do: @theme_drawn_kinds

  # NimbleOptions' check of an `alpha:` option: a number from 0, invisible, to 1, opaque, kept as a
  # float.
  @doc false
  @spec validate_alpha(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_alpha(alpha) when is_number(alpha) and alpha >= 0 and alpha <= 1,
    do: {:ok, alpha / 1}

  def validate_alpha(alpha),
    do: {:error, "expected a number from 0 to 1, got: #{inspect(alpha)}"}

  # NimbleOptions' check of a smooth's confidence level: a number above 0 and below 1, so a float,
  # where R also takes 1, an infinite band, and past it, none.
  @doc false
  @spec validate_level(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_level(level) when is_float(level) and level > 0 and level < 1, do: {:ok, level}

  def validate_level(level),
    do: {:error, "expected a number above 0 and below 1, got: #{inspect(level)}"}

  # NimbleOptions' check of a smooth's `span:`: a number above 0, kept as a float.
  @doc false
  @spec validate_span(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_span(span) when is_number(span) and span > 0, do: {:ok, span / 1}

  def validate_span(span),
    do: {:error, "expected a span, a number above 0, got: #{inspect(span)}"}

  # NimbleOptions' check of a density's `bw:`: one of the rules by name, or a finite number above 0,
  # kept as a float, as R keeps a double.
  @doc false
  @spec validate_bandwidth(term()) :: {:ok, :nrd0 | :nrd | float()} | {:error, String.t()}
  def validate_bandwidth(rule) when rule in [:nrd0, :nrd], do: {:ok, rule}
  def validate_bandwidth(width) when is_number(width) and width > 0, do: {:ok, width / 1}

  def validate_bandwidth(width),
    do: {:error, "expected a bandwidth, :nrd0, :nrd or a number above 0, got: #{inspect(width)}"}

  # NimbleOptions' check of a density's `adjust:`: a number above 0, kept as a float.
  @doc false
  @spec validate_adjust(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_adjust(adjust) when is_number(adjust) and adjust > 0, do: {:ok, adjust / 1}

  def validate_adjust(adjust),
    do:
      {:error, "expected a multiple of the bandwidth, a number above 0, got: #{inspect(adjust)}"}

  # NimbleOptions' check of a violin's `quantiles:`: `:none`, or a list of probabilities from 0 to
  # 1, each kept as a float, as R refuses one outside them.
  @doc false
  @spec validate_quantiles(term()) :: {:ok, :none | [float()]} | {:error, String.t()}
  def validate_quantiles(:none), do: {:ok, :none}

  def validate_quantiles(quantiles) when is_list(quantiles) do
    if Enum.all?(quantiles, fn quantile ->
         is_number(quantile) and quantile >= 0 and quantile <= 1
       end),
       do: {:ok, Enum.map(quantiles, fn quantile -> quantile / 1 end)},
       else: quantiles_error(quantiles)
  end

  def validate_quantiles(quantiles), do: quantiles_error(quantiles)

  defp quantiles_error(quantiles),
    do:
      {:error,
       "expected quantiles, a list of numbers from 0 to 1, or :none, got: #{inspect(quantiles)}"}

  # NimbleOptions' check of a density's `bounds:`: `{low, high}`, the low a number or
  # `:neg_infinity`, the high a number or `:infinity`, not below the low, each number kept as a
  # float; bounds high to low would keep no row, where R draws a row of missing values.
  @doc false
  @spec validate_bounds(term()) ::
          {:ok, {float() | :neg_infinity, float() | :infinity}} | {:error, String.t()}
  def validate_bounds({low, high})
      when (is_number(low) or low == :neg_infinity) and (is_number(high) or high == :infinity) and
             not (is_number(low) and is_number(high) and low > high),
      do: {:ok, {bound(low), bound(high)}}

  def validate_bounds(bounds),
    do:
      {:error,
       "expected bounds {low, high}, the low a number or :neg_infinity, the high a number or " <>
         ":infinity, not below the low, got: #{inspect(bounds)}"}

  defp bound(bound) when is_number(bound), do: bound / 1
  defp bound(infinity), do: infinity

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

  # NimbleOptions' check of a theme element's colour: a CSS colour, with an alpha of its own too,
  # kept in its one spelling, uppercase hex; never `:none`, which no line or text takes yet.
  @doc false
  @spec validate_theme_color(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_theme_color(:none),
    do: {:error, "expected a CSS colour, got: :none (an element itself may be :none, removed)"}

  def validate_theme_color(color), do: validate_color(color)

  # NimbleOptions' check of a theme rectangle's fill or border colour: a CSS colour, with an alpha
  # of its own too, or `:none` for none.
  @doc false
  @spec validate_theme_rect_color(term()) :: {:ok, String.t() | :none} | {:error, String.t()}
  def validate_theme_rect_color(:none), do: {:ok, :none}
  def validate_theme_rect_color(color), do: validate_theme_color(color)

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

  # NimbleOptions' check of a complete theme's `base_size:`: points, 0 or more, kept as a float.
  @doc false
  @spec validate_base_size(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_base_size(size) when is_number(size) and size >= 0, do: {:ok, size / 1}

  def validate_base_size(size),
    do: {:error, "expected a size in points, 0 or more, got: #{inspect(size)}"}

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

  # NimbleOptions' check of a theme point, `{x, y}`, each a number, a share of the panels' width or
  # height, which may lie beyond them.
  @doc false
  @spec validate_theme_point(term()) :: {:ok, {number(), number()}} | {:error, String.t()}
  def validate_theme_point({x, y} = point) when is_number(x) and is_number(y), do: {:ok, point}

  def validate_theme_point(point),
    do: {:error, "expected a point: {x, y}, each a number, got: #{inspect(point)}"}

  # NimbleOptions' check of a theme justification: `:center` or a side, or `{horizontal,
  # vertical}`, each the name of a point across or up, or, where `takes` is `:shares`, a number, a
  # share of the box's width or height, as grid's `valid.just()` reads one; ggplot2's
  # `legend.box.just` takes names alone (`:names`).
  @doc false
  @spec validate_theme_justification(term(), :shares | :names) ::
          {:ok, Theme.justification()} | {:error, String.t()}
  def validate_theme_justification(name, _takes) when name in @theme_justification_names,
    do: {:ok, name}

  def validate_theme_justification({across, up} = justification, takes)
      when is_justification_across(across, takes) and is_justification_up(up, takes),
      do: {:ok, justification}

  def validate_theme_justification(justification, takes) do
    {:error,
     "expected a justification: one of #{inspect(@theme_justification_names)}, or " <>
       "{horizontal, vertical}, each #{justification_sides(takes)}, got: " <>
       inspect(justification)}
  end

  defp justification_sides(:shares),
    do: "a number or :left, :center or :right across and :bottom, :center or :top up"

  defp justification_sides(:names),
    do: ":left, :center or :right across and :bottom, :center or :top up"

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

  # NimbleOptions' check of a theme text's `hjust:` or `vjust:`: any number, kept as a float, never
  # one of a text layer's words, which R's `element_text()` refuses.
  @doc false
  @spec validate_text_justification(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_text_justification(just) when is_number(just), do: {:ok, just / 1}

  def validate_text_justification(just),
    do:
      {:error, "expected a number, a share of the text's width or height, got: #{inspect(just)}"}

  # NimbleOptions' check of a theme text's `lineheight:`: a number 0 or more, kept as a float, where
  # R takes a negative one too and stacks a text's lines upward.
  @doc false
  @spec validate_lineheight(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_lineheight(height) when is_number(height) and height >= 0, do: {:ok, height / 1}

  def validate_lineheight(height),
    do: {:error, "expected a line height, a number 0 or more, got: #{inspect(height)}"}

  # NimbleOptions' check of a bar's or a tile's `width:`: any number, kept as a float, as R keeps
  # one; a negative width puts a mark's edges the other way round, which draws it as wide.
  @doc false
  @spec validate_width(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_width(width) when is_number(width), do: {:ok, width / 1}
  def validate_width(width), do: {:error, "expected a width, a number, got: #{inspect(width)}"}

  # NimbleOptions' check of a tile's `height:`: any number, kept as a float, as R keeps one.
  @doc false
  @spec validate_height(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_height(height) when is_number(height), do: {:ok, height / 1}

  def validate_height(height),
    do: {:error, "expected a height, a number, got: #{inspect(height)}"}

  # NimbleOptions' check of a bar's `just:`: where it sits against its position, from 0 to 1, kept
  # as a float.
  @doc false
  @spec validate_just(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_just(just) when is_number(just) and just >= 0 and just <= 1, do: {:ok, just / 1}

  def validate_just(just),
    do: {:error, "expected a number from 0 to 1, got: #{inspect(just)}"}

  # NimbleOptions' check of a layer's `position:`: one of the positions its marks take, alone or in
  # a tuple with a keyword list of its options, each given once, recorded as it is given, which
  # `Plot` validates again to fill each default. `positions` is one of the
  # families below: the positions the marks take (`takes:`), those they refuse, each with the
  # reason, R's, why it would fail or move nothing (`refuses:`), the options of a position they
  # refuse, by the position's name, each with why it would change nothing (`refuses_options:`),
  # and, for marks with no width of their own, why both dodges need their `width:`
  # (`needs_width:`).
  @doc false
  @spec validate_position(term(), keyword()) ::
          {:ok, atom() | {atom(), keyword()}} | {:error, String.t()}
  def validate_position(kind, positions) when is_atom(kind),
    do: checked_position(kind, [], kind, positions)

  def validate_position({kind, options} = position, positions)
      when is_atom(kind) and is_list(options),
      do: checked_position(kind, options, position, positions)

  def validate_position(position, positions),
    do: {:error, position_error(position, Keyword.fetch!(positions, :takes))}

  # The position `kind` with `options`, as `given` wrote it, checked against `positions`.
  defp checked_position(kind, options, given, positions) do
    with :ok <- taken(kind, given, positions),
         true <- once?(options) || {:error, position_options_error(given)},
         :ok <- unrefused_kind_options(kind, options, given),
         {:ok, _validated} <- NimbleOptions.validate(options, position_kind(kind)),
         :ok <- unrefused_options(kind, options, given, positions),
         :ok <- with_width(kind, options, given, Keyword.fetch(positions, :needs_width)) do
      {:ok, given}
    else
      {:error, %NimbleOptions.ValidationError{message: message}} ->
        {:error, "in #{inspect(kind)}'s options, " <> message}

      error ->
        error
    end
  end

  # Whether the marks take `kind`: one they refuse names the reason.
  defp taken(kind, given, positions) do
    takes = Keyword.fetch!(positions, :takes)

    refusal =
      positions
      |> Keyword.get(:refuses, [])
      |> Keyword.fetch(kind)

    case {kind in takes, refusal} do
      {true, _refusal} -> :ok
      {false, {:ok, reason}} -> {:error, position_error(given, takes) <> ", since " <> reason}
      {false, :error} -> {:error, position_error(given, takes)}
    end
  end

  # Whether `options` names none of the options `kind` refuses whatever the marks: one it refuses
  # names the reason.
  defp unrefused_kind_options(kind, options, given),
    do: refused_option(kind, options, given, Map.get(@position_kind_refused_options, kind, []))

  # Whether `options` names none of the options the marks refuse for `kind`: one they refuse
  # names the reason.
  defp unrefused_options(kind, options, given, positions) do
    refused =
      positions
      |> Keyword.get(:refuses_options, [])
      |> Keyword.get(kind, [])

    refused_option(kind, options, given, refused)
  end

  # `:ok` where `options` names none of `refused`, else an error naming the first and its reason.
  defp refused_option(kind, options, given, refused) do
    case Enum.find(refused, :none, fn {option, _reason} -> Keyword.has_key?(options, option) end) do
      :none ->
        :ok

      {option, reason} ->
        {:error,
         "expected #{inspect(kind)} without its #{option}:, got: #{inspect(given)}, since " <>
           reason}
    end
  end

  # Dodging marks with no width of their own, either way, needs the width they share.
  defp with_width(kind, options, given, {:ok, reason}) when kind in [:dodge, :dodge2] do
    if Keyword.has_key?(options, :width),
      do: :ok,
      else:
        {:error,
         "expected #{inspect(kind)} with its width:, {#{inspect(kind)}, width: width}, got: " <>
           "#{inspect(given)}, since " <> reason}
  end

  defp with_width(_kind, _options, _given, _needs_width), do: :ok

  defp position_error(position, kinds),
    do:
      "expected #{in_words(kinds)}, alone or in a tuple with a keyword list of its options, " <>
        "got: " <> inspect(position)

  # Whether `options` is a keyword list naming each option at most once.
  defp once?(options), do: Keyword.keyword?(options) and distinct_keys?(options)

  defp distinct_keys?(options) do
    names = Keyword.keys(options)
    names == Enum.uniq(names)
  end

  defp position_options_error({kind, options}),
    do:
      "expected #{inspect(kind)}'s options to be a keyword list naming each at most once, " <>
        "got: " <> inspect(options)

  # Names written as a list in a sentence: `:a`, `:a or :b`, `:a, :b or :c`.
  defp in_words([kind]), do: inspect(kind)

  defp in_words(kinds) do
    {last, rest} = List.pop_at(kinds, -1)
    Enum.map_join(rest, ", ", &inspect/1) <> " or " <> inspect(last)
  end

  # NimbleOptions' check of one of a summary's values, `fun:`, `fun_min:` or `fun_max:`: a summary
  # by name, or a function of the values at a position.
  @doc false
  @spec validate_summary_function(term()) :: {:ok, atom() | function()} | {:error, String.t()}
  def validate_summary_function(summary) when summary in [:mean, :median, :min, :max],
    do: {:ok, summary}

  def validate_summary_function(summary) when is_function(summary, 1), do: {:ok, summary}

  def validate_summary_function(summary) do
    {:error,
     "expected :mean, :median, :min, :max or a function of one argument, got: " <>
       inspect(summary)}
  end

  # NimbleOptions' check of a summary's `fun_data:`: a whole summary by name, alone or in a tuple
  # with a keyword list of its arguments, each given at most once, recorded with every argument
  # it takes, in `@summary_data_arguments`' order, a number a float; `:mean_cl_normal` takes
  # `conf_int:` or `mult:`, never both, and records the one it is given.
  @doc false
  @spec validate_summary_data(term()) ::
          {:ok, Giggly.Stat.Summary.summary_data()} | {:error, String.t()}
  def validate_summary_data(summary) when is_map_key(@summary_data_arguments, summary),
    do: validate_summary_data({summary, []})

  def validate_summary_data({summary, arguments})
      when is_map_key(@summary_data_arguments, summary) and is_list(arguments) do
    with :ok <- check_summary_data_names(summary, arguments),
         {:ok, checked} <- check_summary_data_values(summary, arguments) do
      {:ok, {summary, summary_data_recorded(summary, checked)}}
    end
  end

  def validate_summary_data(summary) do
    {:error,
     "expected :mean_se, :mean_cl_normal, :mean_sdl, :median_hilow or :mean_cl_boot, alone " <>
       "or in a tuple with a keyword list of its arguments, got: " <> inspect(summary)}
  end

  defp check_summary_data_names(summary, arguments) do
    taken = summary_data_taken(summary)
    names_taken = Keyword.keyword?(arguments) and taken_once?(Keyword.keys(arguments), taken)
    summary_data_names(summary, arguments, taken, names_taken)
  end

  # Whether every name is one the summary takes, and none is given twice.
  defp taken_once?(names, taken),
    do: Enum.all?(names, fn name -> name in taken end) and names == Enum.uniq(names)

  defp summary_data_names(summary, arguments, taken, false) do
    listed = Enum.map_join(taken, ", ", fn name -> "#{name}:" end)

    {:error,
     "expected {#{inspect(summary)}, arguments}'s arguments to be a keyword list of " <>
       listed <> " each at most once, got: " <> inspect(arguments)}
  end

  defp summary_data_names(:mean_cl_normal, arguments, _taken, true) do
    if Keyword.has_key?(arguments, :conf_int) and Keyword.has_key?(arguments, :mult),
      do:
        {:error,
         "expected {:mean_cl_normal, arguments} to give conf_int: or mult:, not both, got: " <>
           inspect(arguments)},
      else: :ok
  end

  defp summary_data_names(_summary, _arguments, _taken, true), do: :ok

  defp check_summary_data_values(summary, arguments) do
    Enum.reduce_while(arguments, {:ok, []}, fn {name, value}, {:ok, checked} ->
      case summary_data_value(summary, name, value) do
        {:ok, value} -> {:cont, {:ok, [{name, value} | checked]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp summary_data_value(_summary, :mult, mult) when is_number(mult), do: {:ok, mult / 1}

  defp summary_data_value(:mean_cl_normal, :conf_int, level)
       when is_number(level) and level >= 0 and level < 1,
       do: {:ok, level / 1}

  defp summary_data_value(summary, :conf_int, level)
       when summary in [:median_hilow, :mean_cl_boot] and is_number(level) and level >= 0 and
              level <= 1,
       do: {:ok, level / 1}

  defp summary_data_value(:mean_cl_boot, :resamples, count) when is_integer(count) and count >= 1,
    do: {:ok, count}

  defp summary_data_value(:mean_cl_boot, :seed, seed) when is_integer(seed), do: {:ok, seed}

  defp summary_data_value(summary, name, value) do
    {:error,
     "expected #{inspect(summary)}'s #{name}: to be " <>
       summary_data_wanted(summary, name) <> ", got: " <> inspect(value)}
  end

  defp summary_data_wanted(_summary, :mult), do: "a number"
  defp summary_data_wanted(:mean_cl_normal, :conf_int), do: "a number from 0, below 1"
  defp summary_data_wanted(_summary, :conf_int), do: "a number from 0 to 1"
  defp summary_data_wanted(_summary, :resamples), do: "a whole number, 1 or more"
  defp summary_data_wanted(_summary, :seed), do: "an integer"

  defp summary_data_taken(:mean_cl_normal), do: [:conf_int, :mult]

  defp summary_data_taken(summary) do
    @summary_data_arguments
    |> Map.fetch!(summary)
    |> Keyword.keys()
  end

  defp summary_data_recorded(:mean_cl_normal, [mult: _mult] = checked), do: checked

  defp summary_data_recorded(summary, checked) do
    for {name, default} <- Map.fetch!(@summary_data_arguments, summary),
        do: {name, Keyword.get(checked, name, default)}
  end

  # NimbleOptions' check of how far a jittered point moves at most along one axis: a distance in
  # the axis's units, 0 or more, kept as a float.
  @doc false
  @spec validate_jitter_amount(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_jitter_amount(amount) when is_number(amount) and amount >= 0,
    do: {:ok, amount / 1}

  def validate_jitter_amount(amount),
    do: {:error, "expected a distance, a number 0 or more, got: #{inspect(amount)}"}

  # NimbleOptions' check of dodging by clusters' `padding:`: the fraction of its share each bar
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

  # NimbleOptions' check of a diagonal line's intercept or slope: any number, kept as a float, as
  # R keeps one.
  @doc false
  @spec validate_coefficient(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_coefficient(coefficient) when is_number(coefficient), do: {:ok, coefficient / 1}

  def validate_coefficient(coefficient),
    do: {:error, "expected a number, or a list of them, got: #{inspect(coefficient)}"}

  # NimbleOptions' check of a scale's `oob:`: one of R's `oob_*` functions by name, or a function
  # of the values and the limits. `:discard` is refused: R's `oob_discard()` returns fewer values
  # than it is handed, which ggplot2 recycles over the rows, so its marks are drawn at values other
  # rows hold, a meaning no plot wants.
  @doc false
  @spec validate_oob(term()) :: {:ok, atom() | function()} | {:error, String.t()}
  def validate_oob(name) when name in @oob_names, do: {:ok, name}
  def validate_oob(oob) when is_function(oob, 2), do: {:ok, oob}

  def validate_oob(:discard) do
    {:error,
     "oob: :discard is not taken: it would leave fewer values than rows, which ggplot2 " <>
       "recycles, drawing marks at values other rows hold; use :censor, which makes a value " <>
       "outside the limits missing"}
  end

  def validate_oob(oob) do
    {:error,
     "expected one of #{Enum.map_join(@oob_names, ", ", &inspect/1)}, or a function of two " <>
       "arguments, the values and the limits, got: #{inspect(oob)}"}
  end

  # NimbleOptions' check of a continuous scale's transformation: one `Scales.Transform` resolves,
  # a name, a composition or one a user made, as ggplot2's `transform` takes any. A date, date-time
  # or time one, alone or first in a composition, is refused, since `scale_x_date/2` and its kin
  # place those columns and no other scale takes them; an unknown name, or a composition
  # `Scales.Transform` refuses, is refused naming why. A user's function failing on the domain's
  # ends raises its own error.
  @doc false
  @spec validate_transform(term()) :: {:ok, Transform.name()} | {:error, String.t()}
  def validate_transform(name) do
    case {Transform.temporal?(name), Transform.resolved(name)} do
      {true, _resolved} ->
        {:error,
         "expected a transformation of numbers, since Plot.scale_x_date/2, " <>
           "Plot.scale_x_datetime/2 and Plot.scale_x_time/2 and their y twins place dates, " <>
           "date-times and times, got: #{inspect(name)}"}

      {false, {:ok, name}} ->
        {:ok, name}

      {false, {:error, :unknown}} ->
        {:error, "expected a transformation: #{@transform_names_doc}, got: #{inspect(name)}"}

      {false, {:error, reason}} ->
        {:error,
         "expected a transformation, got: #{inspect(name)}, which Scales.Transform refuses: " <>
           reason}
    end
  end

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
  # float, a function of one or two arguments, or `:none` for none.
  @doc false
  @spec validate_breaks(term()) :: {:ok, [float()] | function() | :none} | {:error, String.t()}
  def validate_breaks(:none), do: {:ok, :none}
  def validate_breaks(breaker) when is_breaks_function(breaker), do: {:ok, breaker}

  def validate_breaks(breaks) when is_list(breaks) do
    case Enum.reject(breaks, &is_number/1) do
      [] -> {:ok, Enum.map(breaks, fn break -> break / 1 end)}
      [other | _rest] -> {:error, "expected a list of numbers, got: #{inspect(other)} in it"}
    end
  end

  def validate_breaks(breaks) do
    {:error,
     "expected a list of numbers, a function of one or two arguments or :none, got: " <>
       inspect(breaks)}
  end

  # NimbleOptions' check of a scale's labels: a list of strings, `nil` for a missing one, a function
  # of one argument, which is handed the breaks, or `:none` for none.
  @doc false
  @spec validate_scale_labels(term()) ::
          {:ok, [String.t() | nil] | (list() -> list()) | :none} | {:error, String.t()}
  def validate_scale_labels(:none), do: {:ok, :none}
  def validate_scale_labels(labeller) when is_function(labeller, 1), do: {:ok, labeller}

  def validate_scale_labels(labels) when is_list(labels) do
    case Enum.reject(labels, fn label -> is_binary(label) or is_nil(label) end) do
      [] ->
        {:ok, labels}

      [other | _rest] ->
        {:error, "expected a list of strings or nil, got: #{inspect(other)} in it"}
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
  def validate_expand(expansion) do
    with true <- Keyword.keyword?(expansion),
         [] <- Keyword.keys(expansion) -- [:mult, :add],
         {:ok, mult} <- expansion_ends(Keyword.get_values(expansion, :mult)),
         {:ok, add} <- expansion_ends(Keyword.get_values(expansion, :add)) do
      {:ok, [mult: mult, add: add]}
    else
      _invalid -> expansion_error(expansion)
    end
  end

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
  # (`discrete_values/1`), a function of one argument, handed the limits, as ggplot2 calls one,
  # or `:none` for none.
  @doc false
  @spec validate_discrete_breaks(term()) ::
          {:ok, list() | (list() -> list()) | :none} | {:error, String.t()}
  def validate_discrete_breaks(:none), do: {:ok, :none}
  def validate_discrete_breaks(breaker) when is_function(breaker, 1), do: {:ok, breaker}
  def validate_discrete_breaks(values) when is_list(values), do: discrete_values(values)

  def validate_discrete_breaks(values) do
    {:error,
     "expected a list of values, each a string, a number, an atom or nil, a function of one " <>
       "argument, or :none, got: " <>
       inspect(values)}
  end

  # A list of a discrete axis's values, each a string, a number or an atom, `nil` and the booleans
  # among them, as a discrete column holds them, and none named twice, a number and the float
  # equal to it being one value, as the scale matches them (`Scales.DataRange.key/1`).
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
    case values -- Enum.uniq_by(values, &DataRange.key/1) do
      [] ->
        {:ok, values}

      [repeated | _rest] ->
        {:error,
         "expected each value once, got: #{inspect(repeated)} more than once in #{inspect(values)}"}
    end
  end

  defp discrete_value?(value), do: is_binary(value) or is_number(value) or is_atom(value)

  # NimbleOptions' check of a discrete scale's labels: a list of strings, a map from a value
  # (`discrete_values/1`) to its label, either's `nil` a missing one, a function of one argument,
  # which is handed the breaks, or `:none` for none.
  @doc false
  @spec validate_discrete_labels(term()) ::
          {:ok, [String.t() | nil] | map() | (list() -> list()) | :none} | {:error, String.t()}
  def validate_discrete_labels(labels) when is_map(labels) and not is_struct(labels) do
    values = Map.keys(labels)
    texts = Map.values(labels)

    with {:ok, _values} <- discrete_values(values),
         [] <- Enum.reject(texts, fn text -> is_binary(text) or is_nil(text) end) do
      {:ok, labels}
    else
      {:error, _message} = error ->
        error

      [other | _rest] ->
        {:error,
         "expected each label a string or nil, got: #{inspect(other)} in #{inspect(labels)}"}
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

  # NimbleOptions' check of a date scale's breaks or minor breaks: a list of dates, a function of
  # one or two arguments, or `:none` for none.
  @doc false
  @spec validate_dates(term()) :: {:ok, [Date.t()] | function() | :none} | {:error, String.t()}
  def validate_dates(:none), do: {:ok, :none}
  def validate_dates(breaker) when is_breaks_function(breaker), do: {:ok, breaker}

  def validate_dates(dates) when is_list(dates) do
    case Enum.reject(dates, fn date -> is_struct(date, Date) end) do
      [] -> {:ok, dates}
      [other | _rest] -> {:error, "expected a list of dates, got: #{inspect(other)} in it"}
    end
  end

  def validate_dates(dates) do
    {:error,
     "expected a list of dates, a function of one or two arguments or :none, got: " <>
       inspect(dates)}
  end

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

  # NimbleOptions' check of a date-time scale's limits: `{low, high}`, each a date-time or `nil` for
  # an end the data decides, both given of one kind, `DateTime` or `NaiveDateTime`, in either
  # order, which the scale sorts once transformed.
  @doc false
  @spec validate_datetime_limits(term()) ::
          {:ok, {DateTime.t() | NaiveDateTime.t() | nil, DateTime.t() | NaiveDateTime.t() | nil}}
          | {:error, String.t()}
  def validate_datetime_limits({low, high} = limits)
      when (is_datetime(low) or is_nil(low)) and (is_datetime(high) or is_nil(high)) do
    case one_kind([low, high]) do
      :ok -> {:ok, limits}
      :error -> {:error, mixed_datetimes_message("limits", limits)}
    end
  end

  def validate_datetime_limits(limits) do
    {:error,
     "expected {low, high}, each a DateTime, a NaiveDateTime or nil for an end the data " <>
       "decides, got: #{inspect(limits)}"}
  end

  # NimbleOptions' check of a date-time scale's breaks or minor breaks: a list of date-times of one
  # kind, `DateTime` or `NaiveDateTime`, a function of one or two arguments, or `:none` for none.
  @doc false
  @spec validate_datetimes(term()) ::
          {:ok, [DateTime.t()] | [NaiveDateTime.t()] | function() | :none} | {:error, String.t()}
  def validate_datetimes(:none), do: {:ok, :none}
  def validate_datetimes(breaker) when is_breaks_function(breaker), do: {:ok, breaker}

  def validate_datetimes(datetimes) when is_list(datetimes) do
    with [] <- Enum.reject(datetimes, fn datetime -> is_datetime(datetime) end),
         :ok <- one_kind(datetimes) do
      {:ok, datetimes}
    else
      [other | _rest] -> {:error, "expected a list of date-times, got: #{inspect(other)} in it"}
      :error -> {:error, mixed_datetimes_message("list", datetimes)}
    end
  end

  def validate_datetimes(datetimes) do
    {:error,
     "expected a list of date-times, a function of one or two arguments or :none, got: " <>
       inspect(datetimes)}
  end

  # Whether the date-times given, `nil` aside, are all of one kind: an instant in a time zone, or
  # a naive date-time, which is not one.
  defp one_kind(values) do
    kinds =
      values
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn %struct{} -> struct end)
      |> Enum.uniq()

    case kinds do
      [_both, _kinds] -> :error
      _one_or_none -> :ok
    end
  end

  defp mixed_datetimes_message(what, given) do
    "expected DateTimes alone or NaiveDateTimes alone, since a naive date-time names no " <>
      "instant, got both in the #{what} #{inspect(given)}"
  end

  # NimbleOptions' check of a date-time scale's step between breaks: one of a second, a minute,
  # an hour, a day, a week, a month and a year and how many of it, a positive whole number.
  @doc false
  @spec validate_datetime_step(term()) ::
          {:ok, [{:second | :minute | :hour | :day | :week | :month | :year, pos_integer()}]}
          | {:error, String.t()}
  def validate_datetime_step([{unit, count}] = step)
      when unit in [:second, :minute, :hour, :day, :week, :month, :year] and is_integer(count) and
             count > 0,
      do: {:ok, step}

  def validate_datetime_step(step) do
    {:error,
     "expected one of :second, :minute, :hour, :day, :week, :month and :year and how many of " <>
       "it, a positive whole number, such as [hour: 6], got: #{inspect(step)}"}
  end

  # NimbleOptions' check of a date-time scale's label format: a string `Calendar.strftime/3`
  # writes a date-time in, tried on one, so a format it cannot write raises at the call rather
  # than when the plot is run.
  @doc false
  @spec validate_datetime_format(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_datetime_format(format) when is_binary(format) do
    Calendar.strftime(~U[1970-01-01 00:00:00Z], format)
    {:ok, format}
  rescue
    exception ->
      {:error,
       "expected a format Calendar.strftime/3 can write a date-time in, got: " <>
         "#{inspect(format)}, which it cannot: #{Exception.message(exception)}"}
  end

  def validate_datetime_format(format),
    do: {:error, "expected a format, a string, got: #{inspect(format)}"}

  # NimbleOptions' check of a time scale's limits: `{low, high}`, each a time of day or `nil` for an
  # end the data decides, in either order, which the scale sorts once transformed.
  @doc false
  @spec validate_time_limits(term()) ::
          {:ok, {Time.t() | nil, Time.t() | nil}} | {:error, String.t()}
  def validate_time_limits({low, high} = limits) when is_time_limit(low) and is_time_limit(high),
    do: {:ok, limits}

  def validate_time_limits(limits) do
    {:error,
     "expected {low, high}, each a time of day or nil for an end the data decides, got: " <>
       inspect(limits)}
  end

  # NimbleOptions' check of a time scale's breaks or minor breaks: a list of times of day, a
  # function of one or two arguments, or `:none` for none.
  @doc false
  @spec validate_times(term()) :: {:ok, [Time.t()] | function() | :none} | {:error, String.t()}
  def validate_times(:none), do: {:ok, :none}
  def validate_times(breaker) when is_breaks_function(breaker), do: {:ok, breaker}

  def validate_times(times) when is_list(times) do
    case Enum.reject(times, fn time -> is_struct(time, Time) end) do
      [] -> {:ok, times}
      [other | _rest] -> {:error, "expected a list of times of day, got: #{inspect(other)} in it"}
    end
  end

  def validate_times(times) do
    {:error,
     "expected a list of times of day, a function of one or two arguments or :none, got: " <>
       inspect(times)}
  end

  # NimbleOptions' check of a time scale's step between breaks: one of a second, a minute and an
  # hour and how many of it, a positive whole number.
  @doc false
  @spec validate_time_step(term()) ::
          {:ok, [{:second | :minute | :hour, pos_integer()}]} | {:error, String.t()}
  def validate_time_step([{unit, count}] = step)
      when unit in [:second, :minute, :hour] and is_integer(count) and count > 0,
      do: {:ok, step}

  def validate_time_step(step) do
    {:error,
     "expected one of :second, :minute and :hour and how many of it, a positive whole number, " <>
       "such as [minute: 30], got: #{inspect(step)}"}
  end

  # NimbleOptions' check of a time scale's label format: a string `Calendar.strftime/3` writes a
  # time of day in, tried on one, so a format it cannot write, such as one with a date's parts,
  # raises at the call rather than when the plot is run.
  @doc false
  @spec validate_time_format(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_time_format(format) when is_binary(format) do
    Calendar.strftime(~T[00:00:00], format)
    {:ok, format}
  rescue
    exception ->
      {:error,
       "expected a format Calendar.strftime/3 can write a time of day in, got: " <>
         "#{inspect(format)}, which it cannot: #{Exception.message(exception)}"}
  end

  def validate_time_format(format),
    do: {:error, "expected a format, a string, got: #{inspect(format)}"}

  # NimbleOptions' check of an axis's limits as `lims/2` takes them: a list of a discrete axis's
  # values, `{low, high}` of dates or `nil` for a date axis, of date-times of one kind or `nil` for
  # a date-time one, or else of numbers or `nil` for a continuous one. Times of day are refused,
  # as ggplot2's `xlim()` fails on two `hms` values; a time scale's `limits:` takes them.
  @doc false
  @spec validate_axis_limits(term()) :: {:ok, list() | tuple()} | {:error, String.t()}
  def validate_axis_limits(values) when is_list(values), do: validate_discrete_limits(values)

  def validate_axis_limits({low, high} = limits)
      when is_struct(low, Date) or is_struct(high, Date),
      do: validate_date_limits(limits)

  def validate_axis_limits({low, high} = limits) when is_datetime(low) or is_datetime(high),
    do: validate_datetime_limits(limits)

  def validate_axis_limits({low, high} = limits)
      when is_struct(low, Time) or is_struct(high, Time) do
    {:error,
     "expected no times of day, which a time scale's limits: take, as in " <>
       "scale_x_time(plot, limits: {low, high}), got: #{inspect(limits)}"}
  end

  def validate_axis_limits(limits) do
    case validate_limits(limits) do
      {:ok, _limits} = valid ->
        valid

      {:error, _message} ->
        {:error,
         "expected {low, high}, two numbers, two dates or two date-times, each nil for an " <>
           "end the data decides, or a list of a discrete axis's values, got: #{inspect(limits)}"}
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

  # NimbleOptions' check of `lims/2`'s limits for a colour, fill, alpha, size or line width scale:
  # a list of a discrete scale's values, or `{low, high}`, two numbers, each kept as a float, or
  # `nil` for an end the data decides, high to low reversing the scale, as an axis's do.
  @doc false
  @spec validate_legend_limits(term()) ::
          {:ok, list() | {float() | nil, float() | nil}} | {:error, String.t()}
  def validate_legend_limits(values) when is_list(values), do: validate_discrete_limits(values)

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

  # NimbleOptions' check of a gradient's `values:`: a list of numbers, at least two of them
  # different, since a place is moved along the straight lines between them, kept as floats. R also
  # drops an `NA`, which is refused here, as no value written by hand is missing.
  @doc false
  @spec validate_gradient_values(term()) :: {:ok, [float(), ...]} | {:error, String.t()}
  def validate_gradient_values([_first | _rest] = values) do
    if Enum.all?(values, &is_number/1) do
      floats = Enum.map(values, fn value -> value / 1 end)

      if Enum.min(floats) < Enum.max(floats),
        do: {:ok, floats},
        else:
          {:error,
           "expected at least two different places, since the colours are blended between " <>
             "them, got: #{inspect(values)}"}
    else
      values_error(values)
    end
  end

  def validate_gradient_values(other), do: values_error(other)

  defp values_error(values), do: {:error, "expected a list of numbers, got: #{inspect(values)}"}

  # NimbleOptions' check of a brewer scale's `palette:`: a ColorBrewer palette's name, exactly as
  # R's `pal_brewer()` takes it, or a number counting from 1 among its type's, which the scale
  # function looks up, since it alone reads `type:` too.
  @doc false
  @spec validate_brewer_palette(term()) ::
          {:ok, String.t() | pos_integer()} | {:error, String.t()}
  def validate_brewer_palette(name) when name in @brewer_names, do: {:ok, name}
  def validate_brewer_palette(number) when is_integer(number) and number > 0, do: {:ok, number}

  def validate_brewer_palette(other),
    do:
      {:error,
       "expected a ColorBrewer palette's name, one of #{inspect(@brewer_names)}, or its number " <>
         "among its type's, counting from 1, got: #{inspect(other)}"}

  # NimbleOptions' check of a discrete colour scale's `palette:`: a name scales knows, as its
  # palette (`Scales.Palette.named/1`), or a list of colours (`validate_palette_colors/1`), as a
  # manual palette of them.
  @doc false
  @spec validate_discrete_palette(term()) :: {:ok, Palette.t()} | {:error, String.t()}
  def validate_discrete_palette(name) when is_binary(name), do: named_palette(name)

  def validate_discrete_palette([_first | _rest] = colors) do
    with {:ok, parsed} <- validate_palette_colors(colors), do: {:ok, {:manual, parsed}}
  end

  def validate_discrete_palette(other), do: palette_error(other)

  # NimbleOptions' check of a continuous colour scale's `palette:`: a name scales knows, as its
  # palette (`Scales.Palette.named/1`), or a list of colours (`validate_gradient_colors/1`), as a
  # gradient through them.
  @doc false
  @spec validate_continuous_palette(term()) :: {:ok, Palette.t()} | {:error, String.t()}
  def validate_continuous_palette(name) when is_binary(name), do: named_palette(name)

  def validate_continuous_palette([_first | _rest] = colors) do
    with {:ok, parsed} <- validate_gradient_colors(colors), do: {:ok, {:gradient, parsed}}
  end

  def validate_continuous_palette(other), do: palette_error(other)

  defp palette_error(palette),
    do:
      {:error,
       "expected a palette's name or a list of at least one colour, got: #{inspect(palette)}"}

  # The palette scales names `name`, or its refusal's message, which lists the names.
  defp named_palette(name) do
    {:ok, Palette.named(name)}
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  # NimbleOptions' check of a discrete palette's colours: a list of at least one, each a colour or
  # `:none` (`validate_color/1`).
  @doc false
  @spec validate_palette_colors(term()) :: {:ok, [ColorOperations.t()]} | {:error, String.t()}
  def validate_palette_colors([_first | _rest] = colors),
    do: checked_each(colors, &validate_color/1)

  def validate_palette_colors(other),
    do: {:error, "expected a list of at least one colour, got: #{inspect(other)}"}

  # NimbleOptions' check of a manual scale's `values:` for `aesthetic`: a list of at least one
  # colour (`validate_color/1`), shape (`validate_shape/1`) or line type (`validate_linetype/1`),
  # or a map from a value (`discrete_values/1`) to its colour, shape or line type.
  @doc false
  @spec validate_manual_values(term(), :color | :shape | :linetype) ::
          {:ok, list() | %{term() => ColorOperations.t() | atom() | tuple()}}
          | {:error, String.t()}
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
  # `kind`: `:legend`, `:none` or a legend `guide_legend/1` made, for any; `:colorbar` or
  # `:colorsteps` for a continuous colour or fill scale alone, as each shows a continuous scale's
  # colours, and `:colorsteps` for a binned one, whose colour bar is refused, so a discrete scale's
  # is refused, and an alpha, a shape, a size, a line type or a line width scale's whatever its
  # kind.
  @doc false
  @spec validate_guide(
          term(),
          :continuous | :binned | :discrete | :alpha | :shape | :size | :linetype | :linewidth
        ) ::
          {:ok, Giggly.Plot.guide()} | {:error, String.t()}
  def validate_guide(%Guide.Legend{} = guide, _kind), do: {:ok, guide}
  def validate_guide(guide, _kind) when guide in [:legend, :none], do: {:ok, guide}
  def validate_guide(guide, :continuous) when guide in [:colorbar, :colorsteps], do: {:ok, guide}
  def validate_guide(:colorsteps, :binned), do: {:ok, :colorsteps}

  def validate_guide(:colorbar, :binned),
    do:
      {:error, "a colour bar shows a continuous scale, and this one is binned; give :colorsteps"}

  def validate_guide(:colorbar, :discrete),
    do: {:error, "a colour bar shows a continuous scale, and this one is discrete; give :legend"}

  def validate_guide(:colorsteps, :discrete),
    do:
      {:error,
       "colour steps show a binned or continuous scale, and this one is discrete; give :legend"}

  def validate_guide(:colorbar, aesthetic),
    do:
      {:error,
       "a colour bar shows colour or fill, never #{Aesthetics.in_words(aesthetic)}; give :legend"}

  def validate_guide(:colorsteps, aesthetic),
    do:
      {:error,
       "colour steps show colour or fill, never #{Aesthetics.in_words(aesthetic)}; give :legend"}

  def validate_guide(guide, _kind) do
    {:error,
     "expected :legend, :colorbar, :colorsteps, :none or a legend Plot.guide_legend/1 makes, " <>
       "got: " <> inspect(guide)}
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
  # call, `:infinity` or `:neg_infinity`, `nil` for none, a string, `true` or `false`, a date, a
  # date-time, naive or not, or a time of day.
  @doc false
  @spec validate_annotation_position(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_annotation_position(value) when is_number(value), do: {:ok, value / 1}

  def validate_annotation_position(value)
      when is_binary(value) or is_boolean(value) or value in [nil, :infinity, :neg_infinity],
      do: {:ok, value}

  def validate_annotation_position(%struct{} = value)
      when struct in [Date, DateTime, NaiveDateTime, Time],
      do: {:ok, value}

  def validate_annotation_position(value) do
    {:error,
     "expected a position, or a list of them: a number, :infinity or :neg_infinity, nil, a " <>
       "string, true or false, a date, a date-time or a time, got: #{inspect(value)}"}
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

  # NimbleOptions' check of an `arrow:` option: `true`, an arrowhead at its defaults, or a keyword
  # list of its options, an option given twice refused as `Aesthetics.canonicalize/1` refuses one;
  # kept as a map, its angle a float, its length in points worked out as the theme works one out,
  # and its fill resolved.
  @doc false
  @spec validate_arrow(term()) :: {:ok, map()} | {:error, String.t()}
  def validate_arrow(true), do: validate_arrow([])

  def validate_arrow(options) do
    if Keyword.keyword?(options) do
      validated =
        options
        |> Aesthetics.canonicalize()
        |> NimbleOptions.validate(@arrow_schema)

      case validated do
        {:ok, arrow} -> {:ok, in_points(arrow)}
        {:error, %NimbleOptions.ValidationError{message: message}} -> {:error, message}
      end
    else
      {:error,
       "expected true or a keyword list of an arrowhead's options, got: #{inspect(options)}"}
    end
  end

  # An arrowhead's validated options as a map, its length in points.
  defp in_points(arrow) do
    arrow
    |> Map.new()
    |> Map.update!(:length, &Theme.points/1)
  end

  # NimbleOptions' check of an arrowhead's `length:`: any amount in one of its units, as grid
  # draws a negative one's arms past its tip; `validate_arrow/1` works it out in points.
  @doc false
  @spec validate_arrow_length(term()) :: {:ok, {number(), atom()}} | {:error, String.t()}
  def validate_arrow_length({amount, unit} = length)
      when is_number(amount) and unit in @arrow_units,
      do: {:ok, length}

  def validate_arrow_length(length) do
    {:error,
     "expected {amount, unit}, an amount with a unit of #{inspect(@arrow_units)}, " <>
       "got: #{inspect(length)}"}
  end

  # NimbleOptions' check of a rug's `sides:`: a list of the panel's sides, each given once, as
  # ggplot2 draws a side its `sides` names twice once; none draws no rug, as R's `""` draws none.
  @doc false
  @spec validate_rug_sides(term()) :: {:ok, [atom()]} | {:error, String.t()}
  def validate_rug_sides(sides) when is_list(sides) do
    if Enum.all?(sides, fn side -> side in @rug_sides end) and Enum.uniq(sides) == sides,
      do: {:ok, sides},
      else: rug_sides_error(sides)
  end

  def validate_rug_sides(sides), do: rug_sides_error(sides)

  defp rug_sides_error(sides) do
    {:error,
     "expected a list of the sides #{inspect(@rug_sides)}, each given once, got: " <>
       inspect(sides)}
  end

  # NimbleOptions' check of a rug's `length:`: any amount, as grid draws a negative one's lines
  # out from the edge, a share of the panel kept as a float and any other worked out in points as
  # the theme works one out.
  @doc false
  @spec validate_rug_length(term()) :: {:ok, {float(), :npc | :points}} | {:error, String.t()}
  def validate_rug_length({amount, :npc}) when is_number(amount), do: {:ok, {amount / 1, :npc}}

  def validate_rug_length({amount, unit} = length)
      when is_number(amount) and unit in @arrow_units,
      do: {:ok, {Theme.points(length), :points}}

  def validate_rug_length(length) do
    {:error,
     "expected {amount, unit}, an amount with a unit of #{inspect(@rug_length_units)}, " <>
       "got: #{inspect(length)}"}
  end

  # NimbleOptions' check of a colour a mark may take from its own, `:color`: a closed arrowhead's
  # `fill:`, the line's colour, and a label's `border_color:` and `text_color:`, the label's; or a
  # colour, resolved as `validate_color/1` resolves one.
  @doc false
  @spec validate_own_color(term()) :: {:ok, String.t() | :none | :color} | {:error, String.t()}
  def validate_own_color(:color), do: {:ok, :color}
  def validate_own_color(color), do: validate_color(color)

  # NimbleOptions' check of a label's `label_padding:`: a margin as a theme's is given, one length
  # for every side or a keyword list of sides, each held as `validate_label_r/1` holds a length.
  @doc false
  @spec validate_label_padding(term()) ::
          {:ok, %{atom() => {float(), :points | :lines}}} | {:error, String.t()}
  def validate_label_padding(padding) do
    with {:ok, sides} <- validate_theme_margin(padding, :root),
         do: {:ok, Map.new(sides, fn {side, measure} -> {side, label_measure(measure)} end)}
  end

  # NimbleOptions' check of a label's `label_r:`: a length as a theme's is given, a number of
  # ggplot2's points or `{amount, unit}`, held in points as the theme works one out, or in lines,
  # which the geom works out in the label's own font, as grid works out a label's `"lines"`.
  @doc false
  @spec validate_label_r(term()) :: {:ok, {float(), :points | :lines}} | {:error, String.t()}
  def validate_label_r(radius) do
    with {:ok, measure} <- validate_theme_length(radius, :root),
         do: {:ok, label_measure(measure)}
  end

  defp label_measure({amount, :lines}), do: {amount / 1, :lines}
  defp label_measure(measure), do: {Theme.points(measure), :points}

  # NimbleOptions' check of a `binwidth:` option: a number above 0, kept as a float, as R keeps a
  # double.
  @doc false
  @spec validate_binwidth(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_binwidth(width) when is_number(width) and width > 0, do: {:ok, width / 1}

  def validate_binwidth(width),
    do: {:error, "expected a bin width, a number above 0, got: #{inspect(width)}"}

  # NimbleOptions' check of a hexagon layer's `bins:`: a whole number above 0 for both axes, or a
  # pair of them, x's first, held as the pair.
  @doc false
  @spec validate_hex_bins(term()) ::
          {:ok, {pos_integer(), pos_integer()}} | {:error, String.t()}
  def validate_hex_bins(bins) when is_integer(bins) and bins > 0, do: {:ok, {bins, bins}}

  def validate_hex_bins({x_bins, y_bins} = bins)
      when is_integer(x_bins) and x_bins > 0 and is_integer(y_bins) and y_bins > 0,
      do: {:ok, bins}

  def validate_hex_bins(bins),
    do:
      {:error,
       "expected a number of bins, a whole number above 0, or {x_bins, y_bins}, got: " <>
         inspect(bins)}

  # NimbleOptions' check of a hexagon layer's `binwidth:`: a number above 0 for both axes, or a
  # pair of them, the width's first, held as a pair of floats, as R keeps doubles.
  @doc false
  @spec validate_hex_binwidth(term()) :: {:ok, {float(), float()}} | {:error, String.t()}
  def validate_hex_binwidth(width) when is_number(width) and width > 0,
    do: {:ok, {width / 1, width / 1}}

  def validate_hex_binwidth({width, height})
      when is_number(width) and width > 0 and is_number(height) and height > 0,
      do: {:ok, {width / 1, height / 1}}

  def validate_hex_binwidth(width),
    do:
      {:error,
       "expected a bin width, a number above 0, or {width, height}, got: " <> inspect(width)}

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

  # NimbleOptions' check of a facet's `labeller:`, kept as `Giggly.Facet.Labeller` reads it: one
  # labeller given alone labels both sides, every column at once, as ggplot2 hands a labeller each
  # side's table; a keyword list is ggplot2's `labeller()`, its sides `:none` when not given. A wrap
  # has one side of strips, so it takes `rows:` or `cols:` for them, not both.
  @doc false
  @spec validate_labeller(term(), :wrap | :grid) :: {:ok, map()} | {:error, String.t()}
  def validate_labeller(labellers, facet) when is_list(labellers) do
    cond do
      not Keyword.keyword?(labellers) ->
        {:error, labeller_error(labellers)}

      facet == :wrap and both_sides?(labellers) ->
        {:error,
         "a wrap's strips are one side, labelled by rows: or cols:, not both, got: " <>
           inspect(labellers)}

      true ->
        labellers
        |> NimbleOptions.validate(@labellers_schema)
        |> labellers_kept()
    end
  end

  def validate_labeller(labeller, _facet) do
    case labeller_entry(labeller, @labeller_alone_schemas) do
      {:ok, {kind, options}} ->
        {multi_line, kind_options} = Map.pop!(options, :multi_line)
        {:ok, alone({kind, kind_options}, multi_line)}

      {:ok, kept} ->
        {:ok, alone(kept, true)}

      error ->
        error
    end
  end

  defp both_sides?(labellers),
    do: Keyword.has_key?(labellers, :rows) and Keyword.has_key?(labellers, :cols)

  defp labellers_kept({:ok, validated}) do
    {:ok,
     %{
       rows: Keyword.get(validated, :rows, :none),
       cols: Keyword.get(validated, :cols, :none),
       columns: Keyword.fetch!(validated, :columns),
       default: Keyword.fetch!(validated, :default),
       multi_line: Keyword.fetch!(validated, :multi_line)
     }}
  end

  defp labellers_kept({:error, %NimbleOptions.ValidationError{message: message}}),
    do: {:error, message}

  defp alone(labeller, multi_line),
    do: %{
      rows: labeller,
      cols: labeller,
      columns: %{},
      default: {:value, %{}},
      multi_line: multi_line
    }

  # NimbleOptions' check of one labeller in a keyword list of them: a kind by name, or with its
  # options, which take no `multi_line:` there; a function of one label; or a map of labels.
  @doc false
  @spec validate_labeller_entry(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_labeller_entry(labeller), do: labeller_entry(labeller, @labeller_kind_schemas)

  # NimbleOptions' check of `columns:`: a keyword list or a map of a labeller for each column, by
  # a column reference, kept as a map by the column's name, a column named twice refused.
  @doc false
  @spec validate_column_labellers(term()) :: {:ok, map()} | {:error, String.t()}
  def validate_column_labellers(labellers) when is_list(labellers) or is_map(labellers) do
    Enum.reduce_while(labellers, {:ok, %{}}, fn
      {reference, labeller}, {:ok, kept} when is_binary(reference) or is_atom(reference) ->
        column_labeller(to_string(reference), labeller, kept)

      other, _kept ->
        {:halt, {:error, "expected a column and its labeller, got: #{inspect(other)}"}}
    end)
  end

  def validate_column_labellers(labellers),
    do:
      {:error,
       "expected a keyword list or a map of a labeller for each column, got: " <>
         inspect(labellers)}

  defp column_labeller(name, _labeller, kept) when is_map_key(kept, name),
    do: {:halt, {:error, "expected each column named once, got #{inspect(name)} twice"}}

  defp column_labeller(name, labeller, kept) do
    case validate_labeller_entry(labeller) do
      {:ok, entry} -> {:cont, {:ok, Map.put(kept, name, entry)}}
      {:error, message} -> {:halt, {:error, "the labeller of #{inspect(name)}: #{message}"}}
    end
  end

  defp labeller_entry(kind, schemas) when is_map_key(schemas, kind),
    do: labeller_entry({kind, []}, schemas)

  defp labeller_entry({kind, options} = labeller, schemas) when is_map_key(schemas, kind) do
    with true <- Keyword.keyword?(options) || {:error, labeller_error(labeller)},
         {:ok, validated} <- NimbleOptions.validate(options, Map.fetch!(schemas, kind)) do
      {:ok, {kind, Map.new(validated)}}
    else
      {:error, %NimbleOptions.ValidationError{message: message}} -> {:error, message}
      error -> error
    end
  end

  defp labeller_entry(function, _schemas) when is_function(function, 1), do: {:ok, function}

  defp labeller_entry(lookup, _schemas) when is_map(lookup) do
    if Enum.all?(lookup, fn {label, shown} -> is_binary(label) and is_binary(shown) end),
      do: {:ok, lookup},
      else: {:error, "expected a map of labels to the labels to show, got: #{inspect(lookup)}"}
  end

  defp labeller_entry(labeller, _schemas), do: {:error, labeller_error(labeller)}

  defp labeller_error(labeller),
    do:
      "expected :value, :both, :context or :wrap, one of them with its options, a function of " <>
        "one label, a map of labels, or a keyword list of labellers, got: #{inspect(labeller)}"
end
