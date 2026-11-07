defmodule Cuevolution.NamesTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Cuevolution.Names

  doctest Cuevolution.Names

  describe "title_case/1" do
    test "normalises whatever casing was typed" do
      assert Names.title_case("john otieno") == "John Otieno"
      assert Names.title_case("JOHN OTIENO") == "John Otieno"
      assert Names.title_case("jOhN oTiEnO") == "John Otieno"
      assert Names.title_case("John Otieno") == "John Otieno"
    end

    test "keeps apostrophe names intact — these are common in Kenya" do
      assert Names.title_case("ng'ang'a") == "Ng'ang'a"
      assert Names.title_case("NG'ANG'A") == "Ng'ang'a"
      assert Names.title_case("wang'ombe") == "Wang'ombe"
      assert Names.title_case("o'brien") == "O'brien"
    end

    test "capitalises across hyphens" do
      assert Names.title_case("mary-jane") == "Mary-Jane"
      assert Names.title_case("MARY-JANE WANJIRU") == "Mary-Jane Wanjiru"
    end

    test "preserves the spacing it was given" do
      assert Names.title_case("john  otieno") == "John  Otieno"
      assert Names.title_case("  john ") == "  John "
    end

    test "handles empty and nil" do
      assert Names.title_case(nil) == nil
      assert Names.title_case("") == ""
    end

    test "leaves digits and symbols alone" do
      assert Names.title_case("seed team 5") == "Seed Team 5"
      assert Names.title_case("8ball crew") == "8ball Crew"
    end
  end

  describe "full_name/2 and player_name/1" do
    test "joins and title-cases" do
      assert Names.full_name("john", "OTIENO") == "John Otieno"
      assert Names.player_name(%{first_name: "mary", last_name: "wanjiru"}) == "Mary Wanjiru"
    end

    test "skips a missing half rather than leaving a stray space" do
      assert Names.full_name("mary", nil) == "Mary"
      assert Names.full_name(nil, "wanjiru") == "Wanjiru"
      assert Names.full_name(nil, nil) == ""
      assert Names.full_name("mary", "") == "Mary"
    end
  end

  describe "sort_key/1" do
    test "orders case-insensitively" do
      assert Enum.sort_by(["otieno", "Abara", "ZULU", "mwangi"], &Names.sort_key/1) ==
               ["Abara", "mwangi", "otieno", "ZULU"]
    end

    test "nil sorts first rather than crashing" do
      assert Names.sort_key(nil) == ""
    end
  end
end
