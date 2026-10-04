#!/usr/bin/env bats

setup() {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  export OPSKIT_CLIENTS_DIR="$BATS_TEST_TMPDIR/clients"
  mkdir -p "$OPSKIT_CLIENTS_DIR"
  "$OPSKIT_ROOT/bin/opskit" client new demo --domain chat.demo.localhost --name Demo --local >/dev/null 2>&1
  for l in log validate secrets render deploy alert_state health channels_health chatwoot_api notify channel_hints channels channels_social; do . "$OPSKIT_ROOT/lib/$l.sh"; done
  # network and docker are stubbed: every function below is the real checker logic
  _frontend_url() { echo "https://chat.demo.localhost:8443"; }
  _hc_now() { echo 1000000; }
  _runner() { :; }
}

out() { CH_FAILS=0 CH_WARNS=0 CH_PASSES=0; "$@" 2>&1; }

# ---- table, hints, exit codes ----------------------------------------------------------------------------------
@test "a FAIL row prints a plain fix hint, a PASS row does not" {
  run _row "Shop (email)" "incoming mail" FAIL "login rejected" email_auth
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"fix: The mail server rejected the login."* ]]
  [[ "$output" == *"APP PASSWORD"* ]]
  run _row "Shop (email)" "incoming mail" PASS "ok" email_auth
  [[ "$output" != *"fix:"* ]]
}

@test "counters and summary exit code follow the rows" {
  CH_FAILS=0 CH_WARNS=0 CH_PASSES=0
  _row a b PASS x >/dev/null; _row a b WARN x >/dev/null; _row a b FAIL x >/dev/null
  [ "$CH_PASSES" = 1 ] && [ "$CH_WARNS" = 1 ] && [ "$CH_FAILS" = 1 ]
}

@test "every hint key used by the checkers has text" {
  for k in widget_page widget_cable widget_roundtrip api_roundtrip email_auth email_connect email_tls email_timeout email_no_receive email_oauth email_not_seen tg_endpoint tg_mismatch tg_error tg_token tg_unreachable wa_provider wa_settings wa_handshake wa_open wa_token wa_number wa_unreachable meta_reauth meta_env meta_handshake no_checker; do
    [ -n "$(_ch_hint "$k")" ]
  done
}

@test "hints never contain secret-looking text" {
  for k in email_auth wa_token tg_token; do ! _ch_hint "$k" | grep -qiE 'password=|token=[A-Za-z0-9]{8}|AGE-SECRET'; done
}

# ---- Telegram ---------------------------------------------------------------------------------------------------
tg_json() { jq -n '{id:4,name:"Shop bot",channel_type:"Channel::Telegram",bot_name:"shop_bot"}'; }
tg_env() { _ch_status() { echo 200; }; _runner() { echo "SECRET=111:TOKENTOKENTOKENTOKENTOKEN"; }; }

@test "telegram: everything fine = all PASS" {
  tg_env
  _tg_api() { printf '200\n'; jq -n '{ok:true,result:{url:"https://chat.demo.localhost:8443/webhooks/telegram/111:TOKENTOKENTOKENTOKENTOKEN",pending_update_count:0}}'; }
  run out ch_telegram demo "$(tg_json)"
  [ "$(grep -c PASS <<<"$output")" -eq 4 ]
  [[ "$output" != *"FAIL"* ]]
  [[ "$output" != *"TOKENTOKEN"* ]]
}

@test "telegram: webhook pointing to another address is a FAIL that names the host, not the token" {
  tg_env
  _tg_api() { printf '200\n'; jq -n '{ok:true,result:{url:"https://old-server.example.com/webhooks/telegram/111:TOKENTOKENTOKENTOKENTOKEN"}}'; }
  run out ch_telegram demo "$(tg_json)"
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"old-server.example.com"* ]]
  [[ "$output" != *"TOKENTOKEN"* ]]
}

@test "telegram: a recent delivery error is a FAIL, an old one is not" {
  tg_env
  _tg_api() { printf '200\n'; jq -n --argjson d "$((1000000 - 60))" '{ok:true,result:{url:"https://chat.demo.localhost:8443/webhooks/telegram/111:TOKENTOKENTOKENTOKENTOKEN",last_error_message:"Wrong response from the webhook: 502",last_error_date:$d}}'; }
  run out ch_telegram demo "$(tg_json)"
  [[ "$output" == *"FAIL"*"last error: Wrong response"* ]]
  _tg_api() { printf '200\n'; jq -n --argjson d "$((1000000 - 200000))" '{ok:true,result:{url:"https://chat.demo.localhost:8443/webhooks/telegram/111:TOKENTOKENTOKENTOKENTOKEN",last_error_message:"old",last_error_date:$d}}'; }
  run out ch_telegram demo "$(tg_json)"
  [[ "$output" != *"FAIL"* ]]
}

