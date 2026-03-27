defmodule AiBrandAgent.AI.LLMClient do
  @moduledoc """
  HTTP client for the Google Gemini API.

  Sends structured prompts to the `generateContent` endpoint and returns
  the generated text. Handles rate limiting, transient errors, and
  malformed responses.
  """

  require Logger

  @base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @doc """
  Send a prompt to Gemini and return the generated text.

  Accepts either a plain string or a list of `%{role, parts}` messages.
  Returns `{:ok, text}` or `{:error, reason}`.
  """
  def complete(prompt) when is_binary(prompt) do
    complete([%{role: "user", parts: [%{text: prompt}]}])
  end

  def complete(messages) when is_list(messages) do
    body = %{
      contents: messages,
      generationConfig: %{
        temperature: 0.8,
        maxOutputTokens: 2048
      }
    }

    url = "#{@base_url}/#{model()}:generateContent?key=#{api_key()}"

    do_request(url, body, 0)
  end

  defp do_request(url, body, attempt) do
    max = max_retries()

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: resp_body}} ->
        extract_text(resp_body)

      {:ok, %{status: 429} = resp} ->
        if attempt < max do
          backoff_ms = rate_limit_backoff_ms(resp, attempt)

          Logger.info(
            "Gemini rate limited, retrying in #{div(backoff_ms, 1000)}s (attempt #{attempt + 1}/#{max})"
          )

          Process.sleep(backoff_ms)
          do_request(url, body, attempt + 1)
        else
          {:error, :rate_limited}
        end

      {:ok, %{status: status}} when status in 500..599 ->
        {:error, :service_unavailable}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("Gemini API error #{status}: #{inspect(resp_body)}")
        {:error, {:gemini_error, status}}

      {:error, reason} ->
        Logger.error("Gemini API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp rate_limit_backoff_ms(resp, attempt) when is_map(resp) do
    headers = response_headers(resp)
    body = response_body(resp)

    header_delay_ms =
      case retry_after_seconds(headers) do
        {:ok, secs} ->
          min(secs * 1000, rate_limit_retry_after_cap_ms())

        :none ->
          nil
      end

    body_delay_ms = gemini_retry_delay_ms_from_body(body)

    exponential_ms =
      min(
        initial_backoff_ms() * Integer.pow(2, attempt),
        max_backoff_ms()
      )

    base =
      [header_delay_ms, body_delay_ms, exponential_ms]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> exponential_ms
        parts -> Enum.max(parts)
      end

    jitter = :rand.uniform(max(div(base, 5), 500))
    capped = min(base + jitter, max_backoff_ms())
    max(capped, 1_000)
  end

  defp response_headers(%Req.Response{headers: h}), do: h
  defp response_headers(%{headers: h}), do: h
  defp response_headers(_), do: []

  defp response_body(%Req.Response{body: b}), do: b
  defp response_body(%{body: b}), do: b
  defp response_body(_), do: nil

  @retry_info "type.googleapis.com/google.rpc.RetryInfo"

  defp gemini_retry_delay_ms_from_body(%{"error" => %{"details" => details}})
       when is_list(details) do
    Enum.find_value(details, fn
      %{"@type" => @retry_info, "retryDelay" => d} when is_binary(d) ->
        case Regex.run(~r/^([\d.]+)s$/i, String.trim(d)) do
          [_, num] ->
            ms =
              case Float.parse(num) do
                {f, _} -> round(f * 1000)
                :error -> 0
              end

            min(ms, rate_limit_retry_after_cap_ms())

          _ ->
            nil
        end

      _ ->
        nil
    end)
  end

  defp gemini_retry_delay_ms_from_body(_), do: nil

  defp header_first([h | _]), do: header_first(h)
  defp header_first(h) when is_binary(h), do: h
  defp header_first(_), do: nil

  defp retry_after_seconds(headers) when is_list(headers) do
    raw =
      Enum.find_value(headers, fn
        {k, v} when is_binary(k) and is_binary(v) ->
          if String.downcase(k) == "retry-after", do: String.trim(v), else: nil

        _ ->
          nil
      end)

    case raw do
      nil ->
        :none

      s ->
        case Integer.parse(s) do
          {secs, _} when secs >= 0 -> {:ok, secs}
          _ -> :none
        end
    end
  end

  defp retry_after_seconds(headers) when is_map(headers) do
    raw =
      header_first(Map.get(headers, "retry-after")) ||
        header_first(Map.get(headers, "Retry-After"))

    case raw do
      nil ->
        :none

      s when is_binary(s) ->
        case Integer.parse(String.trim(s)) do
          {secs, _} when secs >= 0 -> {:ok, secs}
          _ -> :none
        end

      _ ->
        :none
    end
  end

  defp retry_after_seconds(_), do: :none

  defp gemini_kw do
    Application.get_env(:ai_brand_agent, :gemini, [])
  end

  defp max_retries, do: Keyword.get(gemini_kw(), :max_retries, 4)

  defp initial_backoff_ms, do: Keyword.get(gemini_kw(), :initial_backoff_ms, 8_000)

  defp max_backoff_ms, do: Keyword.get(gemini_kw(), :max_backoff_ms, 60_000)

  defp rate_limit_retry_after_cap_ms,
    do: Keyword.get(gemini_kw(), :rate_limit_retry_after_cap_ms, 90_000)

  defp extract_text(%{
         "candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]
       }) do
    {:ok, String.trim(text)}
  end

  defp extract_text(body) do
    Logger.error("Unexpected Gemini response shape: #{inspect(body)}")
    {:error, :malformed_response}
  end

  defp api_key do
    Application.fetch_env!(:ai_brand_agent, :gemini) |> Keyword.fetch!(:api_key)
  end

  defp model do
    Application.fetch_env!(:ai_brand_agent, :gemini) |> Keyword.fetch!(:model)
  end
end
