import AppKit

/// Render directly into the movie's bounded raster instead of allocating a
/// full Retina snapshot and scaling that intermediate image down afterwards.
@MainActor enum CanvasMovieCapture {
    static func pixelSize(bounds:NSRect,backingScale:CGFloat)->CGSize? {
        guard bounds.width.isFinite,bounds.height.isFinite,bounds.width>=64,bounds.height>=64,
              backingScale.isFinite,backingScale>0 else{return nil}
        let scale=min(backingScale,1920/bounds.width,1080/bounds.height)
        return CGSize(width:max(64,Int(bounds.width*scale)/2*2),height:max(64,Int(bounds.height*scale)/2*2))
    }
    static func image(of view:NSView)->CGImage? {
        guard let size=pixelSize(bounds:view.bounds,backingScale:view.window?.backingScaleFactor ?? 1),
              let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:Int(size.width)*4,bitsPerPixel:32),
              let context=NSGraphicsContext(bitmapImageRep:bitmap) else{return nil}
        NSGraphicsContext.saveGraphicsState()
        defer{NSGraphicsContext.restoreGraphicsState()}
        NSGraphicsContext.current=context
        let cg=context.cgContext
        cg.clear(CGRect(origin:.zero,size:size))
        cg.scaleBy(x:size.width/view.bounds.width,y:size.height/view.bounds.height)
        cg.translateBy(x:-view.bounds.minX,y:-view.bounds.minY)
        // AppKit traverses descendants and applies their view transforms. This
        // keeps the same editor/hidden-subview policy as ordinary canvas drawing.
        view.displayIgnoringOpacity(view.bounds,in:context)
        return bitmap.cgImage
    }
}
