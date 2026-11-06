#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the field-gated watchOS targets to Peak.xcodeproj.
#
# Written against the `xcodeproj` gem rather than by hand because the project is
# objectVersion 77 and uses PBXFileSystemSynchronizedRootGroups ("folder"
# references). Hand-editing that structure reliably corrupts it — the group,
# its exception sets and the target's `fileSystemSynchronizedGroups` array all
# have to stay consistent, and Xcode silently drops sources when they don't.
#
# Idempotent: re-running removes and recreates the targets it owns.
#
# What it deliberately does NOT do
# --------------------------------
# It does not add an "Embed Watch Content" phase to the iOS `Peak` target.
# Embedding would make every iOS build, test run and archive also compile and
# sign the watch app, which is exactly the coupling this branch is required not
# to introduce. The watch app is therefore a standalone target with its own
# scheme. Embed it only after the recorded physical Watch/ocean gate passes.

require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Peak.xcodeproj')

TEAM = 'L49MKXGVM4'
WATCH_DEPLOYMENT_TARGET = '10.0'
WATCH_APP_TARGET = 'PeakWatch'
WATCH_WIDGET_TARGET = 'PeakWatchWidgets'
WATCH_BUNDLE_ID = 'com.designprism.peak.watchkitapp'
WATCH_WIDGET_BUNDLE_ID = 'com.designprism.peak.watchkitapp.widgets'
SHARED_GROUP = 'PeakShared'

project = Xcodeproj::Project.open(PROJECT_PATH)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def remove_target(project, name)
  target = project.targets.find { |t| t.name == name }
  return unless target

  # Exception sets point back at the target; leaving them behind on a re-run
  # accumulates dangling references that Xcode reports as a corrupt project.
  project.objects.select do |object|
    object.is_a?(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet) &&
      object.target == target
  end.each(&:remove_from_project)

  target.build_configuration_list&.build_configurations&.each(&:remove_from_project)
  target.build_configuration_list&.remove_from_project
  product = target.product_reference
  product&.remove_from_project
  target.remove_from_project
end

# Excludes files from a synchronized folder's automatic target membership.
#
# Needed because a synchronized root group sweeps *everything* in the folder
# into the target, including Info.plist — which is also the target's
# INFOPLIST_FILE. Xcode then tries to both process it and copy it as a resource
# and fails with "Multiple commands produce ... Info.plist". The iOS `Peak`
# folder carries exactly this exception already.
def add_membership_exception(project, group, target, paths)
  exception = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
  exception.target = target
  exception.membership_exceptions = paths
  group.exceptions ||= []
  group.exceptions << exception
  exception
end

def synchronized_group(project, path)
  existing = project.root_object.main_group.children.find do |child|
    child.is_a?(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup) && child.path == path
  end
  return existing if existing

  group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
  group.path = path
  group.source_tree = '<group>'
  project.root_object.main_group << group
  group
end

# ---------------------------------------------------------------------------
# Clean slate for the targets this script owns
# ---------------------------------------------------------------------------

remove_target(project, WATCH_WIDGET_TARGET)
remove_target(project, WATCH_APP_TARGET)

# ---------------------------------------------------------------------------
# Folder references
# ---------------------------------------------------------------------------

shared_group = synchronized_group(project, SHARED_GROUP)
watch_group = synchronized_group(project, WATCH_APP_TARGET)
watch_widget_group = synchronized_group(project, WATCH_WIDGET_TARGET)

# ---------------------------------------------------------------------------
# watchOS app target
# ---------------------------------------------------------------------------

watch_app = project.new(Xcodeproj::Project::Object::PBXNativeTarget)
project.targets << watch_app
watch_app.name = WATCH_APP_TARGET
watch_app.product_name = WATCH_APP_TARGET
watch_app.product_type = 'com.apple.product-type.application'
watch_app.build_configuration_list =
  Xcodeproj::Project::ProjectHelper.configuration_list(project, :watchos, WATCH_DEPLOYMENT_TARGET)

product_ref = project.products_group.new_reference("#{WATCH_APP_TARGET}.app", :built_products)
product_ref.explicit_file_type = 'wrapper.application'
product_ref.include_in_index = '0'
product_ref.set_source_tree(:built_products)
watch_app.product_reference = product_ref

