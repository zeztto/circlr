import CirclrCore
import Foundation

enum AutomationDSP {
    static func apply(_ plans:[AutomationPlan],to pcm:inout PCM)throws {
        for plan in plans {
            guard plan.parameter != .synthCutoff,!plan.spans.isEmpty else{continue}
            var cursor=0
            for frame in pcm.left.indices {
                if frame%8192==0 {try Task.checkCancellation()}
                let seconds=Double(frame)/PCM.rate
                while cursor+1<plan.spans.count && seconds>=plan.spans[cursor].end {cursor+=1}
                let value=plan.spans[cursor].value(at:seconds)
                switch plan.parameter {
                case .synthCutoff:break // Applied inside the instrument, never as a PCM effect.
                case .gain:pcm.left[frame]*=Float(value);pcm.right[frame]*=Float(value)
                case .pan:pcm.left[frame]*=Float(sqrt(max(0,1-value)));pcm.right[frame]*=Float(sqrt(max(0,1+value)))
                }
            }
        }
    }
}

/// Monotonic sample-time cursor over compiled spans; the last value extends through release tails.
struct SynthCutoffCursor {
    private let spans:[AutomationSpan]
    private var index=0
    var active:Bool {!spans.isEmpty}
    init(_ plans:[AutomationPlan])throws {
        let cutoff=plans.filter{$0.parameter == .synthCutoff}
        guard cutoff.count<=1 else{throw CirclrError("신스 필터 오토메이션은 하나만 사용할 수 있습니다")}
        spans=cutoff.first?.spans ?? []
        guard spans.allSatisfy({$0.start.isFinite && $0.end.isFinite && $0.start>=0 && $0.end>$0.start && $0.from.isFinite && $0.to.isFinite && (40...20000).contains($0.from) && (40...20000).contains($0.to)}),
              zip(spans,spans.dropFirst()).allSatisfy({$0.end==$1.start}) else {
            throw CirclrError("신스 필터 오토메이션의 시간과 Hz 범위를 확인하세요")
        }
    }
    mutating func value(at seconds:Double)->Double {
        precondition(active)
        while index+1<spans.count && seconds>=spans[index].end {index+=1}
        return spans[index].value(at:seconds)
    }
}
