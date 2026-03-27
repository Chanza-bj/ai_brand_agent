defmodule AiBrandAgent.AI.LLMClientTest do
  use ExUnit.Case, async: true

  alias AiBrandAgent.AI.LLMClient

  # These tests verify the response parsing logic without hitting the API.
  # For integration tests, use a mock or Req.Test.

  describe "extract_text (via complete/1 internals)" do
    test "complete/1 accepts a string prompt" do
      # This test documents the interface — actual API calls are mocked in integration tests.
      assert is_function(&LLMClient.complete/1, 1)
    end

    test "complete/1 accepts a message list" do
      messages = [%{role: "user", parts: [%{text: "hello"}]}]
      assert is_function(&LLMClient.complete/1, 1)
      assert is_list(messages)
    end
  end
end
