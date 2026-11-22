# Stage 1a entry-layer probe: generates the throwaway Xcode projects into a work folder.
#
#   ruby gen_projects.rb <work> capi       # IosLibraryCApi.framework + test host + IosLibraryCApiTests (Xcode 26.6)
#   ruby gen_projects.rb <work> consumers  # C/Objective-C smoke + Swift app that use the two xcframeworks (Xcode 26.3)
#   ruby gen_projects.rb <work> fallback   # the fallback layout (C entry + function-pointer table) (Xcode 26.3)
#
# Expects <work>/xcf/ios-native-toolkit.xcframework (IosLibrary built by Xcode 26.6), and for
# "consumers" also <work>/xcf/ios-native-toolkit-capi.xcframework. Needs the xcodeproj gem.
require 'fileutils'
require 'xcodeproj'

SRC = File.expand_path(__dir__)
work = File.expand_path(ARGV.fetch(0))
mode = ARGV.fetch(1)
XCF = File.join(work, 'xcf')

def settings(target, values)
  target.build_configurations.each { |c| c.build_settings.merge!(values) }
end

def add_sources(project, target, files)
  group = project.main_group.find_subpath('Sources', true)
  files.each do |f|
    ref = group.new_reference(File.join(SRC, f))
    if f.end_with?('.h')
      build_file = target.headers_build_phase.add_file_reference(ref)
      build_file.settings = { 'ATTRIBUTES' => ['Public'] }
    else
      target.source_build_phase.add_file_reference(ref)
    end
  end
end

def xcframework_ref(project, name)
  ref = project.frameworks_group.new_reference(File.join(XCF, name))
  ref.last_known_file_type = 'wrapper.xcframework'
  ref
end

def embed(project, target, refs)
  phase = target.new_copy_files_build_phase('Embed Frameworks')
  phase.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:frameworks]
  refs.each do |ref|
    target.frameworks_build_phase.add_file_reference(ref, true)
    bf = phase.add_file_reference(ref, true)
    bf.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
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
  ios_library = xcframework_ref(project, 'ios-native-toolkit.xcframework')

  fw = project.new_target(:framework, 'IosLibraryCApi', :ios, '18.0', nil, :swift)
  add_sources(project, fw, %w[
    capi/include/NativeToolkitC/Common.h capi/include/NativeToolkitC/Probe.h
    capi/Sources/Support.swift capi/Sources/ProbeImpl.swift capi/Sources/Entry.swift capi/Sources/ThreadLocal.c
  ])
  fw.frameworks_build_phase.add_file_reference(ios_library, true)
  settings(fw, {
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.IosLibraryCApi',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET' => '18.0',
    'SWIFT_VERSION' => '6.0',
    'DEFINES_MODULE' => 'YES',
    'MODULEMAP_FILE' => File.join(SRC, 'capi/module.modulemap'),
    'PUBLIC_HEADERS_FOLDER_PATH' => '$(CONTENTS_FOLDER_PATH)/Headers/NativeToolkitC',
    'EXPORTED_SYMBOLS_FILE' => File.join(SRC, 'capi/IosLibraryCApi.exp'),
    'SWIFT_INCLUDE_PATHS' => File.join(SRC, 'capi/internal'),
    'HEADER_SEARCH_PATHS' => File.join(SRC, 'capi/internal'),
    'SWIFT_INSTALL_OBJC_HEADER' => 'NO',
    'SWIFT_INSTALL_MODULE' => ENV.fetch('CAPI_SWIFT_INSTALL_MODULE', 'NO'),
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'NO',
    'ENABLE_MODULE_VERIFIER' => 'YES',
    'MODULE_VERIFIER_SUPPORTED_LANGUAGES' => 'objective-c objective-c++',
    'MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS' => 'gnu11 gnu++17',
    'GCC_C_LANGUAGE_STANDARD' => 'gnu11',
    'CODE_SIGN_STYLE' => 'Manual',
    'CODE_SIGN_IDENTITY' => '',
    'DEVELOPMENT_TEAM' => '',
    'CURRENT_PROJECT_VERSION' => '1',
    'MARKETING_VERSION' => '2.0.0'
  })

  host = project.new_target(:application, 'CApiTestHost', :ios, '18.0', nil, :swift)
  host.source_build_phase.add_file_reference(project.main_group.find_subpath('Sources', true).new_reference(File.join(SRC, 'tests/TestHost.swift')))
  settings(host, APP.merge('PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.stage1a.testhost', 'SWIFT_VERSION' => '6.0'))
  embed(project, host, [ios_library, fw.product_reference])
  host.add_dependency(fw)

  tests = project.new_target(:unit_test_bundle, 'IosLibraryCApiTests', :ios, '18.0', nil, :swift)
  tests.source_build_phase.add_file_reference(project.main_group.find_subpath('Sources', true).new_reference(File.join(SRC, 'tests/IosLibraryCApiTests.swift')))
  tests.frameworks_build_phase.add_file_reference(fw.product_reference, true)
  settings(tests, {
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.stage1a.tests',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET' => '18.0',
    'SWIFT_VERSION' => '5.0',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/CApiTestHost.app/CApiTestHost',
    'BUNDLE_LOADER' => '$(TEST_HOST)',
    'CODE_SIGN_STYLE' => 'Manual',
    'CODE_SIGN_IDENTITY' => '-',
    'DEVELOPMENT_TEAM' => ''
  })
  tests.add_dependency(host)
  project.save
  scheme(project, 'IosLibraryCApi', build: [fw])
  scheme(project, 'CApiTests', build: [fw, host], test: [tests], launch: host)

