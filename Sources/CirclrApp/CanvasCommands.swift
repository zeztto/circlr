import AppKit
import SwiftUI
import CirclrCore

struct StudioCommand: Identifiable {
    let id: String
    let title: String
    var detail = ""
    var shortcut = ""
    let run: () -> Void
}
struct StudioPalette: Identifiable {
    let id = UUID()
    let commands: [StudioCommand]
}

extension AppStore {
    func openCircleSettings() {
        guard let address=hierarchySelection else{return}
        connectionsOpen=false
        hierarchyTransitionID=nil;focusHierarchy(address,detail:true);hierarchySettingsOpen=true
    }
    func showCommands() {
        libraryOpen=false
        navigationOpen=false
        var commands=canvasCommands?() ?? []
        func add(_ id:String,_ title:String,_ shortcut:String="",_ run:@escaping()->Void) {
            commands.append(StudioCommand(id:id,title:title,shortcut:shortcut,run:run))
        }
        add("new","새 앨범","⌘N"){[weak self] in self?.newProject()}
        add("open","프로젝트 열기…","⌘O"){[weak self] in self?.open()}
        add("save","프로젝트 저장","⌘S"){[weak self] in self?.save()}
        add("save-as","다른 이름으로 저장…","⇧⌘S"){[weak self] in self?.save(as:true)}
        add("play","재생 / 정지","Space"){[weak self] in self?.play()}
        add("stop","모든 재생·렌더 정지"){[weak self] in self?.stop()}
        if canEditCirclePorts { add("ports", "서클 연결 편집", "L") { [weak self] in self?.showConnections() } }
        if selectedUse != nil { add("router", "오디오 라우터 서클 만들기") { [weak self] in self?.addMusicRouter() } }
        add("movie","영상 녹화 시작 / 마치기…","⇧⌘R"){[weak self] in self?.toggleMovieRecording()}
        add("wav","앨범 WAV 내보내기…","⌘E"){[weak self] in self?.export()}
        add("stems","트랙별 stems 내보내기…"){[weak self] in self?.export(stems:true)}
        if undoCount>0 {add("undo","실행 취소","⌘Z"){[weak self] in self?.undo()}}
        if redoCount>0 {add("redo","다시 실행","⇧⌘Z"){[weak self] in self?.redo()}}
        add("media-library","샘플 라이브러리 검색·미리 듣기","⌥⌘L"){[weak self] in self?.showMediaLibrary()}
        add("global","글로벌 템포·박자·스케일 설정"){[weak self] in self?.focusHierarchy(.album,detail:true);self?.hierarchySettingsOpen=true}
        add("settings","선택 서클 이름·음악 설정","R"){[weak self] in self?.openCircleSettings()}
        add("navigation","섹션·트랙으로 바로 이동","⌘J"){[weak self] in self?.showNavigation()}
        add("parent","상위 서클로 이동","Esc"){[weak self] in self?.hierarchyParent()}
        add("fit","전체 앨범 보기","F"){[weak self] in self?.hierarchyCommand=HierarchyCommand(action:.fit)}
        add("follow","재생 팔로우 켜기 / 끄기"){[weak self] in guard let self else{return};self.playbackFollow=self.playbackFollow.toggled()}
        add("console","콘솔 접기 / 펼치기","⌃`"){[weak self] in self?.consoleOpen.toggle()}
        add("layout","궤도 / 자유 배치 전환"){[weak self] in guard let self else{return};self.setCanvasViewPreferences(layout:self.project.usesOrbits ? .freeform:.orbit)}
        add("grid","그리드 켜기 / 끄기"){[weak self] in guard let self else{return};self.setCanvasViewPreferences(grid:!(self.project.album?.layout.grid ?? true))}
        add("snap","그리드 스냅 켜기 / 끄기"){[weak self] in guard let self else{return};self.setCanvasViewPreferences(snap:!(self.project.album?.layout.snap ?? true))}
        if let movie=lastMovieURL {add("reveal-movie","저장한 영상 Finder에서 보기"){NSWorkspace.shared.activateFileViewerSelecting([movie])}}
        if hierarchySelections.count>=2 {
            add("group","선택한 서클로 그룹 만들기","⌘G"){[weak self] in self?.makeHierarchyGroup()}
            if !project.usesOrbits {
                for (mode,name) in ["가로 정렬","세로 정렬","동일 간격"].enumerated() {add("align-\(mode)",name){[weak self] in self?.alignHierarchy(mode)}}
            }
        }
        if selectedUse != nil {
            if selectedMusic != nil {add("automation","볼륨·팬 오토메이션","⌘5"){[weak self] in self?.showAutomation()}}
            if currentAudioClip != nil {
                add("audio-split","커서에서 오디오 분할","⌘T"){[weak self] in self?.splitAudio()}
                add("audio-duplicate","오디오 구간 뒤에 복제","⌘D"){[weak self] in self?.duplicateAudio()}
                add("audio-delete","선택 오디오 삭제"){[weak self] in self?.applyAudioEdit(.delete,label:"오디오 삭제")}
            }
            add("reuse","섹션 다시 사용","⌘D"){[weak self] in self?.reuse()}
            add("detach","공유 원본에서 독립 섹션으로 분리"){[weak self] in self?.detach()}
            add("section-play","선택 섹션만 재생"){[weak self] in self?.play(onlySelection:true)}
            add("midi-import","MIDI 파일 가져오기…","⌥⌘I"){[weak self] in self?.chooseMIDIImport()}
            add("record-midi","MIDI 녹음 시작 / 정지"){[weak self] in self?.startMIDIRecording()}
            add("record-audio","오디오 녹음 시작 / 정지","⌥⌘R"){[weak self] in self?.startAudioRecording()}
            add("rhythm","이 섹션의 리듬 패턴 만들기"){[weak self] in self?.makeHierarchyPattern()}
            if selectedTrackID != nil {
                add("bounce","선택 트랙을 오디오로 바운스"){[weak self] in self?.bounceTrack()}
                add("midi-export","선택 MIDI 파일 저장…"){[weak self] in self?.exportMIDI()}
                for pattern in MIDIPattern.allCases {add("pattern-\(pattern.rawValue)","MIDI 패턴 생성 · \(pattern.label)"){[weak self] in self?.generateMIDI(pattern)}}
            }
        }
        for node in hierarchyScene?.nodes ?? [] {
            commands.append(StudioCommand(id:"find-\(node.id)",title:node.title,detail:(hierarchyScene?.path(to:node.id).dropLast().map(\.title).joined(separator:" › ") ?? "")+" · \(node.subtitle)",run:{[weak self] in self?.focusHierarchy(node.id,detail:node.role == .music)}))
        }
        add("keyboard-help","키보드 사용법","⌘/"){[weak self] in self?.keyboardHelp=true}
        keyboardHelp=false;commandPalette=StudioPalette(commands:commands)
    }
    func performCommand(_ command:StudioCommand) {
        commandPalette=nil;focusCanvas?();command.run()
    }
}

