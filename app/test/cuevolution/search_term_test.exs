defmodule Cuevolution.SearchTermTest do
  use ExUnit.Case, async: true

  alias Cuevolution.SearchTerm

  doctest Cuevolution.SearchTerm

  describe "patterns/1" do
    test "wraps a plain term as a substring pattern" do
      assert SearchTerm.patterns("Vans01") == ["%Vans01%"]
    end

    test "treats a blank term as no filter at all" do
      assert SearchTerm.patterns(nil) == []
      assert SearchTerm.patterns("") == []
      assert SearchTerm.patterns("   ") == []
      assert SearchTerm.patterns("\t\n ") == []
    end

    test "strips surrounding whitespace and collapses internal runs" do
      assert SearchTerm.patterns("  Ali  ") == ["%Ali%"]
      assert SearchTerm.patterns("Ali   Nyakundi") == ["%Ali Nyakundi%"]
    end

    # The UI prints usernames as `@handle`, so an admin copying a row types
    # an `@` the stored handle does not have.
    test "offers an @-stripped alternative alongside the term as typed" do
      assert SearchTerm.patterns("@MAS") == ["%@MAS%", "%MAS%"]
      assert SearchTerm.patterns("@@Vans01") == ["%@@Vans01%", "%Vans01%"]
    end

    # ...but usernames may contain `@` themselves, so the typed form has to
    # survive too, and a term with no leading `@` must not be duplicated.
    test "keeps a term whose @ is not a display prefix" do
      assert SearchTerm.patterns("Bk@123") == ["%Bk@123%"]
    end

    test "does not emit an empty pattern for an @-only term" do
      assert SearchTerm.patterns("@") == ["%@%"]
      assert SearchTerm.patterns("@@@") == ["%@@@%"]
    end

    test "escapes LIKE metacharacters so they match literally" do
      assert SearchTerm.patterns("100%") == ["%100\\%%"]
      assert SearchTerm.patterns("a_b") == ["%a\\_b%"]
      assert SearchTerm.patterns("back\\slash") == ["%back\\\\slash%"]
    end
  end
end
