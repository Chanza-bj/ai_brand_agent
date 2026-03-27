defmodule AiBrandAgent.Accounts.UserBrandProfile do
  @moduledoc """
  Optional copy points for a user's product or service, used to tailor AI drafts
  toward authentic promotion without replacing niche/trend discovery.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_brand_profiles" do
    field :enabled, :boolean, default: false
    field :product_or_service_name, :string
    field :pitch, :string
    field :call_to_action, :string
    field :link_url, :string

    belongs_to :user, AiBrandAgent.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :enabled,
      :product_or_service_name,
      :pitch,
      :call_to_action,
      :link_url,
      :user_id
    ])
    |> validate_required([:user_id])
    |> validate_length(:product_or_service_name, max: 200)
    |> validate_length(:pitch, max: 5000)
    |> validate_length(:call_to_action, max: 500)
    |> validate_length(:link_url, max: 2000)
    |> validate_promo_content_when_enabled()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end

  defp validate_promo_content_when_enabled(changeset) do
    if Ecto.Changeset.get_field(changeset, :enabled) do
      name = Ecto.Changeset.get_field(changeset, :product_or_service_name)
      pitch = Ecto.Changeset.get_field(changeset, :pitch)

      if blank_str?(name) and blank_str?(pitch) do
        Ecto.Changeset.add_error(
          changeset,
          :product_or_service_name,
          "add a product or service name, or a pitch, when promotion is enabled"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp blank_str?(nil), do: true
  defp blank_str?(s) when is_binary(s), do: String.trim(s) == ""
end
