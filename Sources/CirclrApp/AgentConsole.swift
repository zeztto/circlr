import SwiftUI
import CirclrCore

struct AgentConsoleBoundsKey:PreferenceKey {
    static var defaultValue=CGRect.zero
    static func reduce(value:inout CGRect,nextValue:()->CGRect){let next=nextValue();if next.width>0{value=next}}
}

struct AgentConsole:View {
    @ObservedObject var store:AppStore
    @State private var command=""
    @FocusState private var inputFocused:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:8) {
                Button{withAnimation(.easeOut(duration:0.18)){store.consoleOpen.toggle()}}label:{Image(systemName:"terminal");Text("콘솔");Image(systemName:store.consoleOpen ? "chevron.down":"chevron.up").font(.system(size:9))}
                    .keyboardShortcut("`",modifiers:.control).help("콘솔 접기·펼치기 · Ctrl `")
                Circle().fill(store.agentSocket == nil ? StudioTheme.secondary:StudioTheme.accent).frame(width:5,height:5)
                Text(store.agentSocket == nil ? "연결 없음":"MCP 연결 가능").font(.system(size:10)).foregroundStyle(StudioTheme.secondary)
                Spacer()
                if let job=store.agentJob,job.state=="running" {
                    Text(job.kind).font(.system(size:10,design:.monospaced))
                    ProgressView(value:job.progress).frame(width:65)
                    Button("정지"){store.stop()}
                } else if let job=store.agentJob,let id=job.nodeID,let node=store.hierarchyScene?.nodes.first(where:{$0.music?.id==id}) {
                    Button("바운스 서클 보기"){store.focusHierarchy(node.id,detail:true)}
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
                    }.frame(height:122)
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
        .onExitCommand{inputFocused=false;store.consoleOpen=false}
    }
}
extension AppStore {
    func consoleCommand(_ text:String) {
        let parts=text.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        guard let command=parts.first else{return}
        recordActivity("콘솔","> "+text)
        if command=="help" {
            recordActivity("콘솔","state · play · stop · save · undo · midi chords|arpeggio|bass|pulse · bounce · synth pad|bass|keys|supersaw|pluck|lead")
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
            let names=["pad","bass","keys","supersaw","pluck","lead"]
            guard parts.count==2,let i=names.firstIndex(of:parts[1]),let track=selectedTrack else {recordActivity("콘솔","악기를 선택하고 synth pad처럼 입력하세요");return}
            request.method="apply";var operation=AgentOperation("set_instrument");operation.trackID=track.id;operation.synthVoice=SynthVoice(rawValue:i);args.operations=[operation]
        case "bounce":args.arrangementID=project.activeArrangementID;args.useID=selectedUse?.id;args.trackID=selectedTrackID
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
