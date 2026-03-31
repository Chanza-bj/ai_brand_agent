defmodule AiBrandAgentWeb.AuthController do
  @moduledoc """
  Handles Auth0 login/logout flows and OAuth callbacks.

  Supports two callback flows:
  1. **Login** — exchanges code for tokens, upserts user, sets session.
  2. **Social connection** — same token exchange, but also persists the
     social connection record so the platform is linked for publishing.
  """

  use AiBrandAgentWeb, :controller

  require Logger

  alias AiBrandAgent.Auth.Auth0Client
  alias AiBrandAgent.Auth.RefreshTokenCrypto
  alias AiBrandAgent.Auth.TokenVault
  alias AiBrandAgent.Accounts
  alias AiBrandAgentWeb.ErrorMessage

  @doc "Redirect to Auth0 login via Google."
  def login(conn, _params) do
    state = generate_state()
    redirect_uri = url(~p"/auth/auth0/callback")

    conn
    |> put_session(:auth0_state, state)
    |> redirect(
      external: Auth0Client.authorize_url(redirect_uri, state, connection: "google-oauth2")
    )
  end

  @doc """
  Handle Auth0 callback after login or social connection.

  When `:connecting_platform` is present in the session, the callback
  additionally upserts a `SocialConnection` record for the user.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    stored_state = get_session(conn, :auth0_state)

    if state != stored_state do
      conn
      |> put_flash(:error, "Invalid authentication state.")
      |> redirect(to: ~p"/")
    else
      redirect_uri = url(~p"/auth/auth0/callback")

      with {:ok, tokens} <- Auth0Client.exchange_code(code, redirect_uri),
           {:ok, profile} <- Auth0Client.get_userinfo(tokens["access_token"]),
           {:ok, user} <- resolve_oauth_user(conn, profile) do
        log_auth0_callback_debug(tokens, profile)

        connecting_platform = get_session(conn, :connecting_platform)
        user = store_refresh_token(user, tokens)

        conn =
          conn
          |> delete_session(:auth0_state)
          |> put_session(:user_id, user.id)

        conn =
          if connecting_platform == nil do
            token = Accounts.assign_new_session_token!(user)
            put_session(conn, :session_token, token)
          else
            conn
          end

        case connecting_platform do
          nil ->
            ensure_google_connection(user, profile)

            conn = put_flash(conn, :info, "Welcome, #{user.name}!")

            destination =
              if TokenVault.google_federated_token_vault_ok?(user.id) do
                ~p"/dashboard"
              else
                ~p"/auth/connected-accounts/start"
              end

            redirect(conn, to: destination)

          platform ->
            auth0_connection_id =
              get_session(conn, :connecting_auth0_connection_id) ||
                extract_connection_id(profile, platform) ||
                platform

            conn =
              conn
              |> delete_session(:connecting_platform)
              |> delete_session(:connecting_auth0_connection_id)
              |> delete_session(:connecting_user_id)

            handle_social_connection(conn, user, platform, profile, tokens, auth0_connection_id)
        end
      else
        {:error, :connecting_user_not_found} ->
          conn
          |> delete_session(:auth0_state)
          |> delete_session(:connecting_platform)
          |> delete_session(:connecting_auth0_connection_id)
          |> delete_session(:connecting_user_id)
          |> put_flash(:error, "Session expired. Please log in again, then connect the account.")
          |> redirect(to: ~p"/auth/auth0")

        {:error, {:auth0_error, 401, _}} ->
          conn
          |> delete_session(:auth0_state)
          |> delete_session(:connecting_platform)
          |> delete_session(:connecting_auth0_connection_id)
          |> delete_session(:connecting_user_id)
          |> put_flash(
            :error,
            "Auth0 could not issue tokens (401 Unauthorized). " <>
              "Verify the Application’s client secret, or Token Vault private key vs JWKS in Auth0. See server logs."
          )
          |> redirect(to: ~p"/")

        {:error, _reason} ->
          conn
          |> delete_session(:auth0_state)
          |> delete_session(:connecting_platform)
          |> delete_session(:connecting_auth0_connection_id)
          |> delete_session(:connecting_user_id)
          |> put_flash(:error, ErrorMessage.login_failed())
          |> redirect(to: ~p"/")
      end
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed.")
    |> redirect(to: ~p"/")
  end

  @doc "Log out and redirect to Auth0 logout."
  def logout(conn, _params) do
    return_to = url(~p"/")

    conn =
      case get_session(conn, :user_id) do
        nil ->
          conn

        user_id ->
          case Accounts.get_user(user_id) do
            nil ->
              conn

            user ->
              _ = Accounts.clear_session_token!(user)
              conn
          end
      end

    conn
    |> clear_session()
    |> redirect(external: Auth0Client.logout_url(return_to))
  end

  @doc """
  Redirect to Auth0 to connect a social account (LinkedIn or Facebook).

  Uses `auth0_connection_for/1` to map the app platform label to your Auth0 connection name.
  Provider access tokens for publishing are fetched via the Management API (not Token Vault)
  unless you later enable Token Vault for those providers.
  """
  def connect(conn, %{"platform" => platform}) when platform in ["linkedin", "facebook"] do
    state = generate_state()
    redirect_uri = url(~p"/auth/auth0/callback")
    auth0_connection = auth0_connection_for(platform)
    user = conn.assigns.current_user

    authorize_opts = connect_authorize_opts(platform, auth0_connection)

    conn
    |> put_session(:auth0_state, state)
    |> put_session(:connecting_platform, platform)
    |> put_session(:connecting_auth0_connection_id, auth0_connection)
    |> put_session(:connecting_user_id, user.id)
    |> redirect(external: Auth0Client.authorize_url(redirect_uri, state, authorize_opts))
  end

  def connect(conn, _params) do
    conn
    |> put_flash(:error, "Unsupported platform.")
    |> redirect(to: ~p"/connections")
  end

  defp connect_authorize_opts("facebook", auth0_connection) do
    scope =
      Application.get_env(:ai_brand_agent, :facebook_connection_scope) ||
        "pages_show_list,pages_manage_posts"

    scope = sanitize_facebook_connection_scope(scope)

    # Auth0 passes this to Meta as `connection_scope` so the user token can list Pages
    # (`GET /me/accounts`). Scopes on the Meta app alone are not enough without this OAuth ask.
    # `prompt=consent` helps force the Facebook consent UI so Page permissions are not skipped.
    [connection: auth0_connection, connection_scope: scope, prompt: "consent"]
  end

  defp connect_authorize_opts("linkedin", auth0_connection) do
    # Without `w_member_social`, LinkedIn returns 403 `ugcPosts.CREATE.NO_VERSION` — the token
    # can authenticate (OpenID) but cannot create posts. Auth0 forwards `connection_scope` to LinkedIn.
    scope =
      Application.get_env(:ai_brand_agent, :linkedin_connection_scope) ||
        "openid profile email w_member_social"

    [connection: auth0_connection, connection_scope: scope, prompt: "consent"]
  end

  defp connect_authorize_opts(_platform, auth0_connection) do
    [connection: auth0_connection]
  end

  # Meta rejects the legacy permission name `manage_pages` (use `pages_manage_posts`).
  # We strip it if present in env/config; if the error persists, remove `manage_pages` from
  # Auth0 Dashboard → Authentication → Social → Facebook → Permissions (Auth0 merges that list).
  defp sanitize_facebook_connection_scope(scope) when is_binary(scope) do
    parts =
      scope
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {kept, dropped} = Enum.split_with(parts, &(&1 != "manage_pages"))

    if dropped != [] do
      Logger.warning(
        "Auth0 connect Facebook: removed invalid Meta scope #{inspect(dropped)}. " <>
          "Use pages_manage_posts, not manage_pages. If Facebook still errors, delete manage_pages " <>
          "from Auth0 → Social → Facebook → Permissions (Auth0 merges that with connection_scope)."
      )
    end

    case Enum.join(kept, ",") do
      "" -> "pages_show_list,pages_manage_posts"
      joined -> joined
    end
  end

  defp sanitize_facebook_connection_scope(_), do: "pages_show_list,pages_manage_posts"

  # ── Private ─────────────────────────────────────────────────────────

  # Normal login: create/update user from Auth0 `sub`.
  #
  # Connect flow: keep the logged-in app user. The user already hit `/auth/connect/*` while
  # authenticated; completing OAuth is provider consent. Auth0 often returns a provider-specific
  # `sub` (e.g. `linkedin|…`, `facebook|…`) that does not equal `google-oauth2|…` — we still
  # attach the SocialConnection to the same `users` row (we do not call upsert from `sub`).
  defp resolve_oauth_user(conn, profile) do
    case get_session(conn, :connecting_platform) do
      nil ->
        Accounts.upsert_user_from_auth0(profile)

      _platform ->
        connecting_user_id = get_session(conn, :connecting_user_id) || get_session(conn, :user_id)

        case connecting_user_id && Accounts.get_user(connecting_user_id) do
          nil ->
            {:error, :connecting_user_not_found}

          user ->
            if get_session(conn, :user_id) == user.id do
              {:ok, user}
            else
              {:error, :connecting_user_not_found}
            end
        end
    end
  end

  defp handle_social_connection(conn, user, platform, profile, _tokens, auth0_connection_id) do
    profile_sub = Map.get(profile, "sub")

    with :ok <- maybe_link_secondary_identity(user.auth0_user_id, profile_sub, platform) do
      do_handle_social_connection(conn, user, platform, profile, auth0_connection_id)
    else
      {:error, message} when is_binary(message) ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/connections")
    end
  end

  defp do_handle_social_connection(conn, user, platform, profile, auth0_connection_id) do
    platform_user_id = extract_platform_user_id(profile, platform, auth0_connection_id)

    attrs = %{
      platform: platform,
      auth0_connection_id: auth0_connection_id,
      platform_user_id: platform_user_id
    }

    case Accounts.upsert_connection(user.id, attrs) do
      {:ok, connection} ->
        case Auth0Client.identity_linked_via_management_api?(
               user.auth0_user_id,
               connection.auth0_connection_id
             ) do
          {:ok, true, _} ->
            conn
            |> put_flash(:info, "#{platform_title(platform)} connected successfully!")
            |> redirect(to: ~p"/connections")

          {:ok, false, labels} ->
            _ = Accounts.delete_connection(connection.id)

            Logger.warning(
              "Auth0 connect: #{platform} not present on Auth0 user profile after OAuth. " <>
                "auth0_user_id=#{inspect(user.auth0_user_id)} management_api_identities=#{inspect(labels)}"
            )

            conn
            |> put_flash(:error, connect_not_linked_flash(platform, labels))
            |> redirect(to: ~p"/connections")

          {:error, reason} ->
            Logger.error(
              "Auth0 connect: could not verify identities via Management API: #{inspect(reason)}"
            )

            conn
            |> put_flash(
              :info,
              "#{platform_title(platform)} was saved, but we could not verify your Auth0 profile " <>
                "(Management API error). Ensure the M2M app has read:users and read:user_idp_tokens."
            )
            |> redirect(to: ~p"/connections")
        end

      {:error, changeset} ->
        Logger.error(
          "upsert_connection failed for platform=#{platform} user_id=#{user.id}: #{inspect(changeset.errors)}"
        )

        conn
        |> put_flash(:error, "Failed to save #{platform} connection.")
        |> redirect(to: ~p"/connections")
    end
  end

  defp maybe_link_secondary_identity(primary_auth0_user_id, profile_sub, platform) do
    cond do
      not is_binary(profile_sub) ->
        :ok

      primary_auth0_user_id == profile_sub ->
        :ok

      true ->
        case Auth0Client.link_secondary_identity(primary_auth0_user_id, profile_sub) do
          {:ok, _} ->
            :ok

          {:error, {:mgmt_api_error, status, body}} when status in [400, 409] ->
            Logger.warning(
              "Auth0 link identities: tolerating HTTP #{status} (may already be linked): #{inspect(body)}"
            )

            :ok

          {:error, {:mgmt_api_error, 403, _}} ->
            {:error,
             "The Management API denied linking (403). Add scope **update:users** to your M2M " <>
               "application for Auth0 Management API, then try Connect again."}

          {:error, {:mgmt_api_error, 401, _}} ->
            {:error,
             "Auth0 Management API rejected the token (401). Check M2M credentials and audience."}

          {:error, {:mgmt_api_error, 404, body}} ->
            maybe_tolerate_link_404(primary_auth0_user_id, platform, body)

          {:error, {:mgmt_api_error, status, body}} ->
            {:error,
             "Could not merge accounts in Auth0 (HTTP #{status}). #{format_mgmt_error_body(body)}"}

          {:error, :invalid_auth0_user_id_format} ->
            {:error, "Invalid Auth0 user id returned by the provider."}

          {:error, :invalid_user_id} ->
            {:error, "Invalid Auth0 user id for account linking."}

          {:error, reason} ->
            {:error, "Failed to link account: #{inspect(reason)}"}
        end
    end
  end

  # Linking can return 404 `inexistent_user` when Auth0 already merged the social identity
  # during the Connect callback (no standalone secondary user exists). If Management API
  # already shows this provider on the primary user, continue.
  defp maybe_tolerate_link_404(primary_auth0_user_id, platform, body) do
    case Auth0Client.identity_linked_via_management_api?(primary_auth0_user_id, platform) do
      {:ok, true, _} ->
        Logger.info(
          "Auth0 link identities: POST /identities returned 404 (#{inspect(Map.get(body, "errorCode"))}) " <>
            "but #{platform} is already on the primary user — continuing"
        )

        :ok

      {:ok, false, labels} ->
        {:error,
         "Auth0 could not link #{platform} (404: #{format_mgmt_error_body(body)}). " <>
           "Identities on your profile: #{inspect(labels)}. " <>
           "Try removing duplicate #{platform} rows in Auth0 (User → Raw JSON → identities), then Connect again."}

      {:error, reason} ->
        {:error,
         "Auth0 link failed (404) and we could not re-check identities: #{inspect(reason)}. " <>
           "Original: #{format_mgmt_error_body(body)}"}
    end
  end

  defp format_mgmt_error_body(body) when is_map(body) do
    Map.get(body, "message") || inspect(body)
  end

  defp format_mgmt_error_body(body) when is_binary(body) do
    String.slice(body, 0, 240)
  end

  defp format_mgmt_error_body(body), do: inspect(body)

  defp platform_title("linkedin"), do: "LinkedIn"
  defp platform_title("facebook"), do: "Facebook"
  defp platform_title(other), do: String.capitalize(other)

  defp connect_not_linked_flash(platform, labels) do
    name = platform_title(platform)

    """
    Auth0 does not show #{name} on your user profile yet (only: #{inspect(labels)}). \
    Publishing needs this provider under User Management → Users → your user → identities. \
    Fix: (1) Applications → your app → Connections → enable #{name}. \
    (2) Authentication → Social → #{name} → Applications → enable this app. \
    (3) Disconnect here, sign out, sign in with Google, then Connect #{name} again.
    """
    |> String.trim()
  end

  defp extract_connection_id(profile, platform) do
    identities = Map.get(profile, "identities", [])

    case Enum.find(identities, &identity_matches_platform?(&1, platform)) do
      %{"connection" => connection} when is_binary(connection) -> connection
      _ -> nil
    end
  end

  defp extract_platform_user_id(profile, platform, auth0_connection_id) do
    identities = Map.get(profile, "identities", [])

    matching =
      Enum.find(identities, fn identity ->
        identity_matches_platform?(identity, platform) ||
          Map.get(identity, "connection") == auth0_connection_id
      end)

    case matching do
      %{"user_id" => uid} -> uid
      _ -> Map.get(profile, "sub")
    end
  end

  # Auth0 uses `linkedin` / `linkedin-oauth2` (and similar) — not always the string "linkedin".
  defp identity_matches_platform?(identity, "linkedin") do
    p = to_string(Map.get(identity, "provider") || "")
    c = to_string(Map.get(identity, "connection") || "")

    p in ["linkedin", "linkedin-oauth2"] or c in ["linkedin", "linkedin-oauth2"] or
      String.contains?(p, "linkedin")
  end

  defp identity_matches_platform?(identity, "facebook") do
    p = to_string(Map.get(identity, "provider") || "")
    c = to_string(Map.get(identity, "connection") || "")
    p == "facebook" or c == "facebook" or String.contains?(p, "facebook")
  end

  defp identity_matches_platform?(_identity, _platform), do: false

  defp ensure_google_connection(user, profile) do
    google_user_id = extract_platform_user_id(profile, "google-oauth2", "google-oauth2")

    Accounts.upsert_connection(user.id, %{
      platform: "google",
      auth0_connection_id: "google-oauth2",
      platform_user_id: google_user_id
    })
  end

  defp store_refresh_token(user, %{"refresh_token" => rt}) when is_binary(rt) do
    stored = RefreshTokenCrypto.encrypt_for_storage(rt)

    case user
         |> AiBrandAgent.Accounts.User.changeset(%{auth0_refresh_token: stored})
         |> AiBrandAgent.Repo.update() do
      {:ok, updated} -> updated
      {:error, _} -> user
    end
  end

  defp store_refresh_token(user, _tokens), do: user

  defp auth0_connection_for("facebook") do
    Application.get_env(:ai_brand_agent, :facebook_auth0_connection, "facebook")
  end

  defp auth0_connection_for("linkedin"), do: "linkedin"

  defp log_auth0_callback_debug(tokens, profile) do
    if Application.get_env(:ai_brand_agent, :log_auth0_callback_debug, false) do
      keys = tokens |> Map.keys() |> Enum.sort()

      Logger.info(
        "Auth0 /oauth/token response: keys=#{inspect(keys)} " <>
          "(access_token, refresh_token, id_token values are not logged)"
      )

      safe =
        profile
        |> Map.take([
          "sub",
          "email",
          "email_verified",
          "name",
          "nickname",
          "picture",
          "updated_at"
        ])
        |> Map.update("picture", nil, fn
          url when is_binary(url) and byte_size(url) > 0 -> "[set]"
          other -> other
        end)

      Logger.info("Auth0 /userinfo response (subset): #{inspect(safe)}")
    end
  end

  defp generate_state do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
