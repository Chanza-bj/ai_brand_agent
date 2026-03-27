defmodule AiBrandAgent.Repo.Migrations.AddCurrentSessionTokenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :current_session_token, :string
    end
  end
end
