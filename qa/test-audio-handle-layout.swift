import Foundation
import CoreGraphics

@main struct AudioHandleGeometryQA {
    static var failures: [String] = []
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures.append(message) }
    }
    static func finite(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
    }
    static func hit(_ layout: AudioWaveformHandleLayout, _ point: CGPoint) -> String {
        let a = layout.distance(to: point, end: false), b = layout.distance(to: point, end: true)
        guard min(a, b) < layout.hitRadius else { return "split" }
        return b < a ? "end" : "start"
    }
    static func main() {
        var scenarios = 0
        // Full-source zoom spans subpixel clips through roughly 13 pixels here.
        for width: CGFloat in [25, 32, 44, 120, 320, 848] {
            for origin: CGFloat in [0, 37] {
                let bounds = CGRect(x: origin, y: 11, width: width, height: 80)
                let plot = bounds.insetBy(dx: 12, dy: 22)
                for duration: CGFloat in [0.05, 0.5] {
                    for time: CGFloat in [0, (32-duration)/2, 32-duration] {
                        scenarios += 1
                        let label = "width=\(width), origin=\(origin), start=\(time), duration=\(duration)"
                        let startX = plot.minX + time/32 * plot.width
                        let endX = plot.minX + (time+duration)/32 * plot.width
                        let layout = AudioWaveformHandleLayout(bounds: bounds, plot: plot,
                            startX: startX, endX: endX, startLabel: CGSize(width: 20, height: 12), endLabel: CGSize(width: 12, height: 12))
                        guard let a=layout.start, let b=layout.end else { failures.append(label + " missing handle"); continue }
                        expect(layout.compact, label + " expected compact")
                        expect(a.timeX == startX && b.timeX == endX, label + " time mapping moved")
                        expect(a.dot.x == startX && b.dot.x == endX, label + " dot time moved")
                        expect(bounds.contains(a.label) && bounds.contains(b.label), label + " label out of bounds")
                        expect(!a.label.intersects(b.label), label + " labels overlap")
                        expect(finite(a.label) && finite(b.label) && layout.hitRadius.isFinite, label + " nonfinite geometry")
                        expect([a.dot.x,a.dot.y,b.dot.x,b.dot.y].allSatisfy(\.isFinite), label + " nonfinite dot")
                        expect(hit(layout, a.dot) == "start", label + " start hit lost")
                        expect(hit(layout, b.dot) == "end", label + " end hit lost")
                        expect(hit(layout, CGPoint(x:(startX+endX)/2,y:bounds.midY)) == "split", label + " central split stolen")
                    }
                }
            }
        }
        let bounds = CGRect(x:0,y:0,width:848,height:160)
        let plot = bounds.insetBy(dx:12,dy:22)
        let wide = AudioWaveformHandleLayout(bounds:bounds,plot:plot,startX:100,endX:500,
            startLabel:CGSize(width:20,height:12),endLabel:CGSize(width:12,height:12))
        expect(!wide.compact && wide.hitRadius == 14, "wide legacy hit radius")
        for y in [plot.minY, plot.midY, plot.maxY] {
            expect(hit(wide, CGPoint(x:113,y:y)) == "start", "wide vertical start hit")
            expect(hit(wide, CGPoint(x:487,y:y)) == "end", "wide vertical end hit")
            expect(hit(wide, CGPoint(x:114,y:y)) == "split", "wide strict radius boundary")
        }
        for hiddenStart in [true,false] {
            let layout = AudioWaveformHandleLayout(bounds:bounds,plot:plot,
                startX:hiddenStart ? nil:100,endX:hiddenStart ? 500:nil,
                startLabel:CGSize(width:20,height:12),endLabel:CGSize(width:12,height:12))
            expect(layout.distance(to:CGPoint(x:hiddenStart ? 100:500,y:80),end:!hiddenStart).isInfinite,
                   "offscreen endpoint must not hit")
            expect(hit(layout,CGPoint(x:hiddenStart ? 100:500,y:80)) == "split", "offscreen steals click")
            let handle = hiddenStart ? layout.end! : layout.start!
            expect(bounds.contains(handle.label), "single visible label bounds")
        }
        // Exercise the same admission API called by OrbitAudioView.mouseDown.
        // The former plot.contains-only guard rejected these visible dot edges.
        for duration: CGFloat in [0.05, 0.5] {
            for atEnd in [false, true] {
                let startX = atEnd ? plot.maxX-duration/32*plot.width : plot.minX
                let endX = atEnd ? plot.maxX : plot.minX+duration/32*plot.width
                let layout = AudioWaveformHandleLayout(bounds:bounds,plot:plot,startX:startX,endX:endX,
                    startLabel:CGSize(width:20,height:12),endLabel:CGSize(width:12,height:12))
                let endpoint = atEnd ? layout.end! : layout.start!
                for outside: CGFloat in [0.6, 4.5] {
                    let point = CGPoint(x:endpoint.dot.x + (atEnd ? outside : -outside), y:endpoint.dot.y)
                    expect(!plot.contains(point), "boundary fixture must reproduce old guard rejection")
                    expect(bounds.contains(point), "visible dot edge must stay inside view")
                    expect(layout.acceptsMouseDown(at:point,bounds:bounds,plot:plot), "visible endpoint edge ignored")
                    expect(hit(layout,point) == (atEnd ? "end" : "start"), "endpoint edge chose wrong trim")
                }
                let middleOutside = CGPoint(x:atEnd ? plot.maxX+0.6 : plot.minX-0.6,y:bounds.midY)
                expect(!layout.acceptsMouseDown(at:middleOutside,bounds:bounds,plot:plot), "plot-outside center must ignore")
                let outsideBounds = CGPoint(x:atEnd ? bounds.maxX+0.6 : bounds.minX-0.6,y:endpoint.dot.y)
                expect(!layout.acceptsMouseDown(at:outsideBounds,bounds:bounds,plot:plot), "view-outside point must ignore")
                let center = CGPoint(x:(startX+endX)/2,y:bounds.midY)
                expect(layout.acceptsMouseDown(at:center,bounds:bounds,plot:plot) && hit(layout,center) == "split",
                       "inside-plot central split lost")
            }
        }
        let wideEdge = AudioWaveformHandleLayout(bounds:bounds,plot:plot,startX:plot.minX,endX:plot.maxX,
            startLabel:CGSize(width:20,height:12),endLabel:CGSize(width:12,height:12))
        expect(!wideEdge.acceptsMouseDown(at:CGPoint(x:plot.minX-0.6,y:bounds.midY),bounds:bounds,plot:plot),
               "wide legacy outside-plot guard changed")
        let empty = AudioWaveformHandleLayout(bounds:bounds,plot:plot,startX:nil,endX:nil,
            startLabel:CGSize(width:20,height:12),endLabel:CGSize(width:12,height:12))
        expect(hit(empty,CGPoint(x:400,y:80)) == "split", "both hidden steal click")
        let output: [String:Any] = ["status":failures.isEmpty ? "passed":"failed",
            "shortClipScenarios":scenarios,"checks":checks,"failures":failures,
            "appLaunched":false,"audioAPICalls":0]
        let data = try! JSONSerialization.data(withJSONObject:output,options:[.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
        if !failures.isEmpty { exit(1) }
    }
}
