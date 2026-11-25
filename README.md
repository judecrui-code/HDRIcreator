# HDRI Creator (native iOS, Swift/SwiftUI)

Guided 28-position spherical capture for HDRI panoramas. **Work in progress: stage 1 of the build plan.**

## Build (on a Mac with Xcode 15+)
```bash
brew install xcodegen
cd HDRICreator && xcodegen generate && open HDRICreator.xcodeproj
```
Select your iPhone (a real device is required: no camera/gyro in the simulator), set your Team under Signing, Run.
Unit tests (`⌘U`) cover the layout maths and run in the simulator.

## Status — be skeptical of anything not listed as done
This code was written on a Linux machine with **no Swift compiler**. It passes a syntax parse only; it has
**never been compiled or run**. Expect a few compile errors on first build; paste them back and they get fixed.

| Stage | State |
|---|---|
| Xcode project spec, Info.plist privacy strings, module folders | written, not built |
| 28-position layout (1 zenith + 3×8 rings + nadir + 2 greedy supplementals) | written; geometry validated with a Python reference model (100% sphere coverage), Swift port untested |
| Camera preview, lens select, AE/AWB/focus lock, EV, capability detection | written, untested on device |
| CoreMotion aiming, stability, level, auto-capture, redo, skip | written, untested on device — **the attitude sign convention is the main thing to verify** (phone flat face-up should read elevation −90°; pointing at the sky +90°) |
| Live sphere guide, home screen, projects, storage | written, untested |
| Bracketing (3/5/7/custom), RAW capture | NOT implemented |
| HDR merge, alignment, stitching, ghost reduction | NOT implemented in Swift (a validated Python prototype of the maths exists separately) |
| OpenEXR writer, 4K/8K/16K export | NOT implemented |
| Viewer | NOT implemented |

`Tools/layout_check.py` is the reference model for the layout.
