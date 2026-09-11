import SwiftUI
import CirclrCore

extension AppStore {
    func libraryTrackChoiceCurrent(_ request:MediaImportRequest,entryID:String)->Bool {
        libraryOpen && canStartMediaImport && libraryDestinationCurrent && libraryDestination==request
            && library.workspace == .track(request,entryID:entryID)
            && library.chosenIDs == [entryID] && library.chosen.first?.kind == .audio
    }
    func chooseLibraryTrack(_ trackID:ID?,request:MediaImportRequest,entryID:String) {
        guard libraryTrackChoiceCurrent(request,entryID:entryID) else{library.notice="파일이나 대상이 변경됐습니다. 파일 목록에서 다시 선택하세요";return}
        if changeLibraryPlacement(request,change:{try AudioImportPlacement.track(trackID,of:$0,in:project)}) {
            library.workspace = .files;library.searchFocus=UUID()
        }
    }
}

struct LibraryTrackChooser:View {
    @ObservedObject var store:AppStore
    @ObservedObject var library:MediaLibraryController
    let request:MediaImportRequest
    let entryID:String
    @State private var query=""
    @State private var highlighted=0
    private var choices:[AudioImportTrackChoice] {(try? AudioImportPlacement.tracks(for:request.destination,in:store.project,query:query)) ?? []}
    private var active:Int {min(highlighted,max(0,choices.count-1))}
    private var current:Bool {store.libraryTrackChoiceCurrent(request,entryID:entryID)}
    private var requestedTrack:ID? {if case .section(_,_,let id,_,_,_)=request.destination{return id};return nil}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:$query,onMove:move,onSubmit:chooseActive,onCancel:close,placeholder:"오디오 대상 트랙 이름 · 번호 검색")
            }.padding(.horizontal,18).padding(.bottom,14)
            HStack {
                Text("오디오 대상 트랙").font(.system(size:15,weight:.semibold))
                Spacer();Text("\(choices.count)개 결과").monospacedDigit().foregroundStyle(StudioTheme.secondary)
            }.padding(.horizontal,18).padding(.bottom,8)
            Text("시작 \(BeatPosition.text(AudioImportPlacement.beat(request.destination)))박 유지 · "+(library.selected?.name ?? "선택한 오디오"))
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(2).padding(.horizontal,18).padding(.bottom,12)
            if !current {
                Text("파일이나 대상이 변경됐습니다. 파일 목록에서 대상을 갱신하고 다시 선택하세요.")
                    .font(.system(size:12)).foregroundStyle(StudioTheme.accent).padding(.horizontal,18).padding(.bottom,12)
            } else if !library.notice.isEmpty {
                Text(library.notice).foregroundStyle(StudioTheme.accent).padding(.horizontal,18).padding(.bottom,12)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if choices.isEmpty {Text("일치하는 트랙이 없습니다").foregroundStyle(StudioTheme.secondary).padding(30)}
                    LazyVStack(spacing:1) {
                        ForEach(Array(choices.enumerated()),id:\.offset){index,choice in
                            Button{choose(choice.trackID)}label:{
                                HStack(spacing:12) {
                                    VStack(alignment:.leading,spacing:6) {
                                        Text(choice.name).font(.system(size:14,weight:.medium)).lineLimit(2)
                                        Text(choice.detail).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                    if choice.trackID==requestedTrack {Text("현재 대상").font(.system(size:12)).foregroundStyle(StudioTheme.accent)}
                                }.padding(.horizontal,18).padding(.vertical,12)
                                    .background(index==active ? StudioTheme.raised:Color.clear)
                            }.buttonStyle(.plain).id(index).disabled(!current)
                                .accessibilityLabel(choice.name+" · "+choice.detail).help(choice.name+" · "+choice.detail)
                                .accessibilityAddTraits(index==active ? .isSelected:[])
                        }
                    }
                }.onChange(of:active){_,index in proxy.scrollTo(index,anchor:.center)}
                    .onChange(of:query){_,_ in highlighted=0;proxy.scrollTo(0,anchor:.top)}
            }
            Divider().overlay(StudioTheme.line)
            Text("↑↓ 선택 · Return 트랙 지정 · Esc 파일 목록으로 복귀")
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(18)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .onAppear{highlighted=choices.firstIndex{$0.trackID==requestedTrack} ?? 0}
    }
    private func move(_ delta:Int) {highlighted=max(0,min(choices.count-1,active+delta))}
    private func chooseActive() {guard choices.indices.contains(active) else{return};choose(choices[active].trackID)}
    private func choose(_ id:ID?) {store.chooseLibraryTrack(id,request:request,entryID:entryID)}
    private func close() {library.workspace = .files;library.searchFocus=UUID()}
}
