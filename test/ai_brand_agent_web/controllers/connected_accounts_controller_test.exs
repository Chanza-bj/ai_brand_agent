defmodule AiBrandAgentWeb.ConnectedAccountsControllerTest do
  use AiBrandAgentWeb.ConnCase, async: true

  describe "GET /auth/connected-accounts/start" do
    test "redirects to Auth0 login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/auth/connected-accounts/start")

      assert redirected_to(conn) == "/auth/auth0"
    end
  end
end
