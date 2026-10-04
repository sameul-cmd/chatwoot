# TEST ONLY (selftest): create SIMULATED Telegram / WhatsApp inboxes without calling Telegram or Meta
# (the sandbox cannot reach them; Chatwoot hard-codes their URLs). The credentials below are fake.
# ACTION = telegram | whatsapp | whatsapp_broken ; prints SIM_OK <action> <inbox id>
account = Account.first

case ENV.fetch('ACTION')
when 'telegram'
  Channel::Telegram.skip_callback(:validation, :before, :ensure_valid_bot_token)
  Channel::Telegram.skip_callback(:save, :before, :setup_telegram_webhook)
  ch = Channel::Telegram.find_by(bot_token: '123456:SIMULATEDTOKENxxxxxxxxxxxxxxxxxxxxx') ||
       Channel::Telegram.create!(account: account, bot_token: '123456:SIMULATEDTOKENxxxxxxxxxxxxxxxxxxxxx', bot_name: 'demo_sim_bot')
  inbox = Inbox.find_by(channel: ch) || Inbox.create!(account: account, channel: ch, name: 'Simulated Telegram')
when 'whatsapp', 'whatsapp_broken'
  Channel::Whatsapp.skip_callback(:create, :after, :sync_templates)
  Channel::Whatsapp.skip_callback(:commit, :after, :setup_webhooks)
  broken = ENV['ACTION'] == 'whatsapp_broken'
  phone = broken ? '+8801700000002' : '+8801700000001'
  cfg = { 'api_key' => 'SIMULATED-ACCESS-TOKEN', 'phone_number_id' => '111111111111111', 'webhook_verify_token' => "verify-#{phone[-1]}-token" }
  cfg['business_account_id'] = '222222222222222' unless broken
  ch = Channel::Whatsapp.find_by(phone_number: phone)
  unless ch
    ch = Channel::Whatsapp.new(account: account, phone_number: phone, provider: 'whatsapp_cloud', provider_config: cfg)
    ch.save!(validate: false)
  end
  inbox = Inbox.find_by(channel: ch) || Inbox.create!(account: account, channel: ch, name: broken ? 'Simulated WhatsApp (incomplete)' : 'Simulated WhatsApp')
end
puts "SIM_OK #{ENV.fetch('ACTION')} #{inbox.id}"
