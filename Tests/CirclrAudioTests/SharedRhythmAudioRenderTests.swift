import XCTest
import CirclrCore
@testable import CirclrAudio

final class SharedRhythmAudioRenderTests:XCTestCase {
    func testRepeatedSharedSplitPreservesOfflinePCM()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("shared-audio-\(newID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        var pcm=PCM(frames:96000)
        for i in pcm.left.indices {pcm.left[i]=Float(sin(Double(i)*0.021)*0.1);pcm.right[i]=pcm.left[i]}
        let url=root.appendingPathComponent("source.wav");try pcm.writeWAV(url)
        var p=Project();_=p.addTrack(name:"共有");_=p.addSection(name:"反復",at:Point(),bars:3)
        let asset=Asset(name:"source",path:url.path,duration:2,sampleRate:48000);p.assets=[asset]
        var pattern=RhythmPattern(name:"pattern",trackID:p.tracks[0].id)
        var clip=AudioClip(assetID:asset.id,duration:1);clip.fadeIn=0.15;clip.fadeOut=0.2
        pattern.audio=[clip];p.patterns=[pattern];p.global.rhythm.patternID=pattern.id
        p=try SectionGraphMigration.migrate(p)
        // Exercise explicit node cycles as well as repeated pattern expansion.
        let ni=try XCTUnwrap(p.sections[0].graph?.nodes.firstIndex{if case .rhythmAudio=$0.content{return true};return false})
        p.sections[0].graph!.nodes[ni].lengthBeats=12
        func render(_ value:Project)async throws->PCM {
            let u=value.active.uses[0],(s,c,k)=try ArrangementCompiler.context(project:value,use:u)
            let plan=try XCTUnwrap(SectionGraphCompiler.compile(project:value,section:s,use:u,context:c,clock:k))
            let output=try await SectionGraphRenderer.render(plan,project:value,root:nil,clock:k,tail:0,applyOutputGain:false)
            return try XCTUnwrap(output[value.tracks[0].id])
        }
        let before=try await render(p)
        _=try SharedRhythmAudioEditing.apply(.split(sourceOffset:0.5),patternID:pattern.id,trackID:pattern.trackID,clipID:clip.id,in:&p)
        let expanded=ArrangementRenderer.expandPattern(p.patterns[0],length:12,grid:p.global.beatGrid)
        XCTAssertEqual(expanded.audio.map{$0.renderWindow!.cycleBeat},[0,0,4,4,8,8])
        let after=try await render(p)
        XCTAssertEqual(before.count,after.count)
        let error=zip(before.left,after.left).map{abs($0-$1)}.max() ?? 0
        XCTAssertLessThan(error,0.000001)
        XCTAssertGreaterThan(before.left.map{abs($0)}.max() ?? 0,0.01)
    }
}
