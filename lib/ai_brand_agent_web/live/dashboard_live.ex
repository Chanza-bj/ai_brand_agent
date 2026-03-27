defmodule AiBrandAgentWeb.DashboardLive do
  @moduledoc """
  Main dashboard LiveView.

  Shows an overview of the user's AI brand agent activity:
  recent posts, trending topics, and connected platforms.
  """

  use AiBrandAgentWeb, :live_view

  alias AiBrandAgent.Auth.TokenVault
  alias AiBrandAgent.Services.ContentService
  alias AiBrandAgent.Accounts

  on_mount {AiBrandAgentWeb.Plugs.Auth, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(AiBrandAgent.PubSub, "posts:user:#{user.id}")
      Phoenix.PubSub.subscribe(AiBrandAgent.PubSub, "trends:user:#{user.id}")
      send(self(), :refresh_google_token_vault_status)
    end

    posts = ContentService.list_posts(user.id, limit: 3)
    topics = ContentService.list_topics_for_user(user.id, 5)
    niches = Accounts.list_user_topic_seeds(user.id)
    connections = Accounts.list_connections(user.id)
    publishing_connections = Enum.filter(connections, &(&1.platform in ["linkedin", "facebook"]))

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:posts, posts)
      |> assign(:topics, topics)
      |> assign(:niches, niches)
      |> assign(:connections, connections)
      |> assign(:publishing_connections, publishing_connections)
      |> assign(:google_token_vault_ok, nil)
      |> assign_dashboard_stats()

    {:ok, socket}
  end

  @impl true
  def handle_info({:new_post, post}, socket) do
    posts = [post | socket.assigns.posts] |> Enum.take(3)

    {:noreply,
     socket
     |> assign(:posts, posts)
     |> assign_dashboard_stats()}
  end

  def handle_info({:post_published, updated_post}, socket) do
    posts =
      Enum.map(socket.assigns.posts, fn p ->
        if p.id == updated_post.id, do: updated_post, else: p
      end)

    {:noreply,
     socket
     |> assign(:posts, posts)
     |> assign_dashboard_stats()}
  end

  def handle_info({:new_topics, _topics}, socket) do
    uid = socket.assigns.current_user.id
    topics = ContentService.list_topics_for_user(uid, 5)
    niches = Accounts.list_user_topic_seeds(uid)

    {:noreply,
     socket
     |> assign(topics: topics)
     |> assign(niches: niches)}
  end

  def handle_info({:post_scheduled, %{post: scheduled}}, socket) do
    posts =
      Enum.map(socket.assigns.posts, fn p ->
        if p.id == scheduled.id, do: scheduled, else: p
      end)

    {:noreply,
     socket
     |> assign(:posts, posts)
     |> assign_dashboard_stats()}
  end

  def handle_info({:post_scheduled, _}, socket) do
    posts = ContentService.list_posts(socket.assigns.current_user.id, limit: 3)

    {:noreply,
     socket
     |> assign(:posts, posts)
     |> assign_dashboard_stats()}
  end

  def handle_info(:refresh_google_token_vault_status, socket) do
    ok =
      TokenVault.google_federated_token_vault_ok?(socket.assigns.current_user.id)

    {:noreply, assign(socket, :google_token_vault_ok, ok)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-base-content">AI Brand Agent</h1>
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
      
    <!-- Stats Cards -->
      <div class="grid grid-cols-1 md:grid-cols-5 gap-4 mb-8">
        <div class="card bg-base-200 p-4">
          <div class="text-sm text-base-content/60">Drafts</div>
          <div class="text-2xl font-bold">{@stats.drafts}</div>
        </div>
        <div class="card bg-base-200 p-4">
          <div class="text-sm text-base-content/60">Approved</div>
          <div class="text-2xl font-bold">{@stats.approved}</div>
        </div>
        <div class="card bg-base-200 p-4">
          <div class="text-sm text-base-content/60">Scheduled</div>
          <div class="text-2xl font-bold">{@stats.scheduled}</div>
        </div>
        <div class="card bg-base-200 p-4">
          <div class="text-sm text-base-content/60">Published</div>
          <div class="text-2xl font-bold">{@stats.published}</div>
        </div>
        <div class="card bg-base-200 p-4">
          <div class="text-sm text-base-content/60">Connections</div>
          <div class="text-2xl font-bold">{length(@connections)}</div>
        </div>
      </div>

      <div
        :if={@publishing_connections == []}
        class="mb-6 rounded-lg border border-warning/30 bg-warning/5 px-4 py-3 flex items-center gap-3"
      >
        <.icon name="hero-link" class="w-5 h-5 text-warning" />
        <div class="flex-1">
          <span class="text-sm font-medium">No publishing platforms connected</span>
          <span class="text-xs text-base-content/60 ml-1">
            — connect LinkedIn or Facebook to publish posts.
          </span>
        </div>
        <.link navigate={~p"/connections"} class="btn btn-xs btn-warning btn-outline">
          Connect
        </.link>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <!-- Recent Posts -->
        <div class="lg:col-span-2">
          <h2 class="text-xl font-semibold mb-4">Recent Posts</h2>
          <div :if={@posts == []} class="text-base-content/50 italic">
            No posts yet. Add <.link navigate={~p"/niches"} class="link">niches</.link>
            for AI drafts or <.link navigate={~p"/posts/new"} class="link">compose</.link>
            your own.
          </div>
          <div :for={post <- @posts} class="card bg-base-200 mb-3 p-4">
            <div class="flex items-center justify-between mb-2">
              <span class={"badge #{status_badge_class(post.status)}"}>{post.status}</span>
              <span class="text-xs text-base-content/50">{post.platform}</span>
            </div>
            <p class="text-sm line-clamp-3">{post.content}</p>
            <div class="mt-2 flex gap-2">
              <.link
                navigate={~p"/posts/#{post.id}"}
                class="text-xs text-primary hover:underline"
              >
                View details
              </.link>
            </div>
          </div>

          <.link
            :if={@posts != []}
            navigate={~p"/posts"}
            class="block text-center text-sm text-primary hover:underline mt-2"
          >
            View all posts &rarr;
          </.link>
        </div>
        
    <!-- Niches + topic ideas -->
        <div>
          <div class="mb-6">
            <div class="flex items-center justify-between gap-2 mb-2">
              <h2 class="text-lg font-semibold">Your niches</h2>
              <.link navigate={~p"/niches"} class="btn btn-xs btn-ghost">Edit</.link>
            </div>
            <div :if={@niches == []} class="text-base-content/50 italic text-sm">
              None yet — <.link navigate={~p"/niches"} class="link">add niches</.link>
              to drive topic ideas.
            </div>
            <ul :if={@niches != []} class="text-sm space-y-1 mb-1">
              <li :for={n <- @niches} class="flex justify-between gap-2">
                <span class="truncate">{n.phrase}</span>
                <span :if={not n.enabled} class="text-xs text-warning shrink-0">paused</span>
              </li>
            </ul>
          </div>

          <div class="flex items-center justify-between gap-2 mb-4">
            <h2 class="text-xl font-semibold">Topic ideas</h2>
            <.link navigate={~p"/niches"} class="btn btn-xs btn-ghost">Manage niches</.link>
          </div>
          <div :if={@topics == []} class="text-base-content/50 italic text-sm">
            No AI-generated angles yet. After you add a niche, we queue a fetch (and the scheduler runs every 15 minutes). If Gemini rate-limits, try again shortly.
          </div>
          <div :for={topic <- @topics} class="card bg-base-200 mb-2 p-3">
            <p class="text-sm font-medium">{topic.title}</p>
            <span :if={topic.source} class="text-xs text-base-content/50">{topic.source}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp assign_dashboard_stats(socket) do
    user_id = socket.assigns.current_user.id
    assign(socket, :stats, ContentService.post_dashboard_stats(user_id))
  end

  defp status_badge_class("draft"), do: "badge-ghost"
  defp status_badge_class("approved"), do: "badge-info"
  defp status_badge_class("scheduled"), do: "badge-primary"
  defp status_badge_class("publishing"), do: "badge-warning"
  defp status_badge_class("published"), do: "badge-success"
  defp status_badge_class("failed"), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"
end
