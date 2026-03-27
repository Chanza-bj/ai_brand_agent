defmodule AiBrandAgent.Workers.TrendWorkerTest do
  use AiBrandAgent.DataCase, async: false

  import AiBrandAgent.Fixtures

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Services.ContentService
  alias AiBrandAgent.Workers.TrendWorker

  setup do
    Ecto.Adapters.SQL.Sandbox.allow(
      AiBrandAgent.Repo,
      self(),
      Process.whereis(AiBrandAgent.Agents.TrendAgent)
    )

    previous = Application.get_env(:ai_brand_agent, :trend_fetcher)

    Application.put_env(:ai_brand_agent, :trend_fetcher, AiBrandAgent.Trends.StubFetcher)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:ai_brand_agent, :trend_fetcher)
      else
        Application.put_env(:ai_brand_agent, :trend_fetcher, previous)
      end
    end)

    :ok
  end

  describe "perform/1" do
    test "creates user-scoped topics when user has enabled seeds" do
      user = user_fixture()
      {:ok, _} = Accounts.create_user_topic_seed(user.id, %{phrase: "OAuth tips"})

      assert :ok = TrendWorker.perform(%Oban.Job{})

      topics = ContentService.list_topics_for_user(user.id, 10)
      assert length(topics) >= 1
      assert Enum.any?(topics, &String.contains?(&1.title, "OAuth tips"))
    end

    test "no-op when no users have seeds" do
      _user = user_fixture()
      assert :ok = TrendWorker.perform(%Oban.Job{})
    end
  end

  describe "new/1" do
    test "creates a valid Oban job changeset" do
      changeset = TrendWorker.new(%{})
      assert changeset.valid?
    end
  end
end
