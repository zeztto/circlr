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
    public var avoidsOwnRing:Bool
    public init(id:CircleAddress,anchor:CGPoint,size:CGSize,radius:Double,expanded:Bool=false,priority:Int=0,allowsViewportAdjustment:Bool=false,avoidsOwnRing:Bool=false) {
        self.id=id;self.anchor=anchor;self.size=size;self.radius=radius;self.expanded=expanded;self.priority=priority
        self.allowsViewportAdjustment=allowsViewportAdjustment
        self.avoidsOwnRing=avoidsOwnRing
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
    /// A label can sit wholly inside a large orbit or wholly outside it, but
    /// must leave the time-bearing ring and its bar ticks visible.
    public static func obscuresRing(_ rect:CGRect,center:CGPoint,radius:Double,clearance:Double=8)->Bool {
        let nearX=max(rect.minX,min(rect.maxX,center.x))-center.x
        let nearY=max(rect.minY,min(rect.maxY,center.y))-center.y
        let farX=max(abs(rect.minX-center.x),abs(rect.maxX-center.x))
        let farY=max(abs(rect.minY-center.y),abs(rect.maxY-center.y))
        let outer=radius+clearance,inner=max(0,radius-clearance)
        return nearX*nearX+nearY*nearY<outer*outer && farX*farX+farY*farY>inner*inner
    }
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
            // Preserve normal placements first. Selected nodes and direct song sections
            // in narrow views may use spare viewport space without moving music circles.
            // Never shrink the label or pull an unrelated, off-screen circle into view.
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
                // A crowded orbit can block the four nearest edges. Search a small,
                // deterministic lattice only after the familiar local positions.
                let fractions:[Double]=[0,0.25,0.5,0.75,1]
                let lattice=fractions.flatMap { fy in fractions.map { fx in
                    CGPoint(x:viewport.minX+(viewport.width-w)*fx,y:viewport.minY+(viewport.height-h)*fy)
                }}
                candidates += lattice.enumerated().sorted { a,b in
                    let da=hypot(a.element.x+w/2-p.x,a.element.y+h/2-p.y)
                    let db=hypot(b.element.x+w/2-p.x,b.element.y+h/2-p.y)
                    return da==db ? a.offset<b.offset:da<db
                }.map{CGRect(origin:$0.element,size:request.size)}
            }
            if let rect=candidates.first(where:{candidate in viewport.contains(candidate) &&
                !(request.avoidsOwnRing && obscuresRing(candidate,center:p,radius:r)) &&
                !occupied.contains(where:{$0.intersects(candidate)}) &&
                !circles.contains(where:{$0.id != request.id && $0.intersects(candidate)})}) {
                result.append(CanvasLabelPlacement(id:request.id,rect:rect,anchor:p));occupied.append(rect.insetBy(dx:-4,dy:-4))
            }
        }
        return result
    }
}

