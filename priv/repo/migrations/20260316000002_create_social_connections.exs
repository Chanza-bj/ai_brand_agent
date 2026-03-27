defmodule AiBrandAgent.Repo.Migrations.CreateSocialConnections do
  use Ecto.Migration

  def change do
    create table(:social_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :platform, :string, null: false
      add :auth0_connection_id, :string, null: false
      add :platform_user_id, :string

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:social_connections, [:user_id, :platform])
    create index(:social_connections, [:user_id])
  end
end
