# Hackathon demo — recording workflow & script

Companion to `HACKATHON_SUBMISSION.md`. Use this to rehearse and record your **~3 minute** video for the **Authorized to Act** hackathon (Auth0 **Token Vault** required).

**Dedicated teleprompter script (plain text):** [`HACKATHON_DEMO_SCRIPT.txt`](HACKATHON_DEMO_SCRIPT.txt)

---

## 1. What judges need to see on video

| Requirement | How you show it |
|-------------|-------------------|
| **Token Vault** | Say it by name; show **Google-connected** flow → **Agent settings → Save & sync calendar** (or Google Calendar tab). Optionally **Connections** if you show Token Vault / Google health. |
| **App on the built-for device** | Record **in the browser** (deployed URL or stable tunnel). Full window or 1280×720+ is fine. |
| **~3 minutes** | Script below targets **~2:45–3:00**; **hard-stop at 2:55** if you run long. |
| **Compliance** | Royalty-free or **no music**; avoid flashing unrelated trademarks as hero shots. |

---

## 2. Recording workflow

### A. Environment (day before)

1. **Deploy** (or ngrok / Cloudflare Tunnel) so the URL is stable; avoid losing session mid-take.
2. **Seed the story**: niche phrase, topic with drafts if possible, **Google already connected** so OAuth doesn’t eat the clock. **Dry run** with a timer.
3. **Browser**: zoom 100–110%, hide bookmarks bar, consistent theme. Close Slack/email.
4. **Auth0**: confirm Google + Token Vault path; **Connections** should look healthy or be explainable.
5. **Gemini**: if you show AI generation, confirm quota; if risky, **pre-generate** and show **Posts** + detail only.

### B. Recording setup

- **Video**: 1920×1080 or 1280×720, 30 fps.
- **Audio**: USB mic or headset; record a **30s test** and play back.
- **Tool**: OBS, Windows Game Bar (`Win+G`), or macOS Screenshot screen recording.
- **Capture**: **Browser window** only (cleaner than full desktop).

### C. Session

1. One full **dry run** without recording.
2. **2–3 takes** back-to-back; pick the cleanest.
3. **Trim** dead air at start/end only.
4. **Export** MP4 (H.264); upload **YouTube** or **Vimeo** per submission rules (**public** or **unlisted** if allowed).

### D. Post checklist

- [ ] Length **≤ 3:00** on the timeline.
- [ ] First **~20s** mention **problem + Auth0 Token Vault**.
- [ ] **Login + dashboard** visible.
- [ ] **Agent settings + calendar sync** OR clear Calendar proof.
- [ ] **Posts** path (draft → approve / schedule) visible.
- [ ] **No** copyrighted background music.
- [ ] YouTube title/description: project name + “Auth0 Token Vault” + live app / repo links.

---  

## 3. Word-for-word script (~3 min)

**~130–150 words/min → stop at ~3:00. Cut optional [bracketed] lines if long.**

### [0:00–0:25] Hook + Token Vault

> “Today’s AI agents need to call real APIs—like Google Calendar—without turning every app into a secret warehouse for OAuth tokens.  
> **AI Brand Agent** is a Phoenix web app that uses **Auth0 for AI Agents — Token Vault** so Google access tokens are issued through Auth0’s trust boundary, not pasted into our database.  
> I’ll show how a user’s **posting schedule** syncs to **Google Calendar** and how the agent uses that when it schedules content.”

### [0:25–0:55] Login + dashboard

> “I sign in with **Auth0**—here’s the **dashboard**: niches, recent topics, and posts.  
> The agent can run on a schedule in the background; what matters for this hackathon is **authorized access** to Google.”

### [0:55–1:40] Connections + Agent settings + calendar

> “Under **Connections**, Google is linked for **Token Vault**—the app exchanges the user’s Auth0 session for Google API access the right way.  
> In **Agent settings**, I set **timezone**, **weekdays**, and **local post time**—this is **local wall time**, not a confusing UTC offset.  
> I hit **Save and sync calendar**—that writes **transparent posting windows** to **Google Calendar** so I can see them and the agent can read them.  
> *[Optional: open **Google Calendar** in another tab—here are the **[AI Brand Agent] posting slots**.]*”

### [1:40–2:35] Posts + agent behavior

> “Back to **Posts**—here are drafts the pipeline created from a topic. I can **approve**, use **smart schedule** to respect calendar and busy time, or **publish** to LinkedIn or Facebook—those platforms use Auth0’s **linked identities** via the Management API.  
> The product caps **publishes per day** so the user keeps control.”

### [2:35–2:55] Close

> “**Summary:** **Token Vault** powers **Google Calendar** integration; **Auth0** handles **login and consent**; the user defines **when** the agent may act.  
> That’s **AI Brand Agent**—link to the repo and live demo in the description.”

**Stop. Do not add a fourth act.**

---

## 4. If something breaks while recording

- **Token Vault / Google fails**: show **Agent settings** + **Connections** + say Token Vault is configured in Auth0; show **README** if needed.
- **Gemini rate limit**: skip live generation; show **Posts** + **detail** only.
- **Over time**: drop the optional Google Calendar tab first.

---

## 5. YouTube description (paste)

```text
Demo: AI Brand Agent — Auth0 Token Vault for Google Calendar; Auth0 login; agent posting windows + calendar-aware scheduling; LinkedIn/Facebook via Auth0-linked accounts.

Live app: <YOUR_URL>
Repo: <YOUR_REPO_URL>
```

---

## 6. Submission cross-reference

See **`HACKATHON_SUBMISSION.md`** for the form-ready project description and checklist.
