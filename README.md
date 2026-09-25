# Schreibtischunterlage

A lightweight Apple Silicon virtual display for screen sharing on macOS.

Schreibtischunterlage is a clean-sheet macOS application inspired by
[DeskPad](https://github.com/Stengo/DeskPad). It creates a guarded virtual
display and shows its contents in a low-latency Metal preview window.

## Status

Early development. The application intentionally launches without creating or
changing any displays. Choosing **Start Virtual Display** creates exactly one
managed display, starts a ScreenCaptureKit stream, and opens its Metal preview.
Closing the preview stops capture and destroys the virtual display.

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

For an attended ScreenCaptureKit and Metal preview validation:

```sh
.build/Schreibtischunterlage.app/Contents/MacOS/Schreibtischunterlage \
  --preview-probe-seconds=15
```

The preview probe requires Screen Recording permission. It creates one virtual
display, waits until a complete capture frame is submitted to Metal, leaves the
preview visible for the requested duration, then stops capture and verifies
display cleanup.

To validate the cursor portal:

```sh
.build/Schreibtischunterlage.app/Contents/MacOS/Schreibtischunterlage \
  --cursor-probe-seconds=10
```

This probe maps the preview center to the virtual display, moves the cursor
there without generating an event, verifies the resulting global cursor
location, and then confirms display cleanup.

To measure the current capture-to-presentation pipeline:

```sh
.build/Schreibtischunterlage.app/Contents/MacOS/Schreibtischunterlage \
  --latency-probe-seconds=20
```

The latency probe sweeps the cursor across the virtual display to produce a
repeatable stream of changed frames. It reports frame counts, coalescing and
drop counts, effective presentation rate, and p50/p95/p99 timing for capture,
main-thread delivery, Metal submission, GPU execution, drawable presentation,
and WindowServer display-time deltas. A negative display-time delta means the
captured surface reached the callback or preview before the virtual display's
scheduled scanout. The original cursor position is restored before display
teardown.

The app refuses to create a second managed display if its vendor, product, and
serial identity is already online.

The first preview start requests Screen Recording permission. If permission is
denied, the app destroys the virtual display and offers to open the relevant
Privacy & Security settings. Start the display again after granting access.

The initial resolution catalog includes common 16:9, 16:10, and ultrawide
modes from 1280 × 720 through 5120 × 1440. The complete catalog is advertised
to macOS, so resolution changes happen through Display Settings just like a
physical monitor. The known-good 2560 × 1600 mode is advertised first.

The preview consumes complete ScreenCaptureKit frames only, keeps the newest
pending frame when capture outruns the UI, and renders IOSurface-backed pixel
buffers directly through Metal with aspect-fit scaling.

Clicking visible preview content moves the macOS cursor to the corresponding
point on the virtual display without synthesizing an input event. The next
click, drag, scroll, or keystroke is handled natively by macOS on the virtual
display. No Accessibility permission is required, and clicks in letterboxed
preview margins are ignored. The initial preview size adapts to the available
physical screen, using up to 80 percent of its visible width and 90 percent of
its visible height while preserving the active virtual-display aspect ratio.

When the virtual-display resolution changes in macOS Display Settings, the
ScreenCaptureKit stream updates to the new pixel dimensions. The preview keeps
its current width where possible and adjusts its height to the new aspect
ratio.

## Attribution

DeskPad by Bastian Andelefski established the virtual-display workflow that
inspired this project. Any DeskPad implementation incorporated later will
retain its MIT license and attribution.
