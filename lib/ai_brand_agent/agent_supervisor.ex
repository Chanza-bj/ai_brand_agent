defmodule AiBrandAgent.AgentSupervisor do
  @moduledoc """
  Supervises the three core AI agents.

  Uses `:one_for_one` strategy — each agent is independent and can
  restart without affecting siblings.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      AiBrandAgent.Agents.TrendAgent,
      AiBrandAgent.Agents.ContentAgent,
      AiBrandAgent.Agents.PostAgent,
      AiBrandAgent.Agents.CalendarAgent
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
