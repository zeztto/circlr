import SwiftUI
import CirclrCore

/// Timing and processing are visible together inside the current canvas workspace.
struct TransitionWorkspace:View {
    @ObservedObject var store:AppStore
    let edgeID:ID
    let projectID:ID
    let arrangementID:ID
    init(store:AppStore,edgeID:ID) {
        self.store=store;self.edgeID=edgeID;projectID=store.project.id;arrangementID=store.project.activeArrangementID
    }
    var edge:FlowEdge? {store.project.active.edges.first{$0.id==edgeID}}
    var isCurrent:Bool {store.project.id==projectID && store.project.activeArrangementID==arrangementID && store.edgeSelection==edgeID}
    func use(_ id:ID)->SectionUse? {store.project.active.uses.first{$0.id==id}}
    func clock(_ id:ID) throws -> MusicClock {
        guard let use=use(id) else {throw CirclrError("전환의 앞·뒤 섹션을 확인하세요")}
        return try ArrangementCompiler.context(project:store.project,use:use,arrangementID:arrangementID).2
    }
    func binding<T>(_ key:WritableKeyPath<CirclrCore.Transition,T>,fallback:T)->Binding<T> {
        Binding(get:{edge?.transition[keyPath:key] ?? fallback},set:{value in
            guard isCurrent else{return};store.updateEdge{$0.transition[keyPath:key]=value}
        })
    }
    func timing(_ edge:FlowEdge)->Result<TransitionTiming,Error> {
        Result {try TransitionTiming(edge.transition,source:clock(edge.from),target:clock(edge.to))}
    }
    func maximum(_ edge:FlowEdge)->Double {
        switch edge.transition.anchor {
        case .seconds:return 3600
        case .sourceBars:return Double((try? clock(edge.from).meters.count) ?? 4096)
        case .targetBars:return Double((try? clock(edge.to).meters.count) ?? 4096)
        }
    }
    var body:some View {
        if let edge {
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:12) {
                    endpoint(edge.from,label:"앞 섹션")
                    Image(systemName:"arrow.right").foregroundStyle(StudioTheme.secondary)
                    endpoint(edge.to,label:"뒤 섹션")
                    Spacer(minLength:8)
                }
                HStack(alignment:.top,spacing:24) {
                    ScrollView {
                        VStack(alignment:.leading,spacing:12) {
                            StudioChoice("방식",selection:binding(\.mode,fallback:edge.transition.mode),options:[(.within,"끝부분 안에서"),(.insert,"사이에 삽입"),(.overlap,"겹치기")])
                            StudioChoice("길이 기준",selection:binding(\.anchor,fallback:edge.transition.anchor),options:[(.sourceBars,"앞 섹션 마디"),(.targetBars,"뒤 섹션 마디"),(.seconds,"초")])
                            HStack {
                                Text("길이");Spacer()
                                let unit=edge.transition.anchor == .seconds ? "초":"마디"
                                CommittedNumberField(title:"전환 길이 · "+unit,value:binding(\.length,fallback:edge.transition.length),range:0...maximum(edge),width:100,presentation:edge.transition.anchor == .seconds ? .sourceSeconds:.number)
                                Text(unit).foregroundStyle(StudioTheme.secondary).frame(width:30,alignment:.leading)
                            }
                            timingSummary(edge)
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,6)
                    }.frame(width:300)
                    ScrollView {
                        VStack(alignment:.leading,spacing:12) {
                            StudioChoice("전환 리듬",selection:Binding(get:{self.edge?.transition.patternID ?? ""},set:{value in
                                guard isCurrent else{return};store.updateEdge{$0.transition.patternID=value.isEmpty ? nil:value}
                            }),options:[("","없음")]+store.project.patterns.map{($0.id,$0.name)})
                            if edge.transition.mode == .within {
                                StudioChoice("비울 트랙",selection:Binding(get:{self.edge?.transition.replaceTrackID ?? ""},set:{value in
                                    guard isCurrent else{return};store.updateEdge{$0.transition.replaceTrackID=value.isEmpty ? nil:value}
                                }),options:[("","원래 트랙 유지")]+store.project.tracks.map{($0.id,$0.name)})
                            }
                            if edge.transition.mode == .within && edge.transition.replaceTrackID == nil || edge.transition.mode == .insert && edge.transition.patternID != nil {
                                Text(edge.transition.mode == .within ? "앞 섹션 끝부분에 적용":"삽입하는 리듬에 적용").font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                                EffectControls(effect:binding(\.effect,fallback:edge.transition.effect),isCurrent:{isCurrent})
                            } else {
                                Text(edge.transition.mode == .within ? "선택 트랙의 전환 구간을 비웁니다. 리듬은 지정된 트랙으로 합칩니다.":
                                     edge.transition.mode == .insert ? "리듬이 없는 빈 구간을 삽입합니다.":"앞·뒤 섹션을 자동 페이드로 겹칩니다. 선택한 리듬도 함께 합칩니다.")
                                    .font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                            }
                            Button("연결 삭제",role:.destructive){if isCurrent{store.removeSelection()}}
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,6)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }.frame(maxHeight:.infinity)
            }.task(id:edgeID) {
                await Task.yield()
                if !Task.isCancelled && isCurrent {store.focusCanvas?()}
            }
        }
    }
    func endpoint(_ id:ID,label:String)->some View {
        let endpoint=CirclePortEndpoint(node:.section(arrangementID:arrangementID,useID:id),portID:CirclePort.flowInput)
        let choice=ConnectionTargetSearch.choice(endpoint,name:use(id)?.name ?? "섹션 없음",port:label,in:store.project)
        return Button {
            guard isCurrent else{return}
            store.hierarchyTransitionID=nil;store.hierarchySettingsOpen=false
            store.focusHierarchy(.section(arrangementID:arrangementID,useID:id),detail:false)
        } label: {Text(choice.title).lineLimit(2)}
            .accessibilityLabel(label+" · "+choice.title).help(choice.title+" · "+choice.detail+" · 섹션으로 이동")
    }
    @ViewBuilder func timingSummary(_ edge:FlowEdge)->some View {
        switch timing(edge) {
        case .success(let timing):
            VStack(alignment:.leading,spacing:5) {
                Text("전환 "+timing.duration.formatted(.number.precision(.fractionLength(3)))+"초").monospacedDigit()
                Text(edge.transition.mode == .within ? "뒤 섹션은 앞 섹션이 끝나면 시작합니다":
                     edge.transition.mode == .insert ? "뒤 섹션이 \(timing.duration.formatted(.number.precision(.fractionLength(3))))초 늦게 시작합니다":
                     "뒤 섹션이 \(timing.duration.formatted(.number.precision(.fractionLength(3))))초 먼저 시작합니다")
                if edge.transition.mode == .overlap {Text("앞 섹션 페이드 아웃 · 뒤 섹션 페이드 인")}
                Text("앞 섹션의 마지막 반복 → 뒤 섹션의 첫 반복")
                if edge.transition.length == 0 {Text("길이가 0이면 전환 효과와 리듬을 재생하지 않습니다")}
            }.font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
        case .failure(let error):Text("전환 재생 불가 · "+error.localizedDescription).font(.system(size:12)).foregroundStyle(Color.red)
        }
    }
}
