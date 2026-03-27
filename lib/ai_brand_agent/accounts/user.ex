defmodule AiBrandAgent.Accounts.User do
  @moduledoc """
  Schema for application users, linked to Auth0 via `auth0_user_id`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :auth0_user_id, :string
    field :email, :string
    field :name, :string
    field :auth0_refresh_token, :string
    field :current_session_token, :string

    has_many :social_connections, AiBrandAgent.Accounts.SocialConnection
    has_many :posts, AiBrandAgent.Accounts.Post
    has_many :user_topic_seeds, AiBrandAgent.Accounts.UserTopicSeed
    has_many :topics, AiBrandAgent.Accounts.Topic
    has_one :brand_profile, AiBrandAgent.Accounts.UserBrandProfile

    timestamps(type: :utc_datetime)
  end

  @email_format ~r/^[^\s]+@[^\s]+$/

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:auth0_user_id, :email, :name, :auth0_refresh_token])
    |> validate_required([:auth0_user_id, :email])
    |> validate_format(:email, @email_format, message: "must have the @ sign and no spaces")
    |> unique_constraint(:auth0_user_id)
    |> unique_constraint(:email)
  end

  @doc """
  Updates the server-side session token (single active session per user).
  """
  def session_token_changeset(user, attrs) do
    user
    |> cast(attrs, [:current_session_token])
  end
end
