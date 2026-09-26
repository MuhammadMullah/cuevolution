defmodule CuevolutionWeb.Router do
  use CuevolutionWeb, :router

  import CuevolutionWeb.AdminAuth
  import CuevolutionWeb.PlayerAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CuevolutionWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :admin_required do
    plug :fetch_current_admin
    plug :require_admin
  end

  pipeline :player_required do
    plug :fetch_current_player
    plug :require_player
  end

  scope "/", CuevolutionWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/legal/tos", PageController, :tos

    live_session :player_guest do
      live "/register", RegistrationLive, :new
      live "/login", PlayerLoginLive, :new
      live "/forgot-password", ForgotPasswordLive, :new
      live "/reset-password/:token", ResetPasswordLive, :new
    end

    post "/login", PlayerSessionController, :create
    delete "/logout", PlayerSessionController, :delete
  end

  scope "/health", CuevolutionWeb do
    get "/live", HealthController, :live
    get "/startup", HealthController, :startup
    get "/readiness", HealthController, :readiness
  end

  scope "/", CuevolutionWeb do
    pipe_through [:browser, :player_required]

    live_session :player_authenticated, on_mount: [{CuevolutionWeb.PlayerAuth, :ensure_player}] do
      live "/fixtures", FixturesLive, :index
      live "/my-group", Player.MyGroupLive, :index
      live "/standings", StandingsLive, :index
      live "/profile", ProfileSettingsLive, :profile
      live "/profile/settings", ProfileSettingsLive, :settings
      live "/team", TeamDashboardLive, :show
      live "/team/new", TeamCreationLive, :new
    end
  end

  scope "/admin", CuevolutionWeb do
    pipe_through :browser

    live_session :admin_guest do
      live "/login", AdminLoginLive, :new
      live "/setup/:token", AdminSetupLive, :new
    end

    post "/login", AdminSessionController, :create
    delete "/logout", AdminSessionController, :delete
  end

  scope "/admin", CuevolutionWeb do
    pipe_through [:browser, :admin_required]

    live_session :admin_authenticated, on_mount: [{CuevolutionWeb.AdminAuth, :ensure_admin}] do
      live "/dashboard", AdminDashboardLive, :index
    end

    live_session :admin_fixture_operations,
      on_mount: [
        {CuevolutionWeb.AdminAuth, :ensure_admin},
        {CuevolutionWeb.AdminAuth, {:ensure_permission, :manage_fixtures}}
      ] do
      live "/draws", AdminDrawsLive, :index
      live "/venue-fixtures", VenueFixturesLive, :index
    end

    live_session :admin_result_operations,
      on_mount: [
        {CuevolutionWeb.AdminAuth, :ensure_admin},
        {CuevolutionWeb.AdminAuth, {:ensure_permission, :record_results}}
      ] do
      live "/results", AdminResultsLive, :index
      live "/matches/:id", Admin.MatchEntryLive, :show
    end

    live_session :admin_operations,
      on_mount: [
        {CuevolutionWeb.AdminAuth, :ensure_admin},
        {CuevolutionWeb.AdminAuth, {:ensure_permission, :manage_stages}}
      ] do
      live "/stages", StageManagementLive, :index
      live "/groups", GroupManagementLive, :index
    end

    live_session :admin_directory,
      on_mount: [
        {CuevolutionWeb.AdminAuth, :ensure_admin},
        {CuevolutionWeb.AdminAuth, {:ensure_permission, :view_directory}}
      ] do
      live "/players", PlayerDirectoryLive, :index
      live "/players/:id", PlayerDetailLive, :show
      live "/venues/:id/players", VenuePlayersLive, :show
    end

    get "/directory/export.csv", AdminDirectoryExportController, :csv
    get "/directory/export.xlsx", AdminDirectoryExportController, :xlsx
    get "/venue-fixtures/export.csv", VenueFixturesExportController, :csv

    live_session :admin_team_management,
      on_mount: [
        {CuevolutionWeb.AdminAuth, :ensure_admin},
        {CuevolutionWeb.AdminAuth, {:ensure_permission, :manage_teams}}
      ] do
      live "/teams/new", Admin.TeamCreationLive, :new
      live "/teams/:id", TeamDetailLive, :show
    end

    live_session :admin_venue_management,
      on_mount: [
        {CuevolutionWeb.AdminAuth, :ensure_admin},
        {CuevolutionWeb.AdminAuth, {:ensure_permission, :manage_venues}}
      ] do
      live "/venues", VenueManagementLive, :index
    end

    live_session :admin_notifications,
      on_mount: [
        {CuevolutionWeb.AdminAuth, :ensure_admin},
        {CuevolutionWeb.AdminAuth, {:ensure_permission, :view_directory}}
      ] do
      live "/notifications", NotificationLogLive, :index
      live "/audit-log", Admin.AuditLogLive, :index
    end

    live_session :admin_user_management,
      on_mount: [
        {CuevolutionWeb.AdminAuth, :ensure_admin},
        {CuevolutionWeb.AdminAuth, {:ensure_permission, :manage_admins}}
      ] do
      live "/admins", AdminManagementLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", CuevolutionWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:cuevolution, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CuevolutionWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
