defmodule AiBrandAgent.Workers.ContentWorker do
  @moduledoc """
  Oban worker that generates social media content for a given topic.

  Enqueued by `TrendAgent` when new topics arrive, or manually from the
  dashboard. Delegates the actual generation to `ContentAgent`.
  """

  use Oban.Worker,
    queue: :content,
    max_attempts: 3,
    unique: [period: 300, keys: [:topic_id, :platform]]

  require Logger

  alias AiBrandAgent.Agents.MultiPostGenerator
  alias AiBrandAgent.Services.ContentService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"topic_id" => topic_id} = args}) do
    user_id = Map.get(args, "user_id")
    platform = Map.get(args, "platform", "linkedin")

    case ContentService.get_topic(topic_id) do
      nil ->
        Logger.warning("ContentWorker: topic #{topic_id} not found, discarding")
        :discard

      topic ->
        generate_for_users(topic, user_id, platform)
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp generate_for_users(topic, nil, platform) do
    import Ecto.Query

    user_ids =
      AiBrandAgent.Accounts.SocialConnection
      |> where(platform: ^platform)
      |> select([sc], sc.user_id)
      |> AiBrandAgent.Repo.all()

    case user_ids do
      [] ->
        Logger.info("ContentWorker: no users connected to #{platform}, skipping")
        :ok

      ids ->
        generate_sequentially(ids, topic, platform)
    end
  end

  defp generate_for_users(topic, user_id, platform) do
    case do_generate(topic, user_id, platform) do
      :ok ->
        :ok

      {:error, :rate_limited} ->
        {:snooze, gemini_rate_limit_snooze_seconds()}

      {:error, _reason} ->
        {:error, "content generation failed"}
    end
  end

  defp generate_sequentially([], _topic, _platform), do: :ok

  defp generate_sequentially([uid | rest], topic, platform) do
    case do_generate(topic, uid, platform) do
      :ok ->
        Process.sleep(2_000)
        generate_sequentially(rest, topic, platform)

      {:error, :rate_limited} ->
        Logger.warning(
          "ContentWorker: rate limited, snoozing remaining #{length(rest) + 1} user(s)"
        )

        {:snooze, gemini_rate_limit_snooze_seconds()}

      {:error, _reason} ->
        generate_sequentially(rest, topic, platform)
    end
  end

  defp do_generate(topic, user_id, platform) do
    case MultiPostGenerator.run(topic, user_id, platform) do
      {:ok, :skipped} ->
        :ok

      {:ok, _post} ->
        :ok

      {:error, :no_variants_generated} ->
        {:error, :generation_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp gemini_rate_limit_snooze_seconds do
    Application.get_env(:ai_brand_agent, :gemini, [])
    |> Keyword.get(:content_worker_snooze_seconds, 300)
  end
end
