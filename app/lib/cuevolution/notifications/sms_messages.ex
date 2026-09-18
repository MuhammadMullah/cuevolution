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
