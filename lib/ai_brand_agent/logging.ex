defmodule AiBrandAgent.Logging do
  @moduledoc """
  Sanitizes third-party HTTP/API payloads for logs so production does not retain
  full error bodies (tokens, PII, internal structure).
  """

  @doc """
  Returns a short summary safe for logs in production; full `inspect/1` in dev/test.
  """
  def safe_http_body(body) do
    if redact_api_bodies?() do
      summarize_body(body)
    else
      inspect(body)
    end
  end

  defp redact_api_bodies? do
    Application.get_env(:ai_brand_agent, :redact_third_party_logs, true) == true and
      Application.get_env(:ai_brand_agent, :env) == :prod
  end

  defp summarize_body(body) when is_map(body) do
    "map(#{map_size(body)} keys)"
  end

  defp summarize_body(body) when is_list(body) do
    "list(#{length(body)} items)"
  end

  defp summarize_body(body) when is_binary(body) do
    "binary(#{byte_size(body)} bytes)"
  end

  defp summarize_body(nil), do: "nil"
  defp summarize_body(_), do: "[redacted]"
end
