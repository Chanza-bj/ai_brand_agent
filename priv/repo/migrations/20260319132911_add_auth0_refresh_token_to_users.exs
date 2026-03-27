defmodule AiBrandAgent.Repo.Migrations.AddAuth0RefreshTokenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :auth0_refresh_token, :text
    end
  end
end
