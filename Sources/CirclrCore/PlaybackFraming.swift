import Foundation
import CoreGraphics

/// Stable framing of the editable contents, independent of playhead position and signal level.
public enum PlaybackFraming {
    public static func camera(for section:CircleSceneNode,in scene:HierarchyScene,viewport:CGRect)->HierarchyCamera? {
        guard viewport.minX.isFinite,viewport.minY.isFinite,viewport.width.isFinite,viewport.height.isFinite,
              viewport.width>0,viewport.height>0 else{return nil}
        let children=scene.children(of:section.id)
        let targets=children.isEmpty ? [section]:children
        var content=CGRect.null
        for node in targets {
            let r=node.outerRadius
            guard node.center.x.isFinite,node.center.y.isFinite,r.isFinite,r>0 else{return nil}
            content=content.union(CGRect(x:node.center.x-r,y:node.center.y-r,width:r*2,height:r*2))
        }
        guard !content.isNull,content.width.isFinite,content.height.isFinite,content.width>0,content.height>0 else{return nil}
        // Reserve screen-space room for port handles and labels only once.
        let usable=viewport.insetBy(dx:min(56,viewport.width*0.12),dy:min(40,viewport.height*0.12))
        let zoom=min(1e12,max(1e-6,min(usable.width/content.width,usable.height/content.height)))
        return HierarchyCamera(pan:Point(usable.midX-content.midX*zoom,usable.midY-content.midY*zoom),zoom:zoom)
    }
}
