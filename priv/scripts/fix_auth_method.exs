# Restores token_endpoint_auth_method to fix login, while keeping the
# Token Vault credential registered.
#
# Usage: mix run priv/scripts/fix_auth_method.exs

auth0_config = Application.fetch_env!(:ai_brand_agent, :auth0)
domain = Keyword.fetch!(auth0_config, :domain)
client_id = Keyword.fetch!(auth0_config, :client_id)
client_secret = Keyword.fetch!(auth0_config, :client_secret)
audience = Keyword.fetch!(auth0_config, :audience)

base = "https://#{domain}"

IO.puts("Fetching Management API token...")

{:ok, %{status: 200, body: %{"access_token" => token}}} =
  Req.post("#{base}/oauth/token",
    json: %{
      client_id: client_id,
      client_secret: client_secret,
      audience: audience,
      grant_type: "client_credentials"
    }
  )

IO.puts("Restoring token_endpoint_auth_method...")

case Req.request(
       method: :patch,
       url: "#{base}/api/v2/clients/#{client_id}",
       headers: [{"authorization", "Bearer #{token}"}, {"content-type", "application/json"}],
       json: %{
         "token_endpoint_auth_method" => "client_secret_post",
         "client_authentication_methods" => nil
       }
     ) do
  {:ok, %{status: 200}} ->
    IO.puts("Restored! Login should work again.")

  {:ok, %{status: status, body: body}} ->
    IO.puts("Failed (#{status}): #{inspect(body)}")
end
