import AppKit

extension NSAccessibilityElement {
    /// Parent-space frames follow the view when its window moves or its document scrolls.
    @MainActor func setFrameInView(_ rect:NSRect,view:NSView) {
        let screen=NSAccessibility.screenRect(fromView:view,rect:rect)
        let parent=view.accessibilityFrame()
        setAccessibilityFrameInParentSpace(NSRect(x:screen.minX-parent.minX,y:screen.minY-parent.minY,width:screen.width,height:screen.height))
    }
}
