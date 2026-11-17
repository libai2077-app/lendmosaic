#!/usr/bin/env ruby
require 'base64'
require 'fileutils'
require 'json'
require 'open3'
require 'securerandom'
File.umask(0o077)
STATE = File.join(ENV.fetch('RUNNER_TEMP'), 'ios-ci-signing')
SECURITY = '/usr/bin/security'
def run(*argv, input: '')
  out, err, status = Open3.capture3(*argv, stdin_data: input)
  unless status.success?
    # Only our validator's short error is safe to forward; never print command arguments.
    detail = err.lines.find { |line| line.start_with?('Profile validation failed:') }
    raise "#{File.basename(argv.first)} failed#{detail ? ': ' + detail.strip : ''}"
  end
  out
end
def cleanup
  return unless File.directory?(STATE)
  begin
    record = File.join(STATE, 'cleanup.json')
    data = File.file?(record) ? JSON.parse(File.read(record)) : {}
    Array(data['profiles']).each { |path| FileUtils.rm_f(path) }
    run(SECURITY, 'list-keychains', '-d', 'user', '-s', *data['keychains']) if data['keychains'] && !data['keychains'].empty?
    path = File.join(STATE, 'signing.keychain-db')
    run(SECURITY, 'delete-keychain', path) if File.exist?(path)
    FileUtils.rm_rf(STATE)
  ensure
    # Delete raw secrets even if a keychain command fails. Keep the cleanup manifest
    # on failure so the workflow's final cleanup can retry the keychain operation.
    FileUtils.rm_f(File.join(STATE, 'cert.p12'))
    FileUtils.rm_f(File.join(STATE, 'profile.mobileprovision'))
    FileUtils.rm_rf(File.join(STATE, 'private_keys'))
  end
end
begin
  raise 'Requires macOS' unless RUBY_PLATFORM.include?('darwin')
  if ARGV.first == 'cleanup'
    cleanup
    exit
  end
  raise 'Signing state exists; use a fresh hosted runner' if File.exist?(STATE)
  FileUtils.mkdir_p(STATE, mode: 0o700)
  cert = File.join(STATE, 'cert.p12')
  profile = File.join(STATE, 'profile.mobileprovision')
  File.binwrite(cert, Base64.strict_decode64(ENV.fetch('BUILD_CERTIFICATE_BASE64').gsub(/\s/, '')))
  File.binwrite(profile, Base64.strict_decode64(ENV.fetch('BUILD_PROVISION_PROFILE_BASE64').gsub(/\s/, '')))
  p = run(SECURITY, 'cms', '-D', '-i', profile)
  data = JSON.parse(run('python3', File.join(__dir__, 'validate-profile.py'), input: p))
  previous = run(SECURITY, 'list-keychains', '-d', 'user').lines.map { |s| s.strip.sub(/\A"/, '').sub(/"\z/, '') }
  record = {'keychains' => previous, 'profiles' => []}
  record_path = File.join(STATE, 'cleanup.json')
  File.write(record_path, JSON.generate(record))
  keychain = File.join(STATE, 'signing.keychain-db')
  password = SecureRandom.hex(32)
  run(SECURITY, 'create-keychain', '-p', password, keychain)
  run(SECURITY, 'set-keychain-settings', '-lut', '21600', keychain)
  run(SECURITY, 'unlock-keychain', '-p', password, keychain)
  run(SECURITY, 'import', cert, '-P', ENV.fetch('P12_PASSWORD'), '-f', 'pkcs12', '-k', keychain, '-T', '/usr/bin/codesign')
  run(SECURITY, 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain)
  run(SECURITY, 'list-keychains', '-d', 'user', '-s', keychain, *previous)
  matches = run(SECURITY, 'find-identity', '-v', '-p', 'codesigning', keychain).scan(/([A-F0-9]{40})\s+"Apple Distribution:/).flatten
  data['fingerprint'] = (matches & data['fingerprints']).first
  raise 'No private-key signing identity matches the profile certificates' unless data['fingerprint']
  ['~/Library/Developer/Xcode/UserData/Provisioning Profiles', '~/Library/MobileDevice/Provisioning Profiles'].each do |dir|
    FileUtils.mkdir_p(File.expand_path(dir))
    dest = File.join(File.expand_path(dir), "#{data['uuid']}.mobileprovision")
    raise 'Refusing to overwrite existing profile' if File.exist?(dest)
    record['profiles'] << dest
    File.write(record_path, JSON.generate(record))
    FileUtils.cp(profile, dest)
  end
  if ENV.fetch('UPLOAD_IPA') == 'true'
    id = ENV.fetch('ASC_KEY_ID')
    raise 'Invalid API Key ID' unless /\A[A-Za-z0-9]+\z/.match?(id)
    raise 'Missing API issuer' if ENV.fetch('ASC_ISSUER_ID').strip.empty?
    dir = File.join(STATE, 'private_keys')
    FileUtils.mkdir_p(dir, mode: 0o700)
    File.binwrite(File.join(dir, "AuthKey_#{id}.p8"), Base64.strict_decode64(ENV.fetch('ASC_PRIVATE_KEY_BASE64').gsub(/\s/, '')))
  end
  File.write(File.join(STATE, 'signing.json'), JSON.generate(data))
  puts 'Signing identity and profile installed.'
rescue StandardError => e
  warn "Signing setup failed: #{e.message}"
  exit 1
end
