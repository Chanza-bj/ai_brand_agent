defmodule AiBrandAgentWeb.NichesLive do
  @moduledoc """
  CRUD for user niche seeds (phrases) used by `TrendWorker` to discover topic ideas.
  """

  use AiBrandAgentWeb, :live_view

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Workers.UserTrendFetchWorker

  on_mount {AiBrandAgentWeb.Plugs.Auth, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    seeds = Accounts.list_user_topic_seeds(user.id)

    socket =
      socket
      |> assign(:page_title, "Niches")
      |> assign(:seeds, seeds)
      |> assign(:form, to_form(%{"phrase" => ""}, as: :seed))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"seed" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :seed))}
  end

  def handle_event("add", %{"seed" => %{"phrase" => phrase}}, socket) do
    phrase = String.trim(phrase || "")

    if phrase == "" do
      {:noreply, put_flash(socket, :error, "Enter a niche phrase.")}
    else
      user = socket.assigns.current_user

      case Accounts.create_user_topic_seed(user.id, %{phrase: phrase}) do
        {:ok, _} ->
          seeds = Accounts.list_user_topic_seeds(user.id)
          _ = enqueue_topic_discovery(user.id)

          {:noreply,
           socket
           |> assign(:seeds, seeds)
           |> assign(:form, to_form(%{"phrase" => ""}, as: :seed))
           |> put_flash(
             :info,
             "Niche added. Topic ideas are generating — check your Dashboard in a minute (or sooner if Gemini is available)."
           )}

        {:error, :too_many_seeds} ->
          {:noreply, put_flash(socket, :error, "Maximum number of niches reached (10).")}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, put_flash(socket, :error, format_errors(cs))}
      end
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Accounts.get_user_topic_seed(user.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Niche not found.")}

      seed ->
        case Accounts.update_user_topic_seed(seed, %{enabled: not seed.enabled}) do
          {:ok, updated} ->
            seeds = Accounts.list_user_topic_seeds(user.id)

            if updated.enabled do
              _ = enqueue_topic_discovery(user.id)
            end

            {:noreply, assign(socket, :seeds, seeds)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not update niche.")}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Accounts.delete_user_topic_seed(user.id, id) do
      {:ok, _} ->
        seeds = Accounts.list_user_topic_seeds(user.id)
        {:noreply, assign(socket, :seeds, seeds) |> put_flash(:info, "Niche removed.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Niche not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-2xl mx-auto px-4 py-8">
        <h1 class="text-3xl font-bold mb-2">Your niches</h1>
        <p class="text-base-content/70 text-sm mb-6">
          The scheduler uses these phrases (with Gemini) to propose topic angles every 15 minutes.
          Connect LinkedIn or Facebook so drafts can be generated for your accounts.
        </p>

        <.form
          for={@form}
          id="niche-form"
          phx-submit="add"
          phx-change="validate"
          class="card bg-base-200 p-4 mb-8"
        >
          <.input
            field={@form[:phrase]}
            type="text"
            label="Add a niche"
            placeholder="e.g. sustainable fintech, OAuth security"
            required
          />
          <button type="submit" class="btn btn-primary mt-2">Add niche</button>
        </.form>

        <h2 class="text-lg font-semibold mb-3">Saved niches</h2>
        <div :if={@seeds == []} class="text-base-content/50 italic text-sm">
          None yet — add at least one to enable topic discovery.
        </div>

        <ul class="space-y-2">
          <li
            :for={seed <- @seeds}
            class="card bg-base-200 p-4 flex flex-col sm:flex-row sm:items-center gap-3"
          >
            <div class="flex-1">
              <p class="font-medium">{seed.phrase}</p>
              <p class="text-xs text-base-content/50">
                {if seed.enabled, do: "Enabled", else: "Paused"}
              </p>
            </div>
            <div class="flex gap-2">
              <button
                type="button"
                phx-click="toggle"
                phx-value-id={seed.id}
                class="btn btn-sm btn-ghost"
                id={"toggle-seed-#{seed.id}"}
              >
                {if seed.enabled, do: "Pause", else: "Enable"}
              </button>
              <button
                type="button"
                phx-click="delete"
                phx-value-id={seed.id}
                class="btn btn-sm btn-error btn-outline"
                id={"delete-seed-#{seed.id}"}
              >
                Delete
              </button>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp enqueue_topic_discovery(user_id) do
    %{user_id: user_id}
    |> UserTrendFetchWorker.new()
    |> Oban.insert()
  end

  defp format_errors(cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
