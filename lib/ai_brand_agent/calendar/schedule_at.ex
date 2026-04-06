defmodule AiBrandAgent.Calendar.ScheduleAt do
  @moduledoc """
  Parses `<input type="datetime-local">` values in the user's IANA timezone and converts to UTC.

  **DST:** ambiguous local times resolve to the first matching instant; gaps (invalid local times)
  return `{:error, :invalid_local_time}`.
  """

  @doc """
  `datetime_local` is like `"2026-04-06T14:30"` (browser local, interpreted in `timezone`).

  Returns `{:ok, utc_datetime}` or `{:error, reason}`.
  """
  def parse_to_utc(datetime_local, timezone)
      when is_binary(datetime_local) and is_binary(timezone) do
    tz = String.trim(timezone)
    tz = if tz == "", do: "Etc/UTC", else: tz

    with {:ok, naive} <- naive_from_datetime_local(datetime_local),
         {:ok, dt} <- datetime_from_naive_in_zone(naive, tz) do
      utc = DateTime.shift_zone!(dt, "Etc/UTC")
      {:ok, DateTime.truncate(utc, :second)}
    else
      {:error, :invalid_local_time} = e ->
        e

      {:error, _} ->
        {:error, :invalid_datetime}

      _ ->
        {:error, :invalid_datetime}
    end
  end

  defp naive_from_datetime_local(s) do
    s = String.trim(s)

    s =
      if Regex.match?(~r/T\d{2}:\d{2}$/, s) do
        s <> ":00"
      else
        s
      end

    NaiveDateTime.from_iso8601(s)
  end

  defp datetime_from_naive_in_zone(%NaiveDateTime{} = naive, tz) do
    case DateTime.from_naive(naive, tz) do
      {:ok, dt} ->
        {:ok, dt}

      {:ambiguous, dt1, _dt2} ->
        {:ok, dt1}

      {:gap, _, _} ->
        {:error, :invalid_local_time}
    end
  end
end
