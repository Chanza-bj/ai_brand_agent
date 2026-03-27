defmodule AiBrandAgentWeb.AgentSettingsLive do
  @moduledoc """
  Posting schedule: local weekday + time in your IANA timezone, synced to Google Calendar
  for the agent. Winning drafts are always auto-approved and scheduled (max 3 publishes per local day).
  """

  use AiBrandAgentWeb, :live_view

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Accounts.UserPostingPreference
  alias AiBrandAgent.Agents.AgentPostingCalendarSync
  alias AiBrandAgent.Agents.ScheduleResolver

  on_mount {AiBrandAgentWeb.Plugs.Auth, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    pref = Accounts.get_posting_preferences_for_user(user.id)
    suggested = ScheduleResolver.suggested_slots(user.id, pref, 5)

    socket =
      socket
      |> assign(:page_title, "Agent settings")
      |> assign(:pref, pref)
      |> assign(:weekday_selection, pref.posting_weekdays)
      |> assign(:suggested_slots, suggested)
      |> assign(:weekday_options, weekday_options())
      |> assign(:form, pref_form(pref))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"posting" => params}, socket) do
    weekdays = parse_weekdays_param(params["weekdays"])

    {:noreply,
     socket
     |> assign(:weekday_selection, weekdays)
     |> assign(:form, to_form(params, as: :posting))}
  end

  def handle_event("save", %{"posting" => params}, socket) do
    user = socket.assigns.current_user
    weekdays = parse_weekdays_param(params["weekdays"])
    socket = assign(socket, :weekday_selection, weekdays)

    attrs = %{
      timezone: String.trim(Map.get(params, "timezone") || "Etc/UTC"),
      default_post_time: String.trim(Map.get(params, "default_post_time") || "09:00"),
      posting_weekdays: weekdays
    }

    case Accounts.upsert_posting_preferences(user.id, attrs) do
      {:ok, pref} ->
        sync_result = AgentPostingCalendarSync.sync_user_schedule(user.id)
        suggested = ScheduleResolver.suggested_slots(user.id, pref, 5)

        info =
          case sync_result do
            {:ok, _} ->
              "Saved. Your posting windows are on Google Calendar; the agent uses them when scheduling."

            {:error, :invalid_timezone} ->
              "Saved, but timezone is invalid — fix it to sync Google Calendar."

            {:error, :unauthorized} ->
              "Saved, but Google Calendar could not authorize — reconnect Google (Token Vault)."

            {:error, _} ->
              "Saved, but Google Calendar sync failed (check connection and logs)."

            _ ->
              "Saved."
          end

        {:noreply,
         socket
         |> assign(:pref, pref)
         |> assign(:weekday_selection, pref.posting_weekdays)
         |> assign(:suggested_slots, suggested)
         |> assign(:form, pref_form(pref))
         |> put_flash(:info, info)}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         socket
         |> assign(:form, to_form(cs, as: :posting))
         |> put_flash(:error, format_errors(cs))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-2xl mx-auto px-4 py-8">
        <h1 class="text-3xl font-bold mb-2">Agent settings</h1>
        <p class="text-base-content/70 text-sm mb-6">
          Choose <span class="font-medium">local</span> days and time using an IANA timezone
          (e.g. <code class="text-xs bg-base-300 px-1 rounded">America/Chicago</code>).
          The same schedule is written to Google Calendar; the agent reads those slots when it auto-schedules.
          Winning AI variants are always approved and queued (max 3 published posts per local day).
        </p>

        <.form
          for={@form}
          id="agent-posting-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
        >
          <div class="card bg-base-200 p-5 space-y-3">
            <h2 class="font-semibold text-lg">Posting days &amp; time</h2>
            <p class="text-xs text-base-content/50">
              Mon = 1 … Sun = 7. Time is interpreted in the timezone below (not UTC).
            </p>
            <div class="flex flex-wrap gap-3">
              <%= for {d, label} <- @weekday_options do %>
                <label class="label cursor-pointer gap-2">
                  <input
                    type="checkbox"
                    name="posting[weekdays][]"
                    value={d}
                    checked={d in @weekday_selection}
                    class="checkbox checkbox-sm"
                  />
                  <span class="label-text">{label}</span>
                </label>
              <% end %>
            </div>
            <.input
              field={@form[:timezone]}
              type="text"
              label="Timezone (IANA)"
              placeholder="America/Chicago"
            />
            <.input
              field={@form[:default_post_time]}
              type="text"
              label="Post time (24h, local to timezone above)"
              placeholder="10:00"
            />
          </div>

          <button type="submit" class="btn btn-primary" id="agent-posting-save">
            Save &amp; sync calendar
          </button>
        </.form>

        <div class="mt-8 card bg-base-200/50 border border-base-300 p-5">
          <h2 class="font-semibold text-lg mb-2">Next suggested slots</h2>
          <p class="text-xs text-base-content/50 mb-3">
            Computed in your timezone (same logic the agent uses if Calendar is empty).
          </p>
          <ul :if={@suggested_slots != []} class="space-y-1 text-sm font-mono">
            <li :for={slot <- @suggested_slots}>
              {format_slot_local(slot, @pref.timezone)}
            </li>
          </ul>
          <p :if={@suggested_slots == []} class="text-sm text-base-content/50">
            No upcoming slots — adjust weekdays or time.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_slot_local(%DateTime{} = utc, tz) when is_binary(tz) do
    if AiBrandAgent.Calendar.LocalScheduling.valid_timezone?(tz) do
      utc
      |> DateTime.shift_zone!(String.trim(tz))
      |> Calendar.strftime("%a %b %d %Y %H:%M")
      |> then(&(&1 <> " (" <> tz <> ")"))
    else
      Calendar.strftime(utc, "%a %b %d %Y %H:%M UTC")
    end
  end

  defp weekday_options do
    [{1, "Mon"}, {2, "Tue"}, {3, "Wed"}, {4, "Thu"}, {5, "Fri"}, {6, "Sat"}, {7, "Sun"}]
  end

  # HTML omits unchecked boxes; all unchecked => no key. Do not default here — UI and validation
  # must agree (previously nil defaulted to Mon–Fri on save and checkboxes read stale @pref).
  defp parse_weekdays_param(nil), do: []

  defp parse_weekdays_param(list) when is_list(list) do
    list
    |> Enum.map(&String.to_integer/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp parse_weekdays_param(one) when is_binary(one), do: [String.to_integer(one)]

  defp pref_form(%UserPostingPreference{} = pref) do
    to_form(
      %{
        "timezone" => pref.timezone,
        "default_post_time" => pref.default_post_time
      },
      as: :posting
    )
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end
end