@test "telegram: unreachable = WARN, rejected token = FAIL, endpoint down = FAIL" {
  tg_env
  _tg_api() { printf '000\n'; }
  run out ch_telegram demo "$(tg_json)"
  [[ "$output" == *"WARN"*"could not reach Telegram"* ]]
  [[ "$output" != *"FAIL"* ]]
  _tg_api() { printf '401\n{}'; }
  run out ch_telegram demo "$(tg_json)"
  [[ "$output" == *"FAIL"*"bot token rejected"* ]]
  _ch_status() { echo 502; }
  run out ch_telegram demo "$(tg_json)"
  [[ "$output" == *"FAIL"*"HTTP 502"* ]]
}

@test "telegram: unreadable token only skips Telegram's own view" {
  tg_env
  _runner() { :; }
  run out ch_telegram demo "$(tg_json)"
  [[ "$output" == *"WARN"*"skipped"* ]]
  [[ "$output" != *"FAIL"* ]]
}

# ---- WhatsApp ------------------------------------------------------------------------------------------------------
wa_json() { jq -n '{id:5,name:"Shop WA",channel_type:"Channel::Whatsapp",provider:"whatsapp_cloud",phone_number:"+8801700000001",provider_config:{api_key:"SECRETKEY123",phone_number_id:"111",business_account_id:"222",webhook_verify_token:"vtoken"}}'; }
wa_good() {
  _ch_secret_get() { case "$2" in *verify_token=vtoken*) sed -n 's/.*hub.challenge=\(.*\)$/\1/p' <<<"$2" ;; *) echo "" ;; esac; }
  _meta_get() { printf '200\n'; jq -n '{display_phone_number:"+880 1700-000001",verified_name:"Shop",quality_rating:"GREEN"}'; }
}

@test "whatsapp: complete settings, handshake and Meta view = all PASS" {
  wa_good
  run out ch_whatsapp demo "$(wa_json)"
  [ "$(grep -c " PASS " <<<"$output")" -eq 4 ]
  [[ "$output" != *"FAIL"* ]]
  [[ "$output" == *"24 hours"* ]]
  [[ "$output" != *"SECRETKEY123"* ]]
}

@test "whatsapp: missing settings are named, secrets are not shown" {
  wa_good
  run out ch_whatsapp demo "$(wa_json | jq 'del(.provider_config.business_account_id) | del(.provider_config.api_key)')"
  [[ "$output" == *"FAIL"*"missing: api_key business_account_id"* ]]
  [[ "$output" == *"fix: The WhatsApp settings are incomplete"* ]]
}

@test "whatsapp: wrong provider, bad phone number" {
  wa_good
  run out ch_whatsapp demo "$(wa_json | jq '.provider="default"')"
  [[ "$output" == *"FAIL"*"provider"* ]]
  run out ch_whatsapp demo "$(wa_json | jq '.phone_number="017-bad"')"
  [[ "$output" == *"missing: phone_number"* ]]
}

@test "whatsapp: a webhook that accepts any token is flagged as a security problem" {
  wa_good
  _ch_secret_get() { sed -n 's/.*hub.challenge=\(.*\)$/\1/p' <<<"$2"; }
  run out ch_whatsapp demo "$(wa_json)"
  [[ "$output" == *"FAIL"*"any token is accepted"* ]]
}

@test "whatsapp: handshake failure is a FAIL" {
  wa_good
  _ch_secret_get() { echo ""; }
  run out ch_whatsapp demo "$(wa_json)"
  [[ "$output" == *"FAIL"*"challenge not echoed"* ]]
}

@test "whatsapp: Meta view - expired token, unknown number, other number, unreachable" {
  wa_good
  _meta_get() { printf '400\n'; jq -n '{error:{code:190,message:"expired"}}'; }
  run out ch_whatsapp demo "$(wa_json)"
  [[ "$output" == *"FAIL"*"access token expired or invalid"* ]]
  _meta_get() { printf '404\n{}'; }
  run out ch_whatsapp demo "$(wa_json)"
  [[ "$output" == *"FAIL"*"phone number id not found"* ]]
  _meta_get() { printf '200\n'; jq -n '{display_phone_number:"+1 555 000 1111"}'; }
  run out ch_whatsapp demo "$(wa_json)"
  [[ "$output" == *"FAIL"*"differs"* ]]
  _meta_get() { printf '000\n'; }
  run out ch_whatsapp demo "$(wa_json)"
  [[ "$output" == *"WARN"*"could not reach Meta"* ]]
  [[ "$output" != *"FAIL"* ]]
}

