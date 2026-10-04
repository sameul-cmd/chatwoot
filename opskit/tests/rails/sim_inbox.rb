# TEST ONLY (selftest): a fake Google-style email inbox. ACTION=break -> credentials missing (Chatwoot then reports
# reauthorization_required); ACTION=fix -> credentials present again.
account = Account.first
channel = Channel::Email.find_by(email: 'sim-support@example.test')
if channel.nil?
  channel = Channel::Email.create!(account: account, email: 'sim-support@example.test', provider: 'google', provider_config: {})
  Inbox.create!(account: account, channel: channel, name: 'Simulated Support Email')
end
case ENV.fetch('ACTION')
when 'break'
  channel.update!(provider: 'google', provider_config: {})
  channel.prompt_reauthorization!
when 'fix'
  channel.update!(provider: 'google', provider_config: { 'access_token' => 'simulated' })
  channel.reauthorized!
end
puts "SIM_OK #{ENV.fetch('ACTION')}"
