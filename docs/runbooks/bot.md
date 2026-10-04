# Runbook: the AI first-reply bot

**Status:** verified on a local demo stack with a **pretend AI** (answers in Bangla and English, handoffs, kill switch, eval harness). **Not yet tried with a real AI model or a real client.** The real-model score and the quality of real answers are NOT VERIFIED until you run `opskit bot eval` with your own key (task 8.12).

## What the bot does
A customer writes to the client's inbox; the bot answers first, **only from the client's own question list** (the KB). It says it is an automated assistant, answers in the customer's language, never invents prices or policies, and hands the chat to a person when unsure, when asked for a person, when the customer is upset, when the question is off-topic, after 3 bot replies, or when the AI service fails. A chat that is handed off is opened for people, labelled `ai-handoff`, assigned to the client's team if one is set, and gets a private note with the reason (never customer text).

## Who does what
- **Owner:** the AI service account and key (BYOK), proofreading the Bangla messages, the real `bot eval`.
- **Client:** writing the answers in the KB and the test questions.
- **Us:** the commands below.

## Steps
1. **AI key.** Create or use an AI service account (any OpenAI-compatible service) on a **paid** plan or one you own. Then run `opskit/bin/opskit llm set-key <id> --base-url https://<host>/v1 --paid` (the key is typed hidden, or taken from the `AIBOT_LLM_API_KEY` environment variable; it is stored only in `clients/<id>/llm.env`, mode 600). `--paid` is your statement that the key is paid-tier or owned by you or the client; without it a real client's bot refuses to start.
2. **Model.** `opskit llm models <id>` lists what the service offers; choose with `opskit llm model <id> <name>`. Optional: `opskit llm effort <id> none|low|medium|high|max` (default medium; if the service refuses a level the bot steps down by itself) and `opskit llm embedding-model <id> <name>` for smarter search (see below).
3. **KB.** Fill in `clients/<id>/kb/faq.yaml` (the pack copies a starter with empty answers; empty answers are ignored). Each entry has `question` and `answer` in `bn` and `en`, and `aliases`: other ways customers write it, such as Banglish ("delivery kobe", "dam koto"). Put facts the bot may state (prices, times, rules) **only** here: the bot refuses to say any number that is not in the entry it used. Extra notes can go in `kb/*.md`. After editing run `opskit bot reload <id>` (no restart needed).
4. **Test questions.** Write `clients/<id>/kb/eval.yaml` (see `aibot/demo/kb/eval.yaml`): at least 20 questions in Bangla, English and Banglish, including off-topic ones, "I want a human", complaints and traps (things the shop does not sell). Mark price/delivery/return/policy questions `critical: true`.
5. **Go-live gate.** `opskit bot eval <id>` runs the questions through the real bot and prints correct / handed off / wrong / wrong price-or-policy. **Gate: no wrong price/policy and at least 90% correct-or-handed-off.** Do not enable the bot on a paying client's inbox before this passes **with the real AI key**.
6. **Bangla messages.** The bot's own fixed messages (automation notice, handoff, off-topic) have draft Bangla texts. Until `bot.messages_bn_approved: true` is set in `client.yaml` (after you proofread them) a real client's customers get these messages in English. You can also write the client's own wording under `bot.messages`. Local practice stacks (demo mode) use the draft Bangla.
7. **Handoff team (optional).** Create a team in Chatwoot, then put its name in `client.yaml` as `bot.handoff_team`. `bot enable` looks the team up and stops if it does not exist.
8. **Switch on.** `opskit bot enable <id> --inbox N` (repeat `--inbox` for more). It registers the bot in Chatwoot, stores its token privately, restarts only the bot container and attaches it to the inboxes. Running it again changes nothing.
9. **Watch.** `opskit bot status <id>` shows health, attached inboxes and counts. `opskit bot unanswered <id>` lists the questions the bot could not answer, most asked first: add them to the KB (this list contains customer text: run it on your own machine only).
10. **Switch off.** `opskit bot disable <id>`: detaches the bot from every inbox, opens every chat still waiting for it so nobody is stranded, and tells the bot to stop. Chats then go straight to people. Switch on again with step 8.

## How search works
Keyword ranking (BM25) always runs. If an embedding model is set, the question is also embedded (one extra small AI call) and the two result lists are merged; if the embedding service fails, keyword ranking alone is used, and if keyword ranking finds nothing (different wording) the embedding result alone is used. Entries without an answer are never used.

## Privacy and safety
Customer text goes to your AI provider after phone numbers and emails are replaced by `[phone]` / `[email]` (names are not removed). Nothing customer-written is logged by the bot; the bot keeps a small database on the host (`audit_days`, default 30 days) with the question, answer, used entries and handoff reason for reports. The bot only replies to incoming customer messages, only on the inboxes you attach it to, and is never reachable from outside the client's own server network.

## Common problems
| Symptom | Fix |
|---|---|
| `bot enable`: "the AI service is not set up" / "no model chosen" | steps 1 and 2 |
| `bot enable`: "team ... does not exist" | create the team in Chatwoot or clear `bot.handoff_team` |
| Bot container keeps restarting | `docker compose -p <id> logs aibot`: most often the paid-tier statement is missing (`llm set-key ... --paid`) |
| Everything is handed off | the KB has no answers for those questions (look at `bot unanswered`), or the AI service is down (reason `llm_error` in the private note) |
| Customers get English handoff messages | the Bangla messages are not approved yet (step 6) |
| The AI service refuses `max` effort | automatic: the bot steps down to `high`, `medium`, `low` and remembers it |
| After a restore from backup | run `opskit bot enable <id> --inbox N` again; it reuses the existing Chatwoot bot |

## Not verified
A real AI model's answer quality and the real `bot eval` score; real WhatsApp/Facebook conversations; how Bangla customers react to the fixed messages; the bot under load; the Chatwoot team-assignment behaviour when the team has no agents.
