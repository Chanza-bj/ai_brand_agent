defmodule AiBrandAgent.Repo do
  use Ecto.Repo,
    otp_app: :ai_brand_agent,
    adapter: Ecto.Adapters.Postgres
end
