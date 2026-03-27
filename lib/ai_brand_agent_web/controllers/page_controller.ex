defmodule AiBrandAgentWeb.PageController do
  use AiBrandAgentWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      page_title: "Brand Agent: Personal brand on autopilot",
      meta_description:
        "Define your niches and keywords, get topic ideas and on-brand drafts for LinkedIn and Facebook, optionally highlight your product or service, and publish with OAuth secured in Auth0 Token Vault.",
      canonical_url: url(conn, ~p"/")
    )
  end
end
