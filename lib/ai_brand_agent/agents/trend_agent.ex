defmodule AiBrandAgent.Agents.TrendAgent do
  @moduledoc """
  Coordinates trend discovery: persists user-scoped topics from `TrendWorker`,
  enqueues `ContentWorker` jobs per user, and broadcasts on PubSub.

  In-memory `get_topics/1` keeps the latest batch for debugging; the dashboard
  uses `ContentService.list_topics_for_user/2` as the source of truth.
  """

  use GenServer

  require Logger

  alias AiBrandAgent.Services.ContentService
  alias AiBrandAgent.Workers.ContentWorker

  @pubsub AiBrandAgent.PubSub
  @legacy_topic "trends:new"

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Store trending topic maps (each must include `:user_id`) and trigger content generation."
  def store_topics(topics) when is_list(topics) do
    GenServer.call(__MODULE__, {:store_topics, topics}, :timer.seconds(60))
  end

  @doc "Return the most recent `limit` topics from the in-memory buffer (best-effort)."
  def get_topics(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_topics, limit})
  end

  # ── PubSub helpers ──────────────────────────────────────────────────

  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @legacy_topic)

  # ── Server callbacks ───────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{topics: [], last_fetched_at: nil}}
  end

  @impl true
  def handle_call({:store_topics, incoming_topics}, _from, state) do
    persisted =
      Enum.reduce(incoming_topics, [], fn topic_attrs, acc ->
        user_id = Map.fetch!(topic_attrs, :user_id)

        case ContentService.find_or_create_topic_for_user(user_id, topic_attrs) do
          {:ok, topic} ->
            [topic | acc]

          {:error, reason} ->
            Logger.warning("TrendAgent: failed to persist topic: #{inspect(reason)}")
            acc
        end
      end)

    persisted = Enum.reverse(persisted)

    enqueue_content_jobs(persisted)
    broadcast_by_user(persisted)
    broadcast_legacy(persisted)

    new_state = %{
      state
      | topics: persisted ++ state.topics,
        last_fetched_at: DateTime.utc_now()
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_topics, limit}, _from, state) do
    {:reply, Enum.take(state.topics, limit), state}
  end

  # ── Private ─────────────────────────────────────────────────────────

  @publishing_platforms ["linkedin", "facebook"]

  defp enqueue_content_jobs(topics) do
    if Application.get_env(:ai_brand_agent, :enqueue_content_from_trends, true) do
      for topic <- topics,
          topic.user_id != nil,
          platform <- @publishing_platforms do
        %{topic_id: topic.id, platform: platform, user_id: topic.user_id}
        |> ContentWorker.new()
        |> Oban.insert()
      end
    end
  end

  defp broadcast_by_user(topics) do
    topics
    |> Enum.group_by(& &1.user_id)
    |> Enum.each(fn {user_id, list} when not is_nil(user_id) ->
      Phoenix.PubSub.broadcast(
        @pubsub,
        "trends:user:#{user_id}",
        {:new_topics, list}
      )
    end)
  end

  defp broadcast_legacy(topics) do
    Phoenix.PubSub.broadcast(@pubsub, @legacy_topic, {:new_topics, topics})
  end
end
