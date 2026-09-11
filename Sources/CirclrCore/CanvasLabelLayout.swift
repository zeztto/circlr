import CoreGraphics
import Foundation

public struct CanvasLabelRequest {
    public var id:CircleAddress
    public var anchor:CGPoint
    public var size:CGSize
    public var radius:Double
    public var expanded:Bool
    public var priority:Int
    public var allowsViewportAdjustment:Bool
    public init(id:CircleAddress,anchor:CGPoint,size:CGSize,radius:Double,expanded:Bool=false,priority:Int=0,allowsViewportAdjustment:Bool=false) {
        self.id=id;self.anchor=anchor;self.size=size;self.radius=radius;self.expanded=expanded;self.priority=priority
        self.allowsViewportAdjustment=allowsViewportAdjustment
    }
}
public struct CanvasLabelPlacement {
    public var id:CircleAddress
    public var rect:CGRect
    public var anchor:CGPoint
}
public struct CanvasLabelCircle {
    public var id:CircleAddress
    public var center:CGPoint
    public var radius:Double
    public init(id:CircleAddress,center:CGPoint,radius:Double) {self.id=id;self.center=center;self.radius=radius}
    public func intersects(_ rect:CGRect,clearance:Double=4)->Bool {
        guard radius.isFinite,radius>0,center.x.isFinite,center.y.isFinite else{return false}
        let x=max(rect.minX,min(rect.maxX,center.x)),y=max(rect.minY,min(rect.maxY,center.y))
        return hypot(x-center.x,y-center.y)<radius+clearance
    }
}
/// Screen-space labels keep a readable size while the musical orbits retain their true geometry.
public enum CanvasLabelLayout {
    public static func place(_ requests:[CanvasLabelRequest],within viewport:CGRect,avoiding obstacles:[CGRect]=[],circles:[CanvasLabelCircle]=[])->[CanvasLabelPlacement] {
        guard viewport.minX.isFinite,viewport.minY.isFinite,viewport.width.isFinite,viewport.height.isFinite,viewport.width>0,viewport.height>0 else{return []}
        var occupied=obstacles,result:[CanvasLabelPlacement]=[]
        let ordered=requests.enumerated().sorted{$0.element.priority==$1.element.priority ? $0.offset<$1.offset:$0.element.priority>$1.element.priority}
        for (_,request) in ordered {
            let p=request.anchor,w=request.size.width,h=request.size.height,r=request.radius
            guard w.isFinite,h.isFinite,w>0,h>0,r.isFinite,r>=0,p.x.isFinite,p.y.isFinite else{continue}
            var origins:[CGPoint]=[]
            if request.expanded {origins.append(CGPoint(x:p.x-w/2,y:p.y-r+22))}
            else if r>=45 {origins.append(CGPoint(x:p.x-w/2,y:p.y-h/2))}
            origins += [CGPoint(x:p.x+r+9,y:p.y-h/2),CGPoint(x:p.x-r-w-9,y:p.y-h/2),CGPoint(x:p.x-w/2,y:p.y+r+9),CGPoint(x:p.x-w/2,y:p.y-r-h-9)]
            // Alternate rows let dense, simultaneous starts remain individually selectable.
            for offset in [h+5,-h-5,2*h+10,-2*h-10] {origins.append(CGPoint(x:p.x+r+9,y:p.y-h/2+offset));origins.append(CGPoint(x:p.x-r-w-9,y:p.y-h/2+offset))}
            var candidates=origins.map{CGRect(origin:$0,size:request.size)}
            // Preserve normal placements first. Only the primary selection may move inward at an edge.
            // Never shrink the label or pull an unrelated, off-screen circle into the viewport.
            if request.allowsViewportAdjustment,w<=viewport.width,h<=viewport.height,
               viewport.contains(p) || CanvasLabelCircle(id:request.id,center:p,radius:r).intersects(viewport,clearance:0) {
                candidates += origins.map{CGRect(x:max(viewport.minX,min(viewport.maxX-w,$0.x)),y:max(viewport.minY,min(viewport.maxY-h,$0.y)),width:w,height:h)}
                // Nearby rows may all be occupied in a dense section. The viewport perimeter
                // offers space without moving any musical circle or hiding an editing control.
                let x=max(viewport.minX,min(viewport.maxX-w,p.x-w/2)),y=max(viewport.minY,min(viewport.maxY-h,p.y-h/2))
                let edges=[CGPoint(x:x,y:viewport.minY),CGPoint(x:x,y:viewport.maxY-h),
                           CGPoint(x:viewport.minX,y:y),CGPoint(x:viewport.maxX-w,y:y),
                           CGPoint(x:viewport.minX,y:viewport.minY),CGPoint(x:viewport.maxX-w,y:viewport.minY),
                           CGPoint(x:viewport.minX,y:viewport.maxY-h),CGPoint(x:viewport.maxX-w,y:viewport.maxY-h)]
                candidates += edges.enumerated().sorted{a,b in
                    let da=hypot(a.element.x+w/2-p.x,a.element.y+h/2-p.y),db=hypot(b.element.x+w/2-p.x,b.element.y+h/2-p.y)
                    return da==db ? a.offset<b.offset:da<db
                }.map{CGRect(origin:$0.element,size:request.size)}
            }
            if let rect=candidates.first(where:{candidate in viewport.contains(candidate) && !occupied.contains(where:{$0.intersects(candidate)}) && !circles.contains(where:{$0.id != request.id && $0.intersects(candidate)})}) {
                result.append(CanvasLabelPlacement(id:request.id,rect:rect,anchor:p));occupied.append(rect.insetBy(dx:-4,dy:-4))
            }
        }
        return result
    }
}

public enum CanvasWorkspaceGeometry {
    public static func viewport(width:Double,height:Double,console:CGRect?=nil)->CGRect {
        let bottom=min(height-58,console.map{$0.minY-14} ?? height-58)
        return CGRect(x:24,y:78,width:max(1,width-48),height:max(1,bottom-78))
    }
    public static func editor(center:CGPoint,radius:Double,within viewport:CGRect)->CGRect {
        let w=min(1040,viewport.width,max(1,radius*1.9)),h=min(760,viewport.height,max(1,radius*1.6))
        return CGRect(x:max(viewport.minX,min(viewport.maxX-w,center.x-w/2)),y:max(viewport.minY,min(viewport.maxY-h,center.y-h/2)),width:w,height:h)
    }
}
