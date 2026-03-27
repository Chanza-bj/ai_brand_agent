defmodule AiBrandAgent.Fixtures do
  @moduledoc """
  Test fixtures for creating database records.
  """

  alias AiBrandAgent.Repo
  alias AiBrandAgent.Accounts.{User, SocialConnection, Topic, Post}

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      %User{}
      |> User.changeset(
        Map.merge(
          %{
            auth0_user_id: "auth0|#{unique_id()}",
            email: "user_#{unique_id()}@example.com",
            name: "Test User"
          },
          attrs
        )
      )
      |> Repo.insert()

    user
  end

  def social_connection_fixture(user, attrs \\ %{}) do
    {:ok, conn} =
      %SocialConnection{}
      |> SocialConnection.changeset(
        Map.merge(
          %{
            user_id: user.id,
            platform: "linkedin",
            auth0_connection_id: "linkedin",
            platform_user_id: "li_#{unique_id()}"
          },
          attrs
        )
      )
      |> Repo.insert()

    conn
  end

  def topic_fixture(attrs \\ %{}) do
    {:ok, topic} =
      %Topic{}
      |> Topic.changeset(
        Map.merge(
          %{
            title: "Test Topic #{unique_id()}",
            source: "test",
            metadata: %{category: "test"}
          },
          attrs
        )
      )
      |> Repo.insert()

    topic
  end

  def post_fixture(user, attrs \\ %{}) do
    topic =
      Map.get_lazy(attrs, :topic, fn ->
        topic_fixture(%{user_id: user.id})
      end)

    {:ok, post} =
      %Post{}
      |> Post.changeset(
        Map.merge(
          %{
            user_id: user.id,
            topic_id: topic.id,
            platform: "linkedin",
            content: "Test post content #{unique_id()}",
            status: "draft"
          },
          Map.delete(attrs, :topic)
        )
      )
      |> Repo.insert()

    post
  end

  defp unique_id, do: System.unique_integer([:positive]) |> to_string()
end
