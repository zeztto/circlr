import XCTest
import AVFAudio
import CirclrCore
@testable import CirclrAudio

final class RecordingRoundTripTests:XCTestCase {
    /// Controlled callback PCM only; this never opens a microphone or an output device.
    func testCapturedCAFBecomesPortableTakeAndRenderedBounce()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-recording-roundtrip-\(newID())")
        defer{try? FileManager.default.removeItem(at:root)}
        var source=PCM(frames:96_000)
        for i in 0..<source.count {
            source.left[i]=Float(i%127+1)/1024
            source.right[i] = -Float(i%89+1)/1024
        }
        let control=try CaptureControl(),buffer=try source.buffer()
        let writer=try TakeWriter(url:root.appendingPathComponent("captured.caf"),format:buffer.format)
        control.limit(frames:UInt64(source.count));control.append(buffer,to:writer,channels:2)
        control.disable();control.waitForCallbacks();try writer.finish()
        let file=try AVAudioFile(forReading:writer.url)
        XCTAssertEqual(file.length,96_000)
        XCTAssertEqual(file.processingFormat.sampleRate,48_000)
        XCTAssertEqual(file.processingFormat.channelCount,2)
        let readback=try PCM.read(writer.url)
        XCTAssertEqual(readback.left,source.left);XCTAssertEqual(readback.right,source.right)

        var project=Project();let trackID=project.addTrack(name:"녹음 트랙")
        project.tracks[0].gain=1
        let useID=project.addSection(name:"녹음 구간",at:Point(),bars:1)
        project=try SectionGraphMigration.migrate(project)
        let clock=try MusicClock(bars:1,context:project.global)
        let asset=Asset(name:"입력 원본",path:writer.url.path,duration:Double(file.length)/file.processingFormat.sampleRate,sampleRate:file.processingFormat.sampleRate)
        let takeID=try AudioTakeEditing.save(asset:asset,projectID:project.id,arrangementID:project.active.id,useID:useID,trackID:trackID,laneID:project.sections[0].lanes[0].id,clock:clock,in:&project)
        XCTAssertEqual(project.takes?.map(\.id),[takeID])
        let rendered=try await ArrangementRenderer.render(project:project,root:nil,plan:ArrangementCompiler.compile(project),tailSeconds:0)
        XCTAssertEqual(rendered.mix.left,source.left);XCTAssertEqual(rendered.mix.right,source.right)

        let package=root.appendingPathComponent("captured.circlr")
        let saved=try ProjectStore.save(project,to:package,mediaRoot:nil)
        let reopened=try ProjectStore.load(package)
        XCTAssertEqual(reopened.project,saved)
        let embedded=try ProjectStore.assetURL(saved.assets[0],root:package)
        XCTAssertEqual(try ProjectStore.checksum(embedded),try ProjectStore.checksum(writer.url))
        // Rendering must use embedded media after the original capture is no longer present.
        try FileManager.default.removeItem(at:writer.url)
        let portable=try await ArrangementRenderer.render(project:reopened.project,root:reopened.root,plan:ArrangementCompiler.compile(reopened.project),tailSeconds:0)
        XCTAssertEqual(portable.mix.left,source.left);XCTAssertEqual(portable.mix.right,source.right)

        let bounceURL=root.appendingPathComponent("take-bounce.wav")
        try portable.stems[trackID]!.writeWAV(bounceURL)
        var bounced=reopened.project
        let bounceAsset=Asset(name:"녹음 바운스",path:bounceURL.path,duration:clock.seconds,sampleRate:PCM.rate)
        let bounceID=try BounceEditing.apply(asset:bounceAsset,trackID:trackID,useID:useID,bodySeconds:clock.seconds,tailSeconds:0,in:&bounced)
        let after=try await ArrangementRenderer.render(project:bounced,root:reopened.root,plan:ArrangementCompiler.compile(bounced),tailSeconds:0)
        XCTAssertLessThanOrEqual(zip(after.mix.left,source.left).map{abs($0-$1)}.max()!,1.0/8_388_608)
        XCTAssertLessThanOrEqual(zip(after.mix.right,source.right).map{abs($0-$1)}.max()!,1.0/8_388_608)
        try BounceEditing.restore(nodeID:bounceID,useID:useID,in:&bounced)
        let restored=try await ArrangementRenderer.render(project:bounced,root:reopened.root,plan:ArrangementCompiler.compile(bounced),tailSeconds:0)
        XCTAssertEqual(restored.mix.left,source.left);XCTAssertEqual(restored.mix.right,source.right)
    }
}
