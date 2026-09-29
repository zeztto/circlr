import AppKit

/// Project commands must not consume a field editor's composition or text history.
@MainActor enum NativeTextCommandBoundary {
    static func textView(in window:NSWindow?)->NSTextView? {window?.firstResponder as? NSTextView}
    static func consumeUndo(redo:Bool,in window:NSWindow?)->Bool {
        guard let text=textView(in:window) else{return false}
        // Let composition remain intact; never fall through to the song's history.
        guard !text.hasMarkedText() else{return true}
        if let manager=text.undoManager {
            if redo {if manager.canRedo {manager.redo()}}
            else if manager.canUndo {manager.undo()}
        }
        return true
    }
    static func takeConsoleCommand(_ draft:inout String,in window:NSWindow?)->String? {
        guard textView(in:window)?.hasMarkedText() != true else{return nil}
        let command=draft;draft="";return command
    }
}

@MainActor extension AppStore {
    var canUndoFocusedContent:Bool {NativeTextCommandBoundary.textView(in:NSApp.keyWindow) != nil || undoCount>0}
    var canRedoFocusedContent:Bool {NativeTextCommandBoundary.textView(in:NSApp.keyWindow) != nil || redoCount>0}
    func undoFocusedContent(redo:Bool=false,in window:NSWindow?=NSApp.keyWindow) {
        if NativeTextCommandBoundary.consumeUndo(redo:redo,in:window){return}
        if redo {self.redo()} else {undo()}
    }
}
