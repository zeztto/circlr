import CirclrCore
import Foundation

enum AutomationDSP {
    static func apply(_ plans:[AutomationPlan],to pcm:inout PCM)throws {
        for plan in plans {
            guard !plan.spans.isEmpty else{continue}
            var cursor=0
            for frame in pcm.left.indices {
                if frame%8192==0 {try Task.checkCancellation()}
                let seconds=Double(frame)/PCM.rate
                while cursor+1<plan.spans.count && seconds>=plan.spans[cursor].end {cursor+=1}
                let value=plan.spans[cursor].value(at:seconds)
                switch plan.parameter {
                case .gain:pcm.left[frame]*=Float(value);pcm.right[frame]*=Float(value)
                case .pan:pcm.left[frame]*=Float(sqrt(max(0,1-value)));pcm.right[frame]*=Float(sqrt(max(0,1+value)))
                }
            }
        }
    }
}
