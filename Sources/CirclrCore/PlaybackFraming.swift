import Foundation
import CoreGraphics

/// Stable framing of the editable contents, independent of playhead position and signal level.
public enum PlaybackFraming {
    public static func camera(for section:CircleSceneNode,in scene:HierarchyScene,viewport:CGRect,
                              avoiding console:CGRect?=nil)->HierarchyCamera? {
        guard viewport.minX.isFinite,viewport.minY.isFinite,viewport.width.isFinite,viewport.height.isFinite,
              viewport.width>0,viewport.height>0 else{return nil}
        guard let content=scene.contextBounds(of:section.id) else { return nil }
        guard !content.isNull,content.width.isFinite,content.height.isFinite,content.width>0,content.height>0 else{return nil}
        if let console,console.intersects(viewport) {
            let circles=CanvasWorkspaceGeometry.contextCircles(section.id,in:scene)
            return CanvasWorkspaceGeometry.fittingCamera(circles:circles,within:viewport,
                                                         avoiding:console,marginX:min(56,viewport.width*0.12),
                                                         marginY:min(40,viewport.height*0.12))
        }
        // Reserve screen-space room for port handles and labels only once.
        let usable=viewport.insetBy(dx:min(56,viewport.width*0.12),dy:min(40,viewport.height*0.12))
        let zoom=min(1e12,max(1e-6,min(usable.width/content.width,usable.height/content.height)))
        return HierarchyCamera(pan:Point(usable.midX-content.midX*zoom,usable.midY-content.midY*zoom),zoom:zoom)
    }
}