watch_app.build_phases << project.new(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
watch_app.build_phases << project.new(Xcodeproj::Project::Object::PBXFrameworksBuildPhase)
watch_app.build_phases << project.new(Xcodeproj::Project::Object::PBXResourcesBuildPhase)

# The app's own sources plus the portable shared logic. Nothing from `Peak/`:
# the iOS model layer is not portable and dragging it in is explicitly out of
# scope for this release.
watch_app.file_system_synchronized_groups << watch_group
watch_app.file_system_synchronized_groups << shared_group
add_membership_exception(project, watch_group, watch_app, ['Info.plist', 'PeakWatch.entitlements'])

# ---------------------------------------------------------------------------
# watchOS widget extension target (Smart Stack relevance)
# ---------------------------------------------------------------------------

watch_widget = project.new(Xcodeproj::Project::Object::PBXNativeTarget)
project.targets << watch_widget
watch_widget.name = WATCH_WIDGET_TARGET
watch_widget.product_name = WATCH_WIDGET_TARGET
watch_widget.product_type = 'com.apple.product-type.app-extension'
watch_widget.build_configuration_list =
  Xcodeproj::Project::ProjectHelper.configuration_list(project, :watchos, WATCH_DEPLOYMENT_TARGET)

widget_product_ref = project.products_group.new_reference("#{WATCH_WIDGET_TARGET}.appex", :built_products)
widget_product_ref.explicit_file_type = 'wrapper.app-extension'
widget_product_ref.include_in_index = '0'
widget_product_ref.set_source_tree(:built_products)
watch_widget.product_reference = widget_product_ref

watch_widget.build_phases << project.new(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
watch_widget.build_phases << project.new(Xcodeproj::Project::Object::PBXFrameworksBuildPhase)
watch_widget.build_phases << project.new(Xcodeproj::Project::Object::PBXResourcesBuildPhase)
watch_widget.file_system_synchronized_groups << watch_widget_group
watch_widget.file_system_synchronized_groups << shared_group
add_membership_exception(
  project, watch_widget_group, watch_widget,
  ['Info.plist', 'PeakWatchWidgets.entitlements']
)

# The watch app embeds its widget, exactly as the iOS app embeds PeakWidgets.
embed = watch_app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.dst_path = ''
embed.add_file_reference(widget_product_ref, true)
watch_app.add_dependency(watch_widget)

# ---------------------------------------------------------------------------
# Build settings
# ---------------------------------------------------------------------------

primary_settings = project.targets.find { |target| target.name == 'Peak' }
  .build_configurations.find { |configuration| configuration.name == 'Release' }.build_settings
common = {
  'CODE_SIGN_STYLE' => 'Automatic',
  # A previous attempt inherited the project-level SQ949Q468V (a stale test
  # team) and failed provisioning with "No Account for Team". The watch targets
  # pin the real team explicitly, as PeakWidgets already does.
  'DEVELOPMENT_TEAM' => TEAM,
  'CURRENT_PROJECT_VERSION' => primary_settings.fetch('CURRENT_PROJECT_VERSION'),
  'MARKETING_VERSION' => primary_settings.fetch('MARKETING_VERSION'),
  'SDKROOT' => 'watchos',
  'WATCHOS_DEPLOYMENT_TARGET' => WATCH_DEPLOYMENT_TARGET,
  'TARGETED_DEVICE_FAMILY' => '4',
  'SWIFT_VERSION' => '5.0',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES',
  # Matches the iOS app so the shared sources compile under one isolation rule
  # on both platforms instead of two.
  'SWIFT_DEFAULT_ACTOR_ISOLATION' => 'MainActor',
  'SWIFT_APPROACHABLE_CONCURRENCY' => 'YES',
  'SKIP_INSTALL' => 'YES'
}

watch_app.build_configurations.each do |config|
  config.build_settings.merge!(common)
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => WATCH_BUNDLE_ID,
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_FILE' => 'PeakWatch/Info.plist',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Peak',
    'CODE_SIGN_ENTITLEMENTS' => 'PeakWatch/PeakWatch.entitlements',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'SKIP_INSTALL' => 'NO',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks']
  )
end

watch_widget.build_configurations.each do |config|
  config.build_settings.merge!(common)
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => WATCH_WIDGET_BUNDLE_ID,
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_FILE' => 'PeakWatchWidgets/Info.plist',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Peak',
    'CODE_SIGN_ENTITLEMENTS' => 'PeakWatchWidgets/PeakWatchWidgets.entitlements',
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/Frameworks',
      '@executable_path/../../Frameworks'
    ]
  )
end

# ---------------------------------------------------------------------------
# Share the portable logic with the iOS app too
# ---------------------------------------------------------------------------

ios_app = project.targets.find { |t| t.name == 'Peak' }
raise 'iOS target "Peak" not found' unless ios_app

unless ios_app.file_system_synchronized_groups.include?(shared_group)
  ios_app.file_system_synchronized_groups << shared_group
end

# ---------------------------------------------------------------------------
# Scheme
# ---------------------------------------------------------------------------

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(watch_app)
scheme.set_launch_target(watch_app)
scheme.save_as(PROJECT_PATH, WATCH_APP_TARGET, true)

project.save

puts "Added #{WATCH_APP_TARGET} (#{WATCH_BUNDLE_ID}) and #{WATCH_WIDGET_TARGET}."
puts "Shared folder '#{SHARED_GROUP}' is now a member of: Peak, #{WATCH_APP_TARGET}, #{WATCH_WIDGET_TARGET}."
