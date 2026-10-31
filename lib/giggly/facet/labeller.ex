defmodule Giggly.Facet.Labeller do
  @moduledoc false

  # The labels of a facet's strips, ggplot2's labellers: `label/4` writes the strips of one side's
  # panels, a wrap's every panel or a grid's rows or columns, from the values of that side's
  # columns, as ggplot2's `build_strip()` hands its labeller a table of them, one row per strip.
  #
  # A labeller is held as `Giggly.Plot` records it, ggplot2's `labeller()`: a map of the labeller
  # for every strip of the rows (`:rows`) and of the columns (`:cols`), each `:none` when not given;
  # one for each column it names (`:columns`, by the column's name in the data); the labeller of
  # every other column (`:default`); and whether each column's label is a strip of its own
  # (`:multi_line`), or one strip holds them all, joined by ", ". One given alone, such as
  # `label_both`, is recorded as the labeller of both sides. Each labeller in it is one of:
  #
  # - `{:value, %{}}`, ggplot2's `label_value()`: the value alone, as R's `as.character()` writes
  #   it (`Giggly.AsCharacter`: `4` for a whole float, `TRUE`);
  # - `{:both, %{sep: sep}}`, `label_both()`: the column's name, `sep` and the value, `cyl: 4`; with
  #   every label in one strip, the names joined and then the values, `cyl, drv: 8, 4`;
  # - `{:context, %{}}`, `label_context()`: the value alone for one column, both for more, with
  #   ": ", as R passes its `sep` nowhere;
  # - a function of one label, returning the label to show, or a map of labels to the labels to
  #   show, ggplot2's `as_labeller()`: each label is replaced, and then the labeller's `:default`
  #   writes the labels it gives, as `as_labeller(x, default)` hands them on, a label the map
  #   lacks missing.
  #
  # A side's labeller, where it has one, writes its strips, every column of the side at once; a
  # wrap's strips are its columns', labelled by whichever side's labeller is given, as ggplot2's
  # `resolve_labeller()` takes `cols %||% rows`. Otherwise each column is labelled alone, by its own
  # labeller or else the default, and a label its own leaves missing is the default's, as
  # `labeller()` fills them in; with `multi_line` false they are then joined, `cyl: 8, drv: 4`.
  #
  # A missing value (`nil`) is missing to the end, never handed to a function or looked up, and is
  # written `NA` wherever a strip shows it, `cyl: NA` beside a name, as R writes and draws R's
  # missing string. A function must return a string.

  alias Giggly.AsCharacter

  @value {:value, %{}}

  @typedoc "One labeller: a kind of label, or a function or map giving one."
  @type labeller ::
          {:value, %{}}
          | {:both, %{sep: String.t()}}
          | {:context, %{}}
          | (String.t() -> String.t())
          | %{String.t() => String.t()}

  @type t :: %{
          rows: labeller() | :none,
          cols: labeller() | :none,
          columns: %{String.t() => labeller()},
          default: labeller(),
          multi_line: boolean()
        }

  # Each strip's labels on `side` (`:wrap`, `:rows` or `:cols`), for each of `combinations`, the
  # values of `columns`, in their order, under `labeller`: one label for each column, in the
  # columns' order, or one for all of them; a side splitting on no columns has no strips.
  @doc false
  @spec label(t(), :wrap | :rows | :cols, [String.t()], [[term()]]) :: [[String.t()]]
  def label(_labeller, _side, [], combinations),
    do: Enum.map(combinations, fn _values -> [] end)

  def label(labeller, side, columns, combinations) do
    table =
      Enum.with_index(columns, fn name, index ->
        {name,
         Enum.map(combinations, fn values ->
           value = Enum.at(values, index)
           written(value)
         end)}
      end)

    labeller
    |> layers(side, table)
    |> Enum.zip_with(fn labels -> Enum.map(labels, &shown/1) end)
  end

  # A side's labels, a list of strips' labels for each strip a panel stacks, nearest first.
  defp layers(%{default: default, multi_line: multi_line} = labeller, side, table) do
    case margin(labeller, side) do
      :none -> by_column(labeller, table)
      margin -> evaluate(margin, default, multi_line, table)
    end
  end

  # The labeller of every strip on a side, `:none` where it has none.
  defp margin(%{rows: rows, cols: :none}, :wrap), do: rows
  defp margin(%{cols: cols}, :wrap), do: cols
  defp margin(%{rows: rows}, :rows), do: rows
  defp margin(%{cols: cols}, :cols), do: cols

  # Each column labelled alone, by its own labeller where it has one, a label that leaves missing
  # filled in from the default's.
  defp by_column(%{columns: own, default: default, multi_line: multi_line}, table) do
    layers = Enum.map(table, fn column -> column_alone(column, own, default) end)
    if multi_line, do: layers, else: [joined(layers)]
  end

  defp column_alone({name, _labels} = column, own, default) do
    fallback = column_labels(default, @value, column)

    case Map.fetch(own, name) do
      {:ok, labeller} ->
        labeller
        |> column_labels(default, column)
        |> Enum.zip_with(fallback, fn label, default_label -> label || default_label end)

      :error ->
        fallback
    end
  end

  defp column_labels(labeller, default, column) do
    [labels] = evaluate(labeller, default, true, [column])
    labels
  end

  # The strips' labels under one labeller, a function's or a map's written by `default`.
  defp evaluate({:value, _options}, _default, multi_line, table), do: values(table, multi_line)

  defp evaluate({:both, %{sep: separator}}, _default, multi_line, table),
    do: both(table, multi_line, separator)

  defp evaluate({:context, _options}, _default, multi_line, [_column] = table),
    do: values(table, multi_line)

  defp evaluate({:context, _options}, _default, multi_line, table),
    do: both(table, multi_line, ": ")

  defp evaluate(function, default, multi_line, table) when is_function(function, 1) do
    relabelled = relabelled(table, fn label -> called(function, label) end)
    evaluate(default, @value, multi_line, relabelled)
  end

  defp evaluate(lookup, default, multi_line, table) when is_map(lookup) do
    relabelled = relabelled(table, fn label -> Map.get(lookup, label) end)
    evaluate(default, @value, multi_line, relabelled)
  end

  defp values(table, true), do: Enum.map(table, fn {_name, labels} -> labels end)

  defp values(table, false) do
    labels = values(table, true)
    [joined(labels)]
  end

  defp both(table, true, separator) do
    Enum.map(table, fn {name, labels} ->
      Enum.map(labels, fn label -> name <> separator <> shown(label) end)
    end)
  end

  defp both(table, false, separator) do
    names = Enum.map_join(table, ", ", fn {name, _labels} -> name end)

    [
      table
      |> values(true)
      |> joined()
      |> Enum.map(fn label -> names <> separator <> label end)
    ]
  end

  # Each strip's labels joined into one, ggplot2's `collapse_labels_lines()`.
  defp joined(layers),
    do: Enum.zip_with(layers, fn labels -> Enum.map_join(labels, ", ", &shown/1) end)

  # Each label replaced, a missing one kept missing.
  defp relabelled(table, replace) do
    Enum.map(table, fn {name, labels} ->
      {name, Enum.map(labels, fn label -> label && replace.(label) end)}
    end)
  end

  defp called(function, label) do
    case function.(label) do
      shown when is_binary(shown) ->
        shown

      other ->
        raise ArgumentError,
              "a labeller function must return a string, and returned #{inspect(other)} " <>
                "for the label #{inspect(label)}"
    end
  end

  defp written(nil), do: nil
  defp written(value), do: AsCharacter.text(value)

  defp shown(nil), do: "NA"
  defp shown(label), do: label
end
