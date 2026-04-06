defmodule AiBrandAgent.Services.ContentService do
  @moduledoc """
  Business logic for topics and post content.

  Provides the persistence layer that agents and workers delegate to.
  """

  import Ecto.Query

  alias AiBrandAgent.Repo
  alias AiBrandAgent.Accounts.{Post, Topic}

  # ── Topics ──────────────────────────────────────────────────────────

  @doc """
  Find an existing topic for this user by title or insert a new row.

  Requires `user_id` in `attrs` (or as first arg). Scopes uniqueness per user.
  """
  def find_or_create_topic_for_user(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
    attrs =
      attrs
      |> normalize_topic_attrs()
      |> Map.put(:user_id, user_id)

    title = Map.fetch!(attrs, :title)

    case Repo.get_by(Topic, user_id: user_id, title: title) do
      nil ->
        %Topic{}
        |> Topic.changeset(attrs)
        |> Repo.insert()

      topic ->
        {:ok, topic}
    end
  end

  @doc "Get a topic by ID (any user)."
  def get_topic(id), do: Repo.get(Topic, id)

  @doc "Get a topic by ID only if it belongs to the user."
  def get_topic_for_user(topic_id, user_id) do
    Repo.get_by(Topic, id: topic_id, user_id: user_id)
  end

  @doc "Recent discovered topics for a user (dashboard, trends panel)."
  def list_topics_for_user(user_id, limit \\ 20) do
    Topic
    |> where(user_id: ^user_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "List recent topics globally (legacy / admin); prefer `list_topics_for_user/2`."
  def list_recent_topics(limit \\ 20) do
    Topic
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ── Posts ────────────────────────────────────────────────────────────

  @doc "Create a new post (typically as a draft)."
  def create_post(attrs) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get a post by ID, optionally preloading associations."
  def get_post(id, preloads \\ []) do
    Post
    |> Repo.get(id)
    |> maybe_preload(preloads)
  end

  @doc """
  Get a post by ID only if it belongs to `user_id`.

  Use this for browser/API flows to prevent IDOR. Internal jobs may use `get_post/2`
  when the caller has already validated ownership.
  """
  def get_post_for_user(id, user_id, preloads \\ []) do
    Post
    |> Repo.get_by(id: id, user_id: user_id)
    |> maybe_preload(preloads)
  end

  @doc """
  Count posts per status for dashboard stats (all posts for the user, not a limited sample).
  """
  def post_dashboard_stats(user_id) do
    counts =
      from(p in Post,
        where: p.user_id == ^user_id,
        group_by: p.status,
        select: {p.status, count(p.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      drafts: Map.get(counts, "draft", 0),
      approved: Map.get(counts, "approved", 0),
      scheduled: Map.get(counts, "scheduled", 0),
      published: Map.get(counts, "published", 0)
    }
  end

  @doc "Mark an approved post as scheduled (Smart Schedule / calendar queue)."
  def mark_post_scheduled(%Post{status: "approved"} = post) do
    post
    |> Post.status_changeset("scheduled")
    |> Repo.update()
  end

  def mark_post_scheduled(%Post{status: status}) do
    {:error, {:invalid_transition, status, "scheduled"}}
  end

  @doc """
  List posts for a user, optionally filtered by status.

  Options:
  - `:exclude_discarded` — when true (default), omits `discarded` variants from multi-candidate runs.
  """
  def list_posts(user_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)
    exclude_discarded = Keyword.get(opts, :exclude_discarded, true)
    exclude_discarded = if status == "discarded", do: false, else: exclude_discarded

    Post
    |> where(user_id: ^user_id)
    |> maybe_exclude_discarded(exclude_discarded)
    |> maybe_filter_status(status)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:topic)
    |> Repo.all()
  end

  @doc "Mark a draft as discarded (losing variant in a multi-candidate run)."
  def discard_post(%Post{status: "draft"} = post) do
    post
    |> Post.status_changeset("discarded")
    |> Repo.update()
  end

  def discard_post(%Post{status: status}) do
    {:error, {:invalid_transition, status, "discarded"}}
  end

  @doc "Count posts published on a given UTC calendar date (for daily caps)."
  def count_published_posts_on_date(user_id, %Date{} = d) do
    start = DateTime.new!(d, ~T[00:00:00.000000], "Etc/UTC")
    ending = DateTime.add(start, 1, :day)

    from(p in Post,
      where: p.user_id == ^user_id,
      where: p.status == "published",
      where: not is_nil(p.published_at),
      where: p.published_at >= ^start and p.published_at < ^ending,
      select: count(p.id)
    )
    |> Repo.one()
  end

  @doc """
  Count posts published on the **user's local calendar day** (IANA `timezone`),
  e.g. three posts per local day, not UTC midnight.
  """
  def count_published_posts_in_local_calendar_day(user_id, timezone)
      when is_binary(user_id) do
    tz =
      if is_binary(timezone) and String.trim(timezone) != "" do
        String.trim(timezone)
      else
        "Etc/UTC"
      end

    now_utc = DateTime.utc_now() |> DateTime.truncate(:second)
    local_date = now_utc |> DateTime.shift_zone!(tz) |> DateTime.to_date()
    {start_utc, end_utc} = local_day_utc_bounds(local_date, tz)

    from(p in Post,
      where: p.user_id == ^user_id,
      where: p.status == "published",
      where: not is_nil(p.published_at),
      where: p.published_at >= ^start_utc and p.published_at < ^end_utc,
      select: count(p.id)
    )
    |> Repo.one()
  end

  defp local_day_utc_bounds(%Date{} = local_date, tz) do
    case DateTime.new(local_date, ~T[00:00:00.000000], tz) do
      {:ok, local_start} ->
        to_utc_day_bounds(local_start)

      {:ambiguous, s1, _} ->
        to_utc_day_bounds(s1)

      {:gap, _, _} ->
        u = DateTime.new!(local_date, ~T[00:00:00.000000], "Etc/UTC")
        to_utc_day_bounds(u)
    end
  end

  defp to_utc_day_bounds(%DateTime{} = local_dt) do
    start_utc = DateTime.shift_zone!(local_dt, "Etc/UTC")
    end_utc = DateTime.add(start_utc, 86400, :second)
    {start_utc, end_utc}
  end

  @doc "Approve a draft post, making it eligible for publishing."
  def approve_post(%Post{status: "draft"} = post) do
    post
    |> Post.status_changeset("approved")
    |> Repo.update()
  end

  def approve_post(%Post{status: status}) do
    {:error, {:invalid_transition, status, "approved"}}
  end

  @doc "Reset a failed post back to approved so it can be retried."
  def retry_post(%Post{status: "failed"} = post) do
    post
    |> Post.status_changeset("approved", %{error_message: nil})
    |> Repo.update()
  end

  def retry_post(%Post{status: status}) do
    {:error, {:invalid_transition, status, "approved"}}
  end

  @doc "Update the content of a draft post."
  def update_post_content(%Post{status: "draft"} = post, content) do
    post
    |> Post.changeset(%{content: content})
    |> Repo.update()
  end

  def update_post_content(%Post{status: status}, _content) do
    {:error, {:not_editable, status}}
  end

  @doc """
  Records that the Gmail \"draft ready\" notification was sent (idempotent marker).
  """
  def mark_draft_ready_email_sent(%Post{} = post) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    post
    |> Post.changeset(%{draft_ready_email_sent_at: now})
    |> Repo.update()
  end

  @doc """
  Delete draft posts older than `hours` hours.

  Returns `{count, nil}` with the number of deleted rows.
  """
  def delete_stale_drafts(hours \\ 48) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)

    Post
    |> where(status: "draft")
    |> where([p], p.inserted_at < ^cutoff)
    |> Repo.delete_all()
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_exclude_discarded(query, true), do: where(query, [p], p.status != "discarded")
  defp maybe_exclude_discarded(query, false), do: query

  defp maybe_preload(nil, _preloads), do: nil
  defp maybe_preload(record, []), do: record
  defp maybe_preload(record, preloads), do: Repo.preload(record, preloads)

  defp normalize_topic_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {k, v}, acc when k in [:title, :source, :metadata, :user_id, :user_topic_seed_id] ->
        Map.put(acc, k, v)

      {k, v}, acc
      when is_binary(k) and
             k in ~w(title source metadata user_id user_topic_seed_id) ->
        Map.put(acc, String.to_existing_atom(k), v)

      _, acc ->
        acc
    end)
  end

  defp normalize_topic_attrs(_), do: %{}
end
