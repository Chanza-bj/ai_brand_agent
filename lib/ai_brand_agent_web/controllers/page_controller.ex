defmodule AiBrandAgentWeb.PageController do
  use AiBrandAgentWeb, :controller

  def home(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        render(conn, :home,
          page_title: "Athena: Personal brand on autopilot",
          meta_description:
            "Define your niches and keywords, get topic ideas and on-brand drafts for LinkedIn and Facebook, optionally highlight your product or service, and publish with OAuth secured in Auth0 Token Vault.",
          canonical_url: url(conn, ~p"/")
        )

      _user ->
        redirect(conn, to: ~p"/dashboard")
    end
  end
end
