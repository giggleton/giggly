defmodule Scales.Labels.ArithmeticTest do
  use ExUnit.Case, async: true

  alias Scales.Labels.Arithmetic

  # Golden: every expected value below is R's own, from R 4.6.1 (the image
  # `giggly-r:ggplot2-4.0.3`), each from the call in the comment above it, printed with
  # sprintf("%.17g"). They move only if R's arithmetic does. The labellers' tests reach these
  # functions through R's labels; these pin what no label tells apart.

  describe "round_to/2" do
    test "takes a tie, measured in floats, to the even neighbour" do
      # round(0.125, 2); round(0.375, 2); round(-0.125, 2); round(0.625, 2)
      assert Arithmetic.round_to(0.125, 2) === 0.12
      assert Arithmetic.round_to(0.375, 2) === 0.38
      assert Arithmetic.round_to(-0.125, 2) === -0.12
      assert Arithmetic.round_to(0.625, 2) === 0.62
    end
  end

  # The infinities below are R's `-Inf` and `Inf` for the same operations, which Erlang refuses.
  describe "product/2 and quotient/2" do
    test "give the infinity of the result's sign past the largest double" do
      # 1e308 * 10; -1e308 * 10; -0.5 / 1e-310; 0.5 / -1e-310; -1e308 / -0.1
      assert Arithmetic.product(1.0e308, 10.0) == :infinity
      assert Arithmetic.product(-1.0e308, 10.0) == :neg_infinity
      assert Arithmetic.quotient(-0.5, 1.0e-310) == :neg_infinity
      assert Arithmetic.quotient(0.5, -1.0e-310) == :neg_infinity
      assert Arithmetic.quotient(-1.0e308, -0.1) == :infinity
    end

    # Not R's: the labellers hand these a break only once it is a number, and a missing or
    # infinite one taken through the rescue would read as an overflow, its sign lost.
    test "refuse what is not a number" do
      for value <- [nil, :infinity, :neg_infinity] do
        refused = untyped(value)
        assert_raise FunctionClauseError, fn -> Arithmetic.product(refused, 1.0) end
        assert_raise FunctionClauseError, fn -> Arithmetic.product(1.0, refused) end
        assert_raise FunctionClauseError, fn -> Arithmetic.quotient(refused, 1.0) end
        assert_raise FunctionClauseError, fn -> Arithmetic.quotient(1.0, refused) end
        assert_raise FunctionClauseError, fn -> Arithmetic.difference(refused, 1.0) end
        assert_raise FunctionClauseError, fn -> Arithmetic.difference(1.0, refused) end
      end
    end
  end

  # `value` with its type hidden from the compiler, so a test can hand a function a value its
  # guards refuse.
  @spec untyped(term()) :: term()
  defp untyped(value), do: value
end
