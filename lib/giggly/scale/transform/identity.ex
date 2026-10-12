defmodule Giggly.Scale.Transform.Identity do
  @moduledoc """
  The identity transformation, R's `transform_identity()`: every value as it is. It is what a
  continuous scale records when nothing transforms its axis. Use it through
  `Giggly.Scale.Transform`.
  """

  @behaviour Giggly.Scale.Transform

  @impl Giggly.Scale.Transform
  def transform(values), do: values
end
