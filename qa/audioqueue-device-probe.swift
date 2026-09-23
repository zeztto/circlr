// QA only. Run via diagnose-audioqueue-device.py, which bounds and reaps this child.
// The sole queued buffer contains zeros. This never changes the system output device.
import Foundation
import AudioToolbox

func mark(_ value: String) { fputs(value + "\n", stderr) }
func check(_ result: OSStatus, _ stage: String, _ exitCode: Int32) {
    guard result == noErr else {
        mark("\(stage) failed status=\(result)")
        exit(exitCode)
    }
    mark("\(stage) status=0")
}

guard CommandLine.arguments.count == 2 else { exit(64) }
let requestedUID = CommandLine.arguments[1]
let isDefault = requestedUID == "default"

var format = AudioStreamBasicDescription(
    mSampleRate: 48_000,
    mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
    mBytesPerPacket: 4,
    mFramesPerPacket: 1,
    mBytesPerFrame: 4,
    mChannelsPerFrame: 2,
    mBitsPerChannel: 16,
    mReserved: 0
)
var queue: AudioQueueRef?
mark("before NewOutput")
let created = AudioQueueNewOutput(&format, { _, _, _ in }, nil, nil, nil, 0, &queue)
check(created, "NewOutput", 1)
guard let queue else { mark("NewOutput returned null queue"); exit(1) }

if !isDefault {
    let uid = requestedUID as CFString
    var uidPointer = Unmanaged.passUnretained(uid).toOpaque()
    mark("before bindDevice")
    let bound = withExtendedLifetime(uid) {
        AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice,
                              &uidPointer, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size))
    }
    check(bound, "bindDevice", 2)
} else {
    mark("bindDevice skipped (system default)")
}

let silenceFrames = 48_000 // one second, so no callback refill is needed
let silenceBytes = UInt32(silenceFrames * Int(format.mBytesPerFrame))
var buffer: AudioQueueBufferRef?
mark("before allocateBuffer")
check(AudioQueueAllocateBuffer(queue, silenceBytes, &buffer), "allocateBuffer", 3)
guard let buffer else { mark("allocateBuffer returned null buffer"); exit(3) }
memset(buffer.pointee.mAudioData, 0, Int(silenceBytes))
buffer.pointee.mAudioDataByteSize = silenceBytes
mark("before enqueueBuffer")
check(AudioQueueEnqueueBuffer(queue, buffer, 0, nil), "enqueueBuffer", 4)

mark("before start")
check(AudioQueueStart(queue, nil), "start", 5)
Thread.sleep(forTimeInterval: 0.20)
mark("before stop")
check(AudioQueueStop(queue, true), "stop", 6)
mark("before dispose")
check(AudioQueueDispose(queue, true), "dispose", 7)
mark("done")
