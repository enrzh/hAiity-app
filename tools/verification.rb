#!/usr/bin/env ruby
require 'digest'
require 'json'
require 'open3'
require 'yaml'

class UniqueJSONKeys < Hash
  def []=(key, value)
    abort("Duplicate JSON key: #{key}") if key?(key)
    super
  end
end

def run(*args)
  text, error, status = Open3.capture3(*args)
  abort(error) unless status.success?
  text.strip
end

def fingerprint
  JSON.parse(File.read('Haiity/Localizable.xcstrings'), object_class: UniqueJSONKeys)
  paths = run('git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split("\0").sort
  digest = Digest::SHA256.new
  paths.each do |path|
    next unless path.match?(%r{\A(Haiity/|HaiityWidget/|HaiityTests/|HaiityUITests/|TestPlans/|tools/|ci_scripts/|Haiity\.xcodeproj/|project\.yml\z|\.xcodegen-version\z|Haiity\.storekit\z)})
    digest << path << "\0" << (File.file?(path) ? File.binread(path) : '<missing>') << "\0"
  end
  digest.hexdigest
end

def identity
  settings = YAML.load_file('project.yml').fetch('targets').fetch('Haiity').fetch('settings').fetch('base')
  {
    'commit' => run('git', 'rev-parse', 'HEAD'), 'fingerprint' => fingerprint,
    'xcode' => run('xcodebuild', '-version'),
    'sdk' => run('xcrun', '--sdk', 'iphoneos', '--show-sdk-version'),
    'xcodegen' => run(ENV.fetch('XCODEGEN_BIN', File.executable?('.ci-tools/xcodegen') ? '.ci-tools/xcodegen' : 'xcodegen'), '--version'),
    'version' => settings.fetch('MARKETING_VERSION').to_s,
    'build' => settings.fetch('CURRENT_PROJECT_VERSION').to_s
  }
end

def checked_result(path, floor)
  summary = JSON.parse(run('xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', path))
  checked_summary(summary, path, floor)
end

def checked_summary(summary, path, floor)
  passed = summary['passedTests']
  unless summary['result'] == 'Passed' && summary['failedTests'] == 0 && summary['skippedTests'] == 0 && passed.is_a?(Integer) && passed >= floor
    abort("Verification failed or incomplete: #{path}")
  end
  { 'path' => File.expand_path(path), 'passed' => summary.fetch('passedTests') }
end

def check_identity(evidence, current)
  current.each { |key, value| abort("Verification no longer matches #{key}; run tools/verify.sh") unless evidence[key] == value }
end

if $PROGRAM_NAME == __FILE__
  case ARGV.shift
  when 'fingerprint'
    puts fingerprint
  when 'record'
    expected, unit, smoke = ARGV
    abort('Sources changed during verification') unless fingerprint == expected
    evidence = identity.merge('unit' => checked_result(unit, 2_000), 'smoke' => checked_result(smoke, 4))
    puts JSON.pretty_generate(evidence)
  when 'check'
    evidence = JSON.parse(File.read(ARGV.fetch(0)))
    check_identity(evidence, identity)
    checked_result(evidence.fetch('unit').fetch('path'), 2_000)
    checked_result(evidence.fetch('smoke').fetch('path'), 4)
    puts "Verified #{evidence.fetch('commit')} / #{evidence.fetch('version')} (#{evidence.fetch('build')})"
  else
    abort('Usage: verification.rb fingerprint | record FINGERPRINT UNIT_RESULT SMOKE_RESULT | check EVIDENCE')
  end
end
