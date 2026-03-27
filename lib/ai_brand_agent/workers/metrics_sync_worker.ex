defmodule AiBrandAgent.Workers.MetricsSyncWorker do
  @moduledoc """
  Periodically records engagement snapshots for published posts.

  When platform APIs return insights, plug them in here. Until then, inserts a
  baseline row so `EngagementInsights` can aggregate once real data exists.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  import Ecto.Query

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Accounts.Post
  alias AiBrandAgent.Accounts.PostMetric
  alias AiBrandAgent.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    cutoff = DateTime.add(now, -48 * 3600, :second)

    posts =
      from(p in Post,
        where: p.status == "published",
        where: not is_nil(p.platform_post_id),
        where: p.published_at >= ^cutoff,
        select: p.id
      )
      |> Repo.all()

    Enum.each(posts, fn post_id ->
      recent? =
        Repo.exists?(
          from(m in PostMetric,
            where: m.post_id == ^post_id,
            where: m.captured_at >= ^cutoff
          )
        )

      unless recent? do
        _ =
          Accounts.insert_post_metric(%{
            post_id: post_id,
            captured_at: now,
            likes: 0,
            comments: 0,
            impressions: 0,
            raw: %{"source" => "placeholder_until_platform_api"}
          })
      end
    end)

    :ok
  end
end
