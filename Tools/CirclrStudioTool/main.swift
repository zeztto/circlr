import Foundation
import AVFAudio
import CirclrCore
import CirclrAudio

/// Reproducible local song production using exactly the application's Core/Audio modules.
@main struct StudioTool {
    static func main() async {
        do {
            let args=CommandLine.arguments
            guard args.count>=3 else {throw CirclrError("사용: circlr-studio make-demo 출력폴더 [Splice폴더] | render 프로젝트.circlr 출력.wav")}
            if args[1]=="make-demo" {
                let folder=URL(fileURLWithPath:args[2]),splice=URL(fileURLWithPath:args.count>3 ? args[3]:NSHomeDirectory()+"/Splice")
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                var project=try F0rH3r.make(spliceRoot:splice)
                let target=folder.appendingPathComponent("f0r h3r.circlr")
                guard !FileManager.default.fileExists(atPath:target.path) else {throw CirclrError("기존 곡을 보존하기 위해 새 출력 폴더를 지정하세요")}
                project=try ProjectStore.save(project,to:target,mediaRoot:nil)
                let plan=try AlbumCompiler.executionPlan(project)
                var audio=try await ArrangementRenderer.render(project:project,root:target,plan:plan,includeStems:false,progress:report)
                // Store the same gain in the project, then re-render through its real graph.
                let headroom=pow(10,-1.2/20),gain=min(3,headroom/Double(max(0.001,audio.peak)))
                let master=project.signal.nodes.first{$0.kind == .master}!.id
                var trim=SignalNode(kind:.effect,name:"마스터 헤드룸");trim.effect=Effect(.gain,amount:gain)
                let incoming=project.signal.edges.filter{$0.to==master};project.signal.edges.removeAll{$0.to==master}
                for var edge in incoming {edge.to=trim.id;project.signal.edges.append(edge)}
                project.signal.nodes.append(trim);project.signal.edges.append(SignalEdge(from:trim.id,to:master))
                project.signal.layout.positions[trim.id]=Point(650,100);project.signal.layout.positions[master]=Point(950,100)
                project=try ProjectStore.save(project,to:target,mediaRoot:target)
                audio=try await ArrangementRenderer.render(project:project,root:target,plan:AlbumCompiler.executionPlan(project),includeStems:false,progress:report)
                let wav=folder.appendingPathComponent("f0r h3r.wav");try AudioExport.save(audio,to:wav)
                var lanes:[(String,[Note])]=[]
                for track in project.tracks {
                    var notes:[Note]=[]
                    for occurrence in plan.occurrences {
                        for lane in occurrence.lanes where lane.trackID==track.id {
                            for var note in lane.notes {note.beat+=occurrence.start*project.global.tempo/60;notes.append(note)}
                        }
                    }
                    if !notes.isEmpty {lanes.append((track.name,notes))}
                }
                try MIDIFile.encode(lanes:lanes,tempo:project.global.tempo,meter:project.global.meter).write(to:folder.appendingPathComponent("f0r h3r.mid"))
                var reportData:[String:Any]=["title":project.name,"tempo":project.global.tempo,"key":project.global.scale.label,"bodySeconds":plan.duration,"tailSeconds":audio.tailSeconds,"sampleRate":PCM.rate,"bitDepth":24,"peak":audio.peak,"rms":audio.mix.rms,"tracks":project.tracks.count,"notes":lanes.reduce(0){$0+$1.1.count},"masterGain":gain,"spliceCreditsSpent":0,"creditLimit":10]
                reportData["sections"]=plan.occurrences.map{["name":$0.use.name,"startSeconds":$0.start,"duration":$0.duration,"bars":$0.clock.meters.count] as [String:Any]}
                reportData["assets"]=project.assets.map{["name":$0.name,"path":$0.path,"sha256":$0.checksum,"source":"Splice owned library · Digi Grid Outrun Sounds","creditsSpent":0] as [String:Any]}
                try JSONSerialization.data(withJSONObject:reportData,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("production-report.json"))
                print("완료: \(wav.path) · \(audio.mix.duration)s · peak \(audio.peak)")
            } else if args[1]=="render",args.count>=4 {
                let loaded=try ProjectStore.load(URL(fileURLWithPath:args[2]))
                let audio=try await ArrangementRenderer.render(project:loaded.project,root:loaded.root,plan:AlbumCompiler.executionPlan(loaded.project),includeStems:false,progress:report)
                try AudioExport.save(audio,to:URL(fileURLWithPath:args[3]));print("완료: \(args[3])")
            } else {throw CirclrError("알 수 없는 명령입니다")}
        }catch{FileHandle.standardError.write(Data(("오류: \(error.localizedDescription)\n").utf8));exit(1)}
    }
    static func report(_ message:String,_ value:Double){print("\(Int(value*100))% \(message)")}
}

