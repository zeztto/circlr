import XCTest
import CoreAudio
import CoreMIDI
@testable import CirclrAudio

final class MIDIInputEventTimeTests: XCTestCase {
    func testInterleavedSourcesPreservePartialMessagesRunningStatusAndFirstByteTimes() {
        var parser=MIDIMessageParser()
        var messages:[(UInt8,UInt8,UInt8,Double)]=[]
        let emit: (UInt8,UInt8,UInt8,Double)->Void = { messages.append(($0,$1,$2,$3)) }
        // CoreMIDI's virtual source filters an incomplete packet before it
        // reaches its read block, so exercise the byte-stream parser directly.
        parser.parse([0x90,60],time:10.0,sourceKey:1,emit:emit)
        parser.parse([0x80,65,0],time:10.1,sourceKey:2,emit:emit)
        parser.parse([100],time:10.2,sourceKey:1,emit:emit)
        parser.parse([61,110],time:10.3,sourceKey:1,emit:emit) // A running status
        parser.parse([66,0],time:10.4,sourceKey:2,emit:emit)    // B running status

        XCTAssertEqual(messages.count,4)
        XCTAssertEqual(messages.map { $0.0 },[0x80,0x90,0x90,0x80])
        XCTAssertEqual(messages.map { $0.1 },[65,60,61,66])
        XCTAssertEqual(messages.map { $0.2 },[0,100,110,0])
        XCTAssertEqual(messages.map { $0.3 },[10.1,10.0,10.3,10.4])
    }

    func testInvalidPacketClearsOnlyItsSourcesPartialMessage() {
        var parser=MIDIMessageParser()
        var messages:[UInt8]=[]
        let emit: (UInt8,UInt8,UInt8,Double)->Void = { _,pitch,_,_ in messages.append(pitch) }
        parser.parse([0x90,60],time:1,sourceKey:1,emit:emit)
        parser.parse([0x90,65],time:1,sourceKey:2,emit:emit)
        parser.reset(sourceKey:1)
        parser.parse([100],time:2,sourceKey:1,emit:emit)
        parser.parse([110],time:2,sourceKey:2,emit:emit)
        XCTAssertEqual(messages,[65])
    }

    func testZeroIsCallbackNowAndFutureOrStaleHostTimesCannotShiftARecording() throws {
        let host = AudioGetCurrentHostTime()
        let callbackUptime = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(MIDIHostClock.occurrenceUptime(timeStamp: 0, receivedHostTime: host,
                                                         receivedUptime: callbackUptime), callbackUptime)
        let tinyFuture = host + AudioConvertNanosToHostTime(1_000_000)
        XCTAssertEqual(MIDIHostClock.occurrenceUptime(timeStamp: tinyFuture, receivedHostTime: host,
                                                         receivedUptime: callbackUptime), callbackUptime)
        let invalidFuture = host + AudioConvertNanosToHostTime(100_000_000)
        XCTAssertNil(MIDIHostClock.occurrenceUptime(timeStamp: invalidFuture, receivedHostTime: host,
                                                     receivedUptime: callbackUptime))
        let stale = host - AudioConvertNanosToHostTime(31_000_000_000)
        XCTAssertNil(MIDIHostClock.occurrenceUptime(timeStamp: stale, receivedHostTime: host,
                                                     receivedUptime: callbackUptime))
        let validPast = host - AudioConvertNanosToHostTime(250_000_000)
        XCTAssertEqual(try XCTUnwrap(MIDIHostClock.occurrenceUptime(timeStamp: validPast, receivedHostTime: host,
                                                                      receivedUptime: callbackUptime)), callbackUptime - 0.25,
                       accuracy: 0.0001)
        XCTAssertNil(MIDIHostClock.occurrenceUptime(timeStamp: 0, receivedHostTime: host,
                                                     receivedUptime: .infinity))
    }

    func testZeroTimestampFromVirtualSourceUsesReceiveCallbackTime() throws {
        var sender = MIDIClientRef(), source = MIDIEndpointRef()
        XCTAssertEqual(MIDIClientCreate("circlr zero-time sender" as CFString, nil, nil, &sender), noErr)
        guard sender != 0 else { return }
        defer { if source != 0 { MIDIEndpointDispose(source) }; MIDIClientDispose(sender) }
        XCTAssertEqual(MIDISourceCreate(sender, "circlr-zero-source-\(UUID().uuidString)" as CFString, &source), noErr)
        guard source != 0 else { return }
        let input = try MIDIInput(endpointName: "circlr-zero-destination-\(UUID().uuidString)")
        let received = expectation(description: "zero-timestamp virtual source packet")
        let sentUptime = ProcessInfo.processInfo.systemUptime
        input.onMessage = { status, pitch, velocity, eventUptime in
            guard status & 0xF0 == 0x90,pitch == 72,velocity == 88 else { return }
            let callbackUptime = ProcessInfo.processInfo.systemUptime
            XCTAssertGreaterThanOrEqual(eventUptime, sentUptime - 0.02)
            XCTAssertLessThanOrEqual(eventUptime, callbackUptime)
            received.fulfill()
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: 1024, alignment: 8)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(list)
        let bytes: [UInt8] = [0x90, 72, 88]
        bytes.withUnsafeBufferPointer { _ = MIDIPacketListAdd(list, 1024, packet, 0, 3, $0.baseAddress!) }
        XCTAssertEqual(MIDIReceived(source, list), noErr)
        wait(for: [received], timeout: 3)
        withExtendedLifetime(input) {}
    }

    func testVirtualMIDIPacketKeepsOccurrenceTimeAcrossDeliveryDelay() throws {
        let input = try MIDIInput(endpointName: "circlr-timing-\(UUID().uuidString)")
        let destination = try XCTUnwrap((0..<MIDIGetNumberOfDestinations()).map { MIDIGetDestination($0) }.first { endpoint in
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            return (name?.takeRetainedValue() as String?) == input.endpointName
        })
        let received = expectation(description: "virtual MIDI occurrence time")
        let occurrence = AudioGetCurrentHostTime() - AudioConvertNanosToHostTime(150_000_000)
        let expectedUptime = Double(AudioConvertHostTimeToNanos(occurrence)) / 1_000_000_000
        input.onMessage = { status, pitch, velocity, occurrence in
            guard status & 0xF0 == 0x90, pitch == 60, velocity == 96 else { return }
            XCTAssertEqual(Double(occurrence), expectedUptime, accuracy: 0.02)
            received.fulfill()
        }
        var client = MIDIClientRef(), port = MIDIPortRef()
        XCTAssertEqual(MIDIClientCreate("circlr timing sender" as CFString, nil, nil, &client), noErr)
        defer { if port != 0 { MIDIPortDispose(port) }; if client != 0 { MIDIClientDispose(client) } }
        XCTAssertEqual(MIDIOutputPortCreate(client, "timing output" as CFString, &port), noErr)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: 1024, alignment: 8)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(list)
        let bytes: [UInt8] = [0x90, 60, 96]
        XCTAssertNotNil(bytes.withUnsafeBufferPointer {
            MIDIPacketListAdd(list, 1024, packet, occurrence, 3, $0.baseAddress!)
        })
        XCTAssertEqual(MIDISend(port, destination, list), noErr)
        wait(for: [received], timeout: 3)
        withExtendedLifetime(input) {}
    }
}
