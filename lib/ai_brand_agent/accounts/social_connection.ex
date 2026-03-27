defmodule AiBrandAgent.Accounts.SocialConnection do
  @moduledoc """
  Tracks which social platforms a user has connected via Auth0.

  Does NOT store tokens — those live exclusively in Auth0 Token Vault.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "social_connections" do
    field :platform, :string
    field :auth0_connection_id, :string
    field :platform_user_id, :string

    belongs_to :user, AiBrandAgent.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:platform, :auth0_connection_id, :platform_user_id, :user_id])
    |> validate_required([:platform, :auth0_connection_id, :user_id])
    |> validate_inclusion(:platform, ["linkedin", "facebook", "google"])
    |> unique_constraint([:user_id, :platform])
    |> foreign_key_constraint(:user_id)
  end
end
