defmodule AiBrandAgent.Agents.PostAgent do
  @moduledoc """
  Secure publishing agent. Retrieves OAuth tokens from Auth0 Token Vault,
  dispatches to the appropriate platform client, and records the result.

  Tokens are fetched per-request and never cached in the agent state.
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias AiBrandAgent.Agents.CalendarAgent
  alias AiBrandAgent.Auth.TokenVault
  alias AiBrandAgent.Accounts.SocialConnection
  alias AiBrandAgent.Repo
  alias AiBrandAgent.Services.PublishingService
  alias AiBrandAgent.Social.FacebookClient
  alias AiBrandAgent.Social.LinkedInClient

  @pubsub AiBrandAgent.PubSub

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Publish a post by its ID.

  Retrieves the token from Auth0 Token Vault, publishes via the platform
  client, and records the result. Returns `{:ok, post}` or `{:error, reason}`.
  """
  def publish(post_id) do
    GenServer.call(__MODULE__, {:publish, post_id}, :timer.seconds(30))
  end

  # ── Server callbacks ────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:publish, post_id}, _from, state) do
    result = do_publish(post_id)
    {:reply, result, state}
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp do_publish(post_id) do
    Logger.info("PostAgent.publish: start post_id=#{post_id}")

    with {:ok, post} <- PublishingService.get_publishable_post(post_id),
         :ok <- check_not_busy(post),
         {:ok, post} <- PublishingService.mark_publishing(post) do
      Logger.info(
        "PostAgent.publish: token phase user_id=#{post.user_id} platform=#{inspect(post.platform)} status=publishing"
      )

      with {:ok, token} <- TokenVault.get_access_token(post.user_id, post.platform),
           {:ok, platform_result} <-
             publish_to_platform(post.platform, post.user_id, token, post.content) do
        Logger.info(
          "PostAgent.publish: success post_id=#{post_id} platform=#{inspect(post.platform)}"
        )

        case PublishingService.record_success(post, platform_result) do
          {:ok, updated} ->
            broadcast_published(updated)
            {:ok, updated}

          {:error, _} = err ->
            err
        end
      else
        {:error, :rate_limited} = err ->
          Logger.warning("PostAgent.publish: rate_limited post_id=#{post_id}")
          err

        {:error, reason} = err ->
          Logger.error(
            "PostAgent.publish: failed after mark_publishing post_id=#{post_id} platform=#{inspect(post.platform)} reason=#{inspect(reason)}"
          )

          PublishingService.record_failure(post_id, reason)
          err
      end
    else
      {:error, reason} = err ->
        Logger.error(
          "PostAgent.publish: failed before token phase post_id=#{post_id} reason=#{inspect(reason)}"
        )

        PublishingService.record_failure(post_id, reason)
        err
    end
  end

  # Google Calendar busy check requires a Google Token Vault token. For LinkedIn/Facebook
  # publishes we skip it so we don't call Auth0/Google twice (and spam logs) when the
  # publish target is not Google anyway.
  defp check_not_busy(%{platform: platform, user_id: user_id}) do
    if platform in ["linkedin", "facebook"] do
      Logger.debug(
        "PostAgent.check_not_busy: skipping Calendar busy check for platform=#{inspect(platform)}"
      )

      :ok
    else
      if CalendarAgent.busy?(user_id) do
        {:error, :user_busy}
      else
        :ok
      end
    end
  end

  defp publish_to_platform("linkedin", _user_id, token, content) do
    LinkedInClient.create_post(token, content)
  end

  defp publish_to_platform("facebook", user_id, token, content) do
    opts = facebook_publish_opts(user_id)
    FacebookClient.create_post(token, content, opts)
  end

  defp publish_to_platform(platform, _user_id, _token, _content) do
    {:error, {:unsupported_platform, platform}}
  end

  defp facebook_publish_opts(user_id) do
    query =
      from sc in SocialConnection,
        where: sc.user_id == ^user_id and sc.platform == "facebook",
        limit: 1

    case Repo.one(query) do
      %SocialConnection{platform_user_id: page_id} when is_binary(page_id) ->
        page_id = String.trim(page_id)

        if page_id != "" and String.match?(page_id, ~r/^\d+$/) do
          [page_id: page_id]
        else
          []
        end

      _ ->
        []
    end
  end

  defp broadcast_published(post) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "posts:user:#{post.user_id}",
      {:post_published, post}
    )
  end
end
