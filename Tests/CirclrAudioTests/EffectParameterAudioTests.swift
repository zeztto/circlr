import XCTest
import CirclrCore
@testable import CirclrAudio

final class EffectParameterAudioTests: XCTestCase {
    func effect(_ kind: EffectKind, _ values: [Double]) throws -> Effect {
        var result=Effect(kind)
        for (parameter,value) in zip(EffectParameter.all(for:kind),values) {result=try parameter.applying(value,to:result)}
        return result
    }
    func testFrequencyAndDelayUnitsMatchActualDSPTime() throws {
        var impulse=PCM(frames:48001);impulse.left[0]=1;impulse.right[0]=0.5
        let filter=try NativeDSP.process(impulse,effect:effect(.lowpass,[1000]))
        XCTAssertEqual(filter.left[0],Float(1-exp(-2*Double.pi*1000/48000)),accuracy:1e-6)
        let delay=try NativeDSP.process(impulse,effect:effect(.delay,[500,50]))
        XCTAssertEqual(delay.left[0],1);XCTAssertEqual(delay.left[23999],0)
        XCTAssertEqual(delay.left[24000],0.5);XCTAssertEqual(delay.right[24000],0.25)
        XCTAssertEqual(delay.left[48000],0.125);XCTAssertEqual(delay.right[48000],0.25)
    }
    func testCompressionAndLevelUnitsMatchActualDSP() throws {
        var signal=PCM(frames:48000)
        signal.left=Array(repeating:0.5,count:signal.count);signal.right=Array(repeating:0.25,count:signal.count)
        let compressed=try NativeDSP.process(signal,effect:effect(.compressor,[-18,4]))
        let expected=0.5*pow(0.5/pow(10,-18.0/20),1.0/4-1)
        XCTAssertEqual(Double(compressed.left.last!),expected,accuracy:1e-5)
        let gain=try NativeDSP.process(signal,effect:effect(.gain,[2]))
        XCTAssertEqual(gain.left[0],1);XCTAssertEqual(gain.right[0],0.5)
        let pan=try NativeDSP.process(signal,effect:effect(.pan,[-100]))
        XCTAssertEqual(pan.right[0],0);XCTAssertEqual(pan.left[0],Float(0.5*sqrt(2)),accuracy:1e-6)
        let drive=try NativeDSP.process(signal,effect:effect(.drive,[10]))
        XCTAssertEqual(drive.left[24000],Float(tanh(Double(5))/tanh(Double(10))),accuracy:1e-6)
        let dry=try NativeDSP.process(signal,effect:effect(.reverb,[50,0]))
        XCTAssertEqual(dry.left,signal.left);XCTAssertEqual(dry.right,signal.right)
    }
}