extension AlbumCanvasView {
    func creationScope(at point:NSPoint, selected:CircleAddress?=nil)->CircleAddress {
        let address=selected ?? hit(point)?.id ?? store.hierarchySelection ?? .album
        switch address {
        case .music(let a,let u,_): return .section(arrangementID:a,useID:u)
        case .signal: return .sound
        case .group(let parent,_): return parent
        default: return address
        }
    }
    func localCreationPoint(_ point:NSPoint, owner:CircleAddress)->Point {
        guard let parent=scene?.node(owner) else{return Point()}
        let world=Point((point.x-camera.pan.x)/camera.zoom,(point.y-camera.pan.y)/camera.zoom)
        let scale=parent.scale*HierarchySceneBuilder.childScale
        var local=Point((world.x-parent.center.x)/scale,(world.y-parent.center.y)/scale)
        if store.project.album?.layout.snap != false {
            let spacing=store.project.album?.layout.spacing ?? 24
            local=Point((local.x/spacing).rounded()*spacing,(local.y/spacing).rounded()*spacing)
        }
        return local
    }
    func creationMenu(at point:NSPoint, selected:CircleAddress?=nil)->NSMenu {
        let menu=NSMenu(),scope=creationScope(at:point,selected:selected),position=localCreationPoint(point,owner:scope)
        func add(_ title:String,to target:NSMenu?=nil,owner:CircleAddress?=nil,_ action:@escaping(AppStore,Point)->Void) {
            let item=NSMenuItem(title:title,action:#selector(runCircleMenu(_:)),keyEquivalent:"")
            item.target=self
            item.representedObject=CircleMenuAction{[weak self] in
                guard let self else{return}
                let owner=owner ?? scope
                self.store.selectHierarchy(owner);self.store.hierarchySettingsOpen=false
                action(self.store,owner==scope ? position:self.localCreationPoint(point,owner:owner))
            }
            (target ?? menu).addItem(item)
        }
        switch scope {
        case .album:
            add("곡 서클 만들기"){ $0.addComposition(.song,at:$1) }
        case .composition(let id):
            if store.project.album?.composition(id)?.children.isEmpty != false {
                add("섹션 서클 만들기"){ $0.addSection(at:$1) }
            }
            add("악장 서클 만들기"){ $0.addComposition(.movement,at:$1) }
            add("곡 서클 만들기",owner:.album){ $0.addComposition(.song,at:$1) }
        case .section:
            add("MIDI 서클 만들기"){ $0.addMIDICircle(at:$1) }
            add("오디오 라우터 서클 만들기"){ $0.addMusicRouter(at:$1) }
            add("오디오 파일로 서클 만들기…"){ store,point in
                if store.selectedTrackID==nil {store.selectedTrackID=store.project.tracks.first?.id}
                store.importAudio(at:point)
            }
            let item=NSMenuItem(title:"이펙터 서클 만들기",action:nil,keyEquivalent:""),child=NSMenu()
            item.submenu=child;menu.addItem(item)
            for kind in EffectKind.allCases {add(AppStore.effectName(kind),to:child){$0.addMusicEffect(kind,at:$1)}}
        case .sound:
            add("버스 서클 만들기"){ $0.addHierarchyBus(at:$1) }
            for kind in EffectKind.allCases {add("전역 \(AppStore.effectName(kind))",to:menu){$0.addHierarchySignalEffect(kind,at:$1)}}
        default: break
        }
        if menu.items.isEmpty {add("곡 서클 만들기",owner:.album){$0.addComposition(.song,at:$1)}}
        return menu
    }
    func availableCommands()->[StudioCommand] {
        let point=NSPoint(x:bounds.midX,y:bounds.midY)
        let menu=circleMenu(at:point,selected:store.selectedCircle)
        func flatten(_ menu:NSMenu,prefix:String="",path:String="context")->[StudioCommand] {
            menu.items.enumerated().flatMap { index,item -> [StudioCommand] in
                let identity=path+"-\(index)"
                let title=prefix+item.title
                if let child=item.submenu {return flatten(child,prefix:title+" · ",path:identity)}
                guard let action=item.representedObject as? CircleMenuAction else{return []}
                return [StudioCommand(id:identity,title:title,run:action.run)]
            }
        }
        return flatten(menu)+[
            StudioCommand(id:"next-cable",title:"다음 케이블 선택",shortcut:"K",run:{[weak self] in self?.selectNeighborCable(forward:true)}),
            StudioCommand(id:"previous-cable",title:"이전 케이블 선택",shortcut:"⇧K",run:{[weak self] in self?.selectNeighborCable(forward:false)}),
            StudioCommand(id:"next-port",title:"다음 IN/OUT 포트 선택",shortcut:"P",run:{[weak self] in self?.selectNeighborPort(forward:true)})
        ]
    }
    func selectNeighbor(forward:Bool,additive:Bool=false) {
        guard let scene else{return}
        let current=store.selectedCircle
        var candidates=scene.nodes.filter{$0.parent==current?.parent && $0.id != .album}
        if current?.id == .album || candidates.isEmpty {candidates=scene.nodes.filter{$0.parent==current?.id}}
        guard !candidates.isEmpty else{return}
        clearCableSelection()
        let index=candidates.firstIndex(where:{$0.id==current?.id}) ?? (forward ? -1:0)
        let next=candidates[(index+(forward ? 1:-1)+candidates.count)%candidates.count]
        interruptPlaybackFollow();store.selectHierarchy(next.id,additive:additive);needsDisplay=true
        if !bounds.contains(screen(next)) {focus(next.id)}
        NSAccessibility.post(element:self,notification:.selectedChildrenChanged)
    }
    func enterSelectedCircle() {
        guard let address=store.hierarchySelection else{return}
        if let child=scene?.nodes.first(where:{$0.parent==address}),store.selectedMusic==nil,!store.hierarchySettingsOpen {
            store.selectHierarchy(child.id);focus(child.id,detail:child.role == .music)
        }else {focus(address,detail:true)}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.32){[weak self] in
            guard let self,let editor=self.editor else{return}
            func target(_ view:NSView)->NSView? {
                if view is StepGridView || view is OrbitMIDIView || view is OrbitAudioView || view is PianoRollView || view is AudioLaneView {return view}
                for child in view.subviews {if let result=target(child){return result}}
                return nil
            }
            if let view=target(editor){self.window?.makeFirstResponder(view)}
        }
    }
}

