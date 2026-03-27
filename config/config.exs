# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :ai_brand_agent,
  ecto_repos: [AiBrandAgent.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :ai_brand_agent, AiBrandAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AiBrandAgentWeb.ErrorHTML, json: AiBrandAgentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AiBrandAgent.PubSub,
  live_view: [signing_salt: "xp4dMivk"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  ai_brand_agent: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  ai_brand_agent: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban configuration
config :ai_brand_agent, Oban,
  repo: AiBrandAgent.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/15 * * * *", AiBrandAgent.Workers.TrendWorker},
       {"0 * * * *", AiBrandAgent.Workers.DraftPrunerWorker},
       {"15 * * * *", AiBrandAgent.Workers.MetricsSyncWorker}
     ]}
  ],
  queues: [default: 10, content: 1, publish: 5]

# Facebook OAuth: permissions forwarded to Meta on “Connect Facebook” (`connection_scope`).
# Meta requires comma-separated permissions, not spaces. Override: AUTH0_FACEBOOK_CONNECTION_SCOPE.
config :ai_brand_agent, :facebook_connection_scope, "pages_show_list,pages_manage_posts"

# LinkedIn OAuth: space-separated scopes on “Connect LinkedIn” (`connection_scope`).
# Must include w_member_social for UGC posting. Override: AUTH0_LINKEDIN_CONNECTION_SCOPE.
config :ai_brand_agent, :linkedin_connection_scope, "openid profile email w_member_social"

# Auth0 Social connection name for Facebook (override if you created a new connection without legacy scopes).
config :ai_brand_agent, :facebook_auth0_connection, "facebook"

# My Account API: scopes for refresh-token exchange (audience https://<tenant>/me/). Connected Accounts.
config :ai_brand_agent,
       :auth0_my_account_scope,
       "openid profile offline_access create:me:connected_accounts read:me:connected_accounts delete:me:connected_accounts"

# Google scopes requested during Connected Accounts `connect` (JSON array body).
config :ai_brand_agent, :google_connected_accounts_scopes, [
  "openid",
  "profile",
  "email",
  "https://www.googleapis.com/auth/calendar.events"
]

# Auth0 configuration (override in runtime.exs with env vars)
config :ai_brand_agent, :auth0,
  domain: "dev-677l58koldj2zef6.us.auth0.com",
  client_id: "YhMo6wJk3vrdzj4q1FVvgFbjydr7zQPg",
  client_secret: "CAhNLwh-GF4SdgpXV_zPw_K8Nxc0l9JIy6Iqg2SDc_bKegT6msevlkkC_HXKjuT-",
  audience: "https://dev-677l58koldj2zef6.us.auth0.com/api/v2/"

# Auth0 Token Vault (Privileged Worker flow)
# Configure in runtime.exs via AUTH0_TOKEN_VAULT_PRIVATE_KEY (PEM string) or
# AUTH0_TOKEN_VAULT_PRIVATE_KEY_PATH (file path).
# See: https://auth0.com/docs/secure/tokens/token-vault/privileged-worker-token-exchange-with-token-vault

# Gemini API configuration
# See `Gemini` env vars in `runtime.exs` for production. Rate limits: free tier is strict;
# increase backoff and snooze below, or use a paid Gemini tier / fewer scheduled jobs.
config :ai_brand_agent, :gemini,
  api_key: "AIzaSyDNt4Qj4lV6OZBCt9Qr25WfEk-ZkOmHEEA",
  model: "gemini-2.5-flash",
  # HTTP 429 retries (inside LLMClient; keep total wait under ContentAgent GenServer timeout)
  max_retries: 4,
  initial_backoff_ms: 8_000,
  max_backoff_ms: 60_000,
  rate_limit_retry_after_cap_ms: 90_000,
  # Oban ContentWorker snooze when Gemini returns :rate_limited after retries
  content_worker_snooze_seconds: 300

# Niche → topic discovery (Token Vault / trends). Swap for News API, RSS, etc.
config :ai_brand_agent, :trend_fetcher, AiBrandAgent.Trends.LlmFetcher

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
# mix run priv/scripts/register_credential.exs
