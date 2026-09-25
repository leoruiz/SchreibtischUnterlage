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
- A curated resolution catalog exposed through macOS Display Settings
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

The manual display probe is intentionally excluded from `make test` because it
changes the live macOS display configuration. Run it only during attended
hardware validation:

```sh
.build/Schreibtischunterlage.app/Contents/MacOS/Schreibtischunterlage \
  --display-probe
```

It creates a virtual display for three seconds, releases it, then verifies that
the baseline displays are unchanged and the virtual display is no longer
online.

For repeated lifecycle validation:

```sh
.build/Schreibtischunterlage.app/Contents/MacOS/Schreibtischunterlage \
  --display-probe-cycles=10
```

The app refuses to create a second managed display if its vendor, product, and
serial identity is already online.

The initial resolution catalog includes common 16:9, 16:10, and ultrawide
modes from 1280 × 720 through 5120 × 1440. The complete catalog is advertised
to macOS, so resolution changes happen through Display Settings just like a
physical monitor. The known-good 2560 × 1600 mode is advertised first.

## Attribution

DeskPad by Bastian Andelefski established the virtual-display workflow that
inspired this project. Any DeskPad implementation incorporated later will
retain its MIT license and attribution.
