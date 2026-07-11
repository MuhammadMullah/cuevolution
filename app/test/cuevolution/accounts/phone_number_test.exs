defmodule Cuevolution.Accounts.PhoneNumberTest do
  use ExUnit.Case, async: true

  alias Cuevolution.Accounts.PhoneNumber

  describe "normalize/1" do
    test "normalizes a local Kenyan format (leading 0) to E.164" do
      assert PhoneNumber.normalize("0712345678") == {:ok, "+254712345678"}
    end

    test "normalizes a local Kenyan format with spaces/dashes to E.164" do
      assert PhoneNumber.normalize("0712 345 678") == {:ok, "+254712345678"}
      assert PhoneNumber.normalize("0712-345-678") == {:ok, "+254712345678"}
    end

    test "accepts an already-E.164 number unchanged" do
      assert PhoneNumber.normalize("+254712345678") == {:ok, "+254712345678"}
    end

    test "accepts a bare national number (no leading 0 or +) assuming Kenya" do
      assert PhoneNumber.normalize("712345678") == {:ok, "+254712345678"}
    end

    test "accepts a foreign E.164 number as-is" do
      assert PhoneNumber.normalize("+14155552671") == {:ok, "+14155552671"}
    end

    test "rejects input with no digits" do
      assert PhoneNumber.normalize("not a number") == :error
    end

    test "rejects a too-short number that can't normalize to a valid E.164 value" do
      assert PhoneNumber.normalize("12345") == :error
    end

    test "rejects nil" do
      assert PhoneNumber.normalize(nil) == :error
    end

    test "honors an explicit region_code instead of the Kenya default" do
      assert PhoneNumber.normalize("202-456-1111", "US") == {:ok, "+12024561111"}
    end

    test "rejects a number that's invalid for the given region_code" do
      # A Kenyan-shaped local number isn't valid when parsed as a US number.
      assert PhoneNumber.normalize("0712345678", "US") == :error
    end
  end
end
