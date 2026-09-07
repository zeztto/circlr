import Foundation
import AVFAudio
import CirclrCore
import CirclrAudio

/// Original v4 arrangement. Sections use regular DJ phrases, while orchestration carries variation.
enum ClubArrangement {
    typealias Harmony = F0rH3r.Harmony
    static let form:[(String,Int,String)] = [
        ("접속 · DJ Intro",16,"intro"),("도시의 기억 · Groove",16,"groove"),
        ("수평선 · Lift",8,"lift"),("f0r h3r · Club Chorus",16,"chorus"),
        ("북쪽의 밤 · Breakdown",8,"break"),("너의 도시 · Final Chorus",16,"final"),
        ("잔상 · DJ Outro",16,"outro")]
    // Bass, comping, atmosphere, punctuation, hook, future-bass body, arp, organ, brass, strings.
    static let voices:[(String,SynthVoice,Double)] = [
        ("펄스 베이스",.bass,1.1),("도시의 벨벳 EP",.electricPiano,0.7),
        ("오로라 패드",.pad,0.7),("유리빛 응답",.keys,0.75),
        ("그녀의 모티프",.lead,1.5),("빛의 코드",.supersaw,0.9),
        ("얼음 아르페지오",.pluck,0.6),("드로바 그루브",.organ,0.6),
        ("네온 브라스",.brass,0.85),("북쪽의 스트링",.strings,0.65)]
    static func make(sampleRoot:URL,bank:DemoSamples) throws -> Project {
        var p=Project();p.name="f0r h3r";p.global.tempo=120;p.global.scale=Scale(root:6);p.schemaVersion=2
        for entry in bank.files {
            let url=sampleRoot.appendingPathComponent(entry.file),file=try AVAudioFile(forReading:sampleRoot.appendingPathComponent(entry.file))
            p.assets.append(Asset(name:"FreePats · "+entry.sourceFile,path:url.path,duration:Double(file.length)/file.processingFormat.sampleRate,sampleRate:file.processingFormat.sampleRate))
        }
        for (name,asset,pitch,gain) in [("클럽 킥",0,36,0.84),("백비트 스네어",1,38,0.46),("엇박 하이햇",2,42,0.55),("가벼운 셰이커",3,70,0.28)] {
            _=p.addTrack(name:name,drums:true);let index=p.tracks.count-1
            p.tracks[index].instrument = .sampler(assetID:p.assets[asset].id,rootPitch:pitch);p.tracks[index].instrument.drums=true;p.tracks[index].gain=gain
        }
        for (name,voice,gain) in voices {
            _=p.addTrack(name:name);let index=p.tracks.count-1
            p.tracks[index].instrument = .synthesizer(voice);p.tracks[index].gain=gain
        }
        _=p.addTrack(name:"구간의 빛");p.tracks[14].gain=0.13
        p.tracks[4].instrument.synth?.cutoff=900;p.tracks[4].instrument.synth?.release=0.055;p.tracks[4].instrument.synth?.character=0.82
        p.tracks[5].instrument.synth?.sustain=0.05;p.tracks[5].instrument.synth?.character=0.8
        p.tracks[6].instrument.synth?.cutoff=1600;p.tracks[6].instrument.synth?.attack=0.3;p.tracks[6].instrument.synth?.release=0.7
        p.tracks[7].instrument.synth?.stereoWidth=0.6;p.tracks[7].instrument.synth?.decay=1.5
        p.tracks[8].instrument.synth?.cutoff=5000;p.tracks[8].instrument.synth?.attack=0.018;p.tracks[8].instrument.synth?.detune=5;p.tracks[8].instrument.synth?.character=0.8
        p.tracks[9].instrument.synth?.cutoff=4800;p.tracks[9].instrument.synth?.detune=19;p.tracks[9].instrument.synth?.release=0.1;p.tracks[9].instrument.synth?.motion=0.5
        p.tracks[10].instrument.synth?.cutoff=2400;p.tracks[10].instrument.synth?.motion=0.55
        p.tracks[11].instrument.synth?.cutoff=3600;p.tracks[11].instrument.synth?.release=0.08
        p.tracks[12].instrument.synth?.cutoff=2400;p.tracks[12].instrument.synth?.character=0.75
        p.tracks[13].instrument.synth?.cutoff=3800;p.tracks[13].instrument.synth?.release=0.7
        for (index,item) in form.enumerated() {
            let id=p.addSection(name:item.0,at:Point(Double(index%4)*4800,Double(index/4)*8800),bars:item.1)
            let si=p.sections.count-1;fill(&p.sections[si],style:item.2,assets:p.assets)
            p.sections[si].graph=graph(section:p.sections[si],tracks:p.tracks,style:item.2,tempo:p.global.tempo)
            if index>0 {try ProjectEditing.connect(from:p.active.uses[index-1].id,to:id,in:&p)}
        }
        p.enableAlbum();try ProjectStore.validateStructure(p);return p
    }
    static func fill(_ section:inout Section,style:String,assets:[Asset]) {
        let drop=style=="chorus" || style=="final",intro=style=="intro",outro=style=="outro",breakdown=style=="break"
        let progression:[Harmony]=drop ? [F0rH3r.d,F0rH3r.e,F0rH3r.cm,F0rH3r.f,F0rH3r.b,F0rH3r.e,F0rH3r.a,F0rH3r.c]:[F0rH3r.f,F0rH3r.d,F0rH3r.a,F0rH3r.c]
        func add(_ track:Int,_ beat:Double,_ length:Double,_ pitch:Int,_ velocity:Int) {
            let end=Double(section.bars)*4
            guard beat>=0,beat<end else{return}
            section.lanes[track].notes.append(Note(beat:beat,length:min(length,end-beat),pitch:pitch,velocity:max(1,min(127,velocity))))
        }
        func chord(_ track:Int,_ beat:Double,_ length:Double,_ pitches:[Int],_ velocity:Int,_ spread:Double=0) {
            for (n,pitch) in pitches.enumerated(){add(track,beat+Double(n)*spread,length,pitch,velocity-n%2*3)}
        }
        for bar in 0..<section.bars {
            let start=Double(bar)*4,h=progression[(drop ? bar:bar/2)%progression.count]
            let drum=(!breakdown || bar>=6)
            // The grid never changes to half-time or syncopated kicks. No rolls/tom fills.
            if drum {
                for beat in 0..<4 {add(0,start+Double(beat),0.16,36,beat==0 ? 120:116)}
                if !(intro && bar<4) && !(outro && bar>=12) {for beat in [1.0,3.0]{add(1,start+beat,0.18,38,104)}}
                for beat in [0.5,1.5,2.5,3.5]{add(2,start+beat,0.08,42,drop ? 94:83)}
                // Only two quiet shaker answers per bar; no permanent sixteenths.
                if (drop && bar>=8) || style=="groove" {for beat in [1.5,3.5]{add(3,start+beat,0.07,70,55)}}
            }
            let bass=(!intro || bar>=8) && (!outro || bar<8) && !breakdown
            if bass {
                for beat in [0.5,1.5,2.5,3.5]{add(4,start+beat,0.36,h.root,(beat==0.5 || beat==2.5) ? 109:98)}
            }
            let harmony=(!intro || bar>=8) && (!outro || bar<8)
            if harmony {
                // Rootless close voicings occupy the middle; bass owns the root below C3.
                if !drop || bar%2==0 {
                    chord(5,start+0.04,breakdown ? 2.8:1.05,h.notes,breakdown ? 85:88,0.009)
                    if !breakdown {chord(5,start+2.5,0.62,h.notes,74,0.008)}
                }
                // Low bed uses only two guide tones; no repeated full chord underneath everything.
                chord(6,start,3.7,[h.notes[0],h.notes[2]],drop ? 58:66)
            }
            if drop {
                chord(9,start+0.5,0.72,h.notes,92);chord(9,start+2.5,0.7,h.notes,86)
                if bar%4==3 {chord(12,start+3,0.5,Array(h.notes.prefix(3)).map{$0+12},80)}
                if style=="final" && bar>=8 {
                    chord(13,start,3.7,[h.notes[1]+12,h.notes[3]+12],66)
                }
            }
            if style=="groove" || (drop && bar%2==1) {
                chord(11,start+1.5,0.3,[h.notes[1],h.notes[2]],71)
                chord(11,start+3.5,0.3,[h.notes[1],h.notes[3]],65)
            }
            if (intro && bar>=12) || style=="lift" || breakdown || (outro && bar<4) {
                let steps=breakdown ? [0,3,6]:[0,2,4,6]
                for step in steps {add(10,start+Double(step)*0.5,0.28,h.notes[(step/2)%4]+12,step==0 ? 79:64)}
            }
            if (style=="groove" && bar%4==3) || (drop && bar%4==1) {
                add(7,start+2.5,0.4,h.notes[3]+12,88);add(7,start+3.5,0.35,h.notes[2]+12,76)
            }
            if style=="lift" {
                // An eight-bar harmonic rise with long strings replaces snare-roll builds.
                chord(13,start,3.8,[h.notes[1]+12,h.notes[3]+12],58+bar*3)
                if bar>=4 {chord(12,start,0.7,Array(h.notes.prefix(3)),68+bar*2)}
            }
            if breakdown {chord(13,start,3.8,[h.notes[1]+12,h.notes[3]+12],60)}
        }
        // Original hook: eight-bar question/answer, space between gestures, space for the response keys.
        let motif:[(Double,Double,Int)]=[
            (0.5,0.65,69),(1.5,0.4,73),(2.25,1.15,76),
            (4.25,0.55,78),(5,0.38,76),(5.75,1.45,73),
            (8.5,0.55,71),(9.5,0.42,68),(10.25,1.3,64),
            (12.25,0.62,68),(13.25,0.4,69),(14,1.35,73),
            (16.5,0.55,74),(17.5,0.4,73),(18.25,1.15,69),
            (20.25,0.55,68),(21,0.38,66),(21.75,1.5,64),
            (24.5,0.55,68),(25.5,0.4,69),(26.25,1.3,73),
            (28.25,0.65,71),(29.25,0.4,68),(30,1.1,65)]
        if drop {
            for cycle in 0..<2 {for (i,n) in motif.enumerated() {
                let pitch=style=="final" && cycle==1 && i==23 ? 66:n.2
                add(8,n.0+Double(cycle)*32,n.1,pitch,(style=="final" ? 106:101)-i%3*4)
            }}
        } else if style=="groove" {
            for (beat,length,pitch) in [(33.5,0.7,66),(34.75,0.6,68),(36.5,1.15,69),(38.25,0.85,68),(41.5,0.65,66),(42.75,0.6,64),(44.5,2.0,61)] {add(8,beat,length,pitch,87)}
        } else if breakdown {
            for (beat,length,pitch) in [(1.0,2.4,69),(9.0,2.0,68),(17.0,3.0,66)] {add(8,beat,length,pitch,82)}
        }
        if drop || breakdown || style=="lift" {
            var clip=AudioClip(assetID:assets[5].id,duration:min(assets[5].duration,4));clip.gain=0.6;section.lanes[14].audio=[clip]
        }
        for i in section.lanes.indices {section.lanes[i].notes.sort{$0.beat == $1.beat ? $0.pitch<$1.pitch:$0.beat<$1.beat}}
    }
    static func graph(section:Section,tracks:[Track],style:String,tempo:Double)->SectionGraph {
        var g=SectionGraph()
        func node(_ id:ID,_ name:String,_ content:MusicCircleContent,_ x:Double,_ y:Double){var n=MusicCircle(name:name,content:content);n.id=id;g.nodes.append(n);g.layout.positions[id]=Point(x,y)}
        func wire(_ from:ID,_ to:ID,_ signal:MusicSignal = .audio,_ sc:Bool=false){var e=MusicConnection(from:from,to:to,signal:signal);e.sidechain=sc;g.edges.append(e)}
        for (i,track) in tracks.enumerated() {
            let y=Double(i)*390,lane=section.lanes[i],source="instrument:\(track.id)",out="output:\(track.id)"
            if i==14 {
                node(source,"구간의 빛",.mix,-400,y)
                for clip in lane.audio {let id="audio:\(clip.id)";node(id,"심벌 잔향",.audio(laneID:lane.id,clipID:clip.id),-720,y);wire(id,source)}
            } else {
                let midi="midi:\(lane.id)";node(midi,track.name+" MIDI",.midi(laneID:lane.id),-720,y)
                node(source,track.name,.instrument(trackID:track.id),-400,y);wire(midi,source,.midi)
            }
            var effects:[Effect]=[]
            // No reverb on kick, bass or hat. Stereo placement leaves the hook in the centre.
            if [5,6,7,8,10,12,13].contains(i){effects.append(Effect(.reverb,amount:i==6 || i==13 ? 0.55:0.3,secondary:i==6 || i==13 ? 0.22:0.12))}
            if [7,8,10].contains(i){effects.append(Effect(.delay,amount:(60/tempo*0.75-0.03)/0.97,secondary:i==8 ? 0.14:0.18))}
            let pan:[Int:Double]=[3:0.18,5:-0.16,7:0.27,10:-0.3,11:0.2,12:-0.22]
            if let amount=pan[i]{effects.append(Effect(.pan,amount:amount))}
            if [4,6,9,13].contains(i){effects.append(Effect(.compressor,amount:i==4 ? 0.62:0.50,secondary:0.5))}
            var previous=source
            for (j,fx) in effects.enumerated(){let id="fx:\(track.id):\(j)";node(id,fx.kind == .compressor ? "킥 사이드체인":fx.kind.rawValue,.effect(fx),Double(j)*270,y);wire(previous,id);previous=id
                if fx.kind == .compressor {wire("instrument:\(tracks[0].id)",id,.audio,true)}
            }
            node(out,track.name+" 출력",.output(trackID:track.id),Double(effects.count)*270+80,y);wire(previous,out)
        }
        return g
    }
}
