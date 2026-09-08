import CoreGraphics
import Foundation

public struct CanvasLabelRequest {
    public var id:CircleAddress
    public var anchor:CGPoint
    public var size:CGSize
    public var radius:Double
    public var expanded:Bool
    public var priority:Int
    public init(id:CircleAddress,anchor:CGPoint,size:CGSize,radius:Double,expanded:Bool=false,priority:Int=0) {
        self.id=id;self.anchor=anchor;self.size=size;self.radius=radius;self.expanded=expanded;self.priority=priority
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
            if let rect=origins.map({CGRect(origin:$0,size:request.size)}).first(where:{candidate in viewport.contains(candidate) && !occupied.contains(where:{$0.intersects(candidate)}) && !circles.contains(where:{$0.id != request.id && $0.intersects(candidate)})}) {
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
