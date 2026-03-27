defmodule AiBrandAgent.Workers.UserTrendFetchWorker do
  @moduledoc """
  One-off niche → topic fetch for a single user (e.g. after adding a niche on `/niches`).

  Debounced with Oban uniqueness so rapid adds do not stack many Gemini calls.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 120, fields: [:worker, :args]]

  require Logger

  alias AiBrandAgent.Trends

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Trends.run_fetch_for_user(user_id) do
      :ok -> :ok
      {:error, :user_not_found} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
