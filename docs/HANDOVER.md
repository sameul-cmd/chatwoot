# Handover - continuing on another device

Everything is in git. Nothing else needs to be copied except secrets you create yourself.

## 1. Get the code
1. Install: Git, Docker (Desktop on Windows with WSL2, or Docker Engine on Linux), and Claude Code (optional, to keep working the same way).
2. `git clone https://github.com/sameul-cmd/chatwoot.git` then `git checkout claude/wizardly-babbage-ui2rpa`.
3. Read `docs/PROGRESS.md` (what is done) and `README-START-HERE.md`.

## 2. Set up tools (once)
- Linux / WSL2 Ubuntu: `sudo apt install shellcheck bats gettext-base jq age rclone python3-pip` and `pip install jsonschema pyyaml`; install `uv` (https://docs.astral.sh/uv) and yq (mikefarah).
- Check: `opskit/bin/opskit doctor` (lists anything missing), then `opskit/bin/check --quick` (should end with ALL CHECKS PASSED).

## 3. Things only you can test (need your accounts) - collect results in `docs/EXPLORATION_REPORT.md`
| Item | What you need | Phase |
|---|---|---|
| Telegram inbox round trip | a Telegram bot token (@BotFather) | 0 / 6 |
| Email inbox (IMAP/SMTP) | a test mailbox | 0 / 6 |
| WhatsApp Cloud API | Meta developer account + test number | 0 / 6 |
| Facebook / Instagram | Meta app + a test page | 0 / 6 |
| Mobile app login | phone + ngrok | 0 |
| Bengali UI language | browser check in Chatwoot profile settings | 0 |
| Real LLM answers | your OpenAI-compatible endpoint + key (BYOK) in the aibot env, never in git | 8 |
| Real server run | a VPS + domain | 11 |

## 4. Secrets
Never commit `.env`, keys, `opskit/clients/`, `opskit/hosts/`. The sandbox test passwords were throw-away and are gone with the sandbox.