struct StudioCommandPalette:View {
    @ObservedObject var store:AppStore
    let palette:StudioPalette
    @State private var query=""
    @State private var selection=0
    private var results:[StudioCommand] {
        let terms=query.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        return palette.commands.filter{command in terms.allSatisfy{(command.title+" "+command.detail).localizedCaseInsensitiveContains($0)}}
    }
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:$query,onMove:{delta in selection=max(0,min(results.count-1,selection+delta))},onSubmit:execute,onCancel:{store.commandPalette=nil;store.focusCanvas?()})
                Text("Esc").font(.system(size:10,design:.monospaced)).foregroundStyle(StudioTheme.secondary)
            }.padding(17)
            Divider().overlay(StudioTheme.line)
            if results.isEmpty {Text("일치하는 명령이 없습니다").foregroundStyle(StudioTheme.secondary).padding(30)}
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing:2) {
                        ForEach(Array(results.enumerated()),id:\.element.id) { index,command in
                            Button{store.performCommand(command)}label:{
                                HStack {
                                    VStack(alignment:.leading,spacing:3) {Text(command.title);if !command.detail.isEmpty {Text(command.detail).font(.system(size:10)).foregroundStyle(StudioTheme.secondary)}}
                                    Spacer();Text(command.shortcut).font(.system(size:10,design:.monospaced)).foregroundStyle(StudioTheme.secondary)
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,10)
                                    .background(index==selection ? StudioTheme.raised:Color.clear,in:RoundedRectangle(cornerRadius:5))
                            }.buttonStyle(.plain).id(command.id).accessibilityAddTraits(index==selection ? .isSelected:[])
                        }
                    }.padding(7)
                }.frame(maxHeight:360)
                .onChange(of:selection){_,value in if results.indices.contains(value){proxy.scrollTo(results[value].id,anchor:.center)}}
                .onChange(of:query){_,_ in if let first=results.first{proxy.scrollTo(first.id,anchor:.top)}}
            }
            Divider().overlay(StudioTheme.line)
            HStack{Text("↑ ↓ 선택 · Return 실행");Spacer();Text("\(results.count)개 명령")}.font(.system(size:10)).foregroundStyle(StudioTheme.secondary).padding(12)
        }
        .frame(width:560).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(StudioTheme.line))
        .shadow(color:.black.opacity(0.3),radius:20,y:10)
        .onChange(of:query){_,_ in selection=0}
    }
    private func execute() {guard results.indices.contains(selection) else{return};store.performCommand(results[selection])}
}
struct CommandSearchField:NSViewRepresentable {
    @Binding var text:String
    let onMove:(Int)->Void
    let onSubmit:()->Void
    let onCancel:()->Void
    var placeholder="명령 또는 서클 이름 검색"
    var onExtend:((Int)->Void)?
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSSearchField {
        let field=NSSearchField();field.placeholderString=placeholder;field.isBordered=false;field.focusRingType = .none
        field.font = .systemFont(ofSize:15);field.delegate=context.coordinator
        DispatchQueue.main.async{field.window?.makeFirstResponder(field)}
        return field
    }
    func updateNSView(_ field:NSSearchField,context:Context){context.coordinator.parent=self;if field.stringValue != text {field.stringValue=text}}
    final class Coordinator:NSObject,NSSearchFieldDelegate {
        var parent:CommandSearchField
        init(_ parent:CommandSearchField){self.parent=parent}
        func controlTextDidChange(_ notification:Notification){if let field=notification.object as? NSSearchField {parent.text=field.stringValue}}
        func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector)->Bool {
            if textView.hasMarkedText(){return false}
            if selector==#selector(NSResponder.moveDownAndModifySelection(_:)),let extend=parent.onExtend{extend(1);return true}
            if selector==#selector(NSResponder.moveUpAndModifySelection(_:)),let extend=parent.onExtend{extend(-1);return true}
            if selector==#selector(NSResponder.moveDown(_:)){parent.onMove(1);return true}
            if selector==#selector(NSResponder.moveUp(_:)){parent.onMove(-1);return true}
            if selector==#selector(NSResponder.insertNewline(_:)){parent.onSubmit();return true}
            if selector==#selector(NSResponder.cancelOperation(_:)){parent.onCancel();return true}
            return false
        }
    }
}

