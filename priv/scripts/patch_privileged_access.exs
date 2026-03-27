token =
  System.get_env("API_EXPLORER_TOKEN") ||
    File.read!("api_token.txt") |> String.trim()
client_id = "YhMo6wJk3vrdzj4q1FVvgFbjydr7zQPg"
credential_id = "cred_6kghyPsUwVirNNx5w14q5o"
base = "https://dev-677l58koldj2zef6.us.auth0.com"

IO.puts("Patching client #{client_id} with token_vault_privileged_access...")

case Req.request(
       method: :patch,
       url: "#{base}/api/v2/clients/#{client_id}",
       headers: [
         {"authorization", "Bearer #{token}"},
         {"content-type", "application/json"}
       ],
       json: %{
         "token_vault_privileged_access" => %{
           "credentials" => [%{"id" => credential_id}]
         }
       }
     ) do
  {:ok, %{status: 200, body: resp}} ->
    IO.puts("Success!")
    IO.puts("token_vault_privileged_access: #{inspect(resp["token_vault_privileged_access"])}")

  {:ok, %{status: status, body: body}} ->
    IO.puts("Failed (#{status}): #{inspect(body)}")
end
