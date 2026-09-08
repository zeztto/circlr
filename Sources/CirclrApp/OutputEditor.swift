import SwiftUI
import CirclrCore

struct OutputEditor:View {
    @ObservedObject var store:AppStore
    let track:Track
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            if let address=store.hierarchySelection {
                LevelRow(store:store,target:.circle(address,original:store.editOriginal),title:"서클 레벨",
                    detail:circleDetail(address))
                Divider().overlay(StudioTheme.line)
            }
            TrackLevelEditor(store:store,track:track)
            if store.hierarchySelection != nil {
                HStack(spacing:10) {
                    Toggle("공유 원본 편집",isOn:$store.editOriginal).fixedSize()
                        .help("서클 레벨의 편집 범위를 이번 사용과 공유 원본 사이에서 전환합니다")
                    Spacer()
                    Button("볼륨 오토메이션"){openAutomation(.gain)}
                    Button("팬 오토메이션"){openAutomation(.pan)}
                    Button("트랙 바운스"){store.bounceTrack()}.disabled(store.preparing)
                        .help("출력 레벨과 오토메이션을 유지하며 앞의 오디오 경로를 바운스합니다")
                }
            }
        }.frame(maxWidth:720,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading)
    }
    func circleDetail(_ address:CircleAddress)->String {
        guard store.editOriginal else{return "이번 섹션 사용에만 적용합니다."}
        if let original=try? LevelEditing.snapshot(.circle(address,original:true),in:store.project),
           let effective=try? LevelEditing.snapshot(.circle(address,original:false),in:store.project),original != effective {
            return "공유 원본에 적용합니다. 이번 사용의 개별 레벨 설정은 유지됩니다."
        }
        return "같은 원본을 사용하는 섹션에 적용합니다. 개별 설정은 유지됩니다."
    }
    func openAutomation(_ parameter:AutomationParameter){store.connectionsOpen=false;store.automationParameter=parameter;store.showAutomation()}
}
struct TrackLevelEditor:View {
    @ObservedObject var store:AppStore
    let track:Track
    var body:some View {
        LevelRow(store:store,target:.track(track.id),title:"트랙 전체 레벨",detail:track.name+" · 이 트랙을 사용하는 모든 섹션에 적용합니다.")
            .frame(maxWidth:720,alignment:.leading)
    }
}
private struct LevelRow:View {
    @ObservedObject var store:AppStore
    let target:LevelTarget
    let title:String
    let detail:String
    var body:some View {
        if let value=try? LevelEditing.snapshot(target,in:store.project) {
            let projectID=store.project.id,generation=store.mediaImportGeneration,address=store.hierarchySelection
            GainControls(title:title,detail:detail,
                gain:Binding(get:{(try? LevelEditing.snapshot(target,in:store.project))?.gain ?? value.gain},set:{next in
                    guard current(projectID,generation,address) else{return}
                    store.mutate(title){try LevelEditing.set(target,gain:next,in:&$0)}
                }),
                muted:Binding(get:{(try? LevelEditing.snapshot(target,in:store.project))?.muted ?? value.muted},set:{next in
                    guard current(projectID,generation,address) else{return}
                    store.mutate(title+" 음소거"){try LevelEditing.set(target,muted:next,in:&$0)}
                }))
        }else {
            Text(store.editOriginal ? "이번 사용에 추가된 서클입니다. 공유 원본 편집을 끄고 조절하세요.":"레벨을 편집할 대상을 다시 선택하세요.")
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
        }
    }
    func current(_ project:ID,_ generation:Int,_ address:CircleAddress?)->Bool {
        guard store.project.id==project,store.mediaImportGeneration==generation,store.hierarchySelection==address else{return false}
        if case .circle(_,let original)=target{return original==store.editOriginal}
        if case .track(let id)=target{return id==store.selectedTrackID}
        return false
    }
}
