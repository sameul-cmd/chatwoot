# Phase 7 — Industry starter packs, Bangla + English (Improvement 7)

Spec: SPEC Section 12, Section 17 (Phase 7), `.claude/CLAUDE.md` "Packs & channels rules".
**Accept (from SPEC):** applying `fcommerce` to a fresh demo account creates the listed items; re-applying changes nothing; client-made items are untouched; Bangla texts flagged `review_required` until the owner approves.

## What this phase is, in plain words
A new client's inbox starts empty. A "pack" is a ready-made starter set for one kind of business (online shop on Facebook/WhatsApp, clinic, travel agency, school, service business, or a generic one): **saved replies** (agents type `/` and pick one), **labels** (tags like "order", "price"), **automatic rules** (a customer writes "price" or "দাম" and the chat is tagged), **opening hours with an after-hours auto-reply**, a **greeting**, and a **starter question-and-answer list** the bot will use in Phase 8. One command, `opskit pack apply <client> <industry>`, shows what it would add (a "dry run"), then adds it. Running it twice changes nothing, and it never deletes or overwrites what the client made. Every text exists in Bangla and English. I draft the Bangla; **you** (native speaker) proofread it, and until you approve it the text is marked "review needed".

## Facts this phase relies on (read from Chatwoot v4.18.0 code, 2026-10-04; to be re-checked live in 7.1)
- **Saved replies** (`/api/v1/accounts/:id/canned_responses`): fields `short_code` and `content`; `short_code` is unique per account. Easy to make idempotent.
- **Labels** (`/labels`): `title` (unique per account), `description`, `color`, `show_on_sidebar`. Easy to make idempotent.
- **Automation rules** (`/automation_rules`): `name`, `description`, `event_name`, `active`, `conditions[]`, `actions[]` (e.g. `add_label`, `assign_team`, `assign_agent`, `send_message`). **Names are not unique**, so the pack puts a fixed tag in the name (`[opskit:fcommerce] ...`) and finds its own rules by that tag.
- **Opening hours, greeting and after-hours message** are **per inbox** settings (`PATCH /inboxes/:id`: `working_hours_enabled`, `working_hours[]`, `timezone`, `out_of_office_message`, `greeting_enabled`, `greeting_message`, `csat_survey_enabled`), not separate objects. So they only apply to inboxes that already exist (Phase 6 created them).
- Saved replies and messages can contain Chatwoot variables such as `{{contact.name}}`; unknown variables are sent as-is, so the pack uses only known ones.
- The `pack` field and a small `pack.schema.json` already exist from Phase 1 (item list only) and need extending.
- Our own earlier finding: through Caddy the API header must be `api-access-token`; the monitor/admin API user from Phase 4 can be reused for writes (needs administrator).

## Open questions for the owner (plain words; defaults in bold)
**Owner answered 2026-10-04: all 8 defaults accepted.**
1. **Which packs.** I write **f-commerce (online shop selling through Facebook/WhatsApp/Instagram) in full depth**, plus `generic`, and **lighter versions of clinic, travel, education, service** (about 8 saved replies, 5 labels, 2 rules each) that you can ask me to deepen when you get a real client in that field.
2. **How Bangla and English share saved replies.** An agent should see both languages. **Default:** every item becomes two saved replies, `/order_ask_bn` and `/order_ask_en` (endings `_bn` / `_en`), only for the languages the client has in `client.yaml`.
3. **Bangla not yet proofread.** **Default:** `pack apply` lists unproofread Bangla in the dry run and refuses to apply it to a client unless you add `--include-unreviewed`; the demo and selftest use that flag. A new command `opskit pack review <industry>` prints all Bangla texts on one page for you to proofread; when you tell me "approved", I flip the flags.
4. **No made-up facts.** Packs contain **no prices, delivery times, return rules or payment numbers**. Where a saved reply needs a business fact, it shows a blank like `[delivery time]` for the agent to fill in before sending (saved replies are drafts an agent reads first). **Texts that are sent automatically (after-hours message, greeting) never contain blanks**; a test enforces that.
5. **Which inboxes get hours and greeting.** **Default:** all of the client's inboxes; `--inbox <id>` limits it. Shops in Bangladesh keep different weekly holidays, so the default hours are **every day 10:00–20:00 in the client's timezone**, and the dry run reminds you to adjust them in the inbox settings.
6. **If the client already changed a pack item.** **Default:** `pack apply` remembers what it last wrote (a small file in the client folder). If the live text differs from that, the client edited it: it is **left alone** and shown as "kept (client edited)". Updated pack texts (a newer pack version) are applied only to items the client has not edited.
7. **Assigning chats to people.** The SPEC mentions "auto-assign by inbox", but the pack cannot know the client's agents or teams. **Default:** packs do **not** assign; instead the rules tag chats, and `pack apply` prints a one-line hint on how to add assignment in Chatwoot (Settings > Automation) once the client has agents. (V2 can ask for a team name in `client.yaml`.)
8. **Starter Q&A list for the bot.** **Default:** the pack ships `kb_starter/` with the questions every business of that type gets (opening hours, how to order, delivery, payment, returns...) and **empty answers**. `pack apply` copies it to the client's `kb/` folder only if that folder has no file yet; the bot (Phase 8) ignores questions with empty answers, so it can never answer from something nobody wrote.

## Tasks

