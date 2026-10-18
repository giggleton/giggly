defmodule Giggly.Mapping do
  @moduledoc """
  What a mapping maps each aesthetic to: a column, an expression computed from columns in each
  row, or a constant. A mapping is a map from aesthetic to value, as ggplot2's `aes()` is:

      %{x: :displ, y: {&Kernel.//2, [:hwy, :cty]}, colour: {:constant, "smooth"}}

  is ggplot2's `aes(displ, hwy / cty, colour = "smooth")`.

  ## Values

    * **A column** is named by an atom or a string, compared with the table's column names as a
      string, so `:hwy` and `"hwy"` name the same column. `true`, `false` and `nil` name none.
    * **An expression**, `{function, [value, ...]}`, is the function applied in each row to what
      its arguments are in that row, as ggplot2's `aes(y = hwy / cty)` divides each row's `hwy` by
      its `cty`. Each argument is a value, so it may be a column, a constant or another expression,
      and the function takes as many arguments as it is given.
    * **A constant**, `{:constant, term}`, is the term in every row. A number, a boolean, a date or
      a time is a constant written alone; a string or an atom would name a column, so a constant
      one is written `{:constant, "smooth"}`, as ggplot2's `aes(colour = "smooth")` maps every row
      to one level.
    * **A factor**, `{:factor, [value]}`, is the value read as discrete, as ggplot2's
      `aes(colour = factor(cyl))` reads a column of numbers as levels: a discrete scale whatever
      the values, its levels in order of value with a missing one last, each written as R writes
      it (`4`, `0.5`, `TRUE`), and the rows grouped by them. A factor reads a whole column, so it
      is the whole of a mapping value or a factor's own, never an expression's argument, where R
      hands a function its levels' codes rather than its values.

  A constant is a value a column can hold: `nil`, a list, and a value with no column type of its
  own (a map, a tuple, a struct other than a date or a time) are refused, and so are a function
  alone, a tuple that is neither an expression nor a constant, and a function given a number of
  arguments it does not take.

      iex> plot =
      ...>   %{"hwy" => [29, 24], "cty" => [18, 16]}
      ...>   |> Giggly.Plot.new(%{x: :cty, y: {&Kernel.//2, [:hwy, :cty]}})
      ...>   |> Giggly.Plot.geom_point(%{colour: {:constant, "smooth"}})
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :y)
      [1.6111111111111112, 1.5]
      iex> Giggly.DataFrame.pull(frame, :color)
      ["#F8766D", "#F8766D"]

  ## Titles

  A guide is titled by what its aesthetic is mapped to, as ggplot2 titles it by the expression's
  text:

    * a column by its name, `cty`;
    * an expression by its text, as Elixir writes the call: a capture of one of `Kernel`'s
      operators as the operator, `hwy / cty`, and any other capture as a call to the function it
      names, `:math.log10(carat)`, as `inspect/1` names it;
    * an expression whose function is a closure, such as `fn hwy -> hwy * 2 end`, has no text, so
      its guide has no title until `Giggly.Plot.labs/2` gives it one;
    * a factor by its value's text inside `factor()`, `factor(cyl)`;
    * a constant by its aesthetic's name, `color`, unless another layer maps the aesthetic to a
      column or an expression, whose title wins, as ggplot2 titles a constant.

  So a capture is the form to write where the title should say what was computed, and a closure
  the form to write inline, with a title from `labs/2`.

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
  # weight, its type where the call can tell it (`dtype/2`); the assembly evaluates it against a
  # layer's table (`evaluate/2`) and titles its guide (`title/2`). A value is held resolved: a
  # column by its name as a string, a constant as `{:constant, term}`, a factor as
  # `{:factor, [resolved]}`, an expression as its function and its resolved arguments. A value's
  # kinds differ in what they are, not in how they run, so they are function clauses rather than a
  # protocol. `Plot` calls only the checks; that holds by review, as the assembly's calls into
  # `Coord` and `Geom` do.
  use Boundary, deps: [Giggly.DataFrame], exports: []

  alias Giggly.DataFrame

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

  @typedoc "A column, named by an atom or a string."
  @type column :: atom() | String.t()

  @typedoc "An expression: a function and the values it is applied to in each row."
  @type expression :: {function(), [value()]}

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

  @typedoc "A factor: a value read as discrete."
  @type factor :: {:factor, [value()]}

  @typedoc "A value as written: a column, an expression, a constant or a factor."
  @type value :: column() | expression() | constant() | factor()

  @typedoc """
  A value as a plot holds it: a column by its name as a string, a constant as `{:constant, term}`,
  and an expression as its function and its arguments, each held so.
  """
  @type resolved ::
          String.t() | {:constant, term()} | {:factor, [resolved()]} | {function(), [resolved()]}

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

  def resolve({:factor, _arguments}),
    do: {:error, "a factor reads one value, written {:factor, [value]}"}

  def resolve({function, arguments}) when is_function(function) and is_list(arguments),
    do: expression(function, arguments)

  def resolve({function, _arguments}) when is_function(function),
    do: {:error, "an expression's arguments are a list of values"}

  def resolve(value) when is_tuple(value),
    do:
      {:error, "a tuple is an expression, {function, [values]}, or a constant, {:constant, term}"}

  def resolve(value), do: constant(value)

  defp expression(function, arguments) when is_function(function, length(arguments)) do
    resolved = Enum.map(arguments, &argument/1)

    case Enum.find(resolved, fn result -> match?({:error, _reason}, result) end) do
      nil -> {:ok, {function, Enum.map(resolved, fn {:ok, argument} -> argument end)}}
      error -> error
    end
  end

  defp expression(function, arguments) do
    {:arity, arity} = Function.info(function, :arity)

    {:error,
     "#{inspect(function)} takes #{arity} argument(s), and the expression gives it " <>
       "#{length(arguments)}"}
  end

  # An expression's argument: any value but a factor, which reads a whole column as discrete, as
  # R hands a function its level codes, where a function applied in each row sees one value.
  defp argument({:factor, _arguments}),
    do: {:error, "a factor reads a whole column, so it is not an expression's argument"}

  defp argument(value), do: resolve(value)

  defp factor(value) do
    case resolve(value) do
      {:ok, resolved} -> {:ok, {:factor, [resolved]}}
      error -> error
    end
  end

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

  # The columns `value` reads, each once, in the order it reads them.
  @doc false
  @spec columns(resolved()) :: [String.t()]
  def columns(value) do
    value
    |> column_names()
    |> Enum.uniq()
  end

  defp column_names(name) when is_binary(name), do: [name]
  defp column_names({:constant, _term}), do: []

  # An expression's arguments, or a factor's one value.
  defp column_names({_function_or_factor, arguments}),
    do: Enum.flat_map(arguments, &column_names/1)

  # The type of the column `value` makes from `table`, where the call can tell it: a column's own
  # and a constant's, as the frame types them; `:category` for a factor, which the frame is told;
  # `:computed` for an expression, whose function decides it when the plot is run.
  @doc false
  @spec dtype(resolved(), DataFrame.t()) :: DataFrame.dtype() | :computed
  def dtype(name, table) when is_binary(name) do
    table
    |> DataFrame.dtypes()
    |> Map.fetch!(name)
  end

  def dtype({:constant, term}, _table), do: dtype_of(term)
  def dtype({:factor, [_value]}, _table), do: :category
  def dtype({_function, _arguments}, _table), do: :computed

  # The type the frame gives a column of `term`, read by building one.
  defp dtype_of(term) do
    [{:constant, [term]}]
    |> DataFrame.new()
    |> DataFrame.dtypes()
    |> Map.fetch!(:constant)
  end

  # What `value` is in each row of `frame`, in row order: a column's values, a constant in every
  # row, or an expression's function applied in each row to its arguments' values there, a
  # function of no arguments called once per row.
  @doc false
  @spec evaluate(resolved(), DataFrame.t()) :: list()
  def evaluate(name, frame) when is_binary(name), do: DataFrame.pull(frame, name)

  def evaluate({:constant, term}, frame),
    do: List.duplicate(term, DataFrame.row_count(frame))

  def evaluate({:factor, [value]}, frame), do: evaluate(value, frame)

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

  # The title `value` gives the guide of `aesthetic`, as ggplot2's `make_labels()` gives it:
  # `{:title, text}` for a column, an expression or a factor, its text, or `:none` for one with a
  # closure in it, which has none; `{:fallback, name}` for a constant, the aesthetic's own name,
  # which ggplot2 marks as a fallback any layer's title replaces.
  @doc false
  @spec title(resolved(), atom()) :: {:title, String.t() | :none} | {:fallback, String.t()}
  def title({:constant, _term}, aesthetic), do: {:fallback, Atom.to_string(aesthetic)}
  def title(value, _aesthetic), do: {:title, text(value)}

  defp text(name) when is_binary(name), do: name
  defp text({:constant, term}), do: inspect(term)

  defp text({:factor, [value]}) do
    case text(value) do
      :none -> :none
      written -> "factor(#{written})"
    end
  end

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
