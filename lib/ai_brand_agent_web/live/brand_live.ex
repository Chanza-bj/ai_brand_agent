defmodule AiBrandAgentWeb.BrandLive do
  @moduledoc """
  Optional product or service copy used when AI drafts posts from topic ideas —
  the model weaves the offer in authentically (see `PromptBuilder` / `ContentAgent`).
  """

  use AiBrandAgentWeb, :live_view

  alias AiBrandAgent.Accounts

  on_mount {AiBrandAgentWeb.Plugs.Auth, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    profile = Accounts.get_brand_profile_for_user(user.id)

    socket =
      socket
      |> assign(:page_title, "Brand & offer")
      |> assign(:form, brand_form(profile))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"brand" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :brand))}
  end

  def handle_event("save", %{"brand" => params}, socket) do
    user = socket.assigns.current_user

    attrs = %{
      enabled: params["enabled"] == "true",
      product_or_service_name: trim_or_nil(params["product_or_service_name"]),
      pitch: trim_or_nil(params["pitch"]),
      call_to_action: trim_or_nil(params["call_to_action"]),
      link_url: trim_or_nil(params["link_url"])
    }

    case Accounts.upsert_brand_profile(user.id, attrs) do
      {:ok, _} ->
        profile = Accounts.get_brand_profile_for_user(user.id)

        {:noreply,
         socket
         |> assign(:form, brand_form(profile))
         |> put_flash(:info, "Brand profile saved.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         socket
         |> assign(:form, to_form(cs, as: :brand))
         |> put_flash(:error, format_errors(cs))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-2xl mx-auto px-4 py-8">
        <h1 class="text-3xl font-bold mb-2">Brand &amp; offer</h1>
        <p class="text-base-content/70 text-sm mb-6">
          When enabled, AI-generated drafts from your topic ideas will naturally mention your product or service
          (not generic spam). Turn off anytime to return to commentary-only posts.
        </p>

        <.form
          for={@form}
          id="brand-profile-form"
          phx-submit="save"
          phx-change="validate"
          class="card bg-base-200 p-4 space-y-4"
        >
          <.input
            field={@form[:enabled]}
            type="checkbox"
            label="Weave my offer into AI drafts from topics"
          />

          <.input
            field={@form[:product_or_service_name]}
            type="text"
            label="Product or service name"
            placeholder="e.g. Acme CRM for agencies"
          />

          <.input
            field={@form[:pitch]}
            type="textarea"
            label="Value proposition"
            placeholder="What problem you solve and for whom (2–4 sentences is enough)"
            rows="5"
          />

          <.input
            field={@form[:call_to_action]}
            type="text"
            label="Preferred call to action (optional)"
            placeholder="e.g. Book a 15‑min demo"
          />

          <.input
            field={@form[:link_url]}
            type="url"
            label="Link (optional)"
            placeholder="https://…"
          />

          <button type="submit" class="btn btn-primary" id="brand-profile-save">
            Save
          </button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp brand_form(nil) do
    to_form(
      %{
        "enabled" => "false",
        "product_or_service_name" => "",
        "pitch" => "",
        "call_to_action" => "",
        "link_url" => ""
      },
      as: :brand
    )
  end

  defp brand_form(profile) do
    to_form(
      %{
        "enabled" => if(profile.enabled, do: "true", else: "false"),
        "product_or_service_name" => profile.product_or_service_name || "",
        "pitch" => profile.pitch || "",
        "call_to_action" => profile.call_to_action || "",
        "link_url" => profile.link_url || ""
      },
      as: :brand
    )
  end

  defp trim_or_nil(nil), do: nil

  defp trim_or_nil(s) when is_binary(s) do
    s = String.trim(s)
    if s == "", do: nil, else: s
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
