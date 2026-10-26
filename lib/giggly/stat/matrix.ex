defmodule Giggly.Stat.Matrix do
  @moduledoc false

  # Small dense matrices, each a list of its rows, each row a list of numbers, and vectors as
  # lists, for gam's algebra on its 10 by 10 sums (`Giggly.Stat.Gam`). It is plain Elixir rather
  # than Nx, which on its binary backend takes some eighty times as long over matrices this small
  # and solves less tightly (design-log §4, the entry beginning "gam is Giggly's own"). A
  # symmetric positive definite matrix is factored by Cholesky's method, L Lᵀ, L lower triangular,
  # as Golub and Van Loan give it (Matrix Computations, 4th ed., §4.2), which a solve, an inverse
  # and a log-determinant read; a symmetric matrix's eigenvalues are found by cyclic Jacobi
  # rotations (§8.5), each zeroing one off-diagonal entry, sweep after sweep, until what is left off
  # the diagonal is below 1e-14 of the whole, relatively, in the root of its sum of squares.

  # How small, relatively, the root of the off-diagonal entries' sum of squares must be, squared,
  # before Jacobi's sweeps stop.
  @settled 1.0e-28

  # The matrix's transpose.
  @doc false
  @spec transpose([[number()]]) :: [[number()]]
  def transpose(matrix), do: Enum.zip_with(matrix, fn column -> column end)

  # The product of two matrices.
  @doc false
  @spec multiply([[number()]], [[number()]]) :: [[number()]]
  def multiply(left, right) do
    columns = transpose(right)
    Enum.map(left, fn row -> Enum.map(columns, fn column -> dot(row, column) end) end)
  end

  # The matrix times a vector.
  @doc false
  @spec multiply_vector([[number()]], [number()]) :: [number()]
  def multiply_vector(matrix, vector), do: Enum.map(matrix, fn row -> dot(row, vector) end)

  # The sum of two matrices of one size.
  @doc false
  @spec add([[number()]], [[number()]]) :: [[number()]]
  def add(left, right) do
    Enum.zip_with(left, right, fn left_row, right_row ->
      Enum.zip_with(left_row, right_row, fn left_entry, right_entry ->
        left_entry + right_entry
      end)
    end)
  end

  # The matrix with every entry times `factor`.
  @doc false
  @spec scale([[number()]], number()) :: [[number()]]
  def scale(matrix, factor),
    do: Enum.map(matrix, fn row -> Enum.map(row, fn entry -> entry * factor end) end)

  # The matrix u vᵀ.
  @doc false
  @spec outer([number()], [number()]) :: [[number()]]
  def outer(left, right),
    do: Enum.map(left, fn left_entry -> Enum.map(right, fn entry -> left_entry * entry end) end)

  # The sum of two vectors' products, entry by entry.
  @doc false
  @spec dot([number()], [number()]) :: number()
  def dot(left, right) do
    Enum.zip_reduce(left, right, 0.0, fn left_entry, right_entry, sum ->
      sum + left_entry * right_entry
    end)
  end

  # The identity matrix of `size` rows.
  @doc false
  @spec identity(pos_integer()) :: [[float()]]
  def identity(size), do: Enum.map(1..size, fn row -> unit_row(size, row) end)

  defp unit_row(size, index), do: Enum.map(1..size, fn column -> diagonal(column, index) end)

  defp diagonal(index, index), do: 1.0
  defp diagonal(_column, _index), do: 0.0

  # The Cholesky factor of a symmetric positive definite matrix, its rows of L in order, row i
  # holding its i + 1 entries up to the diagonal, or `:none` where a pivot comes out at 0 or
  # below, so the matrix is not positive definite as rounded.
  @doc false
  @spec cholesky([[number()]]) :: {:ok, [[float()]]} | :none
  def cholesky(matrix) do
    matrix
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {row, length}, {:ok, reversed} ->
      case factor_row(Enum.take(row, length), Enum.reverse(reversed)) do
        {:ok, factor_row} -> {:cont, {:ok, [factor_row | reversed]}}
        :none -> {:halt, :none}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      :none -> :none
    end
  end

  # A row of L from the matrix's row up to its diagonal and the rows of L above it.
  defp factor_row(entries, previous) do
    {below, [diagonal]} = Enum.split(entries, -1)

    lower =
      below
      |> Enum.zip(previous)
      |> Enum.reduce([], fn {entry, previous_row}, reversed ->
        {earlier, [pivot]} = Enum.split(previous_row, -1)
        [(entry - dot(Enum.reverse(reversed), earlier)) / pivot | reversed]
      end)
      |> Enum.reverse()

    remainder = diagonal - dot(lower, lower)

    if remainder > 0,
      do: {:ok, Enum.concat(lower, [:math.sqrt(remainder)])},
      else: :none
  end

  # The logarithm of the factored matrix's determinant, twice the sum of the logarithms of L's
  # diagonal.
  @doc false
  @spec log_determinant([[float()]]) :: float()
  def log_determinant(factor) do
    logarithms =
      Enum.map(factor, fn row ->
        row
        |> List.last()
        |> :math.log()
      end)

    2 * Enum.sum(logarithms)
  end

  # The x with L Lᵀ x = `vector`: L z = `vector` forward, then Lᵀ x = z back.
  @doc false
  @spec solve([[float()]], [number()]) :: [float()]
  def solve(factor, vector) do
    forward =
      factor
      |> Enum.zip(vector)
      |> Enum.reduce([], fn {row, value}, reversed ->
        {earlier, [pivot]} = Enum.split(row, -1)
        [(value - dot(earlier, Enum.reverse(reversed))) / pivot | reversed]
      end)

    size = length(factor)

    factor
    |> Enum.map(fn row -> Enum.concat(row, List.duplicate(0.0, size - length(row))) end)
    |> transpose()
    |> Enum.reverse()
    |> Enum.zip(forward)
    |> Enum.reduce([], fn {upper_row, value}, later ->
      [pivot | after_diagonal] = Enum.drop(upper_row, size - length(later) - 1)
      [(value - dot(after_diagonal, later)) / pivot | later]
    end)
  end

  # The factored matrix's inverse, a column solved for each column of the identity.
  @doc false
  @spec inverse([[float()]]) :: [[float()]]
  def inverse(factor) do
    factor
    |> length()
    |> identity()
    |> Enum.map(fn column -> solve(factor, column) end)
    |> transpose()
  end

  # A symmetric matrix's eigenvalues, greatest first.
  @doc false
  @spec eigenvalues([[number()]]) :: [float()]
  def eigenvalues(matrix) do
    size = length(matrix)

    entries =
      for {row, row_index} <- Enum.with_index(matrix),
          {entry, column_index} <- Enum.with_index(row),
          into: %{},
          do: {{row_index, column_index}, entry / 1}

    entries
    |> settled(size)
    |> then(fn settled -> for index <- 0..(size - 1), do: Map.fetch!(settled, {index, index}) end)
    |> Enum.sort(:desc)
  end

  defp settled(entries, size) do
    indices = 0..(size - 1)
    off_diagonal = for row <- indices, column <- indices, row != column, do: {row, column}
    off = Enum.reduce(off_diagonal, 0.0, fn key, sum -> sum + entries[key] * entries[key] end)

    total =
      entries
      |> Map.values()
      |> Enum.reduce(0.0, fn entry, sum -> sum + entry * entry end)

    if off <= @settled * total do
      entries
    else
      pairs = for first <- 0..(size - 2), second <- (first + 1)..(size - 1), do: {first, second}

      pairs
      |> Enum.reduce(entries, fn {first, second}, rotated ->
        rotate(rotated, size, first, second)
      end)
      |> settled(size)
    end
  end

  # The matrix Jᵀ A J, J the rotation in the plane of `first` and `second` that zeroes their
  # off-diagonal entry, its tangent the smaller root of t² + 2θt - 1 = 0, θ = (a_qq - a_pp) / 2a_pq.
  defp rotate(entries, size, first, second) do
    across = entries[{first, second}]

    if across == 0.0 do
      entries
    else
      theta = (entries[{second, second}] - entries[{first, first}]) / (2 * across)
      sign = if theta >= 0, do: 1, else: -1
      tangent = sign / (abs(theta) + :math.sqrt(theta * theta + 1))
      cosine = 1 / :math.sqrt(tangent * tangent + 1)
      sine = tangent * cosine

      columns =
        Enum.reduce(0..(size - 1), entries, fn index, turned ->
          at_first = turned[{index, first}]
          at_second = turned[{index, second}]

          turned
          |> Map.put({index, first}, cosine * at_first - sine * at_second)
          |> Map.put({index, second}, sine * at_first + cosine * at_second)
        end)

      Enum.reduce(0..(size - 1), columns, fn index, turned ->
        at_first = turned[{first, index}]
        at_second = turned[{second, index}]

        turned
        |> Map.put({first, index}, cosine * at_first - sine * at_second)
        |> Map.put({second, index}, sine * at_first + cosine * at_second)
      end)
    end
  end
end
