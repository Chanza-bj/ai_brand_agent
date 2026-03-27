defmodule AiBrandAgent.Repo.Migrations.AddAgentCalendarRecurringEventId do
  use Ecto.Migration

  def change do
    alter table(:user_posting_preferences) do
      add :agent_calendar_recurring_event_id, :string
    end
  end
end
