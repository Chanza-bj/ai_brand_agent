defmodule AiBrandAgent.Workers.DraftPrunerWorker do
  @moduledoc """
  Oban cron worker that removes stale draft posts.

  Drafts that have not been approved within 48 hours are considered
  abandoned and are automatically deleted to keep the dashboard clean.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias AiBrandAgent.Services.ContentService

  @stale_hours 48

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {count, _} = ContentService.delete_stale_drafts(@stale_hours)

    if count > 0 do
      Logger.info(
        "DraftPrunerWorker: removed #{count} stale draft(s) older than #{@stale_hours}h"
      )
    end

    :ok
  end
end
