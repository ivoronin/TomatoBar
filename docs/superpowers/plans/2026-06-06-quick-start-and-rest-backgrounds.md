# Quick Start And Rest Backgrounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add idle-state Work/Rest quick-start buttons, launch-time auto-start, and random rest overlay backgrounds from a user-selected folder.

**Architecture:** Keep the current `TBTimer` state machine as the source of timer truth, adding only an `idle -> rest` event for manual rest start. Move background image selection into a focused helper so `TBTimer` chooses the rest image while `TBRestOverlayController` only displays it.

**Tech Stack:** Swift 5, SwiftUI, AppKit, SwiftState, `@AppStorage`, `NSOpenPanel`, `NSImage`, Xcode target `TomatoBar`.

---

## File Structure

- Modify `TomatoBar/State.swift`
  - Add `startRest` to `TBStateMachineEvents`.
- Modify `TomatoBar/Timer.swift`
  - Add `restBackgroundFolderPath` storage.
  - Add a `TBRestBackgroundProvider`.
  - Add the `idle -> rest` transition and `startRest()` method.
  - Auto-start work once from timer initialization.
  - Pass a selected background image into the overlay controller.
- Create `TomatoBar/TBRestBackgroundProvider.swift`
  - Resolve the configured folder.
  - Filter supported image files.
  - Randomly load one `NSImage`.
  - Return `nil` for all fallback cases.
- Modify `TomatoBar/TBRestOverlayController.swift`
  - Replace the asset-name parameter with an optional `NSImage`.
- Modify `TomatoBar/TBRestOverlayView.swift`
  - Render an optional `NSImage` directly.
  - Keep the existing fallback visual background.
- Modify `TomatoBar/View.swift`
  - Split the idle top button into "Work" and "Rest".
  - Keep the running-state single stop button.
  - Add a settings row that opens an `NSOpenPanel` directory picker.
- Modify localization files:
  - `TomatoBar/en.lproj/Localizable.strings`
  - `TomatoBar/zh-Hans.lproj/Localizable.strings`
  - `TomatoBar/ko.lproj/Localizable.strings`
- Modify `TomatoBar.xcodeproj/project.pbxproj`
  - Add `TBRestBackgroundProvider.swift` to the target's source build phase if Xcode does not add it automatically.
- Modify `TomatoBar/App.swift`
  - Create the status item before constructing `TBPopoverView`, so launch auto-start can update the menu bar safely.

## Task 1: Add Manual Rest State Event

**Files:**
- Modify: `TomatoBar/State.swift`
- Modify: `TomatoBar/Timer.swift`

- [ ] **Step 1: Add the state event**

In `TomatoBar/State.swift`, change the event enum to:

```swift
enum TBStateMachineEvents: EventType {
    case startStop, timerFired, skipRest, startRest
}
```

- [ ] **Step 2: Add the idle-to-rest route**

In `TomatoBar/Timer.swift`, inside `init()` after the existing `startStop` routes, add:

```swift
stateMachine.addRoutes(event: .startRest, transitions: [.idle => .rest])
```

The route must only support `idle -> rest`. Do not add `work -> rest` or `rest -> rest`.

- [ ] **Step 3: Add the public method**

In `TomatoBar/Timer.swift`, after `func startStop()`, add:

```swift
func startRest() {
    stateMachine <-! .startRest
}
```

- [ ] **Step 4: Build to catch state-machine syntax errors**

Run:

```bash
xcodebuild -project TomatoBar.xcodeproj -target TomatoBar -configuration Debug build
```

Expected: build succeeds. If it fails because the new source from later tasks does not exist yet, defer the full build until Task 4; at this point there should be no new file references.

- [ ] **Step 5: Commit**

```bash
git add TomatoBar/State.swift TomatoBar/Timer.swift
git commit -m "feat: add manual rest timer event"
```

## Task 2: Auto-Start Work On Launch

**Files:**
- Modify: `TomatoBar/App.swift`
- Modify: `TomatoBar/Timer.swift`

