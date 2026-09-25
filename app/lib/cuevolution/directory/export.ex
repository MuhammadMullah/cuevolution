defmodule Cuevolution.Directory.Export do
  @moduledoc """
  Renders `Cuevolution.Directory.list_players_and_teams/1` output as a
  downloadable CSV or XLSX for the admin directory's export buttons —
  players as `Full Name(@username)`, teams as their name plus an inline,
  semicolon-joined roster in that same player format.
  """

  alias NimbleCSV.RFC4180, as: CSV

  @doc "`{headers, rows}` for the given players/teams — shared by `to_csv/1` and `to_xlsx/1`."
  def to_table(players, teams) do
    cond do
      teams == [] ->
        {["Player"], Enum.map(players, &[player_label(&1)])}

      players == [] ->
        {["Team", "Roster"], Enum.map(teams, &team_row/1)}

      true ->
        {["Type", "Name", "Roster"],
         Enum.map(players, &player_row/1) ++ Enum.map(teams, &team_mixed_row/1)}
    end
  end

  def to_csv(players, teams) do
    {headers, rows} = to_table(players, teams)

    [headers | rows]
    |> Enum.map(fn row -> Enum.map(row, &sanitize_cell/1) end)
    |> CSV.dump_to_iodata()
    |> IO.iodata_to_binary()
  end

  def to_xlsx(players, teams) do
    {headers, rows} = to_table(players, teams)
    sheet = %Elixlsx.Sheet{name: "Directory", rows: [headers | rows]}

    {:ok, {_filename, content}} =
      %Elixlsx.Workbook{sheets: [sheet]} |> Elixlsx.write_to_memory("directory.xlsx")

    IO.iodata_to_binary(content)
  end

  defp player_label(player), do: "#{player.first_name} #{player.last_name}(@#{player.username})"

  defp player_row(player), do: ["Player", player_label(player), ""]

  defp team_row(team), do: [team.name, roster_label(team.roster)]

  defp team_mixed_row(team), do: ["Team", team.name, roster_label(team.roster)]

  defp roster_label(roster) do
    roster |> Enum.map(&player_label/1) |> Enum.sort() |> Enum.join("; ")
  end

  # Excel/Sheets treats a cell starting with =, +, -, or @ as a formula, so a
  # team name (free text a captain chose) starting with one would execute as
  # a formula when the exported CSV is opened — force it to plain text. XLSX
  # cells are typed explicitly as text by Elixlsx, so this only applies here.
  defp sanitize_cell(value) when is_binary(value) do
    if String.starts_with?(value, ["=", "+", "-", "@"]) do
      "'" <> value
    else
      value
    end
  end
end
