defmodule AiBrandAgent.Auth.TokenVaultTest do
  use AiBrandAgent.DataCase, async: true

  alias AiBrandAgent.Auth.TokenVault
  import AiBrandAgent.Fixtures

  describe "get_access_token/2" do
    test "returns error when user not found" do
      assert {:error, :user_not_found} =
               TokenVault.get_access_token(Ecto.UUID.generate(), "linkedin")
    end

    test "returns error when no connection exists" do
      user = user_fixture()

      assert {:error, {:no_connection, "linkedin"}} =
               TokenVault.get_access_token(user.id, "linkedin")
    end

    test "google_federated_token_vault_ok? is false without google connection" do
      user = user_fixture()

      refute TokenVault.google_federated_token_vault_ok?(user.id)
    end
  end
end
