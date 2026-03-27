defmodule AiBrandAgent.Accounts.Topic do
  @moduledoc """
  A trending topic discovered by the TrendAgent.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "topics" do
    field :title, :string
    field :source, :string
    field :metadata, :map, default: %{}

    belongs_to :user, AiBrandAgent.Accounts.User

    belongs_to :user_topic_seed, AiBrandAgent.Accounts.UserTopicSeed,
      foreign_key: :user_topic_seed_id

    has_many :posts, AiBrandAgent.Accounts.Post

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [:title, :source, :metadata, :user_id, :user_topic_seed_id])
    |> validate_required([:title])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:user_topic_seed_id)
  end
end
