defmodule AiBrandAgent.Accounts.UserPostingPreference do
  @moduledoc """
  Per-user schedule and autonomy flags for the posting agent.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_posting_preferences" do
    field :timezone, :string, default: "Etc/UTC"
    field :posting_weekdays, {:array, :integer}, default: [1, 2, 3, 4, 5]
    field :default_post_time, :string, default: "09:00"
    field :auto_approve, :boolean, default: true
    field :auto_post, :boolean, default: true
    field :max_posts_per_day, :integer, default: 3
    field :agent_calendar_recurring_event_id, :string

    belongs_to :user, AiBrandAgent.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(pref, attrs) do
    pref
    |> cast(attrs, [
      :timezone,
      :posting_weekdays,
      :default_post_time,
      :auto_approve,
      :auto_post,
      :max_posts_per_day,
      :agent_calendar_recurring_event_id,
      :user_id
    ])
    |> validate_required([:timezone, :posting_weekdays, :default_post_time])
    |> validate_length(:posting_weekdays, min: 1)
    |> validate_change(:posting_weekdays, &validate_weekdays/2)
    |> validate_change(:timezone, &validate_timezone/2)
    |> validate_number(:max_posts_per_day, greater_than: 0, less_than: 50)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_weekdays(:posting_weekdays, days) do
    if is_list(days) and Enum.all?(days, &(&1 >= 1 and &1 <= 7)) do
      []
    else
      [posting_weekdays: "must be weekdays 1 (Mon) through 7 (Sun)"]
    end
  end

  defp validate_timezone(:timezone, tz) when is_binary(tz) do
    if AiBrandAgent.Calendar.LocalScheduling.valid_timezone?(tz) do
      []
    else
      [timezone: "use a valid IANA name, e.g. America/Chicago or Europe/London"]
    end
  end

  defp validate_timezone(_, _), do: [timezone: "invalid"]
end
