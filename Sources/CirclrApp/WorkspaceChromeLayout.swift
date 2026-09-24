import Foundation

/// Breakpoints are based on the controls' content budget, independently of window orientation.
struct WorkspaceChromeLayout {
    let width:CGFloat
    var twoHeaderRows:Bool {width<1280}
    var compactTransport:Bool {width<1500}
    var compactOverlays:Bool {width<1000}
    var inset:CGFloat {width<1000 ? 16:20}
    var headerHeight:CGFloat {twoHeaderRows ? 116:66}
}

/// Keeps canvas overlays within the window, clear of either header layout.
struct WorkspaceOverlayLayout {
    let viewport:CGSize
    let headerHeight:CGFloat
    private let margin:CGFloat=16
    var topInset:CGFloat {headerHeight+margin}
    var pickerSize:CGSize {
        CGSize(width:min(850,max(0,viewport.width-margin*2)),
               height:min(560,max(0,viewport.height-topInset-margin)))
    }
}
