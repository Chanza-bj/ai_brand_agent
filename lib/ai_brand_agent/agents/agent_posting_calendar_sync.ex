defmodule AiBrandAgent.Agents.AgentPostingCalendarSync do
  @moduledoc """
  Writes the user's posting weekdays + local time to Google Calendar as a **transparent**
  recurring event so (1) the schedule is visible in the calendar app and (2) the agent can
  read upcoming instances when scheduling a post.

  Events with this summary are ignored by `busy?` checks so they do not block publishing.
  """

  require Logger

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Auth.TokenVault
  alias AiBrandAgent.Calendar.LocalScheduling
  alias AiBrandAgent.Social.GoogleCalendarClient

  @event_summary "[AI Brand Agent] posting slots"

  @doc "Public summary prefix so `GoogleCalendarClient` can filter agent events."
  def event_summary, do: @event_summary

  @doc """
  Deletes any previously synced recurring series and creates a new one.
  Persists `agent_calendar_recurring_event_id` on the prefs row.
  """
  def sync_user_schedule(user_id) when is_binary(user_id) do
    pref = Accounts.get_posting_preferences_for_user(user_id)

    with {:ok, token} <- TokenVault.get_access_token(user_id, "google") do
      _ = maybe_delete_previous(token, pref.agent_calendar_recurring_event_id)

      case create_recurring_series(token, pref) do
        {:ok, %{"id" => id}} ->
          Accounts.update_agent_calendar_recurring_event_id(user_id, id)

        {:error, _} = err ->
          err
      end
    end
  end

  defp maybe_delete_previous(_token, nil), do: :ok

  defp maybe_delete_previous(token, event_id) when is_binary(event_id) do
    _ = GoogleCalendarClient.delete_event(token, event_id)
    :ok
  end

  defp create_recurring_series(token, pref) do
    tz = String.trim(pref.timezone)
    weekdays = pref.posting_weekdays

    with {:ok, time} <- parse_time(pref.default_post_time),
         true <- LocalScheduling.valid_timezone?(tz),
         {:ok, local_start} <- first_dtstart(weekdays, time, tz) do
      local_end = DateTime.add(local_start, 15 * 60, :second)
      byday = rrule_byday(weekdays)
      rrule = "RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=#{byday}"

      event = %{
        summary: @event_summary,
        description:
          "Preferred posting windows for AI Brand Agent. Transparent (does not block your calendar for others).",
        start: local_start,
        end: local_end,
        recurrence: [rrule],
        transparency: "transparent"
      }

      GoogleCalendarClient.create_event(token, event)
    else
      false -> {:error, :invalid_timezone}
      {:error, _} = err -> err
      _ -> {:error, :invalid_schedule}
    end
  end

  defp first_dtstart(weekdays, time, tz) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    local_now = DateTime.shift_zone!(now, tz)
    local_date = DateTime.to_date(local_now)

    result =
      Enum.find_value(0..21, fn offset ->
        d = Date.add(local_date, offset)

        if Date.day_of_week(d) in weekdays do
          case DateTime.new(d, time, tz) do
            {:ok, dt} ->
              if DateTime.compare(dt, local_now) == :gt, do: {:ok, dt}

            {:ambiguous, dt1, _} ->
              if DateTime.compare(dt1, local_now) == :gt, do: {:ok, dt1}

            _ ->
              nil
          end
        else
          nil
        end
      end)

    case result do
      {:ok, _} = ok -> ok
      nil -> {:error, :no_slot}
    end
  end

  defp rrule_byday(weekdays) do
    weekdays
    |> Enum.sort()
    |> Enum.map(
      &Map.fetch!(
        %{
          1 => "MO",
          2 => "TU",
          3 => "WE",
          4 => "TH",
          5 => "FR",
          6 => "SA",
          7 => "SU"
        },
        &1
      )
    )
    |> Enum.join(",")
  end

  defp parse_time(str) when is_binary(str) do
    case String.split(str, ":", parts: 2) |> Enum.map(&String.trim/1) do
      [h, m] ->
        with {hi, _} <- Integer.parse(h),
             {mi, _} <- Integer.parse(m),
             {:ok, t} <- Time.new(hi, mi, 0) do
          {:ok, t}
        else
          _ -> {:error, :invalid}
        end

      _ ->
        {:error, :invalid}
    end
  end
end
