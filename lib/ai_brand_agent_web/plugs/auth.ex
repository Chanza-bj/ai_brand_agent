defmodule AiBrandAgentWeb.Plugs.Auth do
  @moduledoc """
  Authentication plug that loads the current user from the session.

  Assigns `current_user` from the session's `:user_id`. If no user is
  found, redirects to the login page (for browser pipelines) or returns
  401 (for API pipelines).
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  alias AiBrandAgent.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    cookie_token = get_session(conn, :session_token)

    cond do
      user_id == nil ->
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> redirect(to: "/auth/auth0")
        |> halt()

      user = Accounts.get_user(user_id) ->
        cond do
          Accounts.session_valid?(user, cookie_token) ->
            assign(conn, :current_user, user)

          Accounts.legacy_bootstrap?(user, cookie_token) ->
            token = Accounts.assign_new_session_token!(user)
            user = Accounts.get_user(user.id)

            conn
            |> put_session(:session_token, token)
            |> assign(:current_user, user)

          true ->
            conn
            |> clear_session()
            |> put_flash(:error, "Your session was logged out (signed in elsewhere).")
            |> redirect(to: "/auth/auth0")
            |> halt()
        end

      true ->
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> redirect(to: "/auth/auth0")
        |> halt()
    end
  end

  @doc "Assign current_user to LiveView socket from session."
  def on_mount(:require_auth, _params, session, socket) do
    user_id = Map.get(session, "user_id")
    cookie_token = Map.get(session, "session_token")

    case user_id && Accounts.get_user(user_id) do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/auth/auth0")}

      user ->
        cond do
          Accounts.session_valid?(user, cookie_token) ->
            {:cont, Phoenix.Component.assign(socket, :current_user, user)}

          Accounts.legacy_bootstrap?(user, cookie_token) ->
            {:cont, Phoenix.Component.assign(socket, :current_user, user)}

          true ->
            {:halt, Phoenix.LiveView.redirect(socket, to: "/auth/auth0")}
        end
    end
  end
end
