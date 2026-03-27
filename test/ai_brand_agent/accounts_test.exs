defmodule AiBrandAgent.AccountsTest do
  use AiBrandAgent.DataCase, async: true

  alias AiBrandAgent.Accounts
  import AiBrandAgent.Fixtures

  describe "upsert_user_from_auth0/1" do
    test "creates a new user from Auth0 profile" do
      profile = %{
        "sub" => "auth0|new123",
        "email" => "new@example.com",
        "name" => "New User"
      }

      assert {:ok, user} = Accounts.upsert_user_from_auth0(profile)
      assert user.auth0_user_id == "auth0|new123"
      assert user.email == "new@example.com"
      assert user.name == "New User"
    end

    test "updates an existing user" do
      existing = user_fixture(%{auth0_user_id: "auth0|existing"})

      profile = %{
        "sub" => "auth0|existing",
        "email" => "updated@example.com",
        "name" => "Updated Name"
      }

      assert {:ok, user} = Accounts.upsert_user_from_auth0(profile)
      assert user.id == existing.id
      assert user.email == "updated@example.com"
      assert user.name == "Updated Name"
    end
  end

  describe "get_user/1" do
    test "returns user by ID" do
      user = user_fixture()
      assert Accounts.get_user(user.id).id == user.id
    end

    test "returns nil for unknown ID" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_user_by_auth0_id/1" do
    test "returns user by Auth0 ID" do
      user = user_fixture(%{auth0_user_id: "auth0|lookup"})
      assert Accounts.get_user_by_auth0_id("auth0|lookup").id == user.id
    end
  end

  describe "session token" do
    test "assign_new_session_token! rotates token and session_valid? matches current cookie" do
      user = user_fixture()
      t1 = Accounts.assign_new_session_token!(user)
      user = Accounts.get_user(user.id)
      assert Accounts.session_valid?(user, t1)

      t2 = Accounts.assign_new_session_token!(user)
      user = Accounts.get_user(user.id)
      assert Accounts.session_valid?(user, t2)
      refute Accounts.session_valid?(user, t1)
    end

    test "session_valid? rejects wrong or missing token when user has a token" do
      user = user_fixture()
      t = Accounts.assign_new_session_token!(user)
      user = Accounts.get_user(user.id)
      assert Accounts.session_valid?(user, t)
      refute Accounts.session_valid?(user, "not-the-token")
      refute Accounts.session_valid?(user, nil)
    end

    test "legacy_bootstrap? is true only when DB and cookie both lack a token" do
      user = user_fixture()
      assert Accounts.legacy_bootstrap?(user, nil)
      t = Accounts.assign_new_session_token!(user)
      user = Accounts.get_user(user.id)
      refute Accounts.legacy_bootstrap?(user, nil)
      refute Accounts.legacy_bootstrap?(user, t)
    end

    test "clear_session_token! clears server-side token" do
      user = user_fixture()
      _ = Accounts.assign_new_session_token!(user)
      user = Accounts.get_user(user.id)
      assert user.current_session_token
      :ok = Accounts.clear_session_token!(user)
      user = Accounts.get_user(user.id)
      refute user.current_session_token
    end
  end

  describe "upsert_connection/2" do
    test "creates a new connection" do
      user = user_fixture()

      attrs = %{
        platform: "linkedin",
        auth0_connection_id: "linkedin",
        platform_user_id: "li_123"
      }

      assert {:ok, conn} = Accounts.upsert_connection(user.id, attrs)
      assert conn.platform == "linkedin"
      assert conn.user_id == user.id
    end

    test "updates existing connection for same platform" do
      user = user_fixture()
      social_connection_fixture(user, %{platform: "linkedin", platform_user_id: "old"})

      attrs = %{
        platform: "linkedin",
        auth0_connection_id: "linkedin",
        platform_user_id: "new_id"
      }

      assert {:ok, conn} = Accounts.upsert_connection(user.id, attrs)
      assert conn.platform_user_id == "new_id"
      assert length(Accounts.list_connections(user.id)) == 1
    end
  end

  describe "list_connections/1" do
    test "returns connections for user" do
      user = user_fixture()
      social_connection_fixture(user, %{platform: "linkedin"})
      social_connection_fixture(user, %{platform: "facebook"})

      connections = Accounts.list_connections(user.id)
      assert length(connections) == 2
    end

    test "returns empty list for user with no connections" do
      user = user_fixture()
      assert Accounts.list_connections(user.id) == []
    end
  end

  describe "delete_connection/1" do
    test "deletes an existing connection" do
      user = user_fixture()
      conn = social_connection_fixture(user)

      assert {:ok, _} = Accounts.delete_connection(conn.id)
      assert Accounts.list_connections(user.id) == []
    end

    test "returns error for unknown connection" do
      assert {:error, :not_found} = Accounts.delete_connection(Ecto.UUID.generate())
    end
  end

  describe "set_facebook_default_page/2" do
    test "stores numeric page id" do
      user = user_fixture()

      social_connection_fixture(user, %{
        platform: "facebook",
        auth0_connection_id: "facebook",
        platform_user_id: nil
      })

      assert {:ok, conn} = Accounts.set_facebook_default_page(user.id, "12345678901234")
      assert conn.platform_user_id == "12345678901234"
    end

    test "clears page id for empty string" do
      user = user_fixture()

      social_connection_fixture(user, %{
        platform: "facebook",
        auth0_connection_id: "facebook",
        platform_user_id: "111"
      })

      assert {:ok, conn} = Accounts.set_facebook_default_page(user.id, "")
      assert conn.platform_user_id == nil
    end

    test "returns error when facebook not connected" do
      user = user_fixture()
      assert {:error, :not_connected} = Accounts.set_facebook_default_page(user.id, "123")
    end

    test "returns error for non-numeric page id" do
      user = user_fixture()

      social_connection_fixture(user, %{
        platform: "facebook",
        auth0_connection_id: "facebook"
      })

      assert {:error, :invalid_page_id} =
               Accounts.set_facebook_default_page(user.id, "not-digits")
    end
  end
end
