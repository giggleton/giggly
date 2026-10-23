defmodule Giggly.MappingTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Mapping}

  doctest Giggly.Mapping

  @frame DataFrame.new([{"hwy", [29, 24, 31]}, {"cty", [18, 16, 21]}, {"class", ["a", "b", "a"]}])

  # A stat's output, its columns named by atoms as every column Giggly computes is.
  @statistic DataFrame.new(count: [1.0, 3.0], prop: [0.25, 0.75], x: [1, 2])

  # A frame implementation standing in for an engine that computes none of the functions a mapping
  # names, as no frame Giggly has yet is: it answers only which operations it runs.
  defmodule Engine do
    defstruct []

    def operations(%__MODULE__{}), do: [:and, :or]
  end

  describe "resolve/1" do
    test "a column named by an atom or a string is held by its name as a string" do
      assert {Mapping.resolve(:hwy), Mapping.resolve("hwy")} === {{:ok, "hwy"}, {:ok, "hwy"}}
    end

    test "a number, a boolean or a date written alone is a constant, not a column of that name" do
      assert Enum.map([7, 2.5, true, false, ~D[2020-01-01]], &Mapping.resolve/1) === [
               {:ok, {:constant, 7}},
               {:ok, {:constant, 2.5}},
               {:ok, {:constant, true}},
               {:ok, {:constant, false}},
               {:ok, {:constant, ~D[2020-01-01]}}
             ]
    end

    test "a string or an atom wrapped as a constant is the term itself, not a column" do
      assert {Mapping.resolve({:constant, "smooth"}), Mapping.resolve({:constant, :smooth})} ===
               {{:ok, {:constant, "smooth"}}, {:ok, {:constant, :smooth}}}
    end

    test "an expression is held with each argument resolved, an expression within it too" do
      divide = &Kernel.//2
      add = &Kernel.+/2

      assert Mapping.resolve({divide, [{add, [:hwy, 1]}, "cty"]}) ===
               {:ok, {divide, [{add, ["hwy", {:constant, 1}]}, "cty"]}}
    end

    test "nil, a list, a function alone and a value with no column type are refused, each so" do
      refusals = [
        {nil, "nil is a missing value"},
        {{:constant, nil}, "nil is a missing value"},
        {[:hwy], "a list"},
        {{:constant, [1]}, "a list"},
        {&String.upcase/1, "applied to its arguments"},
        {{:constant, &String.upcase/1}, "applied to its arguments"},
        {%{a: 1}, "a value a column can hold"},
        {{:constant, {1}}, "a value a column can hold"}
      ]

      for {value, cause} <- refusals do
        assert {:error, reason} = Mapping.resolve(value)
        assert reason =~ cause
      end
    end

    test "a tuple that is neither an expression nor a constant is refused" do
      assert {:error, reason} = Mapping.resolve({"cyl", [:cyl]})
      assert reason =~ "a tuple is an expression"
    end

    test "an atom naming nothing a mapping knows is refused, naming each it knows" do
      for name <- [:fctor, :sqrt] do
        assert {:error, reason} = Mapping.resolve({name, [:cyl]})
        assert reason =~ "#{inspect(name)} is none of the names a mapping knows"
        assert reason =~ ":after_stat, :constant, :factor, :log10"
        assert reason =~ "a capture, {&Module.function/arity, [values]}"
      end
    end

    test "a function by name is held with its value resolved, inside an expression too" do
      multiply = &Kernel.*/2

      assert Enum.map(
               [
                 {:log10, [:carat]},
                 {:log10, [{:log10, [:price]}]},
                 {:log10, [100]},
                 {multiply, [{:log10, [:price]}, 2]}
               ],
               &Mapping.resolve/1
             ) === [
               {:ok, {:log10, ["carat"]}},
               {:ok, {:log10, [{:log10, ["price"]}]}},
               {:ok, {:log10, [{:constant, 100}]}},
               {:ok, {multiply, [{:log10, ["price"]}, {:constant, 2}]}}
             ]
    end

    test "a capture or a closure inside a function by name is refused, the engine computing it" do
      inside = [
        {:log10, [{&Kernel.+/2, [:price, 1]}]},
        {:log10, [{fn price -> price + 1 end, [:price]}]},
        {:log10, [{:log10, [{&Kernel.+/2, [:price, 1]}]}]}
      ]

      for value <- inside do
        assert {:error, reason} = Mapping.resolve(value)
        assert reason =~ "computed by the table's engine, which runs no Elixir function"
        assert reason =~ "{&:math.log10/1, [value]}"
      end
    end

    test "a function by name given values not in a list, or other than one, is refused" do
      assert {:error, not_a_list} = Mapping.resolve({:log10, :carat})
      assert {:error, two} = Mapping.resolve({:log10, [:hwy, :cty]})
      assert {:error, none} = Mapping.resolve({:log10, []})

      assert not_a_list =~ "arguments are a list"
      assert two =~ "log10 takes 1 argument(s), and the expression gives it 2"
      assert none =~ "gives it 0"
    end

    test "a factor or an after_stat inside a function by name is refused, as in any expression" do
      assert {:error, factor} = Mapping.resolve({:log10, [{:factor, [:cyl]}]})
      assert {:error, after_stat} = Mapping.resolve({:log10, [{:after_stat, [:count]}]})

      assert factor =~ "a factor reads a whole column"
      assert after_stat =~ "an after_stat is the whole of a mapping value"
    end

    test "an expression whose arguments are not a list is refused" do
      assert {:error, reason} = Mapping.resolve({&String.upcase/1, :class})
      assert reason =~ "arguments are a list"
    end

    test "a function given a number of arguments it does not take is refused, naming it" do
      assert {:error, reason} = Mapping.resolve({&String.upcase/1, [:class, :hwy]})
      assert reason =~ "&String.upcase/1 takes 1"
      assert reason =~ "gives it 2"
    end

    test "a factor is held with its value resolved, a factor's own included" do
      add = &Kernel.+/2

      assert {Mapping.resolve({:factor, [:cyl]}), Mapping.resolve({:factor, [{add, [:cyl, 1]}]}),
              Mapping.resolve({:factor, [{:factor, [:cyl]}]})} ===
               {{:ok, {:factor, ["cyl"]}}, {:ok, {:factor, [{add, ["cyl", {:constant, 1}]}]}},
                {:ok, {:factor, [{:factor, ["cyl"]}]}}}
    end

    test "a factor of anything but one value is refused" do
      for value <- [{:factor, [:cyl, :gear]}, {:factor, []}, {:factor, :cyl}] do
        assert {:error, reason} = Mapping.resolve(value)
        assert reason =~ "a factor reads one value"
      end
    end

    # R hands a function a factor's level codes: `as.numeric(factor(c(10, 9, 100)))` is 2, 1, 3.
    test "a factor as an expression's argument is refused, since it reads a whole column" do
      assert {:error, reason} = Mapping.resolve({&Kernel.+/2, [{:factor, [:cyl]}, 1]})
      assert reason =~ "a factor reads a whole column"
    end

    test "a factor's refused value refuses it, with the value's reason" do
      assert {:error, reason} = Mapping.resolve({:factor, [nil]})
      assert reason =~ "nil is a missing value"
    end

    test "a factor with levels and ordered is held with its options as given" do
      assert {Mapping.resolve({:factor, [:cyl], levels: [8, 4, 6], ordered: true}),
              Mapping.resolve({:factor, [:cut], ordered: true, levels: ["Fair", "Good"]}),
              Mapping.resolve({:factor, [:cyl], []})} ===
               {{:ok, {:factor, ["cyl"], [levels: [8, 4, 6], ordered: true]}},
                {:ok, {:factor, ["cut"], [ordered: true, levels: ["Fair", "Good"]]}},
                {:ok, {:factor, ["cyl"]}}}
    end

    # R's `factor(1:3, levels = c(1, 1, 2))` fails: "factor level [2] is duplicated".
    test "a factor's options are refused unless levels of one type, none twice, and a flag" do
      refused = [
        {[level: [4]], "a factor's options are levels: and ordered:"},
        {[levels: [4], level: [6]], "a factor's options are levels: and ordered:"},
        {[{"levels", [4]}], "a factor's options are levels: and ordered:"},
        {[levels: [4], levels: [6]], "a factor's options are each given once"},
        {[levels: []], "a factor's levels are a list of one or more values"},
        {[levels: 4], "a factor's levels are a list of one or more values"},
        {[levels: [4, nil]], "nil is a missing value, never a level"},
        {[levels: [4, %{}]], "a level is a value a column can hold"},
        {[levels: [4, [6]]], "a level is a value a column can hold"},
        {[levels: [4, "6"]], "a factor's levels are all of one type"},
        {[levels: [4, 6, 4.0]], "a factor's level 4.0 is given twice"},
        {[ordered: "yes"], "a factor's ordered: is true or false"}
      ]

      for {options, reason} <- refused do
        assert {:error, refusal} = Mapping.resolve({:factor, [:cyl], options})
        assert refusal =~ reason
      end

      assert {:error, refusal} = Mapping.resolve({:factor, [:cyl], :levels})
      assert refusal =~ "with a keyword list of options"
    end

    test "a factor's levels may mix integers and floats, NaN among them, as a column does" do
      assert {:ok, _factor} = Mapping.resolve({:factor, [:x], levels: [1, 2.5, :nan]})
    end

    test "a factor with levels as an expression's argument is refused too" do
      assert {:error, reason} =
               Mapping.resolve({&Kernel.+/2, [{:factor, [:cyl], levels: [4]}, 1]})

      assert reason =~ "a factor reads a whole column"
    end

    test "a refused argument refuses the expression, with the argument's reason" do
      assert {:error, reason} = Mapping.resolve({&Kernel.//2, [:hwy, nil]})
      assert reason =~ "nil is a missing value"
    end

    test "an after_stat is held with its value resolved, an expression or a factor in it too" do
      multiply = &Kernel.*/2

      assert {Mapping.resolve({:after_stat, [:prop]}),
              Mapping.resolve({:after_stat, [{multiply, [:prop, 100]}]}),
              Mapping.resolve({:after_stat, [{:factor, [:count]}]})} ===
               {{:ok, {:after_stat, ["prop"]}},
                {:ok, {:after_stat, [{multiply, ["prop", {:constant, 100}]}]}},
                {:ok, {:after_stat, [{:factor, ["count"]}]}}}
    end

    test "an after_stat of anything but one value is refused" do
      for value <- [{:after_stat, [:count, :prop]}, {:after_stat, []}, {:after_stat, :count}] do
        assert {:error, reason} = Mapping.resolve(value)
        assert reason =~ "an after_stat reads one value"
      end
    end

    # ggplot2 4.0.3 in R 4.6.1 computes `after_stat(count) * 2` as `after_stat(count * 2)`; the
    # grammar has one way to write it, the whole value inside.
    test "an after_stat inside an expression, a factor or another after_stat is refused" do
      after_stat = {:after_stat, [:count]}

      for value <- [
            {&Kernel.*/2, [after_stat, 2]},
            {:factor, [after_stat]},
            {:after_stat, [after_stat]}
          ] do
        assert {:error, reason} = Mapping.resolve(value)
        assert reason =~ "an after_stat is the whole of a mapping value"
      end
    end

    test "an after_stat's refused value refuses it, with the value's reason" do
      assert {:error, reason} = Mapping.resolve({:after_stat, [nil]})
      assert reason =~ "nil is a missing value"
    end
  end

  describe "stage/1" do
    test "an after_stat is evaluated after the stat, every other value at the start" do
      assert Enum.map(
               [{:after_stat, ["count"]}, "cty", {:constant, 7}, {:factor, ["cyl"]}],
               &Mapping.stage/1
             ) === [:after_stat, :start, :start, :start]
    end
  end

  describe "columns/1" do
    test "the columns a value reads, each once, in the order it reads them" do
      {:ok, value} = Mapping.resolve({&Kernel.//2, [{&Kernel.-/2, [:hwy, :cty]}, :hwy]})

      assert {Mapping.columns(value), Mapping.columns("cty"), Mapping.columns({:constant, 7}),
              Mapping.columns({:factor, ["cyl"]})} === {["hwy", "cty"], ["cty"], [], ["cyl"]}
    end

    test "a factor with levels reads its value's columns" do
      assert Mapping.columns({:factor, ["cyl"], levels: [8, 4]}) === ["cyl"]
    end

    test "a function by name reads its value's columns" do
      assert Mapping.columns({:log10, [{:log10, ["price"]}]}) === ["price"]
    end

    test "an after_stat's columns are the stat's variables its value reads" do
      {:ok, value} = Mapping.resolve({:after_stat, [{&Kernel.//2, [:count, :prop]}]})

      assert Mapping.columns(value) === ["count", "prop"]
    end
  end

  describe "dtype/2" do
    test "a column's type is its table's, a constant's its own; an expression's is not known" do
      {:ok, expression} = Mapping.resolve({&Kernel.//2, [:hwy, :cty]})

      assert {Mapping.dtype("class", @frame), Mapping.dtype({:constant, 2.5}, @frame),
              Mapping.dtype(expression, @frame)} === {:string, :float, :computed}
    end

    test "a function by name's type is not known at the call, as an expression's" do
      assert Mapping.dtype({:log10, ["hwy"]}, @frame) === :computed
    end

    test "a factor's type is a category, whatever its value's" do
      assert Mapping.dtype({:factor, ["hwy"]}, @frame) === :category
    end

    test "a factor with levels is a category too" do
      assert Mapping.dtype({:factor, ["hwy"], levels: [31, 29]}, @frame) === :category
    end

    test "an after_stat's type is its value's in the stat's output, whose columns are atoms" do
      assert {Mapping.dtype({:after_stat, ["count"]}, @statistic),
              Mapping.dtype({:after_stat, [{:factor, ["count"]}]}, @statistic)} ===
               {:float, :category}
    end
  end

  describe "functions/0" do
    test "the frame computes every function a mapping names" do
      assert Mapping.functions() -- DataFrame.operations(@frame) === []
    end
  end

  describe "check/2" do
    test "a function by name given numbers, a column, a constant or itself, can be computed" do
      table = DataFrame.new([{"hwy", [29, 24]}, {"weight", [2.5, nil]}, {"gap", [nil, nil]}])

      values = [
        "hwy",
        {:log10, ["hwy"]},
        {:log10, ["weight"]},
        {:log10, ["gap"]},
        {:log10, [{:constant, 100}]},
        {:log10, [{:log10, ["hwy"]}]},
        {:factor, [{:log10, ["hwy"]}]}
      ]

      assert Enum.map(values, fn value -> Mapping.check(value, table) end) ===
               List.duplicate(:ok, 7)
    end

    # R's log10() fails on text ("non-numeric argument to mathematical function"), a factor
    # ("'log10' not meaningful for factors") and a date; it reads TRUE as 1, Giggly's frame, as
    # Explorer's, never reading a boolean as a number.
    test "a function by name given a column or a constant that is not numbers is refused" do
      table =
        DataFrame.new([
          {"class", ["suv", "compact"]},
          {"cut", ["Fair", "Good"], :category},
          {"day", [~D[2026-10-22], ~D[2026-10-23]]},
          {"am", [true, false]}
        ])

      refusals = [
        {{:log10, ["class"]}, ~s{log10 takes numbers, and "class" is a :string column}},
        {{:log10, ["cut"]}, ~s{"cut" is a :category column}},
        {{:log10, ["day"]}, ~s{"day" is a :date column}},
        {{:log10, ["am"]}, ~s{"am" is a :boolean column}},
        {{:log10, [{:constant, true}]}, "true is a :boolean constant"},
        {{:log10, [{:log10, [{:constant, "a"}]}]}, ~s{"a" is a :string constant}},
        {{:factor, [{:log10, ["class"]}], ordered: true}, ~s{"class" is a :string column}},
        {{&Kernel.*/2, [{:log10, ["class"]}, {:constant, 2}]}, ~s{"class" is a :string column}}
      ]

      for {value, cause} <- refusals do
        assert {:error, reason} = Mapping.check(value, table)
        assert reason =~ cause
      end
    end

    test "an after_stat's columns are the stat's output, unknown at the call, its constants not" do
      table = DataFrame.new([{"count", ["a", "b"]}])

      assert Mapping.check({:after_stat, [{:log10, ["count"]}]}, table) === :ok

      assert {:error, reason} =
               Mapping.check({:after_stat, [{:log10, [{:constant, "a"}]}]}, table)

      assert reason =~ ~s{"a" is a :string constant}
    end

    test "a function by name the table's engine cannot compute is refused, naming it" do
      assert Mapping.check({:factor, ["hwy"]}, %Engine{}) === :ok

      assert Mapping.check({:after_stat, [{:log10, ["count"]}]}, %Engine{}) ===
               {:error, "the engine holding the table cannot compute log10"}
    end
  end

  describe "evaluate/2" do
    test "a column is its values, and a constant is the term in every row" do
      assert {Mapping.evaluate("cty", @frame), Mapping.evaluate({:constant, "smooth"}, @frame)} ===
               {[18, 16, 21], ["smooth", "smooth", "smooth"]}
    end

    test "an expression is its function applied in each row to its arguments' values there" do
      {:ok, value} = Mapping.resolve({&Kernel.-/2, [{&Kernel.*/2, [:hwy, 2]}, :cty]})

      assert Mapping.evaluate(value, @frame) === [40, 32, 41]
    end

    test "a factor is its value's values, which the frame is told are a category" do
      assert Mapping.evaluate({:factor, ["hwy"]}, @frame) === [29, 24, 31]
    end

    test "a factor with levels is its value's values, the frame told its levels" do
      assert Mapping.evaluate({:factor, ["hwy"], levels: [31, 29]}, @frame) === [29, 24, 31]
    end

    test "a function by name is what the frame computes, R's log10 at zero, below it and missing" do
      frame = DataFrame.new([{"carat", [1000, 0.0, -1.0, nil]}])
      {:ok, nested} = Mapping.resolve({&Kernel.*/2, [{:log10, [:hwy]}, 2]})

      # R's log10(c(29, 24, 31)) * 2, as Erlang's :math.log10 gives it, digit for digit.
      assert {Mapping.evaluate({:log10, ["carat"]}, frame), Mapping.evaluate(nested, @frame)} ===
               {[3.0, :neg_infinity, :nan, nil],
                [2.924795995797912, 2.760422483423212, 2.9827233876685453]}
    end

    test "a function of no arguments gives a value in every row" do
      assert Mapping.evaluate({fn -> 1 end, []}, @frame) === [1, 1, 1]
    end

    test "an after_stat is its value in each row of the stat's output, read by its names" do
      {:ok, value} = Mapping.resolve({:after_stat, [{&Kernel.*/2, [:prop, 100]}]})

      assert {Mapping.evaluate(value, @statistic),
              Mapping.evaluate({:after_stat, ["count"]}, @statistic),
              Mapping.evaluate({:after_stat, [{:log10, ["count"]}]}, @statistic)} ===
               {[25.0, 75.0], [1.0, 3.0], [0.0, 0.47712125471966244]}
    end
  end

  describe "category/2" do
    test "a factor is declared a category with its options, an after_stat as its value" do
      assert {Mapping.category({:factor, ["hwy"]}, @frame),
              Mapping.category({:factor, ["hwy"], levels: [31, 29], ordered: true}, @frame),
              Mapping.category(
                {:after_stat, [{:factor, ["count"], levels: [3.0, 1.0]}]},
                @statistic
              ), Mapping.category({:after_stat, ["count"]}, @statistic),
              Mapping.category("class", @frame), Mapping.category({:constant, 4}, @frame)} ===
               {:category, {:category, levels: [31, 29], ordered: true},
                {:category, levels: [3.0, 1.0]}, :none, :none, :none}
    end

    test "a table's category keeps its declaration, and a factor of it its levels and ordered" do
      table =
        DataFrame.new([
          {"cut", ["Ideal", "Fair"],
           {:category, levels: ["Fair", "Good", "Ideal"], ordered: true}}
        ])

      declared = {:category, levels: ["Fair", "Good", "Ideal"], ordered: true}

      assert {Mapping.category("cut", table), Mapping.category({:factor, ["cut"]}, table),
              Mapping.category({:factor, ["cut"], ordered: false}, table),
              Mapping.category({:factor, ["cut"], levels: ["Ideal", "Fair"]}, table)} ===
               {declared, declared,
                {:category, levels: ["Fair", "Good", "Ideal"], ordered: false},
                {:category, ordered: true, levels: ["Ideal", "Fair"]}}
    end
  end

  describe "title/2" do
    test "a column is titled by its name; a constant by its aesthetic's, as a fallback" do
      assert {Mapping.title("cty", :x), Mapping.title({:constant, "smooth"}, :color)} ===
               {{:title, "cty"}, {:fallback, "color"}}
    end

    # The compiler inlines most of these (`&Kernel.!=/2` is `&:erlang."/="/2`); a capture built when
    # the program runs names Kernel's own function. Both are titled as Elixir writes the operator,
    # a unary one before its operand, a word one with a space.
    test "every one of Kernel's operators is titled as itself, inlined or not" do
      operators = [
        {"a != b", :!=, &Kernel.!=/2},
        {"a !== b", :!==, &Kernel.!==/2},
        {"a * b", :*, &Kernel.*/2},
        {"a ** b", :**, &Kernel.**/2},
        {"+a", :+, &Kernel.+/1},
        {"a + b", :+, &Kernel.+/2},
        {"a ++ b", :++, &Kernel.++/2},
        {"-a", :-, &Kernel.-/1},
        {"a - b", :-, &Kernel.-/2},
        {"a -- b", :--, &Kernel.--/2},
        {"a / b", :/, &Kernel.//2},
        {"a < b", :<, &Kernel.</2},
        {"a <= b", :<=, &Kernel.<=/2},
        {"a == b", :==, &Kernel.==/2},
        {"a === b", :===, &Kernel.===/2},
        {"a =~ b", :=~, &Kernel.=~/2},
        {"a > b", :>, &Kernel.>/2},
        {"a >= b", :>=, &Kernel.>=/2},
        {"not a", :not, &Kernel.not/1}
      ]

      mistitled =
        for {text, operator, inlined} <- operators,
            {:arity, arity} = Function.info(inlined, :arity),
            function <- [inlined, Function.capture(Kernel, operator, arity)],
            title = Mapping.title({function, Enum.take(["a", "b"], arity)}, :x),
            title != {:title, text},
            do: {text, function, title}

      assert mistitled === []
    end

    test "a constant inside an expression is written as Elixir writes the term" do
      assert {Mapping.title({&Kernel.!=/2, ["class", {:constant, "suv"}]}, :x),
              Mapping.title({&Kernel.*/2, ["hwy", {:constant, 2.5}]}, :x)} ===
               {{:title, ~s(class != "suv")}, {:title, "hwy * 2.5"}}
    end

    test "an operator's operand that is itself an operator's call is put in parentheses" do
      {:ok, value} = Mapping.resolve({&Kernel.*/2, [{&Kernel.+/2, [:hwy, :cty]}, 2]})
      {:ok, called} = Mapping.resolve({&:math.sqrt/1, [{&Kernel.+/2, [:hwy, :cty]}]})

      assert {Mapping.title(value, :y), Mapping.title(called, :y)} ===
               {{:title, "(hwy + cty) * 2"}, {:title, ":math.sqrt(hwy + cty)"}}
    end

    test "any other capture is titled as a call to the function it names" do
      assert {Mapping.title({&:math.log10/1, ["carat"]}, :x),
              Mapping.title({&String.pad_leading/2, ["class", {:constant, 3}]}, :x)} ===
               {{:title, ":math.log10(carat)"}, {:title, "String.pad_leading(class, 3)"}}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 titles `aes(log10(carat))` `log10(carat)`, and so
    # `log10(log10(price))`, `log10(100)`, `log10(price) * 2`, `factor(log10(cyl))` and
    # `after_stat(log10(count))` `log10(count)`.
    test "a function by name is titled as a call to it, its value's text inside" do
      assert Enum.map(
               [
                 {:log10, ["carat"]},
                 {:log10, [{:log10, ["price"]}]},
                 {:log10, [{:constant, 100}]},
                 {&Kernel.*/2, [{:log10, ["price"]}, {:constant, 2}]},
                 {:factor, [{:log10, ["cyl"]}]},
                 {:after_stat, [{:log10, ["count"]}]}
               ],
               fn value -> Mapping.title(value, :x) end
             ) === [
               {:title, "log10(carat)"},
               {:title, "log10(log10(price))"},
               {:title, "log10(100)"},
               {:title, "log10(price) * 2"},
               {:title, "factor(log10(cyl))"},
               {:title, "log10(count)"}
             ]
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 titles `aes(colour = factor(cyl))` `factor(cyl)`.
    test "a factor is titled factor() around its value's text, a constant's as written" do
      assert {Mapping.title({:factor, ["cyl"]}, :color),
              Mapping.title({:factor, [{:constant, 4}]}, :color),
              Mapping.title({:factor, [{fn hwy -> hwy end, ["hwy"]}]}, :color)} ===
               {{:title, "factor(cyl)"}, {:title, "factor(4)"}, {:title, :none}}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 titles `aes(colour = factor(cyl, levels = c(8, 4, 6)))`
    # `factor(cyl, levels = c(8, 4, 6))`, and with `ordered = TRUE` that and `, ordered = TRUE`.
    test "a factor's options are titled as R writes the arguments, in the order given" do
      assert {Mapping.title({:factor, ["cyl"], levels: [8, 4, 6]}, :color),
              Mapping.title({:factor, ["cyl"], levels: [8, 4, 6], ordered: true}, :color),
              Mapping.title({:factor, ["cut"], ordered: false, levels: ["Fair", "Good"]}, :color)} ===
               {{:title, "factor(cyl, levels = c(8, 4, 6))"},
                {:title, "factor(cyl, levels = c(8, 4, 6), ordered = TRUE)"},
                {:title, ~s{factor(cut, ordered = FALSE, levels = c("Fair", "Good"))}}}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 titles `factor(cyl, levels = c(8, 4))`, `factor(am, levels =
    # c(TRUE, FALSE))` and `factor(x, levels = c(1e5, 0.5))` with `1e+05`.
    test "a factor's levels are written as R writes them" do
      assert {Mapping.title({:factor, ["cyl"], levels: [8.0, 4.0]}, :color),
              Mapping.title({:factor, ["am"], levels: [true, false]}, :color),
              Mapping.title({:factor, ["x"], levels: [100_000.0, 0.5]}, :color)} ===
               {{:title, "factor(cyl, levels = c(8, 4))"},
                {:title, "factor(am, levels = c(TRUE, FALSE))"},
                {:title, "factor(x, levels = c(1e+05, 0.5))"}}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 titles `after_stat(prop)` `prop`, `after_stat(factor(count))`
    # `factor(count)` and `after_stat(1)` `1`, which is no fallback: an after_stat is no constant.
    test "an after_stat is titled by its value's text, a constant's as written" do
      assert {Mapping.title({:after_stat, ["prop"]}, :y),
              Mapping.title({:after_stat, [{:factor, ["count"]}]}, :fill),
              Mapping.title({:after_stat, [{:constant, 1}]}, :y),
              Mapping.title({:after_stat, [{fn prop -> prop end, ["prop"]}]}, :y)} ===
               {{:title, "prop"}, {:title, "factor(count)"}, {:title, "1"}, {:title, :none}}
    end

    test "a closure has no text, so neither has an expression with one inside it" do
      closure = fn hwy -> hwy * 2 end

      assert {Mapping.title({closure, ["hwy"]}, :y),
              Mapping.title({&Kernel.+/2, [{closure, ["hwy"]}, "cty"]}, :y)} ===
               {{:title, :none}, {:title, :none}}
    end
  end
end
