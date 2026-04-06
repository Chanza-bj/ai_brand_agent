defmodule AiBrandAgent.Notifications.DraftReadyEmail do
  @moduledoc """
  Sends the **draft-ready** notification via Gmail API (no SMTP), using the user's Google token
  from Token Vault. The generation pipeline always calls this after a winning draft exists.
  """

  require Logger

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Accounts.{Post, User}
  alias AiBrandAgent.Auth.TokenVault
  alias AiBrandAgent.Repo
  alias AiBrandAgent.Services.ContentService
  alias AiBrandAgent.Social.GoogleGmailClient

  @doc """
  Sends email for the given post if it is still `draft` and notification was not sent yet.
  Failures are logged; returns `{:ok, :sent | :skipped | :already_sent}` or `{:error, term}`.
  """
  def send_for_post(%Post{id: id}) do
    case Repo.get(Post, id) do
      nil ->
        {:error, :not_found}

      %Post{draft_ready_email_sent_at: %DateTime{}} ->
        {:ok, :already_sent}

      %Post{status: "draft"} = post ->
        do_send(post)

      _ ->
        {:ok, :skipped}
    end
  end

  defp do_send(%Post{} = post) do
    user = Repo.get(User, post.user_id)

    cond do
      user == nil ->
        Logger.warning("DraftReadyEmail: no user for post #{post.id}")
        {:error, :no_user}

      blank?(user.email) ->
        Logger.warning("DraftReadyEmail: user #{user.id} has no email, skipping")
        {:ok, :skipped}

      true ->
        send_with_google(post, user)
    end
  end

  defp send_with_google(%Post{} = post, %User{} = user) do
    case TokenVault.get_access_token(post.user_id, "google") do
      {:ok, token} ->
        url = post_absolute_url(post.id)
        subject = "Athena: your draft is ready"
        body = draft_email_body(post, url)

        case GoogleGmailClient.send_plain_text(token, %{
               to: user.email,
               subject: subject,
               body: body
             }) do
          {:ok, _message_id} ->
            case ContentService.mark_draft_ready_email_sent(post) do
              {:ok, updated} ->
                _ =
                  Accounts.log_agent_decision(post.user_id, post.id, "draft_ready_email", %{
                    sent_at: DateTime.to_iso8601(updated.draft_ready_email_sent_at)
                  })

                {:ok, :sent}

              {:error, _} = err ->
                err
            end

          {:error, reason} = err ->
            Logger.warning(
              "DraftReadyEmail: Gmail send failed post=#{post.id} reason=#{inspect(reason)}"
            )

            err
        end

      {:error, reason} ->
        Logger.warning(
          "DraftReadyEmail: no Google token user=#{post.user_id} reason=#{inspect(reason)}"
        )

        {:error, {:no_google_token, reason}}
    end
  end

  defp post_absolute_url(post_id) do
    AiBrandAgentWeb.Endpoint.url() <> "/posts/#{post_id}"
  end

  defp draft_email_body(%Post{} = post, url) do
    """
    Your AI-generated draft is ready in Athena.

    Open the post to approve, choose Smart Schedule (pick a time), or publish now:
    #{url}

    Platform: #{post.platform}
    """
  end

  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: true
end
