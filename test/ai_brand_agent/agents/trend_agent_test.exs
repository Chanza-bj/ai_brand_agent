defmodule AiBrandAgent.Agents.TrendAgentTest do
  use AiBrandAgent.DataCase, async: false

  import AiBrandAgent.Fixtures

  alias AiBrandAgent.Agents.TrendAgent
  alias AiBrandAgent.Services.ContentService

  setup do
    Ecto.Adapters.SQL.Sandbox.allow(
      AiBrandAgent.Repo,
      self(),
      Process.whereis(AiBrandAgent.Agents.TrendAgent)
    )

    :ok
  end

  describe "get_topics/1" do
    test "returns an empty list initially or a list" do
      topics = TrendAgent.get_topics(5)
      assert is_list(topics)
    end
  end

  describe "store_topics/1" do
    test "stores user-scoped topics and makes them retrievable from DB" do
      user = user_fixture()

      topics = [
        %{
          title: "Agent Test Topic 1",
          user_id: user.id,
          source: "test",
          metadata: %{}
        },
        %{
          title: "Agent Test Topic 2",
          user_id: user.id,
          source: "test",
          metadata: %{}
        }
      ]

      :ok = TrendAgent.store_topics(topics)

      stored = ContentService.list_topics_for_user(user.id, 10)
      titles = Enum.map(stored, & &1.title)
      assert "Agent Test Topic 1" in titles
      assert "Agent Test Topic 2" in titles

      cached = TrendAgent.get_topics(10)
      cached_titles = Enum.map(cached, & &1.title)
      assert "Agent Test Topic 1" in cached_titles
    end
  end
end
