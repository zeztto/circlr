import AppKit
import SwiftUI
import Combine
import CirclrCore

extension AppStore {
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
    @State private var subdivisions=4
    @State private var page=0
    @State private var drumMode=false
    @State private var extraPitches:Set<Int>=[]
    @State private var newPitch=36
    var grid:StepGrid? {try? StepGrid(subdivisions:subdivisions,beats:store.editorBeats)}
    var pitches:[Int] {
        if !drumMode {return (0..<12).map{max(0,min(127,topPitch-1-$0))}.reduce(into:[Int]()){if !$0.contains($1){$0.append($1)}}}
        let observed=Set((store.currentLane?.notes ?? []).map(\.pitch))
        let mapped=Set(store.selectedTrack?.instrument.sample?.zones?.map(\.pitch) ?? [])
        var result=observed.union(mapped).union(extraPitches)
        if result.isEmpty {result.insert(store.selectedTrack?.instrument.sample?.rootPitch ?? 36)}
        return result.sorted()
    }
    var body:some View {
        if let grid {
            VStack(spacing:8) {
                HStack(spacing:10) {
                    Picker("행",selection:$drumMode){Text("드럼").tag(true);Text("음정").tag(false)}.pickerStyle(.segmented).labelsHidden().frame(width:126)
                    Menu {ForEach(StepGrid.resolutions,id:\.self){value in Button(resolution(value)){subdivisions=value;page=0}}}label:{Text(resolution(subdivisions))}
                        .accessibilityLabel("스텝 분할").help("표시 격자만 바꿉니다. 기존 노트의 타이밍은 유지됩니다")
                    Spacer(minLength:4)
                    CountControl(title:"페이지",value:Binding(get:{min(page,grid.pageCount-1)+1},set:{page=$0-1}),range:1...grid.pageCount,suffix:"/ \(grid.pageCount)")
                    Menu("페이지") {
                        Button("다음 페이지로 복제") {editPage(grid,copy:true)}.disabled(page+1>=grid.pageCount)
                        Button("이 페이지 비우기") {editPage(grid,copy:false)}
                    }
                }
                if drumMode {
                    HStack {CountControl(title:"MIDI 음높이",value:$newPitch,range:0...127);Button("행 추가"){extraPitches.insert(newPitch)};Spacer();Text("각 행은 실제 악기의 MIDI 음높이입니다").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)}
                }
                ScrollView(.vertical) {
                    StepGridCanvas(store:store,grid:grid,page:min(page,grid.pageCount-1),pitches:pitches)
                        .frame(height:CGFloat(pitches.count*28+32))
                }.frame(minHeight:80,maxHeight:.infinity)
                Text("← ↑ ↓ → 셀 선택 · Return 켜기/끄기 · Delete 지우기 · 노트 선택 후 아래에서 길이·세기 편집")
                    .font(.system(size:11)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
            }
            .onAppear{drumMode=store.selectedTrack?.instrument.drums==true;newPitch=store.selectedTrack?.instrument.sample?.rootPitch ?? 36}
            .onChange(of:page){_,_ in store.selectedNoteID=nil}
            .onChange(of:store.editorBeats){_,_ in page=min(page,(self.grid?.pageCount ?? 1)-1)}
        } else {Text("스텝 편집은 131,072박 이하의 음악 서클에서 사용할 수 있습니다").foregroundStyle(StudioTheme.secondary)}
    }
    func resolution(_ value:Int)->String {[1:"1/4",2:"1/8",3:"1/8 셋잇단",4:"1/16",6:"1/16 셋잇단",8:"1/32"][value] ?? "1/16"}
    func editPage(_ grid:StepGrid,copy:Bool) {
        guard let lane=store.currentLane else{return}
        do {
            let next=copy ? try StepEditing.copyPage(lane,grid:grid,from:page,to:page+1):try StepEditing.clearPage(lane,grid:grid,page:page)
            store.setLane(next);store.selectedNoteID=nil
            if copy {page+=1}
        }catch{store.fail(error)}
    }
}

