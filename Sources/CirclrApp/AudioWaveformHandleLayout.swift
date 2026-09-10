import Foundation
import CoreGraphics

/// Shared drawing and hit geometry. Hidden endpoints do not reserve label space.
struct AudioWaveformHandleLayout {
    struct Handle {
        let timeX:CGFloat
        let dot:CGPoint
        var label:CGRect
    }
    let compact:Bool
    let hitRadius:CGFloat
    let start:Handle?
    let end:Handle?

    init(bounds:CGRect,plot:CGRect,startX:CGFloat?,endX:CGFloat?,startLabel:CGSize,endLabel:CGSize) {
        let isCompact = startX.flatMap{a in endX.map{abs($0-a)<28}} ?? false
        compact=isCompact
        let offset=min(12,max(0,plot.height/2-5))
        hitRadius=isCompact ? min(9,max(1,offset-2)):14
        func handle(_ x:CGFloat?,label:CGSize,isEnd:Bool)->Handle? {
            guard let x else{return nil}
            let width=min(label.width,max(0,bounds.width-4))
            let left=min(bounds.maxX-2-width,max(bounds.minX+2,x-width/2))
            return Handle(timeX:x,dot:CGPoint(x:x,y:bounds.midY+(isCompact ? (isEnd ? offset:-offset):0)),
                          label:CGRect(x:left,y:bounds.maxY-15,width:width,height:label.height))
        }
        var a=handle(startX,label:startLabel,isEnd:false),b=handle(endX,label:endLabel,isEnd:true)
        if var left=a,var right=b,left.label.maxX+6>right.label.minX {
            let total=left.label.width+6+right.label.width
            if total<=bounds.width-4 {
                let origin=min(bounds.maxX-2-total,max(bounds.minX+2,(left.timeX+right.timeX-total)/2))
                left.label.origin.x=origin;right.label.origin.x=origin+left.label.width+6
            } else {
                // Extremely narrow views cannot fit both words on one baseline.
                right.label.origin.y=left.label.minY-right.label.height-2
            }
            a=left;b=right
        }
        start=a;end=b
    }
    func acceptsMouseDown(at point:CGPoint,bounds:CGRect,plot:CGRect)->Bool {
        plot.contains(point) || (compact && bounds.contains(point)
            && min(distance(to:point,end:false),distance(to:point,end:true))<hitRadius)
    }
    func distance(to point:CGPoint,end isEnd:Bool)->CGFloat {
        guard let handle=isEnd ? end:start else{return .infinity}
        return compact ? hypot(point.x-handle.dot.x,point.y-handle.dot.y):abs(point.x-handle.timeX)
    }
}
