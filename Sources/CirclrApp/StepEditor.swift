import AppKit
import SwiftUI
import Combine
import CirclrCore

extension AppStore {
    var stepRowScope:String {"\(project.id):\(mediaImportGeneration):\(String(describing:hierarchySelection)):\(selectedLaneID ?? editPatternID ?? ""):\(editOriginal)"}
    func stepRows(extra:Set<Int>)->[StepRow] {
        StepRows.pitches(instrument:selectedTrack?.instrument,observed:(currentLane?.notes ?? []).map(\.pitch),extra:extra)
            .map{StepRow(pitch:$0,label:stepRowLabel($0))}
    }
    func stepRowLabel(_ pitch:Int)->String {
        if let instrument=selectedTrack?.instrument {
            if instrument.kind == .sampler,let zone=instrument.sample?.zones?.first(where:{$0.pitch==pitch}),let asset=project.assets.first(where:{$0.id==zone.assetID}) {return "\(pitch) · \(asset.name)"}
            if instrument.drums && instrument.kind == .soundBank,let name=StepRows.generalMIDIDrumNames[pitch] {return "\(pitch) · \(name)"}
        }
        return "\(pitch) · \(Scale.roots[pitch%12])\(pitch/12-1)"
    }
    func playingStep(in grid:StepGrid)->Int? {
        guard playback.playing,!hasPendingMusic,let plan=prepared?.plan,let node=selectedCircle,let clock=node.clock,
              let seconds=PlaybackPosition.localSeconds(for:node,at:meter.seconds,plan:plan,album:nil,albumID:project.album?.id) else{return nil}
        return Int(clock.beat(atSeconds:seconds)*Double(grid.subdivisions))
    }
    func openStepEditor() {
        midiStepMode=true
        if let music=selectedMusic,case .midi=music.content,let address=hierarchySelection {focusHierarchy(address,detail:true);return}
        if let route=currentStudioTrack,let destination=route.destinations.first(where:{$0.role=="MIDI" && $0.connected}) ?? route.destinations.first(where:{$0.role=="MIDI"}) {navigateStudio(destination.id,track:route.id)}
    }
    func editStep(grid:StepGrid,index:Int,pitch:Int,enabled:Bool?=nil) {
        guard let lane=currentLane else{return}
        do {
            let onsets=grid.onsets(in:lane,pitch:pitch,index:index)
            let next=try StepEditing.set(lane,grid:grid,index:index,pitch:pitch,enabled:enabled ?? onsets.isEmpty)
            if next != lane {setLane(next)}
            selectedBeat=grid.start(index)
            selectedNoteID=grid.onsets(in:next,pitch:pitch,index:index).first?.id
        }catch{fail(error)}
    }
}

