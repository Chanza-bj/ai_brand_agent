defmodule AiBrandAgent.Trends.LlmFetcher do
  @moduledoc """
  Uses Gemini to propose 1–2 short topic titles per niche seed.

  Placeholder for real trend APIs (News, RSS, Google Trends); swap via `:trend_fetcher` config.
  """

  @behaviour AiBrandAgent.Trends.Fetcher

  require Logger

  alias AiBrandAgent.AI.LLMClient

  @max_seeds_per_run 3

  @impl true
  def fetch_for_user(%{id: user_id}, seeds) when is_list(seeds) do
    rows =
      seeds
      |> Enum.take(@max_seeds_per_run)
      |> Enum.with_index()
      |> Enum.reduce([], fn {seed, idx}, acc ->
        if idx > 0, do: Process.sleep(2_000)

        case titles_for_seed(seed) do
          {:ok, titles} ->
            new_rows =
              for title <- titles do
                %{
                  title: title,
                  user_id: user_id,
                  user_topic_seed_id: seed.id,
                  source: "llm_suggested",
                  metadata: %{
                    related_seed: seed.phrase,
                    source: "llm_suggested"
                  }
                }
              end

            acc ++ new_rows

          {:error, reason} ->
            Logger.warning("LlmFetcher: seed #{seed.id} failed: #{inspect(reason)}")
            acc
        end
      end)

    {:ok, rows}
  end

  defp titles_for_seed(seed) do
    prompt = """
    Return a JSON array of exactly 2 strings. Each string must be a short, specific social media POST TOPIC title (a headline idea, not the post body) for someone building authority in this niche: #{inspect(seed.phrase)}.

    Rules: titles must be distinct; max 120 characters each; no hashtags; no numbering inside strings.
    Output ONLY valid JSON, for example: ["First idea", "Second idea"]
    """

    with {:ok, text} <- LLMClient.complete(prompt),
         {:ok, titles} <- parse_titles(text) do
      {:ok, titles}
    end
  end

  defp parse_titles(text) when is_binary(text) do
    trimmed =
      text
      |> String.replace(~r/^```(?:json)?\s*/m, "")
      |> String.replace(~r/\s*```$/m, "")
      |> String.trim()

    case Jason.decode(trimmed) do
      {:ok, list} when is_list(list) ->
        titles =
          list
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()
          |> Enum.take(2)

        if titles == [], do: {:error, :empty_titles}, else: {:ok, titles}

      {:error, _} ->
        # Fallback: non-JSON lines
        lines =
          trimmed
          |> String.split(~r/\R+/)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.reject(&String.starts_with?(&1, "["))
          |> Enum.reject(&String.starts_with?(&1, "]"))
          |> Enum.map(fn line -> String.replace(line, ~r/^[\d\.\)\-\s]+/, "") end)
          |> Enum.take(2)

        if lines == [], do: {:error, :parse}, else: {:ok, lines}
    end
  end
end
