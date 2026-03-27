defmodule AiBrandAgent.Social.LinkedInClient do
  @moduledoc """
  Member text posts via **`POST /v2/ugcPosts`** (legacy UGC Post API).

  **Why not `/rest/posts`?** That route plus **`Linkedin-Version`** is routed like the
  marketing/partner Posts API and often returns **`partnerApiPostsExternal.CREATE`** (403)
  for standard “Share on LinkedIn” developer apps.

  **Why no `Linkedin-Version` here?** Versioned headers target **`/rest/*`**. Sending
  **`Linkedin-Version`** to **`/v2/ugcPosts`** can yield **`ugcPosts.CREATE.NO_VERSION`** (403).
  This client sends only **`Authorization`**, **`X-Restli-Protocol-Version`**, and
  **`Content-Type`**.

  OAuth: **Share on LinkedIn** + **`w_member_social`** (Auth0 `connection_scope` on connect).

  See [UGC Post API](https://learn.microsoft.com/en-us/linkedin/compliance/integrations/shares/ugc-post-api).
  """

  require Logger

  @base_url "https://api.linkedin.com"

  @doc """
  Create a text post on LinkedIn.

  `token` is the OAuth 2.0 bearer token.
  `content` is the post body text.
  `opts` may include `:author_urn` (defaults to fetching from /userinfo).

  Returns `{:ok, %{id: platform_post_id}}` or `{:error, reason}`.
  """
  def create_post(token, content, opts \\ []) do
    with {:ok, author_urn} <- resolve_author(token, opts) do
      body = ugc_text_share_body(author_urn, content)

      url = "#{@base_url}/v2/ugcPosts"
      headers = ugc_posts_headers(token)
      log_outgoing_ugc_post_request(url, headers, body)

      case Req.post(url,
             json: body,
             headers: headers
           ) do
        {:ok, %{status: status, headers: resp_headers}} when status in [200, 201] ->
          post_id = get_header(resp_headers, "x-restli-id")
          {:ok, %{id: post_id}}

        {:ok, %{status: 429, headers: resp_headers}} ->
          retry_after = parse_retry_after(resp_headers)
          {:error, {:rate_limited, retry_after}}

        {:ok, %{status: 401}} ->
          {:error, :unauthorized}

        {:ok, %{status: status, body: body}} ->
          Logger.error("LinkedIn API error #{status}: #{inspect(body)}")
          {:error, {:linkedin_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Fetch the authenticated user's profile URN."
  def get_profile(token) do
    case Req.get("#{@base_url}/v2/userinfo",
           headers: [{"authorization", "Bearer #{token}"}]
         ) do
      {:ok, %{status: 200, body: %{"sub" => sub}}} ->
        {:ok, "urn:li:person:#{sub}"}

      {:ok, %{status: status, body: body}} ->
        {:error, {:linkedin_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp resolve_author(token, opts) do
    case Keyword.get(opts, :author_urn) do
      nil -> get_profile(token)
      urn -> {:ok, urn}
    end
  end

  defp log_outgoing_ugc_post_request(url, headers, body) do
    redacted =
      Enum.map(headers, fn
        {"authorization", _} -> {"authorization", "Bearer <redacted>"}
        pair -> pair
      end)

    body_json =
      case Jason.encode(body) do
        {:ok, s} -> s
        {:error, _} -> inspect(body)
      end

    Logger.info(
      """
      LinkedInClient: outgoing UGC post (Bearer token redacted)
      POST #{url}
      headers: #{inspect(Map.new(redacted), pretty: true)}
      body: #{body_json}
      """
      |> String.trim()
    )
  end

  defp ugc_text_share_body(author_urn, text) do
    %{
      author: author_urn,
      lifecycleState: "PUBLISHED",
      specificContent: %{
        "com.linkedin.ugc.ShareContent" => %{
          shareCommentary: %{
            text: text,
            attributes: []
          },
          shareMediaCategory: "NONE"
        }
      },
      visibility: %{
        "com.linkedin.ugc.MemberNetworkVisibility" => "PUBLIC"
      }
    }
  end

  # No Linkedin-Version — that header is for /rest/*; UGC v2 uses Rest.li 2.0 only.
  defp ugc_posts_headers(token) do
    [
      {"authorization", "Bearer #{token}"},
      {"x-restli-protocol-version", "2.0.0"},
      {"content-type", "application/json"}
    ]
  end

  # Req returns response headers as a map (`%{ "x-restli-id" => ["urn:..."] }`), not a list of tuples.
  defp get_header(headers, name) when is_map(headers) do
    wanted = String.downcase(name)

    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == wanted, do: normalize_header_value(v)
    end)
  end

  defp get_header(headers, name) when is_list(headers) do
    case List.keyfind(headers, name, 0) do
      {_, value} ->
        normalize_header_value(value)

      nil ->
        wanted = String.downcase(name)

        case Enum.find(headers, fn {k, _} -> String.downcase(to_string(k)) == wanted end) do
          {_, value} -> normalize_header_value(value)
          nil -> nil
        end
    end
  end

  defp get_header(_headers, _name), do: nil

  defp normalize_header_value(v) when is_list(v) and v != [], do: List.first(v)
  defp normalize_header_value(v) when is_binary(v), do: v
  defp normalize_header_value(_), do: nil

  defp parse_retry_after(headers) do
    case get_header(headers, "retry-after") do
      nil -> 60
      val when is_binary(val) -> String.to_integer(val)
      _ -> 60
    end
  rescue
    _ -> 60
  end
end
