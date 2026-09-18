require 'json'
require 'digest'
require 'xcodeproj'
require 'rexml/document'

root = File.expand_path('../../../..', __dir__)
baseline = File.join(root, 'docs/handoff/R3/CI21-CONFIG-01/verify_real_config.rb')
source = File.read(baseline)
old = "File.write(File.join(__dir__, 'ruby-config-results.json'), JSON.pretty_generate(report) + \"\\n\")"
replacement = "File.write(#{File.join(__dir__, 'ruby-config-baseline-results.json').inspect}, JSON.pretty_generate(report) + \"\\n\")"
raise 'Baseline report output not uniquely found' unless source.scan(old).length == 1
# Execute the original 15 real Config cases and exact current Podfile hook.
# Redirect only the report destination; never overwrite the frozen CI21 evidence.
eval(source.sub(old, replacement), TOPLEVEL_BINDING, baseline)
run_hook = TOPLEVEL_BINDING.local_variable_get(:execute)
installer, host, test, app, project = fixtures
voice = UserTarget.new('TinodiosVoiceLayoutTests', [ConfigTarget.new('Debug', {'OTHER_LDFLAGS' => 'VOICE_INHERITED_APP'})])
installer.aggregate_targets << Aggregate.new([voice], {'Debug' => real_config('-framework "FirebaseCore"')}, project)
run_hook.call(installer)
raise 'VLC hook modified the App-hosted target' unless voice.build_configurations.first.build_settings['OTHER_LDFLAGS'] == 'VOICE_INHERITED_APP'
raise 'VLC hook modified the App' unless app.build_configurations.first.build_settings['OTHER_LDFLAGS'] == 'APP_UNCHANGED'

project = Xcodeproj::Project.open(File.join(root, 'Tinodios.xcodeproj'))
target = project.targets.find { |t| t.name == 'TinodiosVoiceLayoutTests' }
raise 'Wrong target type' unless target && target.product_type == 'com.apple.product-type.bundle.unit-test'
raise 'Wrong source membership' unless target.source_build_phase.files_references.map(&:path) == ['VoiceLayoutTests.swift']
raise 'Duplicated App resources' unless target.resources_build_phase.files.empty?
raise 'Wrong host dependency' unless target.dependencies.map { |d| d.target.name } == ['Tinodios']
raise 'Missing App frameworks' unless target.frameworks_build_phase.files_references.map(&:path).sort == ['TinodeSDK.framework', 'TinodiosDB.framework'].sort
target.build_configurations.each do |config|
  raise 'Wrong host' unless config.build_settings['TEST_HOST'] == '$(BUILT_PRODUCTS_DIR)/Tinodios.app/Tinodios'
  raise 'Wrong loader' unless config.build_settings['BUNDLE_LOADER'] == '$(TEST_HOST)'
end
app = project.targets.find { |t| t.name == 'Tinodios' }
raise 'App source missing' unless app.source_build_phase.files_references.map(&:path).include?('SendMessageBar.swift')
raise 'App nib missing' unless app.resources_build_phase.files_references.map(&:path).include?('SendMessageBar.xib')
scheme = REXML::Document.new(File.read(File.join(root, 'Tinodios.xcodeproj/xcshareddata/xcschemes/Tinodios.xcscheme')))
names = REXML::XPath.match(scheme, '//Testables/TestableReference/BuildableReference').map { |e| e.attributes['BlueprintName'] }
raise 'Scheme lost original test targets' unless names.sort == %w[TinodiosUITests TinodiosVLCProbeTests TinodiosVoiceLayoutTests].sort
podfile = File.binread(File.join(root, 'Podfile')).gsub("\r\n", "\n")
lock = File.read(File.join(root, 'Podfile.lock'))
raise 'Podfile checksum mismatch' unless lock[/^PODFILE CHECKSUM: (\w+)$/, 1] == Digest::SHA1.hexdigest(podfile)
result = {
  'layer' => 'Actual portable Ruby/Xcodeproj object model and Config hook; not pod install or Xcode compilation',
  'ruby' => RUBY_DESCRIPTION, 'xcodeproj' => Gem.loaded_specs.fetch('xcodeproj').version.to_s,
  'baseline_config_cases' => 15, 'new_host_ignored_by_vlc_hook' => true,
  'target' => target.name, 'source_membership' => target.source_build_phase.files_references.map(&:path),
  'original_app_nib_source_preserved' => true, 'scheme_test_targets' => names,
  'podfile_sha1' => Digest::SHA1.hexdigest(podfile), 'status' => 'PASS'
}
File.write(File.join(__dir__, 'ruby-host-results.json'), JSON.pretty_generate(result) + "\n")
puts JSON.pretty_generate(result)
