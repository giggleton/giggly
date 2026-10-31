defmodule Scales.LabelsTextTest do
  use ExUnit.Case, async: true

  alias Scales.Labels

  # Golden: every expected label below is R's own, from R 4.6.1 with scales 1.4.0 (the image
  # `giggly-r:ggplot2-4.0.3`), `label_wrap(width)(x)` or `label_dictionary(dictionary,
  # nomatch)(x)` of the values and width each test gives, but where a comment says it departs.
  # An invisible character is escaped as R's output was, `\u200B` a zero-width space.

  describe "wrap/2" do
    test "breaks a label into lines shorter than its width, a missing one NA" do
      statuses = ["Conservation Dependent", "Least concern", "Near Threatened", "Domesticated"]

      assert Labels.wrap(statuses ++ [nil, ""], width: 10) ==
               ["Conservation\nDependent", "Least\nconcern", "Near\nThreatened", "Domesticated"] ++
                 ["NA", ""]

      assert Labels.wrap([], width: 10) == []
      assert Labels.wrap(["ab cd", "abcd e"], width: 5) == ["ab\ncd", "abcd\ne"]
      assert Labels.wrap(["ab cd", "abcde f"], width: 6) == ["ab cd", "abcde\nf"]
      assert Labels.wrap(["a b c", "ab"], width: 1) == ["a\nb\nc", "ab"]
    end

    test "never splits a word, one wider than the width on a line of its own" do
      texts = ["abcdefghi j", "abcdefghij k", "verylongwordhere and", "abcdefghi"]

      assert Labels.wrap(texts, width: 10) ==
               ["abcdefghi\nj", "abcdefghij\nk", "verylongwordhere\nand", "abcdefghi"]
    end

    test "makes whitespace between words one space, only spaces, tabs and line breaks being it" do
      texts = ["a  b", " lead", "trail ", "  lead and trail  ", "tab\there", "x\ny", "a\t\n b"]
      others = ["x\r\ny", "aaaa\u00A0bbbb cc", "a\f b\v c"]

      assert Labels.wrap(texts, width: 10) ==
               ["a b", "lead", "trail", "lead and\ntrail", "tab here", "x y", "a b"]

      assert Labels.wrap(others, width: 10) == ["x\r y", "aaaa\u00A0bbbb\ncc", "a\f b\v c"]
    end

    test "keeps two spaces after a sentence's end that two or more whitespace characters " <>
           "followed, at most one closing mark after it" do
      kept = ["a.  b", "a?  b", "a!  b", "a.   b", "a. \tb", "a.  \nb", "(a.)  b", ~s("a."  b)]
      quoted = ["a.'  b", "e.g.  x"]
      single = ["a. b", "a.\tb", "a.\nb", "a)  b", "a'  b", "a.]  b", "a.)\"  b", "a.))  b"]
      closed_twice = ["a.'\"  b"]

      assert Labels.wrap(kept ++ quoted, width: 10) ==
               ["a.  b", "a?  b", "a!  b", "a.  b", "a.  b", "a.  b", "(a.)  b", ~s("a."  b)] ++
                 quoted

      assert Labels.wrap(single ++ closed_twice, width: 10) ==
               ["a. b", "a. b", "a. b", "a) b", "a' b", "a.] b", "a.)\" b", "a.)) b", "a.'\" b"]
    end

    test "counts a sentence's two spaces in the width, and drops them at a line's end" do
      texts = ["Mr.  Smith", "a.  bcdefg", "a.  bcdef", "a.  ", "a.     b"]

      assert Labels.wrap(texts, width: 10) ==
               ["Mr.\nSmith", "a.\nbcdefg", "a.  bcdef", "a.", "a.  b"]

      assert {Labels.wrap(["ab.  cd"], width: 7), Labels.wrap(["ab.  cd"], width: 8)} ==
               {["ab.\ncd"], ["ab.  cd"]}
    end

    test "starts a paragraph at a line holding only whitespace, an empty line before it; a " <>
           "break at the start gives empty lines, and one at the end none" do
      texts = ["x\n\ny", "x\n \ny", "x\n\n\ny", "a\n\nb\n\nc", "\n\nx", "x\n\n", "  \n\n  "]
      more = ["\na", "a\n", "\n", " ", "\t\t", "a\n \t \nb"]

      assert Labels.wrap(texts ++ more, width: 10) ==
               ["x\n\ny", "x\n\ny", "x\n\ny", "a\n\nb\n\nc", "\n\nx", "x", "\n\n"] ++
                 ["a", "a", "", "", "", "a\n\nb"]
    end

    test "counts a wide character two columns and a combining mark none, as R does" do
      wide = ["日本語 日本語", "ａｂｃ ｄｅｆ", "日本語日本語 x"]
      narrow = ["e\u0301e\u0301e\u0301e\u0301 abcd", "a\u0301bcdefghi j", "été été été"]

      assert Labels.wrap(wide, width: 10) == ["日本語\n日本語", "ａｂｃ\nｄｅｆ", "日本語日本語\nx"]
      assert Labels.wrap(["日本 語"], width: 6) == ["日本\n語"]
      assert Labels.wrap(["😀😀 😀😀 😀😀"], width: 10) == ["😀😀 😀😀\n😀😀"]

      assert Labels.wrap(narrow, width: 10) ==
               ["e\u0301e\u0301e\u0301e\u0301 abcd", "a\u0301bcdefghi\nj", "été été\nété"]

      assert Labels.wrap(["日本 語", "👨\u200D👩\u200D👧 ab"], width: 5) ==
               ["日本\n語", "👨\u200D👩\u200D👧\nab"]
    end

    test "drops a word of zero-width characters as whitespace, but after a sentence's end" do
      texts = ["\u200B\u200B\u200B\u200B\u200B\u200B ab", "x \u200B y", "\u0301 x"]
      after_sentences = ["a. \u200B b", "a.\u200B  b", "a.  \u200B b"]

      assert Labels.wrap(texts ++ after_sentences, width: 10) ==
               ["ab", "x y", "x", "a. \u200B b", "a.\u200B b", "a.  b"]

      assert Labels.wrap(["abc\u200B d", "ab. \u200B"], width: 4) == ["abc\u200B\nd", "ab."]
    end

    # R writes any value with `as.character()` first, `1e+05`, `TRUE`; strings alone are taken.
    test "refuses what is not a list of strings and nils" do
      for labels <- [[1.0e5], [true], ["a", :b], ["\xFF"], "a b"] do
        assert_raise ArgumentError, ~r"Labels.wrap/2 takes a list of strings and nils", fn ->
          Labels.wrap(labels, width: 10)
        end
      end
    end

    # R takes any number, a line and one more character within it: 4.5 breaks `"ab c"`, 0 and
    # below every word alone, `Inf` nothing; `NA` fails when a label is written.
    test "takes a width, a positive integer" do
      for options <- [[], [width: 0], [width: -5], [width: 4.5], [width: :infinity]] do
        assert_raise NimbleOptions.ValidationError, fn -> Labels.wrap(["ab c"], options) end
      end
    end
  end

  describe "dictionary/2" do
    @fruit %{"a" => "Apple", "b" => "Banana"}

    test "labels each value it holds, and leaves a string it lacks its own and a missing one " <>
           "missing" do
      assert Labels.dictionary(["a", "b", "c", nil], dictionary: @fruit) ==
               ["Apple", "Banana", "c", nil]

      assert Labels.dictionary(["a", nil], dictionary: %{}) == ["a", nil]
      assert Labels.dictionary([], dictionary: @fruit) == []
    end

    test "gives nomatch: for every value it lacks, a missing one included" do
      assert Labels.dictionary(["a", "c", nil], dictionary: @fruit, nomatch: "?") ==
               ["Apple", "?", "?"]

      assert Labels.dictionary(["a", "c", nil], dictionary: @fruit, nomatch: nil) ==
               ["Apple", nil, nil]

      assert Labels.dictionary(["a", nil], dictionary: %{}, nomatch: "?") == ["?", "?"]
      assert Labels.dictionary([], dictionary: @fruit, nomatch: "?") == []
    end

    test "gives a value it labels nil no label, whatever nomatch: says" do
      assert Labels.dictionary(["a", "b", "c"],
               dictionary: %{"a" => nil, "b" => "B"},
               nomatch: "?"
             ) ==
               [nil, "B", "?"]
    end

    test "matches strings exactly, case, accents and spaces as written" do
      assert Labels.dictionary(["a", "A"], dictionary: %{"A" => "upper"}) == ["a", "upper"]

      assert Labels.dictionary(["e\u0301", "é"], dictionary: %{"é" => "acute"}) ==
               ["e\u0301", "acute"]

      assert Labels.dictionary(["a", " a"], dictionary: %{" a" => "spaced"}) == ["a", "spaced"]
    end

    # Departs: R matches a value as text, so `c("1" = "one")` names the number 1; here a key
    # names the values it matches by `Scales.DataRange.key/1`, a discrete scale's rule.
    test "matches a value by its key, so a whole number names the float equal to it" do
      numbers = %{1 => "one", 2.0 => "two", true => "yes"}

      assert Labels.dictionary([1.0, 2, true, false, -0.0], dictionary: numbers, nomatch: "?") ==
               ["one", "two", "yes", "?", "?"]

      assert Labels.dictionary([1], dictionary: %{"1" => "one"}, nomatch: "?") == ["?"]
      assert Labels.dictionary([0.0], dictionary: %{-0.0 => "zero"}) == ["zero"]
    end

    # Departs: R refuses an empty name, as it refuses an element with none.
    test "takes an empty string as a key" do
      assert Labels.dictionary(["", "a"], dictionary: %{"" => "blank"}) == ["blank", "a"]
    end

    test "raises on a value it lacks that is not a string, without nomatch:" do
      assert_raise ArgumentError, ~r"Labels.dictionary/2 has no label for 2.0", fn ->
        Labels.dictionary([2.0], dictionary: %{1 => "one"})
      end
    end

    test "refuses a key nil, a value named twice, a label not a string, and what is not a map" do
      for dictionary <-
            [%{nil => "none"}, %{1 => "a", 1.0 => "b"}, %{0.0 => "a", -0.0 => "b"}] ++
              [%{"a" => 1}, %{"a" => :b}, [{"a", "A"}], ["A"]] do
        assert_raise NimbleOptions.ValidationError, fn ->
          Labels.dictionary(["a"], dictionary: dictionary)
        end
      end
    end

    test "names both values a key repeats" do
      assert_raise NimbleOptions.ValidationError, ~r"1 and 1.0 name the same value", fn ->
        Labels.dictionary([1], dictionary: %{1 => "a", 1.0 => "b"})
      end
    end

    # R coerces a number to text, recycles a vector with a warning and fails on an empty one.
    test "takes a dictionary, and a nomatch: of a string or nil" do
      for options <- [[], [dictionary: @fruit, nomatch: 1], [dictionary: @fruit, nomatch: ["x"]]] do
        assert_raise NimbleOptions.ValidationError, fn -> Labels.dictionary(["a"], options) end
      end

      assert_raise ArgumentError, ~r"Labels.dictionary/2 takes a list of values", fn ->
        Labels.dictionary("a", dictionary: @fruit)
      end
    end
  end
end
