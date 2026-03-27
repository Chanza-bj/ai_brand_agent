defmodule AiBrandAgent.Social.FacebookClient do
  @moduledoc """
  Client for the Facebook Graph API.

  Publishes posts to a Facebook Page feed using a user access token
  retrieved from Auth0 Token Vault.
  """

  require Logger

  @graph_url "https://graph.facebook.com/v19.0"

  @doc """
  Lists Facebook Pages the token can post to (`/me/accounts`).

  Returns `%{id, name}` only — no page access tokens (safe for UI).
  """
  def list_managed_pages(token) do
    with {:ok, pages} <- fetch_pages(token) do
      {:ok, Enum.map(pages, fn p -> %{id: p.id, name: p.name} end)}
    end
  end

  @doc """
  Create a post on Facebook.

  `token` is the OAuth 2.0 access token for the user (used to discover
  pages via `/me/accounts`).
  `content` is the post message text.
  `opts` may include:
    - `:page_id` — preferred Page ID to post to (defaults to the first available page)
    - `:link` — optional URL to attach

  Returns `{:ok, %{id: platform_post_id}}` or `{:error, reason}`.
  """
  def create_post(token, content, opts \\ []) do
    preferred_page_id = Keyword.get(opts, :page_id)
    link = Keyword.get(opts, :link)

    with {:ok, pages} <- fetch_pages(token),
         {:ok, page} <- pick_page(pages, preferred_page_id),
         {:ok, %{id: platform_post_id}} <- create_page_feed_post(page, content, link) do
      {:ok, %{id: platform_post_id}}
    else
      {:error, _reason} = err -> err
    end
  end

  @doc """
  Public URL to view a Page post on facebook.com.

  `composite_id` is the Graph API `id` for a feed publish result (`{page_id}_{post_id}`).
  """
  def public_post_url(composite_id) when is_binary(composite_id) do
    case String.split(composite_id, "_", parts: 2) do
      [page_id, post_id] when page_id != "" and post_id != "" ->
        "https://www.facebook.com/#{page_id}/posts/#{post_id}"

      _ ->
        nil
    end
  end

  def public_post_url(_), do: nil

  @doc "Fetch basic profile info for the token holder."
  def get_profile(token) do
    case Req.get("#{@graph_url}/me",
           params: [access_token: token, fields: "id,name"]
         ) do
      {:ok, %{status: 200, body: profile}} ->
        {:ok, profile}

      {:ok, %{status: status, body: body}} ->
        {:error, {:facebook_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp fetch_pages(token) do
    # Graph returns page-scoped tokens when requesting `access_token` for each page.
    # Empty `data` means the user has no Pages, or the token lacks `pages_show_list`.
    case Req.get("#{@graph_url}/me/accounts",
           params: [
             access_token: token,
             fields: "id,name,access_token"
           ]
         ) do
      {:ok, %{status: 200, body: body}} ->
        case decode_graph_json(body) do
          {:ok, %{"data" => data}} when is_list(data) ->
            pages =
              for %{"id" => id, "name" => name, "access_token" => page_token} <- data,
                  is_binary(id),
                  is_binary(page_token),
                  do: %{id: id, name: name, access_token: page_token}

            cond do
              data == [] ->
                empty_accounts_error(token)

              pages == [] ->
                {:error,
                 {:no_facebook_pages,
                  "Facebook returned Pages but none included a page **access_token**. " <>
                    "Grant **pages_show_list** (and posting scopes) on the Auth0 Facebook connection, then reconnect."}}

              true ->
                {:ok, pages}
            end

          {:ok, decoded} ->
            Logger.error("Facebook API unexpected /me/accounts shape: #{inspect(decoded)}")
            {:error, {:facebook_error, 200, decoded}}

          {:error, _} = err ->
            err
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("Facebook API error #{status}: #{inspect(body)}")
        {:error, {:facebook_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_graph_json(body) when is_map(body), do: {:ok, body}

  defp decode_graph_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, {:facebook_error, 200, body}}
      {:error, _} -> {:error, {:facebook_error, 200, body}}
    end
  end

  defp decode_graph_json(body), do: {:error, {:facebook_error, 200, body}}

  defp empty_accounts_error(token) do
    case fetch_granted_facebook_permissions(token) do
      {:ok, granted} ->
        Logger.warning(
          "Facebook: /me/accounts returned []; granted permissions=#{inspect(granted)}"
        )

        if "pages_show_list" in granted do
          {:error,
           {:no_facebook_pages,
            "Meta granted **pages_show_list**, but **/me/accounts** is still empty. " <>
              "Create a **Facebook Page** (or ensure you’re a Page admin). " <>
              "Pages under Business Manager sometimes need **business_management** in OAuth — add it to " <>
              "`AUTH0_FACEBOOK_CONNECTION_SCOPE` / Auth0 Facebook scopes, then disconnect and reconnect."}}
        else
          {:error,
           {:no_facebook_pages,
            "This Facebook token does **not** include **pages_show_list** (Meta reports: #{inspect(granted)}). " <>
              "In **Auth0 → Authentication → Social → Facebook**, set **Permissions** to include " <>
              "`pages_show_list,pages_manage_posts` (comma-separated). " <>
              "Confirm **config** uses commas: `pages_show_list,pages_manage_posts`. " <>
              "Then **disconnect** Facebook in Connections and **connect again** so consent includes Page permissions."}}
        end

      {:error, _} ->
        {:error,
         {:no_facebook_pages,
          "Facebook returned no Pages (/me/accounts → data: []). " <>
            "Could not read /me/permissions. Ensure **Connect Facebook** completed with " <>
            "**pages_show_list,pages_manage_posts** (comma-separated for Meta), then reconnect."}}
    end
  end

  defp fetch_granted_facebook_permissions(token) do
    case Req.get("#{@graph_url}/me/permissions", params: [access_token: token]) do
      {:ok, %{status: 200, body: body}} ->
        case decode_graph_json(body) do
          {:ok, %{"data" => data}} when is_list(data) ->
            granted =
              for %{"permission" => perm, "status" => "granted"} <- data,
                  is_binary(perm),
                  do: perm

            {:ok, granted}

          {:ok, _} ->
            {:ok, []}

          {:error, _} = err ->
            err
        end

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Facebook /me/permissions failed status=#{status} body=#{inspect(body)}")
        {:error, :permissions_http}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp pick_page([], _preferred_page_id), do: {:error, {:no_pages_found}}
  defp pick_page(pages, nil), do: {:ok, hd(pages)}

  defp pick_page(pages, preferred_page_id) do
    case Enum.find(pages, fn p -> p.id == preferred_page_id end) do
      nil -> {:error, {:page_not_found, preferred_page_id}}
      page -> {:ok, page}
    end
  end

  defp create_page_feed_post(page, content, link) do
    form =
      %{message: content, access_token: page.access_token}
      |> maybe_put(:link, link)

    case Req.post("#{@graph_url}/#{page.id}/feed", form: form) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        # Req may return JSON as string; success is {"id": "pageid_postid"}.
        case decode_graph_json(body) do
          {:ok, %{"id" => post_id}} when is_binary(post_id) ->
            {:ok, %{id: post_id}}

          {:ok, decoded} ->
            Logger.error("Facebook feed post unexpected 2xx body: #{inspect(decoded)}")
            {:error, {:facebook_error, status, decoded}}

          {:error, _} ->
            {:error, {:facebook_error, status, body}}
        end

      {:ok, %{status: status, body: body}} ->
        case decode_graph_json(body) do
          {:ok, %{"error" => %{"code" => 4}}} ->
            Logger.warning("Facebook rate limit hit (status #{status})")
            {:error, :rate_limited}

          {:ok, %{"error" => %{"code" => 190}}} ->
            {:error, :unauthorized}

          {:ok, decoded} ->
            Logger.error("Facebook API error #{status}: #{inspect(decoded)}")
            {:error, {:facebook_error, status, decoded}}

          {:error, _} ->
            Logger.error("Facebook API error #{status}: #{inspect(body)}")
            {:error, {:facebook_error, status, body}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
