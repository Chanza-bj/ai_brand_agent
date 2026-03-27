defmodule AiBrandAgentWeb.ConnectionsLive do
  @moduledoc """
  LiveView for managing social platform connections.

  Users can connect or disconnect LinkedIn and Facebook accounts.
  Connections are mediated through Auth0 — this page initiates the
  OAuth flow and displays the current connection status.
  """

  use AiBrandAgentWeb, :live_view

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Accounts.SocialConnection
  alias AiBrandAgent.Auth.TokenVault

  on_mount {AiBrandAgentWeb.Plugs.Auth, :require_auth}

  @platforms ["linkedin", "facebook"]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    connections = Accounts.list_connections(user.id)

    socket =
      socket
      |> assign(:page_title, "Connections")
      |> assign(:connections, connections)
      |> assign(:platforms, @platforms)
      |> assign(:facebook_pages, [])
      |> assign(:facebook_pages_status, :idle)
      |> assign(:google_token_vault_ok, nil)

    # Defer so the LiveView process is ready before external calls (Graph API, Auth0).
    Process.send_after(self(), :load_facebook_pages, 0)
    Process.send_after(self(), :refresh_google_token_vault_status, 0)

    {:ok, socket}
  end

  @impl true
  def handle_event("disconnect", %{"id" => connection_id}, socket) do
    case Accounts.delete_connection(connection_id) do
      {:ok, _} ->
        connections = Accounts.list_connections(socket.assigns.current_user.id)

        socket =
          socket
          |> assign(:connections, connections)
          |> assign(:facebook_pages, [])
          |> assign(:facebook_pages_status, :idle)

        {:noreply, socket |> put_flash(:info, "Disconnected!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to disconnect")}
    end
  end

  def handle_event("set_facebook_page", %{"page_id" => page_id}, socket) do
    user = socket.assigns.current_user

    case Accounts.set_facebook_default_page(user.id, page_id) do
      {:ok, updated} ->
        connections = update_connection_in_list(socket.assigns.connections, updated)

        {:noreply,
         socket
         |> assign(:connections, connections)
         |> put_flash(:info, "Default Facebook Page updated")}

      {:error, :invalid_page_id} ->
        {:noreply, put_flash(socket, :error, "Invalid Page ID (use digits only).")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save default page.")}
    end
  end

  def handle_event("refresh_facebook_pages", _params, socket) do
    send(self(), :load_facebook_pages)
    {:noreply, assign(socket, :facebook_pages_status, :loading)}
  end

  def handle_info(:refresh_google_token_vault_status, socket) do
    ok =
      TokenVault.google_federated_token_vault_ok?(socket.assigns.current_user.id)

    {:noreply, assign(socket, :google_token_vault_ok, ok)}
  end

  @impl true
  def handle_info(:load_facebook_pages, socket) do
    user = socket.assigns.current_user
    connections = socket.assigns.connections

    if find_connection("facebook", connections) == nil do
      {:noreply,
       socket
       |> assign(:facebook_pages, [])
       |> assign(:facebook_pages_status, :idle)}
    else
      case Accounts.list_facebook_pages(user.id) do
        {:ok, pages} ->
          {:noreply,
           socket
           |> assign(:facebook_pages, pages)
           |> assign(:facebook_pages_status, :ok)}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(:facebook_pages, [])
           |> assign(:facebook_pages_status, :error)}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-bold">Connected Accounts</h1>
        <p class="text-base-content/70 mt-1 flex flex-wrap items-center gap-2">
          <span>Welcome back, {@current_user.name}</span>
          <%= cond do %>
            <% @google_token_vault_ok == true -> %>
              <span class="inline-flex" role="img" aria-label="Auth0 Token Vault for Google: OK">
                <.icon name="hero-check-circle" class="w-5 h-5 shrink-0 text-success" />
              </span>
            <% @google_token_vault_ok == false -> %>
              <span
                class="inline-flex"
                role="img"
                aria-label="Auth0 Token Vault for Google: not ready"
              >
                <.icon name="hero-x-circle" class="w-5 h-5 shrink-0 text-error" />
              </span>
            <% true -> %>
              <span class="inline-flex" role="img" aria-label="Checking Auth0 Token Vault status">
                <.icon
                  name="hero-arrow-path"
                  class="w-5 h-5 shrink-0 text-base-content/40 animate-spin"
                />
              </span>
          <% end %>
        </p>
      </div>

      <h2 class="text-lg font-semibold mb-3 text-base-content/80">Publishing Platforms</h2>

      <div :for={platform <- @platforms} class="card bg-base-200 mb-4 p-5">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="font-semibold text-lg capitalize">{platform_label(platform)}</h3>
            <p class="text-xs text-base-content/40 mb-1">{platform_description(platform)}</p>
            <p :if={connected?(platform, @connections)} class="text-sm text-success">
              Connected
            </p>
            <p :if={!connected?(platform, @connections)} class="text-sm text-base-content/50">
              Not connected
            </p>
          </div>

          <div>
            <.link
              :if={!connected?(platform, @connections)}
              href={~p"/auth/connect/#{platform}"}
              class="btn btn-sm btn-primary"
            >
              Connect
            </.link>

            <button
              :if={connection = find_connection(platform, @connections)}
              phx-click="disconnect"
              phx-value-id={connection.id}
              class="btn btn-sm btn-error btn-outline"
              data-confirm="Disconnect this account?"
            >
              Disconnect
            </button>
          </div>
        </div>

        <%= case {platform, find_connection(platform, @connections)} do %>
          <% {"facebook", fb} when not is_nil(fb) -> %>
            <div class="mt-4 pt-4 border-t border-base-300 w-full">
              <p class="text-sm font-medium text-base-content/80 mb-1">Default Page for publishing</p>
              <p class="text-xs text-base-content/50 mb-3">
                Posts go to one Page. Choose it here, or leave <span class="font-medium">Auto</span>
                to use the first Page Facebook returns.
              </p>
              <form phx-change="set_facebook_page" id="facebook-default-page-form">
                <label class="sr-only" for="facebook-page-select">Default Facebook Page</label>
                <select
                  id="facebook-page-select"
                  name="page_id"
                  class="select select-bordered select-sm w-full max-w-md"
                >
                  <option value="" selected={is_nil(fb.platform_user_id) || fb.platform_user_id == ""}>
                    Auto (first available Page)
                  </option>
                  <option
                    :for={p <- @facebook_pages}
                    value={p.id}
                    selected={fb.platform_user_id == p.id}
                  >
                    {p.name} ({p.id})
                  </option>
                </select>
              </form>
              <p :if={@facebook_pages_status == :loading} class="text-xs text-base-content/40 mt-2">
                Loading Pages…
              </p>
              <div
                :if={@facebook_pages_status == :error}
                class="text-xs text-warning mt-2 flex flex-wrap items-center gap-2"
              >
                <span>Could not load Pages from Facebook.</span>
                <button type="button" phx-click="refresh_facebook_pages" class="link link-primary">
                  Try again
                </button>
              </div>
              <p
                :if={@facebook_pages_status == :ok && @facebook_pages == []}
                class="text-xs text-warning mt-2"
              >
                No Pages returned. Create a Page or check Meta / Auth0 Page permissions.
              </p>
            </div>
          <% _ -> %>
        <% end %>
      </div>

      <div class="mt-6 text-sm text-base-content/50">
        <p>
          Connections are managed through Auth0. LinkedIn and Facebook tokens are read at publish time via the Auth0 Management API (not stored in this app). Google login uses Token Vault for Calendar when enabled.
        </p>
      </div>
    </div>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp connected?(platform, connections) do
    Enum.any?(connections, &(&1.platform == platform))
  end

  defp find_connection(platform, connections) do
    Enum.find(connections, &(&1.platform == platform))
  end

  defp update_connection_in_list(connections, %SocialConnection{} = updated) do
    Enum.map(connections, fn c ->
      if c.id == updated.id, do: updated, else: c
    end)
  end

  defp platform_label("google"), do: "Google Calendar"
  defp platform_label(platform), do: String.capitalize(platform)

  defp platform_description("google"), do: "Smart scheduling and busy-time blocking"
  defp platform_description("linkedin"), do: "Professional network publishing"
  defp platform_description("facebook"), do: "Social media publishing"
end
