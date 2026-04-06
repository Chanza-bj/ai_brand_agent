defmodule AiBrandAgent.Social.GoogleGmailClient do
  @moduledoc """
  Minimal Gmail API client for sending mail via `users.messages.send`.

  Requires OAuth scope `https://www.googleapis.com/auth/gmail.send` on the access token
  (same Google connection as Calendar / Token Vault).
  """

  require Logger

  alias AiBrandAgent.Logging

  @base_url "https://gmail.googleapis.com/gmail/v1"

  @doc """
  Returns `{:ok, email_address}` for the authenticated user (`users/me/profile`).
  """
  def get_profile_email(access_token) when is_binary(access_token) do
    case Req.get("#{@base_url}/users/me/profile", headers: auth_headers(access_token)) do
      {:ok, %{status: 200, body: %{"emailAddress" => email}}} when is_binary(email) ->
        {:ok, email}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "Google Gmail get_profile error status=#{status} body=#{Logging.safe_http_body(body)}"
        )

        {:error, {:gmail_profile_error, status}}

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
    with {:ok, from} <- get_profile_email(access_token) do
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
