defmodule AiBrandAgent.Calendar.LocalScheduling do
  @moduledoc """
  Interprets posting days/times in the user's IANA timezone (not UTC wall-clock).
  """

  @doc """
  Returns true if `tzdata` can resolve the zone (IANA name, e.g. `America/Chicago`).
  """
  def valid_timezone?(tz) when is_binary(tz) do
    case DateTime.shift_zone(~U[2024-06-15 12:00:00Z], String.trim(tz)) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Next `count` instants when the user posts at `default_post_time` on `posting_weekdays`
  in `timezone`, returned as UTC `DateTime`s strictly after `now_utc`.
  """
  def next_occurrences_utc(posting_weekdays, default_post_time, timezone, now_utc, count \\ 5) do
    with {:ok, time} <- parse_time(default_post_time),
         true <- valid_timezone?(timezone) do
      tz = String.trim(timezone)
      now_utc = DateTime.truncate(now_utc, :second)
      local_now = DateTime.shift_zone!(now_utc, tz)
      local_date = DateTime.to_date(local_now)

      0..120
      |> Enum.flat_map(fn day_offset ->
        date = Date.add(local_date, day_offset)

        if Date.day_of_week(date) in posting_weekdays do
          case DateTime.new(date, time, tz) do
            {:ok, local_dt} ->
              if DateTime.compare(local_dt, local_now) == :gt do
                [DateTime.shift_zone!(local_dt, "Etc/UTC")]
              else
                []
              end

            {:ambiguous, dt1, _dt2} ->
              if DateTime.compare(dt1, local_now) == :gt do
                [DateTime.shift_zone!(dt1, "Etc/UTC")]
              else
                []
              end

            {:gap, _, _} ->
              []

            {:error, _} ->
              []
          end
        else
          []
        end
      end)
      |> Enum.take(count)
    else
      _ -> []
    end
  end

  defp parse_time(str) when is_binary(str) do
    case String.split(str, ":", parts: 2) |> Enum.map(&String.trim/1) do
      [h, m] ->
        with {hi, _} <- Integer.parse(h),
             {mi, _} <- Integer.parse(m),
             {:ok, t} <- Time.new(hi, mi, 0) do
          {:ok, t}
        else
          _ -> {:error, :invalid_time}
        end

      _ ->
        {:error, :invalid_time}
    end
  end
end
