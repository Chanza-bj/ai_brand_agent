defmodule AiBrandAgent.Repo.Migrations.AddAgentPostingAndMetrics do
  use Ecto.Migration

  def change do
    create table(:post_generation_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :topic_id, references(:topics, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:post_generation_runs, [:user_id])
    create index(:post_generation_runs, [:topic_id])

    create table(:user_posting_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :timezone, :string, null: false, default: "Etc/UTC"
      # 1 = Monday .. 7 = Sunday (Date.day_of_week/1)
      add :posting_weekdays, {:array, :integer},
        null: false,
        default: fragment("ARRAY[1,2,3,4,5]::integer[]")

      add :default_post_time, :string, null: false, default: "09:00"
      add :auto_approve, :boolean, null: false, default: false
      add :auto_post, :boolean, null: false, default: false
      add :max_posts_per_day, :integer, null: false, default: 3

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_posting_preferences, [:user_id])

    create table(:post_metrics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :captured_at, :utc_datetime, null: false
      add :likes, :integer, default: 0
      add :comments, :integer, default: 0
      add :impressions, :integer, default: 0
      add :raw, :map
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:post_metrics, [:post_id])
    create index(:post_metrics, [:captured_at])

    create table(:agent_decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :action, :string, null: false
      add :metadata, :map
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:agent_decisions, [:user_id])
    create index(:agent_decisions, [:post_id])

    alter table(:posts) do
      add :generation_run_id,
          references(:post_generation_runs, type: :binary_id, on_delete: :nilify_all)

      add :variant_index, :integer
      add :style_tag, :string
    end

    create index(:posts, [:generation_run_id])
  end
end
