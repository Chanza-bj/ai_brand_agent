defmodule AiBrandAgent.Social.GoogleCalendarClient do
  @moduledoc """
  Client for the Google Calendar API v3.

  All calls use an OAuth 2.0 access token retrieved from Auth0 Token Vault.
  """

  require Logger

  @base_url "https://www.googleapis.com/calendar/v3"

  @agent_event_marker "[AI Brand Agent]"

  @doc """
  True if this event is our synced posting-slot series (ignored for busy checks).
  """
  def agent_posting_slot_event?(%{"summary" => summary}) when is_binary(summary) do
    String.contains?(summary, @agent_event_marker)
  end

  def agent_posting_slot_event?(_), do: false

  @doc """
  List events from a calendar within a time range.

  Returns `{:ok, [event]}` or `{:error, reason}`.
  """
  def list_events(token, time_min, time_max, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    max_results = Keyword.get(opts, :max_results, 50)

    params = [
      timeMin: DateTime.to_iso8601(time_min),
      timeMax: DateTime.to_iso8601(time_max),
      singleEvents: true,
      orderBy: "startTime",
      maxResults: max_results
    ]

    case Req.get("#{@base_url}/calendars/#{encode(calendar_id)}/events",
           headers: auth_headers(token),
           params: params
         ) do
      {:ok, %{status: 200, body: %{"items" => items}}} ->
        {:ok, items}

      {:ok, %{status: 200, body: _}} ->
        {:ok, []}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google Calendar list_events error #{status}: #{inspect(body)}")
        {:error, {:google_calendar_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create an event on a calendar.

  `event` must include `:summary`, `:start`, `:end`.

  * `:start` / `:end` may be `%DateTime{}` or maps with `:dateTime` (RFC3339) and optional `:timeZone`.
    For `%DateTime{}`, `timeZone` is taken from `dt.time_zone` (required by Google for recurring events).
  * Optional `:recurrence` — list of RRULE strings.
  * Optional `:transparency` — `"transparent"` so the block does not mark you busy for others.
  """
  def create_event(token, event, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")

    body =
      %{
        summary: event.summary,
        description: Map.get(event, :description, ""),
        start: normalize_time_field(event.start),
        end: normalize_time_field(event.end)
      }
      |> maybe_put(:recurrence, Map.get(event, :recurrence))
      |> maybe_put(:transparency, Map.get(event, :transparency))

    case Req.post("#{@base_url}/calendars/#{encode(calendar_id)}/events",
           headers: auth_headers(token),
           json: body
         ) do
      {:ok, %{status: status, body: %{"id" => _} = created}} when status in [200, 201] ->
        {:ok, created}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google Calendar create_event error #{status}: #{inspect(body)}")
        {:error, {:google_calendar_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete an event (including a recurring series master).
  """
  def delete_event(token, event_id, opts \\ []) when is_binary(event_id) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    eid = URI.encode_www_form(event_id)

    case Req.delete("#{@base_url}/calendars/#{encode(calendar_id)}/events/#{eid}",
           headers: auth_headers(token)
         ) do
      {:ok, %{status: s}} when s in [200, 204] ->
        :ok

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Google Calendar delete_event #{status}: #{inspect(body)}")
        {:error, {:google_calendar_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if the user has **non-agent** events overlapping a given time.

  Returns `true` if there are blocking events at the given time, `false` otherwise.
  """
  def busy?(token, datetime) do
    window_start = DateTime.add(datetime, -5, :minute)
    window_end = DateTime.add(datetime, 30, :minute)

    case list_events(token, window_start, window_end) do
      {:ok, events} ->
        events
        |> Enum.reject(&agent_posting_slot_event?/1)
        |> case do
          [] -> false
          _ -> true
        end

      {:error, _} ->
        false
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  # Google requires `timeZone` on start/end when the event has recurrence (and often
  # rejects dateTime-only payloads for series). Always send IANA zone from the struct.
  defp normalize_time_field(%DateTime{} = dt) do
    tz = dt.time_zone || "Etc/UTC"
    %{dateTime: DateTime.to_iso8601(dt), timeZone: tz}
  end

  defp normalize_time_field(%{dateTime: _} = m), do: m

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp auth_headers(token) do
    [{"authorization", "Bearer #{token}"}]
  end

  defp encode(calendar_id) do
    URI.encode_www_form(calendar_id)
  end
end
