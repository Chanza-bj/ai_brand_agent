defmodule AiBrandAgent.Auth.RefreshTokenCryptoTest do
  use ExUnit.Case, async: true

  alias AiBrandAgent.Auth.RefreshTokenCrypto

  describe "encrypt_for_storage/1 and decrypt_from_storage/1" do
    test "round-trip with test encryption key" do
      plain = "test-auth0-refresh-token-value"

      enc = RefreshTokenCrypto.encrypt_for_storage(plain)
      assert enc != plain
      assert String.starts_with?(enc, "enc_v1.")

      assert RefreshTokenCrypto.decrypt_from_storage(enc) == plain
    end

    test "legacy plaintext passes through decrypt" do
      assert RefreshTokenCrypto.decrypt_from_storage("plain-no-prefix") == "plain-no-prefix"
    end
  end
end