struct StepEditor:View {
    @ObservedObject var store:AppStore
    let topPitch:Int
    @Binding var state:StepEditorState
    let focusTarget:MIDIEditorFocus
    @Binding var scroll:EditorScrollPosition
    @State private var rowRequest:StepRowRequest?
    var grid:StepGrid? {try? StepGrid(subdivisions:state.subdivisions,beats:store.editorBeats)}
    var selected:Note? {store.currentLane?.notes.first{$0.id==store.selectedNoteID}}
    var pitches:[Int] {
        if !state.drumMode {return (0..<12).map{max(0,min(127,topPitch-1-$0))}.reduce(into:[Int]()){if !$0.contains($1){$0.append($1)}}}
        return StepRows.filter(store.stepRows(extra:state.extraPitches),query:state.rowQuery).map(\.pitch)
    }
    var body:some View {
        if let grid {
            VStack(spacing:8) {
                MIDIWorkspaceToolbarLayout {
                    HStack(spacing:8) {
                    Picker("스텝 행",selection:$state.drumMode){Text("드럼").tag(true);Text("음정").tag(false)}.pickerStyle(.segmented).labelsHidden().frame(width:110)
                    Menu(resolution(state.subdivisions)) {ForEach(StepGrid.resolutions,id:\.self){value in Button(resolution(value)){state.subdivisions=value;state.page=0;reveal();focusTarget.focus()}}}
                        .fixedSize().accessibilityLabel("스텝 분할").help("표시 격자만 바꿉니다. 기존 노트의 타이밍은 유지됩니다")
                    }
                    HStack(spacing:8) {
                    if state.drumMode {
                        Text("\(pitches.count)/\(store.stepRows(extra:state.extraPitches).count)행").fixedSize().monospacedDigit().foregroundStyle(StudioTheme.secondary).font(.system(size:11))
                        CommittedNumberField(title:"드럼 행 MIDI 음높이",value:Binding(get:{Double(state.newPitch)},set:{state.newPitch=Int($0)}),range:0...127,integerOnly:true,width:48)
                        Button{state.rowQuery="";state.extraPitches.insert(state.newPitch);rowRequest=StepRowRequest(pitch:state.newPitch)}label:{Image(systemName:"plus")}.accessibilityLabel("드럼 행 추가")
                    }
                    }
                    HStack(spacing:8) {
                    Button{page(-1,grid:grid)}label:{Image(systemName:"chevron.left")}.accessibilityLabel("이전 스텝 페이지").disabled(state.page<=0)
                    CommittedNumberField(title:"스텝 페이지",value:Binding(get:{Double(min(state.page,grid.pageCount-1)+1)},set:{state.page=Int($0)-1;store.selectedNoteID=nil}),range:1...Double(grid.pageCount),integerOnly:true,width:48)
                    Text("/ \(grid.pageCount)").fixedSize().monospacedDigit().foregroundStyle(StudioTheme.secondary)
                    Button{page(1,grid:grid)}label:{Image(systemName:"chevron.right")}.accessibilityLabel("다음 스텝 페이지").disabled(state.page+1>=grid.pageCount)
                    Menu("페이지") {
                        Button("다음 페이지로 복제") {editPage(grid,copy:true)}.disabled(state.page+1>=grid.pageCount)
                        Button("이 페이지 비우기") {editPage(grid,copy:false)}
                    }.fixedSize()
                    }
                }
                VStack(spacing:0) {
                    StepColumnHeader(store:store,meter:store.meter,grid:grid,page:min(state.page,grid.pageCount-1))
                    ScrollView(.vertical) {
                        StepGridCanvas(store:store,grid:grid,page:min(state.page,grid.pageCount-1),pitches:pitches,focusTarget:focusTarget,rowRequest:rowRequest)
                            .frame(height:CGFloat(max(1,pitches.count)*28))
                            .rememberEditorScroll($scroll)
                    }
                    if pitches.isEmpty {Text("일치하는 드럼 행이 없습니다").foregroundStyle(StudioTheme.secondary).padding(.vertical,8)}
                }.frame(minHeight:100,maxHeight:.infinity)
            }
            .onChange(of:selected){_,_ in reveal()}
            .onChange(of:store.editorBeats){_,_ in state.page=min(state.page,(self.grid?.pageCount ?? 1)-1)}
            .onChange(of:store.stepRowScope){_,_ in rowRequest=nil}
        } else {Text("스텝 편집은 131,072박 이하의 음악 서클에서 사용할 수 있습니다").foregroundStyle(StudioTheme.secondary)}
    }
    func resolution(_ value:Int)->String {[1:"1/4",2:"1/8",3:"1/8 셋잇단",4:"1/16",6:"1/16 셋잇단",8:"1/32"][value] ?? "1/16"}
    func reveal(){if let selected,let grid,let index=grid.index(at:selected.beat){state.page=index/16}}
    func page(_ delta:Int,grid:StepGrid){state.page=max(0,min(grid.pageCount-1,state.page+delta));store.selectedNoteID=nil;focusTarget.focus()}
    func editPage(_ grid:StepGrid,copy:Bool) {
        guard let lane=store.currentLane else{return}
        do {
            let next=copy ? try StepEditing.copyPage(lane,grid:grid,from:state.page,to:state.page+1):try StepEditing.clearPage(lane,grid:grid,page:state.page)
            store.setLane(next);store.selectedNoteID=nil
            if copy {state.page+=1};focusTarget.focus()
        }catch{store.fail(error)}
    }
}

struct StepRowRequest:Equatable {let id=UUID();let pitch:Int}

struct StepColumnHeader:View {
    @ObservedObject var store:AppStore
    @ObservedObject var meter:TransportMeter
    let grid:StepGrid
    let page:Int
    var body:some View {
        GeometryReader { geometry in
            HStack(spacing:0) {
                Text("음높이").frame(width:112,alignment:.leading)
                ForEach(0..<16,id:\.self){column in
                    let index=page*16+column
                    Text(index<grid.stepCount ? String(index+1):"")
                        .foregroundStyle(store.playingStep(in:grid)==index ? StudioTheme.accent:StudioTheme.secondary)
                        .frame(width:max(1,(geometry.size.width-116)/16))
                }
            }.font(.system(size:11)).monospacedDigit().foregroundStyle(StudioTheme.secondary)
        }.frame(height:24).accessibilityElement(children:.ignore).accessibilityLabel("스텝 번호 \(page*16+1)–\(min(grid.stepCount,(page+1)*16))")
    }
}

