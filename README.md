# OpenBar

**Development status:** the macOS 27 backend builds and runs, but a live preservation test still removes four unidentified items when all apps are allowed. See [PROGRESS.md](PROGRESS.md) for current evidence and blockers. Selective visibility is not yet ready for production.

OpenBar is a native menu bar manager with saved app visibility rules and an optional tray for opening hidden controls. On macOS 27 it uses the system's native menu bar visibility service instead of the spacer technique from the supplied photographs, which no longer works on this OS.

The policy allow-lists system controls and newly launched apps by default; actual preservation remains under investigation. It has no account, third-party dependencies, telemetry, network requests, or saved screenshots. Its management window stores your choices locally.

## Run

Requires macOS 14+, Swift 6.2+ and full Xcode for building the SwiftUI app and XCTest suite. The macOS 27 implementation is being validated on macOS 27.0.1.

Use the **Run** button in Codex, or:

```sh
./script/build_and_run.sh
```

The run workflow builds the app and launches its installed copy at `/Applications/OpenBar.app`. macOS must resolve that same bundle identity through LaunchServices to keep OpenBar's own control visible while a native restriction is active. A raw executable or an arbitrary duplicate bundle is unsuitable for this mode. If installation is unavailable, the app reports the problem and leaves hiding disabled.

To generate a release bundle without launching:

```sh
./scripts/build-app.sh
```

The generated artifact is `dist/OpenBar.app`. Bundles are ad-hoc signed for local use; this is not a notarized distribution build. Rebuilding an ad-hoc signed app can invalidate previously granted Accessibility or Screen Recording access even when System Settings still shows an enabled switch. Reauthorize the installed copy if macOS reports that access is missing.

## Choose what stays visible

Right-click OpenBar's tray icon and select **Manage Menu Bar…**. Search the app list, then choose a rule for each app:

| Rule | While hidden | In the tray |
| --- | --- | --- |
| Visible | Remains in the menu bar | No |
| In Tray | Hidden | Yes, when discoverable through Accessibility |
| Hidden Only | Hidden | No |

Click **Hide Selected**, or close the window and click OpenBar's menu bar icon. The next click opens the tray. With no selected apps, that click opens the management window instead. Opening management restores the bar so it is easy to arrange and inspect items.

**Show All** restores everything without deleting your saved rules. Quitting releases the native visibility restriction. Launch starts with the bar shown.

On macOS 27 a rule applies to all status items owned by the same app. It controls visibility across every display; it does not reorder icons or move them into a second native menu bar. Command-drag remains macOS's mechanism for rearranging the actual bar, while OpenBar's three saved rules determine its visibility groups. Apple system apps are excluded from rule editing.

## Tray and permissions

Basic hiding, managing saved rules, and Show All need neither Accessibility nor Screen Recording.

- **Accessibility** enables menu bar item discovery and pressing a real control from the tray. OpenBar requests it when you open the tray or select **Enable Accessibility**. It refreshes permission state when you return to the app.
- **Screen Recording** is optional. **Enable Live Icons** requests it explicitly. With access, the tray captures fresh icon pixels in memory. Without access, it uses the owning app's icon and keeps the item usable.

Captures are cropped to individual items, respect the display's pixel scale, and are discarded with the tray. A notch, failed capture, or vanished capture target falls back to an app icon. No screen permission prompt appears simply because you open the tray.

When you select a tray item, OpenBar makes its app visible and resolves the current Accessibility element again before pressing it. If an Accessibility press is unsupported, it attempts a click at the freshly resolved on-screen position. Items that expose no usable Accessibility control cannot be opened this way.

## Recovery and macOS 27 trade-offs

OpenBar temporarily restores the bar during menu bar interaction and waits before resuming hiding. This protects access to system panels, including Notification Center: the underlying visibility restriction otherwise prevents the clock from opening it. **Show All**, opening management, display changes, sleep/wake, and shutdown release the restriction and cancel pending work. App launches and rule edits rebuild the allow-list so unconfigured apps remain visible.

If the control becomes unavailable, exit OpenBar from Terminal:

```sh
pkill -x OpenBar
```

The macOS 27 backend dynamically loads the private `MenuBarClientCore` framework. It checks the required classes and method signatures, catches Objective-C exceptions, times out unconfirmed activation, and invalidates cancelled or late results. A missing or changed API produces a recoverable error. This private API is a compatibility trade-off: Apple may change it in a future update, and this implementation is unsuitable for the Mac App Store. OpenBar does not start a full assessment session, unload system menu extras, or alter global menu bar preferences.

System item identifiers are also private. The current preservation range is `0..<256`; upstream measurements found that a smaller range could unexpectedly hide Screen Mirroring. System-panel behavior must be rechecked after OS updates. [Native API research](https://github.com/brentc22/stash/blob/main/docs/superpowers/specs/2026-09-22-stash-design.md), [clock interaction workaround](https://github.com/happy666End/MenuBarHider/blob/main/MenuBarHider/App/ClockHoverMonitor.swift).

macOS 14–26 retain the original spacer backend. Place OpenBar to the right of its separators and Command-drag items into the photographed layout. Runtime behavior on those releases is not established by testing on this macOS 27 machine.

## Checks and validation

```sh
./script/test.sh
./script/smoke_test.sh
.build/debug/OpenBar --self-check
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
```

The test suite exercises pure policy and geometry, plus the native service's activation, replacement, timeout, cancellation, and restoration lifecycle with a fake backend. The debug smoke check exercises the real native service while allow-listing running apps and system identifiers. It does not grant permissions or verify a third-party tray click.

The current evidence and outstanding manual checks belong in [VALIDATION.md](general/validation/VALIDATION.md). The earlier compatibility-only build's results are not proof that the replacement backend works. Confirm visible hiding/restoration, own-control reachability, clock/Control Center/Screen Mirroring, and optional tray capture on the exact installed build before calling those workflows verified. Multi-display and macOS 14–26 behavior require their own runtime checks.

See [DESIGN.md](DESIGN.md) for the architecture and changes from the supplied specifications. For a visual introduction to the optional capture path, search YouTube for **Apple Developer ScreenCaptureKit WWDC23**, or watch [What's new in ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2023/10136/).
