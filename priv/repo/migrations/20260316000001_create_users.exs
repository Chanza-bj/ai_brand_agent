defmodule AiBrandAgent.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :auth0_user_id, :string, null: false
      add :email, :string, null: false
      add :name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:auth0_user_id])
    create unique_index(:users, [:email])
  end
end
