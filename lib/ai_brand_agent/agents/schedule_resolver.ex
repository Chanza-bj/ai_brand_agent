defmodule AiBrandAgent.Agents.ScheduleResolver do
  @moduledoc """
  Picks the next publish slot: prefers upcoming instances of the synced
  `[Athena] posting slots` Google Calendar series (legacy: `[AI Brand Agent] posting slots`), then falls back to
  the same schedule computed in the user's IANA timezone.

  Daily cap: 3 published posts per **local** calendar day (fixed product limit).
  """

  require Logger

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Agents.CalendarAgent
  alias AiBrandAgent.Auth.TokenVault
  alias AiBrandAgent.Calendar.LocalScheduling
  alias AiBrandAgent.Services.ContentService
  alias AiBrandAgent.Social.GoogleCalendarClient

  @max_posts_per_day 3

  @doc """
  Schedules an **approved** post: picks a slot, then creates calendar event + Oban publish job.
  """
  def schedule_approved_post(post_id, user_id) do
    case ContentService.get_post_for_user(post_id, user_id) do
      nil ->
        {:error, :not_found}

      post ->
        if post.status != "approved" do
          {:error, {:invalid_status, post.status}}
        else
          do_schedule(post)
        end
    end
  end

  defp do_schedule(post) do
    user_id = post.user_id
    pref = Accounts.get_posting_preferences_for_user(user_id)

    with :ok <- check_daily_cap(user_id, pref),
         {:ok, slot} <- next_open_slot(user_id, pref) do
      CalendarAgent.schedule_post_at(post.id, post.user_id, slot)
    end
  end

  defp check_daily_cap(user_id, pref) do
    n = ContentService.count_published_posts_in_local_calendar_day(user_id, pref.timezone)

    if n >= @max_posts_per_day do
      Logger.info("ScheduleResolver: daily cap reached user=#{user_id} n=#{n}")
      {:error, :daily_cap}
    else
      :ok
    end
  end

  defp next_open_slot(user_id, pref) do
    case next_slot_from_google(user_id) do
      {:ok, %DateTime{} = slot} ->
        pick_if_not_busy(user_id, slot, pref)

      _ ->
        fallback_local_slots(user_id, pref)
    end
  end

  defp next_slot_from_google(user_id) do
    with {:ok, token} <- TokenVault.get_access_token(user_id, "google") do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      time_max = DateTime.add(now, 28 * 86400, :second)

      case GoogleCalendarClient.list_events(token, now, time_max, max_results: 100) do
        {:ok, events} ->
          events
          |> Enum.filter(&GoogleCalendarClient.agent_posting_slot_event?/1)
          |> Enum.map(&parse_event_start_utc/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort(DateTime)
          |> Enum.find(fn dt -> DateTime.compare(dt, now) == :gt end)
          |> case do
            nil -> {:error, :no_google_slot}
            dt -> {:ok, dt}
          end

        e ->
          e
      end
    end
  end

  defp parse_event_start_utc(%{"start" => %{"dateTime" => iso}}) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt} -> dt
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_event_start_utc(_), do: nil

  defp pick_if_not_busy(user_id, slot, pref) do
    if CalendarAgent.busy?(user_id, slot) do
      fallback_local_slots(user_id, pref)
    else
      {:ok, slot}
    end
  end

  defp fallback_local_slots(user_id, pref) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    slots =
      LocalScheduling.next_occurrences_utc(
        pref.posting_weekdays,
        pref.default_post_time,
        pref.timezone,
        now,
        21
      )

    case Enum.find(slots, fn slot -> not CalendarAgent.busy?(user_id, slot) end) do
      %DateTime{} = s ->
        {:ok, s}

      nil ->
        case slots do
          [first | _] -> {:ok, first}
          [] -> {:error, :no_slot}
        end
    end
  end

  @doc """
  Next suggested slots for the UI (UTC instants that match local weekday + time).
  """
  def suggested_slots(_user_id, pref, n \\ 5) do
    LocalScheduling.next_occurrences_utc(
      pref.posting_weekdays,
      pref.default_post_time,
      pref.timezone,
      DateTime.utc_now() |> DateTime.truncate(:second),
      n
    )
  end
end
