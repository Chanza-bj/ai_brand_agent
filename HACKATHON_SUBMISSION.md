# Authorized to Act Hackathon — submission copy

Use the **Project description** block below on the submission form. Trim if the form has a character limit.

---

## Project description (paste into form)

**Athena** is a Phoenix web app that acts as an **AI-powered brand assistant**: it discovers niche-driven topic ideas (via Gemini), generates multiple post variants, ranks them, and schedules or publishes to **LinkedIn** and **Facebook**—with the user’s **posting windows** grounded in **Google Calendar**.

**Why Auth0 for AI Agents (Token Vault)**  
The hackathon requires agents to act on behalf of users with real OAuth consent—not by copying long-lived Google secrets into our database. **Athena uses Auth0 Token Vault** to obtain **Google access tokens** through Auth0’s token exchange, so federated refresh material stays in Auth0’s trust boundary. Our server calls Google Calendar APIs (read busy times, sync transparent “posting slot” events) through that flow. LinkedIn and Facebook publishing use Auth0’s **Management API** identity tokens, matching how humans link social accounts.

**User-facing features**  
- **Sign in** with Auth0 (e.g. Google).  
- **Niches & trends**: seed topics; scheduled jobs propose new ideas per user.  
- **AI drafts**: multi-variant generation; winning variant is approved and scheduled subject to rules.  
- **Agent settings**: IANA timezone, local weekdays/time; schedule is **written to Google Calendar** so the user sees their windows and the agent can read upcoming slots.  
- **Posts**: compose manually or from AI; approve, smart-schedule (calendar-aware), or publish.  
- **Connections**: link LinkedIn/Facebook; optional **Connected Accounts** flow when Token Vault needs federated consent.

**Technical stack**  
Elixir/Phoenix, PostgreSQL, Oban (background jobs), Gemini, Auth0 (login + Token Vault + Management API), Req for HTTP.

**Repository & run**  
Public GitHub repo includes source, assets, and **README** with `mix setup`, environment variables (Auth0, Gemini, optional Token Vault key), and Auth0 configuration notes for Token Vault grant types and Google connection purpose.

**Live demo**  
[Replace with your deployed URL when ready.]

---

## ~3 minute demo outline (video)

1. **0:00–0:20** — Problem: agents need API access without hoarding OAuth secrets; Auth0 Token Vault as the intermediary.  
2. **0:20–0:50** — Log in; show dashboard.  
3. **0:50–1:30** — Connect Google / show Agent settings: timezone, days, time → **Save & sync calendar**; show Google Calendar (or in-app “next suggested slots”).  
4. **1:30–2:30** — Niches or generated topic → draft posts → approve / schedule or publish path; mention daily cap and calendar-aware scheduling.  
5. **2:30–3:00** — Recap: Token Vault for Google; Auth0 for identity and consent; user stays in control of schedule and connections.

**Recording tips:** Browser only is fine (built for web). No copyrighted music. Stop at 3 minutes.

---

## Optional — bonus blog post (250+ words)

If you submit the blog in the **same** text field, add a visible header so judges see it, e.g.:

---

### BONUS BLOG POST — Token Vault in Athena

*[Paste 250+ words here: your journey enabling Token Vault, federated vs Management API fallback, Connected Accounts, one pitfall you hit, and what you’d build next. Keep it materially different from the short description above.]*

---

## Submission checklist

| Item | Status |
|------|--------|
| Token Vault used (Google Calendar path) | Yes — document in README & description |
| Public repo | Add link when published |
| Demo video (~3 min) | YouTube/Vimeo/etc. public link |
| Published app URL | Replace placeholder above |
| APK | N/A — web app; note on form if required |
