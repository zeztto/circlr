// QA only. No audio is started. Run with a bounded subprocess.
import Foundation
import AVFAudio

fputs("before engine\n", stderr)
let engine = AVAudioEngine()
fputs("before outputNode\n", stderr)
_ = engine.outputNode
fputs("outputNode acquired\n", stderr)
let player = AVAudioPlayerNode()
let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
silence.frameLength = 4_800
for channel in 0..<2 {
    memset(silence.floatChannelData![channel], 0, Int(silence.frameLength) * MemoryLayout<Float>.size)
}
engine.attach(player)
engine.connect(player, to: engine.mainMixerNode, format: format)
player.volume = 0
player.scheduleBuffer(silence, at: nil)
fputs("before engine.start\n", stderr)
try engine.start()
fputs("engine started\n", stderr)
player.play()
fputs("player started\n", stderr)
Thread.sleep(forTimeInterval: 0.2)
player.stop()
engine.stop()
fputs("stopped\n", stderr)
