defmodule Cuevolution.Accounts.PasswordValidator do
  @moduledoc """
  Shared password strength rules for Admin and Player accounts: 8-15
  characters, with at least one uppercase letter, one digit, and one
  special character.
  """

  import Ecto.Changeset

  @min_length 8
  @max_length 15

  @spec validate_password(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_password(changeset, field \\ :password) do
    changeset
    |> validate_length(field, min: @min_length, max: @max_length)
    |> validate_format(field, ~r/[A-Z]/, message: "must contain at least one uppercase letter")
    |> validate_format(field, ~r/[0-9]/, message: "must contain at least one number")
    |> validate_format(field, ~r/[^a-zA-Z0-9]/,
      message: "must contain at least one special character"
    )
  end
end
