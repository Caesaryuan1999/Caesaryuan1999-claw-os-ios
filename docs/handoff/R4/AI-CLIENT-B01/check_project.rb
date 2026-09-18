require 'json'
require 'xcodeproj'

project = Xcodeproj::Project.open('Tinodios.xcodeproj')
membership = project.targets.to_h do |target|
  [target.name, target.source_build_phase.files_references.map(&:path).grep(/Assistant/).sort]
end.reject { |_name, files| files.empty? }
expected = {
  'Tinodios' => %w[ClawAssistantModels.swift ClawAssistantService.swift ClawAssistantSession.swift
    ClawAssistantHistory.swift ClawAssistantViewController.swift ClawAssistantHistoryViewController.swift
    ClawAssistantConversationViewController.swift ClawAssistantRun.swift ClawAssistantStream.swift].sort,
  'TinodiosVoiceLayoutTests' => %w[AssistantHistoryTests.swift AssistantLayoutTests.swift
    AssistantRunTests.swift AssistantStreamTests.swift].sort
}
raise 'Unexpected Assistant source membership' unless membership == expected
puts JSON.pretty_generate({ scope: 'Real Xcodeproj parser; not Swift/Xcode build/link',
  ruby: RUBY_VERSION, xcodeproj: Gem.loaded_specs.fetch('xcodeproj').version.to_s,
  membership: membership, pass: true })
