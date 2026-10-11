defmodule GigglyTest do
  use ExUnit.Case
  doctest Giggly

  test "greets the world" do
    assert Giggly.hello() == :world
  end
end
