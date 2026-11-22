# macOS C ABI 1a-9 probe: generates the throwaway Xcode projects of the two frameworks.
#
#   ruby gen_projects.rb <work> core
#       NtkProbeMac.framework (the MacLibrary stand-in; Swift 5, library evolution)
#   ruby gen_projects.rb <work> capi <ntk-probe-mac xcframework>
#       NtkProbeMacCApi.framework (the C ABI; Swift 6, @c @implementation, only _ntk_* exported)
#
# Both are versioned macOS frameworks (Versions/A). Xcode does not make the top-level Headers link when the
# public headers go to a subfolder (survey C, 1), so the capi target links it in a first script phase.
# Needs the xcodeproj gem.
require 'fileutils'
require 'xcodeproj'

HERE = File.expand_path(__dir__)
work = File.expand_path(ARGV.fetch(0))
mode = ARGV.fetch(1)

def settings(target, values)
  target.build_configurations.each { |c| c.build_settings.merge!(values) }
end

def add(project, target, paths)
  group = project.main_group.find_subpath('Sources', true)
  paths.each do |path|
    ref = group.new_reference(path)
    if path.end_with?('.h')
      target.headers_build_phase.add_file_reference(ref).settings = { 'ATTRIBUTES' => ['Public'] }
    else
      target.source_build_phase.add_file_reference(ref)
    end
  end
end

def scheme(project, name, target)
  s = Xcodeproj::XCScheme.new
  s.add_build_target(target)
  s.save_as(project.path, name, true)
end

COMMON = {
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'MACOSX_DEPLOYMENT_TARGET' => '15.0',
  'DEFINES_MODULE' => 'YES',
  'DYLIB_INSTALL_NAME_BASE' => '@rpath',
  'SKIP_INSTALL' => 'NO',
  'CODE_SIGN_STYLE' => 'Manual',
  'CODE_SIGN_IDENTITY' => '',
  'DEVELOPMENT_TEAM' => '',
  'CURRENT_PROJECT_VERSION' => '1',
  'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO'
}.freeze

case mode
when 'core'
  dir = File.join(work, 'core')
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)
  project = Xcodeproj::Project.new(File.join(dir, 'NtkProbeMac.xcodeproj'))
  fw = project.new_target(:framework, 'NtkProbeMac', :osx, '15.0', nil, :swift)
  add(project, fw, Dir[File.join(HERE, 'core/Sources/*.swift')].sort)
  settings(fw, COMMON.merge(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.probe1a9.NtkProbeMac',
    'SWIFT_VERSION' => '5.0',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks', '@loader_path/../../..'],
    'MARKETING_VERSION' => '1.0.0'
  ))
  project.save
  scheme(project, 'NtkProbeMac', fw)

when 'capi'
  core_xcf = File.expand_path(ARGV.fetch(2))
  dir = File.join(work, 'capi')
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)
  project = Xcodeproj::Project.new(File.join(dir, 'NtkProbeMacCApi.xcodeproj'))
  fw = project.new_target(:framework, 'NtkProbeMacCApi', :osx, '15.0', nil, :swift)

  link = fw.new_shell_script_build_phase('Link top-level Headers')
  link.shell_script = <<~SH
    # A versioned framework with its public headers in Headers/NativeToolkitC gets no top-level Headers
    # link from Xcode, and the module map (header "NativeToolkitC/Common.h") is not found without it.
    for d in "${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}" "${TARGET_BUILD_DIR}/${WRAPPER_NAME}"; do
      mkdir -p "$d/Versions/A/Headers"
      ln -sfh Versions/Current/Headers "$d/Headers"
    done
  SH
  link.always_out_of_date = '1'
  # Run it before the headers phase and the compile.
  fw.build_phases.delete(link)
  fw.build_phases.unshift(link)

  headers = %w[Common Probe Dialog Share Notification ProbeNotification].map { |h| File.join(HERE, "capi/include/NativeToolkitC/#{h}.h") }
  add(project, fw, headers + Dir[File.join(HERE, 'capi/Sources/*.swift')].sort)
  core_ref = project.frameworks_group.new_reference(core_xcf)
  core_ref.last_known_file_type = 'wrapper.xcframework'
  fw.frameworks_build_phase.add_file_reference(core_ref, true)
  settings(fw, COMMON.merge(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.jonghyunkim.nativetoolkit.probe1a9.NtkProbeMacCApi',
    'SWIFT_VERSION' => '6.0',
    'MODULEMAP_FILE' => File.join(HERE, 'capi/module.modulemap'),
    'PUBLIC_HEADERS_FOLDER_PATH' => '$(CONTENTS_FOLDER_PATH)/Headers/NativeToolkitC',
    'EXPORTED_SYMBOLS_FILE' => File.join(HERE, 'capi/NtkProbeMacCApi.exp'),
    'SWIFT_INSTALL_OBJC_HEADER' => 'NO',
    'SWIFT_INSTALL_MODULE' => 'NO',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'NO',
    # @loader_path/../../.. is the folder that holds this framework (D-11, 1a-3): the sibling
    # NtkProbeMac.framework is found outside Contents/Frameworks too (e.g. Contents/PlugIns).
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks', '@loader_path/../../..'],
    'MARKETING_VERSION' => '2.0.0'
  ))
  project.save
  scheme(project, 'NtkProbeMacCApi', fw)
else
  abort "unknown mode #{mode}"
end
puts "generated #{mode} in #{work}"
