defmodule AiBrandAgent.Auth.Auth0ClientTest do
  use ExUnit.Case, async: true

  alias AiBrandAgent.Auth.Auth0Client

  describe "find_identity_for_connection/2" do
    test "matches linkedin when Auth0 uses linkedin-oauth2 connection name" do
      identities = [
        %{
          "connection" => "linkedin-oauth2",
          "provider" => "linkedin-oauth2",
          "access_token" => "tok"
        }
      ]

      assert %{"access_token" => "tok"} =
               Auth0Client.find_identity_for_connection(identities, "linkedin")
    end

    test "matches exact stored auth0_connection_id" do
      identities = [
        %{"connection" => "linkedin-oauth2", "access_token" => "x"}
      ]

      assert %{"access_token" => "x"} =
               Auth0Client.find_identity_for_connection(identities, "linkedin-oauth2")
    end

    test "returns nil when no identity matches" do
      identities = [%{"connection" => "twitter", "provider" => "twitter"}]

      assert Auth0Client.find_identity_for_connection(identities, "linkedin") == nil
    end
  end

  describe "authorize_url/3" do
    test "includes connection_scope when provided (Facebook Page permissions)" do
      url =
        Auth0Client.authorize_url("https://app.test/callback", "xyz123",
          connection: "facebook",
          connection_scope: "pages_show_list,pages_manage_posts"
        )

      assert url =~ "connection=facebook"
      assert url =~ "connection_scope="
      assert url =~ "pages_show_list"
      assert url =~ "pages_manage_posts"
    end

    test "includes prompt when provided" do
      url =
        Auth0Client.authorize_url("https://app.test/callback", "xyz123",
          connection: "facebook",
          connection_scope: "pages_show_list,pages_manage_posts",
          prompt: "consent"
        )

      assert url =~ "prompt=consent"
    end
  end

  describe "link_secondary_identity/2" do
    test "returns noop when primary and secondary are the same" do
      sub = "google-oauth2|108091299999329986433"
      assert {:ok, :noop} = Auth0Client.link_secondary_identity(sub, sub)
    end

    test "returns error when secondary sub has no pipe" do
      primary = "google-oauth2|108091299999329986433"

      assert {:error, :invalid_auth0_user_id_format} =
               Auth0Client.link_secondary_identity(primary, "invalid-sub-without-pipe")
    end
  end
end
