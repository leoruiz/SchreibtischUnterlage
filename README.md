# Schreibtischunterlage

A lightweight Apple Silicon virtual display for screen sharing on macOS.

Schreibtischunterlage is a clean-sheet macOS application inspired by
[DeskPad](https://github.com/Stengo/DeskPad). It will create a guarded virtual
display and show its contents in a low-latency Metal preview window.

## Status

Early development. The initial application intentionally launches without
creating or changing any displays.

## Design constraints

- Apple Silicon and macOS 15 or newer
- Swift and AppKit
- ScreenCaptureKit and one purpose-built Metal renderer
- Explicit Start and Stop actions
- No automatic virtual display creation at launch
- No third-party runtime dependencies

## Build

The repository is a Swift package and can be opened directly in Xcode.
Command Line Tools are sufficient for tests and ad-hoc local app bundles:

```sh
make test
make app
```

The application bundle is written to:

```text
.build/Schreibtischunterlage.app
```

## Attribution

DeskPad by Bastian Andelefski established the virtual-display workflow that
inspired this project. Any DeskPad implementation incorporated later will
retain its MIT license and attribution.
