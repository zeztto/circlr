import AppKit
import SwiftUI

/// Root-run widget-only rendering. No AppStore, transport, device, or audio backend.
@main struct AuditionReadoutNativeHost {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain:"AuditionReadoutQA",code:1,userInfo:[NSLocalizedDescriptionKey:"Pass production presentation fixture JSON and a new output directory"])
        }
        let directory = URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
        guard !FileManager.default.fileExists(atPath:directory.path) else {
            throw NSError(domain:"AuditionReadoutQA",code:2,userInfo:[NSLocalizedDescriptionKey:"Preserve existing evidence"])
        }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let fixtureData = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let fixture = try JSONSerialization.jsonObject(with:fixtureData) as! [String:Any]
        let scenarios = fixture["scenarios"] as! [[String:Any]]
        var records:[[String:Any]] = []
        for scenario in scenarios {
            let name=scenario["name"] as! String, time=scenario["time"] as! String
            let label=scenario["label"] as? String, detail=scenario["detail"] as! String
            let footer=scenario["footer"] as? String
            guard name.range(of:"^[a-zA-Z0-9-]+$",options:.regularExpression) != nil else {
                throw NSError(domain:"AuditionReadoutQA",code:5)
            }
            let readout = TransportStatusReadout(time:time,label:label,detail:detail,footer:footer,
                textColor:Color(nsColor:NSColor(white:0.94,alpha:1)),
                secondaryColor:Color(nsColor:NSColor(white:0.63,alpha:1)))
                .padding(12).background(Color(nsColor:NSColor(white:0.065,alpha:1)))
                .environment(\.colorScheme,.dark)
            let host = NSHostingView(rootView:readout)
            host.frame = NSRect(x:0,y:0,width:132,height:96)
            let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView = host
            window.appearance = NSAppearance(named:.darkAqua)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else {
                throw NSError(domain:"AuditionReadoutQA",code:3)
            }
            host.cacheDisplay(in:host.bounds,to:bitmap)
            guard let data = bitmap.representation(using:.png,properties:[:]) else {
                throw NSError(domain:"AuditionReadoutQA",code:4)
            }
            try data.write(to:directory.appendingPathComponent(name+".png"),options:.withoutOverwriting)
            records.append(["name":name,"widgetWidth":108,"label":label ?? "", "detail":detail,
                            "footer":footer ?? "","file":name+".png"])
            window.close()
        }
        let report:[String:Any] = ["scope":"Production TransportStatusReadout with actual AuditionPresentation JSON; dark offscreen widget only, not full-app integration",
            "audioBackendConstructed":false,"scenarios":records]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            .write(to:directory.appendingPathComponent("render-summary.json"),options:.withoutOverwriting)
    }
}
