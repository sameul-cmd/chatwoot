# Add-on menu and business model (research, 2026-10-04)

Status: **proposal for the owner to pick from. Nothing here is built or in the SPEC yet.** Difficulty is for us on top of the existing kit (E = days, M = 1-2 weeks, H = several weeks or needs outside approval).

## 1. White-label (Option 3), default OFF
Facts verified on v4.18.0 CE in the sandbox:
- Branding values (`INSTALLATION_NAME`, `BRAND_NAME`, `LOGO*`, `BRAND_URL`, `WIDGET_BRAND_URL`) are *locked* in CE: no Super Admin UI field.
- Environment variables do NOT override them on an initialised install (DB wins); tested.
- Changing the DB row (`InstallationConfig`) works and **survives `db:chatwoot_prepare`** (upgrade step); tested, then restored.
- The widget footer ("Powered by") reads `BRAND_NAME`, logo and `WIDGET_BRAND_URL`; hiding it entirely is the premium `disable_branding` flag (paid, enterprise) - we must NOT flip premium flags or touch `enterprise/`.
Proposed design: `client.yaml` gets `brand: {mode: chatwoot|custom, name, logo, logo_dark, url}`; `opskit brand apply <id> --dry-run` writes the rows through a Rails one-off (no code patch, no upstream edit, no ledger entry). Default `mode: chatwoot`.
Open (owner/legal, before the first paying client): MIT keeps copyright/licence notices; "Chatwoot" is Chatwoot Inc's trademark; Chatwoot sells white-label (Enterprise ~$99/agent/month cloud). Ask Chatwoot in writing and/or a lawyer.

## 2. How the money is made (service model, not a licence resale)
Self-hosted CE has no per-agent fee, while Chatwoot Cloud is about $19-$99 per agent per month and chatbot platforms are about $49-$149 per month. We sell a managed outcome instead: setup fee (channels + pack + bot KB), monthly care (hosting, backups, monitoring, upgrades, reports, change hours), bot tier (answers/month, languages), optional add-ons below. Validate prices with 3 real prospects before fixing them.

## 3. Add-on menu
| # | Add-on | Why clients pay | Difficulty | Needs from owner |
|---|---|---|---|---|
| A1 | White-label by data (above) | your brand on login/dashboard/widget/emails | E | legal check |
| A2 | Order capture in chat (name, phone, address, product, qty -> Google Sheet/CSV + Telegram ping + conversation attributes) | f-commerce sells in chat; saves retyping orders | M | Google account for demo |
| A3 | Order-status lookup (customer asks "my order?" -> bot reads sheet/Shopify/Woo) | cuts the most common question | M | sample sheet |
| A4 | Voice-note transcription (Bangla/English audio -> text note on the conversation, via the same BYOK endpoint) | voice notes are common; agents can read at a glance | M | your endpoint must support audio |
| A5 | Agent assist: draft reply, 2-line summary, Bangla<->English translation as private notes | faster agents; works even with bot off | E-M | BYOK key |
| A6 | Auto-label + anger/urgent flag (order, price, complaint, refund) | routing and reports without manual work | E | none |
| A7 | Owner digest on Telegram/WhatsApp (yesterday: chats, unanswered, bot handled, slow replies) | owner sees value daily; reduces churn | E | Telegram bot |
| A8 | Out-of-hours + missed-chat follow-up and CSAT/review request (Chatwoot built-ins, shipped in packs) | more leads kept, social proof | E | none |
| A9 | Lead/contacts sync to Google Sheets, HubSpot, Zoho via Chatwoot webhooks | agencies/small SaaS want CRM | E-M | CRM test account |
| A10 | Self-service KB editor (client edits FAQ, bot updates instantly) - listed V2 in SPEC | less support work for you, more stickiness | M-H | none |
| A11 | Appointment booking (clinic, travel, education: slots via Google Calendar/Cal.com + reminders) | clinics/consultants lose bookings in chat | M-H | calendar account |
| A12 | WhatsApp broadcast/reminder templates (Chatwoot campaigns + approved templates) | repeat sales, appointment reminders | M | Meta business account (client-owned) |
| A13 | bKash/Nagad payment-link or payment-status helper | closes the sale in chat | H | merchant API access |
| A14 | Facebook/Instagram comment-to-DM auto reply | f-commerce leads start in comments | H | Meta app review |
| A15 | Shared multi-account install for tiny clients (V2 in SPEC) | lower cost per client | H | decision + load testing |
| A16 | Bot analytics dashboard (V2 in SPEC) | proves ROI | M | none |

## 4. Suggested order (owner to confirm)
1. A1 white-label switch (default off)  2. A2 + A3 order capture/status (f-commerce first market)  3. A6 + A8 (cheap, instant value)  4. A7 owner digest  5. A5 agent assist  6. A4 voice notes  7. A10 KB editor  8. A11 booking. Everything uses the BYOK adapter and fake-LLM tests; none need Chatwoot code changes.

## Sources
- Chatwoot pricing 2026: https://www.eesel.ai/blog/chatwoot-pricing , https://www.featurebase.app/blog/chatwoot-pricing
- Chatwoot self-hosted vs paid, customization: https://achiya-automation.com/en/blog/chatwoot-pricing/ , https://www.chatwoot.com/hc/user-guide/articles/1750735898-purchasing-a-paid-self_hosted-chatwoot-license-a-step_by_step-guide (not readable from the sandbox)
- WhatsApp AI trends (order tracking, booking, CRM sync, handoff): https://timelines.ai/businesses-prepare-whatsapp-crm-trends-2026 , https://trengo.com/blog/best-whatsapp-chatbots
- Bangladesh f-commerce (Facebook/WhatsApp chat sales, bKash, Bangla/Banglish bots, pricing): https://chatdaddy.tech/blog/whatsapp-marketing-bangladesh , https://www.gappsy.com/tools/lazychat/
