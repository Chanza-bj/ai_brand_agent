defmodule AiBrandAgentWeb.PageControllerTest do
  use AiBrandAgentWeb.ConnCase

  import AiBrandAgent.Fixtures

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Brand Agent"
    assert html_response(conn, 200) =~ "keyword"
  end

  test "GET / redirects to dashboard when logged in", %{conn: conn} do
    user = user_fixture()
    conn = conn |> log_in_user(user) |> get(~p"/")
    assert redirected_to(conn) == "/dashboard"
  end
end
