defmodule AiBrandAgentWeb.PostDetailLive do
  @moduledoc """
  LiveView for viewing and editing a single post.

  **Smart Schedule** uses `ScheduleResolver` (Agent timezone, weekdays, default time, optional
  Google “posting slots” calendar)—not a free-form datetime picker.
  """

  use AiBrandAgentWeb, :live_view

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Accounts.Post
  alias AiBrandAgent.Agents.{CalendarAgent, ScheduleResolver}
  alias AiBrandAgent.Services.{ContentService, PublishingService}
  alias AiBrandAgentWeb.ErrorMessage
  alias AiBrandAgent.Social.FacebookClient
  alias AiBrandAgent.Workers.PublishWorker

  on_mount {AiBrandAgentWeb.Plugs.Auth, :require_auth}

  @impl true
  def mount(%{"id" => post_id}, _session, socket) do
    user = socket.assigns.current_user

    case ContentService.get_post_for_user(post_id, user.id, [:topic]) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, ErrorMessage.post_not_found())
         |> redirect(to: ~p"/posts")}

      post ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(AiBrandAgent.PubSub, "posts:user:#{post.user_id}")
        end

        pref = Accounts.get_posting_preferences_for_user(user.id)
        next_slots = ScheduleResolver.suggested_slots(user.id, pref, 3)
        next_slot_preview = List.first(next_slots)

        socket =
          socket
          |> assign(:page_title, "Post Detail")
          |> assign(:post, post)
          |> assign(:editing, false)
          |> assign(:edit_content, post.content)
          |> assign(:scheduled_at, nil)
          |> assign(:posting_schedule_summary, format_agent_schedule_summary(pref))
          |> assign(:next_slot_preview, next_slot_preview)

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
        {:noreply, put_flash(socket, :error, ErrorMessage.post_action(reason))}
    end
  end

  def handle_event("approve", _params, socket) do
    case ContentService.approve_post(socket.assigns.post) do
      {:ok, updated} ->
        {:noreply, put_post(socket, updated) |> put_flash(:info, "Post approved!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, ErrorMessage.post_action(reason))}
    end
  end

  def handle_event("smart_schedule", _params, socket) do
    user = socket.assigns.current_user
    post = socket.assigns.post

    if post.status != "approved" do
      {:noreply,
       put_flash(socket, :error, ErrorMessage.post_action({:invalid_status, post.status}))}
    else
      case ScheduleResolver.schedule_approved_post(post.id, user.id) do
        {:ok, %{scheduled_at: scheduled_at}} ->
          busy? = CalendarAgent.busy?(user.id, scheduled_at)

          info =
            if busy? do
              "Scheduled from your Agent settings. Note: your calendar shows another event overlapping this time."
            else
              "Post scheduled for #{Calendar.strftime(scheduled_at, "%b %d at %H:%M UTC")} (from Agent schedule)."
            end

          {:noreply,
           socket
           |> assign(:scheduled_at, scheduled_at)
           |> put_flash(:info, info)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, ErrorMessage.post_action(reason))}
      end
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
        {:noreply, put_flash(socket, :error, ErrorMessage.post_action(reason))}
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
      {:noreply,
       socket
       |> put_post(post)
       |> assign(:scheduled_at, scheduled_at)}
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

        <%!-- Content display/edit --%>
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

        <%!-- Actions --%>
        <div class="flex flex-col gap-4 mt-4 border-t border-base-300 pt-4">
          <div :if={@post.status == "approved"} class="rounded-lg border border-base-300 bg-base-100/50 p-4 space-y-2">
            <p class="text-sm font-medium">Smart Schedule</p>
            <p class="text-xs text-base-content/70">
              Uses your <.link navigate={~p"/agent"} class="link link-primary">Agent settings</.link>:
              {@posting_schedule_summary}.
            </p>
            <p :if={@next_slot_preview} class="text-xs text-base-content/60">
              Next matching slot (preview): {Calendar.strftime(@next_slot_preview, "%b %d, %Y at %H:%M UTC")}
            </p>
            <p :if={!@next_slot_preview} class="text-xs text-warning">
              No upcoming slot computed from your settings. Check timezone and posting days in Agent settings.
            </p>
            <button type="button" phx-click="smart_schedule" class="btn btn-sm btn-primary gap-2">
              <.icon name="hero-clock" class="w-4 h-4" /> Smart Schedule
            </button>
          </div>

          <div class="flex flex-wrap gap-2">
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
              :if={@post.status in ["draft", "approved", "scheduled"]}
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
    </div>
    """
  end

  defp put_post(socket, %Post{} = post) do
    uid = socket.assigns.current_user.id

    case ContentService.get_post_for_user(post.id, uid, [:topic]) do
      nil -> assign(socket, :post, post)
      loaded -> assign(socket, :post, loaded)
    end
  end

  defp do_immediate_publish(socket) do
    post = socket.assigns.post

    with {:ok, post} <- ensure_publishable_post(post),
         socket <- put_post(socket, post),
         {:ok, _} <- PublishingService.get_publishable_post(post.id),
         {:ok, _} <- %{post_id: post.id} |> PublishWorker.new() |> Oban.insert() do
      {:noreply, put_flash(socket, :info, "Publishing queued!")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, ErrorMessage.post_not_found())}

      {:error, {:not_publishable, status}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           PublishingService.user_facing_error({:not_publishable, status})
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, ErrorMessage.post_action(reason))}
    end
  end

  defp ensure_publishable_post(%Post{status: "draft"} = post) do
    ContentService.approve_post(post)
  end

  defp ensure_publishable_post(%Post{status: status} = post)
       when status in ["approved", "scheduled"] do
    {:ok, post}
  end

  defp ensure_publishable_post(%Post{status: status}) do
    {:error, {:invalid_status, status}}
  end

  @weekday_labels %{
    1 => "Mon",
    2 => "Tue",
    3 => "Wed",
    4 => "Thu",
    5 => "Fri",
    6 => "Sat",
    7 => "Sun"
  }

  defp format_agent_schedule_summary(pref) do
    days =
      pref.posting_weekdays
      |> Enum.sort()
      |> Enum.map(fn d -> Map.get(@weekday_labels, d, "?") end)
      |> Enum.join(", ")

    "#{days} at #{pref.default_post_time} — #{pref.timezone}"
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
