require 'json'
require 'digest'
require 'stringio'
require 'xcodeproj/config'
# Real Config + exact Podfile hook; only project/target containers are adapted.
root = File.expand_path('../../../..', __dir__)
podfile = File.read(File.join(root, 'Podfile'))
start = podfile.index('  probe_targets = %w[TinodiosVLCProbeHost TinodiosVLCProbeTests]')
finish = podfile.index('  # See explanation here:', start)
raise 'Hook extraction failed' unless start && finish && podfile.scan('  probe_targets = %w[').length == 1
hook = podfile[start...finish]
HOST = 'TinodiosVLCProbeHost'
TEST = 'TinodiosVLCProbeTests'
NAMES = %w[MobileVLCKit Kingfisher SQLite SwiftKeychainWrapper].freeze
ConfigTarget = Struct.new(:name, :build_settings)
UserTarget = Struct.new(:name, :build_configurations)
Aggregate = Struct.new(:user_targets, :xcconfigs, :user_project)
Installer = Struct.new(:aggregate_targets)
ProjectAdapter = Struct.new(:saves) do
  def save; self.saves += 1; end
end
def real_config(extra = '')
  Xcodeproj::Config.new('OTHER_LDFLAGS' => '$(inherited) -ObjC ' +
    NAMES.map { |name| %Q[-framework "#{name}"] }.join(' ') + ' ' + extra)
end
def fixtures(host_config = real_config, test_config = real_config)
  project = ProjectAdapter.new(0)
  app = UserTarget.new('Tinodios', [ConfigTarget.new('Debug', { 'OTHER_LDFLAGS' => 'APP_UNCHANGED' })])
  host = UserTarget.new(HOST, [ConfigTarget.new('Debug', {}), ConfigTarget.new('Release', {})])
  test = UserTarget.new(TEST, [ConfigTarget.new('Debug', {}), ConfigTarget.new('Release', {})])
  installer = Installer.new([
    Aggregate.new([app], { 'Debug' => real_config('-framework "FirebaseCore"') }, project),
    Aggregate.new([host], { 'Debug' => host_config, 'Release' => host_config }, project),
    Aggregate.new([test], { 'Debug' => test_config, 'Release' => test_config }, project)])
  [installer, host, test, app, project]
end
results = []
record = lambda { |name, &body| body.call; results << { 'name' => name, 'result' => 'PASS' } }
execute = lambda do |installer|
  previous = $stdout
  output = StringIO.new
  begin
    $stdout = output
    eval(hook, binding, 'Podfile actual probe hook', podfile[0...start].count("\n") + 1)
  ensure
    $stdout = previous
  end
  output.string.lines.map(&:strip)
end
reject = lambda do |installer, text|
  begin
    execute.call(installer)
    raise 'Expected hook failure did not occur'
  rescue KeyError, RuntimeError => error
    raise error unless error.message.include?(text)
  end
end
record.call('old_attributes_fetch_reproduces_KeyError') do
  config = real_config
  raise 'Dedicated field unexpectedly in attributes' if config.attributes.key?('OTHER_LDFLAGS')
  begin
    config.attributes.fetch('OTHER_LDFLAGS')
    raise 'Old failure missing'
  rescue KeyError
  end
  raise 'Serialization lost frameworks' unless config.to_hash.fetch('OTHER_LDFLAGS').include?('MobileVLCKit')
end
record.call('actual_hook_preserves_all_serialized_linker_categories') do
  config = real_config('-weak_framework "Metal" -l"c++" @"/tmp/synthetic.args" -force_load "/tmp/synthetic.a"')
  installer, host, test, app, project = fixtures(config, config)
  log = execute.call(installer)
  flags = host.build_configurations.first.build_settings.fetch('OTHER_LDFLAGS')
  raise 'Serialized flags changed' unless flags == config.to_hash.fetch('OTHER_LDFLAGS').gsub('$(inherited)', '').strip
  parsed = Xcodeproj::Config.new('OTHER_LDFLAGS' => flags).other_linker_flags
  raise 'Categories lost' unless parsed[:weak_frameworks].include?('Metal') && parsed[:libraries].include?('c++') &&
    parsed[:simple].include?('-ObjC') && !parsed[:arg_files].empty? && !parsed[:force_load].empty?
  raise 'App changed' unless app.build_configurations.first.build_settings['OTHER_LDFLAGS'] == 'APP_UNCHANGED'
  raise 'Wrong save count' unless project.saves == 1
  raise 'Missing config observations' unless log.length == 4
