defmodule CuevolutionWeb.VenueFixturesExportController do
  @moduledoc "CSV download for the signed-in admin's assigned venue fixtures."

  use CuevolutionWeb, :controller

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Competitions

  plug :require_fixture_access

  def csv(conn, _params) do
    admin = conn.assigns.current_admin
    fixtures = Competitions.list_fixtures_for_venue(admin.venue_id)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="venue-fixtures-#{Date.utc_today()}.csv")
    )
    |> send_resp(200, to_csv(fixtures))
  end

  defp require_fixture_access(conn, _opts) do
    admin = conn.assigns[:current_admin]

    if Admin.can?(admin, :manage_fixtures) and admin.venue_id do
      conn
    else
      conn
      |> put_flash(:error, "You don't have access to venue fixtures.")
      |> redirect(to: ~p"/admin/dashboard")
      |> halt()
    end
  end

  defp to_csv(fixtures) do
    headers = [
      "Match ID",
      "Group",
      "Status",
      "Scheduled date",
      "Scheduled time",
      "Participant A",
      "Participant A phone",
      "Participant B",
      "Participant B phone"
    ]

    [headers | Enum.map(fixtures, &fixture_row/1)]
    |> Enum.map(fn row -> Enum.map(row, &sanitize_cell/1) end)
    |> NimbleCSV.RFC4180.dump_to_iodata()
    |> IO.iodata_to_binary()
  end

  defp fixture_row(fixture) do
    [
      fixture.match_id || "Fixture",
      fixture_group(fixture),
      fixture.status || "scheduled",
      fixture_date(fixture),
      fixture_time(fixture),
      Competitions.participant_name(fixture.participant_a),
      participant_phone(fixture.participant_a),
      Competitions.participant_name(fixture.participant_b),
      participant_phone(fixture.participant_b)
    ]
  end

  defp fixture_group(%{round: %{group: %{name: name}}}) when is_binary(name), do: name
  defp fixture_group(_fixture), do: "Knockout"

  defp participant_phone(%{player: %{mobile_number: mobile_number}}), do: mobile_number
  defp participant_phone(%{team: %{captain: %{mobile_number: mobile_number}}}), do: mobile_number
  defp participant_phone(_participant), do: ""

  defp fixture_date(%{scheduled_at: nil}), do: ""

  defp fixture_date(fixture) do
    fixture
    |> Competitions.fixture_time_in_eat()
    |> Calendar.strftime("%b %-d, %Y")
  end

  defp fixture_time(%{scheduled_at: nil}), do: ""

  defp fixture_time(fixture) do
    fixture
    |> Competitions.fixture_time_in_eat()
    |> Calendar.strftime("%H:%M")
  end

  defp sanitize_cell(value) when is_binary(value) do
    if String.starts_with?(value, ["=", "+", "-", "@"]) do
      "'" <> value
    else
      value
    end
  end
end
