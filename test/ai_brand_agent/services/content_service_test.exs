defmodule AiBrandAgent.Services.ContentServiceTest do
  use AiBrandAgent.DataCase, async: true

  alias AiBrandAgent.Services.ContentService
  import AiBrandAgent.Fixtures

  describe "find_or_create_topic_for_user/2" do
    test "creates a new topic scoped to the user" do
      user = user_fixture()

      assert {:ok, topic} =
               ContentService.find_or_create_topic_for_user(user.id, %{
                 title: "New Topic",
                 source: "test"
               })

      assert topic.title == "New Topic"
      assert topic.user_id == user.id
    end

    test "returns existing topic with same title for same user" do
      user = user_fixture()

      {:ok, original} =
        ContentService.find_or_create_topic_for_user(user.id, %{title: "Existing", source: "test"})

      {:ok, found} =
        ContentService.find_or_create_topic_for_user(user.id, %{
          title: "Existing",
          source: "other"
        })

      assert found.id == original.id
    end

    test "allows same title for a different user" do
      u1 = user_fixture()
      u2 = user_fixture()

      {:ok, t1} = ContentService.find_or_create_topic_for_user(u1.id, %{title: "Same Title"})
      {:ok, t2} = ContentService.find_or_create_topic_for_user(u2.id, %{title: "Same Title"})
      assert t1.id != t2.id
    end

    test "accepts string keys in attrs" do
      user = user_fixture()

      assert {:ok, topic} =
               ContentService.find_or_create_topic_for_user(user.id, %{"title" => "String Keys"})

      assert topic.title == "String Keys"
    end
  end

  describe "create_post/1" do
    test "creates a draft post" do
      user = user_fixture()
      topic = topic_fixture(%{user_id: user.id})

      attrs = %{
        user_id: user.id,
        topic_id: topic.id,
        platform: "linkedin",
        content: "Test content",
        status: "draft"
      }

      assert {:ok, post} = ContentService.create_post(attrs)
      assert post.status == "draft"
      assert post.platform == "linkedin"
    end

    test "rejects invalid platform" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        platform: "tiktok",
        content: "Nope",
        status: "draft"
      }

      assert {:error, changeset} = ContentService.create_post(attrs)
      assert errors_on(changeset).platform != nil
    end
  end

  describe "list_posts/2" do
    test "lists posts for a user" do
      user = user_fixture()
      post_fixture(user)
      post_fixture(user)

      assert length(ContentService.list_posts(user.id)) == 2
    end

    test "filters by status" do
      user = user_fixture()
      post_fixture(user, %{status: "draft"})
      post_fixture(user, %{status: "published"})

      assert length(ContentService.list_posts(user.id, status: "draft")) == 1
    end

    test "does not return other users' posts" do
      user1 = user_fixture()
      user2 = user_fixture()
      post_fixture(user1)

      assert ContentService.list_posts(user2.id) == []
    end
  end

  describe "approve_post/1" do
    test "approves a draft post" do
      user = user_fixture()
      post = post_fixture(user, %{status: "draft"})

      assert {:ok, approved} = ContentService.approve_post(post)
      assert approved.status == "approved"
    end

    test "rejects approval of non-draft post" do
      user = user_fixture()
      post = post_fixture(user, %{status: "published"})

      assert {:error, {:invalid_transition, "published", "approved"}} =
               ContentService.approve_post(post)
    end
  end

  describe "update_post_content/2" do
    test "updates content of a draft post" do
      user = user_fixture()
      post = post_fixture(user, %{status: "draft"})

      assert {:ok, updated} = ContentService.update_post_content(post, "New content")
      assert updated.content == "New content"
    end

    test "rejects editing a published post" do
      user = user_fixture()
      post = post_fixture(user, %{status: "published"})

      assert {:error, {:not_editable, "published"}} =
               ContentService.update_post_content(post, "Nope")
    end
  end

  describe "get_post/2" do
    test "returns nil for unknown ID" do
      assert ContentService.get_post(Ecto.UUID.generate()) == nil
    end

    test "returns post with preloads" do
      user = user_fixture()
      post = post_fixture(user)

      loaded = ContentService.get_post(post.id, [:topic])
      assert loaded.topic != nil
    end
  end

  describe "get_post_for_user/3" do
    test "returns post when it belongs to the user" do
      user = user_fixture()
      post = post_fixture(user)

      loaded = ContentService.get_post_for_user(post.id, user.id, [:topic])
      assert loaded.id == post.id
    end

    test "returns nil when post belongs to another user" do
      u1 = user_fixture()
      u2 = user_fixture()
      post = post_fixture(u1)

      assert ContentService.get_post_for_user(post.id, u2.id) == nil
    end
  end

  describe "list_recent_topics/1" do
    test "returns recent topics" do
      topic_fixture(%{title: "Topic A"})
      topic_fixture(%{title: "Topic B"})

      topics = ContentService.list_recent_topics(10)
      titles = Enum.map(topics, & &1.title)
      assert "Topic A" in titles
      assert "Topic B" in titles
    end
  end

  describe "list_topics_for_user/2" do
    test "returns only that user's topics" do
      u1 = user_fixture()
      u2 = user_fixture()
      topic_fixture(%{user_id: u1.id, title: "Mine"})
      topic_fixture(%{user_id: u2.id, title: "Yours"})

      titles = u1.id |> ContentService.list_topics_for_user(10) |> Enum.map(& &1.title)
      assert "Mine" in titles
      refute "Yours" in titles
    end
  end
end
