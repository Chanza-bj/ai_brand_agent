defmodule AiBrandAgent.Social.GoogleGmailClient do
  @moduledoc """
  Minimal Gmail API client for sending mail via `users.messages.send`.

  Sender address resolution:

  1. **`users.getProfile`** (Gmail) — needs `gmail.metadata` (or broader Gmail read scopes).
  2. **Fallback:** **`GET https://www.googleapis.com/oauth2/v3/userinfo`** — works when the
     federated token includes **`openid` / `email` / `profile`** (typical for Connected Accounts),
     so mail still sends even if the token was issued **before** `gmail.metadata` was added.

  Sending requires **`https://www.googleapis.com/auth/gmail.send`** on the access token.
  """

  require Logger

  alias AiBrandAgent.Logging

  @base_url "https://gmail.googleapis.com/gmail/v1"
  @oauth2_userinfo_url "https://www.googleapis.com/oauth2/v3/userinfo"

  @doc """
  Returns `{:ok, email_address}` for the authenticated Google account.

  Tries Gmail `users/me/profile` first, then OAuth2 `userinfo` (same bearer token).
  """
  def get_sender_email(access_token) when is_binary(access_token) do
    case gmail_profile_email(access_token) do
      {:ok, email} ->
        {:ok, email}

      {:error, {:gmail_profile_error, status}} when status in [401, 403] ->
        Logger.debug(
          "GoogleGmailClient: Gmail profile #{status}, trying OAuth2 userinfo for sender email"
        )

        oauth2_user_email(access_token)

      {:error, _} = err ->
        err
    end
  end

  @doc false
  def get_profile_email(access_token) when is_binary(access_token) do
    get_sender_email(access_token)
  end

  defp gmail_profile_email(access_token) do
    case Req.get("#{@base_url}/users/me/profile", headers: auth_headers(access_token)) do
      {:ok, %{status: 200, body: %{"emailAddress" => email}}} when is_binary(email) ->
        {:ok, String.trim(email)}

      {:ok, %{status: status, body: body}} ->
        Logger.debug(
          "Google Gmail get_profile status=#{status} body=#{Logging.safe_http_body(body)}"
        )

        {:error, {:gmail_profile_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp oauth2_user_email(access_token) do
    case Req.get(@oauth2_userinfo_url, headers: auth_headers(access_token)) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        case body["email"] do
          email when is_binary(email) and email != "" ->
            {:ok, String.trim(email)}

          _ ->
            Logger.warning("GoogleGmailClient: OAuth2 userinfo returned no email field")
            {:error, :oauth2_userinfo_no_email}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "Google OAuth2 userinfo error status=#{status} body=#{Logging.safe_http_body(body)}"
        )

        {:error, {:oauth2_userinfo_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a plain-text email. Builds RFC 2822, base64url-encodes, POSTs to `messages/send`.
  """
  def send_plain_text(access_token, %{
        to: to,
        subject: subject,
        body: body
      })
      when is_binary(access_token) and is_binary(to) and is_binary(subject) and is_binary(body) do
    with {:ok, from} <- get_sender_email(access_token) do
      raw = build_rfc2822(from, to, subject, body)
      enc = Base.url_encode64(raw, padding: false)

      case Req.post("#{@base_url}/users/me/messages/send",
             headers: [{"content-type", "application/json"} | auth_headers(access_token)],
             json: %{raw: enc}
           ) do
        {:ok, %{status: 200, body: %{"id" => id}}} ->
          {:ok, id}

        {:ok, %{status: status, body: body}} ->
          Logger.error(
            "Google Gmail send error status=#{status} body=#{Logging.safe_http_body(body)}"
          )

          {:error, {:gmail_send_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_rfc2822(from, to, subject, body) do
    headers =
      [
        "From: #{from}",
        "To: #{to}",
        "Subject: #{subject}",
        "MIME-Version: 1.0",
        "Content-Type: text/plain; charset=UTF-8"
      ]
      |> Enum.join("\r\n")

    headers <> "\r\n\r\n" <> body
  end

  defp auth_headers(token), do: [{"authorization", "Bearer #{token}"}]
end
