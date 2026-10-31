# Stage 1a hand-off 2 probe: generates the throwaway Xcode projects (hand-off 1 + notifications).
#
#   ruby gen_projects.rb <work> <ios-native-toolkit.xcframework> capi [asan]
#       IosLibraryCApi.framework + CApiTestHost + IosLibraryCApiTests + IosLibraryCApiUITests (Xcode 26.6)
#   ruby gen_projects.rb <work> <xcframework folder> smoke
#       the C / Objective-C smoke that uses the two built xcframeworks (Xcode 26.6 or 26.3)
#
# Needs the xcodeproj gem. Common.h and Probe.h come from ../entry, Dialog and Share from ../handoff1 (unchanged).
require 'fileutils'
require 'xcodeproj'

HERE = File.expand_path(__dir__)
ENTRY = File.expand_path('../entry', HERE)
H1 = File.expand_path('../handoff1', HERE)
work = File.expand_path(ARGV.fetch(0))
xcf = File.expand_path(ARGV.fetch(1))
mode = ARGV.fetch(2)

def settings(target, values)
  target.build_configurations.each { |c| c.build_settings.merge!(values) }
end

def group(project)
  project.main_group.find_subpath('Sources', true)
end

def add(project, target, paths)
  paths.each do |path|
    ref = group(project).new_reference(path)
    if path.end_with?('.h')
      target.headers_build_phase.add_file_reference(ref).settings = { 'ATTRIBUTES' => ['Public'] }
    else
      target.source_build_phase.add_file_reference(ref)
    end
  end
end

def xcframework_ref(project, path)
  ref = project.frameworks_group.new_reference(path)
  ref.last_known_file_type = 'wrapper.xcframework'
  ref
end

def embed(target, refs)
  phase = target.new_copy_files_build_phase('Embed Frameworks')
  phase.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:frameworks]
  refs.each do |ref|
    target.frameworks_build_phase.add_file_reference(ref, true)
    phase.add_file_reference(ref, true).settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
  end
end

APP = {
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
  'IPHONEOS_DEPLOYMENT_TARGET' => '18.0',
  'TARGETED_DEVICE_FAMILY' => '1,2',
  'CODE_SIGN_STYLE' => 'Manual',
  'CODE_SIGN_IDENTITY' => '-',
  'DEVELOPMENT_TEAM' => '',
  'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
  'CURRENT_PROJECT_VERSION' => '1',
  'MARKETING_VERSION' => '1.0'
}.freeze

def scheme(project, name, build:, test: [], launch: nil)
  s = Xcodeproj::XCScheme.new
  build.each { |t| s.add_build_target(t) }
  test.each { |t| s.add_test_target(t) }
  s.set_launch_target(launch) if launch
  s.save_as(project.path, name, true)
end

