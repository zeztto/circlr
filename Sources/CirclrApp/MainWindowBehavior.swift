import AppKit
import SwiftUI
import OSLog

let windowLifecycleLog=Logger(subsystem:"com.circlr.desktop",category:"WindowLifecycle")

/// Keep SwiftUI's window delegate for scene management, intercepting only close.
struct MainWindowBehavior:NSViewRepresentable {
    let onAttach:(NSWindow)->Void
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeNSView(context:Context)->WindowReferenceView {
        let view=WindowReferenceView()
        view.attach={ [weak coordinator=context.coordinator] window in
            coordinator?.attach(window);onAttach(window)
        }
        return view
    }
    func updateNSView(_ view:WindowReferenceView,context:Context) {
        if let window=view.window {context.coordinator.attach(window);onAttach(window)}
    }
    static func dismantleNSView(_ view:WindowReferenceView,coordinator:Coordinator) {
        view.attach=nil;coordinator.detach()
    }

    @MainActor final class Coordinator:NSObject,NSWindowDelegate {
        weak var window:NSWindow?
        var originalDelegate:NSWindowDelegate?
        func attach(_ target:NSWindow) {
            guard window !== target || target.delegate !== self else{return}
            detach();window=target;originalDelegate=target.delegate;target.delegate=self
        }
        func detach() {
            if window?.delegate === self {window?.delegate=originalDelegate}
            window=nil;originalDelegate=nil
        }
        func windowShouldClose(_ sender:NSWindow)->Bool {
            sender.miniaturize(nil)
            windowLifecycleLog.debug("Main close requested; starting minimization")
            return false
        }
        override func responds(to selector:Selector!)->Bool {
            super.responds(to:selector) || (originalDelegate?.responds(to:selector) ?? false)
        }
        override func forwardingTarget(for selector:Selector!)->Any? {
            if originalDelegate?.responds(to:selector)==true {return originalDelegate}
            return super.forwardingTarget(for:selector)
        }
    }
}

@MainActor final class WindowReferenceView:NSView {
    var attach:((NSWindow)->Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {attach?(window)}
    }
}
