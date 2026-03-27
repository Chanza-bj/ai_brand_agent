# AiBrandAgent

Phoenix app for an **AI brand agent**: trend discovery, **Gemini** content generation, and scheduled/published posts to **LinkedIn** and **Facebook**. **Google Calendar** integration uses **[Auth0 for AI Agents — Token Vault](https://auth0.com/ai/docs/intro/token-vault)** so federated tokens stay in Auth0, not in your database.

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| **Elixir** | `~> 1.15` (see `mix.exs`) |
| **PostgreSQL** | Running locally; dev DB settings live in `config/dev.exs` — adjust user/password/database if yours differ |
| **Auth0 tenant** | Application + (for LinkedIn/Facebook) an M2M app for Management API |
| **Gemini API key** | For AI content (`GEMINI_API_KEY`) |

---

## Quick start

1. **Clone** the repo and **install** dependencies and DB:

   ```bash
   mix setup
   ```

   `mix setup` runs `deps.get`, `ecto.create` / `ecto.migrate`, seeds, and asset tooling (Tailwind + esbuild).

2. **Environment** — Copy `.env.example` to `.env`, fill at least **Auth0** and **Gemini** variables. Load env (e.g. `source .env`, [direnv](https://direnv.net/), or your shell profile). See `.env.example` for the full list.

3. **Run** the server:

   ```bash
   mix phx.server
   ```

4. **Open** the app — default **dev** HTTP port is **4001** (see `config/dev.exs`):

   [http://localhost:4001](http://localhost:4001)

If `mix setup` fails on the database, ensure PostgreSQL is up and credentials in `config/dev.exs` match your instance.

---

## Niches, topic ideas, and compose

1. After login, open **Niches** (`/niches`) and add one or more **niche phrases** (up to 10). These seed what the app should pay attention to.
2. **Oban** runs `TrendWorker` on a schedule (default: every **15 minutes** in `config/config.exs`). For each user with **enabled** niches, the default **`AiBrandAgent.Trends.LlmFetcher`** calls **Gemini** to propose short topic titles (a stand-in for real trend APIs). Topics are stored **per user** (`topics.user_id`).
3. For each new topic, **ContentWorker** creates draft posts for platforms that user has connected (LinkedIn / Facebook).
4. **Compose** (`/posts/new`) saves a **manual** draft with your own copy (no AI); `topic_id` is optional.

To plug in a different source (News API, RSS, etc.), implement `AiBrandAgent.Trends.Fetcher` and set `config :ai_brand_agent, :trend_fetcher, YourModule`.

---

## Auth0 overview

| Layer | What this app uses |
|--------|----------------------|
| **Login** | Regular Auth0 Universal Login (e.g. Google) |
| **Google / Calendar** | **Token Vault** — OAuth 2.0 token exchange to a **Token Vault access token**, then Google APIs. Optional **Connected Accounts** (My Account API) if the dashboard Token Vault indicator is red. |
| **LinkedIn / Facebook** | **Management API** — read provider access tokens from the user’s linked identities (`read:user_idp_tokens`). Not Token Vault–backed in this codebase. |
| **Linking social accounts** | After OAuth, identities are **merged** into the primary Auth0 user (`update:users` on the M2M app). You must be logged in to use `/auth/connect/*`. |

### Google (Token Vault + Calendar)

1. **Grant type** — In the Auth0 application: **Advanced Settings → Grant Types**, enable  
   `urn:auth0:params:oauth:grant-type:token-exchange:federated-connection-access-token`.

2. **Google connection** — **Authentication → Social → Google**: set **Purpose** to **Connected Accounts for Token Vault** or **Both** (not “Login” only), or Token Vault exchange will fail with “not enabled for this connection”.

3. **Privileged worker** — Generate an RSA key pair, register the **public** key in the app’s Token Vault / privileged access settings. Set one of:

   - `AUTH0_TOKEN_VAULT_PRIVATE_KEY` — PEM string  
   - `AUTH0_TOKEN_VAULT_PRIVATE_KEY_PATH` — path to PEM file  

4. **Connected Accounts (optional but recommended)** — If Token Vault stays red, use **Set up Connected Accounts** in the UI or visit `/auth/connected-accounts/start`. Requires **My Account API**, **Connected Accounts** scopes, and **MRRT** per [Connected Accounts for Token Vault](https://auth0.com/docs/secure/call-apis-on-users-behalf/token-vault/connected-accounts-for-token-vault).

5. **Callback URL** — Add the **exact** callback URL to the application’s **Allowed Callback URLs** in Auth0. It must match how you run the app (scheme, host, **port**, path), e.g.  
   `http://localhost:4001/auth/connected-accounts/callback`  
   if you use the default dev port **4001**.

6. **Re-authenticate** users after changing connection purpose or Vault settings so federated tokens are stored correctly.

**Docs:** [Configure Token Vault](https://auth0.com/docs/secure/call-apis-on-users-behalf/token-vault/configure-token-vault) · [Google for AI Agents](https://auth0.com/ai/docs/integrations/google)

### Management API (M2M)

Use audience `https://YOUR_DOMAIN/api/v2/` with scopes such as:

- `read:users` — load profiles  
- `update:users` — [link identities](https://auth0.com/docs/manage-users/user-accounts/user-account-linking/link-user-accounts) when connecting LinkedIn/Facebook  
- `read:user_idp_tokens` — read provider tokens for publishing  

---

## Sessions

Phoenix uses a normal **session cookie** per browser. This app also stores a **server-side session token** on the user: logging in via `/auth/auth0` issues a new token and **invalidates other browsers/devices** for that user on their next request. Connecting LinkedIn/Facebook does **not** rotate that token. Logout clears the server-side token.

---

## Troubleshooting

**Debug logging** — Set `config :logger, level: :debug` in `config/dev.exs` to see Token Vault vs Management API routes. Access and refresh tokens are not logged.

**LinkedIn 403 / wrong API** — This app posts with **`POST /v2/ugcPosts`** and does **not** send `Linkedin-Version` on UGC. You need **Share on LinkedIn** / `w_member_social` in the connection; reconnect after fixing scopes.

**`{:no_identity_token, "linkedin"}` (or `facebook`)** — The user’s Auth0 **identities** must include that provider. Enable the connection for **your** application (app ↔ connection toggles on both sides).

**Facebook: `manage_pages` / invalid scopes** — Use **`pages_manage_posts`** and **`pages_show_list`**, not `manage_pages`. If Auth0 keeps old scopes, inspect the connection with the Management API or create a new connection and set `AUTH0_FACEBOOK_CONNECTION_NAME`.

**Facebook: only `public_profile` / empty `/me/accounts`** — Permissions must be requested and re-consented (Auth0 Facebook **Permissions**, Meta app settings, disconnect/reconnect). For Page posting you need a **Page** you administer and the right Meta app mode. See server logs for `granted permissions=...`.

**Production** — See [Phoenix deployment](https://hexdocs.pm/phoenix/deployment.html).

---

## Development

- **Quality gate:** `mix precommit` (compile with warnings as errors, format, test).
- **Framework:** [Phoenix](https://www.phoenixframework.org/) · [docs](https://hexdocs.pm/phoenix/overview.html)
