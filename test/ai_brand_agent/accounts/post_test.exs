defmodule AiBrandAgent.Accounts.PostTest do
  use AiBrandAgent.DataCase, async: true

  alias AiBrandAgent.Accounts.Post
  import AiBrandAgent.Fixtures

  describe "changeset/2" do
    test "valid changeset" do
      user = user_fixture()

      changeset =
        Post.changeset(%Post{}, %{
          user_id: user.id,
          platform: "linkedin",
          content: "Hello world",
          status: "draft"
        })

      assert changeset.valid?
    end

    test "requires platform, content, user_id" do
      changeset = Post.changeset(%Post{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert errors[:platform]
      assert errors[:content]
      assert errors[:user_id]
    end

    test "validates platform values" do
      changeset =
        Post.changeset(%Post{}, %{
          platform: "twitter",
          content: "x",
          status: "draft",
          user_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert errors_on(changeset)[:platform]
    end

    test "validates status values" do
      changeset =
        Post.changeset(%Post{}, %{
          platform: "linkedin",
          content: "x",
          status: "invalid",
          user_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert errors_on(changeset)[:status]
    end
  end

  describe "status_changeset/3" do
    test "transitions status" do
      user = user_fixture()
      post = post_fixture(user, %{status: "draft"})

      changeset = Post.status_changeset(post, "approved")
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == "approved"
    end

    test "includes extra attributes" do
      user = user_fixture()
      post = post_fixture(user, %{status: "publishing"})

      changeset =
        Post.status_changeset(post, "published", %{
          platform_post_id: "ext_123",
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :platform_post_id) == "ext_123"
    end
  end
end
