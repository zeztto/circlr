import AppKit
import XCTest
import CirclrCore
@testable import CirclrApp

@MainActor final class MIDIRecordingExpressionTests:XCTestCase {
    func testCaptureSeparatesChannelsCarriesExpressionAndUndoIsAtomic() async throws {
        _ = NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        store.project.global.tempo=999
        let useID=store.project.addSection(name:"Capture",at:Point(),bars:1)
        let index=try XCTUnwrap(store.project.active.uses.firstIndex{$0.id==useID})
        store.project.arrangements[store.project.activeIndex].uses[index].repeatCount=2
        store.selection=[useID]
        let before=store.project
        let clock=try XCTUnwrap(store.recordingClock)
        store.startMIDIRecording()
        let start=ProcessInfo.processInfo.systemUptime-store.midiRecordingElapsedSeconds
        // Reverse channel delivery order must not determine the original lane target.
        store.midi(status:0x92,pitch:64,velocity:100,time:start+0.01)
        store.midi(status:0x91,pitch:60,velocity:90,time:start+0.02)
        store.midi(status:0xB1,pitch:64,velocity:95,time:start+0.03)
        store.midi(status:0xE2,pitch:1,velocity:80,time:start+0.04)
        store.midi(status:0x81,pitch:60,velocity:0,time:start+0.10)
        store.midi(status:0x82,pitch:64,velocity:0,time:start+clock.seconds+0.01)
        store.midi(status:0xB1,pitch:64,velocity:0,time:start+clock.seconds+0.02)
        try await Task.sleep(for:.milliseconds(330))
        store.stopRecording()
        let deadline=Date().addingTimeInterval(2)
        while store.midiRecording && Date()<deadline {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertFalse(store.midiRecording)
        let takes=try XCTUnwrap(store.project.takes)
        XCTAssertEqual(takes.count,4)
        let firstPedal=try XCTUnwrap(takes.first{$0.lane.sustain?.channel==1})
        XCTAssertEqual(firstPedal.lane.sustain?.events.first?.rawValue,95)
        XCTAssertEqual(try XCTUnwrap(firstPedal.lane.sustain?.events.first?.beat),clock.beat(atSeconds:0.03),accuracy:0.01)
        let lastPedal=try XCTUnwrap(takes.last{$0.lane.sustain?.channel==1})
        XCTAssertEqual(lastPedal.lane.sustain?.initialValue,95)
        XCTAssertEqual(lastPedal.lane.notes.count,0)
        let lastBend=try XCTUnwrap(takes.last{$0.lane.pitchBend?.channel==2})
        XCTAssertEqual(lastBend.lane.pitchBend?.initialValue,10241)
        XCTAssertEqual(lastBend.lane.notes.map(\.pitch),[64])
        let use=try XCTUnwrap(store.project.active.uses.first{$0.id==useID})
        let section=try XCTUnwrap(store.project.sections.first{$0.id==use.sectionID})
        let lanes=try ArrangementCompiler.effectiveLanes(section:section,use:use)
        XCTAssertTrue(try XCTUnwrap(lanes.first{$0.id==lastPedal.targetLaneID}).notes.isEmpty)
        let document=root.appendingPathComponent("capture.circlr")
        _ = try ProjectStore.save(store.project,to:document,mediaRoot:nil)
        XCTAssertEqual(try ProjectStore.load(document).project.takes,takes)
        store.undo()
        XCTAssertEqual(store.project.takes,before.takes)
        store.redo()
        XCTAssertEqual(store.project.takes,takes)
    }
    func testStaleInvalidAndAfterRepeatExpressionDoesNotCreateTake() async throws {
        _ = NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        store.project.global.tempo=999
        let use=store.project.addSection(name:"Boundary",at:Point(),bars:1)
        store.selection=[use]
        let clock=try XCTUnwrap(store.recordingClock)
        store.startMIDIRecording()
        let start=ProcessInfo.processInfo.systemUptime-store.midiRecordingElapsedSeconds
        store.midi(status:0xB0,pitch:64,velocity:127,time:start-1)
        store.midi(status:0xE0,pitch:0,velocity:100,time:.nan)
        store.midi(status:0xE0,pitch:128,velocity:0,time:start+0.01)
        store.midi(status:0xB0,pitch:64,velocity:127,time:start+clock.seconds+0.1)
        store.stopRecording()
        let deadline=Date().addingTimeInterval(2)
        while store.midiRecording && Date()<deadline {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertFalse(store.midiRecording)
        XCTAssertEqual(store.project.takes?.count ?? 0,0)
    }

    func testExpressionOnlyCapturePreservesUnrecordedDimension() async throws {
        for pedalOnly in [true,false] {
            _ = NSApplication.shared
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let store=AppStore(storageRootOverride:root)
            defer {store.stop();try? FileManager.default.removeItem(at:root)}
            let useID=store.project.addSection(name:"Expression",at:Point(),bars:1)
            store.selection=[useID]
            let use=try XCTUnwrap(store.project.active.uses.first{$0.id==useID})
            let si=try XCTUnwrap(store.project.sections.firstIndex{$0.id==use.sectionID})
            store.project.sections[si].lanes[0].notes=[Note(beat:0,pitch:60)]
            store.project.sections[si].lanes[0].pitchBend = .init(channel:0,initialValue:9000)
            store.project.sections[si].lanes[0].sustain = .init(channel:0,events:[.init(beat:0.5,rawValue:100)])
            store.project.schemaVersion=7
            let original=store.project.sections[si].lanes[0]
            store.startMIDIRecording()
            let start=ProcessInfo.processInfo.systemUptime-store.midiRecordingElapsedSeconds
            store.midi(status:pedalOnly ? 0xB1:0xE1,pitch:pedalOnly ? 64:1,velocity:70,time:start+0.01)
            try await Task.sleep(for:.milliseconds(30))
            store.stopRecording()
            let deadline=Date().addingTimeInterval(2)
            while store.midiRecording && Date()<deadline {try await Task.sleep(for:.milliseconds(10))}
            let take=try XCTUnwrap(store.project.takes?.last)
            let currentUse=try XCTUnwrap(store.project.active.uses.first{$0.id==useID})
            let lane=try XCTUnwrap(try ArrangementCompiler.effectiveLanes(section:store.project.sections[si],use:currentUse).first{$0.id==original.id})
            XCTAssertEqual(lane.notes,original.notes)
            if pedalOnly {
                XCTAssertNil(take.lane.pitchBend)
                XCTAssertEqual(lane.pitchBend,original.pitchBend)
                XCTAssertEqual(lane.sustain?.channel,0)
            } else {
                XCTAssertNil(take.lane.sustain)
                XCTAssertEqual(lane.sustain,original.sustain)
                XCTAssertEqual(lane.pitchBend?.channel,0)
            }
        }
    }

    func testEditedBaselineSurvivesSaveAndIsNotDuplicatedOnAnotherCapture() async throws {
        _ = NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        let useID=store.project.addSection(name:"Baseline",at:Point(),bars:1)
        store.selection=[useID]
        let use=try XCTUnwrap(store.project.active.uses.first{$0.id==useID})
        let si=try XCTUnwrap(store.project.sections.firstIndex{$0.id==use.sectionID})
        store.project.sections[si].lanes[0].notes=[Note(beat:0.2,length:0.4,pitch:72,velocity:101)]
        store.project.sections[si].lanes[0].pitchBend = .init(channel:0,initialValue:9100)
        store.project.schemaVersion=7
        let original=store.project.sections[si].lanes[0]
        // Empty attempts must not create a baseline or history.
        store.startMIDIRecording();store.stopRecording()
        var deadline=Date().addingTimeInterval(2)
        while store.midiRecording && Date()<deadline {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertTrue((store.project.takes ?? []).isEmpty)
        for iteration in 0..<3 {
            store.startMIDIRecording()
            let start=ProcessInfo.processInfo.systemUptime-store.midiRecordingElapsedSeconds
            store.midi(status:0x90,pitch:60,velocity:80,time:start+0.005)
            store.midi(status:0x80,pitch:60,velocity:0,time:start+0.015)
            try await Task.sleep(for:.milliseconds(30))
            store.stopRecording();deadline=Date().addingTimeInterval(2)
            while store.midiRecording && Date()<deadline {try await Task.sleep(for:.milliseconds(10))}
            let baselines=(store.project.takes ?? []).filter{$0.name=="녹음 전"}
            XCTAssertEqual(baselines.count,1)
            let baseline=try XCTUnwrap(baselines.first)
            let document=root.appendingPathComponent("baseline.circlr")
            _ = try ProjectStore.save(store.project,to:document,mediaRoot:nil)
            var restored=try ProjectStore.load(document).project
            let saved=try XCTUnwrap(restored.takes?.first{$0.id==baseline.id})
            try ProjectEditing.activateTake(saved,in:&restored)
            let restoredUse=try XCTUnwrap(restored.active.uses.first{$0.id==useID})
            XCTAssertEqual(try ArrangementCompiler.effectiveLanes(section:restored.sections[si],use:restoredUse).first{$0.id==original.id},original)
            if iteration == 0 {store.activateTake(baseline)}
        }
    }

}
