defmodule AiBrandAgentWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AiBrandAgentWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  import Plug.Conn
  import Plug.Test, only: [init_test_session: 2]

  using do
    quote do
      # The default endpoint for testing
      @endpoint AiBrandAgentWeb.Endpoint

      use AiBrandAgentWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import AiBrandAgentWeb.ConnCase
    end
  end

  @doc """
  Puts `user_id` and `session_token` in the test session so `AiBrandAgentWeb.Plugs.Auth` accepts the conn.
  """
  def log_in_user(conn, user) do
    token = AiBrandAgent.Accounts.assign_new_session_token!(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_id, user.id)
    |> put_session(:session_token, token)
  end

  setup tags do
    AiBrandAgent.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
