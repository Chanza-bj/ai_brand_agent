defmodule AiBrandAgent.Repo.Migrations.PostsDraftReadyEmailSentAt do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :draft_ready_email_sent_at, :utc_datetime
    end
  end
end
