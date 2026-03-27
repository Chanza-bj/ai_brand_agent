defmodule AiBrandAgent.Repo.Migrations.CreateUserBrandProfiles do
  use Ecto.Migration

  def change do
    create table(:user_brand_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :enabled, :boolean, null: false, default: false

      add :product_or_service_name, :string
      add :pitch, :text
      add :call_to_action, :string
      add :link_url, :string

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_brand_profiles, [:user_id])
  end
end
