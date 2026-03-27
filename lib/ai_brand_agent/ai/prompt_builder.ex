defmodule AiBrandAgent.AI.PromptBuilder do
  @moduledoc """
  Builds structured prompts for the Gemini LLM based on intent and context.

  Each public function returns a plain string prompt ready for `LLMClient.complete/1`.
  """

  @doc """
  Build a prompt for the given intent.

  ## Supported intents

    * `:post_from_topic` — generate a social media post from a trending topic.
      Requires `%{topic: %Topic{}, platform: "linkedin" | "facebook"}`.
      Optional `brand_context: nil | map` — when present, the model weaves in the user's
      product or service authentically (see `Accounts.brand_promotion_context_for_llm/1`).
      Optional `variant: :story | :insight | :punchy` — changes the creative angle.
      Optional `performance_hints: binary` — short text from past engagement (may be empty).

    * `:post_from_event` — generate a social media post inspired by a calendar event.
      Requires `%{event: map, platform: binary}`. Event has `"summary"`, `"description"`, and start/end times.

    * `:refine` — rewrite an existing draft with feedback.
      Requires `%{content: binary, feedback: binary, platform: binary}`.
  """
  def build(:post_from_topic, %{topic: topic, platform: platform} = params) do
    platform_guidance = platform_guidance(platform)
    brand_block = brand_context_block(Map.get(params, :brand_context))
    variant_block = variant_angle_block(Map.get(params, :variant))
    hints_block = performance_hints_block(Map.get(params, :performance_hints))

    """
    You are a professional social media strategist.

    Write a compelling #{platform} post about the following trending topic.

    Topic: #{topic.title}
    #{if topic.metadata, do: "Context: #{inspect(topic.metadata)}", else: ""}
    #{brand_block}
    #{variant_block}
    #{hints_block}

    Requirements:
    #{platform_guidance}
    - Write in first person as a thought leader
    - Be authentic and insightful, not generic
    - Include a clear call to action#{brand_cta_note(brand_block)}
    - Do NOT include hashtags unless they are highly relevant
    #{punctuation_no_em_dash()}
    - Return ONLY the post text, no preamble or explanation
    """
  end

  def build(:post_from_event, %{event: event, platform: platform}) do
    summary = Map.get(event, "summary", "Upcoming event")
    description = Map.get(event, "description", "")
    start_time = get_in(event, ["start", "dateTime"]) || ""
    platform_guidance = platform_guidance(platform)

    """
    You are a professional social media strategist.

    Write a compelling #{platform} post inspired by the following upcoming calendar event.
    The post should position the author as actively engaged and forward-thinking.

    Event: #{summary}
    #{if description != "", do: "Details: #{description}", else: ""}
    #{if start_time != "", do: "When: #{start_time}", else: ""}

    Requirements:
    #{platform_guidance}
    - Reference the event naturally without sounding like a calendar notification
    - Show excitement or thought leadership around the event topic
    - Include a clear call to action (e.g., "Join me", "What are your thoughts?")
    #{punctuation_no_em_dash()}
    - Return ONLY the post text, no preamble or explanation
    """
  end

  def build(:refine, %{content: content, feedback: feedback, platform: platform}) do
    """
    You are a professional social media editor.

    Rewrite the following #{platform} post incorporating the feedback below.

    Original post:
    #{content}

    Feedback:
    #{feedback}

    Requirements:
    #{platform_guidance(platform)}
    - Maintain the original voice and intent
    #{punctuation_no_em_dash()}
    - Return ONLY the revised post text
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp platform_guidance("linkedin") do
    """
    - Professional tone suitable for LinkedIn
    - Optimal length: about 150 to 300 words
    - Use line breaks for readability
    - May include one or two relevant emojis sparingly
    """
  end

  defp platform_guidance("facebook") do
    """
    - Conversational yet professional tone for Facebook
    - Optimal length: about 80 to 200 words
    - Engaging opening line to capture attention in the feed
    - May include emojis naturally
    """
  end

  defp platform_guidance(_), do: "- General social media best practices\n"

  defp punctuation_no_em_dash do
    "- Do not use em dashes; use commas or periods between clauses instead"
  end

  defp brand_context_block(nil), do: ""

  defp brand_context_block(%{} = ctx) do
    lines =
      [
        line_if(ctx, :product_or_service_name, "Product or service"),
        line_if(ctx, :pitch, "Value proposition / pitch"),
        line_if(ctx, :call_to_action, "Preferred call to action"),
        line_if(ctx, :link_url, "Link (include only if it fits naturally)")
      ]
      |> Enum.reject(&(&1 == ""))

    if lines == [] do
      ""
    else
      """

      Promotion context (use naturally, not as a hard sales pitch):
      #{Enum.join(lines, "\n")}

      How to integrate the offer:
      - Tie it to the topic angle: show how your product or service helps with the theme above.
      - Avoid spammy tone, unrelated product dumps, or fake enthusiasm.
      - If the topic and offer align weakly, prioritize insight on the topic and mention the offer briefly (e.g. closing line or soft aside).
      """
    end
  end

  defp line_if(ctx, key, label) do
    case Map.get(ctx, key) do
      s when is_binary(s) and s != "" -> "- #{label}: #{s}"
      _ -> ""
    end
  end

  defp brand_cta_note(""), do: ""

  defp brand_cta_note(_),
    do: " (you may use the author's preferred CTA from promotion context when appropriate)"

  defp variant_angle_block(nil), do: ""

  defp variant_angle_block(:story) do
    """

    Creative angle: STORY — lead with a short personal anecdote or narrative that lands the insight.
    """
  end

  defp variant_angle_block(:insight) do
    """

    Creative angle: INSIGHT — lead with a sharp observation, framework, or lesson; minimal backstory.
    """
  end

  defp variant_angle_block(:punchy) do
    """

    Creative angle: PUNCHY — short paragraphs, strong hook in the first line, high skimmability.
    """
  end

  defp variant_angle_block(_), do: ""

  defp performance_hints_block(nil), do: ""

  defp performance_hints_block(s) when is_binary(s) and s != "",
    do:
      "\n\nPast performance hints for this platform (use lightly, do not copy old posts):\n#{s}\n"

  defp performance_hints_block(_), do: ""
end
