defmodule AiBrandAgent.AI.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias AiBrandAgent.AI.PromptBuilder

  describe "build(:post_from_topic, params)" do
    test "generates a LinkedIn prompt" do
      topic = %{title: "AI in Healthcare", metadata: %{category: "tech"}}
      prompt = PromptBuilder.build(:post_from_topic, %{topic: topic, platform: "linkedin"})

      assert prompt =~ "AI in Healthcare"
      assert prompt =~ "linkedin"
      assert prompt =~ "Professional tone"
      assert prompt =~ "thought leader"
      assert prompt =~ "em dashes"
    end

    test "generates a Facebook prompt" do
      topic = %{title: "Remote Work Trends", metadata: nil}
      prompt = PromptBuilder.build(:post_from_topic, %{topic: topic, platform: "facebook"})

      assert prompt =~ "Remote Work Trends"
      assert prompt =~ "facebook"
      assert prompt =~ "Conversational"
    end

    test "handles topic without metadata" do
      topic = %{title: "Test Topic", metadata: nil}
      prompt = PromptBuilder.build(:post_from_topic, %{topic: topic, platform: "linkedin"})

      assert is_binary(prompt)
      assert prompt =~ "Test Topic"
    end

    test "includes promotion context when brand_context is set" do
      topic = %{title: "Remote Work Trends", metadata: nil}

      brand_context = %{
        product_or_service_name: "TeamFlow",
        pitch: "Async standups that don't waste your morning.",
        call_to_action: "Try the free tier",
        link_url: "https://example.com"
      }

      prompt =
        PromptBuilder.build(:post_from_topic, %{
          topic: topic,
          platform: "linkedin",
          brand_context: brand_context
        })

      assert prompt =~ "Remote Work Trends"
      assert prompt =~ "TeamFlow"
      assert prompt =~ "Promotion context"
      assert prompt =~ "Try the free tier"
    end
  end

  describe "build(:refine, params)" do
    test "generates a refinement prompt" do
      params = %{
        content: "Original post content",
        feedback: "Make it shorter",
        platform: "linkedin"
      }

      prompt = PromptBuilder.build(:refine, params)

      assert prompt =~ "Original post content"
      assert prompt =~ "Make it shorter"
      assert prompt =~ "editor"
    end
  end
end
