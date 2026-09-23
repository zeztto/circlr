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
                .onOpenURL{opened=true;store.open($0)}
        }.defaultSize(width:1440,height:900).windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing:.appSettings){Button("출력 설정…"){store.showOutputPreferences()}.keyboardShortcut(",").disabled(store.viewingMode || store.startupOpen)}
            CommandGroup(replacing:.newItem){Group {Button("새 곡…"){store.showStartup()}.keyboardShortcut("n");Button("열기…"){store.open()}.keyboardShortcut("o");Button("데모곡 불러오기…"){store.openBundledDemo()}}.disabled(store.outputPreferencesOpen || store.viewingMode);Divider();Button("창 닫기"){NSApplication.shared.keyWindow?.performClose(nil)}.keyboardShortcut("w")}
            CommandGroup(replacing:.saveItem){Group {Button("저장"){store.save()}.keyboardShortcut("s");Button("다른 이름으로 저장…"){store.save(as:true)}.keyboardShortcut("s",modifiers:[.command,.shift]);Divider();Button("WAV 내보내기…"){store.export()}.keyboardShortcut("e")}.disabled(store.outputPreferencesOpen || store.viewingMode || store.startupOpen)}
            CommandGroup(replacing:.undoRedo){Group {Button("실행 취소"){store.undo()}.keyboardShortcut("z").disabled(store.undoCount==0);Button("다시 실행"){store.redo()}.keyboardShortcut("z",modifiers:[.command,.shift]).disabled(store.redoCount==0)}.disabled(store.outputPreferencesOpen || store.viewingMode || store.startupOpen)}
            CommandMenu("보기") {
                Button(store.viewingMode ? "감상 모드 종료":"텍스트 없는 감상 모드"){_ = store.setViewingMode(!store.viewingMode)}.keyboardShortcut("v",modifiers:[.command,.shift]).disabled(store.startupOpen)
                Button("영상 녹화 시작 / 마치기…"){store.toggleMovieRecording()}.keyboardShortcut("r",modifiers:[.command,.shift]).disabled(store.startupOpen)
                Group {
                Button("샘플 라이브러리…"){store.showMediaLibrary()}.keyboardShortcut("l",modifiers:[.command,.option])
                Button("녹음 테이크 찾기…"){store.showRecordedTakes()}.keyboardShortcut("t",modifiers:[.command,.option]).disabled(store.recordedTakeChoices.isEmpty || store.trackBounceRecoveryLocked || store.midiImportDraft != nil)
                Button("작업 이동…"){store.showNavigation()}.keyboardShortcut("j")
                Button("편곡안 찾기…"){store.showArrangementPicker()}.keyboardShortcut("j",modifiers:[.command,.option]).disabled(store.arrangementPickerOwner==nil)
                Button(store.canReturnFromSectionSettings ? "원래 편집으로 돌아가기":"현재 섹션 설정") {
                    if store.canReturnFromSectionSettings {store.returnFromSectionSettings()}
                    else {store.openCurrentSectionSettings()}
                }.keyboardShortcut(",",modifiers:[.command,.option])
                    .disabled(!store.canOpenCurrentSectionSettings && !store.canReturnFromSectionSettings)
                Button("이 트랙의 MIDI·오디오"){store.openTrackComponent(0)}.keyboardShortcut("1").disabled(store.currentStudioTrack==nil)
                Button("이 트랙의 음색"){store.openTrackComponent(1)}.keyboardShortcut("2").disabled(store.currentStudioTrack==nil)
                Button("오디오 녹음 시작 / 정지"){store.startAudioRecording()}.keyboardShortcut("r",modifiers:[.command,.option]).disabled(store.audioRecordingLocked || (!store.audioRecordingAvailable && !store.audioRecordingBusy))
                Button("MIDI 가져오기…"){store.chooseMIDIImport()}.keyboardShortcut("i",modifiers:[.command,.option]).disabled(!store.midiImportActionAvailable)
                Button("MIDI 저장…"){store.exportMIDI()}.keyboardShortcut("e",modifiers:[.command,.option]).disabled(!store.midiExportActionAvailable)
                Button("현재 트랙 바운스"){store.runCurrentTrackBounce(identity:store.numberEditIdentity)}.keyboardShortcut("b",modifiers:[.command,.option]).disabled(!store.midiTrackBounceActionAvailable)
                Button("MIDI 스텝 편집"){store.openStepEditor()}.keyboardShortcut("4").disabled(!store.canOpenStepEditor)
                Button("볼륨·팬 오토메이션"){store.showAutomation()}.keyboardShortcut("5").disabled(store.selectedMusic==nil)
                Button("커서에서 오디오 분할"){if store.audioCommandAvailable{store.splitAudio()}}.keyboardShortcut("t").disabled(!store.audioCommandAvailable)
                Button("이 트랙의 이펙트"){store.openTrackComponent(2)}.keyboardShortcut("3").disabled(store.currentStudioTrack==nil)
                Divider()
                Button("콘솔 로그 작게"){store.setConsoleLogHeight(40)}.keyboardShortcut("1",modifiers:[.command,.control]).disabled(!store.consoleOpen)
                Button("콘솔 로그 기본 높이"){store.setConsoleLogHeight(122)}.keyboardShortcut("2",modifiers:[.command,.control]).disabled(!store.consoleOpen)
                Button("콘솔 로그 크게"){store.setConsoleLogHeight(180)}.keyboardShortcut("3",modifiers:[.command,.control]).disabled(!store.consoleOpen)
                Divider()
                Button("명령 검색…"){store.showCommands()}.keyboardShortcut("p",modifiers:[.command,.shift])
                Button("키보드 사용법"){store.arrangementPickerRequest=nil;store.libraryOpen=false;store.commandPalette=nil;store.navigationOpen=false;store.keyboardHelp.toggle()}.keyboardShortcut("/")
                Button("캔버스로 포커스 이동"){store.arrangementPickerRequest=nil;store.libraryOpen=false;store.commandPalette=nil;store.navigationOpen=false;store.focusCanvas?()}.keyboardShortcut("0",modifiers:[.command,.option])
            }.disabled(store.outputPreferencesOpen || store.viewingMode || store.startupOpen)}
            CommandMenu("곡 구성"){Group {Button("섹션 추가"){store.addSection()}.keyboardShortcut("k");Button("선택 항목 복제"){store.duplicateFocusedContent()}.keyboardShortcut("d");Button("그룹 만들기"){store.makeHierarchyGroup()}.keyboardShortcut("g");Button("삭제"){store.removeHierarchy()};Divider();Button("재생 / 정지"){store.play()};Button("오디오 가져오기…"){store.importAudio()}.keyboardShortcut("i")}.disabled(store.outputPreferencesOpen || store.viewingMode || store.startupOpen)}
        }
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    weak var store:AppStore?
    weak var mainWindow:NSWindow?
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard let store else{return .terminateNow}
        guard store.hasRecoveryOwnership else{store.stopAgentBridgeForTermination();return .terminateNow}
        // NSAlert.runModal and terminateLater waits both pump the main loop.
        // Reject new MCP edits until termination completes or is cancelled.
        store.pauseAgentBridgeForTermination()
        if store.audioRecordingBusy || store.midiRecording {
            store.stop()
            Task{@MainActor in
                let deadline=ProcessInfo.processInfo.systemUptime+10
                while store.recorder.busy && ProcessInfo.processInfo.systemUptime<deadline {try? await Task.sleep(for:.milliseconds(40))}
                guard !store.recorder.busy else{store.status="녹음 장치가 응답하면 파일 마무리 후 다시 종료하세요";store.resumeAgentBridgeAfterCancelledTermination();sender.reply(toApplicationShouldTerminate:false);return}
                guard store.confirmDiscard() else{store.resumeAgentBridgeAfterCancelledTermination();sender.reply(toApplicationShouldTerminate:false);return}
                let approved=store.terminationDocumentSnapshot
                if let finalizing=store.movieFinalizing {await finalizing.value}
                guard store.terminationDocumentSnapshot == approved else{
                    store.status="종료 대기 중 곡이 변경되었습니다. 변경 내용을 확인한 뒤 다시 종료하세요"
                    store.resumeAgentBridgeAfterCancelledTermination()
                    sender.reply(toApplicationShouldTerminate:false)
                    return
                }
                store.clearSavedRecovery()
                store.stopAgentBridgeForTermination()
                sender.reply(toApplicationShouldTerminate:true)
            }
            return .terminateLater
        }
        if !store.confirmDiscard(){store.resumeAgentBridgeAfterCancelledTermination();return .terminateCancel};store.stop()
        if let finalizing=store.movieFinalizing {
            let approved=store.terminationDocumentSnapshot
            Task{@MainActor in
                await finalizing.value
                guard store.terminationDocumentSnapshot == approved else{
                    store.status="종료 대기 중 곡이 변경되었습니다. 변경 내용을 확인한 뒤 다시 종료하세요"
                    store.resumeAgentBridgeAfterCancelledTermination()
                    sender.reply(toApplicationShouldTerminate:false)
                    return
                }
                store.clearSavedRecovery()
                store.stopAgentBridgeForTermination()
                sender.reply(toApplicationShouldTerminate:true)
            }
            return .terminateLater
        }
        store.clearSavedRecovery()
        store.stopAgentBridgeForTermination()
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {
        guard let mainWindow else{return true}
        windowLifecycleLog.debug("Main reopen requested; minimized=\(mainWindow.isMiniaturized,privacy:.public)")
        if mainWindow.isMiniaturized {mainWindow.deminiaturize(nil)}
        mainWindow.makeKeyAndOrderFront(nil)
        return false
    }
}
