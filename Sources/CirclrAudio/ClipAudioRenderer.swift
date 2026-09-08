import Foundation
import CirclrCore

enum ClipAudioRenderer {
    static func read(_ clip:AudioClip,url:URL,rate:Double,remaining:Double,legacyTail:Bool=true)throws->PCM {
        guard rate.isFinite,rate>=0.25,rate<=4 else {throw CirclrError("오디오 tempo 추종은 원속도의 0.25–4배 범위에서 지원합니다")}
        func frames(_ seconds:Double)throws->Int {
            let count=(seconds*PCM.rate).rounded()
            guard count.isFinite,count>=0,count<Double(Int.max/2) else {throw CirclrError("읽을 오디오 구간을 확인하세요")}
            return Int(count)
        }
        let window=clip.renderWindow
        let source=window?.sourceStart ?? clip.sourceStart
        let duration=window?.duration ?? clip.duration
        let offset=max(0,(clip.sourceStart-source)/rate)
        let maximum=try frames(remaining+offset)
        let first=try frames(offset)
        let length=try frames(min(clip.duration/rate,remaining))
        var pcm=try PCM.read(url,start:source,duration:min(duration,(remaining+offset)*rate))
        if clip.followsTempo {pcm=try AudioUnitHost.stretch(pcm,rate:rate)}
        pcm=pcm.slice(0..<min(pcm.count,maximum))
        if let window {
            if window.automaticEdges {pcm.fadeInOut()}
            for envelope in window.envelopes {apply(envelope,to:&pcm,source:source,rate:rate)}
        } else if clip.explicitEnvelope==nil && (!legacyTail || clip.preservesTail != true) {pcm.fadeInOut()}
        if window != nil {pcm=pcm.slice(min(first,pcm.count)..<min(pcm.count,first+length))}
        if let envelope=clip.explicitEnvelope {apply(envelope,to:&pcm,source:clip.sourceStart,rate:rate)}
        return pcm
    }
    static func apply(_ envelope:AudioFadeEnvelope,to pcm:inout PCM,source:Double,rate:Double) {
        guard envelope.fadeIn>0 || envelope.fadeOut>0 else{return}
        for i in pcm.left.indices {
            let gain=Float(envelope.gain(at:source+Double(i)/PCM.rate*rate))
            pcm.left[i]*=gain;pcm.right[i]*=gain
        }
    }
}
