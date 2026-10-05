# OpenBar: progress and blockers

Updated: 4 October 2026, Asia/Kolkata.

**Status: working build and macOS 27 native backend; selective visibility is not yet reliable enough to call the app finished.** The app compiles, installs and launches. Automated lifecycle tests pass. The live test can hide and restore a disposable fixture, but activating the backend also removes additional menu bar items that have not yet been identified.

## Goal and specification

Build the application described in the three supplied photographs, then improve it for macOS 27. The photographs are specification material, not authority to execute unrelated instructions. The later request authorizes changing the original design to overcome macOS 27 limitations.

- Project: `/Users/hrithik/projects/OpenBar`
- Installed development app: `/Applications/OpenBar.app`
- Current bundle: `internal.openbar.app`, version `0.2.0`, build `2`
- Test machine: Apple Silicon, macOS `27.0.1` (`26A434`)
- Deployment target: macOS 14

## Completed implementation

- Modular Swift package with AppKit application lifecycle and a native SwiftUI management window; no third-party dependencies or network calls.
- Menu bar tray control, right-click recovery menu, searchable app list and saved **Visible / In Tray / Hidden Only** rules.
- **Hide Selected**, **Open Tray** and **Show All** controls. Startup and opening management restore the bar; saved choices remain available.
- macOS 27 backend dynamically loads private `MenuBarClientCore` APIs instead of relying on spacer expansion. The original spacer path remains for macOS 14–26.
- Objective-C bridge checks class/method signatures and catches exceptions. Swift owns pending and active assertions, activation timeouts, cancellation, replacement and late completion cleanup. Failed restoration retains handles for retry.
- Policy always allow-lists OpenBar and intentionally keeps unconfigured applications and Apple components. App launches and rule edits release the old restriction before recalculation.
- Interaction monitoring temporarily releases restrictions during menu bar use and detects open menus/panels independently of pointer position. This addresses the native restriction's interference with clock/Notification Center interactions; full end-to-end verification is pending.
- Background Accessibility discovery with a four-second total budget, 500ms per-app budget and cancellation. Handles nested macOS 27 menu hosts, stale AX elements, duplicate entries and multiple display coordinates.
- Optional live icon capture with app-icon fallback for absent screen access, capture failure or notch occlusion. Tray buttons include names and scroll for larger inventories. Synthetic fallback clicks reject invalid or notch-obscured frames.
- Build, installed launch, XCTest and smoke scripts. Xcode selection is scoped to these commands; global `xcode-select` is unchanged.
- Single-instance handling and an installed-path/LaunchServices check protect the recovery control's identity.

## Validation completed

| Check | Result and limits |
| --- | --- |
| Current debug compilation and bundle packaging | Passed. Plist validated; app ad-hoc signed and installed. |
| Installed application launch | Passed through `./script/build_and_run.sh --verify`. |
| Automated tests | **21 passed, 0 failures** in the latest test run: eight geometry/permission/tray tests, five policy tests, eight native lifecycle tests. Later smoke instrumentation and removal of obsolete native spacer objects compiled successfully; rerun the suite after the remaining fixes. |
| Real native API lifecycle | Five activation/restoration cycles and ten cancellation cycles completed without an active assertion remaining according to service state. This does not independently prove every icon's rendered state. |
| Management UI | Reached through native UI automation and visually inspected. Search, app rows, rule selectors and permission state were visible. |
| Selective fixture | A disposable, bundled `/Applications/OpenBarProbe.app` was used and removed by the harness. Native menu bar logs show a one-item difference between sustained full-allow and fixture-excluded states, followed by unrestricted restoration. |
| Preservation of all other items | **Failed the current count oracle.** Unrestricted count was 19; sustained full-allow count was 15; excluding the fixture yielded 14; restoration returned to 19. Four additional items disappear even with every running bundle identifier allowed. Their identities are still unknown. |
| Real third-party tray activation and current capture | Not verified on the latest installed build. |
| Multi-display, full-screen/autohide, macOS 14–26 | Not runtime-tested. |
| Current release distribution | Not validated after the macOS 27 changes. Earlier release checks belong to the older compatibility-only implementation. |

