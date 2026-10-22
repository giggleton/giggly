defmodule Giggly.Stat.Carry do
  @moduledoc false

  # The columns a summarising stat carries from a group's rows to the rows it computes for the
  # group, as ggplot2's default `compute_panel()` carries a group's constant columns: each column
  # holding one value within every group, `panel` and `group` among them, while one that varies
  # within any group is dropped (ggplot2 also warns, which a pure pipeline cannot). The frame finds
  # them, counting each column's distinct values in each group (`n_distinct`, a missing value
  # counting as one), so a stat never pulls its input to do it; the stat then takes each kept
  # column's `first` value in each group, which keeps its type, as R keeps a factor.

  alias Giggly.DataFrame

  # The names among `carried` that hold one value within every group of `frame`, in their order.
  @doc false
  @spec constant_columns(DataFrame.t(), [DataFrame.name()]) :: [DataFrame.name()]
  def constant_columns(frame, carried) do
    counted_distinct =
      for name <- carried, name not in [:panel, :group], do: {name, {:n_distinct, [name]}}

    distinct = DataFrame.summarise(frame, [:panel, :group], counted_distinct)

    Enum.filter(carried, fn name ->
      name in [:panel, :group] or one_value_in_each_group?(distinct, name)
    end)
  end

  defp one_value_in_each_group?(distinct, name) do
    distinct
    |> DataFrame.pull(name)
    |> Enum.all?(fn count -> count == 1 end)
  end
end
