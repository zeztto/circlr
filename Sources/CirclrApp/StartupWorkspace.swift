import SwiftUI
import AppKit
import CirclrCore

@MainActor extension AppStore {
    func showStartup() {
        guard resolveActiveNumericDraft(),nameEditing.resolve() else{return}
        _ = setViewingMode(false)
        startupOpen=true
    }
    func closeStartup() {
        guard startupOpen else{return}
        if let input=NSApp.keyWindow?.firstResponder as? NSTextView,input.hasMarkedText(){return}
        cancelDemoLoading();startupOpen=false;focusCanvas?()
    }
    func createStarter(_ id:String,name:String?,context:MusicContext? = nil) {
        guard requireFinishedRecordingForDocumentAction() else{return}
        cancelDemoLoading()
        if let input=NSApp.keyWindow?.firstResponder as? NSTextView,input.hasMarkedText(){return}
        do {
            var fresh=try ProjectStarters.make(id:id,name:name)
            if id == "blank",let context {try ContextResolver.validate(context);fresh.global=context}
            try ProjectStore.validateStructure(fresh)
            _ = try ArrangementCompiler.compile(fresh)
            _ = try AlbumCompiler.compile(fresh)
            guard confirmDiscard(),requireFinishedRecordingForDocumentAction() else{return}
            retireDemoCopy();stop();project=fresh;projectURL=nil;mediaRoot=nil
            selectedTrackID=fresh.tracks.first?.id
            resetSession();dirty=true
            status="새 곡 준비 완료 · 섹션과 노트를 편집하세요"
        } catch {fail(error)}
    }
}

struct StartupWorkspace:View {
    @ObservedObject var store:AppStore
    @State private var name="새 곡"
    @State private var tempo="120"
    @State private var numerator=4
    @State private var denominator=4
    @State private var scaleRoot=0
    @State private var scaleMode="major"
    @State private var settingsError:String?
    @FocusState private var nameFocused:Bool
    @State private var demos:[BundledDemo.Entry]=[]
    @State private var demoError:String?
    var body:some View {
        ZStack {
            StudioTheme.canvas
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    Text("곡 만들기").font(.system(size:32,weight:.semibold))
                    Text("섹션으로 구성하고, 궤도 안에서 음악을 만드세요")
                        .font(.system(size:15)).foregroundStyle(StudioTheme.secondary)
                    VStack(alignment:.leading,spacing:12) {
                        Text("새 곡").font(.headline)
                        HStack {
                            TextField("곡 이름",text:$name).textFieldStyle(StudioFieldStyle()).focused($nameFocused)
                                .onSubmit{createBlank()}
                            Button("만들기"){createBlank()}
                                .keyboardShortcut(.defaultAction)
                        }
                        HStack(alignment:.top,spacing:16) {
                            VStack(alignment:.leading,spacing:6) {
                                Text("템포 · BPM").foregroundStyle(StudioTheme.secondary)
                                TextField("120",text:$tempo).textFieldStyle(StudioFieldStyle())
                                    .frame(width:86).accessibilityLabel("새 곡 템포 BPM")
                                    .onSubmit{createBlank()}
                            }
                            VStack(alignment:.leading,spacing:6) {
                                Text("박자").foregroundStyle(StudioTheme.secondary)
                                HStack(spacing:4) {
                                    Picker("박자 분자",selection:$numerator){ForEach(1...32,id:\.self){Text("\($0)").tag($0)}}
                                    Text("/")
                                    Picker("박자 분모",selection:$denominator){ForEach([1,2,4,8,16,32],id:\.self){Text("\($0)").tag($0)}}
                                }.labelsHidden().frame(width:150)
                            }
                            VStack(alignment:.leading,spacing:6) {
                                Text("스케일").foregroundStyle(StudioTheme.secondary)
                                HStack(spacing:6) {
                                    Picker("스케일 근음",selection:$scaleRoot){ForEach(Scale.roots.indices,id:\.self){Text(Scale.roots[$0]).tag($0)}}
                                    Picker("스케일 모드",selection:$scaleMode){ForEach(Scale.modes.map(\.0),id:\.self){Text($0).tag($0)}}
                                }.labelsHidden().frame(width:240)
                            }
                        }
                        if let settingsError {Text(settingsError).foregroundStyle(.red)}
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:10) {
                        Text("템플릿 불러오기").font(.headline)
                        ForEach(ProjectStarters.catalog.filter{$0.id != "blank"}) {entry in
                            Button{store.createStarter(entry.id,name:nil)}label:{
                                HStack {Text(entry.title).frame(width:100,alignment:.leading);VStack(alignment:.leading,spacing:3){Text(entry.detail);Text("4/4 · "+(entry.id == "electronic" ? "A minor":"C major")).font(.system(size:12))}.foregroundStyle(StudioTheme.secondary);Spacer();Image(systemName:"arrow.right")}
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:10) {
                        Text("데모곡 불러오기").font(.headline)
                        if store.demoLoading {
                            HStack(spacing:12) {
                                ProgressView().controlSize(.small)
                                Text("데모곡과 미디어를 읽고 있습니다")
                                Spacer()
                                Button("불러오기 취소"){store.cancelDemoLoading();store.status="데모 불러오기 취소"}
                                    .accessibilityLabel("데모 불러오기 취소")
                            }
                        }
                        if let error=store.demoLoadError {Text(error).foregroundStyle(.red).textSelection(.enabled)}
                        ForEach(demos) {entry in
                            Button{store.openBundledDemo(id:entry.id)}label:{
                                HStack {VStack(alignment:.leading,spacing:4){Text(entry.title);Text(entry.detail).font(.system(size:12)).foregroundStyle(StudioTheme.secondary)};Spacer();Image(systemName:"arrow.right")}
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                        if let demoError {
                            Text(demoError).foregroundStyle(.red).textSelection(.enabled)
                            Button("데모 목록 다시 읽기"){loadDemos()}
                        }
                    }
                    Divider()
                    HStack {
                        Button("프로젝트 열기…"){store.open()}
                        Spacer()
                        Button("현재 캔버스로 돌아가기"){store.closeStartup()}
                    }
                }.frame(maxWidth:660).padding(40).frame(maxWidth:.infinity)
            }
        }.foregroundStyle(StudioTheme.text).buttonStyle(CanvasButtonStyle())
            .onAppear{loadDemos();nameFocused=true}
    }
    private func createBlank() {
        if let input=NSApp.keyWindow?.firstResponder as? NSTextView,input.hasMarkedText(){return}
        guard let bpm=Double(tempo.trimmingCharacters(in:.whitespacesAndNewlines)),
              let mode=Scale.modes.first(where:{$0.0==scaleMode}) else {settingsError="템포를 숫자로 입력하세요";return}
        var context=MusicContext()
        context.tempo=bpm;context.meter=Meter(numerator,denominator)
        context.scale=Scale(root:scaleRoot,name:mode.0,intervals:mode.1)
        context.beatGrid=BeatGrid(subdivisions:4,accents:[numerator])
        do {try ContextResolver.validate(context);settingsError=nil;store.createStarter("blank",name:name,context:context)}
        catch {settingsError=error.localizedDescription}
    }
    private func loadDemos() {
        do {demos=try BundledDemo.catalog();demoError=nil}
        catch {demos=[];demoError="동봉 데모 목록을 읽지 못했습니다: "+error.localizedDescription}
    }
}
