defmodule AiBrandAgentWeb.Plugs.OptionalAuth do
  @moduledoc """
  Assigns `current_user` when a valid session exists, without redirecting guests.

  Use on public routes (e.g. marketing home) so layouts can show signed-in nav and CTAs.
  """

  import Plug.Conn

  alias AiBrandAgent.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    cookie_token = get_session(conn, :session_token)

    cond do
      user_id == nil ->
        assign(conn, :current_user, nil)

      user = Accounts.get_user(user_id) ->
        cond do
          Accounts.session_valid?(user, cookie_token) ->
            assign(conn, :current_user, user)

          Accounts.legacy_bootstrap?(user, cookie_token) ->
            assign(conn, :current_user, user)

          true ->
            assign(conn, :current_user, nil)
        end

      true ->
        assign(conn, :current_user, nil)
    end
  end
end
