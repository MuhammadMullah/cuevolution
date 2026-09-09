import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/cuevolution start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :cuevolution, CuevolutionWeb.Endpoint, server: true
end

config :cuevolution, CuevolutionWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  secret_values =
    case System.get_env("CUEVOLUTION_SECRETS_FILE") do
      nil ->
        case System.get_env("CUEVOLUTION_SECRETS_JSON") do
          nil -> %{}
          json -> Jason.decode!(json)
        end

      path ->
        case File.read(path) do
          {:ok, json} ->
            Jason.decode!(json)

          {:error, :enoent} ->
            case System.get_env("CUEVOLUTION_SECRETS_JSON") do
              nil -> %{}
              json -> Jason.decode!(json)
            end

          {:error, reason} ->
            raise "unable to read CUEVOLUTION_SECRETS_FILE=#{path}: #{inspect(reason)}"
        end
    end

  secret = fn name -> Map.get(secret_values, name) || System.get_env(name) end

  database_url =
    secret.("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []
  db_ssl = System.get_env("DB_SSL", "true") in ~w(true 1)

  db_ssl_opts =
    if db_ssl do
      [verify: :verify_peer, cacerts: :public_key.cacerts_get()]
    else
      []
    end

  config :cuevolution, Cuevolution.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6,
    ssl: db_ssl,
    ssl_opts: db_ssl_opts

  # ## Configuring profile picture storage
  #
  # A Mix release's own priv/static lives inside the release's versioned
  # directory, replaced wholesale on every deploy — anything written there
  # (Storage.Local, the dev/test default) doesn't survive a redeploy. GCS is
  # the production object store; the bucket remains private and reads use
  # short-lived V4 signed URLs.
  case System.get_env("PROFILE_PICTURE_STORAGE", "gcs") do
    "gcs" ->
      gcs_bucket =
        System.get_env("GCS_BUCKET") ||
          raise "GCS_BUCKET is required when PROFILE_PICTURE_STORAGE=gcs"

      signing_service_account =
        System.get_env("GCS_SIGNING_SERVICE_ACCOUNT") ||
          raise "GCS_SIGNING_SERVICE_ACCOUNT is required when PROFILE_PICTURE_STORAGE=gcs"

      config :cuevolution,
             :profile_picture_storage,
             Cuevolution.Accounts.ProfilePicture.Storage.GCS

      config :cuevolution, :gcs,
        bucket: gcs_bucket,
        signing_service_account: signing_service_account

    "local" ->
      config :cuevolution,
             :profile_picture_storage,
             Cuevolution.Accounts.ProfilePicture.Storage.Local

    storage ->
      raise "unsupported PROFILE_PICTURE_STORAGE=#{storage}; expected gcs or local"
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    secret.("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :cuevolution, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :cuevolution, CuevolutionWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :cuevolution, CuevolutionWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :cuevolution, CuevolutionWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  case System.get_env("MAIL_PROVIDER", "local") do
    "smtp_relay" ->
      mail_from_address =
        System.get_env("MAIL_FROM_ADDRESS") ||
          raise "MAIL_FROM_ADDRESS is required when MAIL_PROVIDER=smtp_relay"

      config :cuevolution, :mail_from, {"Cuevolution", mail_from_address}

      config :cuevolution, Cuevolution.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: System.get_env("SMTP_RELAY", "smtp-relay.gmail.com"),
        port: 587,
        tls: :always,
        auth: :never,
        tls_options: [
          versions: [:"tlsv1.2", :"tlsv1.3"],
          verify: :verify_peer,
          depth: 5,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: ~c"smtp-relay.gmail.com"
        ]

    "smtp_auth" ->
      mail_from_address =
        System.get_env("MAIL_FROM_ADDRESS") ||
          raise "MAIL_FROM_ADDRESS is required when MAIL_PROVIDER=smtp_auth"

      smtp_username =
        secret.("SMTP_USERNAME") ||
          raise "SMTP_USERNAME is required when MAIL_PROVIDER=smtp_auth"

      smtp_password =
        secret.("SMTP_PASSWORD") ||
          raise "SMTP_PASSWORD is required when MAIL_PROVIDER=smtp_auth"

      config :cuevolution, :mail_from, {"Cuevolution", mail_from_address}

      config :cuevolution, Cuevolution.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: System.get_env("SMTP_RELAY", "smtp.gmail.com"),
        port: 587,
        username: smtp_username,
        password: smtp_password,
        tls: :always,
        auth: :always,
        tls_options: [
          versions: [:"tlsv1.2", :"tlsv1.3"],
          verify: :verify_peer,
          depth: 5,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: ~c"smtp.gmail.com"
        ]

    "local" ->
      config :cuevolution, Cuevolution.Mailer, adapter: Swoosh.Adapters.Local

    provider ->
      raise "unsupported MAIL_PROVIDER=#{provider}; expected smtp_auth, smtp_relay, or local"
  end

  # ## Configuring SMS (Africa's Talking)
  case System.get_env("SMS_PROVIDER", "africastalking") do
    "africastalking" ->
      africastalking_api_key =
        secret.("AFRICASTALKING_API_KEY") ||
          raise "AFRICASTALKING_API_KEY is required when SMS_PROVIDER=africastalking"

      africastalking_username =
        secret.("AFRICASTALKING_USERNAME") ||
          raise "AFRICASTALKING_USERNAME is required when SMS_PROVIDER=africastalking"

      config :cuevolution,
             :sms_adapter,
             Cuevolution.Notifications.SmsAdapter.AfricasTalkingAdapter

      config :cuevolution, :africastalking,
        api_key: africastalking_api_key,
        username: africastalking_username,
        sender_id: System.get_env("AFRICASTALKING_SENDER_ID")

    "stub" ->
      config :cuevolution, :sms_adapter, Cuevolution.Notifications.SmsAdapter.StubAdapter

    provider ->
      raise "unsupported SMS_PROVIDER=#{provider}; expected africastalking or stub"
  end
end
