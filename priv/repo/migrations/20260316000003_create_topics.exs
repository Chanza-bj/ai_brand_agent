defmodule AiBrandAgent.Repo.Migrations.CreateTopics do
  use Ecto.Migration

  def change do
    create table(:topics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :source, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
