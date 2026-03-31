defmodule AiBrandAgentWeb.ConnectedAccountsController do
  @moduledoc """
  Auth0 [Connected Accounts for Token Vault](https://auth0.com/docs/secure/call-apis-on-users-behalf/token-vault/connected-accounts-for-token-vault):

  start → Auth0 My Account `connect` → user completes consent → callback `complete`.
  """

  use AiBrandAgentWeb, :controller

  require Logger

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Auth.Auth0Client
  alias AiBrandAgent.Auth.RefreshTokenCrypto
  alias AiBrandAgent.Logging

  @session_auth_session :connected_accounts_auth_session
  @session_state :connected_accounts_oauth_state
  @session_redirect :connected_accounts_redirect_uri

  @doc """
  Begins Connected Accounts: exchanges Auth0 RT for My Account API token, calls connect, redirects browser to Auth0.
  """
  def start(conn, _params) do
    user = conn.assigns.current_user
    user = Accounts.get_user(user.id)

    rt_plain = refresh_token_plain(user)

    with %{} = user,
         true <- rt_plain != "",
         {:ok, my_at} <- Auth0Client.exchange_refresh_token_for_my_account_api(rt_plain) do
      # Use request host/port so redirect_uri matches the browser (and Auth0 Allowed Callback URLs).
      redirect_uri = url(conn, ~p"/auth/connected-accounts/callback")
      state = random_state()

      case Auth0Client.connected_accounts_connect(my_at,
             redirect_uri: redirect_uri,
             state: state
           ) do
        {:ok, resp} ->
          case Auth0Client.connected_accounts_connect_url(resp) do
            {:ok, browser_url} ->
              auth_session = Map.fetch!(resp, "auth_session")

              conn
              |> put_session(@session_auth_session, auth_session)
              |> put_session(@session_state, state)
              |> put_session(@session_redirect, redirect_uri)
              |> redirect(external: browser_url)

            {:error, :missing_connect_uri} ->
              conn
              |> put_flash(:error, "Auth0 did not return connect_uri. Check Auth0 logs.")
              |> redirect(to: ~p"/dashboard")
          end

        {:error, {:auth0_error, status, body}} ->
          Logger.warning(
            "ConnectedAccounts.start: my_account token exchange failed status=#{status} body=#{Logging.safe_http_body(body)}"
          )

          conn
          |> put_flash(
            :error,
            user_facing_my_account_error(status, body)
          )
          |> redirect(to: ~p"/dashboard")

        {:error, {:my_account_error, status, body}} ->
          Logger.warning(
            "ConnectedAccounts.start: connect failed status=#{status} body=#{Logging.safe_http_body(body)}"
          )

          conn
          |> put_flash(
            :error,
            my_account_connect_error_flash(status, body, redirect_uri)
          )
          |> redirect(to: ~p"/dashboard")

        {:error, reason} ->
          Logger.error("ConnectedAccounts.start: #{inspect(reason)}")

          conn
          |> put_flash(
            :error,
            "Could not start Connected Accounts. Try again or check server logs."
          )
          |> redirect(to: ~p"/dashboard")
      end
    else
      nil ->
        conn
        |> put_flash(:error, "User not found.")
        |> redirect(to: ~p"/")

      _ ->
        conn
        |> put_flash(
          :error,
          "No Auth0 refresh token stored. Sign out and sign in again with Google, then retry."
        )
        |> redirect(to: ~p"/dashboard")
    end
  end

  @doc "Auth0 redirects here with connect_code after the user authorizes Google."
  def callback(conn, params) do
    case params["error"] do
      err when is_binary(err) ->
        desc = params["error_description"] || ""

        conn
        |> clear_connected_sessions()
        |> put_flash(:error, "Connected Accounts canceled: #{err} #{desc}")
        |> redirect(to: ~p"/dashboard")

      _ ->
        finish_callback(conn, params)
    end
  end

  defp finish_callback(conn, params) do
    connect_code = params["connect_code"] || params["code"]
    state = params["state"]

    stored_state = get_session(conn, @session_state)
    auth_session = get_session(conn, @session_auth_session)
    redirect_uri = get_session(conn, @session_redirect)

    cond do
      connect_code in [nil, ""] ->
        conn
        |> clear_connected_sessions()
        |> put_flash(:error, "Missing connect code from Auth0. Try again.")
        |> redirect(to: ~p"/dashboard")

      state != stored_state or stored_state == nil ->
        conn
        |> clear_connected_sessions()
        |> put_flash(:error, "Invalid OAuth state. Start the flow again from the dashboard.")
        |> redirect(to: ~p"/dashboard")

      redirect_uri in [nil, ""] or auth_session in [nil, ""] ->
        conn
        |> clear_connected_sessions()
        |> put_flash(
          :error,
          "Session expired. Start Connected Accounts from the dashboard again."
        )
        |> redirect(to: ~p"/dashboard")

      true ->
        user_id = conn.assigns.current_user.id

        case Accounts.get_user(user_id) do
          nil ->
            conn
            |> clear_connected_sessions()
            |> put_flash(:error, "User not found.")
            |> redirect(to: ~p"/")

          user ->
            case refresh_token_plain(user) do
              rt when is_binary(rt) and rt != "" ->
                case Auth0Client.exchange_refresh_token_for_my_account_api(rt) do
                  {:ok, my_at} ->
                    case Auth0Client.connected_accounts_complete(my_at, %{
                           auth_session: auth_session,
                           connect_code: connect_code,
                           redirect_uri: redirect_uri
                         }) do
                      {:ok, _} ->
                        conn
                        |> clear_connected_sessions()
                        |> put_flash(
                          :info,
                          "Google Connected Accounts saved. Token Vault should work after a moment — refresh the dashboard."
                        )
                        |> redirect(to: ~p"/dashboard")

                      {:error, {:my_account_error, status, body}} ->
                        Logger.warning(
                          "ConnectedAccounts.callback: complete failed status=#{status} body=#{Logging.safe_http_body(body)}"
                        )

                        conn
                        |> clear_connected_sessions()
                        |> put_flash(:error, "Complete failed (#{status}). Check Auth0 logs.")
                        |> redirect(to: ~p"/dashboard")

                      {:error, reason} ->
                        Logger.error("ConnectedAccounts.callback: #{inspect(reason)}")

                        conn
                        |> clear_connected_sessions()
                        |> put_flash(:error, "Complete failed. Check server logs.")
                        |> redirect(to: ~p"/dashboard")
                    end

                  {:error, {:auth0_error, status, body}} ->
                    Logger.warning(
                      "ConnectedAccounts.callback: my_account token exchange failed status=#{status} body=#{Logging.safe_http_body(body)}"
                    )

                    conn
                    |> clear_connected_sessions()
                    |> put_flash(:error, user_facing_my_account_error(status, body))
                    |> redirect(to: ~p"/dashboard")

                  {:error, reason} ->
                    Logger.error("ConnectedAccounts.callback: #{inspect(reason)}")

                    conn
                    |> clear_connected_sessions()
                    |> put_flash(:error, "Token exchange failed. Check server logs.")
                    |> redirect(to: ~p"/dashboard")
                end

              _ ->
                conn
                |> clear_connected_sessions()
                |> put_flash(
                  :error,
                  "No Auth0 refresh token. Sign out and sign in with Google, then try again."
                )
                |> redirect(to: ~p"/dashboard")
            end
        end
    end
  end

  defp refresh_token_plain(%{auth0_refresh_token: rt}) when is_binary(rt) and rt != "" do
    RefreshTokenCrypto.decrypt_from_storage(rt)
  end

  defp refresh_token_plain(_), do: ""

  defp clear_connected_sessions(conn) do
    conn
    |> delete_session(@session_auth_session)
    |> delete_session(@session_state)
    |> delete_session(@session_redirect)
  end

  defp random_state do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp user_facing_my_account_error(status, body) when is_map(body) do
    err = Map.get(body, "error") || Map.get(body, "error_description") || "unknown error"

    "My Account API token exchange failed (#{status}): #{err}. " <>
      "Enable MRRT + My Account API access (Connected Accounts scopes) for this application in Auth0."
  end

  defp user_facing_my_account_error(status, _),
    do: "My Account API token exchange failed (#{status})."

  defp my_account_connect_error_flash(status, body, redirect_uri)
       when is_map(body) and is_binary(redirect_uri) do
    detail = Map.get(body, "detail") || Map.get(body, "title")

    base =
      "Could not start Connected Accounts (#{status}). Enable My Account API and Connected Accounts scopes for your Auth0 app."

    cond do
      is_binary(detail) and detail != "" ->
        "#{base} Auth0 says: #{detail}. If this is redirect_uri, add this exact URL to Allowed Callback URLs: #{redirect_uri}"

      true ->
        base
    end
  end

  defp my_account_connect_error_flash(status, _, _),
    do:
      "Could not start Connected Accounts (#{status}). Enable My Account API and Connected Accounts scopes for your Auth0 app."
end
