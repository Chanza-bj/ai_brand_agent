# Registers the Token Vault public key with Auth0, configures Private Key JWT
# authentication, and enables Token Vault Privileged Access.
#
# Usage (from project root, with env vars set):
#   mix run priv/scripts/register_credential.exs
#
# Requires M2M scopes: create:client_credentials, read:client_credentials, update:clients

auth0_config = Application.fetch_env!(:ai_brand_agent, :auth0)
domain = Keyword.fetch!(auth0_config, :domain)
client_id = Keyword.fetch!(auth0_config, :client_id)
audience = Keyword.fetch!(auth0_config, :audience)

base = "https://#{domain}"
auth_header = fn token -> [{"authorization", "Bearer #{token}"}] end

# Read keys
private_key_path =
  System.get_env("AUTH0_TOKEN_VAULT_PRIVATE_KEY_PATH") ||
    raise "Set AUTH0_TOKEN_VAULT_PRIVATE_KEY_PATH env var"

clean_path = private_key_path |> String.trim() |> String.trim("\"")
private_pem = File.read!(clean_path)
IO.puts("Read private key from #{clean_path}")

public_key_path = String.replace(clean_path, "private_key.pem", "public_key.pem")
public_pem = File.read!(public_key_path)
IO.puts("Read public key from #{public_key_path}")

# Step 1: Get M2M token using Private Key JWT (client_assertion)
IO.puts("\n== Step 1: Fetching Management API token ==")

jwk = JOSE.JWK.from_pem(private_pem)
now = System.system_time(:second)

assertion_claims =
  Jason.encode!(%{
    "iss" => client_id,
    "sub" => client_id,
    "aud" => "#{base}/",
    "iat" => now,
    "exp" => now + 120,
    "jti" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  })

client_assertion =
  JOSE.JWS.sign(jwk, assertion_claims, %{"alg" => "RS256"})
  |> JOSE.JWS.compact()
  |> elem(1)

token_body = %{
  grant_type: "client_credentials",
  client_id: client_id,
  client_assertion: client_assertion,
  client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
  audience: audience
}

case Req.post("#{base}/oauth/token", json: token_body) do
  {:ok, %{status: 200, body: %{"access_token" => token}}} ->
    IO.puts("Got M2M token.")

    # Step 2: Check / create credential
    IO.puts("\n== Step 2: Checking credentials ==")

    {:ok, %{status: 200, body: existing_creds}} =
      Req.get("#{base}/api/v2/clients/#{client_id}/credentials", headers: auth_header.(token))

    IO.puts("Existing credentials: #{length(existing_creds)}")
    for cred <- existing_creds do
      IO.puts("  - #{cred["id"]} (#{cred["name"] || "unnamed"}, type: #{cred["credential_type"]})")
    end

    credential_id =
      case Enum.find(existing_creds, &(&1["name"] == "token-vault-key")) do
        %{"id" => id} ->
          IO.puts("Credential already exists: #{id}")
          id

        nil ->
          IO.puts("Creating credential...")

          {:ok, %{status: status, body: body}} =
            Req.post("#{base}/api/v2/clients/#{client_id}/credentials",
              headers: auth_header.(token),
              json: %{credential_type: "public_key", name: "token-vault-key", pem: public_pem}
            )

          if status in [200, 201] do
            IO.puts("Credential created: #{body["id"]}")
            body["id"]
          else
            IO.puts("Failed (#{status}): #{inspect(body)}")
            System.halt(1)
          end
      end

    # Step 3: Configure Private Key JWT + Token Vault Privileged Access
    IO.puts("\n== Step 3: Configuring client ==")

    patch_body = %{
      "token_endpoint_auth_method" => nil,
      "client_authentication_methods" => %{
        "private_key_jwt" => %{
          "credentials" => [%{"id" => credential_id}]
        }
      },
      "token_vault_privileged_access" => %{
        "credentials" => [%{"id" => credential_id}]
      }
    }

    case Req.request(
           method: :patch,
           url: "#{base}/api/v2/clients/#{client_id}",
           headers: auth_header.(token) ++ [{"content-type", "application/json"}],
           json: patch_body
         ) do
      {:ok, %{status: 200, body: resp}} ->
        IO.puts("Client configured successfully!")
        IO.puts("  token_endpoint_auth_method: #{inspect(resp["token_endpoint_auth_method"])}")
        IO.puts("  client_authentication_methods: #{inspect(resp["client_authentication_methods"])}")
        IO.puts("  token_vault_privileged_access: #{inspect(resp["token_vault_privileged_access"])}")
        IO.puts("\nDone! Private Key JWT auth + Token Vault Privileged Access are both enabled.")

      {:ok, %{status: status, body: body}} ->
        IO.puts("PATCH failed (#{status}): #{inspect(body)}")
    end

  {:ok, %{status: status, body: body}} ->
    IO.puts("Failed to get M2M token (#{status}): #{inspect(body)}")
end
