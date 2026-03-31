defmodule AiBrandAgent.Auth.RefreshTokenCrypto do
  @moduledoc """
  Optional AES-256-GCM encryption for `users.auth0_refresh_token` at rest.

  Set `AUTH0_REFRESH_TOKEN_ENCRYPTION_KEY` (Base64-encoded 32-byte key) in production.
  If unset, tokens are stored as returned by Auth0 (legacy behavior).

  Existing plaintext values decrypt as-is until re-saved after encryption is enabled.
  """

  require Logger

  @prefix "enc_v1."

  @doc "Encrypt before persisting, or pass through if no key configured."
  def encrypt_for_storage(plain) when is_binary(plain) do
    case encryption_key_bytes() do
      nil ->
        plain

      key ->
        iv = :crypto.strong_rand_bytes(12)
        {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plain, <<>>, true)
        @prefix <> Base.encode64(iv <> cipher <> tag)
    end
  end

  @doc "Decrypt after load for use with Auth0 APIs, or return legacy plaintext."
  def decrypt_from_storage(stored) when is_binary(stored) do
    cond do
      stored == "" ->
        stored

      String.starts_with?(stored, @prefix) ->
        enc = String.replace_prefix(stored, @prefix, "")

        case encryption_key_bytes() do
          nil ->
            stored

          key ->
            try do
              raw = Base.decode64!(enc)
              <<iv::binary-12, rest::binary>> = raw
              ct_len = byte_size(rest) - 16
              <<ciphertext::binary-size(ct_len), tag::binary-16>> = rest

              :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, <<>>, tag, false)
            rescue
              e ->
                Logger.error("RefreshTokenCrypto: decrypt failed #{Exception.message(e)}")
                ""
            end
        end

      true ->
        stored
    end
  end

  defp encryption_key_bytes do
    Application.get_env(:ai_brand_agent, :auth0_refresh_token_encryption_key)
  end
end
