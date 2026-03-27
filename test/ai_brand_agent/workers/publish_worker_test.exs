defmodule AiBrandAgent.Workers.PublishWorkerTest do
  use ExUnit.Case, async: true

  alias AiBrandAgent.Workers.PublishWorker

  describe "new/1" do
    test "creates a job with post_id" do
      changeset = PublishWorker.new(%{post_id: Ecto.UUID.generate()})
      assert changeset.valid?
    end

    test "job is in the publish queue" do
      changeset = PublishWorker.new(%{post_id: Ecto.UUID.generate()})
      assert Ecto.Changeset.get_field(changeset, :queue) == "publish"
    end

    test "max_attempts is 5" do
      changeset = PublishWorker.new(%{post_id: Ecto.UUID.generate()})
      assert Ecto.Changeset.get_field(changeset, :max_attempts) == 5
    end
  end
end
