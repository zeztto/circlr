import Foundation
import CirclrCore

/// Stereo Schroeder-Moorer network: damped combs, true all-pass diffusion and pre-delay.
/// Legacy effects retain their original algorithm through Effect.renderVersion.
enum DiffuseReverb {
    static func process(_ input:PCM,size:Double,wet:Double) throws -> PCM {
        if wet==0{return input}
        let time=0.45+size*3.2,scale=0.72+size*0.65
        let lengths=[1427,1559,1699,1867,1999,2131,2281,2437]
        let pre=864,damping=Float(1-exp(-2*Double.pi*(4200-size*1700)/PCM.rate))
        var result=input
        for channel in 0..<2 {
            try Task.checkCancellation()
            let source=channel==0 ? input.left:input.right
            var send=[Float](repeating:0,count:input.count),low:Float=0
            let highpass=Float(1-exp(-2*Double.pi*180/PCM.rate))
            for i in source.indices {low+=highpass*(source[i]-low);if i+pre<send.count{send[i+pre]=source[i]-low}}
            var diffuse=[Float](repeating:0,count:input.count)
            for base in lengths {
                let length=Int(Double(base)*scale)+channel*31
                var line=[Float](repeating:0,count:length),filtered:Float=0,cursor=0
                let feedback=Float(pow(0.001,Double(length)/(time*PCM.rate)))
                for i in diffuse.indices {
                    let delayed=line[cursor];filtered+=damping*(delayed-filtered)
                    line[cursor]=send[i]+filtered*feedback;diffuse[i]+=delayed*0.125
                    cursor+=1;if cursor==length{cursor=0}
                }
            }
            for base in [563,421,281,179] {
                let length=base+channel*17
                var line=[Float](repeating:0,count:length),cursor=0
                for i in diffuse.indices {
                    let delayed=line[cursor],value=diffuse[i]
                    let output=delayed-0.55*value
                    line[cursor]=value+0.55*output;diffuse[i]=output
                    cursor+=1;if cursor==length{cursor=0}
                }
            }
            if channel==0 {for i in diffuse.indices {result.left[i]+=diffuse[i]*Float(wet)}}
            else {for i in diffuse.indices {result.right[i]+=diffuse[i]*Float(wet)}}
        }
        return result
    }
}
