# Operator & Customer Flows — Inbox Ops Kit

> Derived from `docs/SPEC.md`. ⭐ = covered by `selftest` or an integration test.

### O1. Explore (Phase 0) ⭐
Fork → pin → CE docker install → super admin → widget/email/Telegram/WhatsApp test → features tour → agent-bot capture → backup/restore → report.

### O2. Onboard a client ⭐
`client new` → `channels plan` (client to-dos: Meta, DNS, mailbox) → `host bootstrap` → `deploy` → `pack apply --dry-run` → apply → KB draft from pack + client FAQs → `aibot eval` → connect channels → `channels check` → training call → go live.

### O3. Customer asks on WhatsApp (bot answers) ⭐
Inbound → bot discloses automation, answers from KB (bn/en) → customer satisfied or asks for human → handoff (open + label + team) → agent replies.

### O4. Bot unsure / off-topic ⭐
Low confidence or off-topic → polite handoff message → human takes over; question logged for KB to-do.

### O5. Night outage ⭐
Sidekiq down → critical alert (owner Telegram + client) → fix → resolved note → incident in care report.

### O6. Upgrade ⭐
Release notes → backup → staging on new image → smoke (login, widget round trip, sidekiq, bot) → off-hours prod → smoke → rollback if needed.

### O7. Disconnected Facebook/WhatsApp inbox
Channel poller flags → alert → runbook fix (reauthorize, token refresh) → `channels check` PASS.

### O8. Monthly report
Day 1 → report (volume, response times, CSAT, bot stats, uptime, backups) → emailed via ops-hub.

### O9. Offboard
Final backup → export → hand over → stop → delete after retention with approval.