# ---- Facebook / Instagram ----------------------------------------------------------------------------------------
ig_json() { jq -n '{id:7,name:"Shop IG",channel_type:"Channel::Instagram",reauthorization_required:false}'; }

@test "instagram: missing Meta app settings are named" {
  _runner() { printf 'PRESENT INSTAGRAM_APP_ID yes\nPRESENT INSTAGRAM_APP_SECRET no\nPRESENT INSTAGRAM_VERIFY_TOKEN no\n'; }
  run out ch_meta demo "$(ig_json)"
  [[ "$output" == *"FAIL"*"missing: INSTAGRAM_APP_SECRET INSTAGRAM_VERIFY_TOKEN"* ]]
}

@test "instagram: needs re-connection is a FAIL; good setup + handshake is PASS" {
  _runner() {
    case "$*" in
      *config_present*) printf 'PRESENT INSTAGRAM_APP_ID yes\nPRESENT INSTAGRAM_APP_SECRET yes\nPRESENT INSTAGRAM_VERIFY_TOKEN yes\n' ;;
      *config_value*) echo "SECRET=igtoken" ;;
    esac
  }
  _ch_secret_get() { case "$2" in *verify_token=igtoken*) sed -n 's/.*hub.challenge=\(.*\)$/\1/p' <<<"$2" ;; *) echo "" ;; esac; }
  run out ch_meta demo "$(ig_json)"
  [ "$(grep -c " PASS " <<<"$output")" -eq 3 ]
  run out ch_meta demo "$(ig_json | jq '.reauthorization_required=true')"
  [[ "$output" == *"FAIL"*"needs to be re-connected"* ]]
}

@test "facebook: a route that echoes a wrong token is a FAIL" {
  _runner() { case "$*" in *config_present*) printf 'PRESENT FB_APP_ID yes\nPRESENT FB_APP_SECRET yes\nPRESENT FB_VERIFY_TOKEN yes\n' ;; *config_value*) echo "SECRET=fbtoken" ;; esac; }
  _ch_secret_get() { sed -n 's/.*hub.challenge=\(.*\)$/\1/p' <<<"$2"; }
  run out ch_meta demo "$(jq -n '{id:8,name:"Shop FB",channel_type:"Channel::FacebookPage"}')"
  [[ "$output" == *"FAIL"*"a wrong token is accepted"* ]]
}

# ---- widget / API ------------------------------------------------------------------------------------------------------
@test "widget: all PASS, and the round trip failure is a FAIL" {
  _ch_status() { echo 200; }
  _ch_cable() { return 0; }
  widget_round_trip() { echo ok; }
  run out ch_widget demo "$(jq -n '{id:1,name:"Site",channel_type:"Channel::WebWidget",website_token:"tok"}')"
  [ "$(grep -c " PASS " <<<"$output")" -eq 4 ]
  widget_round_trip() { echo "the visitor's message was not accepted"; return 1; }
  run out ch_widget demo "$(jq -n '{id:1,name:"Site",channel_type:"Channel::WebWidget",website_token:"tok"}')"
  [[ "$output" == *"FAIL"*"visitor's message was not accepted"* ]]
}

@test "widget: missing token or dead page" {
  run out ch_widget demo "$(jq -n '{id:1,name:"Site",channel_type:"Channel::WebWidget"}')"
  [[ "$output" == *"FAIL"*"no website token"* ]]
  _ch_status() { echo 404; }; _ch_cable() { return 1; }; widget_round_trip() { echo x; return 1; }
  run out ch_widget demo "$(jq -n '{id:1,name:"Site",channel_type:"Channel::WebWidget",website_token:"tok"}')"
  [[ "$output" == *"FAIL"*"HTTP 404"* ]]
  [[ "$output" == *"FAIL"*"handshake failed"* ]]
}

@test "unknown channel types get a WARN, not a crash" {
  run out ch_unknown "$(jq -n '{name:"Line",channel_type:"Channel::Line"}')"
  [[ "$output" == *"WARN"*"not available yet"* ]]
}

# ---- orchestration ------------------------------------------------------------------------------------------------------
@test "channels_check: summary line and exit code 1 when anything FAILs" {
  cw_use_monitor() { return 0; }
  cw_request() { case "$2" in /api/v1/profile) echo '{"accounts":[{"id":1}]}' ;; *inboxes) echo '{"payload":[{"id":1,"name":"Odd","channel_type":"Channel::Line"},{"id":2,"name":"WA","channel_type":"Channel::Whatsapp","provider":"default"}]}' ;; esac; }
  run channels_check demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"Summary: 0 PASS, 1 WARN, 1 FAIL"* ]]
}

