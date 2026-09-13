# Assessment evidence

These are review artifacts, not application target sources. The four regression tests describe desired behavior and currently fail on the reviewed snapshot. See ../ASSESSMENT-2026-09-12.md for severity and scope.

Baseline: 23 existing tests passed in an isolated Swift Package harness. Regression run: four tests, six failed assertions. Fixture data was fictional and stored in temporary directories.

The harness compiled these unchanged application files as module Slingshot in Swift 5 language mode, macOS 15 minimum: Calculator.swift, UnitConverter.swift, FuzzyMatcher.swift, PasteboardFilter.swift, FileSearch.swift, MarkdownBlocks.swift, NotesStore.swift, Preferences.swift. All seven existing test files were copied into its test target. No production AppDelegate, clipboard monitor, or UI was launched.

Snapshot: /tmp/slingshot-assessment-snapshot (temporary). source-manifest.json records SHA-256 values of reviewed files, since there was no Git commit. Build log: /tmp/slingshot-assessment-snapshot-build.log (temporary).

Script failure reproduction: place executable xcodegen and xcodebuild stubs earlier on PATH, exiting 0 and 42 respectively; invoke /bin/sh Scripts/build.sh and /bin/sh Scripts/test.sh in a disposable snapshot. Both returned 0. Do not invoke release.sh with this harness.
