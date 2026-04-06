defmodule AiBrandAgent.Agents.MultiPostGenerator do
  @moduledoc """
  Generates three style variants per topic/platform, ranks them, discards losers,
  then leaves the **winning draft** for the user. A **draft-ready** Gmail notification is
  always attempted (`DraftReadyEmail`) so they can open the app to approve, Smart Schedule, or publish.
  """

  require Logger

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.Agents.CandidateRanker
  alias AiBrandAgent.Agents.ContentAgent
  alias AiBrandAgent.Agents.EngagementInsights
  alias AiBrandAgent.Notifications.DraftReadyEmail
  alias AiBrandAgent.Services.ContentService

  @variants [
    {:story, 1},
    {:insight, 2},
    {:punchy, 3}
  ]

  @doc """
  Returns `{:ok, :skipped}` if the user has no connection for `platform`,
  `{:ok, %Post{}}` for the surviving draft (winner), or `{:error, reason}`.
  """
  def run(topic, user_id, platform) when platform in ["linkedin", "facebook"] do
    unless Accounts.has_publishing_connection?(user_id, platform) do
      Logger.info("MultiPostGenerator: skip user=#{user_id} platform=#{platform} (not connected)")
      {:ok, :skipped}
    else
      do_run(topic, user_id, platform)
    end
  end

  defp do_run(topic, user_id, platform) do
    brand_context = Accounts.brand_promotion_context_for_llm(user_id)
    hints = EngagementInsights.performance_hints_for_prompt(user_id, platform)

    {:ok, run} = Accounts.create_generation_run(user_id, topic.id)

    results =
      Enum.map(@variants, fn {variant, idx} ->
        opts = [
          generation_run_id: run.id,
          variant_index: idx,
          style_tag: Atom.to_string(variant),
          variant: variant,
          brand_context: brand_context,
          performance_hints: hints
        ]

        ContentAgent.generate(topic, user_id, platform, opts)
      end)

    if Enum.any?(results, &match?({:error, :rate_limited}, &1)) do
      {:error, :rate_limited}
    else
      do_rank_and_finish(topic, user_id, platform, results, hints)
    end
  end

  defp do_rank_and_finish(topic, user_id, platform, results, hints) do
    posts =
      Enum.flat_map(results, fn
        {:ok, post} -> [post]
        {:error, _} -> []
      end)

    case posts do
      [] ->
        {:error, :no_variants_generated}

      [_ | _] ->
        case CandidateRanker.pick_best(topic, platform, posts, hints) do
          {:ok, winner} ->
            discard_losers(posts, winner)
            automate_winner(winner, user_id)
        end
    end
  end

  defp discard_losers(posts, winner) do
    for p <- posts, p.id != winner.id do
      ContentService.discard_post(p)
    end

    :ok
  end

  defp automate_winner(winner, _user_id) do
    winner = ContentService.get_post(winner.id) || winner

    case DraftReadyEmail.send_for_post(winner) do
      {:ok, :sent} ->
        {:ok, winner}

      {:ok, :already_sent} ->
        {:ok, winner}

      {:ok, :skipped} ->
        {:ok, winner}

      {:error, reason} ->
        Logger.warning(
          "MultiPostGenerator: draft ready notification failed post=#{winner.id} reason=#{inspect(reason)}"
        )

        {:ok, winner}
    end
  end
end
