# Uncomment the next line to define a global platform for your project
platform :ios, '14.0'

# Share one SQLite.swift runtime across the app, TinodiosDB and XCTest.
# Separate static copies have different DispatchSpecificKey instances: passing
# a Connection across those modules can trap on nested queue.sync calls.
use_frameworks! :linkage => :dynamic

# ignore all warnings from all pods
inhibit_all_warnings!

# The Swift pod `FirebaseCoreInternal` depends upon `GoogleUtilities`, which does not define modules. To opt into those targets generating module maps (which is necessary to import them from Swift when building as static libraries), you may set `use_modular_headers!` globally in your Podfile, or specify `:modular_headers => true` for particular dependencies.
# use_modular_headers!

workspace 'Tinodios'

project 'Tinodios'
project 'TinodeSDK'


def db_pods
  pod 'SQLite.swift', '~> 0.15'
  pod 'SwiftKeychainWrapper', '~> 3'
end

target 'TinodeSDKTests' do
  project 'TinodeSDK'
end

target 'TinodiosDB' do
    project 'TinodiosDB'
    db_pods
end

def app_pods
  use_modular_headers!
  pod 'Firebase'
  pod 'FirebaseCore'
  pod 'FirebaseMessaging'
  pod 'FirebaseAnalytics'
  pod 'FirebaseCrashlytics'
  pod 'Kingfisher', '~> 5'
  pod 'MobileVLCKit', '~> 3'
  pod 'PhoneNumberKit', '~> 4'
  pod 'WebRTC-lib', '~> 139.0.0'
end

# UI tests.
target 'TinodiosUITests' do
    project 'Tinodios'
    db_pods
    app_pods
end

# Isolated foreground host for four real VLC dependency measurements only.
target 'TinodiosVLCProbeHost' do
    project 'Tinodios'
    db_pods
    pod 'Kingfisher', '~> 5'
    pod 'MobileVLCKit', '~> 3'
    target 'TinodiosVLCProbeTests' do
        inherit! :search_paths
    end
end

target 'Tinodios' do
    project 'Tinodios'
    db_pods
    app_pods
end

post_install do | installer |
  # Keep the original generated license and reject malformed XML before replacing the resource.
  # Some upstream LGPL text contains form-feed page separators forbidden by XML 1.0.
  license_ok = system('python3', File.join(__dir__, 'Scripts/ci/prepare_license_plist.py'),
    '--source', File.join(__dir__, 'Pods/Target Support Files/Pods-Tinodios/Pods-Tinodios-acknowledgements.plist'),
    '--destination', File.join(__dir__, 'Tinodios/Settings.bundle/Acknowledgements.plist'),
    '--evidence-dir', File.join(__dir__, 'build/licenses'))
  raise 'License XML preparation failed; original license retained in Pods' unless license_ok
  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.xcconfigs.each do |config_name, config_file|
      xcconfig_path = aggregate_target.xcconfig_path(config_name)
      config_file.save_as(xcconfig_path)
    end
  end

  # See explanation here: https://github.com/firebase/firebase-ios-sdk/issues/6533
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
    end
  end
end
