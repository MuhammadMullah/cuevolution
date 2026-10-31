defmodule Cuevolution.Notifications.SmsMessages do
  @moduledoc """
  Builds the plain-text SMS body for each notification event type. Kept
  short — SMS is billed/limited per segment by most providers.
  """

  @doc "Welcome SMS sent right after successful registration."
  def registration_confirmation(player) do
    "Hi #{player.first_name}, welcome to SportPesa National Pool Circuit! Your account is ready, check standings " <>
      "and fixtures any time in the app."
  end

  @doc """
  Sent when a fixture is created/assigned for the player. `payload` must
  contain `:opponent_name`, `:venue`, `:date`, `:time` — never the
  opponent's own contact details (spec 002 FR-010).
  """
  def fixture_assignment(_player, payload) do
    %{opponent_name: opponent, venue: venue, date: date, time: time} = payload

    "SportPesa National Pool Circuit: You've been drawn vs #{opponent} at #{venue} on #{date} #{time}. Good luck!"
  end

  def draw_published(_player, _payload) do
    "SportPesa National Pool Circuit: You've been drawn. Log in to see your fixtures. Carry a copy of your ID for verification at your matches."
  end

  def grassroots_match_reminder(_player, %{deadline: deadline}) do
    "SportPesa National Pool Circuit: You have scheduled Grassroots fixtures. Finish your matches before #{deadline} to avoid a double walkover. Log in to view fixtures."
  end

  def grassroots_deadline_apology(_player, %{deadline: deadline}) do
    "SportPesa National Pool Circuit: We apologize for the incorrect Grassroots deadline. The correct deadline is #{deadline}. Please complete your scheduled matches before this date."
  end

  def birthday_greeting(_player) do
    "On behalf of Sportpesa and the entire pool community, we wish you a very happy birthday! Have a fantastic day."
  end

  @doc """
  One-off announcement of Circuit 1 (Timba XO, Eldoret, 6-8 November 2026) to
  the players who qualified for it. The email carries the full wording; this
  is the condensed version.

  Deliberately kept to 150 characters, plain hyphen and no emoji: that keeps
  it GSM-7 and so a single billed segment. An en dash or an emoji anywhere in
  the body forces the whole message to UCS-2 (67 chars per concatenated
  segment instead of 153) — the full-length wording bills as 7 segments per
  recipient, this bills as 1.
  """
  def circuit_advancement(_player) do
    "Congratulations on securing your place in the SportPesa National Pool Circuit 2026/27! " <>
      "Circuit 1 is at Timba XO, Eldoret, 6-8 Nov. See you in Eldoret!"
  end

  @doc "Sent when a captain adds the player to a team's roster."
  def team_assignment(_player, payload) do
    %{team_name: team_name} = payload

    "SportPesa National Pool Circuit: You've been added to #{team_name}. Check the app for your roster."
  end

  @doc "Sent when a captain invites the player to join a team's roster."
  def team_invitation(_player, payload) do
    %{team_name: team_name, captain_name: captain_name} = payload

    "SportPesa National Pool Circuit: #{captain_name} invited you to join #{team_name}. Sign in to accept/decline " <>
      "within 48 hours."
  end

  def team_player_left(_player, payload) do
    %{
      team_name: team_name,
      player_name: player_name,
      roster_count: roster_count,
      eligible: eligible
    } =
      payload

    status =
      if eligible,
        do: "The team is still eligible.",
        else: "The team is below the minimum and not eligible."

    "SportPesa National Pool Circuit: #{player_name} left #{team_name}. Roster: #{roster_count}. #{status}"
  end

  def player_location_updated(_player, payload) do
    %{region_name: region_name, venue_name: venue_name} = payload
    "SportPesa National Pool Circuit: Your location was updated to #{region_name}, #{venue_name}."
  end

  @doc """
  Sent when a player’s preferred venue is deactivated.

  `payload` must include `:venue_name` and `:suggested_venues`. The suggestions
  list may be empty.

  """
  def venue_deactivated(_player, payload) do
    %{venue_name: venue_name, suggested_venues: suggested_venues} = payload

    "SportPesa National Pool Circuit: Your venue #{venue_name} has closed.#{suggestion_clause(suggested_venues)} " <>
      "Update your venue in the app."
  end

  defp suggestion_clause([]), do: ""

  defp suggestion_clause(suggested_venues),
    do: " Suggestions: #{Enum.join(suggested_venues, ", ")}."
end
