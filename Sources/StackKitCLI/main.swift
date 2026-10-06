import Foundation
import StackKit

// `starlapse-stack` — compare stacking pipelines on an emulated night sky.
//
// Every number is measured against a sky with a known answer, through a camera model
// that quantises and curves the light the way a phone does. Same photons for every
// pipeline, so the differences are the pipelines.

func value(_ flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func number(_ value: Float, _ digits: Int = 2) -> String {
    String(format: "%.\(digits)f", value)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "compare"

if command == "tone" {
    // The display defaults for linear input, derived from the ones tuned on encoded input.
    let shipped = ToneCurve(blackPoint: 0.02, stretch: 12)
    let fitted = ToneCurve.fitLinear(matching: shipped, transfer: .bt709)
    print("encoded  blackPoint 0.02    stretch 12")
    print("linear   blackPoint \(number(fitted.blackPoint, 4))  stretch \(number(fitted.stretch, 1))\n")
    print(pad("linear in", 12) + pad("shipped", 10) + "fitted")
    for linear: Float in [0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5] {
        print(pad(number(linear, 3), 12) + pad(number(shipped.apply(TransferFunction.bt709.encode(linear)), 3), 10)
              + number(fitted.apply(linear), 3))
    }
    exit(0)
}

guard command == "compare" else {
    print("""
        usage: starlapse-stack tone | compare [--frames N] [--sky L] [--electrons E] [--read R] [--clean]
          --frames     light frames in the stack (40)
          --sky        sky background, linear 0...1 (0.02 dark site, 0.06 suburb)
          --electrons  electrons at full scale; lower = higher ISO, more shot noise (800)
          --read       read noise, linear (0.003)
          --clean      no satellite, no drift
        """)
    exit(command == "help" || command == "--help" ? 0 : 1)
}

var camera = CameraModel()
if let electrons = value("--electrons", in: arguments).flatMap(Float.init) { camera.electronsAtFullScale = electrons }
if let read = value("--read", in: arguments).flatMap(Float.init) { camera.readNoise = read }
let sky = value("--sky", in: arguments).flatMap(Float.init) ?? 0.02
let frames = value("--frames", in: arguments).flatMap(Int.init) ?? 40
let clean = arguments.contains("--clean")

let experiment = StackExperiment(
    scene: .field(background: sky),
    camera: camera,
    frames: frames,
    satellite: clean ? nil : (frame: frames / 2, row: 30),
    driftPerFrame: clean ? 0 : 0.5
)

print("sky \(sky)  frames \(frames)  e-/full \(camera.electronsAtFullScale)  read \(camera.readNoise)\n")
print(pad("pipeline", 26) + pad("noise", 9) + pad("bias", 9) + pad("faintSNR", 10)
      + pad("hot σ", 8) + pad("sat σ", 8) + "edge")
for pipeline in StackPipeline.candidates {
    let quality = experiment.run(pipeline)
    print(pad(pipeline.name, 26) + pad(number(quality.noise, 5), 9) + pad(number(quality.bias, 5), 9)
          + pad(number(quality.faintStarSNR), 10) + pad(number(quality.hotPixelResidual, 1), 8)
          + pad(number(quality.satelliteResidual, 1), 8) + number(quality.edgeRatio))
}
