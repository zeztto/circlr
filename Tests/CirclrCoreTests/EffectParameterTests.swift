import XCTest
@testable import CirclrCore

final class EffectParameterTests: XCTestCase {
    func testPhysicalUnitsAndRanges() throws {
        let cases: [(EffectKind,[Double])] = [(.gain,[0.5]),(.lowpass,[sqrt(800000)]),(.delay,[515,25]),(.drive,[10]),(.pan,[50]),(.compressor,[-21,4.5]),(.reverb,[50,25])]
        for (kind,values) in cases {
            let effect=Effect(kind,amount:0.5,secondary:0.25),parameters=EffectParameter.all(for:kind)
            XCTAssertEqual(parameters.count,values.count)
            for (parameter,value) in zip(parameters,values) {XCTAssertEqual(parameter.value(in:effect),value,accuracy:1e-9)}
        }
        XCTAssertTrue(EffectParameter.all(for:.audioUnit).isEmpty)
        XCTAssertEqual(EffectParameter.all(for:.compressor).last?.range,2...11.5)
        XCTAssertEqual(EffectParameter.all(for:.delay).first?.unit,"ms")
    }
    func testDisplayAndSliderRoundTripAcrossEveryNativeRange() throws {
        for kind in EffectKind.allCases {
            let original=Effect(kind)
            for parameter in EffectParameter.all(for:kind) {
                for index in 0...16 {
                    let position=Double(index)/16,value=parameter.value(at:position)
                    let effect=try parameter.applying(value,to:original)
                    XCTAssertEqual(parameter.value(in:effect),value,accuracy:1e-8)
                    XCTAssertEqual(parameter.sliderPosition(in:effect),position,accuracy:1e-12)
                }
            }
        }
    }
    func testInvalidAndWrongKindEditsAreRejected() throws {
        let parameter=try XCTUnwrap(EffectParameter.all(for:.lowpass).first),before=Effect(.lowpass)
        for value in [Double.nan,.infinity,-.infinity,39,20001] {XCTAssertThrowsError(try parameter.applying(value,to:before))}
        XCTAssertThrowsError(try parameter.applying(1000,to:Effect(.delay)))
        XCTAssertEqual(before,Effect(.lowpass))
    }
    func testLegacyValuesAndVersionedPluginStateSurviveUnrelatedEdits() throws {
        var legacy=Effect(.reverb,amount:2,secondary:0.25);legacy.renderVersion=nil
        legacy.plugin=PluginDescriptor(name:"保存",type:1,subtype:2,manufacturer:3,state:Data([1,2,3]))
        let parameters=EffectParameter.all(for:.reverb)
        XCTAssertEqual(parameters[0].value(in:legacy),100)
        XCTAssertEqual(try parameters[0].applying(100,to:legacy),legacy)
        let changed=try parameters[1].applying(50,to:legacy)
        XCTAssertEqual(changed.amount,2);XCTAssertNil(changed.renderVersion);XCTAssertEqual(changed.plugin,legacy.plugin)
        XCTAssertEqual(changed.secondary,0.5)
        let modern=Effect(.reverb)
        XCTAssertEqual(try parameters[0].applying(25,to:modern).renderVersion,2)
        XCTAssertEqual(EffectParameter.all(for:.gain)[0].value(in:Effect(.gain,amount:-0.5)),-0.5)
        let reloaded=try JSONDecoder().decode(Effect.self,from:JSONEncoder().encode(changed))
        XCTAssertEqual(reloaded,changed)
    }
}
