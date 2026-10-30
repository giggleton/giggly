defmodule Giggly.Scale.BreaksFunction do
  @moduledoc false

  # A scale's breaks or minor breaks given as a function: called as ggplot2's `get_breaks()` and
  # `get_breaks_minor()` call one, by how many arguments it takes, and what it returns read as
  # ggplot2 reads a breaks vector.
  #
  # A breaks function of one argument is handed the limits, `{low, high}` in data units; of two,
  # the limits and the breaks wanted, `[n: wanted]`, or `[]` where the scale wants none, so the
  # function's own default holds, as ggplot2 hands `n.breaks` only to a function with an `n`
  # argument. A minor breaks function of one argument is handed the limits; of two, the limits
  # and the breaks in data units, as ggplot2 counts its arguments.
  #
  # What it returns is a list of breaks of the scale's kind, or of `{break, label}` pairs, each
  # label the break's, as R labels a break by its name, numbers read as floats; anything else
  # raises, naming the kind.

  @typedoc """
  The breaks a scale takes: numbers, dates, date-times, times of day, or any value a discrete
  scale holds, which is never a tuple.
  """
  @type kind :: :number | :date | :datetime | :time | :value

  # The breaks `function` gives on `limits` with `wanted` breaks wanted, each of `kind`, and their
  # labels, or `:none` where it gives breaks alone.
  @doc false
  @spec breaks(function(), {term(), term()} | list(), :default | pos_integer(), kind()) ::
          {list(), [String.t()] | :none}
  def breaks(function, limits, _wanted, kind) when is_function(function, 1) do
    returned = function.(limits)
    read(returned, kind)
  end

  def breaks(function, limits, wanted, kind) when is_function(function, 2) do
    returned = function.(limits, wanted_options(wanted))
    read(returned, kind)
  end

  # The minor breaks `function` gives on `limits` between `breaks`, each of `kind`, any labels
  # dropped, as ggplot2 reads no name of a minor break.
  @doc false
  @spec minor_breaks(function(), {term(), term()}, list(), kind()) :: list()
  def minor_breaks(function, limits, _breaks, kind) when is_function(function, 1) do
    returned = function.(limits)
    {breaks, _labels} = read(returned, kind)
    breaks
  end

  def minor_breaks(function, limits, breaks, kind) when is_function(function, 2) do
    returned = function.(limits, breaks)
    {minor_breaks, _labels} = read(returned, kind)
    minor_breaks
  end

  defp wanted_options(:default), do: []
  defp wanted_options(wanted), do: [n: wanted]

  defp read(returned, kind) when is_list(returned) do
    cond do
      Enum.all?(returned, fn value -> of_kind?(value, kind) end) ->
        {as_read(returned, kind), :none}

      Enum.all?(returned, fn value -> labelled?(value, kind) end) ->
        {breaks, labels} = Enum.unzip(returned)
        {as_read(breaks, kind), labels}

      true ->
        refuse(returned, kind)
    end
  end

  defp read(returned, kind), do: refuse(returned, kind)

  # Numbers as floats, as R's breaks are doubles; other values as returned.
  defp as_read(breaks, :number), do: Enum.map(breaks, fn break -> break / 1 end)
  defp as_read(breaks, _kind), do: breaks

  defp labelled?({value, label}, kind), do: is_binary(label) and of_kind?(value, kind)
  defp labelled?(_value, _kind), do: false

  defp of_kind?(value, :number), do: is_number(value)
  defp of_kind?(value, :date), do: is_struct(value, Date)

  defp of_kind?(value, :datetime),
    do: is_struct(value, DateTime) or is_struct(value, NaiveDateTime)

  defp of_kind?(value, :time), do: is_struct(value, Time)
  defp of_kind?(value, :value), do: not is_tuple(value)

  defp refuse(returned, kind) do
    raise ArgumentError,
          "a scale's breaks function must return a list of #{kind_name(kind)}, or of " <>
            "{break, label} pairs, got: #{inspect(returned)}"
  end

  defp kind_name(:number), do: "numbers"
  defp kind_name(:date), do: "dates"
  defp kind_name(:datetime), do: "date-times"
  defp kind_name(:time), do: "times of day"
  defp kind_name(:value), do: "values"
end
