import XCTest
import AudioToolbox
import CoreAudio
@testable import CirclrAudio

final class OutputDeviceBindingTests: XCTestCase {
    private final class Access: OutputDeviceAccess {
        var defaultID: AudioDeviceID = 7
        var resolved: AudioDeviceID = 7
        var actual: AudioDeviceID = 7
        var uid = "device-a"
        var alive = true, output = true, acceptSet = true
        var setError: OutputDeviceBindingError?
        var sets: [AudioDeviceID] = []
        func defaultOutputID() throws -> AudioDeviceID { defaultID }
        func resolveUID(_ uid: String) throws -> AudioDeviceID { resolved }
        func descriptor(_ id: AudioDeviceID) throws -> OutputDeviceDescriptor { .init(uid: uid, name: "출력") }
        func isAlive(_ id: AudioDeviceID) throws -> Bool { alive }
        func hasOutput(_ id: AudioDeviceID) throws -> Bool { output }
        func currentDevice() throws -> AudioDeviceID { actual }
        func setCurrentDevice(_ id: AudioDeviceID) throws {
            sets.append(id)
            if let setError { throw setError }
            if acceptSet { actual = id }
        }
    }
    func testSelectionValidationAndRoundTrip() throws {
        for value in [OutputDeviceSelection.systemDefault, .deviceUID("장치 UID"), .deviceUID(String(repeating:"a",count:1024))] {
            try value.validate()
            XCTAssertEqual(try JSONDecoder().decode(OutputDeviceSelection.self, from: JSONEncoder().encode(value)), value)
        }
        for uid in ["", "  ", "a\nb", "a\0b", String(repeating:"a",count:1025), String(repeating:"가",count:342)] {
            XCTAssertThrowsError(try OutputDeviceSelection.deviceUID(uid).validate())
            XCTAssertThrowsError(try OutputDeviceBinding(selection:.deviceUID(uid),access:Access()))
        }
    }
    func testDefaultAndExplicitBindReadback() throws {
        for selection in [OutputDeviceSelection.systemDefault,.deviceUID("device-a")] {
            let access = Access(), binding = try OutputDeviceBinding(selection:selection,access:access)
            XCTAssertEqual(try binding.bind(), .init(uid:"device-a",name:"출력"))
            XCTAssertEqual(binding.deviceID,7)
            XCTAssertEqual(access.sets,[7])
            XCTAssertEqual(try binding.revalidate().uid,"device-a")
            XCTAssertEqual(access.sets,[7],"Revalidation must never redirect an active device")
        }
    }
    func testMissingDeadAndInputOnlyFailBeforeSetter() throws {
        for state in 0..<3 {
            let access = Access()
            if state == 0 { access.resolved = 0 }
            if state == 1 { access.alive = false }
            if state == 2 { access.output = false }
            let binding = try OutputDeviceBinding(selection:.deviceUID("device-a"),access:access)
            XCTAssertThrowsError(try binding.bind())
            XCTAssertTrue(access.sets.isEmpty)
            XCTAssertNil(binding.deviceID)
        }
    }
    func testSetterStatusAndReadbackMismatch() throws {
        let access = Access(), binding = try OutputDeviceBinding(selection:.systemDefault,access:access)
        access.setError = .systemCall(operation:"선택 적용",status:-50)
        XCTAssertThrowsError(try binding.bind()) { XCTAssertEqual($0 as? OutputDeviceBindingError,access.setError) }
        XCTAssertNil(binding.deviceID)
        access.setError = nil; access.acceptSet = false; access.actual = 9
        XCTAssertThrowsError(try binding.bind()) { XCTAssertEqual($0 as? OutputDeviceBindingError,.changedDevice) }
        XCTAssertNil(binding.deviceID)
    }
    func testRevalidationRejectsDefaultChangeWithoutRedirecting() throws {
        let access = Access(), binding = try OutputDeviceBinding(selection:.systemDefault,access:access)
        try binding.bind(); access.defaultID = 9
        XCTAssertThrowsError(try binding.revalidate()) { XCTAssertEqual($0 as? OutputDeviceBindingError,.changedDevice) }
        XCTAssertEqual(access.sets,[7])
    }
    func testExplicitSelectionSurvivesDefaultChangeButRejectsIdentityAndAvailabilityChanges() throws {
        for state in 0..<5 {
            let access = Access(), binding = try OutputDeviceBinding(selection:.deviceUID("device-a"),access:access)
            try binding.bind(); access.defaultID = 9
            XCTAssertNoThrow(try binding.revalidate())
            if state == 0 { access.resolved = 0 }
            if state == 1 { access.actual = 9 }
            if state == 2 { access.alive = false }
            if state == 3 { access.output = false }
            if state == 4 { access.uid = "reused-device-id" }
            XCTAssertThrowsError(try binding.revalidate())
            XCTAssertEqual(access.sets,[7])
        }
    }
    func testUnboundCannotBeValidatedAndErrorsDoNotExposeUID() throws {
        let binding = try OutputDeviceBinding(selection:.deviceUID("private-uid"),access:Access())
        XCTAssertThrowsError(try binding.revalidate()) { XCTAssertEqual($0 as? OutputDeviceBindingError,.notBound) }
        XCTAssertThrowsError(try binding.bind()) { XCTAssertFalse($0.localizedDescription.contains("private-uid")) }
    }
}
