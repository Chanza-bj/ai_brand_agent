import Config

# Prefer `brand_<NAME>` / `BRAND_<NAME>` for shared hosts, then standard names (see `AiBrandAgent.Config.Env`).
alias AiBrandAgent.Config.Env, as: Env

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
#     PHX_SERVER=true bin/ai_brand_agent start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if Env.get("PHX_SERVER") do
  config :ai_brand_agent, AiBrandAgentWeb.Endpoint, server: true
end

if port = Env.get("PORT") do
  config :ai_brand_agent, AiBrandAgentWeb.Endpoint, http: [port: String.to_integer(port)]
end

# Auth0 configuration from environment
if auth0_domain = Env.get("AUTH0_DOMAIN") do
  config :ai_brand_agent, :auth0,
    domain: auth0_domain,
    client_id: Env.get!("AUTH0_CLIENT_ID"),
    client_secret: Env.get!("AUTH0_CLIENT_SECRET"),
    audience: Env.get("AUTH0_AUDIENCE") || "https://#{auth0_domain}/api/v2/"
end

if fb_scope = Env.get("AUTH0_FACEBOOK_CONNECTION_SCOPE") do
  config :ai_brand_agent, :facebook_connection_scope, fb_scope
end

if li_scope = Env.get("AUTH0_LINKEDIN_CONNECTION_SCOPE") do
  config :ai_brand_agent, :linkedin_connection_scope, li_scope
end

if fb_conn = Env.get("AUTH0_FACEBOOK_CONNECTION_NAME") do
  config :ai_brand_agent, :facebook_auth0_connection, fb_conn
end

if my_scope = Env.get("AUTH0_MY_ACCOUNT_SCOPE") do
  config :ai_brand_agent, :auth0_my_account_scope, my_scope
end

# Auth0 Token Vault - RSA private key for Privileged Worker JWT signing
# Use AUTH0_TOKEN_VAULT_PRIVATE_KEY (PEM string) or AUTH0_TOKEN_VAULT_PRIVATE_KEY_PATH (file path)
token_vault_config =
  case {Env.get("AUTH0_TOKEN_VAULT_PRIVATE_KEY"), Env.get("AUTH0_TOKEN_VAULT_PRIVATE_KEY_PATH")} do
    {pk, _} when is_binary(pk) -> [private_key: pk]
    {_, path} when is_binary(path) -> [private_key_path: path]
    _ -> nil
  end

if token_vault_config do
  config :ai_brand_agent, :token_vault, token_vault_config
end

# Gemini API key from environment (merge so retry/backoff keys from config.exs stay available)
if gemini_key = Env.get("GEMINI_API_KEY") do
  prior = Application.get_env(:ai_brand_agent, :gemini) || []

  config :ai_brand_agent,
         :gemini,
         Keyword.merge(prior,
           api_key: gemini_key,
           model: Env.get("GEMINI_MODEL") || Keyword.get(prior, :model, "gemini-1.5-flash")
         )
end

# Optional: encrypt `users.auth0_refresh_token` at rest (Base64-encoded 32-byte key, AES-256-GCM).
case Env.get("AUTH0_REFRESH_TOKEN_ENCRYPTION_KEY") do
  key_b64 when is_binary(key_b64) and key_b64 != "" ->
    decoded = Base.decode64!(String.trim(key_b64))

    if byte_size(decoded) != 32 do
      raise """
      AUTH0_REFRESH_TOKEN_ENCRYPTION_KEY must be Base64 that decodes to exactly 32 bytes (AES-256).
      Generate e.g.: openssl rand -base64 32
      """
    end

    config :ai_brand_agent, :auth0_refresh_token_encryption_key, decoded

  _ ->
    :ok
end

if config_env() == :prod do
  database_url =
    Env.get("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing (or brand_DATABASE_URL / BRAND_DATABASE_URL).
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if Env.get("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :ai_brand_agent, AiBrandAgent.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(Env.get("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    Env.get("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing (or brand_SECRET_KEY_BASE / BRAND_SECRET_KEY_BASE).
      You can generate one by calling: mix phx.gen.secret
      """

  host = Env.get("PHX_HOST") || "example.com"

  # Browser-facing URL for `Routes.*_url`, flashes, Auth0 `redirect_uri`, etc.
  # Default: https://PHX_HOST:443 (TLS at reverse proxy).
  # For UAT over plain HTTP, e.g. http://SERVER_IP:4002:
  #   PHX_PUBLIC_SCHEME=http  (+ PHX_HOST / PORT); omit PHX_PUBLIC_PORT to reuse PORT.
  url_scheme =
    case Env.get("PHX_PUBLIC_SCHEME") do
      nil -> "https"
      s -> s |> String.trim() |> String.downcase()
    end

  url_scheme = if url_scheme in ["http", "https"], do: url_scheme, else: "https"

  default_public_port = fn ->
    if url_scheme == "https" do
      443
    else
      case Env.get("PORT") do
        p when is_binary(p) ->
          case String.trim(p) do
            "" -> 80
            t -> String.to_integer(t)
          end

        _ ->
          80
      end
    end
  end

  url_port =
    case Env.get("PHX_PUBLIC_PORT") do
      p when is_binary(p) ->
        case String.trim(p) do
          "" -> default_public_port.()
          t -> String.to_integer(t)
        end

      _ ->
        default_public_port.()
    end

  endpoint_opts =
    [
      url: [host: host, port: url_port, scheme: url_scheme],
      http: [
        # Enable IPv6 and bind on all interfaces.
        # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
        # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
        # for details about using IPv6 vs IPv4 and loopback vs public addresses.
        ip: {0, 0, 0, 0, 0, 0, 0, 0}
      ],
      secret_key_base: secret_key_base
    ]
    |> then(fn opts ->
      if url_scheme == "http" do
        # prod.exs enables force_ssl; disable when serving HTTP directly (IP:port UAT).
        Keyword.put(opts, :force_ssl, false)
      else
        opts
      end
    end)

  config :ai_brand_agent, :dns_cluster_query, Env.get("DNS_CLUSTER_QUERY")

  config :ai_brand_agent, AiBrandAgentWeb.Endpoint, endpoint_opts

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ai_brand_agent, AiBrandAgentWeb.Endpoint,
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
  #     config :ai_brand_agent, AiBrandAgentWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
