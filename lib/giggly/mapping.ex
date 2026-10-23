defmodule Giggly.Mapping do
  @moduledoc """
  What a mapping maps each aesthetic to: a column, an expression computed from columns in each
  row, or a constant. A mapping is a map from aesthetic to value:

      %{x: :displ, y: {&Kernel.//2, [:hwy, :cty]}, colour: {:constant, "smooth"}}

  ## Values

    * **A column** is named by an atom or a string, compared with the table's column names as a
      string, so `:hwy` and `"hwy"` name the same column. `true`, `false` and `nil` name none.
    * **An expression**, `{function, [value, ...]}`, is the function applied in each row to what
      its arguments are in that row, so `{&Kernel.//2, [:hwy, :cty]}` divides each row's `hwy` by
      its `cty`. Each argument is a value, so it may be a column, a constant or another expression,
      and the function takes as many arguments as it is given.
    * **A function by name**, `{:log10, [value]}`, is a common function Elixir lacks, computed by
      the engine holding the table: `log10` is the base-10 logarithm, minus infinity for 0, NaN
      for a negative number and missing for a missing value. Its value is a column, a constant
      or another function by name, never a capture or a closure, which the engine cannot run, so
      the logarithm of what a capture computes is a capture too, `{&:math.log10/1, [value]}`.
      Any other function is written as a capture.
    * **A constant**, `{:constant, term}`, is the term in every row. A number, a boolean, a date or
      a time is a constant written alone; a string or an atom would name a column, so a constant
      one is written `{:constant, "smooth"}`.
    * **A factor**, `{:factor, [value]}`, is the value read as discrete, so a column of numbers
      maps as levels: a discrete scale whatever the values, its levels in order of value (dates by
      date) with a missing one last, each written as text (a whole number without a decimal
      point, `4`; a boolean as `TRUE` or `FALSE`), and the rows grouped by them.
      `{:factor, [value], levels: [level, ...]}` gives the levels and their order, each named as
      the value holds it (`[8, 4, 6]` for numbers), a value not among them missing, so the axis,
      the legend, the groups and stacking follow that order; `ordered: true` marks the factor's
      levels as ordered. A factor reads a whole column, so it is the whole of a mapping value, a
      factor's own or an after_stat's, never an expression's argument.
    * **A reordering**, `{:reorder, [value, by]}`, is `value` read as discrete, as a factor reads
      it, its levels ordered by the mean of `by` over each one's rows, the lowest first: levels
      whose means tie keep the order the factor of `value` gives them (its own levels where the
      table's column is a factor), and a level whose mean is missing, since its rows hold a
      missing or NaN `by` or there are none, goes last. The mean is R's `mean()`, worked out as
      R works it out, digit for digit. Each of `value` and `by` is a column or a function by
      name, which the engine holding the table computes, as it computes the means, and `by` is
      numbers; the levels are ordered, as `ordered: true` marks a factor's, where `value` is an
      ordered factor. A reordering reads whole columns, as a factor does, so it goes where a
      factor goes.
    * **An after_stat**, `{:after_stat, [value]}`, is the value computed from what the layer's stat
      computes: its names are the stat's computed variables (counting's are `count` and `prop`),
      and it is evaluated once the stat has run, so it takes no part in grouping or in what the
      stat computes. Its value is put through its aesthetic's scale. It is the whole of a mapping
      value, never inside another, so the share as a percentage is written
      `{:after_stat, [{&Kernel.*/2, [:prop, 100]}]}`.

  A constant is a value a column can hold: `nil`, a list, and a value with no column type of its
  own (a map, a tuple, a struct other than a date or a time) are refused, and so are a function
  alone, a tuple that is neither an expression nor a constant, and a function given a number of
  arguments it does not take. A function by name is refused where the table's engine cannot run
  it, and `log10` where its value is a column or a constant that is not numbers, a factor's
  column among them. A factor's levels are refused unless they are a list of one or more
  values a column can hold, of one type, none of them `nil` and none given twice (`4` and `4.0`
  are one); levels of another type than the value's are refused when the plot is run. A
  reordering is refused where either of its values is a constant, a capture or a closure, a factor
  or another reordering, or where `by` is a column that is not numbers. A layer
  whose stat computes nothing, and so documents no variables, refuses every after_stat.

      iex> plot =
      ...>   %{"hwy" => [29, 24], "cty" => [18, 16]}
      ...>   |> Giggly.Plot.new(%{x: :cty, y: {&Kernel.//2, [:hwy, :cty]}})
      ...>   |> Giggly.Plot.geom_point(%{colour: {:constant, "smooth"}})
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :y)
      [1.6111111111111112, 1.5]
      iex> Giggly.DataFrame.pull(frame, :color)
      ["#F8766D", "#F8766D"]

  Each class's share of all the rows, counted as one group:

      iex> plot =
      ...>   %{"class" => ["suv", "compact", "suv", "midsize"]}
      ...>   |> Giggly.Plot.new(%{x: :class, y: {:after_stat, [:prop]}, group: 1})
      ...>   |> Giggly.Plot.geom_bar()
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :y)
      [0.25, 0.25, 0.5]

  The cylinders in the order given, so the axis reads 8, 4, 6:

      iex> plot =
      ...>   %{"cyl" => [4, 6, 8, 4], "mpg" => [26.0, 19.7, 15.0, 30.4]}
      ...>   |> Giggly.Plot.new(%{x: {:factor, [:cyl], levels: [8, 4, 6]}, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      iex> Giggly.panel_scales(plot, 1).x.levels
      [8, 4, 6]

  The classes in order of their mean highway mileage, 19 for the SUVs, 27 and 28:

      iex> plot =
      ...>   %{"class" => ["suv", "compact", "suv", "midsize"], "hwy" => [18, 28, 20, 27]}
      ...>   |> Giggly.Plot.new(%{x: {:reorder, [:class, :hwy]}, y: :hwy})
      ...>   |> Giggly.Plot.geom_point()
      iex> Giggly.panel_scales(plot, 1).x.levels
      ["suv", "midsize", "compact"]

  ## Titles

  A guide is titled by what its aesthetic is mapped to:

    * a column by its name, `cty`;
    * an expression by its text, as Elixir writes the call: a capture of one of `Kernel`'s
      operators as the operator, `hwy / cty`, and any other capture as a call to the function it
      names, `:math.log10(carat)`, as `inspect/1` names it;
    * a function by name as a call to it, `log10(carat)`;
    * an expression whose function is a closure, such as `fn hwy -> hwy * 2 end`, has no text, so
      its guide has no title until `Giggly.Plot.labs/2` gives it one;
    * a factor by its value's text inside `factor()`, `factor(cyl)`, and its options as R writes
      them, `factor(cyl, levels = c(8, 4, 6), ordered = TRUE)`;
    * a reordering as a call to R's `reorder()`, `reorder(class, hwy)`;
    * an after_stat by its value's text, `prop`;
    * a constant by its aesthetic's name, `color`, unless another layer maps the aesthetic to a
      column or an expression, whose title wins.

  So a capture is the form to write where the title should say what was computed, and a closure
  the form to write inline, with a title from `labs/2`.

      iex> svg =
      ...>   %{"carat" => [0.23, 1.5], "price" => [326, 18823]}
      ...>   |> Giggly.Plot.new(%{x: {:log10, [:carat]}, y: {:log10, [:price]}})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> svg =~ ">log10(carat)</text>" and svg =~ ">log10(price)</text>"
      true

      iex> svg =
      ...>   %{"hwy" => [29, 24], "cty" => [18, 16]}
      ...>   |> Giggly.Plot.new(%{x: :cty, y: {&Kernel.//2, [:hwy, :cty]}})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> svg =~ ">hwy / cty</text>"
      true
  """

  # The grammar of a mapping value, and the one place its shapes are matched: `Giggly.Plot` resolves
  # each value as it enters (`resolve/1`) and checks the columns it reads (`columns/1`) and, for a
  # weight, its type where the call can tell it (`dtype/2`), and whether the table it draws can
  # compute it (`check/2`); the assembly evaluates it against a
  # layer's table (`evaluate/2`) and titles its guide (`title/2`). A value is held resolved: a
  # column by its name as a string, a constant as `{:constant, term}`, a factor as
  # `{:factor, [resolved]}`, a reordering as `{:reorder, [resolved, resolved]}`, an after_stat as
  # `{:after_stat, [resolved]}`, an expression as its
  # function or its name and its resolved arguments, a function by name so being an expression
  # the frame computes as it is. When a value is evaluated is its stage (`stage/1`): an
  # after_stat's against its stat's output, every other against the layer's data. A value's
  # kinds differ in what they are, not in how they run, so they are function clauses rather than a
  # protocol. `Plot` calls only the checks; that holds by review, as the assembly's calls into
  # `Coord` and `Geom` do. It lists `Giggly.AsCharacter`, which writes a factor's levels in its
  # title as R writes them.
  use Boundary, deps: [Giggly.AsCharacter, Giggly.DataFrame], exports: []

  alias Giggly.{AsCharacter, DataFrame}
  alias Giggly.DataFrame.Arithmetic

  # Kernel's operators, each with a capture of it, which the compiler turns into a capture of the
  # function the operator is inlined as (`&Kernel.!=/2` is `&:erlang."/="/2`), so a capture of
  # one is titled as Elixir writes the operator whichever function it names.
  @operators [
               {:!=, &Kernel.!=/2},
               {:!==, &Kernel.!==/2},
               {:*, &Kernel.*/2},
               {:**, &Kernel.**/2},
               {:+, &Kernel.+/1},
               {:+, &Kernel.+/2},
               {:++, &Kernel.++/2},
               {:-, &Kernel.-/1},
               {:-, &Kernel.-/2},
               {:--, &Kernel.--/2},
               {:/, &Kernel.//2},
               {:<, &Kernel.</2},
               {:<=, &Kernel.<=/2},
               {:==, &Kernel.==/2},
               {:===, &Kernel.===/2},
               {:=~, &Kernel.=~/2},
               {:>, &Kernel.>/2},
               {:>=, &Kernel.>=/2},
               {:not, &Kernel.not/1}
             ]
             |> Enum.flat_map(fn {operator, capture} ->
               info = Function.info(capture)
               arity = Keyword.fetch!(info, :arity)
               inlined = {Keyword.fetch!(info, :module), Keyword.fetch!(info, :name), arity}
               [{{Kernel, operator, arity}, operator}, {inlined, operator}]
             end)
             |> Map.new()

  # The functions a mapping names by an atom, each with how many arguments it takes: common ones
  # Elixir lacks, which the engine holding the table computes (design-log §4, the entry beginning
  # "A mapping names a function only as a shortcut").
  @functions %{log10: 1}

  @typedoc "A column, named by an atom or a string."
  @type column :: atom() | String.t()

  @typedoc """
  An expression: a function and the values it is applied to in each row, or a function by name
  and the value it is computed from.
  """
  @type expression :: {function(), [value()]} | {:log10, [value()]}

  @typedoc """
  A constant: `{:constant, term}`, or a number, a boolean, a date or a time written alone.
  """
  @type constant ::
          {:constant, term()}
          | number()
          | boolean()
          | Date.t()
          | Time.t()
          | NaiveDateTime.t()
          | DateTime.t()

  @typedoc "A factor: a value read as discrete, with the levels it holds and their order."
  @type factor ::
          {:factor, [value()]} | {:factor, [value()], [levels: [term()], ordered: boolean()]}

  @typedoc "A reordering: a value read as discrete, its levels ordered by another's means."
  @type reordering :: {:reorder, [column() | expression()]}

  @typedoc "An after_stat: a value computed from the stat's computed variables."
  @type after_stat :: {:after_stat, [value()]}

  @typedoc """
  A value as written: a column, an expression, a constant, a factor, a reordering or an
  after_stat.
  """
  @type value :: column() | expression() | constant() | factor() | reordering() | after_stat()

  @typedoc """
  A value as a plot holds it: a column by its name as a string, a constant as `{:constant, term}`,
  and an expression as its function and its arguments, each held so.
  """
  @type resolved ::
          String.t()
          | {:constant, term()}
          | {:factor, [resolved()]}
          | {:factor, [resolved()], [levels: [term()], ordered: boolean()]}
          | {:reorder, [resolved()]}
          | {:after_stat, [resolved()]}
          | {function(), [resolved()]}
          | {:log10, [resolved()]}

  @typedoc "A mapping as a plot holds it: aesthetic to resolved value."
  @type t :: %{optional(atom()) => resolved()}

  # `value` as the plot holds it, or why it is refused, worded to follow "maps :x to …, but".
  @doc false
  @spec resolve(term()) :: {:ok, resolved()} | {:error, String.t()}
  def resolve(value) when is_binary(value), do: {:ok, value}
  def resolve(value) when is_boolean(value), do: constant(value)
  def resolve(nil), do: constant(nil)
  def resolve(value) when is_atom(value), do: {:ok, Atom.to_string(value)}
  def resolve({:constant, term}), do: constant(term)
  def resolve({:factor, [value]}), do: factor(value)
  def resolve({:factor, [value], []}), do: factor(value)

  def resolve({:factor, [value], options}) when is_list(options) do
    with {:ok, {:factor, [resolved]}} <- factor(value),
         :ok <- factor_options(options) do
      {:ok, {:factor, [resolved], options}}
    end
  end

  def resolve({:factor, _arguments}),
    do: {:error, "a factor reads one value, written {:factor, [value]}"}

  def resolve({:factor, _arguments, _options}),
    do:
      {:error,
       "a factor reads one value, with a keyword list of options, written " <>
         "{:factor, [value], levels: [level, ...]}"}

  def resolve({:reorder, [value, by]}) do
    with {:ok, resolved_value} <- reordered(value),
         {:ok, resolved_by} <- reordered(by),
         do: {:ok, {:reorder, [resolved_value, resolved_by]}}
  end

  def resolve({:reorder, _arguments}),
    do: {:error, "a reordering reads two values, written {:reorder, [value, by]}"}

  def resolve({:after_stat, [value]}), do: wrapped(:after_stat, value)

  def resolve({:after_stat, _arguments}),
    do: {:error, "an after_stat reads one value, written {:after_stat, [value]}"}

  def resolve({function, arguments}) when is_function(function) and is_list(arguments),
    do: expression(function, arguments)

  def resolve({name, arguments}) when is_map_key(@functions, name) and is_list(arguments),
    do: named(name, arguments)

  def resolve({function, _arguments})
      when is_function(function) or is_map_key(@functions, function),
      do: {:error, "an expression's arguments are a list of values"}

  def resolve({name, arguments}) when is_atom(name) and is_list(arguments) do
    known = Enum.sort([:after_stat, :constant, :factor, :reorder | functions()])

    {:error,
     "#{inspect(name)} is none of the names a mapping knows " <>
       "(#{Enum.map_join(known, ", ", &inspect/1)}); any other function is a capture, " <>
       "{&Module.function/arity, [values]}"}
  end

  def resolve(value) when is_tuple(value),
    do:
      {:error, "a tuple is an expression, {function, [values]}, or a constant, {:constant, term}"}

  def resolve(value), do: constant(value)

  defp expression(function, arguments) when is_function(function, length(arguments)) do
    with {:ok, resolved} <- each_resolved(arguments, &argument/1), do: {:ok, {function, resolved}}
  end

  defp expression(function, arguments) do
    {:arity, arity} = Function.info(function, :arity)
    arity_error(inspect(function), arity, arguments)
  end

  # A function by name, given as many values as it takes, none of them a function.
  defp named(name, arguments) do
    case Map.fetch!(@functions, name) do
      arity when arity == length(arguments) ->
        with {:ok, resolved} <- each_resolved(arguments, &named_argument/1),
             do: {:ok, {name, resolved}}

      arity ->
        arity_error(Atom.to_string(name), arity, arguments)
    end
  end

  defp arity_error(function_text, arity, arguments) do
    {:error,
     "#{function_text} takes #{arity} argument(s), and the expression gives it " <>
       "#{length(arguments)}"}
  end

  # Each of `arguments` as `resolve_argument` resolves it, or the first refusal.
  defp each_resolved(arguments, resolve_argument) do
    resolved = Enum.map(arguments, resolve_argument)

    case Enum.find(resolved, fn result -> match?({:error, _reason}, result) end) do
      nil -> {:ok, Enum.map(resolved, fn {:ok, argument} -> argument end)}
      error -> error
    end
  end

  # A function by name's argument: any value an expression takes but a capture or a closure, which
  # the table's engine cannot run, so the engine computes a function by name whole.
  defp named_argument({function, _arguments}) when is_function(function),
    do:
      {:error,
       "a function by name is computed by the table's engine, which runs no Elixir function, " <>
         "so its values are columns, constants and functions by name; write the whole as a " <>
         "capture instead, such as {&:math.log10/1, [value]}"}

  defp named_argument(value), do: argument(value)

  # An expression's argument: any value inside another but a factor, which reads a whole column as
  # discrete, as R hands a function its level codes, where a function applied in each row sees one
  # value.
  defp argument(factor) when elem(factor, 0) == :factor,
    do: {:error, "a factor reads a whole column, so it is not an expression's argument"}

  defp argument(reordering) when elem(reordering, 0) == :reorder,
    do: {:error, "a reordering reads whole columns, so it is not an expression's argument"}

  defp argument(value), do: inner(value)

  defp factor(value), do: wrapped(:factor, value)

  # A reordering's value: a column or a function by name, which the table's engine computes, as it
  # computes the means the levels are ordered by; never a constant, since R pairs each row's value
  # with the one beside it ("arguments must have same length"), a capture or a closure, which the
  # engine cannot run, or what reads a whole column itself.
  defp reordered(value) do
    with {:ok, resolved} <- inner(value), do: reorderable(resolved)
  end

  defp reorderable(name) when is_binary(name), do: {:ok, name}
  defp reorderable({name, _arguments} = call) when is_map_key(@functions, name), do: {:ok, call}

  defp reorderable({:constant, _term}),
    do:
      {:error,
       "a reordering orders a column's values by another's in the same rows, so neither of its " <>
         "values is a constant"}

  defp reorderable({function, _arguments}) when is_function(function),
    do:
      {:error,
       "a reordering is computed by the table's engine, which runs no Elixir function, so its " <>
         "values are columns and functions by name"}

  defp reorderable(_factor_or_reordering),
    do:
      {:error,
       "a reordering's values are columns and functions by name, never a factor or another " <>
         "reordering"}

  # A factor's options, `levels:` and `ordered:`, each at most once, as R's `factor()` takes them.
  defp factor_options(options) do
    with :ok <- factor_option_names(options),
         :ok <- each_once(options) do
      first_refusal(options, &factor_option/1)
    end
  end

  defp factor_option_names(options) do
    if Keyword.keyword?(options) and
         Enum.all?(options, fn {name, _value} -> name in [:levels, :ordered] end),
       do: :ok,
       else: {:error, "a factor's options are levels: and ordered:"}
  end

  defp each_once(options) do
    names = Keyword.keys(options)

    if names == Enum.uniq(names),
      do: :ok,
      else: {:error, "a factor's options are each given once"}
  end

  # `:ok` when `check` passes every item, or else its first refusal.
  defp first_refusal(items, check) do
    Enum.find_value(items, :ok, fn item ->
      case check.(item) do
        :ok -> nil
        refusal -> refusal
      end
    end)
  end

  defp factor_option({:ordered, ordered}) when is_boolean(ordered), do: :ok
  defp factor_option({:ordered, _ordered}), do: {:error, "a factor's ordered: is true or false"}

  defp factor_option({:levels, [_first | _rest] = levels}) do
    case first_refusal(levels, &level/1) do
      :ok -> levels_of_one_type(levels)
      refusal -> refusal
    end
  end

  defp factor_option({:levels, _levels}),
    do: {:error, "a factor's levels are a list of one or more values, in order"}

  defp level(nil), do: {:error, "nil is a missing value, never a level"}

  defp level(level) do
    case resolve({:constant, level}) do
      {:ok, _constant} ->
        :ok

      {:error, _reason} ->
        {:error,
         "a level is a value a column can hold: a number, a string, an atom, a boolean, " <>
           "a date or a time"}
    end
  end

  # Levels of one type, as one column holds them, integers and floats being one, and none given
  # twice, `4` and `4.0` being one.
  defp levels_of_one_type(levels) do
    kinds =
      levels
      |> Enum.map(&level_kind/1)
      |> Enum.uniq()

    case {kinds, repeated(levels)} do
      {[_one_kind], :none} ->
        :ok

      {[_one_kind], {:repeated, level}} ->
        {:error, "a factor's level #{inspect(level)} is given twice"}

      {_kinds, _repeated} ->
        {:error, "a factor's levels are all of one type"}
    end
  end

  defp level_kind(level) when is_number(level), do: :number

  defp level_kind(level) do
    case dtype_of(level) do
      :float -> :number
      dtype -> dtype
    end
  end

  # The first level equal to one before it, by `==`, so `4` and `4.0` are one.
  defp repeated(levels) do
    levels
    |> Enum.reduce_while([], &repeated_or_earlier/2)
    |> repetition()
  end

  defp repeated_or_earlier(level, earlier) do
    if Enum.any?(earlier, fn seen -> seen == level end),
      do: {:halt, {:repeated, level}},
      else: {:cont, [level | earlier]}
  end

  defp repetition({:repeated, _level} = repeated), do: repeated
  defp repetition(_earlier), do: :none

  defp wrapped(head, value) do
    case inner(value) do
      {:ok, resolved} -> {:ok, {head, [resolved]}}
      error -> error
    end
  end

  # A value inside another: any but an after_stat, which is evaluated once the stat has run, so it
  # has nothing around it: an expression and a factor are evaluated against the data, and inside an
  # after_stat everything already is against the stat's output.
  defp inner({:after_stat, _arguments}),
    do:
      {:error,
       "an after_stat is the whole of a mapping value, never inside another; put what is " <>
         "around it inside it, {:after_stat, [value]}"}

  defp inner(value), do: resolve(value)

  defp constant(nil), do: {:error, "nil is a missing value, not a column or a constant"}

  defp constant(list) when is_list(list),
    do: {:error, "a list is not a value a mapping takes"}

  defp constant(function) when is_function(function),
    do: {:error, "a function is applied to its arguments, written {function, [values]}"}

  defp constant(term) do
    case dtype_of(term) do
      :term ->
        {:error,
         "a constant is a value a column can hold: a number, a string, an atom, a boolean, " <>
           "a date or a time"}

      _dtype ->
        {:ok, {:constant, term}}
    end
  end

  # The columns `value` reads, each once, in the order it reads them: the layer's data's, or an
  # after_stat's, the stat's computed variables (`stage/1` says which).
  @doc false
  @spec columns(resolved()) :: [String.t()]
  def columns(value) do
    value
    |> column_names()
    |> Enum.uniq()
  end

  defp column_names(name) when is_binary(name), do: [name]
  defp column_names({:constant, _term}), do: []

  # An expression's arguments, or a factor's or an after_stat's one value.
  defp column_names({_function_or_head, arguments}),
    do: Enum.flat_map(arguments, &column_names/1)

  defp column_names({:factor, [value], _options}), do: column_names(value)

  # The functions a mapping names by an atom, each of which the frame computes.
  @doc false
  @spec functions() :: [atom()]
  def functions, do: Map.keys(@functions)

  # Whether `value` can be computed from `table`, the table it is evaluated against, as far as the
  # call can tell, or why not, worded to follow "maps :x to …, but": each function it names by an
  # atom one the engine holding the table runs (`DataFrame.operations/1`), and each of their
  # values whose type the call can tell, a column of the table or a constant, numbers; and for a
  # reordering, the engine's `mean`, and numbers to order by. An after_stat's columns are its
  # stat's output, whose types are known only when the plot is run.
  @doc false
  @spec check(resolved(), DataFrame.t()) :: :ok | {:error, String.t()}
  def check(value, table) do
    operations = DataFrame.operations(table)
    stage = stage(value)

    value
    |> calls()
    |> first_refusal(fn call -> call_refusal(call, operations, table, stage) end)
  end

  # Each function by name `value` calls, with its values, outermost first.
  defp calls(name) when is_binary(name), do: []
  defp calls({:constant, _term}), do: []
  defp calls({:factor, [value], _options}), do: calls(value)

  defp calls({:reorder, [value, by]} = reordering),
    do: [reordering | calls(value) ++ calls(by)]

  defp calls({name, arguments} = call) when is_map_key(@functions, name),
    do: [call | Enum.flat_map(arguments, &calls/1)]

  # An expression's arguments, or a factor's or an after_stat's one value.
  defp calls({_function_or_head, arguments}), do: Enum.flat_map(arguments, &calls/1)

  # A reordering orders its levels by means the engine computes, of numbers.
  defp call_refusal({:reorder, [_value, by]}, operations, table, stage) do
    if :mean in operations,
      do: numbers_refusal("reorder orders by the mean of numbers", by, table, stage),
      else:
        {:error,
         "the engine holding the table cannot compute mean, by which a reordering orders its " <>
           "levels"}
  end

  defp call_refusal({name, arguments}, operations, table, stage) do
    if name in operations,
      do:
        first_refusal(arguments, fn argument ->
          numbers_refusal("#{name} takes numbers", argument, table, stage)
        end),
      else: {:error, "the engine holding the table cannot compute #{name}"}
  end

  # A value that must be numbers, as `needs` says, refused where the call can tell it holds none.
  defp numbers_refusal(needs, argument, table, stage) do
    case known_dtype(argument, table, stage) do
      dtype when dtype in [:integer, :float, :null, :computed] ->
        :ok

      dtype ->
        {:error, "#{needs}, and #{typed_text(argument, dtype)}"}
    end
  end

  defp known_dtype(name, _table, :after_stat) when is_binary(name), do: :computed
  defp known_dtype(value, table, _stage), do: dtype(value, table)

  defp typed_text(name, dtype) when is_binary(name),
    do: "#{inspect(name)} is a #{inspect(dtype)} column"

  defp typed_text({:constant, term}, dtype),
    do: "#{inspect(term)} is a #{inspect(dtype)} constant"

  # The type of the column `value` makes from `table`, the table it is evaluated against (the stat's
  # output for an after_stat, which is known only when the plot is run), where it can be told: a
  # column's own and a constant's, as the frame types them; `:category` for a factor, which the
  # frame is told; `:computed` for an expression, whose function decides it when the plot is run.
  @doc false
  @spec dtype(resolved(), DataFrame.t()) :: DataFrame.dtype() | :computed
  def dtype(name, table) when is_binary(name) do
    table
    |> DataFrame.dtypes()
    |> Map.fetch!(name)
  end

  def dtype({:constant, term}, _table), do: dtype_of(term)
  def dtype({:factor, [_value]}, _table), do: :category
  def dtype({:factor, [_value], _options}, _table), do: :category
  def dtype({:reorder, [_value, _by]}, _table), do: :category
  def dtype({:after_stat, [value]}, statistic), do: dtype(value, by_name(statistic))
  def dtype({_function, _arguments}, _table), do: :computed

  # The type the frame gives a column of `term`, read by building one.
  defp dtype_of(term) do
    [{:constant, [term]}]
    |> DataFrame.new()
    |> DataFrame.dtypes()
    |> Map.fetch!(:constant)
  end

  # What `value` is in each row of `frame`, in row order: a column's values, a constant in every
  # row, a function by name as the frame computes it, or an expression's function applied in each
  # row to its arguments' values there, a function of no arguments called once per row. An
  # after_stat's `frame` is its stat's output.
  @doc false
  @spec evaluate(resolved(), DataFrame.t()) :: list()
  def evaluate(name, frame) when is_binary(name), do: DataFrame.pull(frame, name)

  def evaluate({:constant, term}, frame),
    do: List.duplicate(term, DataFrame.row_count(frame))

  def evaluate({:factor, [value]}, frame), do: evaluate(value, frame)
  def evaluate({:factor, [value], _options}, frame), do: evaluate(value, frame)
  def evaluate({:reorder, [value, _by]}, frame), do: evaluate(value, frame)
  def evaluate({:after_stat, [value]}, statistic), do: evaluate(value, by_name(statistic))

  # A function by name is computed by the frame, whose expression it already is: its columns by
  # name, its constants and its functions by name. Its column is named by an atom, which no column
  # of a table is.
  def evaluate({name, _arguments} = expression, frame) when is_map_key(@functions, name) do
    frame
    |> DataFrame.mutate(evaluated: expression)
    |> DataFrame.pull(:evaluated)
  end

  def evaluate({function, []}, frame) do
    rows = DataFrame.row_count(frame)

    []
    |> List.duplicate(rows)
    |> Enum.map(fn no_arguments -> apply(function, no_arguments) end)
  end

  def evaluate({function, arguments}, frame) do
    arguments
    |> Enum.map(fn argument -> evaluate(argument, frame) end)
    |> Enum.zip_with(fn row -> apply(function, row) end)
  end

  # The stat's output with its columns, which Giggly names by atoms, named by strings, as a mapping
  # holds the names its values read.
  defp by_name(statistic) do
    renames =
      statistic
      |> DataFrame.names()
      |> Enum.map(fn name -> {Atom.to_string(name), name} end)

    DataFrame.select(statistic, renames)
  end

  # How the column `value` makes from `table` is declared a category when it enters a frame
  # (`t:Giggly.DataFrame.category/0`): a column of the table that is a category as the table
  # declares it, levels and all; a factor with the levels it gives and whether it is ordered, each
  # it leaves out kept from its value's where that is a category, as R's `factor()` of a factor
  # keeps its levels' order and `is.ordered()`; an after_stat's as its value's in the stat's
  # output; `:none` for any other value, whose type the frame reads from its values.
  @doc false
  @spec category(resolved(), DataFrame.t()) :: DataFrame.category() | :none
  def category(name, table) when is_binary(name) do
    case DataFrame.dtypes(table) do
      %{^name => :category} -> DataFrame.category(table, name)
      %{} -> :none
    end
  end

  def category({:factor, [value]}, table), do: factor_category(category(value, table), [])

  def category({:factor, [value], options}, table),
    do: factor_category(category(value, table), options)

  def category({:reorder, [value, by]}, table), do: reordered_category(value, by, table)
  def category({:after_stat, [value]}, statistic), do: category(value, by_name(statistic))
  def category(_value, _table), do: :none

  # A reordering's declaration: the levels the factor of `value` holds, a category's own, ordered
  # by the mean of `by` over each one's rows (`DataFrame.summarise/3`'s, R's `mean()`), the lowest
  # first, minus infinity before every number and infinity after, those that tie in the order they
  # held, and those whose mean is missing, `nil` or NaN, or that no row holds, last, as R's
  # `reorder()` sorts its scores; ordered where `value` is an ordered category. The frame computes
  # the means, and only their summary, a row for each value, is read here.
  defp reordered_category(value, by, table) do
    declared =
      case category(value, table) do
        :none -> :category
        category -> category
      end

    summary =
      table
      |> DataFrame.mutate(ordering: by)
      |> DataFrame.put(:reordered, evaluate(value, table), declared)
      |> DataFrame.summarise([:reordered], mean: {:mean, [:ordering]})

    {:category, levels: levels, ordered: ordered} = DataFrame.category(summary, :reordered)

    means =
      summary
      |> DataFrame.pull(:reordered)
      |> Enum.zip_with(DataFrame.pull(summary, :mean), fn level, mean -> {level, mean} end)
      |> Map.new()

    ordered_levels =
      levels
      |> Enum.with_index()
      |> Enum.sort_by(fn {level, index} ->
        mean = Map.get(means, level)
        {Arithmetic.sort_key(mean), index}
      end)
      |> Enum.map(fn {level, _index} -> level end)

    {:category, levels: ordered_levels, ordered: ordered}
  end

  defp factor_category({:category, inherited}, options),
    do: {:category, Keyword.merge(inherited, options)}

  defp factor_category(:none, []), do: :category
  defp factor_category(:none, options), do: {:category, options}

  # When `value` is evaluated, its stage, as ggplot2's `stage()` names them: `:after_stat` against
  # its stat's output, once the stat has run; `:start`, every other, against the layer's data.
  @doc false
  @spec stage(resolved()) :: :start | :after_stat
  def stage({:after_stat, [_value]}), do: :after_stat
  def stage(_value), do: :start

  # The title `value` gives the guide of `aesthetic`, as ggplot2's `make_labels()` gives it:
  # `{:title, text}` for a column, an expression, a factor or an after_stat, its text (an
  # after_stat's its value's, as ggplot2 strips `after_stat()`), or `:none` for one with a
  # closure in it, which has none; `{:fallback, name}` for a constant, the aesthetic's own name,
  # which ggplot2 marks as a fallback any layer's title replaces.
  @doc false
  @spec title(resolved(), atom()) :: {:title, String.t() | :none} | {:fallback, String.t()}
  def title({:constant, _term}, aesthetic), do: {:fallback, Atom.to_string(aesthetic)}
  def title(value, _aesthetic), do: {:title, text(value)}

  defp text(name) when is_binary(name), do: name
  defp text({:constant, term}), do: inspect(term)

  defp text({:after_stat, [value]}), do: text(value)

  defp text({:factor, [value]}), do: text({:factor, [value], []})

  defp text({:factor, [value], options}) do
    case text(value) do
      :none -> :none
      written -> "factor(#{Enum.join([written | Enum.map(options, &option_text/1)], ", ")})"
    end
  end

  defp text({:reorder, [value, by]}), do: "reorder(#{text(value)}, #{text(by)})"

  # A function by name takes one value, as every one so far does.
  defp text({name, [value]}) when is_map_key(@functions, name), do: "#{name}(#{text(value)})"

  defp text({function, arguments}) do
    texts = Enum.map(arguments, &text/1)

    if Function.info(function, :type) == {:type, :external} and :none not in texts,
      do: call_text(function, arguments, texts),
      else: :none
  end

  # A capture's call as Elixir writes it: an operator between or before its operands, an operand
  # that is itself an operator's call in parentheses, so the text reads as it computes; any other
  # function called by its module and name.
  defp call_text(function, arguments, texts) do
    {module, name, _arity} = key = function_key(function)

    case Map.fetch(@operators, key) do
      {:ok, operator} ->
        arguments
        |> Enum.zip_with(texts, &operand_text/2)
        |> operator_text(operator)

      :error ->
        "#{inspect(module)}.#{Macro.inspect_atom(:remote_call, name)}(#{Enum.join(texts, ", ")})"
    end
  end

  # A factor's option as R writes the argument, `levels = c(8, 4, 6)`, `ordered = TRUE`.
  defp option_text({:levels, levels}),
    do: "levels = c(#{Enum.map_join(levels, ", ", &level_text/1)})"

  defp option_text({:ordered, true}), do: "ordered = TRUE"
  defp option_text({:ordered, false}), do: "ordered = FALSE"

  # A level as R writes it in a call: a string in quotes, as `deparse()` writes one, any other value
  # as R's `as.character()` writes it (`8`, `1e+05`, `TRUE`).
  defp level_text(level) when is_binary(level), do: inspect(level)
  defp level_text(level), do: AsCharacter.text(level)

  defp operand_text(argument, text) do
    if operator?(argument), do: "(#{text})", else: text
  end

  defp operator_text([operand], :not), do: "not #{operand}"
  defp operator_text([operand], operator), do: "#{operator}#{operand}"
  defp operator_text([left, right], operator), do: "#{left} #{operator} #{right}"

  defp operator?({function, _arguments}) when is_function(function),
    do: Map.has_key?(@operators, function_key(function))

  defp operator?(_column_or_constant), do: false

  defp function_key(function) do
    info = Function.info(function)
    {Keyword.fetch!(info, :module), Keyword.fetch!(info, :name), Keyword.fetch!(info, :arity)}
  end
end
