import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :cuevolution, Cuevolution.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cuevolution_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  queue_target: 5000

# Oban jobs are enqueued but never auto-processed in test; assert on them
# explicitly with Oban.Testing instead.
config :cuevolution, Oban, testing: :manual, queues: false, plugins: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :cuevolution, CuevolutionWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Aj+3lP1UgynHSLLqJQpH/WKa8FL4sb+sVRxznr7Y2k55EOSl2+U3yJD2jxkfcfwi",
  server: false

# In test we don't send emails
config :cuevolution, Cuevolution.Mailer, adapter: Swoosh.Adapters.Test

# In test we don't send SMS either — route through the Mox mock instead of
# the console-printing stub (see test/test_helper.exs for its default stub).
config :cuevolution, :sms_adapter, Cuevolution.Notifications.SmsAdapter.SmsAdapterMock

# AfricasTalkingAdapter isn't the configured :sms_adapter in test (the Mox
# mock above is), but it still has its own direct unit tests — route its
# Req calls through Req.Test instead of the network.
config :cuevolution, :africastalking,
  api_key: "test_api_key",
  username: "sandbox",
  sender_id: "CUEVO"

config :cuevolution, :africastalking_req_options,
  plug: {Req.Test, Cuevolution.Notifications.SmsAdapter.AfricasTalkingAdapter}

# :profile_picture_storage isn't set here — it stays the Storage.Local
# default (writes under this app's own priv/static), so registration_live's
# The production GCS backend has its own direct unit tests, routed through
# Mox seams for upload and IAM signing; the default profile-picture tests use
# Storage.Local and do not contact the network.
config :cuevolution, :gcs,
  bucket: "test-bucket",
  signing_service_account: "cuevolution-web@test-project.iam.gserviceaccount.com"

config :cuevolution,
       :gcs_requester,
       Cuevolution.Accounts.ProfilePicture.Storage.GCS.Requester.Mock

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
