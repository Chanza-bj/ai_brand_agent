defmodule AiBrandAgent.Trends.Fetcher do
  @moduledoc """
  Behaviour for turning user niche seeds into discovered topic rows.

  Default implementation: `AiBrandAgent.Trends.LlmFetcher` (Gemini suggests angles).
  Configure with `config :ai_brand_agent, :trend_fetcher, MyFetcher` (must implement this module).
  """

  alias AiBrandAgent.Accounts.User

  @doc """
  Given a user and their enabled seeds, returns maps ready for `ContentService.find_or_create_topic_for_user/2`:

  Each map must include at least: `title`, `user_id`, optional `source`, `metadata`, `user_topic_seed_id`.
  """
  @callback fetch_for_user(user :: User.t(), seeds :: [struct()]) ::
              {:ok, [map()]} | {:error, term()}
end
