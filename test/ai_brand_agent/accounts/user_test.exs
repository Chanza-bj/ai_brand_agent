defmodule AiBrandAgent.Accounts.UserTest do
  use AiBrandAgent.DataCase, async: true

  alias AiBrandAgent.Accounts.User

  describe "changeset/2" do
    test "valid changeset" do
      changeset =
        User.changeset(%User{}, %{
          auth0_user_id: "auth0|test",
          email: "test@example.com",
          name: "Test"
        })

      assert changeset.valid?
    end

    test "requires auth0_user_id and email" do
      changeset = User.changeset(%User{}, %{})
      refute changeset.valid?
      assert errors_on(changeset)[:auth0_user_id]
      assert errors_on(changeset)[:email]
    end

    test "enforces unique auth0_user_id" do
      {:ok, _} =
        %User{}
        |> User.changeset(%{auth0_user_id: "auth0|dup", email: "a@a.com", name: "A"})
        |> Repo.insert()

      {:error, changeset} =
        %User{}
        |> User.changeset(%{auth0_user_id: "auth0|dup", email: "b@b.com", name: "B"})
        |> Repo.insert()

      assert errors_on(changeset)[:auth0_user_id]
    end
  end
end
