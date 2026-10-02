#!/usr/bin/env ruby
require_relative 'verification'
require 'stringio'
require 'tmpdir'

checks = 0
rejected = lambda do |&block|
  previous_stderr = $stderr
  $stderr = StringIO.new
  begin
    block.call
  rescue SystemExit => error
    raise 'Rejected input exited successfully' if error.success?
    checks += 1
  else
    raise 'Invalid evidence was accepted'
  ensure
    $stderr = previous_stderr
  end
end

valid = { 'result' => 'Passed', 'failedTests' => 0, 'skippedTests' => 0, 'passedTests' => 2_068 }
raise 'Valid summary failed' unless checked_summary(valid, '/tmp/unit.xcresult', 2_000)['passed'] == 2_068
[
  { 'result' => 'Failed' }, { 'failedTests' => 1 }, { 'skippedTests' => 1 },
  { 'passedTests' => 0 }, { 'passedTests' => 1_999 }, { 'passedTests' => nil }
].each do |change|
  rejected.call { checked_summary(valid.merge(change), '/tmp/unit.xcresult', 2_000) }
end
rejected.call { checked_summary({}, '/tmp/missing.xcresult', 4) }

current = { 'commit' => 'abc', 'fingerprint' => '123', 'xcode' => 'Xcode 27',
            'sdk' => '27.0', 'xcodegen' => 'Version: 2.46.0', 'version' => '1.0.0', 'build' => '269' }
check_identity(current, current)
current.each_key do |key|
  rejected.call { check_identity(current.merge(key => 'changed'), current) }
end
rejected.call { check_identity({}, current) }
rejected.call { JSON.parse('{"Mehr":1,"Mehr":2}', object_class: UniqueJSONKeys) }

# Exercise the real Git/file fingerprint without touching the user's checkout.
Dir.mktmpdir('haiity-evidence-test.') do |dir|
  Dir.chdir(dir) do
    run('git', 'init', '--quiet')
    Dir.mkdir('Haiity')
    File.write('Haiity/Localizable.xcstrings', '{"strings":{}}')
    File.write('Haiity/input.swift', 'before')
    run('git', 'add', 'Haiity')
    baseline = fingerprint
    File.write('Haiity/input.swift', 'after')
    raise 'Changed source kept its fingerprint' if fingerprint == baseline
    File.write('Haiity/input.swift', 'before')
    raise 'Restored bytes changed the fingerprint' unless fingerprint == baseline
    File.write('Haiity/new.swift', 'untracked input')
    raise 'Untracked build input was ignored' if fingerprint == baseline
  end
end

puts "Release evidence checks passed (#{checks} rejection cases; changed/untracked source detected)."
