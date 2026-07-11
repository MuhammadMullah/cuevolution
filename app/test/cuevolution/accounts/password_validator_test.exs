defmodule Cuevolution.Accounts.PasswordValidatorTest do
  use ExUnit.Case, async: true

  alias Cuevolution.Accounts.PasswordValidator

  defp changeset(password) do
    {%{}, %{password: :string}}
    |> Ecto.Changeset.cast(%{password: password}, [:password])
    |> PasswordValidator.validate_password()
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "validate_password/2" do
    test "accepts a password meeting every rule" do
      changeset = changeset("Valid1!ok")
      assert changeset.valid?
    end

    test "rejects a password shorter than 8 characters" do
      changeset = changeset("Ab1!ab")
      refute changeset.valid?
      assert "should be at least 8 character(s)" in errors_on(changeset).password
    end

    test "rejects a password longer than 15 characters" do
      changeset = changeset("Abcdefgh1!abcdef")
      refute changeset.valid?
      assert "should be at most 15 character(s)" in errors_on(changeset).password
    end

    test "rejects a password with no uppercase letter" do
      changeset = changeset("lowercase1!")
      refute changeset.valid?
      assert "must contain at least one uppercase letter" in errors_on(changeset).password
    end

    test "rejects a password with no digit" do
      changeset = changeset("NoDigits!!")
      refute changeset.valid?
      assert "must contain at least one number" in errors_on(changeset).password
    end

    test "rejects a password with no special character" do
      changeset = changeset("NoSpecial1")
      refute changeset.valid?
      assert "must contain at least one special character" in errors_on(changeset).password
    end

    test "accepts exactly 8 characters (inclusive lower boundary)" do
      changeset = changeset("Ab1!abcd")
      assert changeset.valid?
    end

    test "accepts exactly 15 characters (inclusive upper boundary)" do
      changeset = changeset("Ab1!abcdefghijk")
      assert changeset.valid?
    end

    test "a nil password is left to validate_required, not flagged here" do
      changeset = changeset(nil)
      assert changeset.valid?
    end
  end
end
