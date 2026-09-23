// QA only. Run through diagnose-default-output.py, which restores the previous default.
import Foundation
import CoreAudio

let system = AudioObjectID(kAudioObjectSystemObject)
func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    .init(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
          mElement: kAudioObjectPropertyElementMain)
}
func check(_ status: OSStatus, _ operation: String) {
    guard status == noErr else { fputs("\(operation) status=\(status)\n", stderr); exit(1) }
}
func defaultID() -> AudioDeviceID {
    var property = address(kAudioHardwarePropertyDefaultOutputDevice)
    var id = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    check(AudioObjectGetPropertyData(system, &property, 0, nil, &size, &id), "getDefault")
    guard size == UInt32(MemoryLayout<AudioDeviceID>.size), id != kAudioObjectUnknown else { exit(2) }
    return id
}
func uid(_ id: AudioDeviceID) -> String {
    var property = address(kAudioDevicePropertyDeviceUID)
    var result: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    check(AudioObjectGetPropertyData(id, &property, 0, nil, &size, &result), "getUID")
    guard size == UInt32(MemoryLayout<Unmanaged<CFString>?>.size), let result else { exit(2) }
    return result.takeRetainedValue() as String
}
func resolve(_ name: String) -> AudioDeviceID {
    let value = name as CFString
    var pointer = Unmanaged.passUnretained(value).toOpaque()
    var property = address(kAudioHardwarePropertyTranslateUIDToDevice)
    var id = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = withExtendedLifetime(value) {
        AudioObjectGetPropertyData(system, &property,
            UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &pointer, &size, &id)
    }
    check(status, "resolveUID")
    guard size == UInt32(MemoryLayout<AudioDeviceID>.size), id != kAudioObjectUnknown,
          uid(id) == name else { exit(2) }
    return id
}

let args = Array(CommandLine.arguments.dropFirst())
if args == ["get"] {
    let id = defaultID()
    print("\(id)\t\(uid(id))")
} else if args.count == 3 && args[0] == "set" {
    let expected = args[1], target = args[2]
    let current = defaultID()
    guard uid(current) == expected else { fputs("default changed before set\n", stderr); exit(3) }
    let device = resolve(target)
    var property = address(kAudioHardwarePropertyDefaultOutputDevice)
    var value = device
    check(AudioObjectSetPropertyData(system, &property, 0, nil,
        UInt32(MemoryLayout<AudioDeviceID>.size), &value), "setDefault")
    guard uid(defaultID()) == target else { fputs("default did not change\n", stderr); exit(4) }
    print("\(device)\t\(target)")
} else { exit(64) }
