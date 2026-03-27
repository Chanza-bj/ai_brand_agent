defmodule AiBrandAgent.Social.LinkedInClientTest do
  use ExUnit.Case, async: true

  alias AiBrandAgent.Social.LinkedInClient

  describe "module interface" do
    test "create_post/3 is a 3-arity function" do
      assert is_function(&LinkedInClient.create_post/3, 3)
    end

    test "get_profile/1 is a 1-arity function" do
      assert is_function(&LinkedInClient.get_profile/1, 1)
    end
  end
end
