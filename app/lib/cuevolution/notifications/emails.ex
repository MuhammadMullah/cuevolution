defmodule Cuevolution.Notifications.Emails do
  @moduledoc """
  Builds the `Swoosh.Email` for each notification event type. Wording is an
  implementation detail (spec 002 Assumptions) — not specified by the
  business requirements. Every email gets a plain-text alternative body
  alongside the HTML one, for clients that don't render HTML.

  HTML bodies share `layout/2` and `button/2` (ink/red branding matching
  the landing page — see assets/css/app.css) and use a table-based,
  inline-styled layout since email clients don't reliably support external
  stylesheets. Any player-supplied or captain-supplied string (name, team
  name, venue, etc.) is HTML-escaped before interpolation — these values
  aren't sanitized at the source, and an unescaped one could break the
  layout or inject markup into a rendered email.
  """
  import Swoosh.Email

  alias Cuevolution.Accounts.Admin
  alias CuevolutionWeb.Endpoint

  @ink "#0d0c22"
  @body_bg "#f0efec"
  @text "#16152b"
  @text_muted "#6b6a78"
  @red "#e32219"

  @doc "Welcome email sent right after successful registration."
  def registration_confirmation(player) do
    first_name = esc(player.first_name)

    base(player)
    |> subject("Welcome to Sportpesa National Pool Circuit!")
    |> html_body(
      layout("""
      <p style="margin:0 0 16px;">Hi #{first_name},</p>
      <p style="margin:0 0 16px;">
        Your Sportpesa National Pool Circuit account is ready. You're officially part of Kenya's pool circuit.
      </p>
      <p style="margin:0 0 16px;">Here's what happens next:</p>
      <ul style="margin:0 0 16px;padding-left:20px;">
        <li style="margin-bottom:8px;">
          <strong>JJoin or start a team</strong>. Team play is optional, but it's the fastest way into circuit fixtures.
        </li>
        <li style="margin-bottom:8px;">
          <strong>Check standings</strong> any time to see how players and teams in your region
          are ranked.
        </li>
        <li style="margin-bottom:8px;">
          <strong>Watch your inbox.</strong> We'll email you the moment a fixture is published.

        </li>
      </ul>
      #{button("Log In", url("/login"))}
      <p style="margin:24px 0 0;">See you at the table!</p>
      """)
    )
    |> text_body("""
    Hi #{player.first_name},

    Your Sportpesa National Pool Circuit account is ready, and you're officially part of Kenya's pool circuit.

    Here's what happens next:
    - Join or start a team — team play is optional, but it's the fastest way into circuit fixtures.
    - Check standings any time to see how players and teams in your region are ranked.
    - Watch your inbox. We'll email you the moment a fixture is published.

    Log in any time: #{url("/login")}

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
    first_name = esc(player.first_name)

    base(player)
    |> subject("Your next fixture: vs #{opponent}")
    |> html_body(
      layout("""
      <p style="margin:0 0 16px;">Hi #{first_name},</p>
      <p style="margin:0 0 16px;">A new fixture has been published for you:</p>
      #{fixture_table(opponent, venue, date, time)}
      #{button("View My Fixtures", url("/fixtures"))}
      <p style="margin:24px 0 0;">Good luck!</p>
      """)
    )
    |> text_body("""
    Hi #{player.first_name},

    A new fixture has been published for you:

    Opponent: #{opponent}
    Venue:    #{venue}
    Date:     #{date}
    Time:     #{time}

    See all your fixtures: #{url("/fixtures")}

    Good luck!
    """)
  end

  @doc "Sent when a captain adds the player to a team's roster."
  def team_assignment(player, payload) do
    %{team_name: team_name, captain_name: captain_name} = payload
    first_name = esc(player.first_name)
    team_name_esc = esc(team_name)
    captain_name_esc = esc(captain_name)

    base(player)
    |> subject("You've been added to #{team_name}")
    |> html_body(
      layout("""
      <p style="margin:0 0 16px;">Hi #{first_name},</p>
      <p style="margin:0 0 16px;">
        <strong>#{captain_name_esc}</strong> added you to <strong>#{team_name_esc}</strong>.
        You can see your roster and teammates any time in the app.
      </p>
      #{button("View My Team", url("/team"))}
      """)
    )
    |> text_body("""
    Hi #{player.first_name},

    #{captain_name} added you to #{team_name}. You can see your roster and teammates any time
    in the app.

    View your team: #{url("/team")}
    """)
  end

  @doc """
  Password-reset link email (spec 011). Sent via a standalone worker, not
  `Notifications.dispatch/3` — see that worker's moduledoc for why.
  """
  def reset_password_instructions(player, url) do
    first_name = esc(player.first_name)

    base(player)
    |> subject("Reset your password")
    |> html_body(
      layout("""
      <p style="margin:0 0 16px;">Hi #{first_name},</p>
      <p style="margin:0 0 16px;">
        We got a request to reset your password. Click below to choose a new one —
        this link expires in 20 minutes.
      </p>
      #{button("Reset My Password", url)}
      <p style="margin:24px 0 0;">
        If you didn't request this, you can safely ignore this email — your password won't
        change.
      </p>
      """)
    )
    |> text_body("""
    Hi #{player.first_name},

    We got a request to reset your password. Use the link below to choose a new
    one — it expires in 20 minutes.

    #{url}

    If you didn't request this, you can safely ignore this email — your password won't change.
    """)
  end

  @doc """
  Sent to a newly invited admin, with a link to set their password and
  mobile number before they can sign in.
  """
  def admin_invitation(%Admin{} = admin, url) do
    role_label = Admin.role_label(admin.role)

    new()
    |> to(admin.email)
    |> from(Application.get_env(:cuevolution, :mail_from))
    |> subject("You've been invited to the Sportpesa National Pool League admin team")
    |> html_body(
      layout("""
      <p style="margin:0 0 16px;">Hi,</p>
      <p style="margin:0 0 16px;">
        You've been added as a <strong>#{role_label}</strong> on the Sportpesa National Pool
        League admin team. Set your password and mobile number below to get started —
        this link expires in 7 days.
      </p>
      #{button("Set Up My Account", url)}
      <p style="margin:24px 0 0;">
        If you weren't expecting this invitation, you can safely ignore this email.
      </p>
      """)
    )
    |> text_body("""
    Hi,

    You've been added as a #{role_label} on the Sportpesa National Pool League admin team.

    Set your password and mobile number to get started — this link expires in 7 days:

    #{url}

    If you weren't expecting this invitation, you can safely ignore this email.
    """)
  end

  defp base(player) do
    new()
    |> to({"#{player.first_name} #{player.last_name}", player.email})
    |> from(Application.get_env(:cuevolution, :mail_from))
  end

  defp url(path), do: Endpoint.url() <> path

  defp esc(string), do: string |> Plug.HTML.html_escape() |> to_string()

  defp fixture_table(opponent, venue, date, time) do
    """
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
      style="margin:0 0 20px;border:1px solid #e5e3df;border-radius:8px;overflow:hidden;">
      #{fixture_row("Opponent", esc(opponent))}
      #{fixture_row("Venue", esc(venue))}
      #{fixture_row("Date", esc(date))}
      #{fixture_row("Time", esc(time))}
    </table>
    """
  end

  defp fixture_row(label, value) do
    """
    <tr>
      <td style="padding:10px 16px;background-color:#{@body_bg};font-size:13px;
        color:#{@text_muted};width:96px;border-bottom:1px solid #e5e3df;">#{label}</td>
      <td style="padding:10px 16px;font-size:14px;font-weight:600;color:#{@text};
        border-bottom:1px solid #e5e3df;">#{value}</td>
    </tr>
    """
  end

  defp button(text, href) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" class="cta-table" style="margin:8px 0 4px;">
      <tr>
        <td style="border-radius:8px;background-color:#{@red};">
          <a href="#{href}" class="cta-link" style="display:inline-block;padding:12px 28px;
            font-size:14px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;
            text-align:center;">#{text}</a>
        </td>
      </tr>
    </table>
    """
  end

  # Fluid table (width="100%" capped by max-width) so it already shrinks to
  # fit a phone screen without a media query. The <meta viewport> tag is
  # what actually matters on top of that — several mobile mail clients
  # otherwise render at a fixed desktop width and force pinch-zoom even
  # though the table itself is fluid. The @media block on top is the usual
  # "hybrid coding" layer: inline styles are the safe fallback for clients
  # that ignore <style> in <head>, the media query tightens padding and
  # makes the CTA full-width/easier to tap on small screens for the many
  # clients that do support it (Apple/Gmail/Outlook.com apps).
  defp layout(inner_html) do
    """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="color-scheme" content="light">
        <meta name="supported-color-schemes" content="light">
        <style>
          @media only screen and (max-width: 480px) {
            .email-header, .email-content, .email-footer { padding-left: 20px !important; padding-right: 20px !important; }
            .cta-table { width: 100% !important; }
            .cta-link { display: block !important; width: 100% !important; }
          }
        </style>
      </head>
      <body style="margin:0;padding:0;background-color:#{@body_bg};">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
          style="background-color:#{@body_bg};padding:32px 16px;">
          <tr>
            <td align="center">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
                style="max-width:560px;background-color:#ffffff;border-radius:12px;
                overflow:hidden;font-family:'Mona Sans',Inter,-apple-system,'Helvetica Neue',
                Arial,sans-serif;">
                <tr>
                  <td class="email-header" style="background-color:#{@ink};padding:24px 32px;text-align:center;">
                    <img src="#{url("/images/SP-pool-blue-logo-white.png")}" alt="Cuevolution"
                      height="36" style="height:36px;display:inline-block;border:0;">
                  </td>
                </tr>
                <tr>
                  <td class="email-content" style="padding:32px;font-size:15px;line-height:1.6;color:#{@text};">
                    #{inner_html}
                  </td>
                </tr>
                <tr>
                  <td class="email-footer" style="padding:20px 32px;background-color:#{@body_bg};text-align:center;
                    font-size:12px;color:#{@text_muted};">
                    © #{Date.utc_today().year} Sportpesa National Pool Circuit. All rights reserved.<br>
                    You're receiving this email because you have an account on Sportpesa National Pool Circuit.
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end
end
