# Runs inside the rails container (stdin to `rails runner -`). READ-ONLY. Prints only what the channel checker needs;
# the caller keeps secrets in shell variables and never logs them.
#   ACTION=telegram_token INBOX_ID=<n>          -> SECRET=<bot token>   (Chatwoot does not expose it through the API)
#   ACTION=config_present NAMES=A,B,C           -> PRESENT <name> yes|no (only allow-listed names)
#   ACTION=config_value NAME=<allow-listed>     -> SECRET=<verify token>
ALLOWED_NAMES = %w[FB_APP_ID FB_APP_SECRET FB_VERIFY_TOKEN IG_VERIFY_TOKEN INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET INSTAGRAM_VERIFY_TOKEN].freeze
VALUE_NAMES = %w[FB_VERIFY_TOKEN IG_VERIFY_TOKEN INSTAGRAM_VERIFY_TOKEN].freeze

case ENV.fetch('ACTION')
when 'telegram_token'
  channel = Inbox.find(ENV.fetch('INBOX_ID')).channel
  puts "SECRET=#{channel.bot_token}" if channel.is_a?(Channel::Telegram)
when 'config_present'
  ENV.fetch('NAMES').split(',').each do |name|
    next unless ALLOWED_NAMES.include?(name)

    puts "PRESENT #{name} #{GlobalConfigService.load(name, '').to_s.empty? ? 'no' : 'yes'}"
  end
when 'config_value'
  name = ENV.fetch('NAME')
  abort('name not allowed') unless VALUE_NAMES.include?(name)
  puts "SECRET=#{GlobalConfigService.load(name, '')}"
end
