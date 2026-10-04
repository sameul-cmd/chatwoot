# Runs inside the rails container (stdin to `rails runner -`). Idempotent: creates the first Super Admin + account
# only when no user with that email exists, then completes Chatwoot's first-run onboarding (clears the Redis flag).
email = ENV.fetch('ADMIN_EMAIL')
password = ENV.fetch('ADMIN_PASSWORD')
account_name = ENV.fetch('ACCOUNT_NAME')

if User.exists?(email: email)
  puts 'ADMIN_EXISTS'
else
  account = Account.first || Account.create!(name: account_name)
  user = User.new(name: 'Administrator', email: email, password: password, password_confirmation: password, type: 'SuperAdmin')
  user.skip_confirmation!
  user.save!
  AccountUser.create!(account: account, user: user, role: :administrator)
  puts 'ADMIN_CREATED'
end
Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)
