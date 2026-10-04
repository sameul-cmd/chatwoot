# Phase 8 — aibot, the AI first-reply bot (Improvement 4)

Spec: SPEC Section 13, Section 17 (Phase 8), `.claude/CLAUDE.md` "aibot rules", ADR-011 (BYOK LLM), ADR-012 (private-network webhook), TECH_ARCHITECTURE sections 2, 4 and 7 (add-on extension points).
**Accept (from SPEC):** on the demo client, the bot answers a KB question in Bangla and in English, hands off on "মানুষ চাই" / "talk to a human", on an off-topic question, and after 3 bot turns; the first message discloses automation; `aibot eval` on the demo test set meets the gate; client mode refuses to start without `AIBOT_LLM_TIER_PAID=true` or a local/client key; no message text in logs (test).

## What this phase is, in plain words
When a customer writes to the client's inbox, the **bot answers first**, but only from the client's own answers (a small question-and-answer list, the "KB"). It writes in the customer's language (Bangla or English), says at the start that it is an automated assistant, never pretends to be a person, never invents prices or policies, and **hands the chat to a human** whenever it is not sure, the customer asks for a person, the customer is upset, the question is off-topic, or it has already replied three times. If the bot or the AI service is down, Chatwoot automatically opens the chat for humans (verified in Phase 0), so a bot problem never leaves a customer unanswered.

You bring your **own AI account** (any OpenAI-compatible service, "BYOK"). The kit lets you pick the model from the service's list and set how hard it thinks (none to max). Your key stays on the server and never goes into git or logs.

What I can prove **here**: every rule, the whole message flow against a real Chatwoot demo, using a **pretend AI** that answers in a scripted way. What I **cannot** prove here: how good a real model's answers are. That needs your real key; the `aibot eval` command measures it, and the go-live gate (no wrong prices/policies, 90% correct-or-handed-off) must be run by you with your key on your own device before a paying client goes live.

