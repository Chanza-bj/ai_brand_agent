defmodule AiBrandAgent.Accounts.PostMetric do
  @moduledoc """
  Point-in-time engagement snapshot for a published post.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "post_metrics" do
    field :captured_at, :utc_datetime
    field :likes, :integer, default: 0
    field :comments, :integer, default: 0
    field :impressions, :integer, default: 0
    field :raw, :map

    belongs_to :post, AiBrandAgent.Accounts.Post

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(metric, attrs) do
    metric
    |> cast(attrs, [:post_id, :captured_at, :likes, :comments, :impressions, :raw])
    |> validate_required([:post_id, :captured_at])
    |> foreign_key_constraint(:post_id)
  end
end