- [ ] **Step 1: Reorder status item setup**

In `TomatoBar/App.swift`, change `applicationDidFinishLaunching` so the `NSStatusItem` exists before `TBPopoverView()` creates `TBTimer`.

Use this structure:

```swift
func applicationDidFinishLaunching(_: Notification) {
    statusBarItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )
    statusBarItem?.button?.imagePosition = .imageLeft
    setIcon(name: .idle)
    statusBarItem?.button?.action = #selector(TBStatusItem.togglePopover(_:))

    let view = TBPopoverView()

    popover.behavior = .transient
    popover.contentViewController = NSViewController()
    popover.contentViewController?.view = NSHostingView(rootView: view)
    if let contentViewController = popover.contentViewController {
        popover.contentSize.height = contentViewController.view.intrinsicContentSize.height
        popover.contentSize.width = 240
    }
}
```

- [ ] **Step 2: Add a launch guard**

In `TomatoBar/Timer.swift`, add a private property near the other private timer fields:

```swift
private var didAutoStartOnLaunch = false
```

- [ ] **Step 3: Add the auto-start method**

In `TomatoBar/Timer.swift`, add this method near `startStop()`:

```swift
private func startWorkOnLaunch() {
    guard !didAutoStartOnLaunch, stateMachine.state == .idle else { return }
    didAutoStartOnLaunch = true
    startStop()
}
```

- [ ] **Step 4: Call auto-start at the end of timer initialization**

At the end of `TBTimer.init()`, after URL event handling is registered, add:

```swift
startWorkOnLaunch()
```

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -project TomatoBar.xcodeproj -target TomatoBar -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add TomatoBar/App.swift TomatoBar/Timer.swift
git commit -m "feat: auto-start work on launch"
```

## Task 3: Add Rest Background Provider

**Files:**
- Create: `TomatoBar/TBRestBackgroundProvider.swift`
- Modify: `TomatoBar.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the provider file**

Create `TomatoBar/TBRestBackgroundProvider.swift` with:

```swift
import AppKit
import Foundation

struct TBRestBackgroundProvider {
    private let fileManager: FileManager
    private let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp"
    ]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func randomImage(folderPath: String) -> NSImage? {
        guard !folderPath.isEmpty else { return nil }

        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let imageURLs = contents.filter { url in
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                return false
            }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }

        guard let selectedURL = imageURLs.randomElement() else { return nil }
        return NSImage(contentsOf: selectedURL)
    }
}
```

- [ ] **Step 2: Add the file to the Xcode target**

Open `TomatoBar.xcodeproj/project.pbxproj` and add the new file using the existing source-file pattern.

Add a `PBXBuildFile` entry:

```text
		8AB000030606000100AA0001 /* TBRestBackgroundProvider.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8AB000020606000100AA0001 /* TBRestBackgroundProvider.swift */; };
```

Add a `PBXFileReference` entry:

```text
		8AB000020606000100AA0001 /* TBRestBackgroundProvider.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TBRestBackgroundProvider.swift; sourceTree = "<group>"; };
```

Add the file reference under the `TomatoBar` group alongside other Swift files:

```text
				8AB000020606000100AA0001 /* TBRestBackgroundProvider.swift */,
```

Add the build file under `PBXSourcesBuildPhase`:

