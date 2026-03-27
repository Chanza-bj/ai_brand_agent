defmodule AiBrandAgent.Trends.StubFetcher do
  @moduledoc false
  @behaviour AiBrandAgent.Trends.Fetcher

  @impl true
  def fetch_for_user(%{id: user_id}, seeds) when is_list(seeds) do
    rows =
      for seed <- seeds do
        %{
          title: "Stub topic for #{seed.phrase}",
          user_id: user_id,
          user_topic_seed_id: seed.id,
          source: "stub",
          metadata: %{source: "stub"}
        }
      end

    {:ok, rows}
  end
end
