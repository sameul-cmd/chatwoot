# Sends one test email through the configured SMTP settings via Sidekiq (deliver_later), proving both.
subject = ENV.fetch('TEST_SUBJECT')
ActionMailer::Base.mail(from: ENV.fetch('MAILER_SENDER_EMAIL'), to: ENV.fetch('TEST_TO'), subject: subject, body: 'opskit post-deploy check').deliver_later
puts 'QUEUED'
