# Quick Start And Rest Backgrounds Design

## Context

TomatoBar is a macOS menu bar Pomodoro timer implemented with SwiftUI, AppKit, and a `SwiftState` state machine. The current timer has three states: `idle`, `work`, and `rest`. The popover currently shows one large start/stop button at the top. When the timer is idle, the button says "Start" and starts a work interval. When a timer is running, the button shows the countdown and changes to "Stop" on hover.

Recent work added a full-screen rest overlay. The overlay currently uses the bundled `RestBackground` asset and appears when a rest starts, if `enableRestOverlay` is enabled.

This design adds three related conveniences:

- Split the idle start button into separate "Work" and "Rest" actions.
- Automatically start work whenever TomatoBar launches.
- Let users choose a folder of images and randomly use one image as the rest overlay background.

## Goals

- In the idle state, replace the single "Start" button with two side-by-side buttons: "Work" and "Rest".
- Keep the existing running-state button behavior: countdown text, hover-to-stop label, and click-to-stop.
- Let "Work" start a normal work interval from idle.
- Let "Rest" immediately start the next rest interval from idle.
- Preserve the existing long-rest cadence when a manual rest starts.
- Start a work interval automatically each time the app launches.
- Let users choose a persistent rest background folder from Settings.
- Randomly select one supported image from the configured folder each time a rest starts.
- Fall back to the bundled `RestBackground` asset when the configured folder is empty, invalid, unreadable, or contains an image that cannot be loaded.

## Non-Goals

- Do not add forced work/rest switching while a timer is running.
- Do not change the existing global shortcut or `tomatobar://startStop` URL behavior.
- Do not add a setting to disable launch-time auto-start in this iteration.
- Do not recursively scan subfolders inside the selected background folder.
- Do not import user-selected images into the app bundle or asset catalog.
- Do not redesign the rest overlay UI beyond changing its background source.

## Button Behavior

The popover's top control has two modes.

When `TBTimer` is idle, the view shows two large buttons in a horizontal layout:

- "Work" starts a work interval.
- "Rest" starts the next rest interval.

When `TBTimer` is running, the view keeps the existing single large button:

- The label shows the current countdown.
- On hover, the label changes to "Stop".
- Clicking the button stops the current interval and returns the timer to idle.

The visual treatment should match the existing large button style closely. The two idle buttons should occupy the same overall width as the previous single button, with equal widths.

## Timer State

The existing `startStop` event remains responsible for the existing toggle behavior:

- `idle -> work`
- `work -> idle`
- `rest -> idle`

Add a small, explicit event for manual rest start:

- `startRest`

The new event only supports:

- `idle -> rest`

This keeps the new behavior scoped to the idle split-button use case. It does not add a general "force rest" command while work is running.

The "Work" button can continue to call `startStop()` from idle. The "Rest" button calls a new `startRest()` method on `TBTimer`, which sends the `startRest` event to the state machine.

Manual rest start reuses the existing `onRestStart` handler. This means the timer length, menu bar icon, notification, and overlay behavior remain centralized in one path.

Because manual rest start transitions from `idle` to `rest`, it does not trigger `onWorkFinish`. That prevents a manually started rest from incrementing `consecutiveWorkIntervals`.

## Rest Type Selection

Manual rest should use the same "next rest" rule as automatic rest:

- If `consecutiveWorkIntervals >= workIntervalsInSet`, start a long rest and reset `consecutiveWorkIntervals` to `0`.
- Otherwise, start a short rest.

In normal use, a manual rest from a freshly launched or manually stopped idle state will often be short. If the user stops after several completed work intervals and then manually starts rest, the app still honors the pending long-rest cadence.

## Launch-Time Auto-Start

TomatoBar should start work automatically each time the app launches.

The auto-start should live in `TBTimer`, not in the button action. The timer should expose an initialization path that starts the first work interval once when the timer object is created.

The implementation must guard against duplicate starts caused by SwiftUI view refreshes or unexpected repeated initialization paths. A simple instance-level flag is enough if `TBPopoverView` owns one `TBTimer` instance for the app session. If the app structure changes later to create multiple timer instances, this behavior should be revisited.

Auto-start should only start from idle. It should not change behavior after the user manually stops, after rest finishes, or during normal timer transitions.

## Background Folder Setting

Add a persistent app setting for the rest background folder path.

The Settings tab should include:

- The existing "Show screen overlay during breaks" toggle.
- A "Rest background folder" row or button near that toggle.
- A visible summary of the selected folder, such as the folder name or "Default background" when no folder is selected.

Selecting a folder should use an AppKit folder picker configured to choose directories only. The selected path is stored with `@AppStorage`.

The app should not copy images. It reads images from the selected folder when a rest starts.

## Background Image Selection

When a rest starts and overlays are enabled:

1. Read the configured background folder path.
2. List files in that folder without recursing into subfolders.
3. Filter to supported image extensions:
   `jpg`, `jpeg`, `png`, `heic`, `tiff`, `gif`, `bmp`.
4. Randomly choose one candidate.
5. Load it as an `NSImage`.
6. Pass the loaded image to the overlay controller for this rest.

All overlay windows for the same rest should use the same selected image, even when multiple displays are connected.

If any step fails, use the existing bundled `RestBackground` asset. If that also fails to load, preserve the existing fallback visual background in `TBRestOverlayView`.

## Overlay Boundary

The overlay currently accepts an asset image name. Extend this boundary so the overlay can render either:

- A loaded `NSImage` from the selected folder.
- The bundled default asset.
- The existing fallback background when no image is available.

The timer owns the choice of which image should be used for a rest. The overlay controller remains responsible only for opening, updating, and closing overlay windows.

## Localization

Add localized strings for:

- `TBPopoverView.work.label`
- `TBPopoverView.rest.label`
- `SettingsView.restBackgroundFolder.label`
- `SettingsView.restBackgroundFolder.default`
- `SettingsView.restBackgroundFolder.choose`

At minimum, update English and Simplified Chinese strings because the current workspace already maintains both and the user-facing request is in Chinese. Korean can keep English fallback strings if full translation is not available in this iteration.

## Error Handling

- If the folder picker is cancelled, keep the previous folder setting unchanged.
- If the stored folder path no longer exists, show "Default background" behavior and use the bundled image.
- If the folder contains no supported images, use the bundled image.
- If a selected image cannot be decoded by `NSImage`, use the bundled image.
- If overlay windows are disabled, do not read the folder or load an image.
- If the timer is stopped while a rest overlay is visible, close overlays through the existing idle transition path.

## Testing And Verification

Implementation should verify:

- App launch automatically starts a work interval.
- Idle popover shows side-by-side "Work" and "Rest" buttons.
- Clicking "Work" from idle starts a work interval.
- Clicking "Rest" from idle starts a rest interval.
- Running-state popover still shows one countdown button and can stop the timer.
- Manual rest does not increment `consecutiveWorkIntervals` as a completed work interval.
- Manual rest uses long rest when the existing cadence indicates a long rest is due.
- Selecting a background folder persists the folder path.
- Rest overlay uses a random supported image from the configured folder.
- Invalid, empty, or unreadable folder paths fall back to the bundled background.
- The project builds successfully after the change.

Because this is a macOS SwiftUI/AppKit app, verification should combine code review, build verification, and manual UI checks for the menu bar popover and folder picker.
