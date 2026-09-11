import Foundation
import CoreAudio
import AudioToolbox

public enum OutputDeviceBindingError: Error, LocalizedError, Equatable {
    case invalidSelection, missingDevice, unavailableDevice, noOutput, changedDevice, notBound
    case systemCall(operation: String, status: OSStatus)
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: return "출력 장치 선택값이 올바르지 않습니다"
        case .missingDevice: return "선택한 출력 장치를 찾을 수 없습니다"
        case .unavailableDevice: return "선택한 출력 장치를 사용할 수 없습니다"
        case .noOutput: return "선택한 장치에는 오디오 출력이 없습니다"
        case .changedDevice: return "출력 장치가 변경되어 재생을 정지했습니다. 장치 선택을 확인하세요."
        case .notBound: return "출력 장치가 아직 확인되지 않았습니다"
        case .systemCall(let operation, let status): return "출력 장치 \(operation)에 실패했습니다 (OSStatus \(status))"
        }
    }
}

/// Mockable boundary. There is deliberately no system-default device setter.
protocol OutputDeviceAccess: AnyObject {
    func defaultOutputID() throws -> AudioDeviceID
    func resolveUID(_ uid: String) throws -> AudioDeviceID
    func descriptor(_ id: AudioDeviceID) throws -> OutputDeviceDescriptor
    func isAlive(_ id: AudioDeviceID) throws -> Bool
    func hasOutput(_ id: AudioDeviceID) throws -> Bool
    func currentDevice() throws -> AudioDeviceID
    func setCurrentDevice(_ id: AudioDeviceID) throws
}

/// All methods belong to the worker's serial execution context, never the app.
/// Obtaining the AudioUnit first may itself initialize HAL; this is not a HAL-stall workaround.
public final class OutputDeviceBinding {
    public let selection: OutputDeviceSelection
    public private(set) var deviceID: AudioDeviceID?
    private let access: any OutputDeviceAccess
    private var boundUID: String?

    public convenience init(selection: OutputDeviceSelection, audioUnit: AudioUnit) throws {
        try self.init(selection: selection, access: CoreAudioOutputDeviceAccess(audioUnit: audioUnit))
    }
    init(selection: OutputDeviceSelection, access: any OutputDeviceAccess) throws {
        try selection.validate()
        self.selection = selection; self.access = access
    }
    private func selectedID() throws -> AudioDeviceID {
        let id: AudioDeviceID
        switch selection {
        case .systemDefault: id = try access.defaultOutputID()
        case .deviceUID(let uid): id = try access.resolveUID(uid)
        }
        guard id != kAudioObjectUnknown else { throw OutputDeviceBindingError.missingDevice }
        return id
    }
    private func checkedDescriptor(_ id: AudioDeviceID) throws -> OutputDeviceDescriptor {
        guard try access.isAlive(id) else { throw OutputDeviceBindingError.unavailableDevice }
        guard try access.hasOutput(id) else { throw OutputDeviceBindingError.noOutput }
        let descriptor = try access.descriptor(id)
        try OutputDeviceSelection.deviceUID(descriptor.uid).validate()
        if case .deviceUID(let uid) = selection, descriptor.uid != uid { throw OutputDeviceBindingError.changedDevice }
        return descriptor
    }
    @discardableResult public func bind() throws -> OutputDeviceDescriptor {
        deviceID = nil; boundUID = nil
        let id = try selectedID()
        let descriptor = try checkedDescriptor(id)
        try access.setCurrentDevice(id)
        guard try access.currentDevice() == id, try selectedID() == id else { throw OutputDeviceBindingError.changedDevice }
        let confirmed = try checkedDescriptor(id)
        guard confirmed.uid == descriptor.uid else { throw OutputDeviceBindingError.changedDevice }
        deviceID = id; boundUID = confirmed.uid
        return confirmed
    }
    @discardableResult public func revalidate() throws -> OutputDeviceDescriptor {
        guard let id = deviceID, let uid = boundUID else { throw OutputDeviceBindingError.notBound }
        guard try selectedID() == id, try access.currentDevice() == id else { throw OutputDeviceBindingError.changedDevice }
        let descriptor = try checkedDescriptor(id)
        guard descriptor.uid == uid else { throw OutputDeviceBindingError.changedDevice }
        return descriptor
    }
}

private final class CoreAudioOutputDeviceAccess: OutputDeviceAccess {
    private let audioUnit: AudioUnit
    init(audioUnit: AudioUnit) { self.audioUnit = audioUnit }
    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw OutputDeviceBindingError.systemCall(operation: operation, status: status) }
    }
    private func uint(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value), "조회")
        guard size == MemoryLayout<UInt32>.size else { throw OutputDeviceBindingError.unavailableDevice }
        return value
    }
    func defaultOutputID() throws -> AudioDeviceID { try uint(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) }
    func resolveUID(_ uid: String) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let qualifier = uid as CFString
        var qualifierPointer = Unmanaged.passUnretained(qualifier).toOpaque()
        var result = AudioDeviceID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withExtendedLifetime(qualifier) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &qualifierPointer, &size, &result)
        }
        try check(status, "식별")
        guard size == MemoryLayout<AudioDeviceID>.size else { throw OutputDeviceBindingError.unavailableDevice }
        return result
    }
    private func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        // AudioHardwareBase.h: name and device UID return caller-owned CFObjects.
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &result), "정보 조회")
        guard let result else { throw OutputDeviceBindingError.unavailableDevice }
        let value = result.takeRetainedValue()
        guard size == MemoryLayout<Unmanaged<CFString>?>.size else { throw OutputDeviceBindingError.unavailableDevice }
        return value as String
    }
    func descriptor(_ id: AudioDeviceID) throws -> OutputDeviceDescriptor {
        try OutputDeviceDescriptor(uid: string(id, kAudioDevicePropertyDeviceUID), name: string(id, kAudioObjectPropertyName))
    }
    func isAlive(_ id: AudioDeviceID) throws -> Bool { try uint(id, kAudioDevicePropertyDeviceIsAlive) != 0 }
    func hasOutput(_ id: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size), "출력 조회")
        return size >= MemoryLayout<AudioStreamID>.size
    }
    func currentDevice() throws -> AudioDeviceID {
        var result = AudioDeviceID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioUnitGetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &result, &size), "적용 확인")
        guard size == MemoryLayout<AudioDeviceID>.size else { throw OutputDeviceBindingError.unavailableDevice }
        return result
    }
    func setCurrentDevice(_ id: AudioDeviceID) throws {
        var value = id
        try check(AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &value, UInt32(MemoryLayout<AudioDeviceID>.size)), "선택 적용")
    }
}
