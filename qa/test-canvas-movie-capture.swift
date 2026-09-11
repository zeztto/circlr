// Run from the repository root (offline AppKit fixture; no user project/audio):
// swiftc Sources/CirclrApp/CanvasMovieCapture.swift qa/test-canvas-movie-capture.swift -o .build/canvas-capture-qa
// .build/canvas-capture-qa
import AppKit
@MainActor final class Painted:NSView {
    override var isFlipped:Bool {true}
    override func draw(_ dirtyRect:NSRect) {
        NSColor.red.setFill();NSRect(x:0,y:0,width:bounds.width,height:bounds.height/2).fill()
        NSColor.blue.setFill();NSRect(x:0,y:bounds.height/2,width:bounds.width,height:bounds.height/2).fill()
    }
}
@MainActor final class Child:NSView {
    override func draw(_ dirtyRect:NSRect) {NSColor.green.setFill();bounds.fill()}
}
@main struct Fixture {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let rect=NSRect(x:0,y:0,width:3000,height:2000)
        let window=NSWindow(contentRect:rect,styleMask:.borderless,backing:.buffered,defer:false)
        let view=Painted(frame:rect);view.wantsLayer=true
        let child=Child(frame:NSRect(x:600,y:400,width:600,height:400));child.wantsLayer=true
        view.addSubview(child);window.contentView=view
        let image=CanvasMovieCapture.image(of:view)!
        let bitmap=NSBitmapImageRep(cgImage:image)
        func rgb(_ x:Int,_ y:Int)->[Double] {let c=bitmap.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!;return [c.redComponent,c.greenComponent,c.blueComponent]}
        precondition(image.width==1620 && image.height==1080)
        precondition(rgb(100,100)[0]>0.9)
        precondition(rgb(100,900)[2]>0.9)
        precondition(rgb(400,300)[1]>0.9)
        child.isHidden=true
        let hidden=NSBitmapImageRep(cgImage:CanvasMovieCapture.image(of:view)!)
        precondition(hidden.colorAt(x:400,y:300)!.usingColorSpace(.deviceRGB)!.redComponent>0.9)
        precondition(CanvasMovieCapture.pixelSize(bounds:NSRect(x:0,y:0,width:1500,height:900),backingScale:2)==CGSize(width:1800,height:1080))
        precondition(CanvasMovieCapture.pixelSize(bounds:NSRect(x:0,y:0,width:100,height:100),backingScale:2)==CGSize(width:200,height:200))
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:".build/r40-capture-fixture.png"))
        print("PASS direct capture 1620x1080, flipped red/blue regions, layer-backed green descendant, hidden descendant exclusion, Retina geometry")
    }
}
