import Foundation

@main struct TestCanvasFrameTiming {
static func main() {
var timings = CanvasFrameTiming()
assert(timings.diagnostics["calls"] as? Int == 0)
for i in 0..<650 { timings.record(start: Double(i) * 0.02 + 1, end: Double(i) * 0.02 + 1.004) }
let values = timings.diagnostics
assert(values["calls"] as? Int == 650)
assert(values["sampleCount"] as? Int == 600)
assert(abs((values["p95Milliseconds"] as! Double) - 4) < 0.001)
assert(abs((values["maximumStartGapMilliseconds"] as! Double) - 20) < 0.001)
timings.record(start: .nan, end: .nan)
assert(timings.diagnostics["calls"] as? Int == 650)
print("CanvasFrameTiming QA PASS")

}
}
