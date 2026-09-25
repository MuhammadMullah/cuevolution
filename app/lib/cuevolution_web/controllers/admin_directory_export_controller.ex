defmodule CuevolutionWeb.AdminDirectoryExportController do
  @moduledoc """
  CSV/XLSX download of the admin directory (`PlayerDirectoryLive`), honoring
  the same filters as that page but exporting every matching row instead of
  one page. Hit by a native GET submit of `PlayerDirectoryLive`'s own
  `#player-filter-form` (see its `formaction`/`formmethod` export buttons),
  so the query string arrives nested under `filter[...]`, exactly like that
  form's `phx-change` payload — deliberately *not* a link computed from the
  LiveView's last-patched assigns, which lags a keystroke/selection behind
  whatever's actually in the form until the next server round-trip lands.
  """
  use CuevolutionWeb, :controller

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Directory

  plug :require_view_directory

  def csv(conn, params) do
    filter_params = filter_params(params)
    {players, teams} = fetch_rows(filter_params)
    body = Directory.Export.to_csv(players, teams)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="#{filename(filter_params, "csv")}")
    )
    |> send_resp(200, body)
  end

  def xlsx(conn, params) do
    filter_params = filter_params(params)
    {players, teams} = fetch_rows(filter_params)
    body = Directory.Export.to_xlsx(players, teams)

    conn
    |> put_resp_content_type("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="#{filename(filter_params, "xlsx")}")
    )
    |> send_resp(200, body)
  end

  defp require_view_directory(conn, _opts) do
    if Admin.can?(conn.assigns[:current_admin], :view_directory) do
      conn
    else
      conn
      |> put_flash(:error, "You don't have access to that page.")
      |> redirect(to: ~p"/admin/dashboard")
      |> halt()
    end
  end

  # Accepts both the form's native `?filter[region_id]=...` submission and a
  # flat `?region_id=...` query string (e.g. a hand-built or bookmarked URL).
  defp filter_params(%{"filter" => filter_params}), do: filter_params
  defp filter_params(params), do: params

  defp fetch_rows(filter_params) do
    filter_params
    |> Directory.build_filters()
    |> Directory.list_players_and_teams()
  end

  # `kind` lands in a Content-Disposition header value, so it's constrained
  # to a known-safe token rather than trusted as free-form query input.
  defp filename(params, ext) do
    kind =
      case params["kind"] do
        k when k in ["all", "male", "female", "team"] -> k
        _ -> "all"
      end

    "directory-#{kind}-#{Date.utc_today()}.#{ext}"
  end
end
