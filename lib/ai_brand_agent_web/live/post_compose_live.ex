defmodule AiBrandAgentWeb.PostComposeLive do
  @moduledoc """
  Create a post with your own copy (no AI). Optional `topic_id` is omitted.
  """

  use AiBrandAgentWeb, :live_view

  alias AiBrandAgent.Services.ContentService

  on_mount {AiBrandAgentWeb.Plugs.Auth, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Compose post")
      |> assign(:form, to_form(default_params(), as: :post))

    {:ok, socket}
  end

  defp default_params do
    %{"platform" => "linkedin", "content" => ""}
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :post))}
  end

  def handle_event("save", %{"post" => params}, socket) do
    user = socket.assigns.current_user
    platform = String.trim(Map.get(params, "platform") || "")
    content = String.trim(Map.get(params, "content") || "")

    cond do
      platform not in ["linkedin", "facebook"] ->
        {:noreply, put_flash(socket, :error, "Choose LinkedIn or Facebook.")}

      content == "" ->
        {:noreply, put_flash(socket, :error, "Write something for the post body.")}

      true ->
        attrs = %{
          user_id: user.id,
          platform: platform,
          content: content,
          status: "draft",
          topic_id: nil
        }

        case ContentService.create_post(attrs) do
          {:ok, post} ->
            {:noreply,
             socket
             |> put_flash(:info, "Draft saved.")
             |> push_navigate(to: ~p"/posts/#{post.id}")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, put_flash(socket, :error, "Could not save: #{inspect(cs.errors)}")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-2xl mx-auto px-4 py-8">
        <h1 class="text-3xl font-bold mb-6">Compose post</h1>

        <.form for={@form} id="compose-post-form" phx-submit="save" phx-change="validate">
          <div class="card bg-base-200 p-6 space-y-4">
            <.input
              field={@form[:platform]}
              type="select"
              label="Platform"
              options={[{"LinkedIn", "linkedin"}, {"Facebook", "facebook"}]}
            />
            <.input
              field={@form[:content]}
              type="textarea"
              label="Post content"
              rows="8"
              placeholder="Write your post..."
              required
            />
            <div class="flex gap-2 pt-2">
              <button type="submit" class="btn btn-primary" id="compose-save-btn">
                Save draft
              </button>
              <.link navigate={~p"/posts"} class="btn btn-ghost">Cancel</.link>
            </div>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
