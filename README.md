# RapooFlow

Lightweight, native macOS menu bar utility for mouse wheel smooth scrolling, independent wheel direction reversal, and Rapoo mouse (VID `0x24AE`, USB/Bluetooth) button remapping.

## Features

- **Mos-like Smooth Scrolling**: Moving-target linear interpolation (`Interpolator.lerp`) combined with a 5-point S-curve onset polish filter (`ScrollFilter`) and `deadZone` cutoff for smooth, predictable per-notch travel without initial jumpiness.
- **Independent Mouse Wheel Reversal**: Inverts all three CoreGraphics scroll axis representations (`DeltaAxis`, `FixedPtDeltaAxis`, `PointDeltaAxis`) for mouse wheels while leaving built-in Trackpad gestures and continuous streams untouched.
- **Modifier Shortcuts (Mos-compatible)**:
  - `Option` (Dash): 5x speed amplification while held.
  - `Shift` (Toggle): Converts vertical wheel movement into horizontal scrolling.
  - `Command` (Block): Temporarily bypasses smooth interpolation (useful for `Cmd + Scroll` zooming).
  - **Left Mouse Click**: Immediately brakes active scroll momentum.
- **Menu Bar Presets & Tuning**:
  - Built-in presets: **Mos Default** (`step: 33.6`, `speed: 2.70`, `duration: 4.35`), **Smooth**, **Responsive**, and **Quick**.
  - Individual submenus for **Scroll duration**, **Scroll distance (`step`)**, and **Speed**.
- **Rapoo Side Button Remapping**: Translates Forward → Paste (`Cmd+V`) and Back → Copy (`Cmd+C`), including hardware HID driver-mode `Ctrl+V`/`Ctrl+C` reports from Rapoo mice without interfering with normal keyboard `Ctrl+C`/`Ctrl+V`.
- **Per-Application Exclusions**: Quickly exclude or re-enable the currently active application from the menu bar.

## Build & Run

Run `./build.sh` on macOS with Swift Command Line Tools installed:

```bash
./build.sh
```

This compiles the sources with zero warnings and outputs an ad-hoc code-signed `RapooFlow.app` bundle in the project root.

## Testing

Run the automated 4-tier test suite (42 tests covering unit math, headless `CGEvent` pipeline, 60/120/144Hz stepped frame clocks, and hardware/bundle integration):

```bash
./Tests/run_tests.sh
```
