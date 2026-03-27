defmodule AiBrandAgent.Agents.EngagementInsights do
  @moduledoc """
  Derives short text hints from `post_metrics` for prompts and the candidate ranker.

  Pure reads; no caching in v1.
  """

  import Ecto.Query

  alias AiBrandAgent.Repo
  alias AiBrandAgent.Accounts.Post
  alias AiBrandAgent.Accounts.PostMetric

  @doc """
  Returns a compact paragraph for the LLM (may be empty if no data).
  """
  def performance_hints_for_prompt(user_id, platform)
      when is_binary(user_id) and platform in ["linkedin", "facebook"] do
    case aggregate_by_style(user_id, platform) do
      [] ->
        ""

      rows ->
        lines =
          Enum.map(rows, fn %{style_tag: tag, avg_eng: avg, n: n} ->
            "- #{tag || "unknown"}: avg engagement score #{Float.round(avg, 2)} (#{n} posts)"
          end)

        """
        Historical relative performance on #{platform} (likes+comments+impressions per snapshot, rough average):
        #{Enum.join(lines, "\n")}
        """
        |> String.trim()
    end
  end

  def performance_hints_for_prompt(_, _), do: ""

  defp aggregate_by_style(user_id, platform) do
    from(p in Post,
      join: m in PostMetric,
      on: m.post_id == p.id,
      where: p.user_id == ^user_id,
      where: p.platform == ^platform,
      where: p.status == "published",
      where: not is_nil(p.style_tag),
      select: {p.id, p.style_tag, m.likes, m.comments, m.impressions}
    )
    |> Repo.all()
    |> Enum.uniq_by(fn {id, _, _, _, _} -> id end)
    |> Enum.group_by(fn {_, tag, _, _, _} -> tag end)
    |> Enum.map(fn {tag, rows} ->
      n = length(rows)

      sum_eng =
        Enum.reduce(rows, 0, fn {_, _, l, c, im}, acc ->
          acc + (l || 0) + (c || 0) + (im || 0)
        end)

      avg = if n > 0, do: sum_eng / n, else: 0.0
      %{style_tag: tag, n: n, avg_eng: avg}
    end)
    |> Enum.sort_by(& &1.avg_eng, :desc)
  end
end
