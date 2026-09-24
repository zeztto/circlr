import Foundation
import XCTest
import CirclrAudio
@testable import CirclrApp

@MainActor final class InputPreferencesTests:XCTestCase {
    func testAppLocalSelectionPersistsWithoutChangingSystemDefault() async throws {
        let key="circlr-input-preferences-\(UUID().uuidString)"
        let defaults=try XCTUnwrap(UserDefaults(suiteName:key))
        defer {defaults.removePersistentDomain(forName:key)}
        let builtIn=InputDeviceDescriptor(uid:"internal-mic",name:"내장 마이크",isDefault:false)
        let preferences=InputPreferences(defaults:defaults,query:{[builtIn]})
        XCTAssertEqual(preferences.selection,.systemDefault)
        preferences.refresh()
        try await waitUntil {!preferences.loading}
        XCTAssertEqual(preferences.devices,[builtIn])
        preferences.choose(builtIn.uid)
        XCTAssertEqual(preferences.selection,.deviceUID(builtIn.uid))
        XCTAssertEqual(preferences.selectedName,builtIn.name)
        XCTAssertEqual(defaults.string(forKey:"circlr.recording.inputDeviceUID"),builtIn.uid)

        let restored=InputPreferences(defaults:defaults,query:{[]})
        XCTAssertEqual(restored.selection,.deviceUID(builtIn.uid))
        restored.refresh()
        try await waitUntil {!restored.loading}
        XCTAssertTrue(restored.missing)
        restored.choose(nil)
        XCTAssertEqual(restored.selection,.systemDefault)
        XCTAssertNil(defaults.string(forKey:"circlr.recording.inputDeviceUID"))
    }

    func testOnlyListedDeviceCanBeSelectedAndCancelIgnoresLateQuery() async throws {
        let key="circlr-input-preferences-\(UUID().uuidString)"
        let defaults=try XCTUnwrap(UserDefaults(suiteName:key))
        defer {defaults.removePersistentDomain(forName:key)}
        let preferences=InputPreferences(defaults:defaults,query:{
            try await Task.sleep(for:.milliseconds(80))
            return [InputDeviceDescriptor(uid:"after-cancel",name:"늦은 장치",isDefault:false)]
        })
        preferences.choose("unlisted")
        XCTAssertEqual(preferences.selection,.systemDefault)
        preferences.refresh()
        preferences.cancel()
        try await Task.sleep(for:.milliseconds(120))
        XCTAssertFalse(preferences.queried)
        XCTAssertTrue(preferences.devices.isEmpty)
    }

    private func waitUntil(_ condition:()->Bool) async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while !condition() && ProcessInfo.processInfo.systemUptime<deadline {
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}
