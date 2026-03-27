defmodule AiBrandAgent.Workers.PublishWorker do
  @moduledoc """
  Oban worker that publishes an approved post via the PostAgent.

  Enqueued when a user approves a post from the dashboard.
  Handles rate limiting with Oban snooze and distinguishes between
  retryable and permanent failures.
  """

  use Oban.Worker,
    queue: :publish,
    max_attempts: 5

  require Logger

  alias AiBrandAgent.Agents.PostAgent

  @snooze_minutes 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => post_id}}) do
    case PostAgent.publish(post_id) do
      {:ok, _post} ->
        Logger.info("PublishWorker: successfully published post #{post_id}")
        :ok

      {:error, :user_busy} ->
        Logger.info("PublishWorker: user busy, snoozing post #{post_id} for #{@snooze_minutes}m")
        {:snooze, @snooze_minutes * 60}

      {:error, :rate_limited} ->
        Logger.warning("PublishWorker: rate limited, snoozing post #{post_id}")
        {:snooze, 60}

      {:error, :unauthorized} ->
        Logger.error("PublishWorker: unauthorized for post #{post_id}, not retrying")
        :discard

      {:error, {:not_publishable, status}} ->
        Logger.warning("PublishWorker: post #{post_id} not publishable (status: #{status})")
        :discard

      {:error, reason} ->
        Logger.error("PublishWorker: failed to publish post #{post_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
