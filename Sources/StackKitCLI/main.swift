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

guard command == "compare" else {
    print("""
        usage: starlapse-stack compare [--frames N] [--sky L] [--electrons E] [--read R] [--clean]
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
    let q = experiment.run(pipeline)
    print(pad(pipeline.name, 26) + pad(number(q.noise, 5), 9) + pad(number(q.bias, 5), 9)
          + pad(number(q.faintStarSNR), 10) + pad(number(q.hotPixelResidual, 1), 8)
          + pad(number(q.satelliteResidual, 1), 8) + number(q.edgeRatio))
}
