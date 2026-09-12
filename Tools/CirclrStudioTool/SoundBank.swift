import Foundation
import CirclrCore
import CirclrAudio

enum SoundBank {
    /// One section at a time: real instrument/effect/sidechain output without whole-song stem RAM.
    static func section(_ project:Project,root:URL,index:Int,to folder:URL) async throws {
        guard !FileManager.default.fileExists(atPath:folder.path) else {throw CirclrError("섹션 stem은 새 출력 폴더를 지정하세요")}
        let plan=try AlbumCompiler.executionPlan(project)
        guard plan.occurrences.indices.contains(index),let signal=plan.occurrences[index].signalPlan else {throw CirclrError("섹션 순서를 확인하세요 (0부터 시작)")}
        let occurrence=plan.occurrences[index]
        let outputs=try await SectionGraphRenderer.render(signal,project:project,root:root,clock:occurrence.clock,tail:2)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var report:[[String:Any]]=[]
        for (i,track) in project.tracks.enumerated() where !track.muted {
            guard var audio=outputs[track.id] else {continue}
            audio.multiply(track.gain*occurrence.use.gain)
            let safeName=String(track.name.replacingOccurrences(of:#"[^\p{L}\p{N} _-]"#,with:"",options:.regularExpression).prefix(60))
            let name="\(i)-\(safeName).wav";try audio.writeWAV(folder.appendingPathComponent(name))
            report.append(["track":track.name,"file":name,"gain":track.gain,"peak":audio.peak,"rms":audio.rms,"source":"post section effects and track gain; before album bus"])
        }
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("manifest.json"))
    }
    /// Render the same selectable factory patches used by the app, without effects or normalization.
    static func factory(to folder:URL) throws {
        guard !FileManager.default.fileExists(atPath:folder.path) else {throw CirclrError("새 프리셋 출력 폴더를 지정하세요")}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(bars:2,context:context)
        var report:[[String:Any]]=[]
        for preset in SynthPreset.factory {
            let pitches=preset.patch.voice == .bass ? [42]:[57,61,64,68]
            let notes=pitches.map{Note(beat:0,length:4,pitch:$0,velocity:90)}
            let audio=try ProductionInstrument.synth(notes,patch:preset.patch,clock:clock,tail:2)
            guard audio.peak.isFinite,audio.peak<1 else {throw CirclrError("프리셋 출력 headroom 확인: \(preset.name)")}
            try audio.writeWAV(folder.appendingPathComponent(preset.id+".wav"))
            report.append(["id":preset.id,"name":preset.name,"peak":audio.peak,"rms":audio.rms,"normalized":false])
        }
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("manifest.json"))
    }

    /// Isolated stock presets, no external effects. Pairwise RMS matched for six legacy voices.
    static func write(to folder:URL) throws {
        guard !FileManager.default.fileExists(atPath:folder.path) else {throw CirclrError("음색 비교는 새 출력 폴더를 지정하세요")}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(bars:2,context:context)
        var report:[[String:Any]]=[]
        for voice in SynthVoice.allCases {
            let pitches=voice == .bass ? [33]:[57,61,64,68]
            let notes=pitches.enumerated().map{Note(beat:Double($0.offset)*0.015,length:4,pitch:$0.element,velocity:100)}
            for version in voice.rawValue<6 ? [2,3]:[3] {
                var patch=SynthPatch(voice);patch.engineVersion=version
                var audio=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:1)
                let body=audio.slice(0..<96000),gain=min(pow(10,-20/20)/max(1e-6,body.rms),0.85/Double(max(0.001,audio.peak)))
                audio.multiply(gain)
                let name="\(voice.rawValue)-\(voice.label)-engine\(version).wav"
                try audio.writeWAV(folder.appendingPathComponent(name))
                report.append(["voice":voice.rawValue,"name":voice.label,"version":version,"file":name,"gain":gain,"bodyRMS":audio.slice(0..<96000).rms,"peak":audio.peak,"externalEffects":false])
            }
        }
        try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]).write(to:folder.appendingPathComponent("manifest.json"))
        print("기본 음색 비교 완료: \(folder.path)")
    }
}
