defmodule AiBrandAgent.Services.PublishingServiceTest do
  use AiBrandAgent.DataCase, async: true

  alias AiBrandAgent.Services.PublishingService
  import AiBrandAgent.Fixtures

  describe "get_publishable_post/1" do
    test "returns approved post" do
      user = user_fixture()
      post = post_fixture(user, %{status: "approved"})

      assert {:ok, found} = PublishingService.get_publishable_post(post.id)
      assert found.id == post.id
    end

    test "rejects draft post" do
      user = user_fixture()
      post = post_fixture(user, %{status: "draft"})

      assert {:error, {:not_publishable, "draft"}} =
               PublishingService.get_publishable_post(post.id)
    end

    test "returns not_found for unknown ID" do
      assert {:error, :not_found} =
               PublishingService.get_publishable_post(Ecto.UUID.generate())
    end
  end

  describe "mark_publishing/1" do
    test "transitions to publishing" do
      user = user_fixture()
      post = post_fixture(user, %{status: "approved"})

      assert {:ok, updated} = PublishingService.mark_publishing(post)
      assert updated.status == "publishing"
    end
  end

  describe "record_success/2" do
    test "marks post as published with platform ID" do
      user = user_fixture()
      post = post_fixture(user, %{status: "publishing"})

      assert {:ok, updated} = PublishingService.record_success(post, %{id: "platform_123"})
      assert updated.status == "published"
      assert updated.platform_post_id == "platform_123"
      assert updated.published_at != nil
    end

    test "marks post as published without platform ID" do
      user = user_fixture()
      post = post_fixture(user, %{status: "publishing"})

      assert {:ok, updated} = PublishingService.record_success(post, %{})
      assert updated.status == "published"
      assert updated.published_at != nil
    end
  end

  describe "record_failure/2" do
    test "marks post as failed with error message" do
      user = user_fixture()
      post = post_fixture(user, %{status: "publishing"})

      assert {:ok, updated} = PublishingService.record_failure(post, "Connection timeout")
      assert updated.status == "failed"
      assert updated.error_message == "Connection timeout"
    end

    test "accepts post ID as string" do
      user = user_fixture()
      post = post_fixture(user, %{status: "publishing"})

      assert {:ok, updated} = PublishingService.record_failure(post.id, :rate_limited)
      assert updated.status == "failed"
      assert updated.error_message =~ "rate_limited"
    end

    test "returns not_found for unknown post ID" do
      assert {:error, :not_found} =
               PublishingService.record_failure(Ecto.UUID.generate(), "error")
    end

    test "stores human-readable message for no_identity_token" do
      user = user_fixture()
      post = post_fixture(user, %{status: "publishing"})

      assert {:ok, updated} =
               PublishingService.record_failure(post, {:no_identity_token, "linkedin"})

      assert updated.error_message =~ "LinkedIn is not linked in Auth0"
      assert updated.error_message =~ "Connections"
    end

    test "stores human-readable message for not_publishable failed" do
      user = user_fixture()
      post = post_fixture(user, %{status: "publishing"})

      assert {:ok, updated} =
               PublishingService.record_failure(post, {:not_publishable, "failed"})

      assert updated.error_message =~ "Retry"
    end
  end

  describe "user_facing_error/1" do
    test "token vault federated refresh" do
      msg =
        PublishingService.user_facing_error(
          {:token_vault_error, 401, %{"error" => "federated_connection_refresh_token_not_found"}}
        )

      assert msg =~ "federated refresh token"
    end

    test "LinkedIn 403 ugcPosts NO_VERSION includes reconnect hint" do
      msg =
        PublishingService.user_facing_error(
          {:linkedin_error, 403,
           %{
             "message" => "Not enough permissions to access: ugcPosts.CREATE.NO_VERSION"
           }}
        )

      assert msg =~ "LinkedIn API error (403)"
      assert msg =~ "w_member_social"
      assert msg =~ "reconnect"
    end
  end
end
