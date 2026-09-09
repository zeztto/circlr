import AppKit
import SwiftUI
import CirclrCore

struct ArrangementPickerRequest:Identifiable {
    let id=UUID()
    let identity:NumberEditIdentity
    let compositionID:ID
    let destination:String
    let currentID:ID?
    let choices:[ArrangementChoice]
}

extension AppStore {
    var arrangementPickerOwner:Composition? {
        guard let id=selectedCompositionID,let owner=project.album?.composition(id),!owner.arrangementIDs.isEmpty else{return nil}
        return owner
    }
    func showArrangementPicker(compositionID:ID?=nil) {
        guard nameEditing.resolve(),let owner=arrangementPickerOwner,compositionID==nil || compositionID==owner.id else{return}
        do {
            let choices=try ArrangementSelection.catalog(project,compositionID:owner.id)
            soundPickerRequest=nil;libraryOpen=false;navigationOpen=false;commandPalette=nil;keyboardHelp=false
            arrangementPickerRequest=ArrangementPickerRequest(identity:numberEditIdentity,compositionID:owner.id,destination:owner.kind.label+" · "+owner.name,currentID:owner.selectedArrangementID,choices:choices)
        }catch{fail(error)}
    }
    func arrangementPickerCurrent(_ request:ArrangementPickerRequest)->Bool {
        arrangementPickerRequest?.id==request.id && request.identity==numberEditIdentity && arrangementPickerOwner?.id==request.compositionID && !preparing && !midiRecording && !audioRecordingBusy && !audioRecordPending && mediaImportTask==nil
    }
    func closeArrangementPicker(){arrangementPickerRequest=nil;focusCanvas?()}
    func editArrangementName(_ name:String,duplicate:Bool,request:ArrangementPickerRequest)throws {
        guard arrangementPickerCurrent(request),let source=request.currentID,
              request.choices.contains(where:{$0.id==source}) else{throw CirclrError("대상이나 음악이 바뀌었거나 다른 작업 중입니다. 닫은 뒤 다시 열어주세요.")}
        var candidate=project,created:ID?
        if duplicate {created=try ArrangementSelection.duplicate(source,compositionID:request.compositionID,name:name,in:&candidate)}
        else {_ = try ArrangementSelection.rename(source,compositionID:request.compositionID,name:name,in:&candidate)}
        mutate(duplicate ? "편곡안 복제":"편곡안 이름 변경",musical:duplicate) {$0=candidate}
        if duplicate {
            guard let created,project.album?.composition(request.compositionID)?.selectedArrangementID==created else{throw CirclrError("편곡안을 복제하지 못했습니다")}
            hierarchySettingsOpen=false;focusHierarchy(.composition(request.compositionID))
        }
        guard let owner=project.album?.composition(request.compositionID) else{throw CirclrError("대상 곡을 찾을 수 없습니다")}
        let choices=try ArrangementSelection.catalog(project,compositionID:owner.id)
        arrangementPickerRequest=ArrangementPickerRequest(identity:numberEditIdentity,compositionID:owner.id,destination:owner.kind.label+" · "+owner.name,currentID:owner.selectedArrangementID,choices:choices)
    }
    func applyArrangement(_ id:ID,request:ArrangementPickerRequest)throws {
        guard arrangementPickerCurrent(request),request.choices.contains(where:{$0.id==id}) else{throw CirclrError("대상이나 음악이 바뀌었거나 다른 작업 중입니다. 닫은 뒤 다시 열어주세요.")}
        if request.currentID==id {closeArrangementPicker();return}
        mutate("편곡안 선택") {try ArrangementSelection.select(id,compositionID:request.compositionID,in:&$0)}
        guard project.album?.composition(request.compositionID)?.selectedArrangementID==id else{throw CirclrError("편곡안을 적용하지 못했습니다")}
        closeArrangementPicker();hierarchySettingsOpen=false;focusHierarchy(.composition(request.compositionID))
    }
}

struct ArrangementPickerButton:View {
    @ObservedObject var store:AppStore
    let owner:Composition
    private var choice:ArrangementChoice? {(try? ArrangementSelection.catalog(store.project,compositionID:owner.id))?.first{$0.id==owner.selectedArrangementID}}
    var body:some View {
        Button{store.showArrangementPicker(compositionID:owner.id)}label:{
            HStack(spacing:12) {
                VStack(alignment:.leading,spacing:5) {
                    Text(choice?.title ?? "편곡안 선택").font(.system(size:14,weight:.medium)).lineLimit(2)
                    Text("편곡안 찾기 · ⌥⌘J").font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.accent)
            }.padding(12).contentShape(Rectangle()).background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:6))
        }.buttonStyle(.plain).frame(maxWidth:660).accessibilityLabel("편곡안 찾기 · "+(choice?.title ?? owner.name)).help(choice?.title ?? owner.name)
    }
}

