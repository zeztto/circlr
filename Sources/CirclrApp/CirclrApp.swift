import SwiftUI
import AppKit
import OSLog

@main struct CirclrApplication:App {
    @StateObject private var store=AppStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var opened=false
    var body:some Scene {
        Window("써클러",id:"main") {
            RootView(store:store).tint(StudioTheme.accent).accentColor(StudioTheme.accent).preferredColorScheme(.dark)
                .background(MainWindowBehavior{delegate.mainWindow=$0}.frame(width:0,height:0))
                .onAppear{NSApplication.shared.appearance=NSAppearance(named:.darkAqua);delegate.store=store;guard !opened else{return};opened=true;NSApplication.shared.activate(ignoringOtherApps:true);if let i=CommandLine.arguments.firstIndex(of:"--open"),CommandLine.arguments.count>i+1{store.open(URL(fileURLWithPath:CommandLine.arguments[i+1]))}else{store.offerRecovery()}}
                .onOpenURL{store.open($0)}
        }.defaultSize(width:1440,height:900).windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing:.newItem){Button("새 앨범"){store.newProject()}.keyboardShortcut("n");Button("열기…"){store.open()}.keyboardShortcut("o");Divider();Button("창 닫기"){NSApplication.shared.keyWindow?.performClose(nil)}.keyboardShortcut("w")}
            CommandGroup(replacing:.saveItem){Button("저장"){store.save()}.keyboardShortcut("s");Button("다른 이름으로 저장…"){store.save(as:true)}.keyboardShortcut("s",modifiers:[.command,.shift]);Divider();Button("WAV 내보내기…"){store.export()}.keyboardShortcut("e")}
            CommandGroup(replacing:.undoRedo){Button("실행 취소"){store.undo()}.keyboardShortcut("z").disabled(store.undoCount==0);Button("다시 실행"){store.redo()}.keyboardShortcut("z",modifiers:[.command,.shift]).disabled(store.redoCount==0)}
            CommandMenu("곡 구성"){Button("섹션 추가"){store.addSection()}.keyboardShortcut("k");Button("다시 사용"){store.reuse()}.keyboardShortcut("d");Button("그룹 만들기"){store.makeHierarchyGroup()}.keyboardShortcut("g");Button("삭제"){store.removeHierarchy()};Divider();Button("재생 / 정지"){store.play()};Button("오디오 가져오기…"){store.importAudio()}.keyboardShortcut("i")}
        }
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    weak var store:AppStore?
    weak var mainWindow:NSWindow?
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {guard let store else{return .terminateNow};if !store.confirmDiscard(){return .terminateCancel};store.stop();return .terminateNow}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {
        guard let mainWindow else{return true}
        windowLifecycleLog.debug("Main reopen requested; minimized=\(mainWindow.isMiniaturized,privacy:.public)")
        if mainWindow.isMiniaturized {mainWindow.deminiaturize(nil)}
        mainWindow.makeKeyAndOrderFront(nil)
        return false
    }
}
