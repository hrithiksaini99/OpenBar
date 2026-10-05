# Validation

Machine: Apple Silicon, macOS 27.0.1, Swift 6.4, Command Line Tools. Deployment target: macOS 14.

| Check | Result |
| --- | --- |
| Debug compilation, Swift 6 strict concurrency | Passed |
| Release compilation and release bundle signature | Passed; `codesign --verify --deep --strict` succeeded |
| XCTest via installed full Xcode | 8 tests passed, 0 failures; [output](tests.txt) |
| Spec `--self-check` | Passed; geometry and both symbols |
| Debug `.app` packaging and launch | Passed; plist validated, ad-hoc signed, process confirmed |
| Final release bundle launch | Passed; one running OpenBar process confirmed |
| Native smoke check on macOS 27 | Passed compatibility guard, on-screen control, 10 rapid click/Show All cycles, no permission flow; [output](native-smoke.txt) |
| Original spacer-based hide probe on macOS 27 | Failed the eviction assertion; test status item remained visible according to its AppKit window after the spacer expanded to 8,000 points |
| Native UI automation | Could not attach to the windowless accessory app; no visual click verification claimed |
| Tray capture and real third-party item activation | Not executed; Accessibility and Screen Recording were not granted |
| Runtime hiding on macOS 14–26 | Not executed; no such runtime is available on this machine |

The final macOS 27 behavior is intentional: the app explains that the spec’s hiding mechanism is unsupported and leaves the bar visible. It never commits a false tucked state on that OS. This is a compatibility fallback, not completion of macOS 27 hiding. The public-API implementation for macOS 14–26 remains in the source, awaiting runtime validation on those systems.

The initial runtime probe found a stable control but failed to evict a disposable status item. [Hidden Bar’s architecture documentation](https://github.com/dwarvesf/hidden/blob/develop/docs/ARCHITECTURE.md) independently describes length-inflation breakage on macOS 27. Its [replacement bridge](https://github.com/dwarvesf/hidden/blob/develop/hidden/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.m) uses a private `MenuBarClientCore` framework. That workaround is not part of this public-API build.

The Command Line Tools build engine emits linker search-path warnings for its missing `Developer/Library/Frameworks` and `Developer/usr/lib` directories. App compilation and launch succeed. XCTest is resolved by `script/test.sh`, which selects the existing full Xcode installation for that command only. No software was installed and the global `xcode-select` setting was not changed.