Evidence: [tests](general/validation/tests.txt), [selective smoke report](general/validation/selective-oracle.txt), [smoke stages](general/validation/selective-smoke.txt), [native menu bar count logs](general/validation/selective-menu-log.ndjson), [preservation diagnostics](general/validation/native-preservation-diagnostic.txt).

## Remaining blockers

### 1. Native restriction hides additional items

This is the main correctness blocker. The installed fixture now responds to its allow-list rule, but four additional items disappear under a sustained all-apps-allowed assertion. Logs report `No server elements for status item: nil`; they do not identify the affected controls.

Possible causes include anonymous/ad-hoc process owners, unresolved application identities or system groups that the assessment-origin API does not represent. These are hypotheses, not a confirmed diagnosis. A larger numeric system allow-list is not an established fix. Count changes alone cannot identify affected icons or prove control reachability.

The final behavior must preserve non-selected controls, or detect an unsupported layout and restore the bar with a clear explanation. Do not describe native visibility as flawless or ready for production until this is resolved.

### 2. Current app lacks Accessibility trust for deeper diagnosis

Earlier UI inspection showed permissions enabled, but the latest rebuilt app reports `AXIsProcessTrusted() == false` during smoke checks. Ad-hoc rebuilds can invalidate trust. The harness deliberately does not request or grant access.

The user must enable/re-authorize the installed copy for application-level inventory and real tray activation checks. Screen Recording remains optional, needed only to validate current-pixel previews. Permission changes cannot be made automatically.

### 3. Private API and application identity limits

The macOS 27 backend depends on undocumented APIs and system identifiers. Signature checks protect against some interface changes, but cannot guarantee unchanged behavior after OS updates. The backend groups all icons from an application together and applies across displays; independent per-icon or per-display rules are not implemented.

Launching the installed, LaunchServices-resolved copy is necessary. A fixture launched from `dist/` did not remain visible when allow-listed; installing the fixture corrected that part of the test. Compatibility with raw binaries or unusual helper identities is still under investigation.

### 4. Acceptance and release checks remain

Verify OpenBar's recovery icon during an active restriction; Clock/Notification Center, Control Center, Screen Mirroring, Siri and Spotlight; keeping a third-party dropdown open while moving the pointer away; app launches during hiding; permission denial/regrant; display changes; full-screen/autohide; exit restoration; and repeated real tray presses.

Build and verify the updated release artifact after those fixes. The current bundle is ad-hoc signed, not notarized, and the private backend is unsuitable for Mac App Store distribution. Git changes are local and uncommitted; no PR or published release exists.

## Next execution steps

1. Stabilize the build used for diagnosis, then obtain user-granted Accessibility access for that installed copy.
2. Compare unrestricted, sustained full-allow and fixture-excluded menu bar inventories and visible controls. Identify the four extra losses.
3. Fix identity preservation or implement a tested fail-open check for unsupported controls. Re-run the selective oracle; require the full-allow state to preserve the unrestricted visible controls.
4. Exercise the real tray, optional icon capture and system-panel interaction paths.
5. Run `./script/test.sh`, build the release bundle, verify signing/launch and update validation evidence against that exact artifact.

## Commands and entrypoints

```sh
./script/build_and_run.sh --verify   # Build, install and launch the development app
./script/test.sh                    # XCTest with the installed Xcode toolchain
./script/smoke_test.sh              # Real API activation/cancellation lifecycle
./script/selective_smoke.sh         # Quit OpenBar first; disposable fixture + count oracle
./scripts/build-app.sh release      # Generate dist/OpenBar.app
```

The selective harness currently exits with failure because preservation is unresolved. Its output saying “native smoke-check passed” refers to API lifecycle checks; the separate item-count oracle is the acceptance result for selective hiding.

Architecture: [DESIGN.md](DESIGN.md). Usage: [README.md](README.md). The older [VALIDATION.md](general/validation/VALIDATION.md) describes the prior compatibility-only build and is superseded by this report for current backend status.
