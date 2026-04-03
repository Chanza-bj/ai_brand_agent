defmodule AiBrandAgentWeb.PostsLive do
  @moduledoc """
  LiveView for browsing, reviewing, and managing posts.
  """

  use AiBrandAgentWeb, :live_view

  alias AiBrandAgent.Repo
  alias AiBrandAgent.Services.ContentService
  alias AiBrandAgentWeb.ErrorMessage
  alias AiBrandAgent.Social.FacebookClient
  alias AiBrandAgent.Workers.PublishWorker

  on_mount {AiBrandAgentWeb.Plugs.Auth, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(AiBrandAgent.PubSub, "posts:user:#{user.id}")
    end

    posts = ContentService.list_posts(user.id)

    socket =
      socket
      |> assign(:page_title, "Posts")
      |> assign(:posts, posts)
      |> assign(:filter, "all")

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    user = socket.assigns.current_user

    opts =
      case status do
        "all" -> []
        s -> [status: s]
      end

    posts = ContentService.list_posts(user.id, opts)
    {:noreply, assign(socket, posts: posts, filter: status)}
  end

  def handle_event("approve", %{"id" => post_id}, socket) do
    user = socket.assigns.current_user

    case ContentService.get_post_for_user(post_id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, ErrorMessage.post_not_found())}

      post ->
        case ContentService.approve_post(post) do
          {:ok, updated} ->
            posts = update_post_in_list(socket.assigns.posts, updated)
            {:noreply, assign(socket, posts: posts) |> put_flash(:info, "Post approved!")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, ErrorMessage.post_action(reason))}
        end
    end
  end

  def handle_event("publish", %{"id" => post_id}, socket) do
    user = socket.assigns.current_user

    case ContentService.get_post_for_user(post_id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, ErrorMessage.post_not_found())}

      _post ->
        %{post_id: post_id}
        |> PublishWorker.new()
        |> Oban.insert()

        {:noreply, put_flash(socket, :info, "Publishing queued!")}
    end
  end

  def handle_event("retry", %{"id" => post_id}, socket) do
    user = socket.assigns.current_user

    case ContentService.get_post_for_user(post_id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, ErrorMessage.post_not_found())}

      post ->
        case ContentService.retry_post(post) do
          {:ok, updated} ->
            posts = update_post_in_list(socket.assigns.posts, updated)

            {:noreply,
             assign(socket, posts: posts)
             |> put_flash(:info, "Post reset. Ready to publish again.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, ErrorMessage.post_action(reason))}
        end
    end
  end

  @impl true
  def handle_info({:new_post, post}, socket) do
    post = Repo.preload(post, :topic)
    posts = [post | socket.assigns.posts]
    {:noreply, assign(socket, posts: posts)}
  end

  def handle_info({:post_published, updated}, socket) do
    updated = Repo.preload(updated, :topic)
    posts = update_post_in_list(socket.assigns.posts, updated)
    {:noreply, assign(socket, posts: posts)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-6">Posts</h1>
      
    <!-- Filters: wrap on narrow viewports -->
      <div class="mb-6 flex flex-wrap gap-2">
        <button
          :for={s <- ["all", "draft", "approved", "scheduled", "published", "failed", "discarded"]}
          phx-click="filter"
          phx-value-status={s}
          class={"btn btn-sm shrink-0 #{if @filter == s, do: "btn-primary", else: "btn-ghost"}"}
        >
          {String.capitalize(s)}
        </button>
      </div>
      
    <!-- Post list -->
      <div :if={@posts == []} class="text-base-content/50 italic py-8 text-center">
        No posts match this filter.
      </div>

      <div :for={post <- @posts} class="card bg-base-200 mb-4 p-4 sm:p-5">
        <div class="mb-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div class="flex min-w-0 flex-wrap items-center gap-2">
            <span class={"badge #{status_badge_class(post.status)}"}>{post.status}</span>
            <span class="text-sm text-base-content/60">{post.platform}</span>
          </div>
          <time class="shrink-0 text-xs text-base-content/40">
            {Calendar.strftime(post.inserted_at, "%b %d, %Y %H:%M")}
          </time>
        </div>

        <p class="whitespace-pre-wrap text-sm mb-4">{post.content}</p>

        <div :if={topic_title(post)} class="text-xs text-base-content/50 mb-3">
          Topic: {topic_title(post)}
        </div>

        <div :if={post.error_message} class="text-xs text-error mb-3">
          Error: {post.error_message}
        </div>

        <div class="flex flex-wrap gap-2">
          <button
            :if={post.status == "draft"}
            phx-click="approve"
            phx-value-id={post.id}
            class="btn btn-sm btn-info shrink-0"
          >
            Approve
          </button>
          <button
            :if={post.status == "approved"}
            phx-click="publish"
            phx-value-id={post.id}
            class="btn btn-sm btn-success shrink-0"
          >
            Publish
          </button>
          <button
            :if={post.status == "failed"}
            phx-click="retry"
            phx-value-id={post.id}
            class="btn btn-sm btn-warning shrink-0"
          >
            Retry
          </button>
          <.link navigate={~p"/posts/#{post.id}"} class="btn btn-sm btn-ghost shrink-0">
            Details
          </.link>
          <a
            :if={
              post.status == "published" && post.platform == "facebook" &&
                FacebookClient.public_post_url(post.platform_post_id)
            }
            href={FacebookClient.public_post_url(post.platform_post_id)}
            target="_blank"
            rel="noopener noreferrer"
            class="btn btn-sm btn-ghost min-w-0 max-w-full shrink"
          >
            View on Facebook
          </a>
        </div>
      </div>
    </div>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  # `post.topic` may be NotLoaded (truthy in `:if` but invalid for `.title`) — use assoc_loaded?/1.
  defp topic_title(post) do
    if Ecto.assoc_loaded?(post.topic) && post.topic do
      post.topic.title
    end
  end

  defp update_post_in_list(posts, updated) do
    Enum.map(posts, fn p ->
      if p.id == updated.id, do: updated, else: p
    end)
  end

  defp status_badge_class("draft"), do: "badge-ghost"
  defp status_badge_class("approved"), do: "badge-info"
  defp status_badge_class("publishing"), do: "badge-warning"
  defp status_badge_class("published"), do: "badge-success"
  defp status_badge_class("failed"), do: "badge-error"
  defp status_badge_class("scheduled"), do: "badge-warning"
  defp status_badge_class("discarded"), do: "badge-ghost opacity-60"
  defp status_badge_class(_), do: "badge-ghost"
end
