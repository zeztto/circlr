import XCTest
import AVFAudio
import CirclrCore
@testable import CirclrAudio

final class AudioClipEditingTests:XCTestCase {
    func fixture(_ root:URL,sampleRate:Double=48000)throws->Project {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url=root.appendingPathComponent("source.wav"),format=try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate:sampleRate,channels:2))
        let count=Int(sampleRate*1.6),buffer=try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:UInt32(count)))
        buffer.frameLength=UInt32(count)
        for i in 0..<count {buffer.floatChannelData![0][i]=Float(0.17*sin(Double(i)*733/sampleRate)+0.07);buffer.floatChannelData![1][i]=Float(0.13*cos(Double(i)*1211/sampleRate)-0.04)}
        let file=try AVAudioFile(forWriting:url,settings:format.settings);try file.write(from:buffer)
        var p=Project();_=p.addTrack(name:"source");_=p.addSection(name:"edit",at:Point(),bars:2)
        let asset=Asset(name:"source",path:url.path,duration:1.6,sampleRate:sampleRate);p.assets=[asset]
        var clip=AudioClip(assetID:asset.id,duration:1.2,beat:0.17);clip.sourceStart=0.137
        p.sections[0].lanes[0].audio=[clip]
        return try SectionGraphMigration.migrate(p)
    }
    func render(_ p:Project)async throws->PCM {try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0).mix}
    func difference(_ a:PCM,_ b:PCM)->Float {
        XCTAssertEqual(a.count,b.count)
        return max(zip(a.left,b.left).map{abs($0-$1)}.max() ?? 0,zip(a.right,b.right).map{abs($0-$1)}.max() ?? 0)
    }
    func testInvalidRateAndFrameRangeFailBeforeReadingSource()throws {
        let url=URL(fileURLWithPath:"/nonexistent/circlr-audio-qa.wav")
        var clip=AudioClip(assetID:"qa",duration:1)
        for rate in [Double.leastNonzeroMagnitude,0,Double.infinity,Double.nan,4.01] {
            XCTAssertThrowsError(try ClipAudioRenderer.read(clip,url:url,rate:rate,remaining:1)) {XCTAssertTrue($0 is CirclrError)}
        }
        clip.sourceStart=Double.greatestFiniteMagnitude
        clip.renderWindow=try JSONDecoder().decode(AudioRenderWindow.self,from:Data(#"{"sourceStart":0,"duration":1,"cycleBeat":0,"automaticEdges":false,"envelopes":[]}"#.utf8))
        XCTAssertThrowsError(try ClipAudioRenderer.read(clip,url:url,rate:1,remaining:1)) {XCTAssertTrue($0 is CirclrError)}
    }
    func testSplitAndRecursiveSplitMatchSourceAcrossResamplingFadesAndTempo()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-clip-\(newID())");defer{try? FileManager.default.removeItem(at:root)}
        for variant in 0..<5 {
            var p=try fixture(root.appendingPathComponent("\(variant)"),sampleRate:variant==1 ? 44100:48000)
            let use=p.active.uses[0].id;var graph=p.sections[0].graph!,ci=try XCTUnwrap(p.sections[0].graph?.nodes.firstIndex{if case .audio=$0.content{return true};return false})
            let node=graph.nodes[ci].id;graph.nodes[ci].repeatCount=3
            if variant==2 {graph.nodes[ci].settings.tempo = .local(150);graph.nodes[ci].lengthBeats=1.7;graph.nodes[ci].startBeat=0.21}
            if variant==3 {p.sections[0].tempoChanges=[TempoChange(beat:3,bpm:80)];graph.nodes[ci].lengthBeats=3;graph.nodes[ci].repeatCount=2}
            if variant==4 {p.sections[0].lanes[0].audio[0].followsTempo=true;graph.nodes[ci].settings.tempo = .local(144)}
            p.sections[0].graph=graph
            if variant==1 {_=try AudioEditing.apply(.fade(input:0.6,output:0.4),nodeID:node,useID:use,in:&p)}
            let before=try await render(p)
            let right=try XCTUnwrap(AudioEditing.apply(.split(sourceOffset:0.427),nodeID:node,useID:use,in:&p))
            let after=try await render(p)
            XCTAssertLessThanOrEqual(difference(before,after),0.0000002,"variant \(variant)")
            _=try AudioEditing.apply(.split(sourceOffset:0.15),nodeID:right,useID:use,in:&p)
            let recursive=try await render(p)
            XCTAssertLessThanOrEqual(difference(before,recursive),0.0000002,"recursive \(variant)")
        }
    }
    func testExplicitFadeAttenuatesAudioAndCanBeRemoved()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-fade-\(newID())");defer{try? FileManager.default.removeItem(at:root)}
        var p=try fixture(root);let use=p.active.uses[0].id,node=try XCTUnwrap(p.sections[0].graph?.nodes.first{if case .audio=$0.content{return true};return false}).id
        _=try AudioEditing.apply(.fade(input:0,output:0),nodeID:node,useID:use,in:&p);let dry=try await render(p)
        _=try AudioEditing.apply(.fade(input:0.5,output:0.5),nodeID:node,useID:use,in:&p);let faded=try await render(p)
        XCTAssertLessThan(faded.slice(4500..<6000).rms,dry.slice(4500..<6000).rms*0.15)
        XCTAssertLessThan(faded.rms,dry.rms*0.85)
        XCTAssertEqual(faded.slice(31000..<34000).left,dry.slice(31000..<34000).left)
        _=try AudioEditing.apply(.fade(input:0,output:0),nodeID:node,useID:use,in:&p)
        let restored=try await render(p);XCTAssertEqual(restored.left,dry.left);XCTAssertEqual(restored.right,dry.right)
    }
}
