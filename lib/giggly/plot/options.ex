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
  # theme's element tree, a guide's legend, a dodging position and a discrete scale's keys, and
  # nothing that runs a plot, which `GigglyCredo.Check.PlotRunsNothing` holds here as in
  # `Giggly.Plot`.

  alias Giggly.{Aesthetics, ColorOperations, ElementTree, Geom, Guide, Position, Scale, Theme}

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
                      orientation: [
                        type: {:in, [:x, :y]},
                        doc:
                          "The axis each band runs along, `:x` or `:y`; when not given, along " <>
                            "y where the layer is given neither `:ymin` nor `:ymax`, and along " <>
                            "x otherwise. A band along x needs `:ymin` or `:ymax`, and one along " <>
                            "y `:xmin` or `:xmax`."
                      ],
                      outline_type: [default: :both] ++ @outline_type_option
                    ] ++ @band_look_options ++ @line_style_options
                  )

  # `geom_area/3`'s options, validated at the call.
  @area_options NimbleOptions.new!(
                  [
                    data: @data_option,
                    position: [
                      type: {:in, [:stack, :identity]},
                      default: :stack,
                      doc:
                        "How areas that share an `x` are placed: piled on one another " <>
                          "(`:stack`), or each drawn where it is, overlapping (`:identity`)."
                    ],
                    orientation: [
                      type: {:in, [:x, :y]},
                      default: :x,
                      doc:
                        "The axis each area runs along: `:x`, from 0 up to its `y`, or `:y`, " <>
                          "from 0 across to its `x`, for areas that run up the panel."
                    ],
                    outline_type: [default: :upper] ++ @outline_type_option
                  ] ++ @band_look_options ++ @line_style_options
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
          "`base_family` when not given, the default sans-serif at its default. A label is " <>
          "measured as the default font measures it, and drawn at that width."
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
              ~s(families `"sans"`, `"serif"` and `"mono"`; `""` is the default sans-serif.)
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
            "How far apart its lines are, 0 or more, a share of 1.2 times its size: a title's " <>
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

  # Each `Giggly.Plot` function's schema, named after the function, or after the family of scale
  # functions whose options are checked against it.
  @doc false
  @spec facet_wrap() :: NimbleOptions.t()
  def facet_wrap, do: @facet_wrap_options

  @doc false
  @spec point() :: NimbleOptions.t()
  def point, do: @point_options

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
  @spec ribbon() :: NimbleOptions.t()
  def ribbon, do: @ribbon_options

  @doc false
  @spec area() :: NimbleOptions.t()
  def area, do: @area_options

  @doc false
  @spec path() :: NimbleOptions.t()
  def path, do: @path_options

  @doc false
  @spec line() :: NimbleOptions.t()
  def line, do: @line_options

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
  @spec rect() :: NimbleOptions.t()
  def rect, do: @rect_options

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

  @doc false
  @spec position_dodge2() :: NimbleOptions.t()
  def position_dodge2, do: @position_dodge2_options

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

  # The aesthetics an annotation draws row by row, which take a list of values.
  @doc false
  @spec per_annotation_aesthetics() :: [atom()]
  def per_annotation_aesthetics, do: @per_annotation_aesthetics

  # The geoms `annotate/3` draws with, by name.
  @doc false
  @spec annotation_geoms() :: [atom()]
  def annotation_geoms, do: @annotation_geoms

  # A date scale's options that choose what their plain twins choose.
  @doc false
  @spec date_twins() :: keyword(atom())
  def date_twins, do: @date_twins

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
  # R takes a negative one too and stacks a title's lines upward.
  @doc false
  @spec validate_lineheight(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_lineheight(height) when is_number(height) and height >= 0, do: {:ok, height / 1}

  def validate_lineheight(height),
    do: {:error, "expected a line height, a number 0 or more, got: #{inspect(height)}"}

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
  # `kind`: `:legend`, `:none` or a legend `guide_legend/1` made, for any; `:colorbar` for a
  # continuous colour or fill scale alone, as a colour bar shows a continuous scale's colours, so a
  # discrete scale's is refused, and an alpha, a shape, a size, a line type or a line width
  # scale's whatever its kind.
  @doc false
  @spec validate_guide(
          term(),
          :continuous | :discrete | :alpha | :shape | :size | :linetype | :linewidth
        ) ::
          {:ok, Giggly.Plot.guide()} | {:error, String.t()}
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
end
