import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ai_brand_agent, AiBrandAgent.Repo,
  username: System.get_env("DB_USERNAME") || "postgres",
  password: System.get_env("DB_PASSWORD") || "P@ssw0rd",
  hostname: System.get_env("DB_HOST") || "localhost",
  database: "ai_brand_agent_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ai_brand_agent, AiBrandAgentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4099],
  secret_key_base: "+drXdz9dNL73luqIUjBw8ulfFMFpCgDiibubZLErKkaoDD4rBbOmsFJv4O0ePBVA",
  server: false

# Inline: jobs run synchronously; `enqueue_content_from_trends` is false so TrendAgent tests do not call Gemini.
config :ai_brand_agent, Oban, testing: :inline

# Do not enqueue ContentWorker from TrendAgent in tests (avoids Gemini calls).
config :ai_brand_agent, :enqueue_content_from_trends, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true,
  colocated_js: [disable_symlink_warning: true]

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Deterministic key for RefreshTokenCrypto tests (32-byte AES-256).
config :ai_brand_agent,
       :auth0_refresh_token_encryption_key,
       :crypto.hash(:sha256, "test-suite-auth0-refresh-token-encryption-key")

# Non-production Auth0 + Gemini values (replace `config.exs` placeholders for tests).
config :ai_brand_agent, :auth0,
  domain: "test-tenant.auth0.com",
  client_id: "test-auth0-client-id",
  client_secret: "test-auth0-client-secret",
  audience: "https://test-tenant.auth0.com/api/v2/"

config :ai_brand_agent, :gemini, api_key: "test-gemini-api-key-not-used-in-tests"