struct StepGridCanvas:NSViewRepresentable {
    @ObservedObject var store:AppStore
    let grid:StepGrid
    let page:Int
    let pitches:[Int]
    let focusTarget:MIDIEditorFocus
    let rowRequest:StepRowRequest?
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context:Context)->StepGridView {
        let view=StepGridView(store:store,grid:grid,page:page,pitches:pitches)
        view.lastSelection=store.currentLane?.notes.first{$0.id==store.selectedNoteID}
        focusTarget.view=view;return view
    }
    func updateNSView(_ view:StepGridView,context:Context) {
        let note=store.currentLane?.notes.first{$0.id==store.selectedNoteID}
        let selectionChanged=view.lastSelection != note
        let changed=view.grid != grid || view.page != page || view.pitches != pitches || selectionChanged
        let cursorPitch=view.pitches.indices.contains(view.row) ? view.pitches[view.row]:nil
        view.grid=grid;view.page=page;view.pitches=pitches;view.allowsEditing=enabled
        view.row=cursorPitch.flatMap{pitches.firstIndex(of:$0)} ?? 0
        view.column=min(view.column,max(0,view.columns-1))
        if changed,let note,let index=grid.index(at:note.beat),index/16==page,let row=pitches.firstIndex(of:note.pitch) {
            view.row=row;view.column=index%16
        }
        if selectionChanged,!pitches.isEmpty {
            let identity=store.numberEditIdentity
            DispatchQueue.main.async{[weak view] in
                guard let view,view.window != nil,view.store.numberEditIdentity==identity,
                      view.grid==grid,view.page==page,view.pitches==pitches else{return}
                view.scrollToVisible(view.rect(row:view.row,column:view.column))
            }
        }
        view.lastSelection=note;view.needsDisplay=true
        if view.lastRowRequestID != rowRequest?.id {
            view.lastRowRequestID=rowRequest?.id
            if let rowRequest {
                let identity=store.numberEditIdentity
                DispatchQueue.main.async{[weak view] in
                    guard let view,let window=view.window,view.allowsEditing,
                          view.lastRowRequestID==rowRequest.id,view.store.numberEditIdentity==identity,
                          view.page==page,view.grid==grid,view.pitches==pitches,
                          let row=view.pitches.firstIndex(of:rowRequest.pitch) else{return}
                    view.choose(row:row,column:view.column);window.makeFirstResponder(view)
                }
            }
        }
    }
}
@MainActor final class StepGridView:NSView {
    let store:AppStore
    var grid:StepGrid
    var page:Int
    var pitches:[Int]
    var row=0,column=0
    var lastSelection:Note?
    var lastRowRequestID:UUID?
    var allowsEditing=true
    var meterSubscription:AnyCancellable?
    var accessibilityKey=""
    var accessibilityIdentity:NumberEditIdentity?
    var accessibilityCellsKey=""
    var accessibilityCells:[Int:StepCellAccessibility]=[:]
    var cellCacheKey=""
    var cellNotes:[Int:[Note]]=[:]
    var heldCells=Set<Int>()
    var columns:Int {min(16,max(0,grid.stepCount-page*16))}
    var cellWidth:Double {max(1,(bounds.width-116)/16)}
    var visibleRows:Range<Int> {
        let first=max(0,min(pitches.count,Int(floor(visibleRect.minY/28))))
        let end=max(first,min(pitches.count,Int(ceil(visibleRect.maxY/28))))
        return first..<end
    }
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    init(store:AppStore,grid:StepGrid,page:Int,pitches:[Int]) {
        self.store=store;self.grid=grid;self.page=page;self.pitches=pitches;super.init(frame:.zero)
        setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("스텝 편집기 · 방향키 선택 · Return 입력")
        setAccessibilityHelp("행 이름은 선택만 합니다. Home·End 첫·마지막 행, PageUp·PageDown 화면 단위 이동")
        meterSubscription=store.meter.$seconds.sink{[weak self] _ in DispatchQueue.main.async{self?.needsDisplay=true}}
    }
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async{[weak self] in
            guard let self,self.allowsEditing,let window=self.window,!(window.firstResponder is NSTextView) else{return}
            window.makeFirstResponder(self)
        }
    }
    func rect(row:Int,column:Int)->CGRect {CGRect(x:112+Double(column)*cellWidth+2,y:Double(row)*28+2,width:max(1,cellWidth-4),height:24)}
    func label(_ pitch:Int)->String {store.stepRowLabel(pitch)}
    var playingStep:Int? {
        store.playingStep(in:grid)
    }
    func refreshCells() {
        let key="\(store.project.id):\(store.mediaImportGeneration):\(store.project.musicRevision):\(String(describing:store.hierarchySelection)):\(store.editOriginal):\(store.selectedLaneID ?? store.editPatternID ?? ""):\(page):\(grid):\(pitches)"
        guard key != cellCacheKey else{return};cellCacheKey=key;cellNotes=[:];heldCells=[]
        let rows=Dictionary(uniqueKeysWithValues:pitches.enumerated().map{($0.element,$0.offset)})
        let start=grid.start(page*16),end=min(grid.beats,grid.start(page*16+columns))
        for note in store.currentLane?.notes ?? [] {
            guard let row=rows[note.pitch],note.beat<end,note.beat+note.length>start else{continue}
            for col in 0..<columns {
                let index=page*16+col,key=row*16+col,beat=grid.start(index)
                if grid.contains(note.beat,in:index) {cellNotes[key,default:[]].append(note)}
                else if note.beat<beat && note.beat+note.length>beat {heldCells.insert(key)}
            }
        }
    }
    override func draw(_ dirtyRect:NSRect) {
        StudioTheme.canvasNS.setFill();bounds.fill()
        refreshCells();let playing=playingStep,selectedIDs=store.selectedMIDIIDs
        for col in 0..<columns {
            let index=page*16+col
            for row in visibleRows {
                let rect=rect(row:row,column:col),onsets=cellNotes[row*16+col] ?? [],path=NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4)
                let focused=(self.row==row && self.column==col) || onsets.contains{selectedIDs.contains($0.id)}
                (onsets.isEmpty ? (index%grid.subdivisions==0 ? StudioTheme.raisedNS:StudioTheme.surfaceNS):StudioTheme.accentNS.withAlphaComponent(0.32)).setFill();path.fill()
                if let velocity=onsets.map(\.velocity).max() {
                    StudioTheme.accentNS.setFill();NSBezierPath(roundedRect:rect.insetBy(dx:4,dy:4).intersection(CGRect(x:rect.minX+4,y:rect.maxY-4-(rect.height-8)*Double(velocity)/127,width:rect.width-8,height:rect.height)),xRadius:2,yRadius:2).fill()
                } else if heldCells.contains(row*16+col) {
                    StudioTheme.accentNS.withAlphaComponent(0.3).setFill();CGRect(x:rect.minX+4,y:rect.midY-1,width:max(1,rect.width-8),height:2).fill()
                }
                if focused || playing==index {(focused ? StudioTheme.textNS:StudioTheme.accentNS).setStroke();path.lineWidth=focused ? 1.6:1;path.stroke()}
            }
        }
        let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingTail
        for i in visibleRows {(label(pitches[i]) as NSString).draw(in:CGRect(x:4,y:6+i*28,width:102,height:20),withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.medium),.foregroundColor:StudioTheme.textNS,.paragraphStyle:paragraph])}
        updateAccessibility()
    }
    func choose(row:Int,column:Int) {
        guard pitches.indices.contains(row),(0..<columns).contains(column) else{return}
        self.row=row;self.column=column
        store.selectedBeat=grid.start(page*16+column)
        store.selectedNoteID=store.currentLane.flatMap{grid.onsets(in:$0,pitch:pitches[row],index:page*16+column).first?.id}
        scrollToVisible(rect(row:row,column:column));needsDisplay=true
    }
    override func mouseDown(with event:NSEvent) {
        guard allowsEditing else{return}
        window?.makeFirstResponder(self)
        let point=convert(event.locationInWindow,from:nil)
        guard point.x>=0,point.y>=0 else{return}
        if point.x<112 {choose(row:Int(point.y/28),column:column);return}
        let row=Int(point.y/28),col=Int((point.x-112)/cellWidth)
        guard pitches.indices.contains(row),(0..<columns).contains(col) else{return}
        if event.modifierFlags.contains(.shift) {
            if let note=store.currentLane.flatMap({grid.onsets(in:$0,pitch:pitches[row],index:page*16+col).first}) {store.toggleMIDISelection(note.id)}
            needsDisplay=true;return
        }
        choose(row:row,column:col)
        if !event.modifierFlags.contains(.option) {store.editStep(grid:grid,index:page*16+col,pitch:pitches[row])}
        needsDisplay=true
    }
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        if allowsEditing,window?.firstResponder===self,event.modifierFlags.contains(.command),store.handleMIDIBatchKey(event){needsDisplay=true;return true}
        return super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event:NSEvent) {
        guard allowsEditing else{super.keyDown(with:event);return}
        if store.handleMIDIBatchKey(event){needsDisplay=true;return}
        guard !event.modifierFlags.contains(.command),!event.modifierFlags.contains(.control),!pitches.isEmpty else{super.keyDown(with:event);return}
        switch event.keyCode {
        case 123:choose(row:row,column:max(0,column-1))
        case 124:choose(row:row,column:min(columns-1,column+1))
        case 125:choose(row:min(pitches.count-1,row+1),column:column)
        case 126:choose(row:max(0,row-1),column:column)
        case 115:choose(row:0,column:column)
        case 119:choose(row:pitches.count-1,column:column)
        case 116:choose(row:max(0,row-max(1,visibleRows.count-1)),column:column)
        case 121:choose(row:min(pitches.count-1,row+max(1,visibleRows.count-1)),column:column)
        case 48:
            if event.modifierFlags.contains(.shift) {window?.selectPreviousKeyView(self)} else {window?.selectNextKeyView(self)}
        case 36,76:store.editStep(grid:grid,index:page*16+column,pitch:pitches[row]);needsDisplay=true
        case 51,117:
            if store.selectedMIDIIDs.count>1 {store.removeNote()}else{store.editStep(grid:grid,index:page*16+column,pitch:pitches[row],enabled:false)};needsDisplay=true
        case 49:store.play()
        case 53:store.focusCanvas?();store.hierarchyParent()
        default:super.keyDown(with:event)
        }
    }
    func updateAccessibility() {
        guard let window else{return}
        let key="\(cellCacheKey):\(convert(bounds,to:nil)):\(window.frame):\(visibleRect):\(row):\(column):\(allowsEditing)"
        let identity=store.numberEditIdentity
        guard key != accessibilityKey || identity != accessibilityIdentity else{return}
        if cellCacheKey != accessibilityCellsKey || identity != accessibilityIdentity {
            accessibilityCells=[:];accessibilityCellsKey=cellCacheKey
        }
        accessibilityKey=key;accessibilityIdentity=identity
        setAccessibilityValue(pitches.indices.contains(row) ? "\(label(pitches[row])) · \(page*16+column+1)스텝 · \(pitches.count)행":"일치하는 드럼 행이 없습니다")
        var children:[NSAccessibilityElement]=[]
        for row in visibleRows {
            let pitch=pitches[row],header=accessibilityCell(row:row,column:nil)
            header.setAccessibilityLabel(label(pitch)+" · 행 선택")
            header.setFrameInView(CGRect(x:0,y:row*28,width:112,height:28),view:self);children.append(header)
            for col in 0..<columns {
                let cell=accessibilityCell(row:row,column:col)
                cell.setAccessibilityLabel(label(pitch)+" · \(page*16+col+1)스텝")
                cell.setAccessibilityValue(cellNotes[row*16+col]?.isEmpty==false ? "켜짐":heldCells.contains(row*16+col) ? "이전 스텝에서 이어짐":"꺼짐")
                cell.setFrameInView(rect(row:row,column:col),view:self);children.append(cell)
            }
        }
        setAccessibilityChildren(children)
    }
    func accessibilityCell(row:Int,column:Int?)->StepCellAccessibility {
        let key=row*17+(column.map{$0+1} ?? 0)
        let cell=accessibilityCells[key] ?? StepCellAccessibility(parent:self,row:row,column:column)
        cell.setAccessibilityEnabled(allowsEditing);accessibilityCells[key]=cell
        return cell
    }
}
@MainActor final class StepCellAccessibility:NSAccessibilityElement {
    weak var grid:StepGridView?
    let row:Int,column:Int?,pitch:Int,page:Int,stepGrid:StepGrid,identity:NumberEditIdentity
    init(parent:StepGridView,row:Int,column:Int?) {
        self.grid=parent;self.row=row;self.column=column;pitch=parent.pitches[row]
        page=parent.page;stepGrid=parent.grid;identity=parent.store.numberEditIdentity
        super.init();setAccessibilityParent(parent);setAccessibilityRole(.button);setAccessibilityEnabled(parent.allowsEditing)
    }
    override func accessibilityPerformPress()->Bool {
        guard let grid,grid.window != nil,grid.allowsEditing,grid.store.numberEditIdentity==identity,
              grid.page==page,grid.grid==stepGrid,grid.pitches.indices.contains(row),grid.pitches[row]==pitch,
              grid.visibleRows.contains(row),(0..<grid.columns).contains(column ?? grid.column) else{return false}
        grid.window?.makeFirstResponder(grid);grid.choose(row:row,column:column ?? grid.column)
        if let column {grid.store.editStep(grid:stepGrid,index:page*16+column,pitch:pitch)}
        grid.needsDisplay=true;return true
    }
}
