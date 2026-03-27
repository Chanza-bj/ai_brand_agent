defmodule AiBrandAgent.Auth.Auth0Client do
  @moduledoc """
  HTTP client for Auth0.

  Authenticates all token requests using Private Key JWT (client_assertion)
  so the application works with `token_endpoint_auth_method: null`, which
  is required for Token Vault's privileged worker flow.
  """

  require Logger

  @token_path "/oauth/token"
  @userinfo_path "/userinfo"

  # ── Public API ──────────────────────────────────────────────────────

  @doc "Exchange an authorization code for tokens."
  def exchange_code(code, redirect_uri) do
    body =
      %{
        grant_type: "authorization_code",
        client_id: config(:client_id),
        code: code,
        redirect_uri: redirect_uri
      }
      |> put_client_auth()

    case post(@token_path, body) do
      {:ok, %{status: 200, body: tokens}} ->
        {:ok, tokens}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "Auth0Client.exchange_code: token endpoint status=#{status} body=#{inspect(body)} " <>
            "(check Auth0 Application: client auth method, client secret, or Token Vault signing key matches uploaded JWKS)"
        )

        {:error, {:auth0_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Fetch the user profile using an access token."
  def get_userinfo(access_token) do
    case Req.get(base_url() <> @userinfo_path,
           headers: [{"authorization", "Bearer #{access_token}"}]
         ) do
      {:ok, %{status: 200, body: profile}} ->
        {:ok, profile}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Auth0Client.get_userinfo: status=#{status} body=#{inspect(body)}")

        {:error, {:auth0_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Token Vault token exchange (Refresh Token flow).

  Exchanges an Auth0 refresh token for an external provider's access token
  stored in Token Vault.

  `refresh_token` is the user's Auth0 refresh token.
  `connection` is the Auth0 connection name (e.g. "google-oauth2", "facebook-custom").
  Returns `{:ok, access_token}` or `{:error, reason}`.
  """
  def token_vault_exchange(refresh_token, connection) do
    Logger.debug(
      "Auth0Client.token_vault_exchange: connection=#{inspect(connection)} (refresh_token redacted)"
    )

    body =
      %{
        grant_type:
          "urn:auth0:params:oauth:grant-type:token-exchange:federated-connection-access-token",
        client_id: config(:client_id),
        subject_token: refresh_token,
        subject_token_type: "urn:ietf:params:oauth:token-type:refresh_token",
        requested_token_type: "http://auth0.com/oauth/token-type/token-vault-access-token",
        connection: connection
      }
      |> put_client_auth()

    case post(@token_path, body) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        Logger.debug(
          "Auth0Client.token_vault_exchange: ok status=200 connection=#{inspect(connection)} " <>
            "token_source=auth0_token_vault (federated exchange)"
        )

        {:ok, token}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        # Details + hints are logged by AiBrandAgent.Auth.TokenVault
        Logger.debug(
          "Auth0Client.token_vault_exchange: error status=#{status} body=#{inspect(body)}"
        )

        {:error, {:token_vault_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Exchange the user's Auth0 refresh token for a **My Account API** access token.

  Required for [Connected Accounts](https://auth0.com/docs/secure/call-apis-on-users-behalf/token-vault/connected-accounts-for-token-vault)
  (`audience` = `https://<tenant>/me/`). Enable MRRT + My Account API access for your app in Auth0.
  """
  def exchange_refresh_token_for_my_account_api(refresh_token) when is_binary(refresh_token) do
    scope = my_account_scope()

    body =
      %{
        grant_type: "refresh_token",
        client_id: config(:client_id),
        refresh_token: refresh_token,
        audience: my_account_audience(),
        scope: scope
      }
      |> put_client_auth()

    case post(@token_path, body) do
      {:ok, %{status: 200, body: %{"access_token" => at}}} ->
        {:ok, at}

      {:ok, %{status: status, body: body}} ->
        Logger.debug(
          "Auth0Client.exchange_refresh_token_for_my_account_api: error status=#{status} body=#{inspect(body)}"
        )

        {:error, {:auth0_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Start Connected Accounts for Google (`POST /me/v1/connected-accounts/connect`).

  `opts`: `:redirect_uri`, `:state` (required), optional `:connection` (default `google-oauth2`),
  `:scopes` (list of Google / OIDC scope strings).
  """
  def connected_accounts_connect(access_token, opts) when is_list(opts) do
    redirect_uri = Keyword.fetch!(opts, :redirect_uri)
    state = Keyword.fetch!(opts, :state)
    connection = Keyword.get(opts, :connection, "google-oauth2")
    scopes = Keyword.get(opts, :scopes, default_connected_accounts_google_scopes())

    body = %{
      "connection" => connection,
      "redirect_uri" => redirect_uri,
      "state" => state,
      "scopes" => scopes
    }

    case post_me("/me/v1/connected-accounts/connect", body, access_token) do
      {:ok, %{status: status, body: %{} = resp}} when status in 200..299 ->
        {:ok, resp}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "Auth0Client.connected_accounts_connect: status=#{status} body=#{inspect(body)}"
        )

        {:error, {:my_account_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Complete Connected Accounts (`POST /me/v1/connected-accounts/complete`).
  """
  def connected_accounts_complete(access_token, attrs) when is_map(attrs) do
    body = %{
      "auth_session" => Map.fetch!(attrs, :auth_session),
      "connect_code" => Map.fetch!(attrs, :connect_code),
      "redirect_uri" => Map.fetch!(attrs, :redirect_uri)
    }

    case post_me("/me/v1/connected-accounts/complete", body, access_token) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        {:ok, resp}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "Auth0Client.connected_accounts_complete: status=#{status} body=#{inspect(body)}"
        )

        {:error, {:my_account_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Browser URL for the user to open (connect_uri + ticket when present)."
  def connected_accounts_connect_url(%{} = connect_response) do
    uri = Map.get(connect_response, "connect_uri") || Map.get(connect_response, :connect_uri)
    ticket = get_in(connect_response, ["connect_params", "ticket"])

    cond do
      not is_binary(uri) ->
        {:error, :missing_connect_uri}

      is_binary(ticket) ->
        u = URI.parse(uri)

        merged =
          (u.query || "")
          |> URI.decode_query()
          |> Map.put("ticket", ticket)
          |> URI.encode_query()

        {:ok, URI.to_string(%{u | query: merged})}

      true ->
        {:ok, uri}
    end
  end

  @doc false
  def my_account_audience do
    "https://#{config(:domain)}/me/"
  end

  defp my_account_scope do
    Application.get_env(:ai_brand_agent, :auth0_my_account_scope) ||
      "openid profile offline_access create:me:connected_accounts read:me:connected_accounts delete:me:connected_accounts"
  end

  defp default_connected_accounts_google_scopes do
    Application.get_env(:ai_brand_agent, :google_connected_accounts_scopes) ||
      [
        "openid",
        "profile",
        "email",
        "https://www.googleapis.com/auth/calendar.events"
      ]
  end

  defp post_me(path, body, access_token) do
    Req.post(base_url() <> path,
      json: body,
      headers: [
        {"authorization", "Bearer #{access_token}"},
        {"content-type", "application/json"}
      ]
    )
  end

  @doc """
  Fetch a linked identity's access token via the Management API.

  Used for providers not supported by Token Vault (LinkedIn, Facebook).
  Requires the `read:user_idp_tokens` scope on the M2M token.
  """
  def get_identity_token(auth0_user_id, connection) do
    Logger.debug(
      "Auth0Client.get_identity_token: auth0_user_id=#{inspect(auth0_user_id)} " <>
        "stored_connection=#{inspect(connection)}"
    )

    with {:ok, identities} <- fetch_user_identities(auth0_user_id) do
      Logger.debug(
        "Auth0Client.get_identity_token: fetched user identities count=#{length(identities)} " <>
          "labels=#{inspect(Enum.map(identities, &identity_label/1))}"
      )

      identity = find_identity_for_connection(identities, connection)

      case identity do
        %{"access_token" => token} when is_binary(token) and token != "" ->
          Logger.debug(
            "Auth0Client.get_identity_token: matched connection=#{inspect(connection)} " <>
              "(access_token redacted)"
          )

          {:ok, token}

        %{} = found ->
          Logger.error(
            "Management API: identity for #{inspect(connection)} has no usable access_token " <>
              "(keys: #{inspect(Map.keys(found))}). " <>
              "Ensure the M2M app has read:user_idp_tokens and the user re-authenticated after granting scopes."
          )

          {:error, {:no_identity_token, connection}}

        nil ->
          Logger.error(
            "Management API: no identity matched stored connection #{inspect(connection)}. " <>
              "Available identities: #{inspect(Enum.map(identities, &identity_label/1))}"
          )

          {:error, {:no_identity_token, connection}}
      end
    end
  end

  @doc """
  Returns whether the Auth0 user (Management API `GET /api/v2/users/{id}`) has an identity
  row matching `stored_connection` (same matching as token fetch).

  Used after social connect OAuth to ensure the provider is actually linked to the profile
  for `auth0_user_id` (not only present in the OAuth callback payload).

  Returns `{:ok, true}` / `{:ok, false, labels}` or `{:error, reason}` if the API call fails.
  """
  def identity_linked_via_management_api?(auth0_user_id, stored_connection) do
    case fetch_user_identities(auth0_user_id) do
      {:ok, identities} ->
        present = find_identity_for_connection(identities, stored_connection) != nil
        {:ok, present, Enum.map(identities, &identity_label/1)}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Links a secondary Auth0 user (e.g. `linkedin|…`) to the primary user profile using
  `POST /api/v2/users/{primary_id}/identities` with `provider` + `user_id` (see
  [Link User Accounts](https://auth0.com/docs/manage-users/user-accounts/user-account-linking/link-user-accounts)).

  Requires Management API scope **`update:users`** on the M2M application.

  Returns `{:ok, :linked}` or `{:ok, :noop}` when primary and secondary are already the same `sub`.
  """
  def link_secondary_identity(primary_auth0_user_id, secondary_auth0_user_id) do
    cond do
      not is_binary(primary_auth0_user_id) or not is_binary(secondary_auth0_user_id) ->
        {:error, :invalid_user_id}

      primary_auth0_user_id == secondary_auth0_user_id ->
        {:ok, :noop}

      true ->
        with {:ok, provider, user_id} <- split_auth0_user_id(secondary_auth0_user_id),
             {:ok, mgmt_token} <- get_management_token() do
          path_id = URI.encode(primary_auth0_user_id, &URI.char_unreserved?/1)

          body = %{
            "provider" => provider,
            "user_id" => user_id
          }

          case Req.post("#{base_url()}/api/v2/users/#{path_id}/identities",
                 json: body,
                 headers: [{"authorization", "Bearer #{mgmt_token}"}]
               ) do
            {:ok, %{status: status}} when status in 200..299 ->
              Logger.info(
                "Auth0Client.link_secondary_identity: ok primary=#{inspect(primary_auth0_user_id)} " <>
                  "secondary=#{inspect(secondary_auth0_user_id)} status=#{status}"
              )

              {:ok, :linked}

            {:ok, %{status: status, body: body}} ->
              Logger.error(
                "Auth0Client.link_secondary_identity: failed status=#{status} body=#{inspect(body)}"
              )

              {:error, {:mgmt_api_error, status, body}}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, _} = err -> err
        end
    end
  end

  defp split_auth0_user_id(str) when is_binary(str) do
    case String.split(str, "|", parts: 2) do
      [provider, user_id] when provider != "" and user_id != "" ->
        {:ok, provider, user_id}

      _ ->
        {:error, :invalid_auth0_user_id_format}
    end
  end

  defp fetch_user_identities(auth0_user_id) do
    with {:ok, mgmt_token} <- get_management_token() do
      path_id = URI.encode(auth0_user_id, &URI.char_unreserved?/1)

      case Req.get("#{base_url()}/api/v2/users/#{path_id}",
             headers: [{"authorization", "Bearer #{mgmt_token}"}]
           ) do
        {:ok, %{status: 200, body: %{"identities" => identities}}} ->
          {:ok, identities}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Management API get user failed #{status}: #{inspect(body)}")
          {:error, {:mgmt_api_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp identity_label(id) do
    {Map.get(id, "connection"), Map.get(id, "provider")}
  end

  @doc false
  def find_identity_for_connection(identities, stored_connection) when is_list(identities) do
    Enum.find(identities, &identity_matches_stored_connection?(&1, stored_connection))
  end

  defp identity_matches_stored_connection?(identity, stored) when is_binary(stored) do
    c = identity_str(Map.get(identity, "connection"))
    p = identity_str(Map.get(identity, "provider"))

    cond do
      c == stored or p == stored -> true
      linkedin_kind?(stored) -> linkedin_identity?(c, p)
      facebook_kind?(stored) -> facebook_identity?(c, p)
      google_kind?(stored) -> google_identity?(c, p)
      true -> false
    end
  end

  defp linkedin_kind?(s), do: String.contains?(String.downcase(s), "linkedin")
  defp facebook_kind?(s), do: String.contains?(String.downcase(s), "facebook")
  defp google_kind?(s), do: String.contains?(String.downcase(s), "google")

  defp identity_str(v) when is_binary(v), do: v
  defp identity_str(_), do: ""

  defp linkedin_identity?(c, p) do
    c in ["linkedin", "linkedin-oauth2"] or p in ["linkedin", "linkedin-oauth2"] or
      String.contains?(c, "linkedin") or String.contains?(p, "linkedin")
  end

  defp facebook_identity?(c, p) do
    c == "facebook" or p == "facebook" or String.contains?(c, "facebook") or
      String.contains?(p, "facebook")
  end

  defp google_identity?(c, p) do
    c in ["google-oauth2", "google"] or p in ["google-oauth2", "google"] or
      String.contains?(c, "google") or String.contains?(p, "google")
  end

  @doc """
  Obtain an M2M access token for the Management API.

  Used internally by `TokenVault` and other server-side calls.
  """
  def get_management_token do
    body =
      %{
        grant_type: "client_credentials",
        client_id: config(:client_id),
        audience: config(:audience)
      }
      |> put_client_auth()

    case post(@token_path, body) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, {:auth0_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Build the Auth0 `/authorize` URL.

  ## Options

  - `:connection` — Auth0 connection name (e.g. `"facebook"`, `"linkedin"`) for social login/connect.
  - `:connection_scope` — Extra OAuth2 scopes for the identity provider (Auth0 sends this as
    `connection_scope`). **Facebook / Meta** expects **comma-separated** permissions (e.g.
    `pages_show_list,pages_manage_posts`). Other providers may use space-separated scopes.
  - `:prompt` — OIDC `prompt` param (e.g. `"consent"` to force the consent screen so new scopes
    like Page permissions are shown).
  """
  def authorize_url(redirect_uri, state, opts \\ []) do
    connection = Keyword.get(opts, :connection)
    connection_scope = Keyword.get(opts, :connection_scope)
    prompt = Keyword.get(opts, :prompt)

    params =
      %{
        response_type: "code",
        client_id: config(:client_id),
        redirect_uri: redirect_uri,
        scope: "openid profile email offline_access",
        state: state
      }
      |> maybe_put(:connection, connection)
      |> maybe_put(:connection_scope, connection_scope)
      |> maybe_put(:prompt, prompt)

    "#{base_url()}/authorize?" <> URI.encode_query(params)
  end

  @doc "Build the Auth0 logout URL."
  def logout_url(return_to) do
    params = %{
      client_id: config(:client_id),
      returnTo: return_to
    }

    "#{base_url()}/v2/logout?" <> URI.encode_query(params)
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp put_client_auth(body) do
    case build_client_assertion() do
      {:ok, assertion} ->
        body
        |> Map.put(:client_assertion, assertion)
        |> Map.put(
          :client_assertion_type,
          "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        )

      {:error, _} ->
        Map.put(body, :client_secret, config(:client_secret))
    end
  end

  defp build_client_assertion do
    with {:ok, pem} <- token_vault_pem() do
      jwk = JOSE.JWK.from_pem(pem)
      now = System.system_time(:second)

      claims =
        Jason.encode!(%{
          "iss" => config(:client_id),
          "sub" => config(:client_id),
          "aud" => "#{base_url()}/",
          "iat" => now,
          "exp" => now + 120,
          "jti" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
        })

      signed =
        JOSE.JWS.sign(jwk, claims, %{"alg" => "RS256"})
        |> JOSE.JWS.compact()
        |> elem(1)

      {:ok, signed}
    end
  end

  defp token_vault_pem do
    case Application.fetch_env(:ai_brand_agent, :token_vault) do
      {:ok, config} ->
        case Keyword.get(config, :private_key) do
          pem when is_binary(pem) ->
            {:ok, pem}

          nil ->
            path = Keyword.get(config, :private_key_path)

            if path,
              do: File.read(path |> String.trim() |> String.trim("\"")),
              else: {:error, :no_key}
        end

      :error ->
        {:error, :not_configured}
    end
  end

  defp post(path, body) do
    Req.post(base_url() <> path,
      json: body,
      headers: [{"content-type", "application/json"}]
    )
  end

  defp base_url, do: "https://#{config(:domain)}"

  defp config(key) do
    Application.fetch_env!(:ai_brand_agent, :auth0) |> Keyword.fetch!(key)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
