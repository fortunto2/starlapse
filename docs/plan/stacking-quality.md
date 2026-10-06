# Stacking quality — native formats, linear math, outlier rejection

Goal: shoot in the best format the sensor offers, convert it ourselves, and stack
correctly. Every variant is measured on an emulated sky through the CLI before it
reaches Metal.

## Tasks

- [x] A1 StackKit `ColorDecode`: BT.709 YCbCr (8/10-bit, video/full range) → RGB, transfer decode
- [x] A2 StackKit `StackCombiner` (CPU reference): mean, sigma-clip, lighten, comet; per-pixel coverage; master dark
- [x] A3 StackKit `SkySimulator`: linear sky → shot/read noise, hot pixels, satellite, drift → OETF → N-bit quantize
- [x] A4 StackKit `StackQuality` metrics vs ground truth
- [x] A5 `starlapse-stack compare` CLI: shipped pipeline vs variants, table
- [x] A6 Tests for A1–A4
- [x] B1 Metal: decode biplanar 420 (8/10-bit) into linear rgba16Float; BGRA via `_srgb` view
- [x] B2 Metal: coverage-normalised resolve (divide by alpha, not frameCount)
- [x] B3 Metal: sigma-clip on luminance (extra r32Float M2 texture)
- [x] B4 Output: ask the camera for the format's native 420 subtype for stacking; BGRA stays for the detector
- [x] B5 FormatChoice: prefer 10-bit native, Log/ProRes still last
- [x] B6 Retune default tone for linear input (CLI computes the mapping)
- [x] C  Build, tests, lint, commit; device check is blocked on an iPhone

## Decisions

- Detector mode keeps BGRA: its ring buffer and ClipWriter copy single-plane buffers.
- Dark frames: CPU reference + CLI measurement now; capture flow (cover the lens) later.