when 'consumers'
  dir = File.join(work, 'consumers')
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)
  project = Xcodeproj::Project.new(File.join(dir, 'Consumers.xcodeproj'))
  refs = [xcframework_ref(project, 'ios-native-toolkit.xcframework'), xcframework_ref(project, 'ios-native-toolkit-capi.xcframework')]

  smoke = project.new_target(:application, 'Smoke', :ios, '18.0', nil, :objc)
  add_sources(project, smoke, %w[smoke/main.m smoke/Scenarios.c])
  settings(smoke, APP.merge('PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.stage1a.smoke',
                            'CLANG_ENABLE_MODULES' => 'YES', 'GCC_C_LANGUAGE_STANDARD' => 'gnu11'))
  embed(project, smoke, refs)

  swift = project.new_target(:application, 'SwiftConsumer', :ios, '18.0', nil, :swift)
  add_sources(project, swift, %w[swiftapp/SwiftConsumerApp.swift])
  settings(swift, APP.merge('PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.stage1a.swiftapp', 'SWIFT_VERSION' => '6.0'))
  embed(project, swift, refs)
  project.save
  scheme(project, 'Smoke', build: [smoke], launch: smoke)
  scheme(project, 'SwiftConsumer', build: [swift], launch: swift)

when 'fallback'
  dir = File.join(work, 'fallback')
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)
  project = Xcodeproj::Project.new(File.join(dir, 'IosLibraryCApiFallback.xcodeproj'))
  ios_library = xcframework_ref(project, 'ios-native-toolkit.xcframework')
  fw = project.new_target(:framework, 'IosLibraryCApi', :ios, '18.0', nil, :swift)
  add_sources(project, fw, %w[
    capi/include/NativeToolkitC/Common.h capi/include/NativeToolkitC/Probe.h
    capi/Sources/Support.swift capi/Sources/ProbeImpl.swift fallback/Table.swift fallback/Entry.c capi/Sources/ThreadLocal.c
  ])
  fw.frameworks_build_phase.add_file_reference(ios_library, true)
  settings(fw, {
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.IosLibraryCApi',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET' => '18.0',
    'SWIFT_VERSION' => '6.0',
    'DEFINES_MODULE' => 'YES',
    'MODULEMAP_FILE' => File.join(SRC, 'capi/module.modulemap'),
    'PUBLIC_HEADERS_FOLDER_PATH' => '$(CONTENTS_FOLDER_PATH)/Headers/NativeToolkitC',
    'EXPORTED_SYMBOLS_FILE' => File.join(SRC, 'capi/IosLibraryCApi.exp'),
    'SWIFT_INCLUDE_PATHS' => [File.join(SRC, 'fallback/internal'), File.join(SRC, 'capi/internal')],
    'HEADER_SEARCH_PATHS' => [File.join(SRC, 'fallback/internal'), File.join(SRC, 'capi/internal')],
    'SWIFT_INSTALL_OBJC_HEADER' => 'NO',
    'SWIFT_INSTALL_MODULE' => 'NO',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'NO',
    'GCC_C_LANGUAGE_STANDARD' => 'gnu11',
    'CODE_SIGN_STYLE' => 'Manual',
    'CODE_SIGN_IDENTITY' => '',
    'DEVELOPMENT_TEAM' => '',
    'CURRENT_PROJECT_VERSION' => '1',
    'MARKETING_VERSION' => '2.0.0'
  })
  project.save
  scheme(project, 'IosLibraryCApi', build: [fw])
else
  abort "unknown mode #{mode}"
end
puts "generated #{mode} in #{work}"