enum F0rH3r {
    struct Harmony {let root:Int;let notes:[Int]}
    static let f=Harmony(root:42,notes:[57,61,64,68]),d=Harmony(root:38,notes:[54,57,61,64])
    static let a=Harmony(root:45,notes:[56,59,61,64]),c=Harmony(root:37,notes:[53,56,59,62])
    static let b=Harmony(root:35,notes:[54,57,61,62]),e=Harmony(root:40,notes:[56,61,62,66])
    static let cm=Harmony(root:37,notes:[56,59,63,68])
    static func make(spliceRoot:URL) throws -> Project {
        let fm=FileManager.default
        let names=["NW_DG_kick_spot.wav","NW_DG_snare_finale.wav","NW_DG_hat_closed_regret.wav","NW_DG_percussion_shaker_dirty.wav","NW_DG_tom_labyrinth_high.wav","NW_DG_fx_wave.wav"]
        let enumerator=fm.enumerator(at:spliceRoot,includingPropertiesForKeys:nil)
        var files:[String:URL]=[:]
        while let file=enumerator?.nextObject() as? URL {if names.contains(file.lastPathComponent){files[file.lastPathComponent]=file}}
        var p=Project();p.name="f0r h3r";p.global.tempo=116;p.global.scale=Scale(root:6);p.schemaVersion=2
        for name in names {
            guard let url=files[name] else {throw CirclrError("보유 샘플을 Splice에서 동기화하세요: \(name)")}
            let file=try AVAudioFile(forReading:url)
            p.assets.append(Asset(name:name,path:url.path,duration:Double(file.length)/file.processingFormat.sampleRate,sampleRate:file.processingFormat.sampleRate))
        }
        let voices:[(String,SynthVoice,Double)]=[("오로라 패드",.pad,0.65),("도시의 키",.keys,0.9),("펄스 베이스",.bass,1.2),("그녀의 모티프",.lead,0.82),("빛의 코드",.supersaw,0.8),("얼음 아르페지오",.pluck,0.58)]
        for (name,voice,gain) in voices {let id=p.addTrack(name:name);let i=p.tracks.firstIndex{$0.id==id}!;p.tracks[i].instrument = .synthesizer(voice);p.tracks[i].gain=gain}
        p.tracks[0].instrument.synth?.attack=0.28;p.tracks[0].instrument.synth?.release=1.1;p.tracks[0].instrument.synth?.cutoff=2300
        p.tracks[4].instrument.synth?.attack=0.016;p.tracks[4].instrument.synth?.cutoff=6200
        _=p.addTrack(name:"Digi Grid 드럼",drums:true)
        p.tracks[6].instrument = .sampler(assetID:p.assets[0].id);p.tracks[6].instrument.drums=true;p.tracks[6].gain=0.68
        p.tracks[6].instrument.sample?.zones=zip([36,38,42,70,50],p.assets.prefix(5)).map{SampleZone($0.0,assetID:$0.1.id)}
        _=p.addTrack(name:"파도와 전환");p.tracks[7].gain=0.18
        let form:[(String,Int,String)]=[("멀리서 · Intro",4,"intro"),("도시의 기억 · Verse",8,"verse"),("다가오는 빛 · Lift",4,"lift"),("f0r h3r · Chorus",8,"chorus"),("북쪽의 밤 · Bridge",4,"bridge"),("다시 걷는 길 · Verse B",4,"verseB"),("마지막 빛 · Final chorus",12,"final"),("잔상 · Outro",4,"outro")]
        for (sectionIndex,item) in form.enumerated() {
            let (name,bars,style)=item
            let id=p.addSection(name:name,at:Point(Double(sectionIndex%4)*4000,Double(sectionIndex/4)*6200),bars:bars)
            let si=p.sections.count-1
            fill(&p.sections[si],style:style,assets:p.assets)
            p.sections[si].graph=graph(section:p.sections[si],tracks:p.tracks,style:style,tempo:p.global.tempo)
            if sectionIndex>0 {try ProjectEditing.connect(from:p.active.uses[sectionIndex-1].id,to:id,in:&p)}
        }
        p.enableAlbum()
        try ProjectStore.validateStructure(p);return p
    }
    static func fill(_ section:inout Section,style:String,assets:[Asset]) {
        let isChorus=style=="chorus" || style=="final",isVerse=style=="verse" || style=="verseB"
        let progression:[Harmony]=isChorus ? [d,e,cm,f,b,e,a,c]:(style=="bridge" ? [b,c,f,f]:[f,d,a,c])
        func add(_ track:Int,_ beat:Double,_ length:Double,_ pitch:Int,_ velocity:Int) {
            guard beat<Double(section.bars)*4 else{return}
            section.lanes[track].notes.append(Note(beat:beat,length:min(length,Double(section.bars)*4-beat),pitch:pitch,velocity:velocity))
        }
        for bar in 0..<section.bars {
            let h=progression[(isVerse ? bar/2:bar)%progression.count],start=Double(bar)*4
            let fade=style=="outro" ? max(0.2,1-Double(bar)*0.21):1
            for pitch in h.notes {add(0,start,3.9,pitch,Int(58*fade))}
            let keyHits:[Double]=isChorus ? [0.5,2.25]:[0,1.75,3]
            if style != "lift" || bar<2 {
                for (j,hit) in keyHits.enumerated() {for (n,pitch) in h.notes.enumerated(){add(1,start+hit+Double(n)*0.008,j==0 ? 1.25:0.62,pitch+12,Int(Double(74-j*5+n*2)*fade))}}
            }
            if style != "intro" && style != "outro" && !(style=="bridge" && bar<2) {
                let hits:[Double]=isChorus ? [0,0.75,1.5,2.75,3.5]:[0,0.5,1,1.5,2,2.5,3,3.5]
                for (j,beat) in hits.enumerated(){add(2,start+beat,isChorus ? 0.4:0.32,h.root+(j%4==3 ? 12:0),j%2==0 ? 104:83)}
                if bar%4==3 {add(2,start+3.75,0.2,h.root+11,65)}
            }
            if isChorus || style=="lift" {
                let hits:[(Double,Double)]=isChorus ? [(0,0.65),(1.5,0.4),(2.25,0.3),(2.75,0.55),(3.5,0.3)]:[(0,1.3),(2,1.3)]
                for (beat,length) in hits {for pitch in h.notes {add(4,start+beat,length,pitch+12,style=="lift" ? 52+bar*6:78)}}
            }
            if style=="intro" || style=="lift" || style=="final" || (isVerse && bar>=4) || style=="outro" {
                for step in 0..<8 {let beat=start+Double(step)*0.5+(step%2==1 ? 0.018:0);let pitch=h.notes[[0,2,3,1,2,0,3,2][step]]+24;add(5,beat,0.24,pitch,Int(Double(step%4==0 ? 68:50)*fade))}
            }
            if style != "intro" && style != "outro" && !(style=="bridge" && bar<2) {
                let kick:[Double]=isChorus ? [0,0.75,1.5,3.25]:[0,1,2,3]
                for beat in kick {add(6,start+beat,0.18,36,beat==0 ? 113:102)}
                for beat in (isChorus ? [2.0]:[1.0,3.0]) {add(6,start+beat+0.012,0.2,38,isChorus ? 104:85)}
                for step in 0..<8 {add(6,start+Double(step)*0.5+(step%2==1 ? 0.02:0),0.08,42,step%2==0 ? 49:66)}
                if isChorus || isVerse {for step in 0..<16 {add(6,start+Double(step)*0.25+(step%2==1 ? 0.012:0),0.09,70,step%4==2 ? 46:30)}}
                if style=="lift" && bar>=2 {for step in 0..<(bar==3 ? 16:8){add(6,start+Double(step)*(bar==3 ? 0.25:0.5),0.12,38,46+step*2)}}
                if bar%4==3 {for (j,beat) in [3.0,3.5,3.75].enumerated(){add(6,start+beat,0.18,50,65+j*8)}}
            }
            if style=="intro" && bar>=2 {for beat in [0.0,2]{add(6,start+beat,0.18,36,78)}}
            if style=="outro" && bar<2 {for beat in [0.0,2]{add(6,start+beat,0.18,36,68-bar*20)}}
        }
        // A composed, singable eight-bar motif with space at the end of each phrase.
        let motif:[(Double,Double,Int)]=[(0.5,0.65,73),(1.5,0.4,76),(2.25,1.15,78),(4,0.7,81),(5,0.4,80),(5.75,1.5,76),(8.5,0.5,73),(9.5,0.5,71),(10.5,1.1,68),(12,0.6,73),(13,0.4,76),(13.75,1.6,78),(16.5,0.45,78),(17.25,0.65,81),(18.25,0.9,83),(20,1.2,80),(21.5,1.6,78),(24.5,0.6,76),(25.5,0.5,73),(26.5,1,71),(28,0.75,73),(29.25,0.6,77),(30.25,1.3,80)]
        if isChorus {for offset in stride(from:0,to:section.bars*4,by:32){for (beat,length,pitch) in motif {add(3,Double(offset)+beat,length,pitch,style=="final" ? 95:87)}}}
        if style=="verse" {for (beat,length,pitch) in motif.prefix(7){add(3,beat+16,length,pitch-12,60)}}
        if style=="bridge" {for (beat,length,pitch) in [(1.0,2.0,78),(5.0,2.0,77),(9.0,3.0,78)] {add(3,beat,length,pitch,55)}}
        if style=="intro" || isChorus || style=="bridge" {var clip=AudioClip(assetID:assets[5].id,duration:min(assets[5].duration,4));clip.gain=style=="bridge" ? 0.45:0.75;section.lanes[7].audio=[clip]}
        for i in section.lanes.indices {section.lanes[i].notes.sort{$0.beat<$1.beat}}
    }
    static func graph(section:Section,tracks:[Track],style:String,tempo:Double)->SectionGraph {
        var graph=SectionGraph()
        func add(_ id:ID,_ name:String,_ content:MusicCircleContent,_ x:Double,_ y:Double){var node=MusicCircle(name:name,content:content);node.id=id;graph.nodes.append(node);graph.layout.positions[id]=Point(x,y)}
        func connect(_ from:ID,_ to:ID,_ signal:MusicSignal = .audio,sidechain:Bool = false){var edge=MusicConnection(from:from,to:to,signal:signal);edge.sidechain=sidechain;graph.edges.append(edge)}
        var drumSource:ID?
        for (index,track) in tracks.enumerated() {
            let y=Double(index)*380,lane=section.lanes[index],instrument="instrument:\(track.id)",output="output:\(track.id)"
            if index<7 {
                let midi="midi:\(lane.id)";add(midi,track.name+" MIDI",.midi(laneID:lane.id),-700,y)
                add(instrument,track.name,.instrument(trackID:track.id),-400,y);connect(midi,instrument,.midi)
                if index==6 {drumSource=instrument}
            } else {add(instrument,"転換の波",.mix,-400,y);for clip in lane.audio {let id="audio:\(clip.id)";add(id,"파도",.audio(laneID:lane.id,clipID:clip.id),-700,y);connect(id,instrument)}}
            var effects:[Effect]=[]
            if [0,1,3,5].contains(index) {effects.append(Effect(.reverb,amount:index==0 ? 0.78:0.6,secondary:index==0 ? 0.35:0.28))}
            if [1,3,5].contains(index) {effects.append(Effect(.delay,amount:(60/tempo*0.75-0.03)/0.97,secondary:index==3 ? 0.34:0.2))}
            if index==2 {effects.append(Effect(.drive,amount:0.08))}
            if index==4 {effects.append(Effect(.compressor,amount:0.34,secondary:0.7))}
            var previous=instrument
            for (n,effect) in effects.enumerated(){let id="fx:\(track.id):\(n)";add(id,effect.kind == .compressor ? "드럼 사이드체인":effect.kind.rawValue,.effect(effect),Double(n)*270,y);connect(previous,id);previous=id}
            add(output,track.name+" 출력",.output(trackID:track.id),Double(effects.count)*270+80,y);connect(previous,output)
        }
        if let drumSource {connect(drumSource,"fx:\(tracks[4].id):0",sidechain:true)}
        return graph
    }
}
