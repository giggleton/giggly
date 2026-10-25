defmodule Giggly.StatTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Datasets, Stat}

  # Every golden here is ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the layer named, drawn with
  # `stat_boxplot(geom = "blank", position = "identity")`, which adds nothing to the stat's output
  # and moves nothing, printed to 17 significant digits; they move only with ggplot2's
  # `stat_boxplot()` or R's `quantile()`. No geom draws a box yet, so each table is built here as
  # the stat is handed it: positions, a discrete one at its level's place, and the panel and group
  # of each row.
  describe "compute_layer/3 for box plots" do
    # Golden: `ggplot(mpg, aes(class, hwy))`.
    test "each box's quartiles, outliers, whiskers, notches, place and width are R's" do
      frame = mpg_frame(x: places(:class), y: column(:hwy), group: places(:class))

      boxes = Stat.compute_layer(box(), frame, axes([1], true, false))

      assert DataFrame.names(boxes) == [
               :ymin,
               :lower,
               :middle,
               :upper,
               :ymax,
               :outliers,
               :notchupper,
               :notchlower,
               :x,
               :width,
               :relvarwidth,
               :flipped_aes,
               :panel,
               :group
             ]

      assert columns(boxes, [:ymin, :lower, :middle, :upper, :ymax]) === [
               [23.0, 23.0, 23.0, 21.0, 15.0, 20.0, 14.0],
               [24.0, 26.0, 26.0, 22.0, 16.0, 24.5, 17.0],
               [25.0, 27.0, 27.0, 23.0, 17.0, 26.0, 17.5],
               [26.0, 29.0, 29.0, 24.0, 18.0, 30.5, 19.0],
               [26.0, 33.0, 32.0, 24.0, 20.0, 36.0, 22.0]
             ]

      assert DataFrame.pull(boxes, :outliers) === [
               [],
               [35, 37, 35, 44],
               [],
               [17],
               [12, 12, 12, 22],
               [44, 41],
               [12, 12, 25, 24, 27, 25, 26, 23]
             ]

      assert columns(boxes, [:notchupper, :notchlower, :relvarwidth]) === [
               [26.413194961779865, 27.691400059700019, 27.740263631351993, 23.952775848865734] ++
                 [17.550085392820005, 27.602412466965269, 17.901320401320604],
               [23.586805038220135, 26.308599940299981, 26.259736368648007, 22.047224151134266] ++
                 [16.449914607179995, 24.397587533034731, 17.098679598679396],
               [2.2360679774997898, 6.8556546004010439, 6.4031242374328485, 3.3166247903553998] ++
                 [5.7445626465380286, 5.9160797830996161, 7.8740078740118111]
             ]

      assert columns(boxes, [:x, :width, :flipped_aes, :panel, :group]) === [
               [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
               List.duplicate(0.75, 7),
               List.duplicate(false, 7),
               List.duplicate(1, 7),
               [1, 2, 3, 4, 5, 6, 7]
             ]

      assert DataFrame.dtypes(boxes).outliers == {:list, :integer}
    end

    # Golden: `ggplot(df, aes(x, y, group = g))` of x `c(1, 1, 1, 1, 1, 2, 2, 2, NA, Inf, 3, 3)`, y
    # `c(1, 2, 3, Inf, NA, 4, NaN, 5, 6, 7, Inf, -Inf)` and g `a` five times, `b` four, `c` once and
    # `d` twice.
    test "a row missing its x or y, or at an infinite one, is left out, as is a group of no rows" do
      frame =
        DataFrame.new(
          x: [1, 1, 1, 1, 1, 2, 2, 2, nil, :infinity, 3, 3],
          y: [1, 2, 3, :infinity, nil, 4, :nan, 5, 6, 7, :infinity, :neg_infinity],
          panel: List.duplicate(1, 12),
          group: [1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 4, 4]
        )

      boxes = Stat.compute_layer(box(), frame, axes([1], false, false))

      assert columns(boxes, [:ymin, :lower, :middle, :upper, :ymax, :outliers]) === [
               [1.0, 4.0],
               [1.5, 4.25],
               [2.0, 4.5],
               [2.5, 4.75],
               [3.0, 5.0],
               [[], []]
             ]

      assert columns(boxes, [:notchupper, :notchlower, :x, :width, :relvarwidth, :group]) === [
               [2.9122134253196088, 5.0586143571373725],
               [1.0877865746803912, 3.9413856428626275],
               [1.0, 2.0],
               [0.75, 0.75],
               [1.7320508075688772, 1.4142135623730951],
               [1, 2]
             ]
    end

    # Golden: `ggplot(df, aes(x, y)) + stat_boxplot(coef = 0)` of x `a` twice and `b` five times,
    # y `c(0, 10, 1, 2, 3, 4, 10)`.
    test "coef sets the fences, and a box whose every row is an outlier reaches its hinges" do
      frame =
        DataFrame.new(
          x: [1, 1, 2, 2, 2, 2, 2],
          y: [0.0, 10.0, 1.0, 2.0, 3.0, 4.0, 10.0],
          panel: List.duplicate(1, 7),
          group: [1, 1, 2, 2, 2, 2, 2]
        )

      boxes = Stat.compute_layer(%{box() | coef: 0}, frame, axes([1], true, false))

      assert columns(boxes, [:ymin, :lower, :middle, :upper, :ymax, :outliers]) === [
               [2.5, 2.0],
               [2.5, 2.0],
               [5.0, 3.0],
               [7.5, 4.0],
               [7.5, 4.0],
               [[0.0, 10.0], [1.0, 10.0]]
             ]

      assert columns(boxes, [:notchupper, :notchlower]) === [
               [10.586143571373725, 4.4131949617798671],
               [-0.58614357137372508, 1.5868050382201329]
             ]
    end

    # Golden: `ggplot(mpg, aes(displ, hwy, group = cyl))`; the layer's closest x spacing is
    # 0.09999999999999964.
    test "a box on a continuous x sits mid-range, 0.9 of its x range wide, or 0.75 of the spacing" do
      frame = mpg_frame(x: column(:displ), y: column(:hwy), group: places(:cyl))

      boxes = Stat.compute_layer(box(), frame, axes([1], false, false))

      assert columns(boxes, [:ymin, :lower, :middle, :upper, :ymax, :outliers]) === [
               [20.0, 28.75, 17.0, 12.0],
               [26.0, 28.75, 19.0, 16.0],
               [29.0, 29.0, 24.0, 17.0],
               [31.0, 29.0, 26.0, 19.0],
               [37.0, 29.0, 29.0, 23.0],
               [[44, 44, 41], [28], [], [26, 26, 25, 24, 25]]
             ]

      assert columns(boxes, [:x, :width, :relvarwidth, :flipped_aes]) === [
               [2.1500000000000004, 2.5, 3.3500000000000001, 5.5],
               [0.9900000000000001, 0.074999999999999734, 1.5300000000000002, 2.7000000000000002],
               [9.0, 2.0, 8.8881944173155887, 8.3666002653407556],
               [false, false, false, false]
             ]
    end

    # Golden: `ggplot(df, aes(x, y, group = g))` of x `c(0.2, 0.2, 10, 11)`, y `c(1, 2, 3, 4)` and
    # g `c("a", "a", "b", "b")`: the layer's spacing counting from zero is 0.2.
    test "a group of two x values is 0.9 of their range wide, and the spacing counts from zero" do
      frame =
        DataFrame.new(
          x: [0.2, 0.2, 10.0, 11.0],
          y: [1.0, 2.0, 3.0, 4.0],
          panel: [1, 1, 1, 1],
          group: [1, 1, 2, 2]
        )

      boxes = Stat.compute_layer(box(), frame, axes([1], false, false))

      assert columns(boxes, [:x, :width]) === [[0.2, 10.5], [0.15000000000000002, 0.9]]
    end

    # Golden: `ggplot(mpg, aes(y = hwy))` and `ggplot(mpg, aes(x = hwy))`.
    test "a layer mapping y alone is summarised at x 0, and one mapping x alone along x" do
      vertical = mpg_frame(y: column(:hwy), group: List.duplicate(-1, 234))
      horizontal = mpg_frame(x: column(:hwy), group: List.duplicate(-1, 234))

      upright = Stat.compute_layer(box(), vertical, axes([1], false, false))
      lying = Stat.compute_layer(box(), horizontal, axes([1], false, false))

      rest = [:outliers, :notchupper, :notchlower, :width, :relvarwidth]

      summary =
        [[12.0], [18.0], [24.0], [27.0], [37.0], [[44, 44, 41]], [24.929590480554992]] ++
          [[23.070409519445008], [0.75], [15.297058540778355]]

      assert columns(upright, [:ymin, :lower, :middle, :upper, :ymax] ++ rest) === summary
      assert columns(lying, [:xmin, :xlower, :xmiddle, :xupper, :xmax] ++ rest) === summary

      assert {columns(upright, [:x, :flipped_aes]), columns(lying, [:y, :flipped_aes])} ===
               {[[0.0], [false]], [[0.0], [true]]}
    end

    # Golden: `ggplot(mpg, aes(drv, hwy, colour = drv, fill = year)) + stat_boxplot(width = 0.5)`
    # and, with `mpg$w <- ifelse(mpg$drv == "4", 0.3, 0.8)`, `ggplot(mpg, aes(drv, hwy, width =
    # w)) + stat_boxplot(width = 0.5)`; R's `colour` is mapped, which comes after the stat here.
    test "the stat's width sets every box's, a mapped width each group's first, ahead of it" do
      drives = column(:drv)

      colored =
        mpg_frame(
          x: places(:drv),
          y: column(:hwy),
          color: drives,
          fill: column(:year),
          group: places(:drv)
        )

      widths = Enum.map(drives, fn drive -> if drive == "4", do: 0.3, else: 0.8 end)
      mapped = mpg_frame(x: places(:drv), y: column(:hwy), width: widths, group: places(:drv))

      set = Stat.compute_layer(%{box() | width: 0.5}, colored, axes([1], true, false))
      given = Stat.compute_layer(%{box() | width: 0.5}, mapped, axes([1], true, false))

      assert columns(set, [:width, :color, :notchupper, :notchlower]) === [
               [0.5, 0.5, 0.5],
               ["4", "f", "r"],
               [18.778410129749791, 28.460389498757344, 23.212],
               [17.221589870250209, 27.539610501242656, 18.788]
             ]

      assert :fill not in DataFrame.names(set)
      assert DataFrame.pull(given, :width) === [0.3, 0.8, 0.8]
    end

    # Golden: `ggplot(df, aes(x, y, width = w))` of x `c("a", "a", "b", "b")`, y `c(1, 2, 3, 4)` and
    # w `c(1L, 1L, NA, NA)`, then w `NA_real_`: R's widths are 1 and NA, then NA and NA.
    test "a mapped width of whole numbers or of missing values is each group's first" do
      whole = Stat.compute_layer(box(), width_frame([1, 1, nil, nil]), axes([1], true, false))

      missing =
        Stat.compute_layer(box(), width_frame([nil, nil, nil, nil]), axes([1], true, false))

      assert {DataFrame.pull(whole, :width), DataFrame.pull(missing, :width)} ===
               {[1, nil], [nil, nil]}
    end

    # Golden: `ggplot(mpg, aes(drv, hwy)) + facet_wrap(~year)`.
    test "each panel's boxes are summarised apart, panels first" do
      years = column(:year)
      panels = Enum.map(years, fn year -> if year == 1999, do: 1, else: 2 end)
      frame = mpg_frame(x: places(:drv), y: column(:hwy), group: places(:drv), panel: panels)

      boxes = Stat.compute_layer(box(), frame, axes([1, 2], true, false))

      assert columns(boxes, [:panel, :group, :lower, :middle, :upper, :outliers]) === [
               [1, 1, 1, 2, 2, 2],
               [1, 2, 3, 1, 2, 3],
               [16.0, 26.0, 17.0, 17.0, 26.0, 18.5],
               [17.0, 26.0, 21.0, 19.0, 29.0, 21.0],
               [20.0, 29.0, 24.0, 22.75, 31.0, 24.0],
               [[], [21, 35, 44, 44, 41], [], [], [17], []]
             ]

      assert DataFrame.pull(boxes, :relvarwidth) === [
               7.0,
               7.5498344352707498,
               3.3166247903553998,
               7.3484692283495345,
               7.0,
               3.7416573867739413
             ]
    end

    # Golden: `ggplot(mpg, aes(hwy, class))`, whose boxes are `aes(class, hwy)`'s lying down, and
    # `ggplot(mpg, aes(hwy, class, group = drv))`, whose groups each hold many of both.
    test "a box runs along the continuous axis where the other is discrete" do
      frame = mpg_frame(x: column(:hwy), y: places(:class), group: places(:class))
      by_drive = mpg_frame(x: column(:hwy), y: places(:class), group: places(:drv))

      boxes = Stat.compute_layer(box(), frame, axes([1], false, true))
      drive_boxes = Stat.compute_layer(box(), by_drive, axes([1], false, true))

      assert columns(drive_boxes, [:xmiddle, :y, :width, :flipped_aes]) === [
               [18.0, 28.0, 21.0],
               [4.5, 4.0, 4.0],
               [4.5, 3.6000000000000001, 5.4000000000000004],
               [true, true, true]
             ]

      assert columns(boxes, [:xlower, :xmiddle, :xupper, :y, :flipped_aes]) === [
               [24.0, 26.0, 26.0, 22.0, 16.0, 24.5, 17.0],
               [25.0, 27.0, 27.0, 23.0, 17.0, 26.0, 17.5],
               [26.0, 29.0, 29.0, 24.0, 18.0, 30.5, 19.0],
               [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
               List.duplicate(true, 7)
             ]
    end

    # Golden: `ggplot(mpg, aes(cyl, hwy, group = cyl))`, `ggplot(mpg, aes(hwy, cyl, group = cyl))`
    # and `ggplot(mpg, aes(displ, hwy))`, which R summarises along y and warns of; and `ggplot(df,
    # aes(x, y, group = g))` of x `c(1, 2, 3)`, y `c(5, 5, 6)` and g `c("a", "a", "b")`, whose
    # groups each hold one y, though the second holds one x too.
    test "on two continuous axes a box runs along the axis each group holds many values of" do
      upright = mpg_frame(x: column(:cyl), y: column(:hwy), group: places(:cyl))
      lying = mpg_frame(x: column(:hwy), y: column(:cyl), group: places(:cyl))
      undecided = mpg_frame(x: column(:displ), y: column(:hwy), group: List.duplicate(-1, 234))

      continuous = axes([1], false, false)
      upright_boxes = Stat.compute_layer(box(), upright, continuous)
      lying_boxes = Stat.compute_layer(box(), lying, continuous)
      undecided_boxes = Stat.compute_layer(box(), undecided, continuous)

      assert columns(upright_boxes, [:middle, :x, :flipped_aes]) === [
               [29.0, 29.0, 24.0, 17.0],
               [4.0, 5.0, 6.0, 8.0],
               List.duplicate(false, 4)
             ]

      assert columns(lying_boxes, [:xmiddle, :y, :flipped_aes]) === [
               [29.0, 29.0, 24.0, 17.0],
               [4.0, 5.0, 6.0, 8.0],
               List.duplicate(true, 4)
             ]

      one_y =
        DataFrame.new(x: [1.0, 2.0, 3.0], y: [5.0, 5.0, 6.0], panel: [1, 1, 1], group: [1, 1, 2])

      assert columns(Stat.compute_layer(box(), one_y, continuous), [:xmiddle, :y, :flipped_aes]) ===
               [[1.5, 3.0], [5.0, 6.0], [true, true]]

      assert columns(undecided_boxes, [:middle, :x, :width, :flipped_aes]) === [
               [24.0],
               [4.2999999999999998],
               [4.8600000000000003],
               [false]
             ]
    end

    # Golden: `ggplot(mpg, aes(class, hwy)) + stat_boxplot(orientation = "y")`, which summarises
    # each class's single position along x and spans its hwy values across y.
    test "an orientation names the axis the boxes run along, whatever the axes" do
      frame = mpg_frame(x: places(:class), y: column(:hwy), group: places(:class))

      boxes = Stat.compute_layer(%{box() | orientation: :y}, frame, axes([1], true, false))

      assert columns(boxes, [:xmiddle, :y, :width, :x, :flipped_aes]) === [
               [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
               [24.5, 33.5, 27.5, 20.5, 17.0, 32.0, 19.5],
               [2.7000000000000002, 18.900000000000002, 8.0999999999999996, 6.2999999999999998] ++
                 [9.0, 21.600000000000001, 13.5],
               [1, 2, 3, 4, 5, 6, 7],
               List.duplicate(true, 7)
             ]

      upright = Stat.compute_layer(%{box() | orientation: :x}, frame, axes([1], true, false))

      assert DataFrame.pull(upright, :flipped_aes) === List.duplicate(false, 7)
    end

    test "a width that is not a number is refused, naming its type" do
      frame =
        DataFrame.new(x: [1], y: [1.0], width: ["wide"], panel: [1], group: [1])

      error =
        assert_raise ArgumentError, fn ->
          Stat.compute_layer(box(), frame, axes([1], true, false))
        end

      assert error.message =~ "a width must be a number"
      assert error.message =~ ":string"
    end

    test "no aesthetic takes a computed column by default" do
      assert Stat.default_mapping(box()) == %{}
    end
  end

  # Every golden here is ggplot2 4.0.3's `layer_data()` in R 4.6.1 for
  # `geom_area(position = "identity")` of the table named, whose x, y and `align_padding` are the
  # stat's, printed to 17 significant digits; each table is built here as the stat is handed it.
  describe "compute_layer/3 for aligning" do
    # Golden: `layer_data()` for x 3, 1 and 2 at y 3, 1 and 4 in group a, and x 1, 2 and 3 at y 2 in
    # group b, with `geom_area(position = "identity")`: a group's rows out of order along x are
    # read in order, as R's `approxfun()` sorts them.
    test "a group's rows are read in order along x, whatever order they come in" do
      frame = area_frame(x: [3, 1, 2, 1, 2, 3], y: [3, 1, 4, 2, 2, 2], group: [1, 1, 1, 2, 2, 2])

      aligned = Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{})

      assert DataFrame.pull(aligned, :y) === [
               0.0,
               1.0,
               1.006,
               3.9939999999999998,
               4.0,
               3.9980000000000002,
               3.0019999999999998,
               3.0,
               0.0,
               0.0,
               2.0,
               2.0,
               2.0,
               2.0,
               2.0,
               2.0,
               2.0,
               0.0
             ]
    end

    # Golden: `ggplot(crossing, aes(x, y, fill = g))`, `a` at y 1 and `b` from -1 to 1 at x 1 and
    # 3, so `b` crosses zero at 2 and each place is also 0.002 either side.
    test "each group is interpolated at every place and crossing, padded with 0 at each end" do
      frame = area_frame(x: [1, 3, 1, 3], y: [1, 1, -1, 1], group: [1, 1, 2, 2])

      aligned = Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{})

      places = [
        0.998,
        1.0,
        1.002,
        1.998,
        2.0,
        2.0019999999999998,
        2.9980000000000002,
        3.0,
        3.0019999999999998
      ]

      assert DataFrame.pull(aligned, :x) == places ++ places

      assert DataFrame.pull(aligned, :y) ==
               [0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0] ++
                 [0.0, -1.0, -0.998, -0.0020000000000000018, 0.0, 0.0019999999999997797] ++
                 [0.99800000000000022, 1.0, 0.0]

      padding = [true, false, false, false, false, false, false, false, true]
      assert DataFrame.pull(aligned, :align_padding) == padding ++ padding
      assert DataFrame.pull(aligned, :group) == List.duplicate(1, 9) ++ List.duplicate(2, 9)
      flipped = DataFrame.pull(aligned, :flipped_aes)
      assert Enum.uniq(flipped) == [false]
      assert [:x, :y | _rest] = DataFrame.names(aligned)
    end

    # Golden: `ggplot(dupes, aes(x, y, fill = g))`: `a` holds three rows at x 2, out of order, and
    # `b` a missing and an infinite x.
    test "a row missing or infinite is left out, and the rows sharing an x stand in as two" do
      frame =
        area_frame(
          x: [3, 1, 2, 2, 2, 1, 3, nil, :infinity],
          y: [1, 2, 3, 0.5, 4, 2, 2, 5, 1],
          group: [1, 1, 1, 1, 1, 2, 2, 2, 2]
        )

      aligned = Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{})

      assert DataFrame.pull(aligned, :y) ==
               [0.0, 2.0, 2.0020040080160322, 3.0, 4.0] ++
                 [3.9940000000000007, 1.0059999999999993, 1.0, 0.0] ++
                 [0.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 0.0]
    end

    # Golden: `ggplot(small, aes(y, x, fill = g)) + geom_area(orientation = "y", position =
    # "identity")`, `small` holding `a` at x 1 and 2 and `b` at x 1 and 3.
    test "along y, the groups are aligned up the y positions, y leading the columns" do
      frame = area_frame(x: [1, 3, 2, 2], y: [1, 2, 1, 3], group: [1, 1, 2, 2])

      aligned = Stat.compute_layer(%Stat.Align{orientation: :y}, frame, %{})

      assert DataFrame.pull(aligned, :y) ==
               [0.998, 1.0, 1.002, 1.998, 2.0, 2.0019999999999998] ++
                 [0.998, 1.0, 1.002, 1.998, 2.0, 2.0019999999999998, 2.9980000000000002] ++
                 [3.0, 3.0019999999999998]

      assert DataFrame.pull(aligned, :x) ==
               [0.0, 1.0, 1.004, 2.996, 3.0, 0.0, 0.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 0.0]

      flipped = DataFrame.pull(aligned, :flipped_aes)
      assert Enum.uniq(flipped) == [true]
      assert [:y, :x | _rest] = DataFrame.names(aligned)
    end

    # Golden: `ggplot(d, aes(x, y)) + geom_area(aes(fill = g), position = "identity") +
    # facet_wrap(~p)`, panel `one` holding one group and panel `two` `a` at x 1 and 2 and `b`
    # twice at x 3; the columns keep the first panel's order, as R binds the panels' tables.
    test "a panel of one group keeps its rows, and a group of one x is left out" do
      frame =
        area_frame(
          x: [1, 2, 3, 1, 2, 3, 3],
          y: [1, 2, 1, 1, 2, 3, 4],
          group: [1, 1, 1, 1, 1, 2, 2],
          panel: [1, 1, 1, 2, 2, 2, 2]
        )

      aligned = Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{})

      assert DataFrame.pull(aligned, :x) == [1, 2, 3, 0.998, 1.0, 1.002, 1.998, 2.0, 2.002]
      assert DataFrame.pull(aligned, :y) == [1, 2, 1, 0.0, 1.0, 1.002, 1.998, 2.0, 0.0]
      assert DataFrame.pull(aligned, :panel) == [1, 1, 1, 2, 2, 2, 2, 2, 2]
      groups = DataFrame.pull(aligned, :group)
      assert Enum.uniq(groups) == [1]

      assert DataFrame.pull(aligned, :align_padding) ==
               [nil, nil, nil, true, false, false, false, false, true]

      assert [:fill, :x, :y | _rest] = DataFrame.names(aligned)
    end

    test "a panel of one group, in every panel, leaves the table as it is" do
      frame = area_frame(x: [1, 2], y: [1, 2], group: [1, 1])

      assert Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{}) == frame
    end

    # Golden: `ggplot(threshold, aes(x, y, group = g)) + geom_area(position = "identity")`, `b`
    # rising from 0.5 to 2: a group that stays above zero crosses nothing, so the places are the
    # rows' x alone, 0.01 either side.
    test "a group that stays on one side of zero adds no place" do
      frame = area_frame(x: [0, 10, 4, 6], y: [5, 5, 0.5, 2], group: [1, 1, 2, 2])

      aligned = Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{})

      assert DataFrame.pull(aligned, :x) ==
               [-0.01, 0.0, 0.01, 3.9900000000000002, 4.0, 4.0099999999999998] ++
                 [5.9900000000000002, 6.0, 6.0099999999999998, 9.9900000000000002, 10.0] ++
                 [10.01, 3.9900000000000002, 4.0, 4.0099999999999998, 5.9900000000000002] ++
                 [6.0, 6.0099999999999998]
    end

    # Golden: `ggplot(rounding, aes(x, y, group = g)) + geom_area(position = "identity")`, `b`
    # crossing zero between (2, -0.7) and (3.4, 2.8): R's `-y0 * (x1 - x0) / (y1 - y0) + x0` puts it
    # at 2.28, where the same line worked from its other end gives 2.2800000000000002.
    test "a crossing is worked out from the row before it, in R's order" do
      frame = area_frame(x: [2, 3.4, 2, 3.4], y: [1, 1, -0.7, 2.8], group: [1, 1, 2, 2])

      aligned = Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{})

      places =
        [1.9985999999999999, 2.0, 2.0013999999999998, 2.2786, 2.2799999999999998] ++
          [2.2813999999999997, 3.3986000000000001, 3.3999999999999999, 3.4013999999999998]

      assert DataFrame.pull(aligned, :x) == places ++ places
    end

    # Golden: `ggplot(gap, aes(x, y, group = g)) + geom_area(position = "identity")`, places at 0,
    # 1000 and 1000.3: a thousandth of their range, 1.0003, is more than a third of their smallest
    # gap, so each place is that third, about 0.1, either side.
    test "the places' spread is a third of their smallest gap where that is less" do
      frame = area_frame(x: [0, 1000.3, 1000, 1000.3], y: [1, 1, 2, 2], group: [1, 1, 2, 2])

      aligned = Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{})

      assert DataFrame.pull(aligned, :x) ==
               [-0.099999999999984837, 0.0, 0.099999999999984837, 999.89999999999998, 1000.0] ++
                 [1000.1, 1000.1999999999999, 1000.3, 1000.4, 999.89999999999998, 1000.0] ++
                 [1000.1, 1000.1999999999999, 1000.3, 1000.4]
    end

    # Golden: `ggplot(single, aes(x, y, group = g)) + geom_area(position = "identity")`, both groups
    # at x 1 alone: R has no rows.
    test "a panel whose groups share one x aligns to nothing" do
      frame = area_frame(x: [1, 1, 1, 1], y: [1, 2, 3, 4], group: [1, 1, 2, 2])

      aligned = Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{})

      assert DataFrame.row_count(aligned) == 0
    end

    test "the panels and their groups come in order, whatever the rows' order" do
      frame =
        area_frame(
          x: [1, 2, 1, 2, 1, 2, 1, 2],
          y: [1, 1, 2, 2, 3, 3, 4, 4],
          group: [2, 2, 1, 1, 2, 2, 1, 1],
          panel: [2, 2, 2, 2, 1, 1, 1, 1]
        )

      aligned = Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{})

      assert {DataFrame.pull(aligned, :panel), DataFrame.pull(aligned, :group)} ==
               {List.duplicate(1, 12) ++ List.duplicate(2, 12),
                List.duplicate(1, 6) ++
                  List.duplicate(2, 6) ++ List.duplicate(1, 6) ++ List.duplicate(2, 6)}
    end

    # Golden: `ggplot(d, aes(x, y, group = g, colour = c)) + geom_area(position = "identity") +
    # scale_colour_identity()`, `g` 2 holding rows at x 1 and 2 and `g` 1 at x 2, 1 and 1: each
    # group's rows carry its first row's other columns, `#111111`, and, where some share an x, the
    # first at the lowest, `#444444`, not the first in the data.
    test "every other column is the group's first row's, and aligning computes nothing" do
      frame =
        [x: [1, 2, 2, 1, 1], y: [1, 2, 3, 4, 5], group: [2, 2, 1, 1, 1]]
        |> area_frame()
        |> DataFrame.put(:fill, ["#111111", "#222222", "#333333", "#444444", "#555555"])

      aligned = Stat.compute_layer(%Stat.Align{orientation: :x}, frame, %{})

      assert DataFrame.pull(aligned, :fill) ==
               List.duplicate("#444444", 7) ++ List.duplicate("#111111", 6)

      assert DataFrame.pull(aligned, :x) ==
               [0.998, 0.999, 1.0, 1.001, 1.999, 2.0, 2.001] ++
                 [0.999, 1.0, 1.001, 1.999, 2.0, 2.001]

      assert Stat.default_mapping(%Stat.Align{orientation: :x}) == %{}
    end
  end

  # Every golden here is ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_smooth(method = lm,
  # formula = y ~ x)` over the table named, with the options given, printed to 17 significant
  # digits; a band ggplot2's position scale has mapped from NaN to `NA` is NaN as the stat hands it
  # on. Each table is built here as the stat is handed it, its rows in one panel, and the curves'
  # values held to R's within 1e-12 of the largest magnitude the group's column holds, their x to
  # the last digit (design-log §4, the entry beginning "A stat's values reached by another route").
  describe "compute_layer/3 for smooths" do
    # Golden: `ggplot(mpg, aes(displ, hwy))`, `n = 5`, and `level = 0.99`.
    test "a straight line by least squares, its standard error and band, R's" do
      frame = mpg_frame(x: column(:displ), y: column(:hwy), group: List.duplicate(-1, 234))

      curve = fit(frame, n: 5)

      assert DataFrame.names(curve) == [:x, :y, :ymin, :ymax, :se, :flipped_aes, :panel, :group]
      assert DataFrame.pull(curve, :x) === [1.6, 2.95, 4.300000000000001, 5.65, 7.0]

      assert_near(curve, :y, [
        30.048708961974306,
        25.282414073646258,
        20.516119185318214,
        15.74982429699017,
        10.983529408662125
      ])

      assert_near(curve, :ymin, [
        29.177681481115854,
        24.749409315380124,
        19.928881322448479,
        14.779797710668415,
        9.5439447865978266
      ])

      assert_near(curve, :ymax, [
        30.919736442832757,
        25.815418831912393,
        21.103357048187949,
        16.719850883311924,
        12.423114030726424
      ])

      assert_near(curve, :se, [
        0.44209163598339901,
        0.27052756743860312,
        0.29805368167214519,
        0.49233881814122216,
        0.73066388224365719
      ])

      assert DataFrame.pull(curve, :flipped_aes) == List.duplicate(false, 5)
      assert DataFrame.pull(curve, :group) == List.duplicate(-1, 5)

      wider = fit(frame, n: 5, level: 0.99)

      assert_near(wider, :ymin, [
        28.900514560883146,
        24.579803544535324,
        19.742018205643912,
        14.471128595878064,
        9.0858590833560804
      ])

      assert_near(wider, :ymax, [
        31.196903363065466,
        25.985024602757193,
        21.290220164992515,
        17.028519998102276,
        12.88119973396817
      ])
    end

    # Golden: `ggplot(mpg, aes(displ, hwy, colour = drv))`, `n = 3`.
    test "each group is fitted over its own x, its constant columns carried" do
      drives = column(:drv)

      frame =
        DataFrame.new(
          x: column(:displ),
          y: column(:hwy),
          color: drives,
          panel: List.duplicate(1, 234),
          group: Enum.map(drives, fn drive -> %{"4" => 1, "f" => 2, "r" => 3}[drive] end)
        )

      curve = fit(frame, n: 3)

      assert DataFrame.names(curve) ==
               [:x, :y, :ymin, :ymax, :se, :flipped_aes, :color, :panel, :group]

      assert DataFrame.pull(curve, :x) ===
               [1.8, 4.15, 6.5, 1.6, 3.45, 5.3, 3.8, 5.4, 7.0]

      assert DataFrame.pull(curve, :color) == ["4", "4", "4", "f", "f", "f", "r", "r", "r"]

      assert_near(curve, :y, [
        25.501837825142381,
        18.737395044330924,
        11.972952263519463,
        31.61361558658114,
        24.948457943583477,
        18.283300300585815,
        22.270651443922095,
        20.793149764942914,
        19.315648085963733
      ])

      assert_near(curve, :se, [
        0.52443516861157324,
        0.24247355656876632,
        0.582462543489639,
        0.55793905791605802,
        0.53277594598695344,
        1.3313504630657205,
        1.4759989024636737,
        0.76192951167722667,
        1.8497269496943667
      ])

      assert_near(curve, :ymin, [
        24.461499522127355,
        18.256392732768553,
        10.817503257938689,
        30.507201497242619,
        23.891943249483482,
        15.643182371425006,
        19.217315081370455,
        19.216978482008951,
        15.489196354281269
      ])
    end

    # Golden: `ggplot(mpg, aes(displ, hwy, weight = cyl))`, `n = 3`.
    test "a weight weighs each row in the fit" do
      frame =
        mpg_frame(
          x: column(:displ),
          y: column(:hwy),
          weight: column(:cyl),
          group: List.duplicate(-1, 234)
        )

      curve = fit(frame, n: 3)

      assert_near(curve, :y, [29.485343372486021, 20.5461007962069, 11.606858219927783])
      assert_near(curve, :ymin, [28.508819903604689, 20.01455244656032, 10.285913370947808])
      assert_near(curve, :se, [0.49563632310251754, 0.26978836450479377, 0.67044804229810806])
    end

    # Golden: five rows, weighted 1, 1, 0, 1, 1; 1, NaN, 1, 1, NA; and 1, 1e-300, 1, 1, 1. R's
    # `lm()` leaves out a row weighted 0 as it leaves out one missing its weight, but counts a
    # weight above 0, however small, in its degrees of freedom.
    test "a row weighted 0 or missing its weight is left out of the fit and its degrees of freedom" do
      zero_weighted = weighted_frame([1, 1, 0, 1, 1])
      zero = fit(zero_weighted, n: 3)

      assert DataFrame.pull(zero, :x) === [1.0, 3.0, 5.0]
      assert_near(zero, :y, [2.4949999999999997, 3.6749999999999998, 4.8549999999999995])
      assert_near(zero, :ymin, [-0.39327082063530394, 1.8837704767037238, 1.9667291793646955])
      assert_near(zero, :se, [0.67127676855377638, 0.41630817911734586, 0.67127676855377649])

      missing_weighted = weighted_frame([1, :nan, 1, 1, nil])
      missing = fit(missing_weighted, n: 3)

      assert_near(missing, :y, [1.785714285714286, 3.6428571428571428, 5.5])
      assert_near(missing, :ymax, [11.602758434175989, 9.7311294698820845, 17.97724535695577])

      tiny_weighted = weighted_frame([1, 1.0e-300, 1, 1, 1])
      tiny = fit(tiny_weighted, n: 3)

      assert_near(tiny, :y, [2.0457142857142854, 3.3828571428571426, 4.7199999999999998])
      assert_near(tiny, :ymin, [0.12499316408040206, 2.3128502681803118, 3.0855375008900978])
    end

    # A negative or infinite weight makes R's `lm()` fail, and a group of only zero weights leaves
    # it nothing to fit, so ggplot2 draws nothing for the group.
    test "a group with a negative or infinite weight, or every weight 0, is fitted nothing" do
      for weights <- [[1, -1, 1, 1, 1], [1, :infinity, 1, 1, 1], [0, 0, 0, 0, 0]] do
        frame = weighted_frame(weights)
        curve = fit(frame, n: 3)

        assert DataFrame.row_count(curve) == 0
      end
    end

    # Golden: rows at x 1, 2, 2, 2 and 3 weighted 0, 1, 2, 1 and 0: the weighted rows hold one x,
    # so R's `lm()` drops the slope and fits their weighted mean, 3.25, with two degrees of freedom.
    test "where the weighted rows hold one x the curve is flat at their weighted mean" do
      frame =
        DataFrame.new(
          x: [1.0, 2.0, 2.0, 2.0, 3.0],
          y: [1.0, 2.0, 3.0, 5.0, 4.0],
          weight: [0, 1, 2, 1, 0],
          panel: [1, 1, 1, 1, 1],
          group: [-1, -1, -1, -1, -1]
        )

      curve = fit(frame, n: 3)

      assert DataFrame.pull(curve, :x) === [1.0, 2.0, 3.0]
      assert DataFrame.pull(curve, :y) == [3.25, 3.25, 3.25]
      assert_near(curve, :se, List.duplicate(0.770551750371122, 3))
      assert_near(curve, :ymin, List.duplicate(-0.065416592147534036, 3))
      assert_near(curve, :ymax, List.duplicate(6.5654165921475336, 3))
    end

    # Golden: two rows, `(1, 1)` and `(2, 3)`, which the line meets exactly, leaving no degrees of
    # freedom; and `ggplot(g, aes(x, y, group = g, label = lab))`, `b`'s rows at one x and labelled
    # two ways, `a`'s and `c`'s labelled one.
    test "a group with no degrees of freedom has no band, and one holding one x has no curve" do
      frame =
        DataFrame.new(x: [1.0, 2.0], y: [1.0, 3.0], panel: [1, 1], group: [-1, -1])

      curve = fit(frame, n: 3)

      assert_near(curve, :y, [1.0000000000000009, 2.0000000000000009, 3.0000000000000009])
      assert DataFrame.pull(curve, :ymin) == [:nan, :nan, :nan]
      assert DataFrame.pull(curve, :ymax) == [:nan, :nan, :nan]
      assert DataFrame.pull(curve, :se) == [:nan, :nan, :nan]

      grouped =
        DataFrame.new(
          x: [1.0, 2.0, 3.0, 1.0, 1.0, 1.0, 2.0],
          y: [1.0, 3.0, 2.0, 1.0, 2.0, 3.0, 4.0],
          label: ["p", "p", "p", "q", "r", "s", "s"],
          panel: List.duplicate(1, 7),
          group: [1, 1, 1, 2, 2, 3, 3]
        )

      fitted = fit(grouped, n: 3)

      assert DataFrame.pull(fitted, :group) == [1, 1, 1, 3, 3, 3]
      assert DataFrame.pull(fitted, :label) == ["p", "p", "p", "s", "s", "s"]
      assert DataFrame.pull(fitted, :x) === [1.0, 2.0, 3.0, 1.0, 1.5, 2.0]

      assert_near(fitted, :se, [
        1.1180339887498949,
        0.70710678118654724,
        1.1180339887498942,
        :nan,
        :nan,
        :nan
      ])
    end

    # Golden: `ggplot(mpg, aes(displ, hwy))`, `n = 3`, `orientation = "y"`: displ fitted along hwy.
    test "along y, x is fitted to y and the columns are y's first" do
      frame = mpg_frame(x: column(:displ), y: column(:hwy), group: List.duplicate(-1, 234))

      curve = fit(frame, n: 3, orientation: :y)

      assert DataFrame.names(curve) == [:y, :x, :xmin, :xmax, :se, :flipped_aes, :panel, :group]
      assert DataFrame.pull(curve, :y) === [12.0, 28.0, 44.0]
      assert_near(curve, :x, [5.3731603964144945, 2.7139476492438277, 0.054734902073160896])
      assert_near(curve, :xmin, [5.1405923747444175, 2.5788242627289999, -0.33136040655595933])
      assert_near(curve, :se, [0.11804033677125192, 0.068582128941652887, 0.19596339999415183])
      assert DataFrame.pull(curve, :flipped_aes) == [true, true, true]
    end

    # Golden: `ggplot(mpg, aes(displ, hwy, colour = drv))`, `n = 3`, `fullrange = TRUE`, the x
    # axis's extent displ's range, 1.6 to 7; and along y, the y axis's extent 10 to 46, from
    # `ggplot(mpg, aes(hwy, displ)) + expand_limits(x = c(10, 46))` with `fullrange = TRUE`, the
    # same fit along x, since ggplot2's along y reads the x axis (design-log §4, the entry
    # beginning "A full-range smooth spans").
    test "with fullrange each curve spans the panel's axis it runs along" do
      drives = column(:drv)

      frame =
        mpg_frame(
          x: column(:displ),
          y: column(:hwy),
          group: Enum.map(drives, fn drive -> %{"4" => 1, "f" => 2, "r" => 3}[drive] end)
        )

      curve = fit(frame, n: 3, fullrange: true)

      span = [1.6, 4.300000000000001, 7.0]
      assert DataFrame.pull(curve, :x) === span ++ span ++ span

      assert_near(curve, :y, [
        26.077535083083781,
        18.305622100874871,
        10.533709118665964,
        31.61361558658114,
        21.886088215719681,
        12.158560844858229,
        24.30221625251847,
        21.8089321692411,
        19.315648085963733
      ])

      single = mpg_frame(x: column(:displ), y: column(:hwy), group: List.duplicate(-1, 234))

      along_y =
        fit(single, n: 3, fullrange: true, orientation: :y)

      assert DataFrame.pull(along_y, :y) === [10.0, 28.0, 46.0]
      assert_near(along_y, :x, [5.7055619898108283, 2.7139476492438277, -0.2776666913231729])
      assert_near(along_y, :xmin, [5.4404516142134751, 2.5788242627289999, -0.6985442587005366])
      assert_near(along_y, :xmax, [5.9706723654081815, 2.8490710357586555, 0.14321087605419081])
      assert_near(along_y, :se, [0.13455726970691714, 0.068582128941652887, 0.21361720083411376])
    end

    # Golden: `ggplot(mpg, aes(displ, hwy))`, `n = 3`, `se = FALSE`; and `aes(cty, hwy)`, cty's
    # whole numbers spaced as doubles.
    test "without se only the fitted values, and whole-number x spaced as floats" do
      frame = mpg_frame(x: column(:displ), y: column(:hwy), group: List.duplicate(-1, 234))

      curve = fit(frame, n: 3, se: false)

      assert DataFrame.names(curve) == [:x, :y, :flipped_aes, :panel, :group]
      assert_near(curve, :y, [30.048708961974306, 20.516119185318214, 10.983529408662125])

      city = mpg_frame(x: column(:cty), y: column(:hwy), group: List.duplicate(-1, 234))
      spaced = fit(city, n: 3)

      assert DataFrame.pull(spaced, :x) === [9.0, 22.0, 35.0]
      assert_near(spaced, :y, [12.929141592266197, 30.316064526646961, 47.702987461027725])
    end

    # Golden: `ggplot(mpg, aes(displ, hwy))` with `n = 1` and `n = 2`, R's `seq()` giving the low
    # end alone, then both ends.
    test "a curve of one place is at its group's least x, of two at both ends" do
      frame = mpg_frame(x: column(:displ), y: column(:hwy), group: List.duplicate(-1, 234))

      one = fit(frame, n: 1)
      two = fit(frame, n: 2)

      assert DataFrame.pull(one, :x) === [1.6]
      assert_near(one, :y, [30.048708961974306])
      assert DataFrame.pull(two, :x) === [1.6, 7.0]
      assert_near(two, :y, [30.048708961974306, 10.983529408662125])
    end

    test "a row missing or infinite in x or y is left out" do
      frame =
        DataFrame.new(
          x: [1.0, 2.0, 3.0, nil, :infinity, 4.0, 5.0],
          y: [2.0, 3.5, 3.0, 9.0, 9.0, :nan, :neg_infinity],
          panel: List.duplicate(1, 7),
          group: List.duplicate(-1, 7)
        )

      complete =
        DataFrame.new(
          x: [1.0, 2.0, 3.0],
          y: [2.0, 3.5, 3.0],
          panel: [1, 1, 1],
          group: [-1, -1, -1]
        )

      assert fit(frame, n: 3) ==
               fit(complete, n: 3)
    end

    # ggplot2 fits a smooth given no method by loess where the layer's largest group in any panel
    # has under 1,000 rows, every row counted, and by gam from 1,000.
    test "a smooth given no method is refused, naming the method ggplot2 would choose" do
      loess = unfitted([999])

      assert_raise ArgumentError,
                   ~r/largest group has 999 rows, so ggplot2 would fit it by loess/,
                   fn ->
                     fit(loess, method: :none)
                   end

      gam = unfitted([999, 1000])

      assert_raise ArgumentError,
                   ~r/largest group has 1000 rows, so ggplot2 would fit it by gam/,
                   fn ->
                     fit(gam, [method: :none], [1, 2])
                   end

      empty = unfitted([])

      assert_raise ArgumentError,
                   ~r/largest group has 0 rows, so ggplot2 would fit it by loess/,
                   fn ->
                     fit(empty, method: :none)
                   end
    end

    test "names what an after_stat can read, each in either orientation, and the weight it consumes" do
      assert Stat.Smooth.computed_variables() == [:se, :x, :xmax, :xmin, :y, :ymax, :ymin]
      assert Stat.Smooth.dropped_aesthetics() == [:weight]
    end

    # A plot's mapping may carry a band's columns into a smooth layer, unused; the stat's own take
    # their place, as ggplot2 binds its computed columns over those its rows held.
    test "a band's columns the rows already hold give way to the stat's own" do
      frame =
        DataFrame.new(
          x: [1.0, 2.0, 3.0],
          y: [2.0, 3.5, 3.0],
          ymin: [0.0, 0.0, 0.0],
          ymax: [9.0, 9.0, 9.0],
          se: [5.0, 5.0, 5.0],
          flipped_aes: [true, true, true],
          panel: [1, 1, 1],
          group: [-1, -1, -1]
        )

      plain = DataFrame.select(frame, x: :x, y: :y, panel: :panel, group: :group)

      assert fit(frame, n: 3) == fit(plain, n: 3)
    end

    # Golden: `ggplot(mpg, aes(cty, hwy))` with `n = 2`, R's x doubles, and a full range over an
    # axis whose ends are whole numbers.
    test "whole-number ends are spaced as floats, a curve of two places too" do
      city = mpg_frame(x: column(:cty), y: column(:hwy), group: List.duplicate(-1, 234))

      spaced = fit(city, n: 2)
      assert DataFrame.pull(spaced, :x) === [9.0, 35.0]

      axis = %{limits: {2, 7}, discrete: false, transform: fn values -> values end}
      stat = smooth(n: 2, fullrange: true)
      whole = Stat.compute_layer(stat, city, %{1 => %{x: axis, y: axis}})

      assert DataFrame.pull(whole, :x) === [2.0, 7.0]
    end

    test "a carried factor keeps its levels" do
      frame =
        DataFrame.new([
          {:x, [1.0, 2.0, 3.0, 1.0, 2.0, 3.0]},
          {:y, [1.0, 3.0, 2.0, 2.0, 1.0, 4.0]},
          {:color, ["r", "r", "r", "f", "f", "f"],
           {:category, levels: ["r", "f"], ordered: false}},
          {:panel, List.duplicate(1, 6)},
          {:group, [1, 1, 1, 2, 2, 2]}
        ])

      curve = fit(frame, n: 2)

      assert DataFrame.pull(curve, :color) == ["r", "r", "f", "f"]
      assert DataFrame.category(curve, :color) == {:category, levels: ["r", "f"], ordered: false}
    end

    # Golden: R 4.6.1's `lm()` of two rows, `(5.7, 2.9)` and `(1.3, 0.8)`, leaves residuals of
    # exactly 0 and no degrees of freedom, so its standard error is NaN, where the frame's sums
    # leave a residual a hair from 0.
    test "a fit of no degrees of freedom has a NaN error whatever its sums leave of the residuals" do
      frame = DataFrame.new(x: [5.7, 1.3], y: [2.9, 0.8], panel: [1, 1], group: [-1, -1])

      curve = fit(frame, n: 3)

      assert DataFrame.pull(curve, :se) == [:nan, :nan, :nan]
      assert DataFrame.pull(curve, :ymin) == [:nan, :nan, :nan]
      assert_near(curve, :y, [0.79999999999999982, 1.8499999999999996, 2.8999999999999995])
    end

    test "a weight that is not a number is refused" do
      frame = DataFrame.new(x: [1.0], y: [1.0], weight: ["a"], panel: [1], group: [-1])

      assert_raise ArgumentError, ~r/weight is a :string column/, fn ->
        fit(frame, n: 3)
      end
    end
  end

  # A layer's rows, a group of each count's rows in a panel of its own, none of them placed.
  defp unfitted(counts) do
    panels =
      counts
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {count, panel} -> List.duplicate(panel, count) end)

    rows = length(panels)

    DataFrame.new(
      x: List.duplicate(nil, rows),
      y: List.duplicate(1.0, rows),
      panel: panels,
      group: List.duplicate(-1, rows)
    )
  end

  # Every golden here is ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_density()` with the
  # options named, printed to 17 significant digits; the layer's places are R's to the last digit
  # and every other value R's within 1e-12 of the largest magnitude R's column holds, as the
  # estimate's convolution is Nx's, not R's (design-log §4, the entry beginning "A stat's values
  # reached by another route"). Each table is built here as the stat is handed it, its axis's
  # extent the column's, as the scale gives it.
  describe "compute_layer/3 for densities" do
    # Golden: `ggplot(mpg, aes(hwy))` with `geom_density(n = 5)`.
    test "a kernel density estimate across the panel's axis, R's density()" do
      curve = estimate(hwy_frame(), n: 5)

      assert DataFrame.names(curve) ==
               [
                 :x,
                 :density,
                 :scaled,
                 :ndensity,
                 :count,
                 :wdensity,
                 :n,
                 :flipped_aes,
                 :panel,
                 :group
               ]

      assert DataFrame.pull(curve, :x) === [12.0, 20.0, 28.0, 36.0, 44.0]

      assert_near(curve, :density, [
        0.0093474699133166347,
        0.042495683230208497,
        0.061011211809190169,
        0.0058194146438834563,
        0.0021303835656945004
      ])

      assert_near(curve, :scaled, [
        0.15320905184690362,
        0.69652252381270252,
        1.0,
        0.095382708707432581,
        0.03491790283328873
      ])

      assert_near(curve, :ndensity, [
        0.15320905184690362,
        0.69652252381270252,
        1.0,
        0.095382708707432581,
        0.03491790283328873
      ])

      assert_near(curve, :count, [
        2.1873079597160925,
        9.9439898758687892,
        14.276623563350499,
        1.3617430266687287,
        0.4985097543725131
      ])

      assert_near(curve, :wdensity, [
        2.1873079597160925,
        9.9439898758687892,
        14.276623563350499,
        1.3617430266687287,
        0.4985097543725131
      ])

      assert DataFrame.pull(curve, :n) === [234, 234, 234, 234, 234]
      assert DataFrame.pull(curve, :flipped_aes) == List.duplicate(false, 5)
    end

    # Golden: `aes(hwy, colour = drv)` with `geom_density(n = 3, trim = TRUE)`.
    test "trimmed, each group's curve spans its own rows, its constant columns carried" do
      drives = column(:drv)

      frame =
        DataFrame.new(
          x: column(:hwy),
          color: drives,
          panel: List.duplicate(1, 234),
          group: Enum.map(drives, fn drive -> %{"4" => 1, "f" => 2, "r" => 3}[drive] end)
        )

      curve = estimate(frame, n: 3, trim: true)

      assert DataFrame.names(curve) == [
               :x,
               :density,
               :scaled,
               :ndensity,
               :count,
               :wdensity,
               :n,
               :flipped_aes,
               :color,
               :panel,
               :group
             ]

      assert DataFrame.pull(curve, :x) === [12.0, 20.0, 28.0, 17.0, 30.5, 44.0, 15.0, 20.5, 26.0]

      assert_near(curve, :density, [
        0.018756264653155847,
        0.067707446243681121,
        0.019685004730588509,
        0.0047392001781116824,
        0.063740471487487044,
        0.0094821463652452771,
        0.045231355553014323,
        0.070632082114653674,
        0.067514684782176274
      ])

      assert DataFrame.pull(curve, :n) === [103, 103, 103, 106, 106, 106, 25, 25, 25]
      assert DataFrame.pull(curve, :color) == ["4", "4", "4", "f", "f", "f", "r", "r", "r"]
    end

    # Golden: `ggplot(mpg, aes(y = hwy))` with `geom_density(n = 3)`.
    test "along y, a density's places are its y" do
      frame =
        DataFrame.new(
          y: column(:hwy),
          panel: List.duplicate(1, 234),
          group: List.duplicate(-1, 234)
        )

      curve = estimate(frame, [n: 3], y: {12, 44})

      names = DataFrame.names(curve)

      assert Enum.take(names, 2) == [:y, :density]
      assert DataFrame.pull(curve, :y) === [12.0, 28.0, 44.0]

      assert_near(curve, :density, [
        0.0093474699133166347,
        0.061011211809190169,
        0.0021303835656945004
      ])

      assert DataFrame.pull(curve, :flipped_aes) == [true, true, true]
    end

    # Golden: `geom_density(n = 3)` with `bw = "nrd"`, `bw = 2, adjust = 0.5` and `adjust = 0.5`.
    test "the bandwidth is Scott's variation, or a number, times adjust" do
      frame = hwy_frame()

      assert_near(estimate(frame, n: 3, bandwidth: :nrd), :density, [
        0.010703054593875718,
        0.0594769157228573,
        0.0019081911116291537
      ])

      assert_near(
        estimate(frame, n: 3, bandwidth: 2.0, adjust: 0.5),
        :density,
        [0.0091777389352147819, 0.057902375821687106, 0.0034269815200093467]
      )

      assert_near(estimate(frame, n: 3, adjust: 0.5), :density, [
        0.0098624475627717458,
        0.056015751487052672,
        0.0037942645867074447
      ])
    end

    # Golden: `geom_density()` of x 1, 1, 1, 1 and 5, of interquartile range 0, with `n = 3`; of
    # 2, 2 and 2, of standard deviation 0 too, and of 0, 0 and 0, with `n = 2`.
    test "Silverman's rule falls back to the deviation, then the first x's magnitude, then 1" do
      spread = estimate(one_panel(x: [1.0, 1.0, 1.0, 1.0, 5.0]), [n: 3], x: {1, 5})
      assert DataFrame.pull(spread, :x) === [1.0, 3.0, 5.0]

      assert_near(spread, :density, [
        0.27368767872964633,
        0.078712368993667264,
        0.06914226247925695
      ])

      level = estimate(one_panel(x: [2.0, 2.0, 2.0]), [n: 2], x: {2, 2})
      assert DataFrame.pull(level, :x) === [2.0, 2.0]
      assert_near(level, :density, [0.27608016217533199, 0.27608016217533199])

      zero = estimate(one_panel(x: [0.0, 0.0, 0.0]), [n: 2], x: {0, 0})
      assert DataFrame.pull(zero, :x) === [0.0, 0.0]
      assert_near(zero, :density, [0.55216032435066398, 0.55216032435066398])
    end

    # Golden: `geom_density(n = 5, kernel = k)` for each of R's other six kernels.
    test "each kernel is R's, scaled so its standard deviation is the bandwidth" do
      frame = hwy_frame()

      for {kernel, expected} <- [
            epanechnikov: [
              0.0088260398714720342,
              0.043917264095601635,
              0.062105473251687998,
              0.0052049697347955727,
              0.0019460960903589183
            ],
            rectangular: [
              0.011651647613228242,
              0.055516673921852194,
              0.069224494643297205,
              0.0054831282885779891,
              0.002056173108216749
            ],
            triangular: [
              0.0095911826824394419,
              0.044370140062685574,
              0.061103031234799265,
              0.0056764834447801549,
              0.002231852025117578
            ],
            biweight: [
              0.008920122966081195,
              0.043575489682529389,
              0.062072312371462303,
              0.0054633917227592376,
              0.0019881960806204047
            ],
            cosine: [
              0.0089026400318507597,
              0.043323449020884718,
              0.06187082046694594,
              0.0055076346108025335,
              0.0020094502788162065
            ],
            optcosine: [
              0.008917997236684759,
              0.043953984185432608,
              0.062157352233790972,
              0.0053170587371680518,
              0.0019620187026103326
            ]
          ] do
        assert_near(estimate(frame, n: 5, kernel: kernel), :density, expected)
      end
    end

    # Golden: the first four densities of `geom_density()` with `n = 513` and `n = 1024`, on a grid
    # of 1,024 points, and `n = 1025`, on one of 2,048; at 512 the first is 0.0093474699133166347.
    test "past 512 places the grid is the least power of two holding them" do
      frame = hwy_frame()

      for {places, expected} <- [
            {513,
             [
               0.0093440973253974512,
               0.0096322930753769409,
               0.0099292897269487659,
               0.010234306646215257
             ]},
            {1024,
             [
               0.0093440973253974512,
               0.0094875351129041895,
               0.0096325812303428328,
               0.0097801165728798791
             ]},
            {1025,
             [
               0.0093438740768239468,
               0.0094869353369978621,
               0.0096322592476193077,
               0.0097794977338738244
             ]}
          ] do
        densities =
          frame
          |> estimate(n: places)
          |> DataFrame.pull(:density)

        assert length(densities) == places
        assert_near_values(:density, Enum.take(densities, 4), expected)
      end
    end

    # Golden: `geom_density(n = 5)` with `bounds = c(15, 40)`, `c(-Inf, 40)` and `c(12, Inf)`.
    test "rows outside finite bounds are left out and the curve folded back inside them" do
      frame = hwy_frame()

      both = estimate(frame, n: 5, bounds: {15.0, 40.0})

      assert DataFrame.pull(both, :x) === [
               15.0,
               16.785714285714285,
               18.571428571428573,
               20.357142857142858,
               22.142857142857142,
               23.928571428571431,
               25.714285714285715,
               27.5,
               29.285714285714285,
               31.071428571428573,
               32.857142857142861,
               34.642857142857139,
               36.428571428571431,
               38.214285714285715,
               40.0
             ]

      assert_near(both, :density, [
        0.050031419536183508,
        0.048185717632693498,
        0.045109547793543481,
        0.042033377954393464,
        0.04136685214362535,
        0.047298043077601881,
        0.05471484190889328,
        0.062131640740185574,
        0.053655920865872758,
        0.038999826942791478,
        0.024348090938645626,
        0.0096974433296185044,
        0.0061319000090605136,
        0.0040779618187483406,
        0.0039958042911358484
      ])

      assert_near(both, :scaled, [
        0.80524864529811346,
        0.7755423333208048,
        0.72603181335862377,
        0.67652129339644285,
        0.66579365442171645,
        0.76125533647802734,
        0.88062766823900651,
        1.0,
        0.8635844833109183,
        0.62769671745634625,
        0.39187909169277318,
        0.15607898349522228,
        0.098692066329008371,
        0.06563422066706813,
        0.064311906840590446
      ])

      assert_near(both, :count, [
        11.207037976105106,
        10.793600749723343,
        10.10453870575374,
        9.4154766617841368,
        9.2661748801720787,
        10.594761649382821,
        12.256124587592094,
        13.917487525801569,
        12.018926273955497,
        8.7359612351852913,
        5.4539723702566203,
        2.1722273058345452,
        1.3735456020295551,
        0.91346344739962826,
        0.89506016121442999
      ])

      assert_near(both, :wdensity, [
        11.207037976105108,
        10.793600749723344,
        10.104538705753741,
        9.4154766617841368,
        9.2661748801720805,
        10.594761649382823,
        12.256124587592096,
        13.917487525801571,
        12.018926273955499,
        8.7359612351852913,
        5.4539723702566212,
        2.1722273058345452,
        1.3735456020295553,
        0.91346344739962837,
        0.89506016121443022
      ])

      assert DataFrame.pull(both, :n) === [
               224,
               224,
               224,
               224,
               224,
               224,
               224,
               224,
               224,
               224,
               224,
               224,
               224,
               224,
               224
             ]

      high = estimate(frame, n: 5, bounds: {:neg_infinity, 40.0})

      assert DataFrame.pull(high, :x) === [
               12.0,
               15.111111111111111,
               18.222222222222221,
               21.333333333333336,
               24.444444444444443,
               27.555555555555557,
               30.666666666666668,
               33.777777777777779,
               36.888888888888886,
               40.0
             ]

      assert_near(high, :density, [
        0.0090785963347333985,
        0.027497846380733781,
        0.045917096426734159,
        0.058524690283392126,
        0.068807621664313104,
        0.062951860398695131,
        0.035577842270091524,
        0.011407691408269067,
        0.0062841931831204402,
        0.0018926232758501756
      ])

      assert DataFrame.pull(high, :n) === [231, 231, 231, 231, 231, 231, 231, 231, 231, 231]

      low = estimate(frame, n: 5, bounds: {12.0, :infinity})

      assert DataFrame.pull(low, :x) === [
               12.0,
               15.555555555555555,
               19.111111111111111,
               22.666666666666664,
               26.222222222222221,
               29.777777777777779,
               33.333333333333329,
               36.888888888888886,
               40.444444444444443,
               44.0
             ]

      assert_near(low, :density, [
        0.045684457485645653,
        0.04568445748564566,
        0.043505297465042163,
        0.041326137444438658,
        0.041761599277643696,
        0.042197061110848692,
        0.023278868808583889,
        0.00436067650631905,
        0.0032456920900197804,
        0.0021307076737205112
      ])

      assert DataFrame.pull(low, :n) === [234, 234, 234, 234, 234, 234, 234, 234, 234, 234]
    end

    # Golden: x 1, 2, 3, 5 and 8 weighted 1, 2, 0, 3 and 1.5 with `geom_density(n = 4)`, and with
    # `n = 2, bounds = c(1.5, 6)`; and x 1, 2, 3 and 5 weighted -1, -2, -1 and -3, every share of
    # their total above 0.
    test "each row weighs its weight's share of its group's, the count counting rows" do
      weighted = one_panel(x: [1.0, 2.0, 3.0, 5.0, 8.0], weight: [1, 2, 0, 3, 1.5])

      plain = estimate(weighted, [n: 4], x: {1, 8})
      assert DataFrame.pull(plain, :x) === [1.0, 3.3333333333333335, 5.666666666666667, 8.0]

      assert_near(plain, :density, [
        0.096609158747373886,
        0.11549046046156743,
        0.11703559875729051,
        0.067897701221173279
      ])

      assert_near(plain, :scaled, [
        0.82546814621526254,
        0.98679770674794931,
        1.0,
        0.5801457158516371
      ])

      assert_near(plain, :count, [
        0.4830457937368694,
        0.57745230230783717,
        0.58517799378645252,
        0.33948850610586639
      ])

      assert_near(plain, :wdensity, [
        0.72456869060530416,
        0.8661784534617557,
        0.87776699067967889,
        0.50923275915879962
      ])

      assert DataFrame.pull(plain, :n) === [5, 5, 5, 5]

      bounded = estimate(weighted, [n: 2, bounds: {1.5, 6.0}], x: {1, 8})

      assert DataFrame.pull(bounded, :x) === [
               1.5,
               2.3999999999999999,
               3.2999999999999998,
               4.2000000000000002,
               5.0999999999999996,
               6.0
             ]

      assert_near(bounded, :density, [
        0.27992537705456555,
        0.28890886270585009,
        0.23135029064179111,
        0.17379171857773204,
        0.12882039388460825,
        0.12222099298053157
      ])

      assert_near(bounded, :count, [
        0.83977613116369665,
        0.86672658811755032,
        0.69405087192537329,
        0.52137515573319615,
        0.38646118165382476,
        0.36666297894159472
      ])

      assert_near(bounded, :wdensity, [
        1.399626885272828,
        1.4445443135292506,
        1.1567514532089558,
        0.8689585928886604,
        0.64410196942304143,
        0.61110496490265798
      ])

      assert DataFrame.pull(bounded, :n) === [3, 3, 3, 3, 3, 3]

      negative =
        estimate(one_panel(x: [1.0, 2.0, 3.0, 5.0], weight: [-1, -2, -1, -3]), [n: 3], x: {1, 5})

      assert_near(negative, :density, [
        0.13727118201433733,
        0.15270579846961316,
        0.19750721008117639
      ])

      assert_near(negative, :count, [
        0.54908472805734931,
        0.61082319387845263,
        0.79002884032470555
      ])

      assert_near(negative, :wdensity, [
        -0.96089827410036133,
        -1.0689405892872921,
        -1.3825504705682348
      ])
    end

    # Golden: x 1, 2, 3 and 9 weighted 0, 0, 0 and 1 with `n = 2, bounds = c(0, 5)`: the rows
    # inside weigh nothing, so the curve is 0 and scaled NaN, as R divides 0 by 0.
    test "rows inside the bounds weighing nothing give a curve of 0, its scaled values NaN" do
      curve =
        estimate(
          one_panel(x: [1.0, 2.0, 3.0, 9.0], weight: [0, 0, 0, 1]),
          [n: 2, bounds: {0.0, 5.0}],
          x: {1, 9}
        )

      assert DataFrame.pull(curve, :x) === [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]
      assert DataFrame.pull(curve, :density) === [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
      assert DataFrame.pull(curve, :scaled) === [:nan, :nan, :nan, :nan, :nan, :nan]
      assert DataFrame.pull(curve, :wdensity) === [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
      assert DataFrame.pull(curve, :n) === [3, 3, 3, 3, 3, 3]
    end

    # Golden: x 1, NA, 2, Inf, 4 and 7 with `n = 3`.
    test "a row missing its x, or at an infinite one, is left out" do
      curve = estimate(one_panel(x: [1.0, nil, 2.0, :infinity, 4.0, 7.0]), [n: 3], x: {1, 7})

      assert_near(curve, :density, [
        0.12752436585743054,
        0.11197965090664466,
        0.075127057915767986
      ])

      assert DataFrame.pull(curve, :n) === [4, 4, 4]
    end

    # Golden: x 1, 2, 3 and 7 in groups a, a, a and b, coloured p, p, p and q, with `n = 2`; and x
    # 1, 2, 3, 7 and 8 in groups a, a, a, b and b with `bounds = c(0, 5)`: a group of one row, or of
    # none inside the bounds, is one row of missing values, its constant columns carried.
    test "a group of fewer than two rows inside the bounds is a row of missing values" do
      lone =
        DataFrame.new(
          x: [1.0, 2.0, 3.0, 7.0],
          color: ["p", "p", "p", "q"],
          panel: [1, 1, 1, 1],
          group: [1, 1, 1, 2]
        )

      curve = estimate(lone, [n: 2], x: {1, 7})

      densities = DataFrame.pull(curve, :density)

      assert DataFrame.pull(curve, :x) === [1.0, 7.0, nil]
      assert List.last(densities) == nil
      assert DataFrame.pull(curve, :n) === [3, 3, nil]
      assert DataFrame.pull(curve, :color) == ["p", "p", "q"]

      outside =
        DataFrame.new(
          x: [1.0, 2.0, 3.0, 7.0, 8.0],
          panel: [1, 1, 1, 1, 1],
          group: [1, 1, 1, 2, 2]
        )

      bounded = estimate(outside, [n: 2, bounds: {0.0, 5.0}], x: {1, 8})

      places = DataFrame.pull(bounded, :x)

      assert DataFrame.pull(bounded, :group) == [1, 1, 1, 1, 1, 1, 2]
      assert List.last(places) == nil
    end

    # Golden: ggplot2 computes nothing for a panel where R's `density()` fails, warning
    # "Computation failed in `stat_density()`": a negative weight beside positive ones, a missing,
    # NaN or infinite one, weights totalling 0, Scott's rule for rows at one x, a missing weight
    # where some rows are outside the bounds; the panel beside it is computed. A lone row whose
    # weight is missing is a row of missing values, its group too few to fail.
    test "a panel where any group's estimate fails is given no rows, and the others are" do
      for {weights, options} <- [
            {[1, -1, 2], []},
            {[1, nil, 2], []},
            {[1, :nan, 2], []},
            {[1, :infinity, 2], []},
            {[0, 0, 0], []},
            {[1, nil, 2], bounds: {0.0, 2.5}}
          ] do
        frame = two_panels(x: [1.0, 2.0, 3.0], weight: weights)

        panels =
          frame
          |> estimate([n: 2] ++ options, x: {1, 3})
          |> DataFrame.pull(:panel)
          |> Enum.uniq()

        assert panels == [2], "weights #{inspect(weights)}, #{inspect(options)}"
      end

      # Golden: one row inside the bounds whose weight is missing or NaN, beside two outside.
      for weights <- [[nil, 1, 1], [:nan, 1, 1]] do
        panels =
          [x: [1.0, 10.0, 11.0], weight: weights]
          |> two_panels()
          |> estimate([n: 2, bounds: {0.0, 5.0}], x: {1, 11})
          |> DataFrame.pull(:panel)
          |> Enum.uniq()

        assert panels == [2], "weights #{inspect(weights)}"
      end

      # Golden: weights all missing, a column of no type, which is not refused as not numbers.
      unweighed =
        [x: [1.0, 2.0, 3.0], weight: [nil, nil, nil]]
        |> one_panel()
        |> estimate([n: 2], x: {1, 3})

      assert DataFrame.row_count(unweighed) == 0

      # Golden: a bandwidth multiplied past a double's range, either way, in every panel.
      for {bandwidth, adjust} <- [{1.0e-200, 1.0e-200}, {1.0e300, 1.0e10}] do
        curve =
          [x: [1.0, 2.0, 4.0], weight: [1, 1, 1]]
          |> two_panels()
          |> estimate([n: 2, bandwidth: bandwidth, adjust: adjust], x: {1, 4})

        assert DataFrame.row_count(curve) == 0
      end

      level = two_panels(x: [2.0, 2.0, 2.0], weight: [1, 1, 1])

      level_curve = estimate(level, [n: 2, bandwidth: :nrd], x: {1, 3})

      assert DataFrame.pull(level_curve, :panel) == [2, 2]

      lone =
        DataFrame.new(x: [1.0, 5.0, 6.0], weight: [nil, 1, 1], panel: [1, 1, 1], group: [1, 2, 2])

      lone_curve = estimate(lone, [n: 2], x: {1, 6})

      assert DataFrame.pull(lone_curve, :n) === [nil, 2, 2]
    end

    # Golden: x 1, 2, 3, 4 and 100 with `n = 3`, by Scott's rule and Silverman's: the outlier
    # spreads the standard deviation past the interquartile range over 1.34, which each takes.
    test "each rule takes the lesser of the deviation and the interquartile range over 1.34" do
      frame = one_panel(x: [1.0, 2.0, 3.0, 4.0, 100.0])

      assert_near(estimate(frame, [n: 3, bandwidth: :nrd], x: {1, 100}), :density, [
        0.13427862842706603,
        1.3341827710439745e-18,
        0.069060656860154904
      ])

      assert_near(estimate(frame, [n: 3], x: {1, 100}), :density, [
        0.14045001460737799,
        2.1366406094490662e-18,
        0.081088113076211041
      ])
    end

    # Golden: x 1e300, -1e300, 1e300 and -1e300 with `n = 3`, by each rule: their variance is past
    # the largest double, as R's `var()` gives it, and the interquartile range sets the bandwidth.
    test "an infinite variance leaves the bandwidth to the interquartile range" do
      frame = one_panel(x: [1.0e300, -1.0e300, 1.0e300, -1.0e300])

      for {bandwidth, expected} <- [
            nrd0: [2.2438109047126128e-301, 2.4189384779055763e-301, 2.2438109047126116e-301],
            nrd: [2.0774389131283492e-301, 2.3497998516875738e-301, 2.0774389131283492e-301]
          ] do
        curve = estimate(frame, [n: 3, bandwidth: bandwidth], x: {-1.0e300, 1.0e300})
        assert_near(curve, :density, expected)
      end
    end

    # Golden: x 0, 0.001, ..., 0.05 and 1 with `n = 5`: rows a thousandth apart, closer than the
    # grid's points, so the parts of neighbouring rows' shares add up at each point.
    test "the parts of rows sharing a grid point add up" do
      dense = Enum.map(0..51, fn step -> if step == 51, do: 1.0, else: step / 1000 end)

      curve = estimate(one_panel(x: dense), [n: 5], x: {0, 1})

      assert_near(curve, :density, [
        10.110091411611174,
        3.0346112246144055e-17,
        4.5955010223629299e-16,
        0.0,
        0.98422669097874138
      ])
    end

    # Golden: `geom_density(n = 1, bounds = c(-100, Inf))` over mpg's hwy: two places, the widened
    # axis's low end and its high end, whole numbers held as doubles, and the reflection in -100
    # past the curve's low end, adding 0.
    test "a reflection past the curve's ends adds nothing, and its places are doubles" do
      curve = estimate(hwy_frame(), n: 1, bounds: {-100.0, :infinity})

      assert DataFrame.pull(curve, :x) === [-20.0, 44.0]

      assert_near(curve, :density, [4.0203781816406096e-18, 0.0021307076737205072])
    end

    # Golden: a factor of drives carried with its levels and ordered flag, as R carries a factor.
    test "a group's constant category is carried with its levels" do
      frame =
        DataFrame.new([
          {:x, [1.0, 2.0, 4.0, 1.0, 3.0, 5.0]},
          {:color, ["r", "r", "r", "f", "f", "f"],
           {:category, levels: ["r", "f"], ordered: true}},
          {:panel, [1, 1, 1, 1, 1, 1]},
          {:group, [1, 1, 1, 2, 2, 2]}
        ])

      curve = estimate(frame, [n: 2], x: {1, 5})

      assert DataFrame.pull(curve, :color) == ["r", "r", "f", "f"]
      assert DataFrame.category(curve, :color) == {:category, levels: ["r", "f"], ordered: true}
    end

    test "a weight that is not a number is refused, naming its type" do
      frame = one_panel(x: [1.0, 2.0], weight: ["light", "heavy"])

      error = assert_raise ArgumentError, fn -> estimate(frame, [], x: {1, 2}) end

      assert error.message ==
               "a density spreads each row's weight over its grid, so a weight must be a " <>
                 "number, but the layer's weight is a :string column"
    end
  end

  # The table a smooth by least squares with ggplot2's defaults but `options` computes from
  # `frame`, in the panels given.
  defp fit(frame, options, panels \\ [1]) do
    stat = smooth(options)
    Stat.compute_layer(stat, frame, smooth_axes(panels))
  end

  # A smooth by least squares with ggplot2's defaults but those given.
  defp smooth(options) do
    struct!(
      %Stat.Smooth{method: :lm, se: true, level: 0.95, n: 80, fullrange: false, orientation: :x},
      options
    )
  end

  # Each panel's axes as a smooth reads them: the extents a full range spans, x's mpg's displ's
  # and y's wider than its hwy, 10 to 46.
  defp smooth_axes(panels) do
    x_axis = %{limits: {1.6, 7}, discrete: false, transform: fn values -> values end}
    y_axis = %{x_axis | limits: {10, 46}}
    Map.new(panels, fn panel -> {panel, %{x: x_axis, y: y_axis}} end)
  end

  # Five rows a line is fitted to, weighted as given.
  defp weighted_frame(weights) do
    DataFrame.new(
      x: [1.0, 2.0, 3.0, 4.0, 5.0],
      y: [2.0, 3.5, 3.0, 5.0, 4.2],
      weight: weights,
      panel: [1, 1, 1, 1, 1],
      group: [-1, -1, -1, -1, -1]
    )
  end

  # Each of a column's values within 1e-12 of R's, as a share of the largest magnitude R's holds,
  # and NaN where R's is.
  defp assert_near(frame, name, expected),
    do: assert_near_values(name, DataFrame.pull(frame, name), expected)

  # Values within 1e-12 of R's, of the largest magnitude R's hold, NaN where R's is.
  defp assert_near_values(name, actual, expected) do
    largest =
      expected
      |> Enum.filter(&is_number/1)
      |> Enum.map(&abs/1)
      |> Enum.max()

    assert length(actual) == length(expected)

    Enum.zip_with(actual, expected, fn
      value, :nan ->
        assert value == :nan, "#{name}: #{inspect(actual)}, R #{inspect(expected)}"

      value, wanted ->
        assert abs(value - wanted) <= 1.0e-12 * largest,
               "#{name}: #{inspect(actual)}, R #{inspect(expected)}"
    end)
  end

  # The table a density with ggplot2's defaults but `options` computes from `frame`, each of its
  # panels' axes the extent `limits` gives it, x's mpg's hwy's unless given.
  defp estimate(frame, options, limits \\ []) do
    stat =
      struct!(
        %Stat.Density{
          bandwidth: :nrd0,
          adjust: 1.0,
          kernel: :gaussian,
          n: 512,
          trim: false,
          bounds: {:neg_infinity, :infinity}
        },
        options
      )

    panel_axes = %{
      x: extent_axis(Keyword.get(limits, :x, {12, 44})),
      y: extent_axis(Keyword.get(limits, :y, {0, 1}))
    }

    Stat.compute_layer(stat, frame, %{1 => panel_axes, 2 => panel_axes})
  end

  defp extent_axis(limits),
    do: %{limits: limits, discrete: false, transform: fn values -> values end}

  # mpg's highway mileage in one panel and one group.
  defp hwy_frame do
    DataFrame.new(x: column(:hwy), panel: List.duplicate(1, 234), group: List.duplicate(-1, 234))
  end

  # A table of the columns given in one panel and one group.
  defp one_panel(columns) do
    rows =
      columns
      |> Keyword.fetch!(:x)
      |> length()

    columns
    |> Enum.concat(panel: List.duplicate(1, rows), group: List.duplicate(-1, rows))
    |> DataFrame.new()
  end

  # The columns given in panel 1, beside x 1, 2 and 3, each weighted 1, in panel 2.
  defp two_panels(columns) do
    columns
    |> Enum.map(fn {name, values} -> {name, values ++ [1.0, 2.0, 3.0]} end)
    |> Keyword.update!(:weight, fn weights -> Enum.take(weights, 3) ++ [1, 1, 1] end)
    |> Enum.concat(panel: [1, 1, 1, 2, 2, 2], group: [-1, -1, -1, -1, -1, -1])
    |> DataFrame.new()
  end

  # An area layer's table as aligning is handed it, its fill one colour per group.
  defp area_frame(columns) do
    group = Keyword.fetch!(columns, :group)
    rows = length(group)

    DataFrame.new(
      fill: Enum.map(group, fn id -> if id == 1, do: "#F8766D", else: "#00BFC4" end),
      x: Keyword.fetch!(columns, :x),
      y: Keyword.fetch!(columns, :y),
      panel: Keyword.get(columns, :panel, List.duplicate(1, rows)),
      group: group
    )
  end

  defp box, do: %Stat.Boxplot{coef: 1.5, width: :none, orientation: :none}

  defp width_frame(widths) do
    DataFrame.new(
      x: [1, 1, 2, 2],
      y: [1.0, 2.0, 3.0, 4.0],
      width: widths,
      panel: [1, 1, 1, 1],
      group: [1, 1, 2, 2]
    )
  end

  # Each panel's axes as the stat reads them: only whether each is discrete matters to a box plot.
  defp axes(panels, x_discrete, y_discrete) do
    Map.new(panels, fn panel -> {panel, %{x: axis(x_discrete), y: axis(y_discrete)}} end)
  end

  defp axis(discrete),
    do: %{limits: {0, 1}, discrete: discrete, transform: fn values -> values end}

  # A table of mpg's 234 rows, in one panel unless one is given.
  defp mpg_frame(columns) do
    columns
    |> Keyword.put_new(:panel, List.duplicate(1, 234))
    |> DataFrame.new()
  end

  defp column(name), do: Keyword.fetch!(Datasets.mpg(), name)

  # Each of a column's values at its level's place, from 1 in sorted order, as a discrete scale
  # places them.
  defp places(name) do
    values = column(name)

    places =
      values
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.with_index(1)
      |> Map.new()

    Enum.map(values, fn value -> Map.fetch!(places, value) end)
  end

  defp columns(frame, names), do: Enum.map(names, fn name -> DataFrame.pull(frame, name) end)
end