public enum CanvasWorkspaceGeometry {
    public static func containsInteractivePoint(_ point:CGPoint,within viewport:CGRect,avoiding console:CGRect?=nil)->Bool {
        viewport.contains(point) && !(console?.contains(point) ?? false)
    }
    public static func circlesVisible(_ circles:[CanvasLabelCircle],through camera:HierarchyCamera,
                                      within viewport:CGRect,avoiding console:CGRect?=nil,
                                      margin:Double=20)->Bool {
        guard !circles.isEmpty,margin.isFinite,margin>=0,viewport.width>2*margin,
              viewport.height>2*margin,camera.zoom.isFinite,camera.zoom>0 else{return false}
        let safe=viewport.insetBy(dx:margin,dy:margin)
        let obstacle=console?.insetBy(dx:-14,dy:-14)
        return circles.allSatisfy { circle in
            guard circle.center.x.isFinite,circle.center.y.isFinite,circle.radius.isFinite,circle.radius>0 else{return false}
            let center=camera.screen(Point(circle.center.x,circle.center.y)),radius=circle.radius*camera.zoom
            guard center.x.isFinite,center.y.isFinite,radius.isFinite,radius>0 else{return false}
            let frame=CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)
            return safe.contains(frame) && !(obstacle?.intersects(frame) ?? false)
        }
    }
    /// A cubic stays inside its control-point hull. This conservative check is
    /// used before preserving a keyboard-focused cable in the L-shaped workspace.
    public static func curveVisible(_ curve:CirclePortCurve,within viewport:CGRect,
                                    avoiding console:CGRect?=nil,margin:Double=70)->Bool {
        guard margin.isFinite,margin>=0,viewport.width>2*margin,viewport.height>2*margin else{return false}
        let points=[curve.from,curve.control1,curve.control2,curve.to]
        guard points.allSatisfy({$0.x.isFinite && $0.y.isFinite}) else{return false}
        let minX=points.map(\.x).min()!,maxX=points.map(\.x).max()!
        let minY=points.map(\.y).min()!,maxY=points.map(\.y).max()!
        let hull=CGRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY).insetBy(dx:-0.5,dy:-0.5)
        return viewport.insetBy(dx:margin,dy:margin).contains(hull) &&
            !(console?.insetBy(dx:-14,dy:-14).intersects(hull) ?? false)
    }
    public static func viewport(width:Double,height:Double,console:CGRect?=nil)->CGRect {
        let bottom=min(height-58,console.map{$0.minY-14} ?? height-58)
        return CGRect(x:24,y:78,width:max(1,width-48),height:max(1,bottom-78))
    }
    /// A console across only the left side leaves a usable lower-right area. A single
    /// CGRect cannot describe that shape, so fit the actual orbit disks instead of
    /// shrinking the whole song to the rectangle above the console.
    public static func fittingCamera(circles:[CanvasLabelCircle],within viewport:CGRect,
                                     avoiding console:CGRect?=nil,marginX:Double=50,marginY:Double=40,
                                     maximumZoom:Double?=nil)->HierarchyCamera? {
        guard !circles.isEmpty,viewport.minX.isFinite,viewport.minY.isFinite,
              viewport.width.isFinite,viewport.height.isFinite,viewport.width>2*marginX,
              viewport.height>2*marginY,marginX>=0,marginY>=0,
              maximumZoom.map({$0.isFinite && $0>0}) ?? true,
              circles.allSatisfy({$0.center.x.isFinite && $0.center.y.isFinite && $0.radius.isFinite && $0.radius>0}) else{return nil}
        let left=circles.map{$0.center.x-$0.radius}.min()!,right=circles.map{$0.center.x+$0.radius}.max()!
        let top=circles.map{$0.center.y-$0.radius}.min()!,bottom=circles.map{$0.center.y+$0.radius}.max()!
        let content=CGRect(x:left,y:top,width:right-left,height:bottom-top)
        guard content.width.isFinite,content.height.isFinite,content.width>0,content.height>0 else{return nil}
        let usable=viewport.insetBy(dx:marginX,dy:marginY)
        let upper=min(1e12,maximumZoom ?? 1e12,usable.width/content.width,usable.height/content.height)
        guard upper.isFinite,upper>0 else{return nil}
        let centered=HierarchyCamera(pan:Point(usable.midX-content.midX*upper,
                                                usable.midY-content.midY*upper),zoom:upper)
        guard let console,console.width>0,console.height>0,console.minX.isFinite,
              console.minY.isFinite,console.maxX.isFinite,console.maxY.isFinite,
              console.intersects(viewport) else{return centered}
        // The lower-left console reaches below the canvas's bottom safety margin.
        // Other obstacle shapes retain the conservative rectangular camera.
        let clearance=14.0,blocked=console.insetBy(dx:-clearance,dy:-clearance)
        // This search tests each possible disk at every scale. Dense signal graphs
        // use the conservative top band to keep focus changes within a frame budget.
        guard circles.count<=80,blocked.minX<=usable.minX,blocked.maxY>=usable.maxY else {
            let topViewport=CGRect(x:viewport.minX,y:viewport.minY,width:viewport.width,
                                   height:max(1,blocked.minY-viewport.minY))
            return fittingCamera(circles:circles,within:topViewport,
                                 marginX:marginX,marginY:min(marginY,max(0,topViewport.height/4)))
        }
        func camera(at zoom:Double)->HierarchyCamera? {
            let minX=circles.map{usable.minX-($0.center.x-$0.radius)*zoom}.max()!
            let maxX=circles.map{usable.maxX-($0.center.x+$0.radius)*zoom}.min()!
            let minY=circles.map{usable.minY-($0.center.y-$0.radius)*zoom}.max()!
            let maxY=circles.map{usable.maxY-($0.center.y+$0.radius)*zoom}.min()!
            guard minX<=maxX+1e-8,minY<=maxY+1e-8 else{return nil}
            let idealX=usable.midX-content.midX*zoom,idealY=usable.midY-content.midY*zoom
            let thresholds=circles.map{blocked.maxX-($0.center.x-$0.radius)*zoom}
            let candidates=([minX,maxX,idealX]+thresholds+thresholds.map{$0+1e-6})
                .map{max(minX,min(maxX,$0))}
            var best:(camera:HierarchyCamera,cost:Double)?
            for panX in candidates {
                var permittedMaxY=maxY
                for circle in circles {
                    let diskLeft=panX+(circle.center.x-circle.radius)*zoom
                    let diskRight=panX+(circle.center.x+circle.radius)*zoom
                    if diskLeft<blocked.maxX-1e-8 && diskRight>blocked.minX+1e-8 {
                        permittedMaxY=min(permittedMaxY,blocked.minY-(circle.center.y+circle.radius)*zoom)
                    }
                }
                guard minY<=permittedMaxY+1e-8 else{continue}
                let panY=max(minY,min(permittedMaxY,idealY))
                let cost=pow(panX-idealX,2)+pow(panY-idealY,2)
                if best == nil || cost<best!.cost {
                    best=(HierarchyCamera(pan:Point(panX,panY),zoom:zoom),cost)
                }
            }
            return best?.camera
        }
        if let camera=camera(at:upper) {return camera}
        var low=0.0,high=upper,best:HierarchyCamera?
        for _ in 0..<42 {
            let mid=(low+high)/2
            if let candidate=camera(at:mid) {low=mid;best=candidate}
            else {high=mid}
        }
        return best
    }
    /// Match HierarchyScene.contextBounds' semantic level, including expanded groups.
    public static func contextCircles(_ address:CircleAddress,in scene:HierarchyScene)->[CanvasLabelCircle] {
        guard let owner=scene.node(address) else{return []}
        var targets=scene.children(of:address)
        if scene.isOrbit {
            var pending=targets.filter{$0.role == .group}
            while let group=pending.popLast() {
                let members=scene.children(of:group.id)
                targets.append(contentsOf:members)
                pending.append(contentsOf:members.filter{$0.role == .group})
            }
        }
        if scene.isOrbit || targets.isEmpty {targets.insert(owner,at:0)}
        return targets.map{CanvasLabelCircle(id:$0.id,center:CGPoint(x:$0.center.x,y:$0.center.y),radius:$0.outerRadius)}
    }
    public static func editor(center:CGPoint,radius:Double,within viewport:CGRect)->CGRect {
        let w=min(1040,viewport.width,max(1,radius*1.9)),h=min(760,viewport.height,max(1,radius*1.6))
        return CGRect(x:max(viewport.minX,min(viewport.maxX-w,center.x-w/2)),y:max(viewport.minY,min(viewport.maxY-h,center.y-h/2)),width:w,height:h)
    }
}
