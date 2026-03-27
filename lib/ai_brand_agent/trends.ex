defmodule AiBrandAgent.Trends do
  @moduledoc """
  Orchestrates niche → topic discovery for a user (used by `TrendWorker` and one-off jobs).
  """

  require Logger

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Agents.TrendAgent

  @doc """
  Runs the configured `AiBrandAgent.Trends.Fetcher` for one user and persists topics via `TrendAgent`.

  Returns `:ok` or `{:error, reason}`.
  """
  def run_fetch_for_user(user_id) when is_binary(user_id) do
    fetcher = Application.get_env(:ai_brand_agent, :trend_fetcher, AiBrandAgent.Trends.LlmFetcher)

    case Accounts.get_user(user_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        seeds = Accounts.list_enabled_seeds_for_user(user_id)

        cond do
          seeds == [] ->
            :ok

          true ->
            case fetcher.fetch_for_user(user, seeds) do
              {:ok, topic_maps} when topic_maps != [] ->
                TrendAgent.store_topics(topic_maps)
                :ok

              {:ok, _} ->
                :ok

              {:error, reason} = err ->
                Logger.warning(
                  "Trends.run_fetch_for_user: fetch failed user_id=#{user_id} #{inspect(reason)}"
                )

                err
            end
        end
    end
  end
end
