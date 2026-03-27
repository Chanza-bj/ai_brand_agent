defmodule AiBrandAgent.Social.FacebookClientTest do
  use ExUnit.Case, async: true

  alias AiBrandAgent.Social.FacebookClient

  describe "public_post_url/1" do
    test "builds facebook.com URL from Graph composite id" do
      assert FacebookClient.public_post_url("116021456922514_963455189694903") ==
               "https://www.facebook.com/116021456922514/posts/963455189694903"
    end

    test "returns nil for invalid id" do
      assert FacebookClient.public_post_url("nounderscore") == nil
    end
  end

  describe "module interface" do
    test "create_post/3 is a 3-arity function" do
      assert is_function(&FacebookClient.create_post/3, 3)
    end

    test "get_profile/1 is a 1-arity function" do
      assert is_function(&FacebookClient.get_profile/1, 1)
    end
  end
end
