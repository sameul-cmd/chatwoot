# Runbook: industry starter packs

**Status:** verified on a local demo stack (real Chatwoot v4.18.0): apply, re-apply, client edits kept, keyword rule fires. Not yet used on a real client. All Bangla texts are drafts marked "review needed" until you proofread them.

## What a pack is
A starter set for one kind of business, in Bangla and English: **saved replies** (agents type `/`), **labels**, **keyword rules** (a customer message with "দাম" or "price" gets the label `price`), **opening hours**, a **greeting**, an **after-hours message**, the **customer rating (CSAT)** switch, and a **starter question list** for the AI bot (answers left empty for the client).

Packs: `fcommerce` (online shop, the deepest one), `generic`, `clinic`, `travel`, `education`, `service`. They live in `opskit/packs/<industry>/`.

## Steps for a new client
1. (Us) The client's Chatwoot is running and at least one inbox exists (Phase 6 runbooks). Hours, greeting and the after-hours message are inbox settings, so they only reach inboxes that already exist.
2. (Us) See what would happen, nothing is changed:
   `opskit/bin/opskit pack apply <client> fcommerce --dry-run`
   Rows say CREATE, UPDATE, UNCHANGED, KEPT (the client edited it) or SKIPPED (Bangla not proofread).
3. (Owner) Proofread the Bangla: `opskit/bin/opskit pack review fcommerce` prints every Bangla text next to its English meaning. Tell the agent which ones are fine ("approved") or send the corrections. Approved texts are marked with `opskit pack approve fcommerce --key <key>` or `--all`.
4. (Us) Apply: `opskit/bin/opskit pack apply <client> fcommerce` (add `--include-unreviewed` only on demo or practice clients, never on a paying client's inbox). `--inbox 2` limits hours/greeting to one inbox.
5. (Us) Fill in the blanks agents will see in saved replies, such as `[delivery time]`, together with the client. Texts that are sent automatically never have blanks.
6. (Us + client) Fill in the answers in `clients/<id>/kb/faq.yaml` (copied once, never overwritten). The bot ignores questions with no answer.
7. (Us) Tell the client: chats are only tagged, not assigned. Once they have agents, add assignment under Settings > Automation.

## What a pack never does
- Never deletes anything and never touches items the client created.
- Never overwrites a text the client edited (shown as KEPT). A newer pack text is applied only to items the client has not touched.
- Contains no prices, delivery times, return rules, payment numbers or digits at all (a test enforces it).
- Keeps a small file `clients/<id>/pack-state.json` (hashes only, no text) to recognise client edits.

## Good to know
- Running apply twice changes nothing ("0 to create, 0 to update").
- Keyword rules tag a chat when **any** message in it contains one of the words, including a team member's reply (Chatwoot rules cannot say "customer messages only" together with several words).
- Default hours are every day 10:00-20:00 in the client's timezone; change them in the inbox settings and the pack will keep your change.
- The after-hours message and greeting contain both languages (the client's main language first).

## Common problems
| Symptom | Fix |
|---|---|
| "unknown industry" | the message lists the valid names |
| "could not read the client's Chatwoot" | the stack is not running or the admin token is missing: `opskit client check <id>` |
| "Chatwoot refused it: ..." | the reason is printed; fix it and run apply again (finished items are not repeated) |
| Many SKIPPED rows | Bangla not proofread: see step 3 |
| A text keeps showing KEPT | the client edited it; that is intended |

## Not verified
Real clients, real Facebook/WhatsApp conversations, how the Bangla reads to a native speaker, how a client's own existing setup looks (only the demo was tried).
