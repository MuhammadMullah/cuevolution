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
  pool_size: System.schedulers_online() * 2

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

# TwilioAdapter isn't the configured :sms_adapter in test either — it also
# has its own direct unit tests, routed through a Mox mock of the client
# seam (ex_twilio uses HTTPoison directly, with no pluggable test
# transport, unlike Req/Req.Test above).
config :ex_twilio, account_sid: "test_account_sid", auth_token: "test_auth_token"
config :cuevolution, :twilio, from: "+15005550006"

config :cuevolution,
       :twilio_client,
       Cuevolution.Notifications.SmsAdapter.TwilioAdapter.Client.Mock

# :profile_picture_storage isn't set here — it stays the Storage.Local
# default (writes under this app's own priv/static), so registration_live's
# upload test doesn't need any network mocking. Storage.S3 has its own
# direct unit tests, routed through a Mox mock of the request seam
# (ex_aws uses hackney directly, with no pluggable test transport) — its
# url/1 needs no mocking at all, since presigning is local computation.
config :cuevolution, :s3, bucket: "test-bucket"

config :ex_aws,
  access_key_id: "test_access_key_id",
  secret_access_key: "test_secret",
  region: "us-east-1"

config :cuevolution,
       :s3_requester,
       Cuevolution.Accounts.ProfilePicture.Storage.S3.Requester.Mock

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
