# OpenBar implementation design

The three supplied photographs describe an AppKit menu bar utility using an expanded spacer, two hidden tiers, fresh tray captures, and Accessibility activation. Readable copies are in `general/specs/`. They are product requirements and historical notes, not instructions to execute unrelated commands. The follow-up request explicitly authorizes changing that design to work on macOS 27 and improve its usability.

## macOS 27 product behavior

This section describes the intended behavior. Live testing currently shows four unidentified item losses even under a full allow-list; preservation is unresolved. See [PROGRESS.md](PROGRESS.md).

- An accessory app with a fixed-size tray status item, a transient tray popover, and a native SwiftUI management window hosted in AppKit.
- Saved per-app rules: **Visible**, **In Tray**, and **Hidden Only**. Rules and remembered app names live in OpenBar's own UserDefaults domain. The management window also saves its geometry.
- Startup shows the full bar. **Hide Selected** applies the current rules; clicking the hidden-state control opens the tray. **Show All** restores the bar without clearing rules.
- New apps and Apple system components remain visible by default. Apple system apps and OpenBar cannot be assigned hidden rules in management.
- Hiding operates per bundle identifier across displays. Multiple icons from one app share one rule. Reordering remains controlled by macOS.
- Accessibility is optional for hiding and required for discovering/pressing tray controls. Screen Recording is optional for current icon pixels; app icons provide the fallback.
- Nothing is captured at startup, stored as an image, or sent over a network.

The native backend removes the obsolete spacer and tier marker from the visible bar. Their positions no longer define the macOS 27 groups; saved rules do. The legacy backend retains the photographed arrangement on macOS 14–26, which remains separately subject to runtime validation.

## Visibility architecture

`MenuBarPolicy` derives an allow-list from all running bundle identifiers minus configured hidden apps, with OpenBar and any temporarily selected app added back. It never intentionally removes Apple system components.

`NativeVisibilityService` owns pending and active visibility leases. `MenuBarBridge` is the narrow Objective-C boundary to the private framework:

```text
MenuBarClientCore.framework
  MBAssessmentModeConfiguration
    initWithAllowedSystemItems:allowedBundleIdentifiers:
  MBAssessmentModeAssertion
    activateWithConfiguration:completionHandler:
    invalidate
```

The bridge loads the framework at runtime, verifies Objective-C signatures, supplies arrays rather than sets, catches exceptions, and delivers completion on the main queue. It retains pending assertions until their asynchronous response can be cleaned up. There is no static private-framework link dependency and no full `AEAssessmentSession`.

The service includes its own bundle identifier in every allow-list and preserves system identifiers `0..<256`. It replaces an active assertion only after the replacement succeeds. Generation checks reject superseded callbacks. Cancellation, Show All, activation failure, and a three-second timeout invalidate pending assertions; a success arriving after cancellation is invalidated again. Exceptional restoration failures retain the lease for retry and are reportable rather than being silently discarded.

The app must launch as the installed, LaunchServices-resolved `/Applications/OpenBar.app` copy. An allow-listed bundle identifier alone does not reliably keep an arbitrary development copy's icon drawn on macOS 27. AppKit's local status-item window geometry is also insufficient evidence that the remote menu scene is visible.

This is a private menu bar visibility service, not a supported Apple API contract. A future macOS build can change the class interface, system identifiers, or behavior. The fallback is an unrestricted bar and a clear error. The service cannot provide individual-icon rules, independent rules per display, or custom status-item reordering.

## Interaction and recovery

The controller serializes UI operations and gives cancellation a generation boundary. Show All cancels capture/activation work, stops interaction monitoring, closes the tray, and restores visibility. Display topology changes and sleep/wake take that same recovery path. App launch/termination and policy edits release the current restriction before rebuilding its allow-list.

An interaction guard reads public pointer state and window geometry. It suspends the restriction during menu bar use and delays reapplication after interaction. This is necessary because assessment-origin visibility restrictions can prevent Notification Center from opening while active. OpenBar's own menu tracking is observed separately. Cross-process menus and system panels need runtime verification; local AppKit tracking notifications cannot establish another app's menu state.

The implementation does not unload or reload Apple menu extras through `CoreMenuExtra`, write system-wide spacing or visibility preferences, disable system security, or change permissions programmatically. Process exit is the final recovery route if framework invalidation fails.

## Inventory, capture, and activation

`MenuBarInventory` snapshots Accessibility extras bars using bounded messaging timeouts off the main actor. It traverses nested remote-host groups, deduplicates mirror elements, records owning app identity, and assigns display-relative geometry. AX and Core Graphics use top-left screen coordinates; AppKit pointer coordinates require conversion.

`StatusItemScanner` consumes a revealed snapshot. When existing screen access is available, it uses ScreenCaptureKit with display-relative source rectangles and the display's pixel scale. Missing screen access or failed capture yields an app icon instead of discarding a discoverable item. Icons obscured by a notch also use fallback imagery.

The tray preserves physical inventory order. On macOS 27 it includes only apps assigned **In Tray**; **Hidden Only** apps stay excluded. Before activation, the selected app is temporarily allow-listed, the current AX control is resolved again, and an AX press is attempted. A synthetic click is permitted only after checking the fresh frame is on a display. This reduces stale-handle and stale-coordinate failures caused by macOS rebuilding its remote scene.

## Organization and validation boundaries

- `App/`: application lifecycle and debug entrypoints.
- `Controllers/`: operation ownership, menu bar recovery, management window.
- `Models/` and `Stores/`: item identity, visibility policy, observable local state.
- `Services/`: native leases, inventory, permissions, capture, interaction guard.
- `Views/`: management and tray content.
- `Sources/MenuBarBridge/`: Objective-C runtime and exception boundary.
- `script/` and `scripts/`: build, installed launch, tests, smoke checks.

Tests should cover allow-list preservation, own-app protection, new app defaults, per-app grouping, timeout, cancellation before and after activation, stale callback cleanup, replacement failure, retryable restoration failure, and geometry. Runtime smoke checks exercise the real native service without deliberately hiding user apps. Actual icon disappearance, remote control reachability, third-party activation, system panels, full-screen/autohide, and multiple displays require visible runtime evidence. Existing tests for the earlier compatibility-only build cannot substantiate those results.

## Primary references

- [Hidden Bar's native visibility shim](https://github.com/dwarvesf/hidden/blob/develop/hidden/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.m)
- [Native visibility lifecycle and app grouping](https://github.com/dwarvesf/hidden/blob/develop/hidden/Features/StatusBar/Engine/NativeVisibilityEngine.swift)
- [macOS 27 probes, system identifier range, and installed identity](https://github.com/brentc22/stash/blob/main/docs/superpowers/specs/2026-09-22-stash-design.md)
- [Clock hover suspension](https://github.com/happy666End/MenuBarHider/blob/main/MenuBarHider/App/ClockHoverMonitor.swift)
- [Apple: NSStatusItem.length](https://developer.apple.com/documentation/appkit/nsstatusitem/length)
- [Apple: SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
