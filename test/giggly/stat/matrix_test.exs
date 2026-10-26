defmodule Giggly.Stat.MatrixTest do
  use ExUnit.Case, async: true

  alias Giggly.Stat.Matrix

  # Every golden here is R 4.6.1's, printed to 17 significant digits: `chol()` transposed,
  # `solve()`, `log(det())`, `eigen(symmetric = TRUE)` and `%*%`, for the symmetric positive
  # definite matrix @matrix.
  @matrix [[4.0, 2.0, 0.6], [2.0, 5.0, 1.5], [0.6, 1.5, 3.0]]

  describe "cholesky/1" do
    test "factors a symmetric positive definite matrix into its lower rows" do
      assert {:ok, factor} = Matrix.cholesky(@matrix)

      assert_close(List.flatten(factor), [
        2.0,
        1.0,
        2.0,
        0.29999999999999999,
        0.59999999999999998,
        1.5968719422671311
      ])
    end

    # [[1, 2], [2, 1]] has an eigenvalue of -1, so its second pivot, 1 - 4, is below 0; a 0 pivot is
    # refused as well.
    test "refuses a matrix whose pivot comes out at 0 or below" do
      assert Matrix.cholesky([[1.0, 2.0], [2.0, 1.0]]) == :none
      assert Matrix.cholesky([[0.0]]) == :none
    end
  end

  describe "reading a Cholesky factor" do
    test "solves, inverts and takes the log-determinant as R's solve() and det() do" do
      {:ok, factor} = Matrix.cholesky(@matrix)

      assert_close(Matrix.solve(factor, [1.0, -2.0, 0.5]), [
        0.5625,
        -0.75441176470588234,
        0.43137254901960792
      ])

      inverse =
        factor
        |> Matrix.inverse()
        |> List.flatten()

      assert_close(inverse, [
        0.3125,
        -0.125,
        0.0,
        -0.125,
        0.28529411764705881,
        -0.11764705882352942,
        0.0,
        -0.11764705882352942,
        0.39215686274509809
      ])

      assert_close([Matrix.log_determinant(factor)], [3.708682081410116])
    end
  end

  describe "eigenvalues/1" do
    # The second, the 4 by 4 second-difference matrix, whose eigenvalues are 2 - 2 cos(kπ / 5).
    test "are a symmetric matrix's eigenvalues, greatest first" do
      assert_close(Matrix.eigenvalues(@matrix), [
        7.1479955789576026,
        2.8474199084736513,
        2.0045845125687465
      ])

      second_difference = [
        [2, -1, 0, 0],
        [-1, 2, -1, 0],
        [0, -1, 2, -1],
        [0, 0, -1, 2]
      ]

      assert_close(Matrix.eigenvalues(second_difference), [
        3.6180339887498949,
        2.6180339887498962,
        1.381966011250106,
        0.38196601125010998
      ])
    end

    test "of a diagonal matrix are its diagonal, sorted, as floats" do
      assert Matrix.eigenvalues([[1, 0], [0, 3]]) === [3.0, 1.0]
    end

    # Rotating the first two rows leaves their entries beside the third exactly 0, so a rotation
    # meets an entry already 0, which it must pass over: its angle would divide by it.
    test "of a block-diagonal matrix pass over the entries already 0" do
      assert_close(Matrix.eigenvalues([[2, 1, 0], [1, 2, 0], [0, 0, 5]]), [5.0, 3.0, 1.0])
    end
  end

  describe "the arithmetic of matrices and vectors" do
    test "transposes, multiplies, adds, scales and takes products as R's operators do" do
      right = [[1.0, -1.0, 0.0], [0.0, 3.0, 1.0], [2.0, 1.0, -2.0]]

      product =
        @matrix
        |> Matrix.multiply(right)
        |> List.flatten()

      assert_close(product, [
        5.2000000000000002,
        2.6000000000000001,
        0.80000000000000004,
        5.0,
        14.5,
        2.0,
        6.5999999999999996,
        6.9000000000000004,
        -4.5
      ])

      assert Matrix.transpose([[1, 2, 3], [4, 5, 6]]) == [[1, 4], [2, 5], [3, 6]]
      assert Matrix.multiply_vector([[1, 2], [3, 4]], [5, 6]) == [17.0, 39.0]
      assert Matrix.add([[1, 2], [3, 4]], [[10, 20], [30, 40]]) == [[11, 22], [33, 44]]
      assert Matrix.scale([[1, 2], [3, 4]], 3) == [[3, 6], [9, 12]]
      assert Matrix.outer([1, 2], [3, 4, 5]) == [[3, 4, 5], [6, 8, 10]]
      assert Matrix.dot([1, 2, 3], [4, 5, 6]) == 32.0
      assert Matrix.identity(2) == [[1.0, 0.0], [0.0, 1.0]]
    end
  end

  # Values within 1e-14 of R's, of the largest magnitude R's hold.
  defp assert_close(actual, expected) do
    largest =
      expected
      |> Enum.map(&abs/1)
      |> Enum.max()

    assert length(actual) == length(expected)

    Enum.zip_with(actual, expected, fn value, wanted ->
      assert abs(value - wanted) <= 1.0e-14 * largest,
             "#{inspect(actual)}, R #{inspect(expected)}"
    end)
  end
end
