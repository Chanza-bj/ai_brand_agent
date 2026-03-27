defmodule AiBrandAgent.Workers.TrendWorker do
  @moduledoc """
  Oban worker that periodically discovers topic ideas **per user** from their
  niche seeds (`user_topic_seeds`), using `AiBrandAgent.Trends.Fetcher`
  (default: `AiBrandAgent.Trends.LlmFetcher` / Gemini).

  Scheduled via Oban cron. Configure the fetcher with:

      config :ai_brand_agent, :trend_fetcher, MyApp.Trends.CustomFetcher
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Trends

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("TrendWorker: fetching niche-based trends")

    user_ids = Accounts.list_user_ids_with_enabled_seeds()

    Enum.each(Enum.with_index(user_ids), fn {user_id, idx} ->
      if idx > 0, do: Process.sleep(2_500)

      case Trends.run_fetch_for_user(user_id) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "TrendWorker: run_fetch_for_user failed user_id=#{user_id} #{inspect(reason)}"
          )
      end
    end)

    :ok
  end
end
