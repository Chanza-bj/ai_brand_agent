defmodule AiBrandAgent.Config.EnvTest do
  use ExUnit.Case, async: true

  alias AiBrandAgent.Config.Env

  describe "get/1" do
    test "prefers brand_* over generic name" do
      System.put_env("PORT", "1111")
      System.put_env("brand_PORT", "2222")

      on_exit(fn ->
        System.delete_env("PORT")
        System.delete_env("brand_PORT")
      end)

      assert Env.get("PORT") == "2222"
    end

    test "falls back to generic when brand unset" do
      System.put_env("PORT", "3333")

      on_exit(fn ->
        System.delete_env("PORT")
      end)

      assert Env.get("PORT") == "3333"
    end

    test "BRAND_* over generic when brand_* unset" do
      System.put_env("PORT", "1")
      System.put_env("BRAND_PORT", "2")

      on_exit(fn ->
        System.delete_env("PORT")
        System.delete_env("BRAND_PORT")
      end)

      assert Env.get("PORT") == "2"
    end
  end
end
