import Foundation
import XCTest
import CoreAudio
@testable import CirclrAudio

final class InputDeviceBindingTests:XCTestCase {
    private final class Access:InputDeviceAccess {
        var defaultID:AudioDeviceID=7,resolved:AudioDeviceID=7,current:AudioDeviceID=7
        var uid="input-a",alive=true,input=true,acceptSet=true
        var setError:InputDeviceBindingError?
        var sets:[AudioDeviceID]=[]
        func defaultInputID() throws -> AudioDeviceID {defaultID}
        func resolveUID(_ uid:String) throws -> AudioDeviceID {resolved}
        func descriptor(_ id:AudioDeviceID) throws -> InputDeviceDescriptor {
            .init(uid:uid,name:"입력",isDefault:id==defaultID)
        }
        func isAlive(_ id:AudioDeviceID) throws -> Bool {alive}
        func hasInput(_ id:AudioDeviceID) throws -> Bool {input}
        func currentDevice() throws -> AudioDeviceID {current}
        func setCurrentDevice(_ id:AudioDeviceID) throws {
            sets.append(id)
            if let setError {throw setError}
            if acceptSet {current=id}
        }
    }
    func testSelectionValidationAndCoding() throws {
        for selection in [InputDeviceSelection.systemDefault,.deviceUID("마이크 UID"),.deviceUID(String(repeating:"a",count:1024))] {
            try selection.validate()
            XCTAssertEqual(try JSONDecoder().decode(InputDeviceSelection.self,from:JSONEncoder().encode(selection)),selection)
        }
        for uid in ["","  ","a\nb","a\0b",String(repeating:"a",count:1025)] {
            XCTAssertThrowsError(try InputDeviceSelection.deviceUID(uid).validate()) {
                XCTAssertEqual($0 as? InputDeviceBindingError,.invalidSelection)
            }
        }
    }
    func testDefaultAndExplicitUIDBindWithoutChangingSystemDefault() throws {
        for selection in [InputDeviceSelection.systemDefault,.deviceUID("input-a")] {
            let access=Access(),binding=try InputDeviceBinding(selection:selection,access:access)
            XCTAssertEqual(try binding.bind().uid,"input-a")
            XCTAssertEqual(binding.deviceID,7)
            XCTAssertEqual(access.sets,[7])
            access.defaultID=9
            if case .deviceUID=selection {
                XCTAssertEqual(try binding.revalidate().uid,"input-a")
            } else {
                XCTAssertThrowsError(try binding.revalidate())
            }
            XCTAssertEqual(access.sets,[7],"Revalidation must not change any device")
        }
    }
    func testMissingUnavailableAndOutputOnlyUIDFailBeforeBinding() throws {
        for state in 0..<3 {
            let access=Access()
            if state==0 {access.resolved=kAudioObjectUnknown}
            if state==1 {access.alive=false}
            if state==2 {access.input=false}
            let binding=try InputDeviceBinding(selection:.deviceUID("input-a"),access:access)
            let expected:InputDeviceBindingError = state==0 ? .missingDevice : state==1 ? .unavailableDevice : .noInput
            XCTAssertThrowsError(try binding.bind()) {XCTAssertEqual($0 as? InputDeviceBindingError,expected)}
            XCTAssertTrue(access.sets.isEmpty)
            XCTAssertNil(binding.deviceID)
        }
    }
    func testSetterReadbackAndIdentityChangeFailClosed() throws {
        let access=Access(),binding=try InputDeviceBinding(selection:.deviceUID("input-a"),access:access)
        access.setError = .systemCall(operation:"적용",status:-50)
        XCTAssertThrowsError(try binding.bind()) {XCTAssertEqual($0 as? InputDeviceBindingError,access.setError)}
        XCTAssertNil(binding.deviceID)
        access.setError=nil;access.acceptSet=false;access.current=9
        XCTAssertThrowsError(try binding.bind()) {XCTAssertEqual($0 as? InputDeviceBindingError,.changedDevice)}
        access.acceptSet=true;try binding.bind()
        access.uid="reused-id"
        XCTAssertThrowsError(try binding.revalidate()) {XCTAssertEqual($0 as? InputDeviceBindingError,.changedDevice)}
    }
    func testRevalidationRejectsDisconnectedInputWithoutRetargeting() throws {
        let access=Access(),binding=try InputDeviceBinding(selection:.deviceUID("input-a"),access:access)
        try binding.bind();access.alive=false
        XCTAssertThrowsError(try binding.revalidate()) {XCTAssertEqual($0 as? InputDeviceBindingError,.unavailableDevice)}
        XCTAssertEqual(access.sets,[7])
    }
    func testErrorDoesNotExposePrivateUID() throws {
        let access=Access();access.resolved=kAudioObjectUnknown
        let binding=try InputDeviceBinding(selection:.deviceUID("private-input-uid"),access:access)
        XCTAssertThrowsError(try binding.bind()) {XCTAssertFalse($0.localizedDescription.contains("private-input-uid"))}
    }
    func testNativeCatalogReadOnlyWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["CIRCLR_QA_INPUT_CATALOG"]=="1" else {
            throw XCTSkip("Set CIRCLR_QA_INPUT_CATALOG=1 for a native CoreAudio inventory")
        }
        let access=CoreAudioInputDeviceAccess(),before=try access.defaultInputID()
        let devices=try InputDeviceCatalog.available()
        XCTAssertEqual(try access.defaultInputID(),before)
        XCTAssertEqual(Set(devices.map(\.uid)).count,devices.count)
        XCTAssertTrue(devices.allSatisfy{!$0.uid.isEmpty && !$0.name.isEmpty})
        print("NATIVE_INPUT_DEVICES=\(devices)")
    }
}
