# Rest Overlay Design

## Context

TomatoBar is a macOS menu bar Pomodoro timer implemented with SwiftUI, AppKit, and a `SwiftState` state machine. The current timer moves through `idle`, `work`, and `rest` states. When work ends, `TBTimer.onRestStart` starts either a short rest or a long rest, sends a notification, changes the menu bar icon, and starts the rest timer. Rest can already be skipped through `TBTimer.skipRest()`, which transitions from `rest` to `work`.

This design adds a full-screen rest overlay that appears during automatically started short and long rests.

## Goals

- Cover every connected display during short rest and long rest.
- Cover the complete screen frame, including menu bar and Dock areas.
- Show the correct rest type and countdown in the center of every display.
- Let the user skip rest by double-clicking anywhere on any overlay window.
- Remove the overlay when rest is skipped or when the countdown naturally ends.
- Start the next work interval through the existing state machine behavior.
- Keep the feature enabled by default, with a settings toggle to disable it.

## Non-Goals

- Do not implement a system lock screen.
- Do not request Accessibility permissions or prevent application switching at the system level.
- Do not add user image selection in the first implementation.
- Do not live-update overlay windows when displays are connected or disconnected during a rest.

## Recommended Approach

Add a `TBRestOverlayController` owned by `TBTimer`. The controller is responsible only for showing, updating, and closing rest overlay windows. It does not own timer state and does not change the state machine rules.

When a rest starts, `TBTimer.onRestStart` determines whether the interval is a short rest or long rest, calculates the rest length, and asks the overlay controller to show one window for each `NSScreen`.

When timer ticks update `timeLeftString`, `TBTimer` also sends the updated countdown text to the overlay controller. Each visible overlay window displays the same countdown text.

When the user double-clicks any overlay window, the overlay controller calls a skip callback supplied by `TBTimer`. That callback invokes `TBTimer.skipRest()`. The existing `.rest -> .work` transition handles the next work interval.

When rest ends for any reason, `TBTimer` asks the overlay controller to close all overlay windows. This applies to natural completion, skip, and returning to idle.

## Overlay Windows

The controller creates one borderless `NSWindow` per screen using `NSScreen.screens`. Each window uses the screen's full `frame`, not `visibleFrame`, so the overlay covers menu bar and Dock regions too.

Window behavior:

- Borderless and non-resizable.
- High window level suitable for a temporary screen-covering rest prompt.
- Visible across Spaces where possible.
- Does not rely on becoming the user's primary control surface beyond accepting double-clicks.

If no screens are available, the controller does not show an overlay and the rest timer continues normally.

## Overlay View

Each window hosts the same SwiftUI view. The view contains:

- A background image that fills the screen while preserving aspect ratio and cropping overflow.
- A semi-transparent dark overlay to keep the countdown readable.
- Centered rest type text: short rest or long rest.
- Centered monospaced countdown text.

Initial image behavior:

- First implementation uses an included default rest background asset.
- The background-loading boundary should allow a future user-configured image path.
- If the image cannot load, the view falls back to a simple filled background while still showing rest type and countdown.

## Settings

Add an `@AppStorage` setting named `enableRestOverlay`, defaulting to `true`.

The Settings tab gets a toggle with copy similar to "Show screen overlay during breaks". When disabled, rest behavior remains the same as the current app: icon changes, notifications are sent, and timers continue, but no overlay is shown.

## Existing Controls

The overlay covers the menu bar area, so the primary skip interaction is double-clicking anywhere on the overlay. TomatoBar's existing menu bar item, global shortcut, and notification action are not intentionally disabled, but they are not the primary interaction during an active overlay.

## Error Handling

- If background image loading fails, show a fallback background and continue displaying the countdown.
- If one overlay window fails to create, other screens can still be covered.
- When leaving rest, close all windows that were created successfully.
- If a display is connected or disconnected during rest, do not update windows in the first version. The next rest will use the current screen list.

## Testing And Verification

Implementation should verify:

- Work completion shows the overlay for short rest.
- The configured long-rest cadence shows the long rest overlay.
- Natural rest completion closes the overlay and enters the next work interval when `stopAfterBreak` is disabled.
- Double-clicking any overlay closes all overlays and starts the next work interval through `skipRest()`.
- Disabling `enableRestOverlay` preserves existing rest notifications and state behavior without showing windows.
- Overlay windows use full screen frames, covering menu bar and Dock regions.
- The app compiles successfully after the change.

Because this is macOS AppKit and SwiftUI window behavior, coverage should combine focused code review of the controller boundaries with build verification and manual multi-display validation where available.
