#!/usr/bin/env ruby
# frozen_string_literal: true

# Registers the 3.1 watch-companion unit tests with the PeakTests target.
#
# PeakTests is NOT a file-system-synchronized group (only the iOS `Peak` folder
# and the new watch folders are), so a new test file is invisible to the build
# until it has a PBXFileReference, a PBXBuildFile and an entry in the target's
# Sources phase. Idempotent.

require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Peak.xcodeproj')
TEST_FILES = ['WatchCompanionTests.swift'].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)

target = project.targets.find { |t| t.name == 'PeakTests' }
raise 'PeakTests target not found' unless target

group = project.main_group.find_subpath('PeakTests', false)
raise 'PeakTests group not found' unless group

added = []
TEST_FILES.each do |name|
  next if target.source_build_phase.files_references.any? { |ref| ref.path == name }

  ref = group.files.find { |f| f.path == name } || group.new_file(name)
  target.source_build_phase.add_file_reference(ref, true)
  added << name
end

project.save

puts added.empty? ? 'No new test files to register.' : "Registered with PeakTests: #{added.join(', ')}"
