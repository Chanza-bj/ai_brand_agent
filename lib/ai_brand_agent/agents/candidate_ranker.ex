defmodule AiBrandAgent.Agents.CandidateRanker do
  @moduledoc """
  Picks the single best draft among three variants using an LLM judge.
  """

  require Logger

  alias AiBrandAgent.AI.LLMClient
  alias AiBrandAgent.Accounts.Post

  @doc """
  Given 2–3 published draft posts for the same topic/platform run, returns the winning post.

  On LLM failure, returns the first candidate.
  """
  def pick_best(topic, platform, posts, performance_hints \\ "")
      when is_list(posts) and length(posts) >= 1 do
    posts = Enum.reject(posts, &is_nil/1)

    case posts do
      [one] ->
        {:ok, one}

      many ->
        prompt = judge_prompt(topic, platform, many, performance_hints)

        case LLMClient.complete(prompt) do
          {:ok, raw} ->
            case parse_winner_index(raw, length(many)) do
              {:ok, idx} ->
                winner = Enum.at(many, idx - 1) || hd(many)
                {:ok, winner}

              _ ->
                Logger.warning("CandidateRanker: parse failed, defaulting to first variant")
                {:ok, hd(many)}
            end

          {:error, reason} ->
            Logger.warning(
              "CandidateRanker: LLM error #{inspect(reason)}, defaulting to first variant"
            )

            {:ok, hd(many)}
        end
    end
  end

  defp judge_prompt(topic, platform, posts, hints) do
    blocks =
      posts
      |> Enum.with_index(1)
      |> Enum.map(fn {%Post{} = p, i} ->
        label = p.style_tag || "variant_#{i}"

        """
        ### Candidate #{i} (#{label})
        #{p.content}
        """
      end)
      |> Enum.join("\n")

    hints_block =
      if hints in [nil, ""], do: "", else: "\nContext from past performance:\n#{hints}\n"

    """
    You are an expert #{platform} editor. Pick exactly ONE winning post for this topic.

    Topic: #{topic.title}
    #{if topic.metadata, do: "Metadata: #{inspect(topic.metadata)}", else: ""}
    #{hints_block}

    #{blocks}

    Rules:
    - Prefer clarity, specificity, and authentic voice over generic advice.
    - Choose the single candidate that would perform best for the author's audience.

    Reply with ONLY a JSON object, no markdown fences, in this exact form:
    {"winner": <number>}
    where <number> is 1, 2, or 3 matching the candidate index above.
    """
  end

  defp parse_winner_index(raw, max_n) when is_binary(raw) do
    cleaned =
      raw
      |> String.trim()
      |> String.replace_prefix("```json", "")
      |> String.replace_prefix("```", "")
      |> String.replace_suffix("```", "")
      |> String.trim()

    with {:ok, map} <- Jason.decode(cleaned),
         n when is_integer(n) <- Map.get(map, "winner") |> to_int(),
         true <- n >= 1 and n <= max_n do
      {:ok, n}
    else
      _ -> :error
    end
  end

  defp parse_winner_index(_, _), do: :error

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp to_int(_), do: nil
end
