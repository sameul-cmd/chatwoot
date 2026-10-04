# Runbook: email inbox

**Status:** our side verified in the sandbox with pretend mail servers (login test, wrong-password FAIL with hint, one test mail to the mailbox itself). A real Gmail/Outlook/hosting mailbox: **not yet tried with a real account**.

## Pick the right method (important, rules changed)
| Mailbox | Method |
|---|---|
| Personal Gmail (@gmail.com) | App password (2-Step Verification must be on) |
| **Google Workspace** (own domain on Google) | **"Sign in with Google"** (OAuth). Google stopped allowing app passwords for Workspace accounts from 1 May 2025 |
| **Microsoft 365 / Outlook** | **"Sign in with Microsoft"** (OAuth); password sign-in is often disabled |
| Hosting/cPanel/other provider | IMAP + SMTP with the mailbox login and password |
| Cannot give access at all | Forwarding (the client forwards mail to the address shown in the inbox; needs the server's inbound email setting) |

## One-time per server (owner), only for OAuth methods
Create the Google and/or Microsoft sign-in app and set `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `GOOGLE_OAUTH_CALLBACK_URL` (and/or `AZURE_APP_ID`, `AZURE_APP_SECRET`) in the server settings (names exist in Chatwoot's `.env.example`; the exact console steps are in Google's/Microsoft's docs and **have not been walked through yet**).

## Steps
1. (Client) Decide the mailbox customers write to (e.g. support@shop.com). Give secrets only privately, never by chat or email.
2. (Us) Settings > Inboxes > Add Inbox > **Email**. Choose the method above and fill in the name and address.
3. IMAP/SMTP method: IMAP host (usually `imap.<provider>`, port 993, SSL on) and SMTP host (port 587 STARTTLS or 465 SSL/TLS), login = full address, password/app password.
4. (Client) Make sure SPF and DKIM exist for the sending address (the email provider shows the exact DNS records) so replies do not go to spam.
5. (Us) `opskit/bin/opskit channels check <id> --send-test`: IMAP and SMTP rows must say PASS, and "test mail to itself" PASS (it sends ONE message to the mailbox and deletes it).
6. (Client) Send a real email to the address; it must appear in Chatwoot; reply from Chatwoot and check it arrives (and is not in spam).

## Common problems
| Symptom | Fix |
|---|---|
| FAIL "login rejected" | wrong or revoked password; personal Gmail needs an APP password; Workspace/Microsoft: use sign-in with Google/Microsoft |
| FAIL "cannot connect" | wrong host or port, or the provider blocks the server's address |
| WARN/FAIL "TLS" | the SSL setting does not match the port (993 = SSL on, 143 = off; 465 = SSL/TLS, 587 = STARTTLS) |
| Test mail sent but not found | spam rules or different mailbox for SMTP and IMAP |
| "Needs re-authorization" alerts | the OAuth sign-in expired: the client presses Reauthorize in the inbox settings |

## Costs
None from Chatwoot. The client's email provider's own plan applies.

## Sources (not opened from the sandbox unless noted)
Google app passwords and Workspace change as summarised by web search results of 2026-10-04; official: Google Account Help "Sign in with app passwords"; Microsoft docs on basic authentication deprecation. **Verify on the official pages before relying on dates.**
