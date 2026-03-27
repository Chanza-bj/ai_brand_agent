defmodule AiBrandAgent.Agents.CalendarAgent do
  @moduledoc """
  Calendar-aware scheduling agent backed by Google Calendar via Token Vault.

  Reads the user's calendar to find optimal posting windows, blocks
  publishing during busy periods, creates calendar events for scheduled
  posts, and surfaces upcoming events for content inspiration.
  """

  use GenServer

  require Logger

  alias AiBrandAgent.Auth.TokenVault
  alias AiBrandAgent.Services.ContentService
  alias AiBrandAgent.Social.GoogleCalendarClient
  alias AiBrandAgent.Workers.PublishWorker

  @pubsub AiBrandAgent.PubSub
  @preferred_hours [8, 9, 12, 13, 17, 18]

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Find the next optimal posting slot for a user within the next `hours` hours.

  Returns `{:ok, %DateTime{}}` or `{:error, reason}`.
  """
  def find_optimal_slot(user_id, opts \\ []) do
    GenServer.call(__MODULE__, {:find_optimal_slot, user_id, opts}, :timer.seconds(15))
  end

  @doc """
  Schedule an approved post: find a slot, create a calendar event,
  and enqueue a publish job at that time.

  Returns `{:ok, %{scheduled_at: DateTime.t(), calendar_event_id: String.t()}}` or `{:error, reason}`.
  """
  def schedule_post(post_id) do
    GenServer.call(__MODULE__, {:schedule_post, post_id}, :timer.seconds(20))
  end

  @doc """
  Like `schedule_post/1` but uses the given `DateTime` instead of discovering a slot via
  `find_optimal_slot/2`.
  """
  def schedule_post_at(post_id, %DateTime{} = slot) do
    GenServer.call(__MODULE__, {:schedule_post_at, post_id, slot}, :timer.seconds(20))
  end

  @doc """
  Check if the user is busy at the given time.

  Returns `true` or `false`. Defaults to `false` on errors (fail open).
  """
  def busy?(user_id, datetime \\ DateTime.utc_now()) do
    GenServer.call(__MODULE__, {:busy?, user_id, datetime}, :timer.seconds(10))
  end

  @doc """
  Return upcoming calendar events for the next `hours` hours.

  Returns `{:ok, [event]}` or `{:error, reason}`.
  """
  def upcoming_events(user_id, hours \\ 48) do
    GenServer.call(__MODULE__, {:upcoming_events, user_id, hours}, :timer.seconds(10))
  end

  # ── Server callbacks ────────────────────────────────────────────────

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:find_optimal_slot, user_id, opts}, _from, state) do
    {:reply, do_find_optimal_slot(user_id, opts), state}
  end

  def handle_call({:schedule_post, post_id}, _from, state) do
    {:reply, do_schedule_post(post_id), state}
  end

  def handle_call({:schedule_post_at, post_id, slot}, _from, state) do
    {:reply, do_schedule_post_at(post_id, slot), state}
  end

  def handle_call({:busy?, user_id, datetime}, _from, state) do
    {:reply, do_busy?(user_id, datetime), state}
  end

  def handle_call({:upcoming_events, user_id, hours}, _from, state) do
    {:reply, do_upcoming_events(user_id, hours), state}
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp do_find_optimal_slot(user_id, opts) do
    hours_ahead = Keyword.get(opts, :hours, 24)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    time_max = DateTime.add(now, hours_ahead * 3600, :second)

    with {:ok, token} <- get_google_token(user_id),
         {:ok, events} <- GoogleCalendarClient.list_events(token, now, time_max) do
      slot = pick_slot(events, now, time_max)
      {:ok, slot}
    end
  end

  defp do_schedule_post(post_id) do
    with {:ok, post} <- fetch_post(post_id),
         {:ok, slot} <- do_find_optimal_slot(post.user_id, hours: 24) do
      finalize_schedule(post, slot)
    end
  end

  defp do_schedule_post_at(post_id, %DateTime{} = slot) do
    with {:ok, post} <- fetch_post(post_id) do
      finalize_schedule(post, slot)
    end
  end

  defp finalize_schedule(post, slot) do
    with {:ok, calendar_event} <- create_schedule_event(post, slot),
         :ok <- enqueue_publish(post, slot),
         {:ok, updated_post} <- ContentService.mark_post_scheduled(post) do
      broadcast_scheduled(updated_post, slot)

      {:ok,
       %{
         scheduled_at: slot,
         calendar_event_id: Map.get(calendar_event, "id")
       }}
    end
  end

  defp do_busy?(user_id, datetime) do
    case get_google_token(user_id) do
      {:ok, token} -> GoogleCalendarClient.busy?(token, datetime)
      {:error, _} -> false
    end
  end

  defp do_upcoming_events(user_id, hours) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    time_max = DateTime.add(now, hours * 3600, :second)

    with {:ok, token} <- get_google_token(user_id),
         {:ok, events} <- GoogleCalendarClient.list_events(token, now, time_max) do
      {:ok, events}
    end
  end

  defp get_google_token(user_id) do
    TokenVault.get_access_token(user_id, "google")
  end

  defp fetch_post(post_id) do
    case ContentService.get_post(post_id) do
      nil -> {:error, :post_not_found}
      post -> {:ok, post}
    end
  end

  defp create_schedule_event(post, slot) do
    with {:ok, token} <- get_google_token(post.user_id) do
      event = %{
        summary: "Scheduled post: #{truncate(post.content, 60)}",
        description: "Platform: #{post.platform}\n\n#{post.content}",
        start: slot,
        end: DateTime.add(slot, 15 * 60, :second)
      }

      GoogleCalendarClient.create_event(token, event)
    end
  end

  defp enqueue_publish(post, scheduled_at) do
    %{post_id: post.id}
    |> PublishWorker.new(scheduled_at: scheduled_at)
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp pick_slot(events, now, time_max) do
    busy_ranges = extract_busy_ranges(events)

    @preferred_hours
    |> Enum.flat_map(fn hour -> candidate_times(now, time_max, hour) end)
    |> Enum.sort(DateTime)
    |> Enum.find(fn candidate ->
      DateTime.after?(candidate, now) &&
        DateTime.before?(candidate, time_max) &&
        not overlaps_any?(candidate, busy_ranges)
    end)
    |> case do
      nil -> fallback_slot(busy_ranges, now, time_max)
      slot -> slot
    end
  end

  defp candidate_times(now, time_max, hour) do
    today = DateTime.to_date(now)
    tomorrow = Date.add(today, 1)

    [today, tomorrow]
    |> Enum.map(fn date ->
      {:ok, dt} = DateTime.new(date, Time.new!(hour, 0, 0), "Etc/UTC")
      dt
    end)
    |> Enum.filter(fn dt ->
      DateTime.after?(dt, now) && DateTime.before?(dt, time_max)
    end)
  end

  defp extract_busy_ranges(events) do
    Enum.flat_map(events, fn event ->
      with start_str when is_binary(start_str) <- get_in(event, ["start", "dateTime"]),
           end_str when is_binary(end_str) <- get_in(event, ["end", "dateTime"]),
           {:ok, start_dt, _} <- DateTime.from_iso8601(start_str),
           {:ok, end_dt, _} <- DateTime.from_iso8601(end_str) do
        [{start_dt, end_dt}]
      else
        _ -> []
      end
    end)
  end

  defp overlaps_any?(candidate, busy_ranges) do
    candidate_end = DateTime.add(candidate, 15 * 60, :second)

    Enum.any?(busy_ranges, fn {busy_start, busy_end} ->
      DateTime.before?(candidate, busy_end) && DateTime.after?(candidate_end, busy_start)
    end)
  end

  defp fallback_slot(busy_ranges, now, _time_max) do
    case Enum.max_by(busy_ranges, fn {_, e} -> DateTime.to_unix(e) end, fn -> nil end) do
      {_, last_end} ->
        rounded = ceil_to_quarter_hour(last_end)
        if DateTime.after?(rounded, now), do: rounded, else: DateTime.add(now, 3600, :second)

      nil ->
        DateTime.add(now, 3600, :second)
    end
  end

  defp ceil_to_quarter_hour(dt) do
    minute = dt.minute
    next_quarter = (div(minute, 15) + 1) * 15

    if next_quarter >= 60 do
      dt
      |> Map.put(:minute, 0)
      |> Map.put(:second, 0)
      |> DateTime.add(3600, :second)
    else
      dt |> Map.put(:minute, next_quarter) |> Map.put(:second, 0)
    end
  end

  defp truncate(text, max_len) when byte_size(text) <= max_len, do: text
  defp truncate(text, max_len), do: String.slice(text, 0, max_len) <> "..."

  defp broadcast_scheduled(post, scheduled_at) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "posts:user:#{post.user_id}",
      {:post_scheduled, %{post: post, scheduled_at: scheduled_at}}
    )
  end
end
