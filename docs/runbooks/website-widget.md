# Runbook: website chat bubble (widget)

**Status:** our side verified in the sandbox (`opskit channels check`: page, script, live updates, a real visitor round trip). Adding it to a real website: not yet tried on a real client site.

## Who does what
- **Us:** create the inbox, copy the embed code, test.
- **Client (or their web person):** paste the code into their website.

## Steps
1. (Us) In Chatwoot: Settings > Inboxes > Add Inbox > **Website**. Enter the client's website address and a name; choose a colour, welcome text and the client's logo. (Their business name and colours show in the bubble; "Powered by Chatwoot" stays unless the owner decides otherwise, see `docs/ADDONS.md`.)
2. (Us) Add the team members who answer, then copy the **embed code** shown at the end (a short `<script>` block).
3. (Client) Paste the code **once per page template** just before `</body>`: WordPress = a header/footer scripts plugin; Shopify = theme.liquid or custom code; Wix/Squarespace = "custom code" settings. Or send it to their web developer.
4. (Us) `opskit/bin/opskit channels check <id>`: the widget rows must say PASS (page, embed script, live updates, visitor message round trip).
5. (Client) Open the website, click the bubble, send a message. It must appear in Chatwoot within seconds.

## Common problems
| Symptom | Fix |
|---|---|
| Bubble does not appear | the code is not on that page, or a cache plugin serves an old page: clear the cache |
| Bubble appears but messages do not arrive | `channels check` shows which row fails; if "live updates" fails check Caddy/WebSocket (`docs/runbooks/monitoring.md`) |
| Browser console says blocked / mixed content | the website is on http but the chat is on https: put the website on https |
| Works on the demo page but not on the real site | the real site has a strict "Content Security Policy": the client's web person must allow the chat domain |

## Costs
None from Chatwoot or Meta.

## Facts checked in code
Visitor session: `POST /api/v1/widget/config?website_token=...` returns the visitor token; messages go to `POST /api/v1/widget/messages` (Chatwoot 4.18.0).
