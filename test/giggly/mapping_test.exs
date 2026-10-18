defmodule Giggly.MappingTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Mapping}

  doctest Giggly.Mapping

  @frame DataFrame.new([{"hwy", [29, 24, 31]}, {"cty", [18, 16, 21]}, {"class", ["a", "b", "a"]}])

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
      assert {:error, reason} = Mapping.resolve({:fctor, [:cyl]})
      assert reason =~ "a tuple is an expression"
    end

    test "an expression whose arguments are not a list is refused" do
      assert {:error, reason} = Mapping.resolve({&String.upcase/1, :class})
      assert reason =~ "arguments are a list"
    end

    test "a function given a number of arguments it does not take is refused, saying how many" do
      assert {:error, reason} = Mapping.resolve({&Kernel.//2, [:hwy]})
      assert reason =~ "takes 2 argument(s), and the expression gives it 1"
    end

    test "a refused argument refuses the expression, with the argument's reason" do
      assert {:error, reason} = Mapping.resolve({&Kernel.//2, [:hwy, nil]})
      assert reason =~ "nil is a missing value"
    end
  end

  describe "columns/1" do
    test "the columns a value reads, each once, in the order it reads them" do
      {:ok, value} = Mapping.resolve({&Kernel.//2, [{&Kernel.-/2, [:hwy, :cty]}, :hwy]})

      assert {Mapping.columns(value), Mapping.columns("cty"), Mapping.columns({:constant, 7})} ===
               {["hwy", "cty"], ["cty"], []}
    end
  end

  describe "dtype/2" do
    test "a column's type is its table's, a constant's its own; an expression's is not known" do
      {:ok, expression} = Mapping.resolve({&Kernel.//2, [:hwy, :cty]})

      assert {Mapping.dtype("class", @frame), Mapping.dtype({:constant, 2.5}, @frame),
              Mapping.dtype(expression, @frame)} === {:string, :float, :computed}
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

    test "a function of no arguments gives a value in every row" do
      assert Mapping.evaluate({fn -> 1 end, []}, @frame) === [1, 1, 1]
    end
  end

  describe "title/2" do
    test "a column is titled by its name; a constant by its aesthetic's, as a fallback" do
      assert {Mapping.title("cty", :x), Mapping.title({:constant, "smooth"}, :color)} ===
               {{:title, "cty"}, {:fallback, "color"}}
    end

    # The compiler inlines `&Kernel.!=/2` as `&:erlang."/="/2`; a capture built when the program
    # runs names Kernel's own function. Both are titled as Elixir writes the operator.
    test "a capture of Kernel's operator is titled as the operator, inlined or not" do
      inlined = {&Kernel.!=/2, ["class", {:constant, "suv"}]}
      built = {Function.capture(Kernel, :!=, 2), ["class", {:constant, "suv"}]}

      assert {Mapping.title(inlined, :x), Mapping.title(built, :x)} ===
               {{:title, ~s(class != "suv")}, {:title, ~s(class != "suv")}}
    end

    test "a unary operator is written before its operand, a word one with a space" do
      assert {Mapping.title({&Kernel.-/1, ["hwy"]}, :x),
              Mapping.title({&Kernel.not/1, ["manual"]}, :x)} ===
               {{:title, "-hwy"}, {:title, "not manual"}}
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

    test "a closure has no text, so neither has an expression with one inside it" do
      closure = fn hwy -> hwy * 2 end

      assert {Mapping.title({closure, ["hwy"]}, :y),
              Mapping.title({&Kernel.+/2, [{closure, ["hwy"]}, "cty"]}, :y)} ===
               {{:title, :none}, {:title, :none}}
    end
  end
end
