defmodule AiBrandAgent.Accounts do
  @moduledoc """
  Context module for user accounts and social connections.
  """

  import Ecto.Query

  alias AiBrandAgent.Auth.TokenVault
  alias AiBrandAgent.Repo
  alias AiBrandAgent.Social.FacebookClient

  alias AiBrandAgent.Accounts.{
    User,
    SocialConnection,
    UserTopicSeed,
    UserBrandProfile,
    UserPostingPreference,
    PostGenerationRun,
    PostMetric,
    AgentDecision
  }

  @doc """
  Returns true when the cookie session token matches the one stored for the user.
  """
  def session_valid?(%User{} = user, cookie_token) when is_binary(cookie_token) do
    case user.current_session_token do
      nil ->
        false

      db_token when is_binary(db_token) ->
        if byte_size(db_token) == byte_size(cookie_token) do
          Plug.Crypto.secure_compare(db_token, cookie_token)
        else
          false
        end
    end
  end

  def session_valid?(_user, _cookie_token), do: false

  @doc """
  True when the user has no server-side token yet and the cookie has none (pre–single-session rows).
  The browser plug will issue a token on the next HTTP request.
  """
  def legacy_bootstrap?(%User{current_session_token: nil}, nil), do: true
  def legacy_bootstrap?(_user, _cookie_token), do: false

  @doc """
  Generates a new random session token, persists it on the user, and returns the token
  (for storing in the session cookie). New logins call this so other browsers are logged out.
  """
  def assign_new_session_token!(%User{} = user) do
    token = generate_session_token()

    user
    |> User.session_token_changeset(%{current_session_token: token})
    |> Repo.update!()

    token
  end

  @doc "Clears the server-side session token (e.g. on logout)."
  def clear_session_token!(%User{} = user) do
    user
    |> User.session_token_changeset(%{current_session_token: nil})
    |> Repo.update!()

    :ok
  end

  defp generate_session_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Find or create a user from Auth0 profile data.

  Called during the OAuth callback to upsert the user record.
  """
  def upsert_user_from_auth0(%{"sub" => auth0_id} = profile) do
    email = Map.get(profile, "email")
    name = Map.get(profile, "name") || email || auth0_id

    attrs =
      %{auth0_user_id: auth0_id, name: name}
      |> maybe_put(:email, email)

    case Repo.get_by(User, auth0_user_id: auth0_id) do
      nil ->
        %User{}
        |> User.changeset(attrs)
        |> Repo.insert()

      user ->
        user
        |> User.changeset(attrs)
        |> Repo.update()
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc "Get a user by internal ID."
  def get_user(id), do: Repo.get(User, id)

  @doc "Get a user by Auth0 user ID."
  def get_user_by_auth0_id(auth0_id) do
    Repo.get_by(User, auth0_user_id: auth0_id)
  end

  @doc "List social connections for a user."
  def list_connections(user_id) do
    SocialConnection
    |> where(user_id: ^user_id)
    |> Repo.all()
  end

  @doc "Create or update a social connection."
  def upsert_connection(user_id, attrs) do
    platform = Map.get(attrs, :platform) || Map.get(attrs, "platform")

    attrs = Map.put(attrs, :user_id, user_id)

    case Repo.get_by(SocialConnection, user_id: user_id, platform: platform) do
      nil ->
        %SocialConnection{}
        |> SocialConnection.changeset(attrs)
        |> Repo.insert()

      conn ->
        conn
        |> SocialConnection.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Returns Facebook Pages the user can publish to (names + ids), or `{:error, reason}`.
  """
  def list_facebook_pages(user_id) do
    with {:ok, token} <- TokenVault.get_access_token(user_id, "facebook") do
      FacebookClient.list_managed_pages(token)
    end
  end

  @doc """
  Sets which Facebook Page ID to use when publishing (`social_connections.platform_user_id`).
  Pass `""` or `nil` to clear and use the first Page Graph returns.
  """
  def set_facebook_default_page(user_id, page_id) do
    page_id =
      case page_id do
        nil ->
          nil

        "" ->
          nil

        s when is_binary(s) ->
          s = String.trim(s)
          if s == "", do: nil, else: s
      end

    cond do
      page_id != nil and not String.match?(page_id, ~r/^\d+$/) ->
        {:error, :invalid_page_id}

      true ->
        case Repo.get_by(SocialConnection, user_id: user_id, platform: "facebook") do
          nil ->
            {:error, :not_connected}

          %SocialConnection{} = conn ->
            conn
            |> SocialConnection.changeset(%{platform_user_id: page_id})
            |> Repo.update()
        end
    end
  end

  @doc "Delete a social connection."
  def delete_connection(connection_id) do
    case Repo.get(SocialConnection, connection_id) do
      nil -> {:error, :not_found}
      conn -> Repo.delete(conn)
    end
  end

  # ── User topic seeds (niches) ─────────────────────────────────────────

  @max_topic_seeds_per_user 10

  @doc "List a user's niche seeds (topic phrases)."
  def list_user_topic_seeds(user_id) do
    UserTopicSeed
    |> where(user_id: ^user_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc "Enabled seeds only, for TrendWorker."
  def list_enabled_seeds_for_user(user_id) do
    UserTopicSeed
    |> where(user_id: ^user_id, enabled: true)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc "Distinct user IDs that have at least one enabled seed."
  def list_user_ids_with_enabled_seeds do
    from(s in UserTopicSeed,
      where: s.enabled == true,
      distinct: true,
      select: s.user_id
    )
    |> Repo.all()
  end

  def get_user_topic_seed(user_id, seed_id) do
    Repo.get_by(UserTopicSeed, id: seed_id, user_id: user_id)
  end

  def count_user_topic_seeds(user_id) do
    UserTopicSeed
    |> where(user_id: ^user_id)
    |> select([s], count(s.id))
    |> Repo.one()
  end

  def create_user_topic_seed(user_id, attrs) when is_map(attrs) do
    if count_user_topic_seeds(user_id) >= @max_topic_seeds_per_user do
      {:error, :too_many_seeds}
    else
      %UserTopicSeed{}
      |> UserTopicSeed.changeset(Map.put(attrs, :user_id, user_id))
      |> Repo.insert()
    end
  end

  def update_user_topic_seed(%UserTopicSeed{} = seed, attrs) do
    seed
    |> UserTopicSeed.changeset(attrs)
    |> Repo.update()
  end

  def delete_user_topic_seed(user_id, seed_id) do
    case get_user_topic_seed(user_id, seed_id) do
      nil -> {:error, :not_found}
      %UserTopicSeed{} = seed -> Repo.delete(seed)
    end
  end

  # ── Brand / promotion context (optional product or service copy) ─────

  @doc "Returns the user's brand profile row, or nil."
  def get_brand_profile_for_user(user_id) do
    Repo.get_by(UserBrandProfile, user_id: user_id)
  end

  @doc """
  Builds a map for the LLM when promotion is enabled and at least one of
  name or pitch is present. Otherwise returns `nil`.
  """
  def brand_promotion_context_for_llm(user_id) do
    case get_brand_profile_for_user(user_id) do
      nil ->
        nil

      %{enabled: false} ->
        nil

      %UserBrandProfile{} = p ->
        if promotion_context_blank?(p) do
          nil
        else
          ctx =
            %{}
            |> maybe_put_promo(:product_or_service_name, p.product_or_service_name)
            |> maybe_put_promo(:pitch, p.pitch)
            |> maybe_put_promo(:call_to_action, p.call_to_action)
            |> maybe_put_promo(:link_url, p.link_url)

          if map_size(ctx) == 0, do: nil, else: ctx
        end
    end
  end

  defp promotion_context_blank?(%UserBrandProfile{} = p) do
    str_blank?(p.product_or_service_name) and str_blank?(p.pitch)
  end

  defp str_blank?(nil), do: true
  defp str_blank?(s) when is_binary(s), do: String.trim(s) == ""

  defp maybe_put_promo(map, _key, nil), do: map

  defp maybe_put_promo(map, key, s) when is_binary(s) do
    if str_blank?(s), do: map, else: Map.put(map, key, String.trim(s))
  end

  @doc "Create or update the single brand profile row for a user."
  def upsert_brand_profile(user_id, attrs) when is_map(attrs) do
    base = Map.put(attrs, :user_id, user_id)

    case get_brand_profile_for_user(user_id) do
      nil ->
        %UserBrandProfile{}
        |> UserBrandProfile.changeset(base)
        |> Repo.insert()

      %UserBrandProfile{} = profile ->
        profile
        |> UserBrandProfile.changeset(base)
        |> Repo.update()
    end
  end

  # ── Posting agent preferences ───────────────────────────────────────

  @doc "Returns posting preferences for the user, creating defaults if missing."
  def get_posting_preferences_for_user(user_id) do
    case Repo.get_by(UserPostingPreference, user_id: user_id) do
      nil ->
        {:ok, p} =
          %UserPostingPreference{}
          |> UserPostingPreference.changeset(%{user_id: user_id})
          |> Repo.insert()

        p

      %UserPostingPreference{} = p ->
        p
    end
  end

  def upsert_posting_preferences(user_id, attrs) when is_map(attrs) do
    base =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put(:max_posts_per_day, 3)
      |> Map.put(:auto_approve, true)
      |> Map.put(:auto_post, true)

    case Repo.get_by(UserPostingPreference, user_id: user_id) do
      nil ->
        %UserPostingPreference{}
        |> UserPostingPreference.changeset(base)
        |> Repo.insert()

      %UserPostingPreference{} = pref ->
        pref
        |> UserPostingPreference.changeset(base)
        |> Repo.update()
    end
  end

  @doc "Stores the Google Calendar recurring series id after syncing posting windows."
  def update_agent_calendar_recurring_event_id(user_id, event_id)
      when is_binary(user_id) and is_binary(event_id) do
    case Repo.get_by(UserPostingPreference, user_id: user_id) do
      nil ->
        {:error, :not_found}

      %UserPostingPreference{} = pref ->
        pref
        |> UserPostingPreference.changeset(%{agent_calendar_recurring_event_id: event_id})
        |> Repo.update()
    end
  end

  def log_agent_decision(user_id, post_id, action, metadata \\ %{}) when is_binary(action) do
    %AgentDecision{}
    |> AgentDecision.changeset(%{
      user_id: user_id,
      post_id: post_id,
      action: action,
      metadata: metadata
    })
    |> Repo.insert()
  end

  @doc "Insert a post metrics snapshot (e.g. after sync from a platform API)."
  def insert_post_metric(attrs) when is_map(attrs) do
    %PostMetric{}
    |> PostMetric.changeset(attrs)
    |> Repo.insert()
  end

  def create_generation_run(user_id, topic_id) do
    %PostGenerationRun{}
    |> PostGenerationRun.changeset(%{user_id: user_id, topic_id: topic_id})
    |> Repo.insert()
  end

  @doc "True if the user has a social connection for that publishing platform."
  def has_publishing_connection?(user_id, platform)
      when platform in ["linkedin", "facebook"] do
    Repo.exists?(
      from sc in SocialConnection,
        where: sc.user_id == ^user_id and sc.platform == ^platform
    )
  end

  def has_publishing_connection?(_user_id, _platform), do: false
end
