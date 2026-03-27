defmodule AiBrandAgent.Workers.ContentWorkerTest do
  use AiBrandAgent.DataCase, async: true

  alias AiBrandAgent.Workers.ContentWorker

  describe "new/1" do
    test "creates a job with topic_id" do
      changeset = ContentWorker.new(%{topic_id: Ecto.UUID.generate()})
      assert changeset.valid?
    end

    test "job is in the content queue" do
      changeset = ContentWorker.new(%{topic_id: Ecto.UUID.generate()})
      assert Ecto.Changeset.get_field(changeset, :queue) == "content"
    end
  end

  describe "perform/1 with missing topic" do
    test "discards job when topic does not exist" do
      job = %Oban.Job{args: %{"topic_id" => Ecto.UUID.generate()}}
      assert :discard = ContentWorker.perform(job)
    end
  end
end