struct KeyboardHelpView:View {
    @ObservedObject var store:AppStore
    private let rows:[(String,String)] = [
        ("⌥⌘L","로컬 샘플 라이브러리"),("⌘4","MIDI 스텝 편집"),("⌘J","섹션·트랙 바로 이동"),("⌘1 / ⌘2 / ⌘3","같은 트랙의 MIDI·오디오 / 음색 / 이펙터"),("⇧⌘P","명령·서클 검색"),("⌥⌘0","캔버스로 포커스 이동"),("A / C","서클 생성 / 선택 서클 메뉴"),("L","IN/OUT·대상·8방향 연결 편집"),
        ("Tab · ← → ↑ ↓","다음·이전 서클 선택"),("⇧ 방향키","여러 서클 선택"),("Return / Esc","서클 안으로 / 상위 서클"),
        ("K / ⇧K · P / ⇧P","다음·이전 케이블 · IN/OUT 포트 선택"),
        ("케이블 · Tab / ← →","OUT·IN 끝점 선택 / 둘레 8방향 위치 이동"),
        ("케이블 · ↑ ↓ / Return","다른 케이블 선택 / 선택 케이블 바로 편집"),
        ("포트 · Tab / Return","다음 포트 선택 / 해당 포트로 연결 편집"),
        ("케이블 · Delete / Esc","선택 케이블 해제 / 선택 취소"),
        ("R","이름·음악 설정"),("+ − / F","확대·축소 / 전체 앨범"),("⌥ 방향키","화면 이동"),
        ("⇧⌥ 방향키","자유 배치에서 선택 서클 이동"),
        ("Space","재생·정지"),("⇧⌘R","영상 녹화 시작·마치기"),("⌘K / ⌘D / ⌘G","섹션 추가 / 재사용 / 그룹"),("Delete","선택 서클·노트 삭제"),
        ("⌘N O S / ⇧⌘S","새 앨범·열기·저장 / 다른 이름으로 저장"),("⌘Z / ⇧⌘Z","실행 취소 / 다시 실행"),
        ("⌘I / ⌘E","오디오 가져오기 / WAV 내보내기"),("파일 드롭","섹션 위에 오디오 여러 개 또는 MIDI 한 개 놓기"),("⌃`","콘솔 접기·펼치기"),
        ("MIDI · ⌘A / ⇧클릭","노트 전체 선택 / 선택 추가·제외"),("MIDI · Q / ⌘D","선택 퀀타이즈 / 선택 구간 뒤 복제"),("⌥⌘I","MIDI 파일 가져오기"),
        ("MIDI · ⌥P / ⌥T","같은 음높이 / 같은 시작 박 선택"),("MIDI · ⌥I / ⇧⌘A","선택 반전 / 전체 해제"),
        ("MIDI · Tab / Return","노트 선택 / 현재 위치에 노트 입력"),("MIDI · ← → / ↑ ↓","격자 단위 시간 이동 / 반음 이동"),
        ("MIDI · ⇧← → / ⇧↑ ↓","노트 길이 변경 / 옥타브 이동"),("MIDI · ⌥↑ ↓","세기 5단계 변경"),
        ("오디오 · ← → / ⌥← →","원본 시작 / 끝 0.01초 조절 · ⇧ 0.1초"),("설정 · Tab / ⇧Tab","다음·이전 입력 항목 · Return 적용"),
        ("오디오 · ⌘T / ⌘D","커서에서 분할 / 구간 뒤에 복제"),("오디오 · Delete","선택 오디오 삭제"),
        ("오디오 · 휠 / ⇧휠","파형 확대·축소 / 원본 시간 이동"),("오디오 · − + / Page ↑↓","확대·축소 / 반 화면 이동 · Home/End 처음/끝"),
        ("오디오 · 0 / F / C","전체 파일 / 선택 구간 / 분할 커서 보기"),
        ("MIDI · 선택 노트 드래그","선택 전체 이동 · 끝 손잡이로 공통 길이 조절"),
        ("⌥⌘R","오디오 녹음 / 정지 · 연결 중 시작 취소"),("⌘5 / 오토메이션 · Return","볼륨·팬 곡선 열기 / 점 추가"),("오토메이션 · [ ] / 방향키","이전·다음 점 / 시간·값 이동"),
        ("⌘W / ⌘Q","최소화 / 앱 종료")
    ]
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack{Text("키보드로 작업하기").font(.system(size:18,weight:.semibold));Spacer();Button("닫기"){store.keyboardHelp=false;store.focusCanvas?()}.keyboardShortcut(.escape,modifiers:[])}
            Text("텍스트 입력 중에는 캔버스 문자 핫키를 실행하지 않습니다").foregroundStyle(StudioTheme.secondary)
            ScrollView {VStack(spacing:0){ForEach(rows.indices,id:\.self){i in HStack{Text(rows[i].0).font(.system(size:11,design:.monospaced)).frame(width:190,alignment:.leading);Text(rows[i].1).frame(maxWidth:.infinity,alignment:.leading)}.padding(.vertical,8);Divider().overlay(StudioTheme.line)}}}.frame(maxHeight:480)
        }.padding(22).frame(width:650).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(StudioTheme.line))
    }
}
