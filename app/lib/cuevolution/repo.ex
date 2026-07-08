defmodule Cuevolution.Repo do
  use Ecto.Repo,
    otp_app: :cuevolution,
    adapter: Ecto.Adapters.Postgres
end
