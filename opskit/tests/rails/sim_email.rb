# TEST ONLY (selftest): create or update a simulated email inbox pointing at pretend IMAP/SMTP servers on the host.
# ENV: INBOX_NAME, EMAIL, IMAP_PORT, SMTP_PORT, PASSWORD. Uses update_columns so Chatwoot does not try to log in from inside the container.
account = Account.first
channel = Channel::Email.find_by(email: ENV.fetch('EMAIL')) || Channel::Email.create!(account: account, email: ENV.fetch('EMAIL'))
channel.update_columns(
  imap_enabled: true, imap_address: '127.0.0.1', imap_port: ENV.fetch('IMAP_PORT').to_i, imap_login: ENV.fetch('EMAIL'),
  imap_password: ENV.fetch('PASSWORD'), imap_enable_ssl: false,
  smtp_enabled: true, smtp_address: '127.0.0.1', smtp_port: ENV.fetch('SMTP_PORT').to_i, smtp_login: ENV.fetch('EMAIL'),
  smtp_password: ENV.fetch('PASSWORD'), smtp_enable_ssl_tls: false, smtp_enable_starttls_auto: false
)
Inbox.find_by(channel: channel) || Inbox.create!(account: account, channel: channel, name: ENV.fetch('INBOX_NAME'))
puts "SIM_OK email #{ENV.fetch('EMAIL')}"
