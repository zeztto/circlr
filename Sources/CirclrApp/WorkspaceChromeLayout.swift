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
