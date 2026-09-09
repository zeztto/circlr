import AppKit

@MainActor final class GeometryView:NSView {
    let usesFlippedCoordinates:Bool
    init(frame:NSRect,flipped:Bool){self.usesFlippedCoordinates=flipped;super.init(frame:frame);setAccessibilityElement(true);setAccessibilityRole(.group)}
    required init?(coder:NSCoder){fatalError()}
    override var isFlipped:Bool {usesFlippedCoordinates}
}
@main struct AccessibilityGeometryChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        var checks=0
        func check(_ element:NSAccessibilityElement,_ rect:NSRect,_ view:NSView,_ stage:String) {
            let expected=NSAccessibility.screenRect(fromView:view,rect:rect),actual=element.accessibilityFrame()
            precondition(abs(actual.minX-expected.minX)<0.01 && abs(actual.minY-expected.minY)<0.01 && abs(actual.width-expected.width)<0.01 && abs(actual.height-expected.height)<0.01,stage+": \(actual) != \(expected)")
            checks+=1
        }
        for flipped in [false,true] {
            let window=NSWindow(contentRect:NSRect(x:200,y:300,width:600,height:500),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
            let scroll=NSScrollView(frame:NSRect(x:30,y:40,width:400,height:300));window.contentView!.addSubview(scroll)
            let view=GeometryView(frame:NSRect(x:0,y:0,width:800,height:1800),flipped:flipped);scroll.documentView=view
            let rect=NSRect(x:120,y:450,width:112,height:28)
            let element=NSAccessibilityElement();element.setAccessibilityParent(view);element.setAccessibilityRole(.button)
            element.setFrameInView(rect,view:view);check(element,rect,view,"initial")
            window.setFrameOrigin(NSPoint(x:230,y:340));check(element,rect,view,"window movement without redraw")
            scroll.contentView.scroll(to:NSPoint(x:75,y:400));scroll.reflectScrolledClipView(scroll.contentView)
            check(element,rect,view,"document scrolling without redraw")
            view.setBoundsOrigin(NSPoint(x:15,y:25));element.setFrameInView(rect,view:view);check(element,rect,view,"nonzero bounds")
            view.setBoundsSize(NSSize(width:400,height:900));element.setFrameInView(rect,view:view);check(element,rect,view,"scaled bounds")
            view.setFrameSize(NSSize(width:920,height:2100));element.setFrameInView(rect,view:view);check(element,rect,view,"document resize")
            window.setContentSize(NSSize(width:800,height:600));check(element,rect,view,"window resize without redraw")
            window.orderOut(nil)
        }
        print("Accessibility geometry: \(checks) AppKit checks passed")
    }
}