end
record.call('nonempty_search_path_test_keeps_frameworks') do
  installer, host, test = fixtures
  execute.call(installer)
  raise 'Test frameworks discarded' unless test.build_configurations.all? { |c|
    NAMES.all? { |name| c.build_settings.fetch('OTHER_LDFLAGS').include?(name) } }
end
record.call('inherited_only_test_explicitly_clears_parent') do
  config = Xcodeproj::Config.new('OTHER_LDFLAGS' => '$(inherited)')
  raise 'Fixture must omit serialized key' if config.to_hash.key?('OTHER_LDFLAGS')
  installer, host, test = fixtures(real_config, config)
  execute.call(installer)
  raise 'Parent not cleared' unless test.build_configurations.all? { |c| c.build_settings['OTHER_LDFLAGS'] == '' }
end
record.call('empty_real_test_config_proves_six_empty_categories') do
  installer, host, test = fixtures(real_config, Xcodeproj::Config.new)
  execute.call(installer)
  raise 'Empty config not isolated' unless test.build_configurations.all? { |c| c.build_settings['OTHER_LDFLAGS'] == '' }
end
record.call('empty_host_rejected') { reject.call(fixtures(Xcodeproj::Config.new)[0], 'Missing VLC probe linker flags') }
record.call('host_required_framework_missing_rejected') do
  reject.call(fixtures(Xcodeproj::Config.new('OTHER_LDFLAGS' => '-ObjC -framework "MobileVLCKit"'))[0], 'Missing VLC host framework')
end
record.call('missing_configuration_rejected') do
  installer = fixtures[0]; installer.aggregate_targets[1].xcconfigs.delete('Release')
  reject.call(installer, 'key not found')
end
record.call('non_Config_rejected') { reject.call(fixtures({})[0], 'Invalid VLC probe configuration') }
record.call('Firebase_rejected') { reject.call(fixtures(real_config('-framework "FirebaseCore"'))[0], 'Unexpected application dependency') }
record.call('test_WebRTC_rejected') { reject.call(fixtures(real_config, real_config('-framework "WebRTC"'))[0], 'Unexpected application dependency') }
record.call('malformed_empty_categories_rejected') do
  config = Xcodeproj::Config.new; config.other_linker_flags[:unknown] = Set.new
  reject.call(fixtures(real_config, config)[0], 'Missing VLC probe linker flags')
end
record.call('missing_test_target_rejected') do
  installer = fixtures[0]; installer.aggregate_targets.pop
  reject.call(installer, 'VLC probe target configuration incomplete')
end
record.call('test_concrete_simple_flags_retained') do
  installer, host, test = fixtures(real_config, Xcodeproj::Config.new('OTHER_LDFLAGS' => '-ObjC'))
  execute.call(installer)
  raise 'Simple flag discarded' unless test.build_configurations.first.build_settings['OTHER_LDFLAGS'] == '-ObjC'
end
record.call('both_inherited_spellings_removed') do
  installer, host, test = fixtures(real_config, Xcodeproj::Config.new('OTHER_LDFLAGS' => '${inherited} $(inherited)'))
  execute.call(installer)
  raise 'Inheritance survived' unless test.build_configurations.first.build_settings['OTHER_LDFLAGS'] == ''
end
source = $LOADED_FEATURES.find { |name| name.end_with?('/xcodeproj/config.rb') }
report = {
  'layer' => 'Actual local Ruby / actual Xcodeproj Config + exact Podfile hook; project containers adapted; not Mac/CocoaPods install',
  'ruby' => RUBY_DESCRIPTION, 'xcodeproj_gem_version' => Gem::Specification.find_by_name('xcodeproj', '1.28.1').version.to_s,
  'configSourceSHA256' => Digest::SHA256.file(source).hexdigest,
  'hookSHA256' => Digest::SHA256.hexdigest(hook), 'results' => results,
  'passed' => results.length, 'total' => 15
}
File.write(File.join(__dir__, 'ruby-config-results.json'), JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
