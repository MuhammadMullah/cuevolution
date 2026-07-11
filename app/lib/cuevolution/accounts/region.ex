defmodule Cuevolution.Accounts.Region do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "regions" do
    field :name, :string
    field :slug, :string

    timestamps()
  end
end
