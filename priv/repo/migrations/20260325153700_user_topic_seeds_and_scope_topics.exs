defmodule AiBrandAgent.Repo.Migrations.UserTopicSeedsAndScopeTopics do
  use Ecto.Migration

  def change do
    create table(:user_topic_seeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :phrase, :string, null: false

      add :metadata, :map, default: %{}

      add :enabled, :boolean, null: false, default: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:user_topic_seeds, [:user_id])

    alter table(:topics) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      add :user_topic_seed_id,
          references(:user_topic_seeds, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:topics, [:user_id])

    create unique_index(:topics, [:user_id, :title],
             name: :topics_user_id_title_unique_index,
             where: "user_id IS NOT NULL"
           )
  end
end
