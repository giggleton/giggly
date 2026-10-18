defmodule Giggly.AsCharacterTest do
  use ExUnit.Case, async: true

  alias Giggly.AsCharacter

  # Golden: R 4.6.1's `as.character()` of the same doubles.
  test "a float is written as R's as.character() writes it" do
    values = [
      21.0,
      2.62,
      1 / 3,
      0.1 + 0.2,
      1.0e5,
      123_456.0,
      123_456.7,
      1.0e15,
      1_234_567_890_123.0,
      0.0001,
      0.001,
      1.0e-20,
      -2.5,
      100.0,
      100_000.1,
      3.14159265358979,
      6_666_666_666.666666,
      0.12345678901234568,
      0.0,
      -0.0,
      1.0e100,
      1.0e-5
    ]

    assert Enum.map(values, &AsCharacter.text/1) === [
             "21",
             "2.62",
             "0.333333333333333",
             "0.3",
             "1e+05",
             "123456",
             "123456.7",
             "1e+15",
             "1234567890123",
             "1e-04",
             "0.001",
             "1e-20",
             "-2.5",
             "100",
             "100000.1",
             "3.14159265358979",
             "6666666666.66667",
             "0.123456789012346",
             "0",
             "0",
             "1e+100",
             "1e-05"
           ]
  end

  # Golden: R 4.6.1's `as.character()` of `100000L`, `-3L`, `TRUE`, `FALSE`, `as.Date("2020-01-02")`,
  # `Inf`, `-Inf` and `NaN`; an atom has no counterpart in R and is written by its name.
  test "a whole number, a boolean, a date, a non-finite float and an atom are written as R does" do
    values = [100_000, -3, true, false, ~D[2020-01-02], :infinity, :neg_infinity, :nan, :suv]

    assert Enum.map(values, &AsCharacter.text/1) ===
             ["100000", "-3", "TRUE", "FALSE", "2020-01-02", "Inf", "-Inf", "NaN", "suv"]
  end

  test "text is written as it is" do
    assert AsCharacter.text("Mazda RX4") === "Mazda RX4"
  end
end
