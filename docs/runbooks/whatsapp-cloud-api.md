# Runbook: WhatsApp (official Cloud API)

**Status:** our side verified in the sandbox with a simulated inbox (settings, Meta's verification handshake, wrong token refused, pretend-Meta status). The real walk-through with a Meta test number: **pending the owner's Meta account** (the sandbox cannot reach Meta). Only the official Cloud API is used; QR-code tools (WAHA, Evolution, etc.) are never used.

## Who owns what
The **client** owns the Meta Business account, the phone number and the bill. We set it up with them. Never create these accounts in our name.

## Before you start (client)
- A Meta Business account (business.facebook.com) in the business's own name; Meta may require **business verification** (documents) for higher limits and to message anyone.
- A phone number that is **not registered in any WhatsApp or WhatsApp Business app** (delete that account first if it is) and can receive an SMS/voice code.
- A payment method in Meta Business (see costs).

## Steps
1. (Us + client) developers.facebook.com > create an app, type **Business**; add the **WhatsApp** product; link the client's Meta Business account.
2. (Client) WhatsApp > API setup: add the phone number and verify it with the code. Note the **Phone number ID** and the **WhatsApp Business Account ID** shown on that page.
3. (Client) Business Settings > Users > **System users**: add a system user, give it the app (Manage app) and the WhatsApp account (Manage WhatsApp Business accounts); generate a **permanent token** with `whatsapp_business_management` and `whatsapp_business_messaging` (and `whatsapp_business_manage_events` if offered). The temporary token from the API setup page lasts only 24 hours: do not use it. Give the token to us privately.
4. (Us) Settings > Inboxes > Add Inbox > **WhatsApp**, provider **WhatsApp Cloud**: phone number (+country code), phone number ID, business account ID, API key (the token). Chatwoot generates a **webhook verify token** and shows the **webhook URL** (`<server address>/webhooks/whatsapp/<phone number>`).
5. (Us) In the Meta app: WhatsApp > Configuration > Webhook: paste exactly that **callback URL** and the **verify token**, click Verify, then subscribe to the `messages` field.
6. (Us) `opskit/bin/opskit channels check <id>`: settings, handshake, "wrong token refused" and "Meta's own view" must say PASS.
7. (Client) Send a WhatsApp message to the business number from another phone; it must appear in Chatwoot; reply.
8. Templates: to message a customer first, or after 24 hours, create and get **approved message templates** in WhatsApp Manager.

## Rules the bot (Phase 8) and agents must respect
Business topics only; the bot says it is automated and never claims to be human; hand over to a person when unsure. Reply within 24 hours of the customer's last message; afterwards only approved templates.

## Costs (billed by Meta to the client's account, never by us)
Meta charges **per message**, by category (marketing, utility, authentication, service) and country. Reported change: **from 1 October 2026 Meta also charges service messages and utility messages inside an open 24-hour window** (from web search results, not confirmed on Meta's own page from the sandbox). Check Meta's pricing page before quoting prices: https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing

## Common problems
| Symptom | Fix |
|---|---|
| Meta "Verify" fails | callback URL not exactly as in the inbox, or HTTPS problem; verify token differs |
| FAIL "access token expired or invalid" | a temporary token was used, or the system user lost access: create a permanent token |
| FAIL "Meta's number differs" | wrong phone number ID in the inbox |
| Messages to customers fail after 24 h | use an approved template |
| "Phone number already registered" | remove it from the WhatsApp app first (this deletes that chat history) |

## Sources
Meta: WhatsApp Business Platform "Get started" https://developers.facebook.com/documentation/business-messaging/whatsapp/get-started (opened only through search summaries); web-search summaries of 2026-10-04 for the token/permission steps. **Walk through with a real Meta test number and correct this page.**
