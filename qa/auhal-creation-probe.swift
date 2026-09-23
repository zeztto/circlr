// Run only through diagnose-auhal-creation.py, which limits and reaps this process.
// The probe does not set the system output device or start audio playback.
import Foundation
import CoreAudio
import AudioToolbox

func mark(_ message: String) { fputs(message + "\n", stderr) }
func fail(_ stage: String, _ status: OSStatus) -> Never {
    mark("failed \(stage) status=\(status)")
    exit(1)
}

guard CommandLine.arguments.count == 2 else { exit(64) }
let uid = CommandLine.arguments[1] as CFString
var qualifier = Unmanaged.passUnretained(uid).toOpaque()
var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
var device = AudioDeviceID(kAudioObjectUnknown)
var size = UInt32(MemoryLayout<AudioDeviceID>.size)
mark("before resolveUID")
let resolved = withExtendedLifetime(uid) {
    AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address,
        UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &qualifier, &size, &device
    )
}
guard resolved == noErr, size == UInt32(MemoryLayout<AudioDeviceID>.size),
      device != kAudioObjectUnknown else {
    fail("resolveUID", resolved == noErr ? -1 : resolved)
}
mark("resolved deviceID=\(device)")

var description = AudioComponentDescription(
    componentType: kAudioUnitType_Output,
    componentSubType: kAudioUnitSubType_HALOutput,
    componentManufacturer: kAudioUnitManufacturer_Apple,
    componentFlags: 0,
    componentFlagsMask: 0
)
mark("before findComponent")
guard let component = AudioComponentFindNext(nil, &description) else {
    mark("component missing")
    exit(2)
}
mark("before instanceNew")
var unit: AudioUnit?
let created = AudioComponentInstanceNew(component, &unit)
if created != noErr { fail("instanceNew", created) }
guard let unit else { mark("unit nil"); exit(2) }
mark("created")

var enable: UInt32 = 1
let enabled = AudioUnitSetProperty(
    unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
    &enable, UInt32(MemoryLayout<UInt32>.size)
)
if enabled != noErr { fail("enableIO", enabled) }
mark("before setDevice")
let selected = AudioUnitSetProperty(
    unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
    &device, UInt32(MemoryLayout<AudioDeviceID>.size)
)
if selected != noErr { fail("setDevice", selected) }
mark("device set")

var bound = AudioDeviceID(kAudioObjectUnknown)
size = UInt32(MemoryLayout<AudioDeviceID>.size)
let read = AudioUnitGetProperty(
    unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
    &bound, &size
)
if read != noErr { fail("readDevice", read) }
mark("bound deviceID=\(bound)")
guard bound == device else { mark("wrong device"); exit(3) }

mark("before initialize")
let initialized = AudioUnitInitialize(unit)
if initialized != noErr { fail("initialize", initialized) }
mark("initialized")
mark("before dispose")
_ = AudioComponentInstanceDispose(unit)
mark("done")