### [x] 7.1 — Verify the facts live, fix the data format
- **Goal:** on a running demo account: create one saved reply, label, automation rule (keyword → `add_label`) and set inbox hours/greeting through the API; confirm field names, uniqueness errors, the `contains` operator with `query_operator: OR`, behaviour of an unknown action, and what a `PATCH` of working hours does to unspecified days. Record in EXPLORATION_REPORT.
- **Acceptance:** findings written; the exact JSON for each call saved as fixtures in `opskit/tests/fixtures/`.

### [x] 7.2 — Pack format and schemas
- **Goal:** `opskit/packs/<industry>/` files exactly as in SPEC Section 12 (`canned_responses.yaml`, `labels.yaml`, `automations.yaml`, `business_hours.yaml`, `auto_replies.yaml`, `kb_starter/*.yaml`) plus `pack.yaml` (industry, version, description, languages). Extend `pack.schema.json` (or one schema per file) with `review_required` per Bangla text. Validation reuses `lib/schema_check.py`; `opskit pack validate [industry]`.
- **Acceptance:** valid packs pass; a pack with a missing Bangla/English text, an unknown automation action, a bad short code or a blank inside an automatic text fails with the field name.

### [x] 7.3 — `generic` and `fcommerce` packs (drafts, bn + en)
- **Goal:** write the two packs: saved replies (greeting, ask order details, order confirmed, payment instructions blank, delivery info blank, out of stock, price enquiry, thanks, handoff to human...), labels (order, price, complaint, delivery, payment, return, vip), keyword rules (order/অর্ডার, price/দাম, delivery/ডেলিভারি, complaint words → label), hours, greeting, after-hours message, CSAT on, `kb_starter`. All Bangla `review_required: true`; no prices or policies.
- **Acceptance:** `pack validate` passes; test: no automatic text has a blank; no digits that look like prices.

### [x] 7.4 — The four lighter packs
- **Goal:** `clinic` (appointment request, opening hours, doctor availability blank, emergency notice "call your local emergency number" without medical advice), `travel`, `education`, `service`, each as in question 1.
- **Acceptance:** `pack validate` passes for all six; clinic texts contain no medical advice (checked by review in the verification report).

### [x] 7.5 — `opskit pack apply <id> <industry> [--dry-run] [--inbox N] [--include-unreviewed]`
- **Goal:** new `opskit/lib/pack.sh` (+ a small Python/jq helper for the diff): reads the pack, reads the live account through `lib/chatwoot_api.sh`, builds a plan (create / update / kept-client-edited / unchanged / skipped-unreviewed), prints it as a table, and only writes when not `--dry-run`. Writes: saved replies by short code, labels by title, rules by name tag, inbox hours/greeting for the chosen inboxes. Remembers what it wrote in `clients/<id>/pack-state.json` (git-ignored; hashes only, no message text from customers). Never calls a delete endpoint.
- **Acceptance:** first apply creates everything; second apply says "0 changes"; an item the client edited or created is untouched.

### [x] 7.6 — Safety rules in `pack apply`
- **Goal:** the dry run is shown first and a real apply to a **live** client (not the local demo) asks for typed client id, as other live changes do; refuses `shared_accounts` (V2); needs the admin API token and says so plainly if missing; Bangla not reviewed → refused without the flag; unknown industry → lists the valid ones.
- **Acceptance:** bats covers each refusal and message.
- **Built differently:** only local-target clients exist until Phase 11, so there is no typed-id step yet (A-034); unproofread Bangla is skipped per item rather than refusing the whole apply (A-030).

### [x] 7.7 — `opskit pack review <industry>` and `pack approve`
- **Goal:** `pack review` prints every Bangla text with its key and the English meaning side by side as one Markdown page; `pack approve <industry> [--key K | --all]` sets `review_required: false` (used only after the owner says "approved").
- **Acceptance:** output readable on a phone; approve changes only the flags.

### [x] 7.8 — Starter Q&A copy (`kb_starter`)
- **Goal:** `pack apply` copies `kb_starter/*` to `clients/<id>/kb/` only when absent and says where it went; prints a reminder "fill in the answers, the bot ignores empty ones".
- **Acceptance:** second run does not overwrite edited files.

### [x] 7.9 — Tests
- **Goal:** bats with a fake Chatwoot API (extend the existing fake) for: plan building, idempotency, client-edited items kept, deletion never called, `--inbox`, review gate; schema tests from 7.2.
- **Acceptance:** all pass in `opskit/bin/check`.

### [x] 7.10 — Live acceptance and selftest v6
- **Goal:** on the demo stack: `pack apply demo fcommerce --dry-run`, apply, re-apply (0 changes), edit one saved reply and add one of our own in the Chatwoot API, re-apply (both untouched), send a visitor message "দাম কত?" through the widget and see the conversation get the `price` label. Add these steps to `opskit selftest`.
- **Acceptance:** all rows as expected; the keyword-label row proves a rule really fires, not just that it was created.

### [x] 7.11 — Docs, verification, security review
- **Goal:** `docs/runbooks/packs.md` (how to apply, review Bangla, what is never touched); PROGRESS/ASSUMPTIONS/ENVIRONMENT; verification report; check that no customer text, token or password is printed or stored in `pack-state.json`; upstream-path test still 0 files.
- **Acceptance:** `opskit/bin/check` passes; report written.

## Not in this phase (on purpose)
Per-client edits of pack texts through a UI (agents edit in Chatwoot itself), assignment rules, the bot's use of the Q&A list (Phase 8), more industries, Bangla proofreading (you), anything that deletes client data.

## What I need from you
Reply **"all defaults ok"** or give the question numbers you want changed. Nothing else is needed to start. Later (not blocking): about 20 minutes to proofread the Bangla page from `pack review fcommerce` once it exists.