struct ArrangementPickerView:View {
    @ObservedObject var store:AppStore
    let request:ArrangementPickerRequest
    @State private var query=""
    @State private var highlighted:ID?
    @State private var searchFocus=UUID()
    @State private var notice=""
    @State private var naming:Bool? // false: rename current arrangement, true: duplicate it
    @State private var draft=""
    private var currentChoice:ArrangementChoice? {request.choices.first{$0.id==request.currentID}}
    private var rows:[ArrangementChoice] {ArrangementSelection.search(request.choices,query:query)}
    private var active:ID? {rows.contains{$0.id==highlighted} ? highlighted:rows.first?.id}
    private var current:Bool {store.arrangementPickerCurrent(request)}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {Text("편곡안 찾기").font(.system(size:18,weight:.semibold));Spacer();Button(naming == nil ? "닫기 · Esc":"이름 입력 취소 · Esc"){cancel()}.foregroundStyle(StudioTheme.secondary)}.padding(18)
            Text(request.destination+" · 앨범 재생에 사용할 편곡안").font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                .lineLimit(2).fixedSize(horizontal:false,vertical:true).help(request.destination).padding(.horizontal,18).padding(.bottom,14)
            if naming == nil {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:Binding(get:{query},set:{query=$0;highlighted=nil}),onMove:move,onSubmit:applySelected,onCancel:cancel,placeholder:"편곡안 이름 또는 #번호 검색").id(searchFocus)
            }.padding(.horizontal,18).padding(.bottom,14)
            }
            HStack(alignment:.top,spacing:10) {
                Text("현재 · "+(request.choices.first{$0.id==request.currentID}?.title ?? "선택 없음")).lineLimit(2).fixedSize(horizontal:false,vertical:true)
                    .help(request.choices.first{$0.id==request.currentID}?.title ?? "선택 없음")
                Spacer(minLength:8)
                Button("현재 편곡 찾기"){query="";highlighted=request.currentID;searchFocus=UUID()}.disabled(naming != nil)
                Text("\(rows.count)개 결과").monospacedDigit().fixedSize()
            }.font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(.horizontal,18).padding(.bottom,14)
            if let duplicate=naming {
                VStack(alignment:.leading,spacing:8) {
                    Text((duplicate ? "복제 원본 · ":"이름 변경 대상 · ")+(currentChoice?.title ?? "선택 없음"))
                        .font(.system(size:12)).lineLimit(1).help(currentChoice?.title ?? "선택 없음")
                    HStack(spacing:10) {
                        ArrangementNameField(text:$draft,onSubmit:commitName,onCancel:cancel)
                            .frame(height:28).accessibilityLabel(duplicate ? "새 편곡안 이름":"현재 편곡안 이름")
                        Button("적용"){commitName()}.disabled(!current)
                        Button("취소"){cancel()}
                    }
                    if duplicate {Text("섹션 원본은 공유 · 이번 사용 편집은 별도").font(.system(size:12)).foregroundStyle(StudioTheme.secondary)}
                }.padding(.horizontal,18).padding(.bottom,14)
            }else{
                HStack(spacing:10) {
                    Button("이름 변경 · ⇧⌘N"){beginName(duplicate:false)}
                        .keyboardShortcut("n",modifiers:[.command,.shift])
                        .help("현재 편곡안 이름 변경 · ⇧⌘N")
                    Button("이름 정해 복제 · ⇧⌘D"){beginName(duplicate:true)}
                        .keyboardShortcut("d",modifiers:[.command,.shift])
                        .help("이름 정해 복제 · ⇧⌘D · 섹션 원본은 공유 · 이번 사용 편집은 별도")
                }.disabled(!current || currentChoice==nil).padding(.horizontal,18).padding(.bottom,14)
            }
            if !current || !notice.isEmpty {
                Text(!current ? "대상이나 음악이 바뀌었거나 다른 작업 중입니다. 닫은 뒤 다시 열어주세요.":notice)
                    .font(.system(size:12)).foregroundStyle(StudioTheme.accent).fixedSize(horizontal:false,vertical:true).padding(.horizontal,18).padding(.bottom,12)
            }
            ScrollViewReader {proxy in
                ScrollView {
                    if rows.isEmpty {Text("일치하는 편곡안이 없습니다. 이름이나 #번호를 바꿔보세요.").font(.system(size:13)).foregroundStyle(StudioTheme.secondary).padding(30)}
                    LazyVStack(spacing:1) {ForEach(rows){choice in row(choice)}}
                }.onChange(of:active){_,id in if let id {proxy.scrollTo(id,anchor:.center)}}
                    .onChange(of:query){_,_ in if let active{proxy.scrollTo(active,anchor:.center)}}
            }
            Text(naming == nil ? "↑↓ 선택 · Return 편곡 적용 · Esc 취소 · 같은 편곡은 현재 작업과 이력 유지\n⇧⌘N 이름 변경 · ⇧⌘D 이름 정해 복제":"Return 이름 적용 · Esc 이름 입력 취소 · 입력 중에는 편곡 전환이 잠깁니다")
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(18)
        }.frame(width:850,height:560).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(StudioTheme.line)).onAppear{highlighted=request.currentID}
            .onChange(of:request.id){_,_ in highlighted=request.currentID}
            .onExitCommand{cancel()}
    }
    private func move(_ delta:Int) {guard naming == nil,!rows.isEmpty else{return};let i=rows.firstIndex{$0.id==active} ?? 0;highlighted=rows[max(0,min(rows.count-1,i+delta))].id}
    private func row(_ choice:ArrangementChoice)->some View {
        let selected=choice.id==request.currentID
        let label=choice.title+" · "+choice.detail+(selected ? " · 재생 편곡":"")
        return Button{apply(choice.id)}label:{rowContent(choice,selected:selected)}
            .buttonStyle(.plain).disabled(!current || naming != nil).id(choice.id).help(choice.title+" · "+choice.detail)
            .accessibilityLabel(label).accessibilityAddTraits(active==choice.id ? .isSelected:[])
    }
    private func rowContent(_ choice:ArrangementChoice,selected:Bool)->some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:6) {
                Text(choice.title).font(.system(size:14,weight:.medium)).lineLimit(2)
                Text(choice.detail).font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading)
            if selected {Text("재생 편곡").font(.system(size:12)).foregroundStyle(StudioTheme.accent).fixedSize()}
        }.padding(.horizontal,18).padding(.vertical,12).contentShape(Rectangle()).background(active==choice.id ? StudioTheme.raised:Color.clear)
    }
    private func beginName(duplicate:Bool) {
        guard current,let choice=currentChoice else{return}
        notice="";draft=duplicate ? "":choice.name;naming=duplicate
    }
    private func cancel() {
        if naming != nil {naming=nil;draft="";notice="";searchFocus=UUID()}
        else {store.closeArrangementPicker()}
    }
    private func commitName() {
        guard let duplicate=naming else{return}
        do {
            try store.editArrangementName(draft,duplicate:duplicate,request:request)
            naming=nil;draft="";query="";notice="";searchFocus=UUID()
        }catch{notice=error.localizedDescription}
    }
    private func applySelected(){if let active{apply(active)}}
    private func apply(_ id:ID) {guard naming == nil,rows.contains(where:{$0.id==id}) else{return};do{try store.applyArrangement(id,request:request)}catch{notice=error.localizedDescription}}
}

private struct ArrangementNameField:NSViewRepresentable {
    @Binding var text:String
    let onSubmit:()->Void
    let onCancel:()->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSTextField {
        let field=NSTextField();field.placeholderString="편곡안 이름";field.font = .systemFont(ofSize:14)
        field.delegate=context.coordinator
        DispatchQueue.main.async{field.window?.makeFirstResponder(field)}
        return field
    }
    func updateNSView(_ field:NSTextField,context:Context) {
        context.coordinator.parent=self
        if field.stringValue != text {field.stringValue=text}
    }
    final class Coordinator:NSObject,NSTextFieldDelegate {
        var parent:ArrangementNameField
        init(_ parent:ArrangementNameField){self.parent=parent}
        func controlTextDidChange(_ notification:Notification) {
            if let field=notification.object as? NSTextField {parent.text=field.stringValue}
        }
        func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector)->Bool {
            if textView.hasMarkedText(){return false}
            if selector==#selector(NSResponder.insertNewline(_:)){parent.onSubmit();return true}
            if selector==#selector(NSResponder.cancelOperation(_:)){parent.onCancel();return true}
            return false
        }
    }
}