@test "channels_check: --inbox limits the run; no channels gives a pointer to the plan" {
  cw_use_monitor() { return 0; }
  cw_request() { case "$2" in /api/v1/profile) echo '{"accounts":[{"id":1}]}' ;; *inboxes) echo '{"payload":[{"id":1,"name":"Odd","channel_type":"Channel::Line"},{"id":2,"name":"Other","channel_type":"Channel::Sms"}]}' ;; esac; }
  run channels_check demo --inbox 2
  [[ "$output" == *"Other"* ]]
  [[ "$output" != *"Odd"* ]]
  cw_request() { case "$2" in /api/v1/profile) echo '{"accounts":[{"id":1}]}' ;; *inboxes) echo '{"payload":[]}' ;; esac; }
  run channels_check demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"opskit channels plan demo"* ]]
}

@test "channels_check: API down and missing monitoring user are clear errors" {
  cw_use_monitor() { return 1; }
  run channels_check demo
  [ "$status" -eq 1 ]; [[ "$output" == *"monitoring user"* ]]
  cw_use_monitor() { return 0; }
  cw_request() { return 1; }
  run channels_check demo
  [ "$status" -eq 1 ]; [[ "$output" == *"did not answer"* ]]
}

# ---- email with real pretend servers --------------------------------------------------------------------------------
mail_up() {
  python3 "$BATS_TEST_DIRNAME/fake_mail.py" "$BATS_TEST_TMPDIR/ports" "box@example.test" "good-pass" &
  MAIL_PID=$!
  for _ in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/ports" ] && break; sleep 0.1; done
  IMAP="$(jq -r .imap "$BATS_TEST_TMPDIR/ports")"; SMTP="$(jq -r .smtp "$BATS_TEST_TMPDIR/ports")"
}
mail_json() { # PASSWORD
  jq -n --arg pw "$1" --argjson i "$IMAP" --argjson s "$SMTP" '{id:3,name:"Support",channel_type:"Channel::Email",email:"box@example.test",provider:"",imap_enabled:true,imap_address:"127.0.0.1",imap_port:$i,imap_login:"box@example.test",imap_password:$pw,imap_enable_ssl:false,smtp_enabled:true,smtp_address:"127.0.0.1",smtp_port:$s,smtp_login:"box@example.test",smtp_password:$pw,smtp_enable_ssl_tls:false,smtp_enable_starttls_auto:false}'
}

@test "email: good logins PASS; wrong password FAILS with the app-password hint and never shows the password" {
  mail_up
  run out ch_email demo "$(mail_json good-pass)"
  [ "$(grep -c " PASS " <<<"$output")" -eq 2 ]
  run out ch_email demo "$(mail_json wrong-pw-12345)"
  kill "$MAIL_PID"
  [[ "$output" == *"FAIL"*"login rejected"* ]]
  [[ "$output" == *"APP PASSWORD"* ]]
  [[ "$output" != *"wrong-pw-12345"* ]]
}

@test "email: --send-test sends one message and finds it in the mailbox" {
  mail_up
  CH_SEND_TEST=1
  run out ch_email demo "$(mail_json good-pass)"
  kill "$MAIL_PID"
  [[ "$output" == *"PASS"*"test mail to itself"* ]] || [[ "$output" == *"test mail to itself"*"PASS"* ]]
}

@test "email: unreachable server = FAIL with the connection hint; no receive path = FAIL" {
  IMAP=9; SMTP=9
  run out ch_email demo "$(mail_json x)"
  [[ "$output" == *"FAIL"*"cannot connect"* ]]
  run out ch_email demo "$(mail_json x | jq '.imap_enabled=false')"
  [[ "$output" == *"neither IMAP nor forwarding is on"* ]] || [[ "$output" == *"FAIL"* ]]
  run out ch_email demo "$(jq -n '{id:3,name:"Support",channel_type:"Channel::Email",imap_enabled:false,smtp_enabled:false,forwarding_enabled:false}')"
  [[ "$output" == *"neither IMAP nor forwarding is on"* ]]
}

@test "email: Google/Microsoft inboxes use the re-authorization flag instead of a password test" {
  run out ch_email demo "$(jq -n '{id:3,name:"G",channel_type:"Channel::Email",provider:"google",reauthorization_required:true}')"
  [[ "$output" == *"FAIL"*"re-authorized"* ]]
  run out ch_email demo "$(jq -n '{id:3,name:"G",channel_type:"Channel::Email",provider:"google",reauthorization_required:false}')"
  [[ "$output" == *"PASS"* ]]
}