case mode
when 'capi'
  dir = File.join(work, 'capi')
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)
  project = Xcodeproj::Project.new(File.join(dir, 'IosLibraryCApi.xcodeproj'))
  ios_library = xcframework_ref(project, xcf)

  fw = project.new_target(:framework, 'IosLibraryCApi', :ios, '18.0', nil, :swift)
  headers = [File.join(ENTRY, 'capi/include/NativeToolkitC/Common.h'), File.join(ENTRY, 'capi/include/NativeToolkitC/Probe.h'),
             File.join(H1, 'capi/include/NativeToolkitC/ProbeDialog.h'), File.join(H1, 'capi/include/NativeToolkitC/ProbeShare.h'),
             File.join(HERE, 'capi/include/NativeToolkitC/Notification.h'), File.join(HERE, 'capi/include/NativeToolkitC/ProbeNotification.h')]
  add(project, fw, headers + Dir[File.join(H1, 'capi/Sources/**/*.swift')].sort + Dir[File.join(HERE, 'capi/Sources/**/*.swift')].sort)
  fw.frameworks_build_phase.add_file_reference(ios_library, true)
  values = {
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.IosLibraryCApi',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET' => '18.0',
    'SWIFT_VERSION' => '6.0',
    'DEFINES_MODULE' => 'YES',
    'MODULEMAP_FILE' => File.join(HERE, 'capi/module.modulemap'),
    'PUBLIC_HEADERS_FOLDER_PATH' => '$(CONTENTS_FOLDER_PATH)/Headers/NativeToolkitC',
    'EXPORTED_SYMBOLS_FILE' => File.join(HERE, 'capi/IosLibraryCApi.exp'),
    'SWIFT_INSTALL_OBJC_HEADER' => 'NO',
    'SWIFT_INSTALL_MODULE' => 'NO',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'NO',
    'ENABLE_MODULE_VERIFIER' => 'YES',
    'MODULE_VERIFIER_SUPPORTED_LANGUAGES' => 'objective-c objective-c++',
    'MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS' => 'gnu11 gnu++17',
    'CODE_SIGN_STYLE' => 'Manual',
    'CODE_SIGN_IDENTITY' => '',
    'DEVELOPMENT_TEAM' => '',
    'CURRENT_PROJECT_VERSION' => '1',
    'MARKETING_VERSION' => '2.0.0'
  }
  values['ENABLE_ADDRESS_SANITIZER'] = 'YES' if ARGV[3] == 'asan'
  settings(fw, values)

  host = project.new_target(:application, 'CApiTestHost', :ios, '18.0', nil, :swift)
  add(project, host, [File.join(HERE, 'tests/TestHost.swift')])
  settings(host, APP.merge('PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.stage1a.handoff2.host', 'SWIFT_VERSION' => '5.0'))
  embed(host, [ios_library, fw.product_reference])
  host.add_dependency(fw)

  tests = project.new_target(:unit_test_bundle, 'IosLibraryCApiTests', :ios, '18.0', nil, :swift)
  add(project, tests, [File.join(HERE, 'tests/HandoffTests.swift')])
  tests.frameworks_build_phase.add_file_reference(fw.product_reference, true)
  settings(tests, { 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.stage1a.handoff2.tests',
                    'GENERATE_INFOPLIST_FILE' => 'YES', 'IPHONEOS_DEPLOYMENT_TARGET' => '18.0', 'SWIFT_VERSION' => '5.0',
                    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/CApiTestHost.app/CApiTestHost', 'BUNDLE_LOADER' => '$(TEST_HOST)',
                    'CODE_SIGN_STYLE' => 'Manual', 'CODE_SIGN_IDENTITY' => '-', 'DEVELOPMENT_TEAM' => '' })
  tests.add_dependency(host)

  ui = project.new_target(:ui_test_bundle, 'IosLibraryCApiUITests', :ios, '18.0', nil, :swift)
  add(project, ui, [File.join(HERE, 'tests/HandoffUITests.swift')])
  settings(ui, { 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.stage1a.handoff2.uitests',
                 'GENERATE_INFOPLIST_FILE' => 'YES', 'IPHONEOS_DEPLOYMENT_TARGET' => '18.0', 'SWIFT_VERSION' => '5.0',
                 'TEST_TARGET_NAME' => 'CApiTestHost',
                 'CODE_SIGN_STYLE' => 'Manual', 'CODE_SIGN_IDENTITY' => '-', 'DEVELOPMENT_TEAM' => '' })
  ui.add_dependency(host)
  project.save
  scheme(project, 'IosLibraryCApi', build: [fw])
  scheme(project, 'CApiTests', build: [fw, host], test: [tests, ui], launch: host)

when 'smoke'
  dir = File.join(work, 'smoke')
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)
  project = Xcodeproj::Project.new(File.join(dir, 'Smoke.xcodeproj'))
  refs = %w[ios-native-toolkit-handoff2.xcframework ios-native-toolkit-capi-handoff2.xcframework].map { |n| xcframework_ref(project, File.join(xcf, n)) }
  smoke = project.new_target(:application, 'Smoke', :ios, '18.0', nil, :objc)
  add(project, smoke, %w[smoke/main.m smoke/Scenarios.c].map { |f| File.join(HERE, f) })
  settings(smoke, APP.merge('PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.stage1a.handoff2.smoke',
                            'CLANG_ENABLE_MODULES' => 'YES', 'GCC_C_LANGUAGE_STANDARD' => 'gnu11'))
  embed(smoke, refs)
  project.save
  scheme(project, 'Smoke', build: [smoke], launch: smoke)
else
  abort "unknown mode #{mode}"
end
puts "generated #{mode} in #{work}"
