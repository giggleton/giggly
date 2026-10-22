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
