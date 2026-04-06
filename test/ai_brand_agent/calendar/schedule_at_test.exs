defmodule AiBrandAgent.Calendar.ScheduleAtTest do
  use ExUnit.Case, async: true

  alias AiBrandAgent.Calendar.ScheduleAt

  describe "parse_to_utc/2" do
    test "interprets datetime-local as wall time in Etc/UTC" do
      assert {:ok, utc} = ScheduleAt.parse_to_utc("2030-06-15T14:30", "Etc/UTC")
      assert utc.time_zone == "Etc/UTC"
      assert utc.hour == 14
      assert utc.minute == 30
    end

    test "converts wall time using IANA timezone" do
      assert {:ok, utc} = ScheduleAt.parse_to_utc("2030-06-15T14:30", "America/New_York")
      assert utc.time_zone == "Etc/UTC"
      # June: EDT (UTC-4); 14:30 local → 18:30 UTC
      assert utc.hour == 18
      assert utc.minute == 30
    end

    test "appends seconds when input has minute precision only" do
      assert {:ok, _} = ScheduleAt.parse_to_utc("2030-06-15T14:30", "Etc/UTC")
    end

    test "returns error for invalid datetime string" do
      assert {:error, :invalid_datetime} = ScheduleAt.parse_to_utc("not-a-date", "Etc/UTC")
    end
  end
end
