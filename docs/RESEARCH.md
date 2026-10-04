# Research — Inbox Ops Kit (Chatwoot fork), 27 September 2026

> Background for `docs/SPEC.md`; not requirements. SPEC wins on conflicts. Re-check prices and policies before quoting.

## 1. Chatwoot today
- MIT-licensed Rails + Vue app; git-flow (`develop` base, `master`/`v*` tags stable); ~33.9k stars; latest release v4.15.1 (17 Jun 2026); ships `AGENTS.md`, `CLAUDE.md`, `.windsurf/rules`; includes an `enterprise/` directory; features: omnichannel inbox, help center, automations, reports, CSAT, integrations, Captain AI.
  Source: https://github.com/chatwoot/chatwoot
- Enterprise directory is under a separate commercial license requiring a paid subscription in production (SLAs, audit logs, agent capacity, branding, Captain).
  Sources: https://www.getmacha.com/blog/what-is-chatwoot · https://dev.to/beton/chatwoot-pricing-teardown-2026-a7g
- CE excludes Captain AI; paid self-hosted tiers (Premium Support $19, Enterprise $99/agent/month) add it; Chatwoot recommends ≥ 4 GB RAM / 2 cores.
  Source: https://www.eesel.ai/blog/chatwoot-pricing
- Cloud pricing: Hacker $0 (2 agents), Startups $19, Business $39, Enterprise $99 per agent/month; Captain credits extra.
  Source: https://www.eesel.ai/blog/chatwoot-pricing
- Branding removal is Enterprise-only.
  Source: https://www.featurebase.app/blog/chatwoot-pricing

## 2. Install & upgrade (official)
- Docker production: download `.env` + `docker-compose.production.yaml`, set secrets, `docker compose run --rm rails bundle exec rails db:chatwoot_prepare`, `up -d`, Nginx + certbot; CE edition uses equivalent `foss`/CE image tags.
  Source: https://developers.chatwoot.com/self-hosted/deployment/docker.md
- Upgrade: Linux VM `cwctl --upgrade`; Docker: pull + up + `db:chatwoot_prepare`.
  Source: https://developers.chatwoot.com/self-hosted/deployment/upgrade.md
- Official Docker Hub images are amd64-only (open request for arm64); community builds use `docker buildx --platform linux/amd64,linux/arm64 -f ./docker/Dockerfile`, reported working on Oracle Ampere.
  Sources: https://github.com/chatwoot/chatwoot/issues/9579 · https://github.com/orgs/chatwoot/discussions/9577

## 3. WhatsApp policy & costs
- From 15 Jan 2026 (new API users from 15 Oct 2025), Meta bans general-purpose AI chatbots on the WhatsApp Business Platform; business bots for support, FAQ, bookings, order tracking remain allowed.
  Sources: https://respond.io/blog/whatsapp-general-purpose-chatbots-ban · https://www.alibabacloud.com/help/en/chatapp/use-cases/whatsapp-ai-policy-2026-guide
- Bots must not pretend to be human; human handoff expected.
  Source: https://replypop.com/blog/whatsapp-2026-ai-policy-explained
- Since 1 Jul 2025 Meta bills per delivered template message; service replies within the 24-hour window are free.
  Source: https://www.lyron-ai.com/en/news/whatsapp-business-2026-ai-rules-costs/

## 4. Market
- Fiverr: basic VPS install $20 (explicitly no WhatsApp/FB/Instagram sync); full install + setup $130.
  Sources: https://www.fiverr.com/jayalyadav/deploy-chatwoot-chatbot-on-vps-elevate-customer-communication · https://www.fiverr.com/disignerpro/install-chatwoot-on-your-server-and-cutomization
- Self-hosting on a ~€8/month server is ~$96/year regardless of agents; WhatsApp webhooks require valid HTTPS.
  Source: https://ossalt.com/guides/self-hosting-guide-chatwoot-2026
