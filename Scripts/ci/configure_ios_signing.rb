#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'

def required_env(name)
  value = ENV[name]
  if value.nil? || value.empty?
    warn "Missing required environment variable: #{name}"
    exit 1
  end
  value
end

team_id = required_env('APPLE_TEAM_ID')
app_bundle_id = required_env('APP_BUNDLE_ID')
extension_bundle_id = required_env('EXTENSION_BUNDLE_ID')
app_profile_name = required_env('APP_PROFILE_NAME')
extension_profile_name = required_env('EXTENSION_PROFILE_NAME')

project = Xcodeproj::Project.open('Tinodios.xcodeproj')

target_settings = {
  'Tinodios' => {
    'PRODUCT_BUNDLE_IDENTIFIER' => app_bundle_id,
    'PROVISIONING_PROFILE_SPECIFIER' => app_profile_name
  },
  'TinodiosNSExtension' => {
    'PRODUCT_BUNDLE_IDENTIFIER' => extension_bundle_id,
    'PROVISIONING_PROFILE_SPECIFIER' => extension_profile_name
  }
}

target_settings.each do |target_name, settings|
  target = project.targets.find { |candidate| candidate.name == target_name }
  unless target
    warn "Could not find Xcode target: #{target_name}"
    exit 1
  end

  target.build_configurations.each do |configuration|
    build_settings = configuration.build_settings
    build_settings['CODE_SIGN_STYLE'] = 'Manual'
    build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
    build_settings['DEVELOPMENT_TEAM'] = team_id
    build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = settings['PRODUCT_BUNDLE_IDENTIFIER']
    build_settings['PROVISIONING_PROFILE_SPECIFIER'] = settings['PROVISIONING_PROFILE_SPECIFIER']
  end
end

project.save

puts "Configured manual signing:"
puts "  Tinodios -> #{app_bundle_id} / #{app_profile_name}"
puts "  TinodiosNSExtension -> #{extension_bundle_id} / #{extension_profile_name}"
