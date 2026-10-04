#!/usr/bin/env bash
# Plain-language fix hints for the channel checker, one place. Hints never contain secrets.
# shellcheck shell=bash

_ch_hint() {
  case "$1" in
    widget_page) echo "The chat widget page does not load. Check that the client's domain opens over HTTPS and that the website token in the embed code matches the inbox (Settings > Inboxes)." ;;
    widget_cable) echo "Live updates (WebSocket) do not work through the proxy. Check the Caddy config and that port 443 passes WebSocket traffic." ;;
    widget_roundtrip) echo "A visitor cannot start a chat. Check the services (opskit monitor status) and the Rails logs: docker compose -p <id> logs rails." ;;
    api_roundtrip) echo "The API inbox could not receive a test message. Check the inbox identifier and the Rails logs." ;;
    email_auth) echo "The mail server rejected the login. Personal Gmail needs an APP PASSWORD (2-Step Verification on); Google Workspace and Microsoft 365 no longer accept passwords: use 'Sign in with Google/Microsoft' instead. For other providers check the login and that IMAP/SMTP is switched on, then save the inbox settings again." ;;
    email_connect) echo "Cannot connect to the mail server. Check the host name and port (IMAP SSL 993, SMTP 587 STARTTLS or 465 SSL/TLS) and that the mail provider allows connections from this server." ;;
    email_tls) echo "TLS/SSL problem. Use the SSL setting that matches the port (993 = SSL on, 143 = off; 465 = SSL/TLS, 587 = STARTTLS) and make sure the mail server's certificate is valid for that host name." ;;
    email_timeout) echo "The mail server did not answer in time. Check the host name, port and any firewall; try again in a few minutes." ;;
    email_no_receive) echo "This email inbox cannot receive mail. Switch on IMAP in the inbox settings, or set up forwarding (MAILER_INBOUND_EMAIL_DOMAIN + the inbox's forwarding address)." ;;
    email_oauth) echo "This mailbox signs in through Google/Microsoft; the login test is skipped. If Chatwoot reports re-connection is needed, re-authorize the inbox." ;;
    email_not_seen) echo "The test mail was accepted by the outgoing server but did not appear in the mailbox. Check spam/filters, that SMTP and IMAP belong to the same mailbox, and the 'From' address rules of the provider." ;;
    tg_endpoint) echo "Chatwoot's Telegram webhook address does not answer. Check that HTTPS works (valid certificate, port 443 open, the domain points to this server)." ;;
    tg_mismatch) echo "Telegram is sending messages to a different address than this server. Open the inbox in Chatwoot and save it again (or remove and re-add the bot) so Telegram is updated." ;;
    tg_error) echo "Telegram says it cannot deliver messages to this server (see the error). Fix HTTPS/domain, then save the inbox again." ;;
    tg_token) echo "Telegram rejected the bot token (revoked or wrong). Create or refresh the token with @BotFather and update the inbox." ;;
    tg_unreachable) echo "This server could not reach Telegram, so Telegram's own view was not checked. Check the server's internet access." ;;
    wa_provider) echo "Only the official WhatsApp Cloud API is supported (provider whatsapp_cloud). Never use QR-code connectors." ;;
    wa_settings) echo "The WhatsApp settings are incomplete. In the client's Meta Business account copy the missing values (phone number id, business account id, access token) into the inbox settings." ;;
    wa_handshake) echo "Meta's webhook verification would fail. The webhook URL in the Meta app must be exactly the one shown in the inbox settings, and the verify token must match." ;;
    wa_open) echo "The webhook accepts ANY verify token. That is a security problem: update Chatwoot or investigate before using this inbox." ;;
    wa_token) echo "Meta rejected the access token (expired or revoked). Create a permanent System User token in Meta Business and update the inbox." ;;
    wa_number) echo "Meta does not know this phone number id, or it differs from the number saved here. Check 'WhatsApp > API setup' in the Meta app." ;;
    wa_unreachable) echo "This server could not reach Meta, so Meta's own view was not checked. Check the server's internet access." ;;
    meta_reauth) echo "Chatwoot says this channel must be re-connected: open the inbox settings and click Reauthorize (the client's Facebook/Instagram admin must log in)." ;;
    meta_env) echo "The Meta app settings are missing on this server. Add them in Super Admin > Settings (see docs/runbooks/facebook-instagram.md)." ;;
    meta_handshake) echo "The Meta webhook verification route accepts a wrong token or does not answer. Check the Meta app settings and the server's HTTPS." ;;
    no_checker) echo "There is no automatic check for this channel type yet." ;;
    *) echo "" ;;
  esac
}
