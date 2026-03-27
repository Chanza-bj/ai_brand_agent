defmodule AiBrandAgent.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :platform, :string, null: false
      add :content, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :platform_post_id, :string
      add :published_at, :utc_datetime
      add :error_message, :text

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :topic_id, references(:topics, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:posts, [:user_id, :status])
    create index(:posts, [:published_at])
    create index(:posts, [:topic_id])
  end
end
