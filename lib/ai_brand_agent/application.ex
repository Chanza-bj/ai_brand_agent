defmodule AiBrandAgent.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AiBrandAgentWeb.Telemetry,
      AiBrandAgent.Repo,
      {DNSCluster, query: Application.get_env(:ai_brand_agent, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AiBrandAgent.PubSub},
      {Oban, Application.fetch_env!(:ai_brand_agent, Oban)},
      AiBrandAgent.AgentSupervisor,
      AiBrandAgentWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: AiBrandAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AiBrandAgentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
