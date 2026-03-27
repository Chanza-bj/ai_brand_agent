defmodule AiBrandAgent.Accounts.UserTopicSeed do
  @moduledoc """
  A user-defined niche/seed phrase used to discover related trending topics.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_phrase_length 200

  schema "user_topic_seeds" do
    field :phrase, :string
    field :metadata, :map, default: %{}
    field :enabled, :boolean, default: true

    belongs_to :user, AiBrandAgent.Accounts.User
    has_many :topics, AiBrandAgent.Accounts.Topic, foreign_key: :user_topic_seed_id

    timestamps(type: :utc_datetime)
  end

  def changeset(seed, attrs) do
    seed
    |> cast(attrs, [:phrase, :metadata, :enabled, :user_id])
    |> validate_required([:phrase, :user_id])
    |> validate_length(:phrase, max: @max_phrase_length)
    |> foreign_key_constraint(:user_id)
  end
end
