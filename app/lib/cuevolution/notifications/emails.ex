defmodule Cuevolution.Notifications.Emails do
  @moduledoc """
  Builds the `Swoosh.Email` for each notification event type. Wording is an
  implementation detail (spec 002 Assumptions) — not specified by the
  business requirements. Every email gets a plain-text alternative body
  alongside the HTML one, for clients that don't render HTML.
  """
  import Swoosh.Email

  @from {"Cuevolution", "notifications@cuevolution.test"}

  @doc "Welcome email sent right after successful registration."
  def registration_confirmation(player) do
    base(player)
    |> subject("Welcome to Cuevolution!")
    |> html_body("""
    <p>Hi #{player.first_name},</p>
    <p>Your Cuevolution account is ready. You're all set to check standings, join a team, and
    get notified as soon as your fixtures are published.</p>
    <p>See you at the table!</p>
    """)
    |> text_body("""
    Hi #{player.first_name},

    Your Cuevolution account is ready. You're all set to check standings, join a team, and get
    notified as soon as your fixtures are published.

    See you at the table!
    """)
  end

  @doc """
  Sent when a fixture is created/assigned for the player. `payload` must
  contain `:opponent_name`, `:venue`, `:date`, `:time` — never the
  opponent's own contact details (spec 002 FR-010).
  """
  def fixture_assignment(player, payload) do
    %{opponent_name: opponent, venue: venue, date: date, time: time} = payload

    base(player)
    |> subject("Your next fixture: vs #{opponent}")
    |> html_body("""
    <p>Hi #{player.first_name},</p>
    <p>A new fixture has been published for you:</p>
    <p>
      <strong>Opponent:</strong> #{opponent}<br/>
      <strong>Venue:</strong> #{venue}<br/>
      <strong>Date:</strong> #{date}<br/>
      <strong>Time:</strong> #{time}
    </p>
    <p>Good luck!</p>
    """)
    |> text_body("""
    Hi #{player.first_name},

    A new fixture has been published for you:

    Opponent: #{opponent}
    Venue: #{venue}
    Date: #{date}
    Time: #{time}

    Good luck!
    """)
  end

  @doc "Sent when a captain adds the player to a team's roster."
  def team_assignment(player, payload) do
    %{team_name: team_name, captain_name: captain_name} = payload

    base(player)
    |> subject("You've been added to #{team_name}")
    |> html_body("""
    <p>Hi #{player.first_name},</p>
    <p><strong>#{captain_name}</strong> added you to <strong>#{team_name}</strong>. You can see
    your roster and teammates any time in the app.</p>
    """)
    |> text_body("""
    Hi #{player.first_name},

    #{captain_name} added you to #{team_name}. You can see your roster and teammates any time
    in the app.
    """)
  end

  defp base(player) do
    new()
    |> to({"#{player.first_name} #{player.last_name}", player.email})
    |> from(@from)
  end
end
