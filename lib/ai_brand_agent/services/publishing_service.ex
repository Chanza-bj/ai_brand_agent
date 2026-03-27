defmodule AiBrandAgent.Services.PublishingService do
  @moduledoc """
  Business logic for the post publishing lifecycle.

  Handles state transitions: `approved → publishing → published | failed`.
  """

  alias AiBrandAgent.Repo
  alias AiBrandAgent.Accounts.Post

  @doc "Fetch a post that is eligible for publishing (approved or scheduled for publish)."
  def get_publishable_post(post_id) do
    case Repo.get(Post, post_id) do
      nil ->
        {:error, :not_found}

      %Post{status: status} = post when status in ["approved", "scheduled"] ->
        {:ok, post}

      %Post{status: status} ->
        {:error, {:not_publishable, status}}
    end
  end

  @doc "Transition post to `publishing` state."
  def mark_publishing(%Post{} = post) do
    post
    |> Post.status_changeset("publishing")
    |> Repo.update()
  end

  @doc "Record a successful publish."
  def record_success(%Post{} = post, %{id: platform_post_id}) do
    post
    |> Post.status_changeset("published", %{
      platform_post_id: platform_post_id,
      published_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  def record_success(%Post{} = post, _result) do
    post
    |> Post.status_changeset("published", %{
      published_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc "Record a failed publish attempt."
  def record_failure(post_or_id, reason)

  def record_failure(%Post{} = post, reason) do
    post
    |> Post.status_changeset("failed", %{error_message: format_reason(reason)})
    |> Repo.update()
  end

  def record_failure(post_id, reason) when is_binary(post_id) do
    case Repo.get(Post, post_id) do
      nil -> {:error, :not_found}
      post -> record_failure(post, reason)
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: user_facing_error(reason)

  @doc false
  def user_facing_error({:no_identity_token, platform}) when is_binary(platform) do
    label = platform_display_name(platform)

    "#{label} is not linked in Auth0 for this user (Management API shows no #{platform} identity). " <>
      "Open Connections, complete #{label} OAuth, confirm the user has that identity in Auth0, then Retry."
  end

  def user_facing_error(
        {:token_vault_error, 401, %{"error" => "federated_connection_refresh_token_not_found"}}
      ) do
    "Google Token Vault: no federated refresh token for this user. " <>
      "Enable Connected Accounts + your own Google keys in Auth0, then sign in again."
  end

  def user_facing_error({:token_vault_error, status, body}) when is_map(body) do
    desc = Map.get(body, "error_description") || Map.get(body, "error") || ""
    "Auth0 Token Vault error (#{status}): #{desc}"
  end

  def user_facing_error({:not_publishable, "failed"}) do
    "Post status is failed. Use Retry to reset to approved, then publish again."
  end

  def user_facing_error({:not_publishable, status}) do
    "Cannot publish while status is #{inspect(status)}. Approve the post first (or Retry after a failure)."
  end

  def user_facing_error({:mgmt_api_error, status, body}) when is_map(body) do
    "Auth0 Management API error (#{status}): #{Map.get(body, "message") || inspect(body)}"
  end

  def user_facing_error({:no_facebook_pages, message}) when is_binary(message), do: message

  def user_facing_error({:no_pages_found}) do
    "No Facebook Page available to post to. Connect Facebook with Page permissions, then try again."
  end

  def user_facing_error({:page_not_found, page_id}) do
    "Facebook Page id #{inspect(page_id)} is not in your connected Pages. Update Connections or pick a valid Page."
  end

  def user_facing_error({:facebook_error, status, body}) when is_binary(body) do
    "Facebook API error (#{status}): #{String.slice(body, 0, 500)}"
  end

  def user_facing_error({:facebook_error, status, body}) when is_map(body) do
    msg = get_in(body, ["error", "message"]) || inspect(body)
    "Facebook API error (#{status}): #{msg}"
  end

  def user_facing_error({:linkedin_error, 403, %{"message" => msg}}) when is_binary(msg) do
    hint =
      cond do
        String.contains?(msg, "ugcPosts.CREATE.NO_VERSION") ->
          " Add the Share on LinkedIn product in the LinkedIn Developer Portal, ensure Auth0’s LinkedIn connection includes w_member_social, then disconnect and reconnect LinkedIn in Connections so the stored token is reissued with posting permission."

        String.contains?(msg, "partnerApiPostsExternal") ->
          " The /rest/posts API needs marketing/partner access for many apps; this app uses /v2/ugcPosts for member posts. If this persists, confirm Share on LinkedIn and w_member_social, then reconnect LinkedIn."

        true ->
          ""
      end

    "LinkedIn API error (403): #{msg}.#{hint}"
  end

  def user_facing_error({:linkedin_error, status, body}) when is_map(body) do
    msg = Map.get(body, "message") || inspect(body)
    "LinkedIn API error (#{status}): #{msg}"
  end

  def user_facing_error(reason), do: inspect(reason)

  defp platform_display_name("linkedin"), do: "LinkedIn"
  defp platform_display_name("facebook"), do: "Facebook"
  defp platform_display_name("google"), do: "Google"
  defp platform_display_name(other) when is_binary(other), do: String.capitalize(other)
end
