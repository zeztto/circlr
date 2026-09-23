// Run only through diagnose-direct-ioproc.py, which bounds and reaps this child.
// This registers a silent callback on one explicitly selected device, then starts/stops it.
// It does not change the system default output or play project audio.
import Foundation
import CoreAudio

func mark(_ message: String) { fputs(message + "\n", stderr) }
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
guard resolved == noErr, device != kAudioObjectUnknown else {
    mark("resolve failed status=\(resolved)")
    exit(1)
}
mark("resolved deviceID=\(device)")

var ioProc: AudioDeviceIOProcID?
mark("before createIOProc")
let created = AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, nil) { _, _, _, outputData, _ in
    // Explicitly silence every output buffer; do not assume Core Audio initialized it.
    // Never allocate, lock, or log in this real-time callback.
    for buffer in UnsafeMutableAudioBufferListPointer(outputData) {
        if let samples = buffer.mData { memset(samples, 0, Int(buffer.mDataByteSize)) }
    }
}
guard created == noErr, let ioProc else {
    mark("createIOProc failed status=\(created)")
    exit(2)
}
mark("created")

mark("before startIOProc")
let started = AudioDeviceStart(device, ioProc)
guard started == noErr else {
    mark("startIOProc failed status=\(started)")
    _ = AudioDeviceDestroyIOProcID(device, ioProc)
    exit(3)
}
mark("started")
Thread.sleep(forTimeInterval: 0.35)

mark("before stopIOProc")
let stopped = AudioDeviceStop(device, ioProc)
mark("stopIOProc status=\(stopped)")
mark("before destroyIOProc")
let destroyed = AudioDeviceDestroyIOProcID(device, ioProc)
mark("destroyIOProc status=\(destroyed)")
guard stopped == noErr, destroyed == noErr else { exit(4) }
mark("done")
