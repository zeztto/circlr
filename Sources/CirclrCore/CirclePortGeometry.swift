import Foundation

public struct CirclePortHandle:Equatable,Sendable {
    public var endpoint:CirclePortEndpoint
    public var octant:PortOctant
    public var point:Point
    public init(endpoint:CirclePortEndpoint,octant:PortOctant,point:Point){self.endpoint=endpoint;self.octant=octant;self.point=point}
}
public struct CirclePortCurve:Equatable,Sendable {
    public var from:Point,control1:Point,control2:Point,to:Point
    public func point(at progress:Double)throws->Point {
        guard progress.isFinite else{throw CirclrError("연결선 진행 위치를 확인하세요")}
        let t=min(1,max(0,progress)),u=1-t
        return Point(u*u*u*from.x+3*u*u*t*control1.x+3*u*t*t*control2.x+t*t*t*to.x,u*u*u*from.y+3*u*u*t*control1.y+3*u*t*t*control2.y+t*t*t*to.y)
    }
}
public enum CirclePortGeometry {
    public static let hitRadius=9.0
    public static func normal(_ octant:PortOctant)->Point {
        let angle=Double(octant.rawValue)*Double.pi/4-Double.pi/2
        return Point(cos(angle),sin(angle))
    }
    public static func nearestOctant(to point:Point,center:Point)->PortOctant? {
        guard valid(point),valid(center),hypot(point.x-center.x,point.y-center.y)>1e-9 else{return nil}
        let angle=atan2(point.y-center.y,point.x-center.x)+Double.pi/2
        let wrapped=angle<0 ? angle+2*Double.pi:angle
        return PortOctant(rawValue:Int(floor(wrapped/(Double.pi/4)+0.5))%8)
    }
    private static func valid(_ point:Point)->Bool {point.x.isFinite && point.y.isFinite && abs(point.x)<=1e12 && abs(point.y)<=1e12}
    /// All distances are screen points; zoomed world coordinates must be converted before calling.
    public static func anchor(center:Point,radius:Double,port:CirclePort,octant:PortOctant)throws->Point {
        guard valid(center),radius.isFinite,(0...1e9).contains(radius) else{throw CirclrError("포트의 화면 좌표와 반경을 확인하세요")}
        let offset:Double
        if port.id == AudioRouter.input2 { offset=68 }
        else if port.id == AudioRouter.output2 { offset=90 }
        else { offset=port.isSidechain ? 68:port.direction == .input ? 24:46 }
        let n=normal(octant);return Point(center.x+(radius+offset)*n.x,center.y+(radius+offset)*n.y)
    }
    /// Only pass handles that were actually drawn. Hidden/collapsed choices cannot be hit.
    public static func hit(_ point:Point,visibleHandles:[CirclePortHandle])->CirclePortHandle? {
        guard valid(point) else{return nil}
        return visibleHandles.filter{valid($0.point) && hypot($0.point.x-point.x,$0.point.y-point.y)<=hitRadius}
            .min{hypot($0.point.x-point.x,$0.point.y-point.y)<hypot($1.point.x-point.x,$1.point.y-point.y)}
    }
    public static func curve(from:CirclePortHandle,to:CirclePortHandle)throws->CirclePortCurve {
        guard valid(from.point),valid(to.point) else{throw CirclrError("연결선의 끝점을 확인하세요")}
        let distance=hypot(from.point.x-to.point.x,from.point.y-to.point.y),reach=min(200,max(32,distance*0.38))
        let a=normal(from.octant),b=normal(to.octant)
        return .init(from:from.point,control1:Point(from.point.x+a.x*reach,from.point.y+a.y*reach),control2:Point(to.point.x+b.x*reach,to.point.y+b.y*reach),to:to.point)
    }
}
