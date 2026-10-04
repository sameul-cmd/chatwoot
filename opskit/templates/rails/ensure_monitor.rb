# Runs inside the rails container (stdin to `rails runner -`). Idempotent: creates the read-mostly monitoring user
# (administrator, so it can list every inbox) once and prints its API token. The login password is random and
# discarded: nobody logs in as this user; only the API token is used.
email = ENV.fetch('MONITOR_EMAIL')
user = User.find_by(email: email)
unless user
  password = "#{SecureRandom.hex(16)}-Aa1!"
  account = Account.first
  user = User.new(name: 'Ops Monitor', email: email, password: password, password_confirmation: password)
  user.skip_confirmation!
  user.save!
  AccountUser.create!(account: account, user: user, role: :administrator)
end
puts "MONITOR_TOKEN=#{user.access_token.token}"
