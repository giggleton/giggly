defmodule Giggly.Tensor do
  @moduledoc false

  # The one module that builds a tensor: Nx's numerical kernels, taken and given as lists, for the
  # work a stat does on what the frame has summarised, a density's convolution first (design-log
  # §4, the entry beginning "Nx is a core dependency"). Nx reads its default backend from the
  # application environment and the process dictionary on every call that is not told one, so
  # every tensor here is built on `Nx.BinaryBackend` in 64-bit floats, and each operation runs on
  # the backend of the tensors it is handed: a user's own default, EXLA's say, never reaches a
  # drawing. Nothing here runs through `defn`; one that does arrives with `Nx.Defn.Evaluator` as
  # its compiler, for the same reason.
  #
  # Its own boundary, listing Nx, which the root lists too, as boundary lets a sub-boundary list
  # only what its parent does; no other domain lists it, and a stat reaches Nx only through the
  # functions here.
  use Boundary, deps: [Nx], exports: []

  # The circular cross-correlation of `signal` with `kernel`, lists of numbers as long as each
  # other: at each place, the sum over every place of the signal there times the kernel as far
  # along from it, the kernel wrapping round the end, as R's `density()` convolves its binned
  # values with its kernel, `fft(fft(y) * Conj(fft(kernel)), inverse = TRUE)` over their length.
  # It is their convolution where the kernel is symmetric, as every density's is. Worked out by
  # Nx's fast Fourier transform, its inverse dividing by the length, with no threshold (`eps: 0`):
  # Nx's default, 1e-10, would zero a density's tails.
  @doc false
  @spec circular_correlation([number()], [number()]) :: [float()]
  def circular_correlation(signal, kernel) when length(signal) == length(kernel) do
    kernel_spectrum =
      kernel
      |> tensor()
      |> Nx.fft(eps: 0)
      |> Nx.conjugate()

    signal
    |> tensor()
    |> Nx.fft(eps: 0)
    |> Nx.multiply(kernel_spectrum)
    |> Nx.ifft(eps: 0)
    |> Nx.real()
    |> Nx.to_flat_list()
  end

  defp tensor(values), do: Nx.tensor(values, type: :f64, backend: Nx.BinaryBackend)
end
