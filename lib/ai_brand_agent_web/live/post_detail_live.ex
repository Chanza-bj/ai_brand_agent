defmodule AiBrandAgentWeb.PostDetailLive do
  @moduledoc """
  LiveView for viewing and editing a single post.
  """

  use AiBrandAgentWeb, :live_view

  require Logger

  alias AiBrandAgent.Accounts.Post
  alias AiBrandAgent.Agents.CalendarAgent
  alias AiBrandAgent.Services.ContentService
  alias AiBrandAgent.Social.FacebookClient
  alias AiBrandAgent.Workers.PublishWorker

  on_mount {AiBrandAgentWeb.Plugs.Auth, :require_auth}

  @impl true
  def mount(%{"id" => post_id}, _session, socket) do
    case ContentService.get_post(post_id, [:topic]) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Post not found")
         |> redirect(to: ~p"/posts")}

      post ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(AiBrandAgent.PubSub, "posts:user:#{post.user_id}")
        end

        socket =
          socket
          |> assign(:page_title, "Post Detail")
          |> assign(:post, post)
          |> assign(:editing, false)
          |> assign(:edit_content, post.content)
          |> assign(:scheduled_at, nil)

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: false, edit_content: socket.assigns.post.content)}
  end

  def handle_event("save_content", %{"content" => content}, socket) do
    case ContentService.update_post_content(socket.assigns.post, content) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_post(updated)
         |> assign(editing: false, edit_content: content)
         |> put_flash(:info, "Content updated")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Update failed: #{inspect(reason)}")}
    end
  end

  def handle_event("approve", _params, socket) do
    case ContentService.approve_post(socket.assigns.post) do
      {:ok, updated} ->
        {:noreply, put_post(socket, updated) |> put_flash(:info, "Post approved!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot approve: #{inspect(reason)}")}
    end
  end

  def handle_event("schedule", _params, socket) do
    case CalendarAgent.schedule_post(socket.assigns.post.id) do
      {:ok, %{scheduled_at: scheduled_at}} ->
        {:noreply,
         socket
         |> assign(:scheduled_at, scheduled_at)
         |> put_flash(
           :info,
           "Post scheduled for #{Calendar.strftime(scheduled_at, "%b %d at %H:%M UTC")}"
         )}

      {:error, reason} ->
        Logger.warning(
          "Calendar scheduling failed: #{inspect(reason)}, falling back to immediate publish"
        )

        do_immediate_publish(socket)
    end
  end

  def handle_event("publish", _params, socket) do
    do_immediate_publish(socket)
  end

  def handle_event("retry", _params, socket) do
    case ContentService.retry_post(socket.assigns.post) do
      {:ok, updated} ->
        {:noreply,
         put_post(socket, updated) |> put_flash(:info, "Post reset. Ready to publish again.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot retry: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:post_published, updated}, socket) do
    if updated.id == socket.assigns.post.id do
      {:noreply, put_post(socket, updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:post_scheduled, %{post: post, scheduled_at: scheduled_at}}, socket) do
    if post.id == socket.assigns.post.id do
      {:noreply, assign(socket, scheduled_at: scheduled_at)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-8">
      <.link navigate={~p"/posts"} class="text-sm text-primary hover:underline mb-4 block">
        &larr; Back to posts
      </.link>

      <div class="card bg-base-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <span class={"badge #{status_badge_class(@post.status)}"}>{@post.status}</span>
            <span class="text-sm text-base-content/60">{@post.platform}</span>
          </div>
          <time class="text-xs text-base-content/40">
            {Calendar.strftime(@post.inserted_at, "%b %d, %Y %H:%M")}
          </time>
        </div>

        <div :if={@post.topic} class="mb-4">
          <span class="text-xs text-base-content/50">Topic:</span>
          <span class="text-sm font-medium ml-1">{@post.topic.title}</span>
        </div>
        
    <!-- Content display/edit -->
        <div :if={!@editing} class="mb-4">
          <p class="whitespace-pre-wrap">{@post.content}</p>
        </div>

        <form :if={@editing} phx-submit="save_content" class="mb-4">
          <textarea
            name="content"
            rows="8"
            class="textarea textarea-bordered w-full"
          >{@edit_content}</textarea>
          <div class="flex gap-2 mt-2">
            <button type="submit" class="btn btn-sm btn-primary">Save</button>
            <button type="button" phx-click="cancel_edit" class="btn btn-sm btn-ghost">Cancel</button>
          </div>
        </form>

        <div :if={@post.published_at} class="text-xs text-base-content/50 mb-2">
          Published at: {Calendar.strftime(@post.published_at, "%b %d, %Y %H:%M")}
        </div>

        <div :if={@post.platform_post_id} class="text-xs text-base-content/50 mb-2 space-y-1">
          <div>Platform ID: {@post.platform_post_id}</div>
          <a
            :if={facebook_view_url(@post)}
            href={facebook_view_url(@post)}
            target="_blank"
            rel="noopener noreferrer"
            class="link link-primary text-sm"
          >
            View on Facebook →
          </a>
        </div>

        <div :if={@post.error_message} class="text-xs text-error mb-4">
          Error: {@post.error_message}
        </div>

        <div
          :if={@scheduled_at}
          class="flex items-center gap-2 text-sm text-info mb-4 bg-info/10 rounded-lg px-3 py-2"
        >
          <.icon name="hero-clock" class="w-4 h-4" />
          <span>Scheduled for {Calendar.strftime(@scheduled_at, "%b %d, %Y at %H:%M UTC")}</span>
        </div>
        
    <!-- Actions -->
        <div class="flex gap-2 mt-4 border-t border-base-300 pt-4">
          <button
            :if={@post.status == "draft" && !@editing}
            phx-click="edit"
            class="btn btn-sm btn-ghost"
          >
            Edit
          </button>
          <button
            :if={@post.status == "draft"}
            phx-click="approve"
            class="btn btn-sm btn-info"
          >
            Approve
          </button>
          <button
            :if={@post.status == "approved"}
            phx-click="schedule"
            class="btn btn-sm btn-primary"
          >
            <.icon name="hero-clock" class="w-4 h-4" /> Smart Schedule
          </button>
          <button
            :if={@post.status == "approved"}
            phx-click="publish"
            class="btn btn-sm btn-success"
          >
            Publish Now
          </button>
          <button
            :if={@post.status == "failed"}
            phx-click="retry"
            class="btn btn-sm btn-warning"
          >
            <.icon name="hero-arrow-path" class="w-4 h-4" /> Retry
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp put_post(socket, %Post{} = post) do
    case ContentService.get_post(post.id, [:topic]) do
      nil -> assign(socket, :post, post)
      loaded -> assign(socket, :post, loaded)
    end
  end

  defp do_immediate_publish(socket) do
    %{post_id: socket.assigns.post.id}
    |> PublishWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Publishing queued!")}
  end

  defp facebook_view_url(%{platform: "facebook", platform_post_id: id}) when is_binary(id) do
    FacebookClient.public_post_url(id)
  end

  defp facebook_view_url(_), do: nil

  defp status_badge_class("draft"), do: "badge-ghost"
  defp status_badge_class("approved"), do: "badge-info"
  defp status_badge_class("scheduled"), do: "badge-primary"
  defp status_badge_class("publishing"), do: "badge-warning"
  defp status_badge_class("published"), do: "badge-success"
  defp status_badge_class("failed"), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"
end