struct StepGridCanvas:NSViewRepresentable {
    @ObservedObject var store:AppStore
    let grid:StepGrid
    let page:Int
    let pitches:[Int]
    func makeNSView(context:Context)->StepGridView {StepGridView(store:store,grid:grid,page:page,pitches:pitches)}
    func updateNSView(_ view:StepGridView,context:Context) {
        view.grid=grid;view.page=page;view.pitches=pitches;view.row=min(view.row,max(0,pitches.count-1));view.column=min(view.column,max(0,view.columns-1));view.needsDisplay=true
    }
}
@MainActor final class StepGridView:NSView {
    let store:AppStore
    var grid:StepGrid
    var page:Int
    var pitches:[Int]
    var row=0,column=0
    var meterSubscription:AnyCancellable?
    var accessibilityKey=""
    var cellCacheKey=""
    var cellNotes:[Int:[Note]]=[:]
    var heldCells=Set<Int>()
    var columns:Int {min(16,max(0,grid.stepCount-page*16))}
    var cellWidth:Double {max(1,(bounds.width-116)/16)}
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    init(store:AppStore,grid:StepGrid,page:Int,pitches:[Int]) {
        self.store=store;self.grid=grid;self.page=page;self.pitches=pitches;super.init(frame:.zero)
        setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("스텝 편집기 · 방향키 선택 · Return 입력")
        meterSubscription=store.meter.$seconds.sink{[weak self] _ in DispatchQueue.main.async{self?.needsDisplay=true}}
    }
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async{[weak self] in
            guard let self,let window=self.window,!(window.firstResponder is NSTextView) else{return}
            window.makeFirstResponder(self)
        }
    }
    func rect(row:Int,column:Int)->CGRect {CGRect(x:112+Double(column)*cellWidth+2,y:28+Double(row)*28+2,width:max(1,cellWidth-4),height:24)}
    func label(_ pitch:Int)->String {
        if let instrument=store.selectedTrack?.instrument {
            if let zone=instrument.sample?.zones?.first(where:{$0.pitch==pitch}),let asset=store.project.assets.first(where:{$0.id==zone.assetID}) {return "\(pitch) · \(asset.name)"}
            if instrument.drums && instrument.kind == .soundBank,let name=[36:"킥",38:"스네어",39:"클랩",42:"닫힌 하이햇",46:"열린 하이햇",45:"톰",49:"크래시",51:"라이드"][pitch] {return "\(pitch) · \(name)"}
        }
        return "\(pitch) · \(Scale.roots[pitch%12])\(pitch/12-1)"
    }
    var playingStep:Int? {
        guard store.playback.playing,!store.hasPendingMusic,let plan=store.prepared?.plan,let node=store.selectedCircle,let clock=node.clock,
              let seconds=PlaybackPosition.localSeconds(for:node,at:store.meter.seconds,plan:plan,album:nil,albumID:store.project.album?.id) else{return nil}
        return Int(clock.beat(atSeconds:seconds)*Double(grid.subdivisions))
    }
    func refreshCells() {
        let key="\(store.project.id):\(store.project.musicRevision):\(store.selectedLaneID ?? store.editPatternID ?? ""):\(page):\(grid):\(pitches)"
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
            let index=page*16+col,r=rect(row:0,column:col)
            OrbitDrawing.text(String(index+1),at:CGPoint(x:r.midX,y:13),size:11,color:playing==index ? StudioTheme.accentNS:StudioTheme.secondaryNS)
            for row in pitches.indices {
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
        for (i,pitch) in pitches.enumerated() {(label(pitch) as NSString).draw(in:CGRect(x:4,y:34+i*28,width:102,height:20),withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.medium),.foregroundColor:StudioTheme.textNS,.paragraphStyle:paragraph])}
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
        window?.makeFirstResponder(self)
        let point=convert(event.locationInWindow,from:nil)
        guard point.x>=112,point.y>=28 else{return}
        let row=Int((point.y-28)/28),col=Int((point.x-112)/cellWidth)
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
        if window?.firstResponder===self,event.modifierFlags.contains(.command),store.handleMIDIBatchKey(event){needsDisplay=true;return true}
        return super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event:NSEvent) {
        if store.handleMIDIBatchKey(event){needsDisplay=true;return}
        guard !event.modifierFlags.contains(.command),!event.modifierFlags.contains(.control),!pitches.isEmpty else{super.keyDown(with:event);return}
        switch event.keyCode {
        case 123:choose(row:row,column:max(0,column-1))
        case 124:choose(row:row,column:min(columns-1,column+1))
        case 125:choose(row:min(pitches.count-1,row+1),column:column)
        case 126:choose(row:max(0,row-1),column:column)
        case 48:
            if event.modifierFlags.contains(.shift) {window?.selectPreviousKeyView(self)} else {window?.selectNextKeyView(self)}
        case 36,76:store.editStep(grid:grid,index:page*16+column,pitch:pitches[row]);needsDisplay=true
        case 51,117:
            if store.selectedMIDIIDs.count>1 {store.removeNote()}else{store.editStep(grid:grid,index:page*16+column,pitch:pitches[row],enabled:false)};needsDisplay=true
        case 49:store.play()
        default:super.keyDown(with:event)
        }
    }
    func updateAccessibility() {
        guard let window else{return}
        let key="\(cellCacheKey):\(convert(bounds,to:nil)):\(window.frame):\(row):\(column)"
        guard key != accessibilityKey else{return};accessibilityKey=key
        var children:[NSAccessibilityElement]=[]
        for (row,pitch) in pitches.enumerated() {for col in 0..<columns {
            let cell=StepCellAccessibility(parent:self,row:row,column:col)
            cell.setAccessibilityLabel(label(pitch)+" · \(page*16+col+1)스텝")
            cell.setAccessibilityValue(cellNotes[row*16+col]?.isEmpty==false ? "켜짐":"꺼짐")
            cell.setAccessibilityFrame(window.convertToScreen(convert(rect(row:row,column:col),to:nil)));children.append(cell)
        }}
        setAccessibilityChildren(children)
    }
}
@MainActor final class StepCellAccessibility:NSAccessibilityElement {
    weak var grid:StepGridView?
    let row:Int,column:Int
    init(parent:StepGridView,row:Int,column:Int) {self.grid=parent;self.row=row;self.column=column;super.init();setAccessibilityParent(parent);setAccessibilityRole(.button);setAccessibilityEnabled(true)}
    override func accessibilityPerformPress()->Bool {
        guard let grid,grid.pitches.indices.contains(row),(0..<grid.columns).contains(column) else{return false}
        grid.window?.makeFirstResponder(grid);grid.choose(row:row,column:column);grid.store.editStep(grid:grid.grid,index:grid.page*16+column,pitch:grid.pitches[row]);grid.needsDisplay=true;return true
    }
}
