# Runbook: Facebook Messenger and Instagram

**Status:** our side verified in the sandbox only for the checker logic (unit tests: re-connection flag, missing app settings, verification handshake). The Meta app setup and app review: **not yet tried** (needs the owner's Meta developer account; the sandbox cannot reach Meta).

## Important: this is the hardest channel
On a self-hosted Chatwoot **we** must create the Meta app, set its keys on the server and pass **Meta's app review** before messages from the public arrive. Until the app is approved/live, Meta only delivers messages from people who have a role on the app (testers). Plan days to weeks for review.

## One time per server (owner)
1. developers.facebook.com > create an app (Business). Add products **Facebook Login** and **Messenger**; for Instagram also the **Instagram** product.
2. Put these in Chatwoot's Super Admin > Settings (or the server `.env`): Facebook: `FB_APP_ID`, `FB_APP_SECRET`, `FB_VERIFY_TOKEN` (you choose a long random string); Instagram via Facebook Page: `IG_VERIFY_TOKEN`; Instagram login: `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET`, `INSTAGRAM_VERIFY_TOKEN`.
3. In the Meta app > Webhooks: Facebook (Page) callback `<server address>/bot` with `FB_VERIFY_TOKEN`; Instagram callback `<server address>/webhooks/instagram` with the Instagram verify token. Add the app domain.
4. Request the permissions needed for messaging (Messenger pages messaging; Instagram messaging) through **App Review** and switch the app to **Live**.

## Per client
1. (Client) The person connecting must be a full **admin of the Facebook Page**; for Instagram: a **Professional** (Business/Creator) account linked to that Page.
2. (Us) Settings > Inboxes > Add Inbox > Messenger / Instagram: "Continue with Facebook", the client logs in and allows everything.
3. (Us) `opskit/bin/opskit channels check <id>`: connection, Meta app settings and webhook verification rows must say PASS.
4. (Client) Send a Messenger/Instagram message to the page from a personal account that is a tester (or any account after the app is live).

## Common problems
| Symptom | Fix |
|---|---|
| FAIL "Meta app settings: missing ..." | set the named keys in Super Admin > Settings |
| FAIL "needs to be re-connected" | the client's login token expired or permissions were removed: Reauthorize in the inbox |
| FAIL "wrong token is accepted" / handshake fails | verify token mismatch or Chatwoot setting missing |
| Page connected but no messages | app still in Development mode, or review not approved |
| Instagram messages missing | the account is not Professional or not linked to the Page |

## Costs
Messenger/Instagram messaging itself has no per-message fee; Meta rules about the 24-hour window and message tags apply.

## Sources
Chatwoot self-hosted docs (opened only through search summaries): https://developers.chatwoot.com/self-hosted/configuration/features/integrations/facebook-channel-setup , https://developers.chatwoot.com/self-hosted/configuration/features/integrations/instagram-channel-setup , https://developers.chatwoot.com/self-hosted/configuration/features/integrations/instagram-via-instagram-business-login . **Walk through with the owner's Meta developer account and correct this page.**
