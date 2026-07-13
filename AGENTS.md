# Repository Guidelines

## Project Structure & Module Organization

This repository contains a SwiftUI iOS text reader. Application code lives in `ice reader/`: entry points and persistence are at the top level, while reader features are grouped under `App/`. Reusable SwiftUI components are in `App/basic/`; `App/OC/` and `ice reader-Bridging-Header.h` contain the Objective-C iCloud bridge. Images, colors, and app icons belong in `Assets.xcassets`, and preview-only assets belong in `Preview Content`. `showimg/` holds README screenshots. CocoaPods integration is defined by `Podfile` and opened through `ice reader.xcworkspace`.

Do not edit generated files under `Pods/` directly. Add or update dependencies in `Podfile`, then regenerate the workspace support files.

## Build, Test, and Development Commands

- `pod install` installs `CombineCocoa` and refreshes CocoaPods integration.
- `open "ice reader.xcworkspace"` opens the correct Xcode workspace for local development.
- `xcodebuild -workspace "ice reader.xcworkspace" -scheme "ice reader" -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" build` performs a command-line simulator build.

The deployment target is iOS 16.1. Select a concrete simulator in Xcode to run and manually exercise bookshelf loading, scrolling, page restoration, dark mode, rotation, and iCloud progress behavior.

## Coding Style & Naming Conventions

Use four-space indentation and follow the existing SwiftUI organization. Name types and views with `UpperCamelCase` (`BookMainView`), and properties, functions, and state with `lowerCamelCase`. Keep view bodies readable by extracting repeated UI or nontrivial logic into focused helpers or view models. Place UI state changes on the main queue and preserve the existing Combine-based event flow. Add new books at the end of `BookVM.bookNames`; ordering is tied to iCloud keys. No formatter or linter is configured, so use Xcode formatting and keep diffs focused.

## Testing Guidelines

No XCTest target or coverage threshold currently exists. For logic changes, add an XCTest target and name files `<TypeName>Tests.swift` with methods such as `testReadLastPageUsesNewestProgress()`. Until automated tests are introduced, include the simulator scenarios tested in the pull request and ensure the command-line build succeeds.

## Commit & Pull Request Guidelines

Recent commits use short Chinese summaries prefixed with `*`, for example `* 修复冷启动的加载问题`. Keep each commit limited to one behavior. Pull requests should explain the user-visible change, implementation impact, and verification performed; link related issues and attach screenshots or recordings for UI changes. Call out changes to entitlements, persistence keys, bundled books, or CocoaPods files explicitly.