```text
				8AB000030606000100AA0001 /* TBRestBackgroundProvider.swift in Sources */,
```

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -project TomatoBar.xcodeproj -target TomatoBar -configuration Debug build
```

Expected: build succeeds and the provider file is compiled.

- [ ] **Step 4: Commit**

```bash
git add TomatoBar/TBRestBackgroundProvider.swift TomatoBar.xcodeproj/project.pbxproj
git commit -m "feat: add rest background provider"
```

## Task 4: Pass NSImage Backgrounds Into The Overlay

**Files:**
- Modify: `TomatoBar/TBRestOverlayController.swift`
- Modify: `TomatoBar/TBRestOverlayView.swift`
- Modify: `TomatoBar/Timer.swift`

- [ ] **Step 1: Update the overlay view input**

In `TomatoBar/TBRestOverlayView.swift`, add an explicit AppKit import above the SwiftUI import:

```swift
import AppKit
import SwiftUI
```

In `TomatoBar/TBRestOverlayView.swift`, replace:

```swift
let backgroundImageName: String?
```

with:

```swift
let backgroundImage: NSImage?
```

Replace the image branch in `body` with:

```swift
if let image = backgroundImage {
    Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .clipped()
} else {
    LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 0.1, green: 0.15, blue: 0.25),
            Color(red: 0.05, green: 0.08, blue: 0.15),
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
```

- [ ] **Step 2: Update the overlay controller signature**

In `TomatoBar/TBRestOverlayController.swift`, change `showOverlays` to:

```swift
func showOverlays(
    restType: RestType,
    countdown: String,
    backgroundImage: NSImage?,
    skipHandler: @escaping () -> Void
) {
```

When constructing `TBRestOverlayView`, pass:

```swift
backgroundImage: backgroundImage
```

- [ ] **Step 3: Add timer storage for folder and provider**

In `TomatoBar/Timer.swift`, add an app storage setting near `enableRestOverlay`:

```swift
@AppStorage("restBackgroundFolderPath") var restBackgroundFolderPath = ""
```

Add a provider property near `overlayController`:

```swift
private let restBackgroundProvider = TBRestBackgroundProvider()
```

- [ ] **Step 4: Select the background when rest starts**

In `onRestStart`, before `overlayController.showOverlays`, add:

```swift
let configuredImage = restBackgroundProvider.randomImage(folderPath: restBackgroundFolderPath)
let backgroundImage = configuredImage ?? NSImage(named: "RestBackground")
```

Then call:

```swift
overlayController.showOverlays(
    restType: restType,
    countdown: initialCountdown,
    backgroundImage: backgroundImage,
    skipHandler: { [weak self] in self?.skipRest() }
)
```

- [ ] **Step 5: Ensure disabled overlays do not read folders**

Keep the background selection inside the existing:

```swift
if enableRestOverlay {
```

block so folder reads only happen when overlays are enabled.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -project TomatoBar.xcodeproj -target TomatoBar -configuration Debug build
```

Expected: build succeeds. If the compiler reports any remaining `backgroundImageName` references, replace them with `backgroundImage`.

- [ ] **Step 7: Commit**

```bash
git add TomatoBar/TBRestOverlayView.swift TomatoBar/TBRestOverlayController.swift TomatoBar/Timer.swift
git commit -m "feat: use selected images for rest overlays"
```

## Task 5: Split The Idle Start Button

**Files:**
- Modify: `TomatoBar/View.swift`
- Modify: `TomatoBar/en.lproj/Localizable.strings`
- Modify: `TomatoBar/zh-Hans.lproj/Localizable.strings`
- Modify: `TomatoBar/ko.lproj/Localizable.strings`

- [ ] **Step 1: Add button labels**

Add these lines to `TomatoBar/en.lproj/Localizable.strings`:

```text
"TBPopoverView.work.label" = "Work";
"TBPopoverView.rest.label" = "Rest";
```

Add these lines to `TomatoBar/zh-Hans.lproj/Localizable.strings`:

```text
"TBPopoverView.work.label" = "工作";
"TBPopoverView.rest.label" = "休息";
```

Add these lines to `TomatoBar/ko.lproj/Localizable.strings`:

```text
"TBPopoverView.work.label" = "Work";
"TBPopoverView.rest.label" = "Rest";
```

- [ ] **Step 2: Add localized properties**

In `TBPopoverView`, replace the `startLabel` property with:

```swift
private var workLabel = NSLocalizedString("TBPopoverView.work.label", comment: "Work label")
private var restLabel = NSLocalizedString("TBPopoverView.rest.label", comment: "Rest label")
```

Keep:

```swift
private var stopLabel = NSLocalizedString("TBPopoverView.stop.label", comment: "Stop label")
```

- [ ] **Step 3: Extract the running button**

Inside `TBPopoverView`, before `var body`, add:

```swift
private var runningButton: some View {
    Button {
        timer.startStop()
        TBStatusItem.shared.closePopover(nil)
    } label: {
        Text(buttonHovered ? stopLabel : timer.timeLeftString)
            .foregroundColor(Color.white)
            .font(.system(.body).monospacedDigit())
            .frame(maxWidth: .infinity)
    }
    .onHover { over in
        buttonHovered = over
    }
    .controlSize(.large)
    .keyboardShortcut(.defaultAction)
}
```

- [ ] **Step 4: Extract the idle split buttons**

Inside `TBPopoverView`, before `var body`, add:

```swift
private var idleButtons: some View {
    HStack(spacing: 6) {
        Button {
            timer.startStop()
            TBStatusItem.shared.closePopover(nil)
        } label: {
            Text(workLabel)
                .foregroundColor(Color.white)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)

        Button {
            timer.startRest()
            TBStatusItem.shared.closePopover(nil)
        } label: {
            Text(restLabel)
                .foregroundColor(Color.white)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }
}
```

- [ ] **Step 5: Replace the existing top Button in `body`**

Replace the current single `Button { ... } label: { ... }` block at the top of `VStack` with:

```swift
if timer.timer == nil {
    idleButtons
} else {
    runningButton
}
```

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -project TomatoBar.xcodeproj -target TomatoBar -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 7: Manual UI check**

Run the app from Xcode or launch the built app. Expected:

- On first launch, work starts automatically and the top button is the running countdown button.
- After clicking the running button to stop, the popover shows two equal-width buttons: "Work" and "Rest".
- Clicking "Work" starts a work interval.
- Stopping again and clicking "Rest" starts a rest interval.

- [ ] **Step 8: Commit**

```bash
git add TomatoBar/View.swift TomatoBar/en.lproj/Localizable.strings TomatoBar/zh-Hans.lproj/Localizable.strings TomatoBar/ko.lproj/Localizable.strings
git commit -m "feat: split idle start controls"
```

## Task 6: Add Background Folder Picker To Settings

**Files:**
- Modify: `TomatoBar/View.swift`
- Modify: `TomatoBar/en.lproj/Localizable.strings`
- Modify: `TomatoBar/zh-Hans.lproj/Localizable.strings`
- Modify: `TomatoBar/ko.lproj/Localizable.strings`

- [ ] **Step 1: Add settings localized strings**

Add these lines to `TomatoBar/en.lproj/Localizable.strings`:

```text
"SettingsView.restBackgroundFolder.label" = "Rest background folder";
"SettingsView.restBackgroundFolder.default" = "Default background";
"SettingsView.restBackgroundFolder.choose" = "Choose...";
```

Add these lines to `TomatoBar/zh-Hans.lproj/Localizable.strings`:

```text
"SettingsView.restBackgroundFolder.label" = "休息背景文件夹";
"SettingsView.restBackgroundFolder.default" = "默认背景";
"SettingsView.restBackgroundFolder.choose" = "选择...";
```

Add these lines to `TomatoBar/ko.lproj/Localizable.strings`:

```text
"SettingsView.restBackgroundFolder.label" = "Rest background folder";
"SettingsView.restBackgroundFolder.default" = "Default background";
"SettingsView.restBackgroundFolder.choose" = "Choose...";
```

- [ ] **Step 2: Add helper properties to `SettingsView`**

Inside `SettingsView`, after `launchAtLogin`, add:

```swift
private var restBackgroundFolderLabel: String {
    NSLocalizedString("SettingsView.restBackgroundFolder.label",
                      comment: "Rest background folder label")
}

private var defaultBackgroundLabel: String {
    NSLocalizedString("SettingsView.restBackgroundFolder.default",
                      comment: "Default rest background label")
}

private var chooseBackgroundFolderLabel: String {
    NSLocalizedString("SettingsView.restBackgroundFolder.choose",
                      comment: "Choose rest background folder label")
}

private var selectedBackgroundFolderName: String {
    guard !timer.restBackgroundFolderPath.isEmpty else {
        return defaultBackgroundLabel
    }

    return URL(fileURLWithPath: timer.restBackgroundFolderPath).lastPathComponent
}
```

- [ ] **Step 3: Add the folder picker method**

Inside `SettingsView`, add:

```swift
private func chooseRestBackgroundFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = chooseBackgroundFolderLabel

    if panel.runModal() == .OK, let url = panel.url {
        timer.restBackgroundFolderPath = url.path
    }
}
```

- [ ] **Step 4: Add the settings row**

In `SettingsView.body`, place this row immediately after the `enableRestOverlay` toggle:

```swift
HStack {
    VStack(alignment: .leading, spacing: 2) {
        Text(restBackgroundFolderLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
        Text(selectedBackgroundFolderName)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
    Button(chooseBackgroundFolderLabel) {
        chooseRestBackgroundFolder()
    }
}
```

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -project TomatoBar.xcodeproj -target TomatoBar -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 6: Manual UI check**

Run the app and open Settings. Expected:

- The row appears near the rest overlay toggle.
- It shows "Default background" before selection.
- Clicking "Choose..." opens a directory-only panel.
- Cancelling keeps the previous value.
- Choosing a folder updates the visible folder name.

- [ ] **Step 7: Commit**

```bash
git add TomatoBar/View.swift TomatoBar/en.lproj/Localizable.strings TomatoBar/zh-Hans.lproj/Localizable.strings TomatoBar/ko.lproj/Localizable.strings
git commit -m "feat: add rest background folder setting"
```

## Task 7: Final Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Inspect worktree**

Run:

```bash
git status --short
```

Expected: only intentional uncommitted changes are present. Existing unrelated files such as `.idea/`, `TomatoBar.app/`, or `TomatoBar-intel.zip` may still appear and should not be staged unless the user explicitly requests it.

- [ ] **Step 2: Run final build**

Run:

```bash
xcodebuild -project TomatoBar.xcodeproj -target TomatoBar -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 3: Manual launch check**

Launch TomatoBar. Expected:

- The app starts a work interval automatically.
- The menu bar item shows the work icon and countdown according to existing settings.
- Opening the popover while running shows one countdown/stop button.

- [ ] **Step 4: Manual idle controls check**

Stop the timer from the popover. Expected:

- The top control changes to two buttons.
- "Work" starts a work interval.
- Stopping and then clicking "Rest" starts a rest interval.
- Starting manual rest does not behave like a completed work interval.

- [ ] **Step 5: Manual background check**

Create or choose a folder containing at least two supported images. In Settings, choose that folder. Start a rest. Expected:

- The overlay uses one of the folder images.
- Stopping and starting rest again may choose a different image.
- Multiple displays, if available, use the same image for the same rest.

- [ ] **Step 6: Manual fallback check**

Choose an empty folder or move the configured folder away. Start a rest. Expected:

- The overlay falls back to the bundled `RestBackground`.
- If the bundled asset cannot load, the overlay still shows the existing gradient fallback and countdown.

- [ ] **Step 7: Commit any final fixes**

If final verification required code fixes, commit only those intentional files:

```bash
git add TomatoBar/State.swift TomatoBar/Timer.swift TomatoBar/TBRestBackgroundProvider.swift TomatoBar/TBRestOverlayController.swift TomatoBar/TBRestOverlayView.swift TomatoBar/View.swift TomatoBar/App.swift TomatoBar/en.lproj/Localizable.strings TomatoBar/zh-Hans.lproj/Localizable.strings TomatoBar/ko.lproj/Localizable.strings TomatoBar.xcodeproj/project.pbxproj
git commit -m "fix: polish quick start and rest backgrounds"
```

If no fixes were needed, do not create an empty commit.
