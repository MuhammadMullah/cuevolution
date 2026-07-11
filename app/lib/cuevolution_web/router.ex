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

    live_session :player_guest do
      live "/register", RegistrationLive, :new
      live "/login", PlayerLoginLive, :new
    end

    post "/login", PlayerSessionController, :create
    delete "/logout", PlayerSessionController, :delete
  end

  scope "/", CuevolutionWeb do
    pipe_through [:browser, :player_required]

    live_session :player_authenticated, on_mount: [{CuevolutionWeb.PlayerAuth, :ensure_player}] do
      live "/fixtures", FixturesLive, :index
      live "/standings", StandingsLive, :index
      live "/profile", ProfileSettingsLive, :edit
      live "/team", TeamDashboardLive, :show
      live "/team/new", TeamCreationLive, :new
    end
  end

  scope "/admin", CuevolutionWeb do
    pipe_through :browser

    live_session :admin_guest do
      live "/login", AdminLoginLive, :new
    end

    post "/login", AdminSessionController, :create
    delete "/logout", AdminSessionController, :delete
  end

  scope "/admin", CuevolutionWeb do
    pipe_through [:browser, :admin_required]

    live_session :admin_authenticated, on_mount: [{CuevolutionWeb.AdminAuth, :ensure_admin}] do
      live "/dashboard", AdminDashboardLive, :index
      live "/players", PlayerDirectoryLive, :index
      live "/players/:id", PlayerDetailLive, :show
      live "/venues", VenueManagementLive, :index
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
