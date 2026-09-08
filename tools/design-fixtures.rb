# Generates synthetic data ONLY in the explicitly selected iOS simulator.
# ruby tools/design-fixtures.rb <simulator data.json> empty|realistic|crowded
require 'json'
require 'date'
require 'fileutils'

path, scenario = ARGV
abort 'Expected simulator data.json and empty|realistic|crowded' unless
  path&.include?('/Library/Developer/CoreSimulator/Devices/') &&
  path.end_with?('/Library/Application Support/haiity/data.json') &&
  %w[empty realistic crowded].include?(scenario)
today = Date.today
names = ['Read for twenty minutes', 'Drink water', 'Take a walk', 'No late coffee',
         'Stretch after work', 'Practice Spanish', 'Write a journal', 'Call family',
         'Learn something new', 'Go outside', 'Meditate', 'Plan tomorrow']
habits = names.first(scenario == 'empty' ? 0 : scenario == 'crowded' ? 12 : 3).each_with_index.map do |name, i|
  log = {}
  84.times do |offset|
    next if (offset + i) % 4 == 0
    log[(today - offset).iso8601] = i == 1 ? 3 : 1
  end
  log.delete(today.iso8601) if i == 0
  log[today.iso8601] = 1 if i == 1
  {
    id: format('00000000-0000-0000-0000-%012d', 700 + i), name: name, emoji: '',
    createdAt: (today - 84).iso8601, log: log,
    goal: i == 1 ? { freq: 'daily', target: 3 } : { freq: 'daily' },
    notificationMode: 'off', calendarSyncEnabled: false
  }
end
FileUtils.mkdir_p(File.dirname(path))
File.write(path, JSON.pretty_generate({ version: 2, updatedAt: Time.now.to_f, habits: habits,
  defaultTimeZoneIdentifier: 'Europe/Berlin' }))
puts "Generated #{scenario}: #{habits.length} synthetic habits"