## Facts this phase relies on (verified in Phase 0 on v4.18.0; items marked *(verify)* are re-checked live in 8.1)
- Register the bot: `POST /api/v1/accounts/:id/agent_bots {name, outgoing_url}` returns `access_token` (the bot's own API token) and `secret` (signs webhooks). Attach it to an inbox: `POST /inboxes/:id/set_agent_bot`.
- Webhook headers: `X-Chatwoot-Delivery`, `X-Chatwoot-Timestamp`, `X-Chatwoot-Signature: sha256=HMAC_SHA256(secret, "<timestamp>.<raw body>")`. The bot checks the signature **and** the secret in the URL path.
- The bot gets `message_created` for incoming messages **and its own replies**; it acts only on `message_created`, `message_type == incoming`, not private, conversation `pending`.
- New conversations on a bot inbox start `pending` with the bot as assignee. Reply: bot token `POST /conversations/:id/messages`. Hand off: `POST /conversations/:id/toggle_status {"status":"open"}`, label via `POST /conversations/:id/labels`.
- Chatwoot refuses webhooks to private addresses unless `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` (set in every client `.env`, ADR-012). Webhook retries happen on HTTP 429/500, so the bot must answer 200 fast and work in the background.
- If the bot is unreachable Chatwoot opens the conversation for humans.
- *(verify)* assigning a team on handoff (`POST /conversations/:id/assignments {team_id}`), the `GET /teams` lookup, and which token (bot or admin) may do it.
- Already in the repo: `aibot/` skeleton (config with BYOK settings and the paid-tier rule, `/health`), `AIBOT_*` env rendering from `client.yaml bot:`, `SAFE_FETCH...`, the aibot container and its `/data` volume, packs' `kb_starter/faq.yaml` copied to `clients/<id>/kb/faq.yaml` (Phase 7), `opskit llm` placeholder.

## Owner answers (2026-10-04) — these replace the defaults below where they differ
1. **Real key available.** The owner has an OpenAI-compatible key ready. Everything is still built and proven with the pretend AI (tests never call a real service), **and** new task 8.12 runs a real-model check once the key is in this environment (see "What I need from you": the key goes into the environment settings, never into the chat). Only the fictional demo KB is ever sent.
2. **Mask phones and emails** before sending: as proposed.
3. **KB search = hybrid, each is the fallback of the other** (instead of keyword-only): keyword ranking (BM25) and AI-embedding search both run when an embedding model is configured and their results are merged (reciprocal rank fusion); if the embedding service is not configured or fails, keyword ranking alone is used; if keyword ranking finds nothing (Banglish, different wording), embedding search alone is used. No new software: embeddings come from the same OpenAI-compatible service (`/embeddings`), vectors are cached in the bot's SQLite by content hash, similarity is computed in plain Python (the KB is small). Costs one extra small AI call per question (the embedding of the question).
4. **Bot wording:** draft bn + en, Bangla needs the owner's approval before real clients: as proposed.
5. **Upset customers = word list plus AI mood check** (instead of words only): the same answer call also returns `upset: true/false` (no second AI call); either the word list or the AI flag hands off with reason `upset`.
6. **Handoff:** open + label + team if set: as proposed. 7. **3 replies / confidence 0.7:** as proposed. 8. **enable / disable commands:** as proposed. 9. **Counts and unanswered list kept on the host for Phase 9:** as proposed (default).

## Open questions for the owner (plain words; defaults in bold) — original text, answered above
1. **Test AI.** The sandbox must not call real AI services in tests. **Default:** everything is proven with a scripted pretend AI (a small fake server); you run `aibot eval` with your real key on your own device before the first paying client. If you prefer, give me a throw-away key later and I try one real call, but tests never use it.
2. **Customer privacy towards the AI provider.** Customer messages go to your AI provider. **Default:** phone numbers and email addresses in a customer's text are replaced by `[phone]` / `[email]` before sending, and the provider must be a paid or owner-owned key (the existing rule). Names are not removed.
3. **How the bot finds answers.** **Default:** the client's `kb/faq.yaml` (question + answer, bn and en; plus optional `kb/*.md` notes), searched with a simple keyword ranking (BM25, no new software to install); questions with an empty answer are ignored. A list of "also called" words per answer handles Banglish ("dam koto", "delivery kobe").
4. **Wording of the bot's fixed messages** (greeting with disclosure, handoff, "I can only help with questions about <business>"). **Default:** I draft English and Bangla; Bangla is marked "review needed" and, like the packs, is **not used on a real client until you approve it** (demo uses it with a flag). The client can override any text in `client.yaml`.
5. **Upset customers.** **Default:** a fixed word list (bn + en: "complaint", "cheat", "refund", "অভিযোগ", "প্রতারণা", "ফেরত", plus swearing) hands off at once with a friendly message; the client can extend the list. No AI guess about mood in V1.
6. **Handoff target.** **Default:** the chat is opened for humans, labelled `ai-handoff`, and assigned to `bot.handoff_team` if the client has set one (checked live in 8.1; if it cannot be done, the chat is only opened and labelled).
7. **Turn limit and confidence.** **Default:** hand off after **3 bot replies** and when confidence is below **0.7** (both already in the config; client can change).
8. **Switching the bot on/off.** **Default:** `opskit bot enable <id> --inbox N` registers the bot and attaches it to that inbox; `opskit bot disable <id>` detaches it everywhere (kill switch, no redeploy; chats go straight to humans); `opskit bot status <id>` shows counts. Nothing is attached to any inbox until you run `enable`.
9. **Reports for Phase 9.** **Default:** the bot keeps counts (answered, handed off by reason, errors, average time) and the unanswered questions list in its own small database on the host; no push to a hub (no hub exists, ADR-016); the care report in Phase 9 reads it.

## Tasks

### [ ] 8.1 — Verify the open Chatwoot facts live
- **Goal:** on a running demo: create the agent bot through the API, attach it to an inbox, receive a real webhook in a small listener, check the signature formula, send a reply and a handoff with the **bot** token, test label + team assignment (`GET /teams`, `POST .../assignments`), and what happens to a conversation when the bot is switched off mid-chat. Record in EXPLORATION_REPORT; save sample payloads as fixtures.
- **Acceptance:** findings written; fixtures saved (fictional data only).

### [ ] 8.2 — Pure logic: language, KB and retrieval
- **Goal:** `lang.py` (Bangla script / English / Banglish by script ratio and a small Banglish word list), `kb.py` (load `faq.yaml` + `*.md`, chunk, ignore empty answers, aliases), `retrieval.py` (BM25 over bn + en tokens; cosine similarity over cached vectors; reciprocal rank fusion that merges both and falls back to whichever one is available or finds something). No network, no new dependencies.
- **Acceptance:** pytest: language cases (bn, en, mixed, Banglish, numbers only), retrieval picks the right entry for bn/en/Banglish questions and nothing for unrelated ones, empty answers ignored; with vectors missing the ranking equals BM25, with BM25 finding nothing the vector result is used, with both the fused order is stable.

### [ ] 8.3 — Pure logic: policy and handoff rules
- **Goal:** `policy.py`: human-request keywords, complaint words, off-topic (no snippet found), turn limit, confidence gate (`>= min_confidence` and at least one snippet used), and the **fact guard** (numbers, currency and delivery/return/price claims in an answer must appear in the snippets it used, otherwise hand off). `messages.py`: the bot's fixed messages (disclosure, handoff, off-topic) in bn/en with `review_required` flags and client overrides. Every handoff has a named reason.
- **Acceptance:** pytest covers each handoff trigger separately (human request in bn and en, complaint, off-topic, turn limit, low confidence, no snippet used, invented price, LLM error), disclosure on the first bot message only, and "never claims to be human".

### [ ] 8.4 — LLM adapter (BYOK) with a fake
- **Goal:** `llm.py`: one OpenAI-compatible `/chat/completions` client plus `/embeddings` (optional `bot.embeddings.model`; vectors cached by content hash; failure = silent fallback to keyword ranking and a counter) (`base_url`, key from the env var named in `api_key_env`, model, effort sent as `reasoning_effort` or the configured name; `max` mapped down per endpoint if refused, never failing the reply, A-001); strict JSON reply `{answer, confidence, used_ids, handoff, upset}` (the AI mood flag, question 5) parsed from plain or fenced JSON; timeouts and one retry; phone/email masking (question 2); prompt files in `aibot/prompts/` (answer only from snippets; business topics only; Bangla/English; never claim to be human). A scripted **fake LLM server** in the tests.
- **Acceptance:** pytest with the fake: embeddings success/failure/not configured, good JSON, fenced JSON, garbage, timeout, HTTP 400 on the effort field (falls back), no key in logs/repr, phone number masked in the outgoing request.

### [ ] 8.5 — Chatwoot client and the webhook
- **Goal:** `chatwoot.py` (send message, private note, labels, custom attributes, toggle status, assign team, list messages: all behind one class, as TECH_ARCHITECTURE section 7 asks), `app.py` `POST /webhook/<secret>`: check the secret path, the signature, account and inbox; ignore outgoing/bot/private/non-pending; **idempotent on the message id** (SQLite); answer 200 at once and work in a background task; `audit.py` (SQLite with a schema-version table; question, answer, used ids, confidence, handoff reason, kept `audit_days`); logs never contain message text. A fake Chatwoot for tests.
- **Acceptance:** pytest: wrong secret/signature rejected, each ignored event type, a retried delivery answered once, no message text in captured logs (test), audit pruning.

### [ ] 8.6 — Handlers package, reload, metrics, health
- **Goal:** the webhook calls an ordered list of handlers (V1: the answer handler only, extension point for V2 add-ons); `POST /admin/reload` (internal network only) reloads the KB without restart; `/health` as today plus KB size; metrics counters (answered, handed off by reason, errors, latency) and the unanswered-questions list kept in the audit database for Phase 9; kill-switch awareness (`bot.enabled: false` answers 200 and does nothing).
- **Acceptance:** pytest; metrics numbers match a scripted conversation set exactly.

### [ ] 8.7 — opskit wiring: `bot enable | disable | status | reload`
- **Goal:** `lib/bot.sh`: `enable` (idempotent) creates the agent bot via the API with the aibot webhook URL (`http://aibot:8000/webhook/<secret>`), stores the bot token and the signing secret in `clients/<id>/bot.env` (mode 600, git-ignored, merged into `aibot.env` by render), attaches it to the chosen inboxes, restarts only the aibot container, and runs a live check; `disable` detaches everywhere and sets the kill switch; `status` shows attached inboxes, health, counts; `reload` calls the KB reload. `render` mounts `kb/` (read-only) and a rendered bot config. A restored stack just needs `bot enable` again (documented).
- **Acceptance:** bats with the fake Chatwoot API; second `enable` changes nothing; `disable` leaves no inbox attached; no token printed.

### [ ] 8.8 — `opskit llm models | model | effort | set-key`
- **Goal:** replaces the placeholder: `llm models <id>` lists the endpoint's `/models` (needs the key), `llm model <id> <name>` and `llm effort <id> none|low|medium|high|max` write to `client.yaml bot.llm`, `llm set-key <id> [--paid]` stores the key from a hidden prompt or the environment in `clients/<id>/aibot-llm.env` (mode 600) and records the paid-tier statement you make; re-render + restart aibot. Client mode still refuses to start without paid-tier or an owner/client key.
- **Acceptance:** bats with a fake `/models`; key never printed; invalid effort rejected with the valid values.

### [ ] 8.9 — `aibot eval` and the demo KB and test set
- **Goal:** `eval.py` runs a client's test set (YAML: question, language, expected outcome: answer containing certain facts / handoff / forbidden claims) through the real pipeline and scores **correct / handed off / wrong / wrong price-or-policy**, prints the gate result (0 wrong prices/policies and at least 90% correct-or-handed-off) and a table of failures without customer data; `opskit bot eval <id>`. A demo KB (fictional shop) and a 24-question demo test set (KB questions in bn/en/Banglish, off-topic, human request, complaint, invented-price traps).
- **Acceptance:** with the scripted fake AI the harness scores each case type correctly and the gate logic passes/fails as designed (pytest); documented that the real-model score must be taken with your key.

### [ ] 8.10 — Live acceptance and selftest v7
- **Goal:** on the demo stack with the fake AI server reachable from the aibot container: `bot enable`, a visitor asks a KB question in Bangla and in English and gets the cited answer with the disclosure on the first message; "মানুষ চাই" and "talk to a human", an off-topic question, a complaint, and the fourth message all hand off (status open, label `ai-handoff`, team if set); AI down (fake stopped) hands off with reason `llm_error`; `bot disable` stops it; no message text in the aibot logs; client mode refuses to start without the paid flag. Add these rows to `opskit selftest`.
- **Acceptance:** all rows as expected in `opskit selftest`.

### [ ] 8.11 — Docs, verification, security review (written after 8.12 so the real-model result is in the report)
- **Goal:** `docs/runbooks/bot.md` (enable, KB filling, BYOK setup, going live gate, switching off), ADR for the bot design, ASSUMPTIONS, ENVIRONMENT, PROGRESS report; security review (key only in env files mode 600, never in logs/repr/errors; webhook auth; masked PII; SQLite on the host only; no inbound ports; the bot cannot be tricked into other topics by the prompt tests); upstream-path test still 0 files.
- **Acceptance:** `opskit/bin/check` passes; report written.

### [ ] 8.12 — Real-model check with the owner's key (only if the key is available in this environment)
- **Goal:** one real round trip with the owner's endpoint: `opskit llm models` lists the models, an embedding call works, one answer call returns valid JSON, then `opskit bot eval` on the fictional demo KB and test set against the real model, and the demo conversation flow once with the real model. Record the score and what failed. If no key or the host is blocked: skipped, listed as NOT VERIFIED, nothing else waits on it.
- **Acceptance:** the real-model score is recorded in PROGRESS and the runbook; the key never appears in output, logs or files in the repo.

## Not in this phase (on purpose)
Real-model scoring on the client's own KB (the demo KB is scored in 8.12), the V2 add-ons (order capture, booking, FAQ editor UI, agent assist, owner digest; only the extension points are built), learning from conversations, voice/images/attachments (the bot hands off on attachments it cannot read), Chatwoot Help Center import (optional later), pushing metrics to a hub, more than one bot per client.

## What I need from you
Nothing to start building. For the real-model check (8.12), when you are ready:
1. Open the cloud environment menu in the session title bar, then **Edit**.
2. Under API credentials (or Environment variables if there is no such section) add `AIBOT_LLM_API_KEY` = your key. **Never paste the key into this chat.**
3. Under **Network access**, choose Custom and add your AI provider's host (for example `api.openai.com`, or whatever host your OpenAI-compatible service uses) to the allowed domains, keeping the default package-manager list.
4. Tell me the **base URL** (not secret, e.g. `https://api.openai.com/v1`), the **chat model** name and the **embedding model** name you want to try. A **new session** picks up the key; I will say when to start one (all work is on GitHub, so nothing is lost).
Before a paying client goes live (not blocking the build): about 30 minutes to proofread the bot's Bangla messages, and your own `aibot eval` on the client's real KB.
