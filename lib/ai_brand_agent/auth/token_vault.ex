defmodule AiBrandAgent.Auth.TokenVault do
  @moduledoc """
  Interface to Auth0 for AI Agents Token Vault for secure third-party token retrieval.

  Uses two strategies depending on platform support:

  1. **Google** — Prefer OAuth 2.0 Token Exchange (Auth0 refresh token →
     Google access token via Token Vault). If Auth0 responds with
     `federated_connection_refresh_token_not_found` (no federated RT in Token
     Vault yet), fall back to the **Management API** identity access token,
     same as other providers.

  2. **LinkedIn / Facebook** — Auth0 Management API: provider access token
     from `GET /api/v2/users/{id}` identities.

  Tokens are not persisted locally — they are fetched on demand per call.
  """

  require Logger

  alias AiBrandAgent.Auth.Auth0Client
  alias AiBrandAgent.Auth.RefreshTokenCrypto
  alias AiBrandAgent.Logging

  # Token Vault exchange is used only for Google (e.g. Calendar). LinkedIn and Facebook
  # use the Management API identity access token until Token Vault is enabled for them.
  @token_vault_platforms ~w(google)
  @mgmt_api_platforms ~w(linkedin facebook)

  @doc """
  Returns `true` only if Auth0 **Token Vault** federated exchange succeeds for Google
  (`token_vault_exchange` returns 200). Does **not** use the Management API fallback.

  Use for UI health indicators. On failure (missing RT, federated RT not in Vault, etc.)
  returns `false`.
  """
  def google_federated_token_vault_ok?(user_id) when is_binary(user_id) do
    with {:ok, user} <- fetch_user(user_id),
         {:ok, connection} <- fetch_connection(user, "google"),
         {:ok, refresh_token} <- get_refresh_token(user) do
      case Auth0Client.token_vault_exchange(refresh_token, connection.auth0_connection_id) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    else
      _ -> false
    end
  end

  @doc """
  Retrieve a stored OAuth access token for a user + platform.

  For Google, tries Token Vault first, then Management API if the federated
  token is missing in Vault. For LinkedIn/Facebook, uses the Management API only.

  Returns `{:ok, access_token}` or `{:error, reason}`.
  """
  def get_access_token(user_id, platform) do
    Logger.debug(
      "TokenVault.get_access_token: start user_id=#{user_id} platform=#{inspect(platform)}"
    )

    result =
      with {:ok, user} <- fetch_user(user_id),
           {:ok, connection} <- fetch_connection(user, platform) do
        has_rt = has_refresh_token?(user)

        Logger.debug(
          "TokenVault.get_access_token: user=#{short_id(user.auth0_user_id)} " <>
            "social_connection auth0_connection_id=#{inspect(connection.auth0_connection_id)} " <>
            "has_auth0_refresh_token=#{has_rt}"
        )

        cond do
          platform in @token_vault_platforms ->
            Logger.debug(
              "TokenVault: route=google step=try_token_vault_then_maybe_mgmt platform=#{inspect(platform)}"
            )

            google_access_token(user, connection)

          platform in @mgmt_api_platforms ->
            Logger.debug(
              "TokenVault: route=management_api_only platform=#{inspect(platform)} step=management_api"
            )

            mgmt_api_exchange(user, connection)

          true ->
            {:error, {:unsupported_platform, platform}}
        end
      else
        {:error, :user_not_found} = err ->
          Logger.warning("TokenVault.get_access_token: user_not_found user_id=#{user_id}")
          err

        {:error, {:no_connection, p}} = err ->
          Logger.warning(
            "TokenVault.get_access_token: no social_connections row for platform=#{inspect(p)} user_id=#{user_id}"
          )

          err
      end

    case result do
      {:ok, _} ->
        Logger.debug(
          "TokenVault.get_access_token: ok user_id=#{user_id} platform=#{inspect(platform)}"
        )

      {:error, reason} ->
        Logger.debug(
          "TokenVault.get_access_token: error user_id=#{user_id} platform=#{inspect(platform)} reason=#{inspect(reason)}"
        )
    end

    result
  end

  # ── Google: Token Vault, then Management API if Vault has no federated RT ──

  defp google_access_token(user, connection) do
    conn_id = connection.auth0_connection_id

    case get_refresh_token(user) do
      {:ok, refresh_token} ->
        Logger.debug(
          "TokenVault: google step=1_token_vault_exchange connection=#{inspect(conn_id)} " <>
            "(Auth0 RT present, subject_token redacted)"
        )

        case Auth0Client.token_vault_exchange(refresh_token, conn_id) do
          {:ok, _} = ok ->
            Logger.debug(
              "TokenVault: google step=done token_source=token_vault " <>
                "connection=#{inspect(conn_id)} " <>
                "hint=look for Auth0Client.token_vault_exchange: ok ... token_source=auth0_token_vault"
            )

            ok

          {:error, {:token_vault_error, status, body}} ->
            if federated_token_missing_in_vault?(status, body) do
              Logger.warning(
                "TokenVault: Google Token Vault has no federated refresh token " <>
                  "(connection=#{inspect(conn_id)}). " <>
                  "Trying Management API identity token. " <>
                  "For durable Token Vault access, set the Google connection to " <>
                  "Connected Accounts (Token Vault) in Auth0 and sign in again."
              )

              Logger.debug(
                "TokenVault: google step=2_management_api_fallback connection=#{inspect(conn_id)}"
              )

              case mgmt_api_exchange(user, connection) do
                {:ok, _} = ok ->
                  Logger.debug(
                    "TokenVault: google step=done token_source=management_api_fallback " <>
                      "connection=#{inspect(conn_id)}"
                  )

                  ok

                {:error, _} = err ->
                  Logger.error(
                    "TokenVault: Google Token Vault and Management API both failed " <>
                      hint_token_vault_error(body)
                  )

                  err
              end
            else
              Logger.error(
                "TokenVault.token_vault_exchange: failed status=#{status} " <>
                  "connection=#{inspect(conn_id)} body=#{Logging.safe_http_body(body)} " <>
                  hint_token_vault_error(body)
              )

              {:error, {:token_vault_error, status, body}}
            end

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  defp federated_token_missing_in_vault?(401, %{
         "error" => "federated_connection_refresh_token_not_found"
       }),
       do: true

  defp federated_token_missing_in_vault?(_, _), do: false

  defp hint_token_vault_error(body) when is_map(body) do
    code = Map.get(body, "error") || Map.get(body, "error_code")

    case code do
      "federated_connection_refresh_token_not_found" ->
        " hint=Auth0 has no federated refresh token in Token Vault for this user/connection; " <>
          "re-login after enabling Connected Accounts + Token Vault, or check Google connection purpose."

      _ ->
        ""
    end
  end

  defp hint_token_vault_error(_), do: ""

  defp short_id(nil), do: "nil"

  defp short_id(s) when is_binary(s) do
    if String.length(s) > 24, do: String.slice(s, 0, 24) <> "…", else: s
  end

  defp has_refresh_token?(%{auth0_refresh_token: rt}) when is_binary(rt) and rt != "", do: true
  defp has_refresh_token?(_), do: false

  # ── Management API (Identity Tokens) ──────────────────────────────

  defp mgmt_api_exchange(user, connection) do
    Auth0Client.get_identity_token(user.auth0_user_id, connection.auth0_connection_id)
  end

  # ── Shared helpers ────────────────────────────────────────────────

  defp fetch_user(user_id) do
    case AiBrandAgent.Repo.get(AiBrandAgent.Accounts.User, user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp get_refresh_token(%{auth0_refresh_token: rt}) when is_binary(rt) and rt != "" do
    {:ok, RefreshTokenCrypto.decrypt_from_storage(rt)}
  end

  defp get_refresh_token(_user) do
    Logger.error("Token Vault: user has no Auth0 refresh token — they need to re-login")
    {:error, :no_refresh_token}
  end

  defp fetch_connection(user, platform) do
    import Ecto.Query

    query =
      from sc in AiBrandAgent.Accounts.SocialConnection,
        where: sc.user_id == ^user.id and sc.platform == ^platform,
        limit: 1

    case AiBrandAgent.Repo.one(query) do
      nil -> {:error, {:no_connection, platform}}
      conn -> {:ok, conn}
    end
  end
end
