defmodule GigglyCredo.ChecksTest do
  # The one file that loads the repo-local credo checks: requiring a source twice in one VM
  # redefines its module, and the warning fails the gate (`.credo/checks/README.md`).
  use Credo.Test.Case, async: true

  checks = Path.expand("../.credo/checks/*.ex", __DIR__)

  for path <- Path.wildcard(checks) do
    Code.require_file(path)
  end

  alias GigglyCredo.Check.{PlotRunsNothing, ZipMap}

  # Credo is a `runtime: false` dependency, so its services, which parse a source, start here.
  setup_all do
    {:ok, _applications} = Application.ensure_all_started(:credo)
    :ok
  end

  # A module whose one function's body is `body`, as a source file credo can read.
  defp source(body) do
    to_source_file("""
    defmodule Sample do
      def run(positions, labels) do
        #{body}
      end
    end
    """)
  end

  # A plot module aliasing its families as `Giggly.Plot` does, whose one function's body is `body`,
  # as a source file credo can read.
  defp plot_source(body) do
    to_source_file("""
    defmodule Sample.Plot do
      alias Giggly.{Geom, Stat}

      def add(layer, frame) do
        #{body}
      end
    end
    """)
  end

  @roots [roots: [Giggly.Geom, Giggly.Stat]]

  describe "ZipMap" do
    test "a zip piped into a map is reported at the map, naming the one-pass function" do
      """
      positions
        |> Enum.zip(labels)
        |> Enum.map(fn {position, label} -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue(fn issue ->
        assert {issue.line_no, issue.column, issue.trigger} == {5, 6, "Enum.map"}
        assert issue.message =~ "Enum.zip_with"
      end)
    end

    test "a zip of a list of enumerables piped into a map is reported" do
      """
      [positions, labels]
        |> Enum.zip()
        |> Enum.map(fn {position, label} -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue()
    end

    test "a zip call piped into a map is reported" do
      """
      Enum.zip(positions, labels) |> Enum.map(fn {position, label} -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue()
    end

    test "a zip and map in the middle of a longer pipe are reported" do
      """
      positions
        |> Enum.sort()
        |> Enum.zip(labels)
        |> Enum.map(fn {position, label} -> {position, label} end)
        |> Enum.reverse()
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue()
    end

    test "a zip passed to a map is reported" do
      """
      Enum.map(Enum.zip(positions, labels), fn {position, label} -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue()
    end

    test "a piped zip passed to a map is reported" do
      """
      Enum.map(positions |> Enum.zip(labels), fn {position, label} -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue()
    end

    test "a zip with in one pass is not reported" do
      """
      Enum.zip_with(positions, labels, fn position, label -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> refute_issues()
    end

    test "a zip piped into something other than a map is not reported" do
      """
      positions
        |> Enum.zip(labels)
        |> Map.new()
      """
      |> source()
      |> run_check(ZipMap)
      |> refute_issues()
    end

    test "a map of something other than a zip is not reported, piped or passed" do
      """
      sorted = positions |> Enum.sort() |> Enum.map(fn position -> position end)
      Enum.map(Enum.sort(labels), fn label -> label end)
      Enum.map(labels |> Enum.sort(), fn label -> {sorted, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> refute_issues()
    end

    test "a zip or a map from another module than Enum is not reported" do
      """
      lazy = positions |> Stream.zip(labels) |> Enum.map(fn pair -> pair end)
      positions |> Enum.zip(labels) |> Stream.map(fn pair -> {lazy, pair} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> refute_issues()
    end
  end

  describe "PlotRunsNothing" do
    test "a call on an aliased root is reported at the reference, as written" do
      "Geom.draw_panel(layer.geom, frame, nil, nil)"
      |> plot_source()
      |> run_check(PlotRunsNothing, @roots)
      |> assert_issue(fn issue ->
        assert {issue.line_no, issue.column, issue.trigger} == {5, 5, "Geom"}
        assert issue.message =~ "runs nothing"
      end)
    end

    test "a call on a root written in full is reported" do
      "Giggly.Stat.compute_layer(layer.stat, frame)"
      |> plot_source()
      |> run_check(PlotRunsNothing, @roots)
      |> assert_issue(fn issue -> assert issue.trigger == "Giggly.Stat" end)
    end

    test "a root reached through a renamed alias of the namespace above it is reported" do
      """
      alias Giggly, as: Library
          Library.Geom.draw_panel(layer.geom, frame, nil, nil)
      """
      |> plot_source()
      |> run_check(PlotRunsNothing, @roots)
      |> assert_issue(fn issue ->
        assert {issue.line_no, issue.trigger} == {6, "Library.Geom"}
      end)
    end

    test "a root passed as a value is reported, since it closes a call made through it" do
      "apply(Stat, :compute_layer, [layer.stat, frame])"
      |> plot_source()
      |> run_check(PlotRunsNothing, @roots)
      |> assert_issue()
    end

    test "an import of a root is reported" do
      "import Giggly.Geom"
      |> plot_source()
      |> run_check(PlotRunsNothing, @roots)
      |> assert_issue()
    end

    test "a kind's struct and facts, and the aliases naming the families, are not reported" do
      "{%Geom.Point{}, Geom.Point.required_aesthetics(), Stat.Identity, layer, frame}"
      |> plot_source()
      |> run_check(PlotRunsNothing, @roots)
      |> refute_issues()
    end

    test "a name the check cannot resolve is passed over, aliased or written" do
      """
      alias __MODULE__.Layer
          alias __MODULE__.Sub.{Helper}
          alias :math, as: Math
          {Layer.new(layer), __MODULE__.Layer, Helper.run(frame), Math.pi()}
      """
      |> plot_source()
      |> run_check(PlotRunsNothing, @roots)
      |> refute_issues()
    end

    test "the boundary declaration listing the families is not reported" do
      """
      defmodule Sample.Plot do
        use Boundary, deps: [Giggly.Geom, Giggly.Stat], exports: []
      end
      """
      |> to_source_file()
      |> run_check(PlotRunsNothing, @roots)
      |> refute_issues()
    end

    test "a module whose name only ends as a root's does is not reported, an alias rebound included" do
      """
      alias Other.Geom
          alias Other.{Stat}
          {Geom.draw_panel(layer, frame), Stat.run(layer), Sample.Stat.compute_layer(layer, frame)}
      """
      |> plot_source()
      |> run_check(PlotRunsNothing, @roots)
      |> refute_issues()
    end
  end
end
