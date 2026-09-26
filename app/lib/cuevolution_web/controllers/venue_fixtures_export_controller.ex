defmodule CuevolutionWeb.VenueFixturesExportController do
  @moduledoc "PDF download for the signed-in admin's assigned venue or region fixtures."

  use CuevolutionWeb, :controller

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Competitions
  alias Cuevolution.Repo
  alias Cuevolution.Venues.Venue
  import Ecto.Query

  plug :require_fixture_access

  def pdf(conn, params) do
    admin = Repo.preload(conn.assigns.current_admin, [:venue, :region])

    fixtures =
      case admin.role do
        "regional_coordinator" ->
          Competitions.list_fixtures_for_region(
            admin.region_id,
            valid_region_venue_id(admin, params)
          )

        "venue_representative" ->
          Competitions.list_fixtures_for_venue(admin.venue_id)
      end

    {venue_name, stage_name} = pdf_metadata(admin, params, fixtures)

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="venue-fixtures-#{Date.utc_today()}.pdf")
    )
    |> send_resp(200, CuevolutionWeb.FixturePdf.render(fixtures, venue_name, stage_name))
  end

  defp require_fixture_access(conn, _opts) do
    admin = conn.assigns[:current_admin]

    if Admin.can?(admin, :manage_fixtures) and
         ((admin.role == "venue_representative" and not is_nil(admin.venue_id)) or
            (admin.role == "regional_coordinator" and not is_nil(admin.region_id))) do
      conn
    else
      conn
      |> put_flash(:error, "You don't have access to venue fixtures.")
      |> redirect(to: ~p"/admin/dashboard")
      |> halt()
    end
  end

  defp valid_region_venue_id(%Admin{role: "regional_coordinator", region_id: region_id}, params)
       when is_binary(region_id) do
    venue_id = params["venue_id"]

    if is_binary(venue_id) and venue_id != "" and
         Repo.exists?(
           from v in Venue, where: v.id == ^venue_id and v.region_id == ^region_id and v.active
         ) do
      venue_id
    else
      nil
    end
  end

  defp valid_region_venue_id(_admin, _params), do: nil

  defp pdf_metadata(
         %Admin{role: "regional_coordinator", region_id: region_id, region: region},
         params,
         fixtures
       ) do
    venue_id =
      valid_region_venue_id(%Admin{role: "regional_coordinator", region_id: region_id}, params)

    venue_name =
      if venue_id do
        Repo.get!(Venue, venue_id).name
      else
        "All venues in #{region.name}"
      end

    {venue_name, stage_name(fixtures)}
  end

  defp pdf_metadata(%Admin{role: "venue_representative", venue: venue}, _params, fixtures),
    do: {venue.name, stage_name(fixtures)}

  defp stage_name(fixtures) do
    names =
      fixtures
      |> Enum.map(&fixture_stage_name/1)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    case names do
      [] -> "All stages"
      names -> Enum.join(names, ", ")
    end
  end

  defp fixture_stage_name(%{round: %{stage: %{name: name}}}) when is_binary(name), do: name
  defp fixture_stage_name(_fixture), do: nil
end
