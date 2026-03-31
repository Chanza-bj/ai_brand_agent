defmodule AiBrandAgentWeb.ErrorMessage do
  @moduledoc "User-safe flash/copy (no `inspect/1` of internal terms)."

  @doc "Generic failure for LiveView flashes."
  def generic, do: "Something went wrong. Please try again."

  @doc "Post not found or access denied (avoid confirming existence)."
  def post_not_found, do: "Post not found or you don't have access."

  @doc "Maps common internal reasons to short user text."
  def post_action(:not_found), do: post_not_found()

  def post_action({:invalid_transition, _from, _to}),
    do: "This action isn't allowed for this post right now."

  def post_action({:invalid_status, _status}),
    do: "This action isn't allowed for this post right now."

  def post_action({:not_editable, _status}), do: "This post can't be edited."
  def post_action(:daily_cap), do: "Daily publishing limit reached for today."
  def post_action(:no_slot), do: "No available time slot. Adjust your schedule in Agent settings."
  def post_action(_), do: generic()

  def login_failed, do: "Sign-in failed. Please try again or contact support if it continues."
end
