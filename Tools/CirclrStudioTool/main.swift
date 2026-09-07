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
                var reportData:[String:Any]=["title":project.name,"tempo":project.global.tempo,"key":project.global.scale.label,"bodySeconds":plan.duration,"tailSeconds":audio.tailSeconds,"sampleRate":PCM.rate,"bitDepth":24,"peak":audio.peak,"rms":audio.mix.rms,"tracks":project.tracks.count,"notes":lanes.reduce(0){$0+$1.1.count},"masterGain":gain,"productionVersion":2,"synthEngineVersion":2,"listeningReview":"not_performed_by_model","spliceCreditsSpent":0,"creditLimit":10]
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
    static let a=Harmony(root:33,notes:[56,59,61,64]),c=Harmony(root:37,notes:[53,56,59,62])
    static let b=Harmony(root:35,notes:[54,57,61,62]),e=Harmony(root:40,notes:[56,62,66,68])
    static let cm=Harmony(root:37,notes:[56,59,64,68])
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
        let voices:[(String,SynthVoice,Double)]=[("오로라 패드",.pad,0.8),("도시의 키",.keys,1.1),("펄스 베이스",.bass,1.15),("그녀의 모티프",.lead,1.15),("빛의 코드",.supersaw,1.15),("얼음 아르페지오",.pluck,0.65)]
        for (name,voice,gain) in voices {let id=p.addTrack(name:name);let i=p.tracks.firstIndex{$0.id==id}!;p.tracks[i].instrument = .synthesizer(voice);p.tracks[i].gain=gain}
        p.tracks[0].instrument.synth?.attack=0.28;p.tracks[0].instrument.synth?.release=1.1;p.tracks[0].instrument.synth?.cutoff=1800
        p.tracks[1].instrument.synth?.decay=1.6;p.tracks[1].instrument.synth?.sustain=0.08
        p.tracks[2].instrument.synth?.sustain=0.72;p.tracks[2].instrument.synth?.release=0.07
        p.tracks[3].instrument.synth?.attack=0.025;p.tracks[3].instrument.synth?.release=0.22;p.tracks[3].instrument.synth?.detune=4
        p.tracks[5].instrument.synth?.cutoff=2100;p.tracks[5].instrument.synth?.release=0.25
        p.tracks[4].instrument.synth?.attack=0.016;p.tracks[4].instrument.synth?.cutoff=4200;p.tracks[4].instrument.synth?.stereoWidth=0.85;p.tracks[4].instrument.synth?.detune=17
        _=p.addTrack(name:"Digi Grid 드럼",drums:true)
        p.tracks[6].instrument = .sampler(assetID:p.assets[0].id);p.tracks[6].instrument.drums=true;p.tracks[6].gain=0.48
        p.tracks[6].instrument.sample?.zones=zip([38,42,70,50],p.assets.dropFirst().prefix(4)).map{SampleZone($0.0,assetID:$0.1.id)}
        _=p.addTrack(name:"파도와 전환");p.tracks[7].gain=0.13
        _=p.addTrack(name:"Digi Grid 킥",drums:true);p.tracks[8].instrument = .sampler(assetID:p.assets[0].id,rootPitch:36);p.tracks[8].gain=0.68
        let form:[(String,Int,String)]=[("멀리서 · Intro",4,"intro"),("도시의 기억 · Verse",8,"verse"),("다가오는 빛 · Lift",4,"lift"),("f0r h3r · Chorus",8,"chorus"),("푸른 공기 · Post",4,"post"),("다시 걷는 길 · Verse B",8,"verseB"),("다시 피는 빛 · Lift",4,"lift"),("너의 도시 · Chorus",8,"chorus"),("북쪽의 밤 · Bridge",4,"bridge"),("마지막 빛 · Final chorus",12,"final"),("잔상 · Outro",4,"outro")]
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
        let chorus=style=="chorus" || style=="final",verse=style=="verse" || style=="verseB"
        let progression:[Harmony]=chorus ? [d,e,cm,f,b,e,a,c]:(style=="bridge" ? [b,c,f,c]:[f,d,a,c])
        func add(_ track:Int,_ beat:Double,_ length:Double,_ pitch:Int,_ velocity:Int) {
            let end=Double(section.bars)*4
            guard beat>=0,beat<end else{return}
            section.lanes[track].notes.append(Note(beat:beat,length:min(length,end-beat),pitch:pitch,velocity:max(1,min(127,velocity))))
        }
        for bar in 0..<section.bars {
            // Final four bars resolve on the tonic, instead of restarting half a chorus.
            let h=(style=="final" && bar>=8) ? [d,e,c,f][bar-8]:progression[(verse ? bar/2:bar)%progression.count]
            let start=Double(bar)*4,ending=style=="outro"
            let fade=ending ? [0.8,0.65,0.45,0.25][bar]:1
            let sparse=(style=="intro" && bar<2) || (style=="bridge" && bar<2) || ending
            for pitch in h.notes.prefix(3) {add(0,start,3.8,pitch,Int((chorus ? 46:57)*fade))}
            // City-pop comping: mid-register rootless voicing, short upbeats and a longer answer.
            if style != "lift" || bar<2 {
                let hits:[(Double,Double,Int)]=chorus ? [(1.0,0.55,67),(3.1,0.58,62)]:[(0.04,1.1,78),(1.72,0.45,65),(2.9,0.78,71)]
                for (beat,length,velocity) in hits {
                    if ending && beat>0.1 {continue}
                    for (n,pitch) in h.notes.enumerated(){add(1,start+beat+Double(n)*0.012,length,pitch,Int(Double(velocity+n%2*3)*fade))}
                }
            }
            if !sparse && style != "intro" {
                let hits:[(Double,Double,Int)]=chorus ? [(0,0.62,105),(0.8,0.42,89),(1.5,0.42,98),(2.7,0.6,96),(3.5,0.3,82)]:[(0,0.8,98),(1.0,0.36,77),(1.65,0.65,91),(2.5,0.35,82),(3.1,0.54,92)]
                for (j,hit) in hits.enumerated(){add(2,start+hit.0,hit.1,h.root+(j==4 && bar%2==1 ? 12:0),hit.2)}
                if bar%4==3 && style != "lift" {let next=progression[((verse ? (bar+1)/2:bar+1))%progression.count].root;add(2,start+3.75,0.18,next-1,72)}
            }
            if chorus || style=="lift" {
                let hits:[(Double,Double)]=chorus ? [(0,0.65),(1.5,0.38),(2.25,0.3),(2.8,0.55),(3.5,0.32)]:[(0,1.3),(2,1.2)]
                for (beat,length) in hits {for (n,pitch) in h.notes.enumerated(){add(4,start+beat+Double(n)*0.002,length,pitch,style=="lift" ? 52+bar*7:85)}}
            }
            // Arpeggio answers the hook only in its rests; no permanent high-register wash.
            if ["intro","post","outro","lift"].contains(style) || style=="verseB" || (style=="final" && bar%2==1) {
                let steps=style=="intro" || style=="post" ? [0,1,3,4,6,7]:[5,6,7]
                for step in steps {let pitch=h.notes[[0,2,3,1,2,0,3,2][step]]+12;add(5,start+Double(step)*0.5+0.014,0.22,pitch,Int(Double(step%4==0 ? 75:58)*fade))}
            }
            if !sparse && style != "intro" {
                let kicks:[Double]=chorus ? [0,0.75,1.5,3.25]:(style=="post" ? [0,2.5]:[0,1,2,3])
                for beat in kicks {add(8,start+beat,0.16,36,beat==0 ? 118:104)}
                for beat in (chorus || style=="post" ? [2.0]:[1.0,3.0]) {add(6,start+beat+0.01,0.2,38,chorus ? 114:96)}
                for step in 0..<8 {add(6,start+Double(step)*0.5+(step%2==1 ? 0.018:0),0.06,42,[50,75,42,68,53,77,45,65][step])}
                if chorus || style=="verseB" {for step in [1,3,5,7,9,11,13,15]{add(6,start+Double(step)*0.25+0.012,0.06,70,step%4==3 ? 49:36)}}
                if style=="lift" && bar>=2 {
                    for step in 0..<(bar==3 ? 12:4){add(6,start+Double(step)*(bar==3 ? 0.25:0.75),0.08,38,48+step*3)}
                }
                if bar%4==3 {for (j,beat) in [3.25,3.5,3.75].enumerated(){add(6,start+beat,0.12,50,66+j*9)}}
            }
            if style=="intro" && bar>=2 {add(8,start,0.16,36,85)}
            if ending && bar==0 {add(8,start,0.16,36,82)}
        }
        // Eight-bar question/answer. Dmaj9 / E9 / C#m7 / F#m9 / Bm9 / E9 / Amaj9 / C#7b9.
        let motif:[(Double,Double,Int)]=[
            (0.5,0.65,69),(1.5,0.4,73),(2.25,1.15,76),
            (4.25,0.55,78),(5,0.38,76),(5.75,1.45,73),
            (8.5,0.55,71),(9.5,0.42,68),(10.25,1.3,64),
            (12.25,0.62,68),(13.25,0.4,69),(14,1.35,73),
            (16.5,0.55,74),(17.5,0.4,73),(18.25,1.15,69),
            (20.25,0.55,68),(21,0.38,66),(21.75,1.5,64),
            (24.5,0.55,68),(25.5,0.4,69),(26.25,1.3,73),
            (28.25,0.65,71),(29.25,0.4,68),(30,1.1,65)]
        if chorus {
            for (i,item) in motif.enumerated(){add(3,item.0,item.1,item.2,(style=="final" ? 110:103)-(i%3)*5)}
            if style=="final" {
                for (beat,length,pitch) in [(32.5,0.65,69),(33.5,0.4,73),(34.25,1.2,76),(36.25,0.6,78),(37.25,1.1,76),(40.5,0.65,73),(41.5,0.5,71),(42.25,1.1,65),(44.0,3.6,66)] {add(3,beat,length,pitch,104)}
            }
        }
        if verse {
            let phrase:[(Double,Double,Int)]=[(1.5,0.7,66),(2.75,0.6,68),(4.5,1.15,69),(6.25,0.85,68),(9.5,0.65,66),(10.75,0.6,64),(12.5,2,61)]
            for (beat,length,pitch) in phrase {add(3,beat+16,length,pitch,style=="verseB" ? 84:76)}
        }
        if style=="bridge" {for (beat,length,pitch) in [(1.0,2.4,69),(5.0,2,68),(9.0,3,66)] {add(3,beat,length,pitch,76)}}
        if style=="intro" || chorus || style=="bridge" {
            var clip=AudioClip(assetID:assets[5].id,duration:min(assets[5].duration,4));clip.gain=style=="bridge" ? 0.4:0.65;section.lanes[7].audio=[clip]
        }
        for i in section.lanes.indices {section.lanes[i].notes.sort{$0.beat == $1.beat ? $0.pitch<$1.pitch:$0.beat<$1.beat}}
    }
    static func graph(section:Section,tracks:[Track],style:String,tempo:Double)->SectionGraph {
        var graph=SectionGraph()
        func add(_ id:ID,_ name:String,_ content:MusicCircleContent,_ x:Double,_ y:Double){var node=MusicCircle(name:name,content:content);node.id=id;graph.nodes.append(node);graph.layout.positions[id]=Point(x,y)}
        func connect(_ from:ID,_ to:ID,_ signal:MusicSignal = .audio,sidechain:Bool = false){var edge=MusicConnection(from:from,to:to,signal:signal);edge.sidechain=sidechain;graph.edges.append(edge)}
        var drumSource:ID?
        for (index,track) in tracks.enumerated() {
            let y=Double(index)*380,lane=section.lanes[index],instrument="instrument:\(track.id)",output="output:\(track.id)"
            if index != 7 {
                let midi="midi:\(lane.id)";add(midi,track.name+" MIDI",.midi(laneID:lane.id),-700,y)
                add(instrument,track.name,.instrument(trackID:track.id),-400,y);connect(midi,instrument,.midi)
                if index==8 {drumSource=instrument}
            } else {add(instrument,"전환의 파도",.mix,-400,y);for clip in lane.audio {let id="audio:\(clip.id)";add(id,"파도",.audio(laneID:lane.id,clipID:clip.id),-700,y);connect(id,instrument)}}
            var effects:[Effect]=[]
            if [0,1,3,5].contains(index) {effects.append(Effect(.reverb,amount:index==0 ? 0.58:0.36,secondary:index==0 ? 0.48:0.32))}
            if [1,3,5].contains(index) {effects.append(Effect(.delay,amount:(60/tempo*0.75-0.03)/0.97,secondary:index==3 ? 0.22:0.12))}
            if index==4 {effects.append(Effect(.compressor,amount:0.3,secondary:0.7))}
            var previous=instrument
            for (n,effect) in effects.enumerated(){let id="fx:\(track.id):\(n)";add(id,effect.kind == .compressor ? "드럼 사이드체인":effect.kind.rawValue,.effect(effect),Double(n)*270,y);connect(previous,id);previous=id}
            add(output,track.name+" 출력",.output(trackID:track.id),Double(effects.count)*270+80,y);connect(previous,output)
        }
        if let drumSource {connect(drumSource,"fx:\(tracks[4].id):0",sidechain:true)}
        return graph
    }
}
