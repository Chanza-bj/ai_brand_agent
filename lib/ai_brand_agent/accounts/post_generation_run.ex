defmodule AiBrandAgent.Accounts.PostGenerationRun do
  @moduledoc """
  Groups multiple candidate posts (variants) generated for one topic + platform run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "post_generation_runs" do
    belongs_to :user, AiBrandAgent.Accounts.User
    belongs_to :topic, AiBrandAgent.Accounts.Topic

    has_many :posts, AiBrandAgent.Accounts.Post, foreign_key: :generation_run_id

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:user_id, :topic_id])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:topic_id)
  end
end
