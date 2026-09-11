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
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:8) {
                Button{withAnimation(.easeOut(duration:0.18)){store.consoleOpen.toggle()}}label:{Image(systemName:"terminal");Text("콘솔");Image(systemName:store.consoleOpen ? "chevron.down":"chevron.up").font(.system(size:9))}
                    .keyboardShortcut("`",modifiers:.control).help("콘솔 접기·펼치기 · Ctrl `")
                Circle().fill(store.agentSocket == nil ? StudioTheme.secondary:StudioTheme.accent).frame(width:5,height:5)
                Text(store.agentSocket == nil ? "연결 없음":"MCP 연결 가능").font(.system(size:10)).foregroundStyle(StudioTheme.secondary)
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
                        Button("취소"){store.stop()}.accessibilityLabel("바운스 취소")
                    }else{
                        Text(job.kind).font(.system(size:10,design:.monospaced))
                        ProgressView(value:job.progress).frame(width:65)
                        Button("정지"){store.stop()}
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
                Text("r\(store.project.musicRevision)").font(.system(size:10,design:.monospaced)).foregroundStyle(StudioTheme.secondary).padding(.trailing,12)
            }.frame(height:34)
            if store.consoleOpen {
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
