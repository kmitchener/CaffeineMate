# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CaffeineMate is a macOS menu bar application that prevents the system from going to sleep, similar to the `caffeinate` command-line tool. It uses SwiftUI for the app structure and AppKit for the menu bar interface.

## Building and Running

- **Open in Xcode**: Open `CaffeineMate.xcodeproj`
- **Build**: ⌘B in Xcode
- **Run**: ⌘R in Xcode
- **Requirements**: macOS 15.6+ (deployment target), Swift 5.0, Xcode 26.0+

## Architecture

### Core Components

**AppDelegate** (`AppDelegate.swift:10`)

- Primary controller managing the menu bar UI and user interactions
- Handles left-click (toggle) and right-click (menu) on status bar icon
- Updates the status bar when PowerAssertionManager reports a change
- Coordinates between PowerAssertionManager and SettingsManager

**PowerAssertionManager** (`PowerAssertionManager.swift:11`)

- Singleton managing IOKit power assertions
- Creates two types of assertions:
  - System assertion (`kIOPMAssertionTypePreventUserIdleSystemSleep`) - always created when active
  - Display assertion (`kIOPMAssertionTypeNoDisplaySleep`) - created only if "Keep Display Awake" is enabled
- Uses one timer to refresh the elapsed-time countdown and release assertions at expiration
- All state changes flow through this manager (activate/deactivate/toggle)

**SettingsManager** (`SettingsManager.swift:10`)

- Singleton persisting user preferences to UserDefaults
- Stores display, duration, and launch-at-login preferences

**LaunchAtLoginManager** (`LaunchAtLoginManager.swift:12`)

- Uses ServiceManagement framework's SMAppService (macOS 13+)
- Falls back to UserDefaults for older macOS versions (no programmatic launch control)

### Data Flow

1. User clicks status bar icon → AppDelegate toggles → PowerAssertionManager activates/deactivates → IOKit assertions created/released
2. Menu settings changed → PowerAssertionManager applies them if active → SettingsManager persists them on success
3. Timed session running → PowerAssertionManager calculates time remaining from the deadline → AppDelegate updates the menu bar

## Key Behaviors

- **Duration timer**: When set, displays countdown in menu bar (e.g., "15:30") and auto-deactivates at 0
- **Indefinite mode**: No countdown, stays active until manually toggled off
- **Display vs System**: System assertion always created. Display assertion only when "Keep Display Awake" is checked
- **Settings persistence**: All settings survive app restarts via UserDefaults

## Entitlements

- **App Sandbox**: Enabled (`ENABLE_APP_SANDBOX = YES`)
- **Hardened Runtime**: Enabled
- Menu bar app (LSUIElement = YES) - no Dock icon, only status bar presence

## Code Signing & Distribution

- **Signed**: Developer ID Application certificate
- **Notarized**: Submitted to Apple for notarization via App Store Connect API
- **Stapled**: Notarization ticket stapled to the app bundle
- GitHub Actions workflow handles signing, notarization, and release creation
