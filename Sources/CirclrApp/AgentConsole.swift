import SwiftUI
import CirclrCore
import CirclrAudio

struct AgentConsoleBoundsKey:PreferenceKey {
    static var defaultValue=CGRect.zero
    static func reduce(value:inout CGRect,nextValue:()->CGRect){let next=nextValue();if next.width>0{value=next}}
}

struct AgentConsole:View {
    @ObservedObject var store:AppStore
    @State private var command=""
    @State private var resizeStart:Double?
    @FocusState private var inputFocused:Bool
    private var connectionStatus:String {
        if store.agentSocket != nil {
            return store.agentBridgeDefaultSelected ? "MCP 연결 가능 · 기본 선택":"MCP 연결 가능 · 기본 미선택"
        }
        if store.agentBridgeNeedsManualRecovery {return "기존 연결 감지"}
        return store.agentBridgeLastFailure == nil ? "연결 없음":"연결 실패"
    }
    private var connectionDetail:String {
        if store.agentSocket != nil {
            let endpoint=store.agentBridgeEndpointName
            let selection=store.agentBridgeDefaultSelected ? "기본 연결로 선택됨":"소켓은 열렸지만 기본 연결로 선택되지 않음"
            return endpoint.isEmpty ? "로컬 MCP 소켓 열림 · \(selection)":"로컬 MCP 소켓 열림 · \(endpoint) · \(selection)"
        }
        return store.agentBridgeLastFailure ?? "로컬 MCP 연결을 준비하고 있습니다"
    }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:8) {
                Button{withAnimation(.easeOut(duration:0.18)){store.consoleOpen.toggle()}}label:{Image(systemName:"terminal");Text("콘솔");Image(systemName:store.consoleOpen ? "chevron.down":"chevron.up").font(.system(size:9))}
                    .keyboardShortcut("`",modifiers:.control).help("콘솔 접기·펼치기 · Ctrl `")
                Circle().fill(store.agentSocket != nil && store.agentBridgeDefaultSelected ? StudioTheme.accent:StudioTheme.secondary).frame(width:5,height:5)
                Text(connectionStatus).font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85).help(connectionDetail)
                    .accessibilityLabel("에이전트 연결 상태 · \(connectionStatus)")
                    .accessibilityValue(connectionDetail)
                if store.consoleOpen {
                    Menu("로그 높이") {
                        Button("작게 · 40pt"){store.setConsoleLogHeight(40)}
                        Button("기본 · 122pt"){store.setConsoleLogHeight(122)}
                        Button("크게 · 180pt"){store.setConsoleLogHeight(180)}
                    }.fixedSize().menuStyle(.borderlessButton)
                        .font(.system(size:11))
                        .help("로그 높이 · 작게 ⌃⌘1 · 기본 ⌃⌘2 · 크게 ⌃⌘3 · 상단 손잡이를 위아래로 드래그")
                        .accessibilityValue("현재 \(Int(store.consoleLogHeight))포인트")
                }
                Spacer()
                if let job=store.agentJob,job.state=="running" {
                    if job.kind=="bounce" {
                        Text(job.tail.map{String(format:"바운스 · 여운 %.1f초",$0.effectiveSeconds)} ?? "바운스 여운 계산 중")
                            .font(.system(size:11)).lineLimit(1).help(job.message)
                        ProgressView().controlSize(.small)
                        Button(store.isCurrentTrustedAgentJob(job.id) ? "AI 중단":"취소") {
                            try? store.cancelConsoleAgentJob(job.id)
                        }.accessibilityLabel(store.isCurrentTrustedAgentJob(job.id) ? "AI 작업 중단":"바운스 취소")
                            .help(store.isCurrentTrustedAgentJob(job.id) ? "AI 권한을 철회하고 작업을 취소합니다":"이 바운스 작업만 취소합니다")
                    }else{
                        Text(job.kind).font(.system(size:11,design:.monospaced))
                        ProgressView(value:job.progress).frame(width:65)
                        Button(store.isCurrentTrustedAgentJob(job.id) ? "AI 중단":"취소") {
                            try? store.cancelConsoleAgentJob(job.id)
                        }.accessibilityLabel(store.isCurrentTrustedAgentJob(job.id) ? "AI 작업 중단":"\(job.kind) 작업 취소")
                            .help(store.isCurrentTrustedAgentJob(job.id) ? "AI 권한을 철회하고 작업을 취소합니다":"이 작업만 취소합니다")
                    }
                } else if let job=store.agentJob,job.state=="completed" {
                    if let tail=job.tail {
                        Text((job.kind=="export" ? "WAV 완료 · ":"")+String(format:"여운 %.1f초",tail.effectiveSeconds)+(job.endWindowHasSignal == true ? " · 끝 신호 남음 · 여운 확인":""))
                            .font(.system(size:11)).lineLimit(1)
                            .help(([job.message]+tail.notices).joined(separator:" · "))
                            .accessibilityLabel(String(format:"완료 · 여운 %.1f초 · ",tail.effectiveSeconds)+job.message)
                    }
                    if let id=job.nodeID,let node=store.hierarchyScene?.nodes.first(where:{$0.music?.id==id}) {
                        Button("바운스 서클 보기"){_=store.focusUserWorkspace(node.id,detail:true,explicitIntent:.content)}
                    }
                }
                Text("r\(store.project.musicRevision)").font(.system(size:11,design:.monospaced)).foregroundStyle(StudioTheme.secondary).padding(.trailing,12)
            }.frame(height:34)
            if !store.status.isEmpty {
                HStack(alignment:.top,spacing:8) {
                    Image(systemName:store.agentJob?.state == "failed" ? "exclamationmark.circle":"info.circle")
                        .foregroundStyle(StudioTheme.secondary)
                    Text(store.status).font(.system(size:12)).foregroundStyle(StudioTheme.text)
                        .lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                        .help(store.status).accessibilityLabel("작업 상태 · "+store.status)
                }.padding(.horizontal,12).padding(.bottom,8)
            }
            if store.consoleOpen {
                if store.agentBridgeNeedsManualRecovery && store.agentSocket == nil {
                    HStack(spacing:8) {
                        Text("기존 연결 경로는 유지됩니다").font(.system(size:11))
                            .foregroundStyle(StudioTheme.secondary).lineLimit(1)
                        Spacer(minLength:4)
                        Button("이 앱에 새 연결"){store.recoverAgentBridgeWithNewEndpoint()}
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(store.agentBridgeShuttingDown)
                            .help("기존 연결을 건드리지 않고 이 앱의 새 로컬 MCP 연결 경로를 만듭니다. 새 경로는 연결 상태 도움말에서 확인할 수 있습니다.")
                            .accessibilityLabel("이 앱에 새 MCP 연결 만들기")
                            .accessibilityHint("기존 연결 경로를 유지하고 새 연결 경로를 사용합니다")
                    }.padding(.horizontal,12).padding(.bottom,8)
                }
                if store.agentSocket != nil && !store.agentBridgeDefaultSelected {
                    HStack(spacing:8) {
                        Text("이 앱의 MCP 소켓은 열려 있습니다").font(.system(size:11))
                            .foregroundStyle(StudioTheme.secondary).lineLimit(1)
                        Spacer(minLength:4)
                        Button("이 앱을 기본 연결로 선택"){store.selectAgentBridgeAsDefault()}
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(store.agentBridgeShuttingDown)
                            .help("기존 소켓은 건드리지 않고, 현재 이 앱의 열린 MCP 소켓을 기본 연결로 가리키는 선택 정보만 다시 게시합니다.")
                            .accessibilityLabel("이 앱의 MCP 소켓을 기본 연결로 선택")
                            .accessibilityHint("기존 소켓을 유지하고 기본 연결 선택 정보만 다시 게시합니다")
                    }.padding(.horizontal,12).padding(.bottom,8)
                }
                Rectangle().fill(StudioTheme.line).frame(height:1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:5) {
                            ForEach(store.activity.suffix(100)) {event in
                                HStack(alignment:.top,spacing:10) {
                                    Text(event.time.formatted(.dateTime.hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits))).foregroundStyle(StudioTheme.secondary).frame(width:67,alignment:.leading).lineLimit(1)
                                    Text(event.source).foregroundStyle(event.source=="에이전트" ? StudioTheme.accent:StudioTheme.secondary).frame(width:48,alignment:.leading)
                                    Text(event.message).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                                }.font(.system(size:11,design:.monospaced)).id(event.id)
                            }
                        }.padding(.horizontal,14).padding(.vertical,10)
                    }.frame(height:store.consoleLogHeight)
                        .onAppear{DispatchQueue.main.async{if let id=store.activity.last?.id{proxy.scrollTo(id,anchor:.bottom)}}}
                        .onChange(of:store.activitySequence){ if let id=store.activity.last?.id{proxy.scrollTo(id,anchor:.bottom)}}
                }
                HStack(spacing:8) {
                    Text(">").foregroundStyle(StudioTheme.accent)
                    TextField("help · state · midi arpeggio · bounce · stop",text:$command)
                        .textFieldStyle(.plain).font(.system(size:12,design:.monospaced)).focused($inputFocused)
                        .onSubmit{let text=command;command="";store.consoleCommand(text)}
                    Button{let text=command;command="";store.consoleCommand(text)}label:{Image(systemName:"arrow.turn.down.left")}.help("명령 실행")
                }.padding(.horizontal,14).padding(.vertical,5).background(StudioTheme.raised.opacity(0.7))
            }
        }
        .frame(maxWidth:820).background(StudioTheme.canvas.opacity(0.97),in:RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(StudioTheme.line))
        .overlay(alignment:.top) {
            if store.consoleOpen {
                Capsule().fill(StudioTheme.secondary).frame(width:38,height:3)
                    .frame(width:90,height:10).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:1,coordinateSpace:.global)
                        .onChanged{value in
                            if resizeStart==nil {resizeStart=store.consoleLogHeight}
                            store.setConsoleLogHeight((resizeStart ?? 122)-Double(value.translation.height))
                        }
                        .onEnded{_ in resizeStart=nil})
                    .help("콘솔 로그 높이 조절 · 위로 늘리기 · 아래로 줄이기")
                    .accessibilityLabel("콘솔 로그 높이 조절")
                    .accessibilityValue("\(Int(store.consoleLogHeight))포인트")
                    .accessibilityAdjustableAction{direction in
                        switch direction {
                        case .increment:store.setConsoleLogHeight(store.consoleLogHeight+20)
                        case .decrement:store.setConsoleLogHeight(store.consoleLogHeight-20)
                        @unknown default:break
                        }
                    }
            }
        }
        .onChange(of:store.consoleOpen){_,_ in resizeStart=nil}
        .onExitCommand{inputFocused=false;store.consoleOpen=false}
    }
}
extension AppStore {
    func consoleCommand(_ text:String) {
        let parts=text.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        guard let command=parts.first else{return}
        recordActivity("콘솔","> "+text)
        if command=="help" {
            recordActivity("콘솔","state · play · stop · save · undo · midi chords|arpeggio|bass|pulse · bounce · synth pad|bass|keys|supersaw|pluck|lead|ep|organ|brass|strings")
            return
        }
        var request=AgentRequest(method:command);request.projectID=project.id;request.expectedRevision=project.musicRevision
        var args=AgentArguments()
        switch command {
        case "state":request.method="snapshot"
        case "midi":
            guard parts.count==2,let pattern=MIDIPattern(rawValue:parts[1]),let use=selectedUse,let lane=currentLane else {recordActivity("콘솔","MIDI 서클을 선택하고 midi arpeggio처럼 입력하세요");return}
            request.method="apply";var operation=AgentOperation("generate_midi");operation.arrangementID=project.activeArrangementID;operation.useID=use.id;operation.laneID=lane.id;operation.pattern=pattern;operation.append=true;args.operations=[operation]
        case "synth":
            let names=["pad","bass","keys","supersaw","pluck","lead","ep","organ","brass","strings"]
            guard parts.count==2,let i=names.firstIndex(of:parts[1]),let track=selectedTrack else {recordActivity("콘솔","악기를 선택하고 synth pad처럼 입력하세요");return}
            request.method="apply";var operation=AgentOperation("set_instrument");operation.trackID=track.id;operation.synthVoice=SynthVoice(rawValue:i);args.operations=[operation]
        case "bounce":args.arrangementID=project.activeArrangementID;args.useID=selectedUse?.id;args.trackID=selectedTrackID;args.tailSeconds=bounceTailSeconds
        case "play","stop","save","undo":break
        default:recordActivity("콘솔","지원하지 않는 명령입니다. help로 명령을 확인하세요");return
        }
        request.arguments=args
        do {
            let result=try executeAgent(request,source:"콘솔")
            if command=="state" {recordActivity("콘솔","\(project.name) · r\(project.musicRevision) · \(project.tracks.count)트랙 · \(project.active.uses.count)섹션")}
            else if let id=result["jobID"] as? String {recordActivity("콘솔","작업 시작 · \(id)")}
        }catch{recordActivity("콘솔",error.localizedDescription)}
    }
}
