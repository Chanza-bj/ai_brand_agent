defmodule AiBrandAgent.Accounts.AgentDecision do
  @moduledoc """
  Audit log when the agent auto-approves or auto-schedules a post.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_decisions" do
    field :action, :string
    field :metadata, :map

    belongs_to :user, AiBrandAgent.Accounts.User
    belongs_to :post, AiBrandAgent.Accounts.Post

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, [:user_id, :post_id, :action, :metadata])
    |> validate_required([:user_id, :post_id, :action])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:post_id)
  end
end
