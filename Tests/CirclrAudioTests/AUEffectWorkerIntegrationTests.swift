import XCTest
import AVFAudio
import AudioToolbox
import CirclrCore
@testable import CirclrAudio

/// Opt-in offline integration; never creates a hardware output engine.
final class AUEffectWorkerIntegrationTests: XCTestCase {
    func testAppleLowPassWorkerMatchesInProcessPCMAndPreservesInput() async throws {
        guard let path = ProcessInfo.processInfo.environment["CIRCLR_AU_EFFECT_WORKER_TEST_EXECUTABLE"], !path.isEmpty else {
            throw XCTSkip("실제 worker 검증은 CIRCLR_AU_EFFECT_WORKER_TEST_EXECUTABLE 경로가 필요합니다")
        }
        let executable = URL(fileURLWithPath: path)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path), "명시된 worker 실행 파일이 없습니다")
        let descriptor = PluginDescriptor(name: "Apple AULowPassFilter QA", type: kAudioUnitType_Effect,
                                          subtype: kAudioUnitSubType_LowPassFilter,
                                          manufacturer: kAudioUnitManufacturer_Apple)
        var input = PCM(frames: 12_000)
        for frame in input.left.indices {
            let t = Double(frame) / PCM.rate
            input.left[frame] = Float(0.08 * sin(2 * .pi * 220 * t) + 0.04 * sin(2 * .pi * 11_000 * t))
            input.right[frame] = Float(0.07 * sin(2 * .pi * 330 * t) - 0.03 * sin(2 * .pi * 9_000 * t))
        }
        input.left[0] += 0.1
        let originalLeft = input.left, originalRight = input.right
        let configuredUnit = try await AudioUnitHost.instantiate(descriptor)
        XCTAssertEqual(AudioUnitSetParameter(configuredUnit.audioUnit, kLowPassParam_CutoffFrequency,
                                            kAudioUnitScope_Global, 0, 900, 0), noErr)
        XCTAssertEqual(AudioUnitSetParameter(configuredUnit.audioUnit, kLowPassParam_Resonance,
                                            kAudioUnitScope_Global, 0, 3, 0), noErr)
        var configured = descriptor
        configured.state = try XCTUnwrap(AudioUnitHost.capture(configuredUnit))
        XCTAssertFalse(try XCTUnwrap(configured.state).isEmpty)
        var defaultReference: PCM?
        for (label, plugin) in [("default", descriptor), ("captured-state", configured)] {
            let unit = try await AudioUnitHost.instantiate(plugin)
            if label == "captured-state" {
                var cutoff: AudioUnitParameterValue = 0, resonance: AudioUnitParameterValue = 0
                XCTAssertEqual(AudioUnitGetParameter(unit.audioUnit, kLowPassParam_CutoffFrequency,
                                                    kAudioUnitScope_Global, 0, &cutoff), noErr)
                XCTAssertEqual(AudioUnitGetParameter(unit.audioUnit, kLowPassParam_Resonance,
                                                    kAudioUnitScope_Global, 0, &resonance), noErr)
                XCTAssertEqual(cutoff, 900, accuracy: 0.001)
                XCTAssertEqual(resonance, 3, accuracy: 0.001)
            }
            let reference = try AudioUnitHost.process(input, unit: unit)
            let worker = AUEffectWorkerProcess(executable: executable, timeout: 15)
            let output = try await worker.process(input: input, plugin: plugin)
            XCTAssertEqual(input.left, originalLeft)
            XCTAssertEqual(input.right, originalRight)
            XCTAssertEqual(output.count, input.count)
            XCTAssertEqual(reference.count, input.count)
            guard output.count == input.count, reference.count == input.count,
                  output.right.count == input.count, reference.right.count == input.count else {
                XCTFail("worker 또는 reference의 stereo frame count 불일치")
                return
            }
            var maximumError = 0.0, squaredError = 0.0, peak = 0.0, processedDifference = 0.0
            for (actualChannel, referenceChannel, inputChannel) in [(output.left, reference.left, originalLeft),
                                                                   (output.right, reference.right, originalRight)] {
                XCTAssertEqual(actualChannel.count, input.count)
                for index in actualChannel.indices {
                    let actual = Double(actualChannel[index]), expected = Double(referenceChannel[index])
                    XCTAssertTrue(actual.isFinite && expected.isFinite)
                    let error = abs(actual - expected)
                    maximumError = max(maximumError, error)
                    squaredError += error * error
                    peak = max(peak, abs(actual))
                    processedDifference = max(processedDifference, abs(expected - Double(inputChannel[index])))
                }
            }
            let rmsError = sqrt(squaredError / Double(input.count * 2))
            XCTAssertGreaterThan(peak, 0.001, "무음 결과는 정상 PCM 비교를 대신하지 않습니다")
            XCTAssertGreaterThan(processedDifference, 0.001, "reference가 실제 effect 처리를 해야 합니다")
            XCTAssertLessThanOrEqual(maximumError, 0.00001)
            XCTAssertLessThanOrEqual(rmsError, 0.000001)
            if let defaultReference {
                let stateDifference = zip(reference.left, defaultReference.left).map { abs($0.0 - $0.1) }.max() ?? 0
                XCTAssertGreaterThan(stateDifference, 0.001, "캡처한 AU state가 실제 PCM을 바꿔야 합니다")
            } else {
                defaultReference = reference
            }
            print("AU_EFFECT_WORKER_PCM configuration=\(label) frames=\(output.count) peak=\(peak) maxError=\(maximumError) rmsError=\(rmsError)")
        }
    }
}
