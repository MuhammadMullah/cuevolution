defmodule CuevolutionWeb.PageController do
  use CuevolutionWeb, :controller

  alias Cuevolution.Accounts

  @max_partners 4

  @partners [
    %{
      name: "Cuevolution",
      logo: "cuevolution-logo.png",
      tile_class: "bg-white",
      img_class: "h-11 w-auto object-contain"
    },
    %{
      name: "Kenya Pool Billiard Federation",
      logo: "partner-2.jpeg",
      tile_class: "bg-white",
      img_class: "h-24 w-auto scale-150 object-contain"
    }
  ]

  @doc "Signed-in players go straight to their fixtures; guests see the marketing landing page."
  def home(conn, _params) do
    token = get_session(conn, :player_token)

    if token && Accounts.get_player_by_session_token(token) do
      redirect(conn, to: ~p"/fixtures")
    else
      render(conn, :home, partners: Enum.take(@partners, @max_partners))
    end
  end

  def tos(conn, _params) do
    render(conn, :tos)
  end
end
