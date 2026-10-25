defmodule Giggly.TensorTest do
  use ExUnit.Case, async: true

  alias Giggly.Tensor

  # The circular cross-correlation summed directly: at each place, the signal everywhere times the
  # kernel as far along from it, wrapping round.
  defp correlation(signal, kernel) do
    length = length(signal)
    kernel = List.to_tuple(kernel)

    Enum.map(0..(length - 1), fn place ->
      signal
      |> Enum.with_index()
      |> Enum.reduce(0.0, fn {value, index}, total ->
        total + value * elem(kernel, Integer.mod(index - place, length))
      end)
    end)
  end

  defp assert_close(actual, expected) do
    assert length(actual) == length(expected)

    Enum.zip_with(actual, expected, fn value, wanted ->
      assert abs(value - wanted) <= 1.0e-15, "#{inspect(actual)}, summed #{inspect(expected)}"
    end)
  end

  # A kernel that is not symmetric tells correlation from convolution, which reads it backwards.
  test "circular_correlation is the direct sum's, the kernel wrapping round" do
    signal = [0.25, 0.0, 0.5, 0.25, 0.0, 0.0, 0.0, 0.0]
    kernel = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]

    assert_close(Tensor.circular_correlation(signal, kernel), correlation(signal, kernel))
  end

  # 0.1, 0.2, 0.3 and 0.4 in 32-bit floats are off by up to 6e-9; in 64-bit ones by 1e-17.
  test "circular_correlation works in 64-bit floats" do
    assert_close(
      Tensor.circular_correlation([1, 0, 0, 0], [0.1, 0.2, 0.3, 0.4]),
      [0.1, 0.4, 0.3, 0.2]
    )
  end

  # Nx's default threshold, 1e-10, would zero both of these; the transform's round-off is about
  # 1e-17 of the largest value, 1.
  test "circular_correlation keeps values far below Nx's default threshold" do
    [_one, small, zero, tiny] =
      Tensor.circular_correlation([1.0, 0.0, 0.0, 0.0], [1.0, 1.0e-12, 0.0, 3.0e-13])

    assert abs(small - 3.0e-13) <= 1.0e-15
    assert abs(zero) <= 1.0e-15
    assert abs(tiny - 1.0e-12) <= 1.0e-15
  end

  # A backend that builds nothing: a tensor made on it raises.
  defmodule Refusing do
    def init(options), do: options
  end

  # A process's default backend, here one that builds nothing, never reaches the tensors built.
  test "circular_correlation builds its tensors on the binary backend, whatever the default" do
    Nx.default_backend(Refusing)

    assert_close(
      Tensor.circular_correlation([1.0, 2.0], [3.0, 4.0]),
      correlation([1.0, 2.0], [3.0, 4.0])
    )
  end
end
