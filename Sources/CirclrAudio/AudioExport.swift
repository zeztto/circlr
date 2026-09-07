import Foundation
import CirclrCore

public enum AudioExport {
    public static func save(_ audio:PreparedAudio,to url:URL,stemNames:[ID:String]? = nil) throws {
        guard audio.peak <= 1,stemNames == nil || audio.stems.values.allSatisfy({$0.peak<=1}) else {throw CirclrError("Clipping을 방지하려면 트랙 또는 출력 Gain을 낮춘 뒤 내보내세요")}
        let fm=FileManager.default,parent=url.deletingLastPathComponent(),stage=parent.appendingPathComponent(".circlr-export-\(newID())\(stemNames == nil ? ".wav":"")"),backup=parent.appendingPathComponent(".circlr-export-backup-\(newID())")
        try fm.createDirectory(at:parent,withIntermediateDirectories:true)
        var complete=false,moved=false
        defer{if !complete{try? fm.removeItem(at:stage)}}
        if let names=stemNames {
            if fm.fileExists(atPath:url.path),!fm.fileExists(atPath:url.appendingPathComponent("circlr-export.json").path){throw CirclrError("기존 일반 폴더를 덮어쓸 수 없습니다. 새 stem 폴더 이름을 지정하세요")}
            try fm.createDirectory(at:stage,withIntermediateDirectories:true)
            for (id,pcm) in audio.stems {
                let name=(names[id] ?? "트랙").replacingOccurrences(of:"/",with:"-").replacingOccurrences(of:":",with:"-")
                try pcm.writeWAV(stage.appendingPathComponent("\(name)-\(id.prefix(6)).wav"))
            }
            try audio.mix.writeWAV(stage.appendingPathComponent("전체 mix.wav"))
            let manifest:[String:Any]=["format":"circlr-stems-v1","musicRevision":audio.plan.revision,"arrangementID":audio.plan.arrangementID,"bodySeconds":audio.plan.duration,"tailSeconds":audio.tailSeconds,"sampleRate":PCM.rate,"bitDepth":24]
            try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:stage.appendingPathComponent("circlr-export.json"))
            try "Stem은 각 source의 signal 경로를 개별 render하며 원래 sidechain 입력을 유지합니다. 공유 nonlinear processor를 통과한 stem 합은 전체 mix와 다를 수 있습니다.\n".write(to:stage.appendingPathComponent("내보내기 정보.txt"),atomically:true,encoding:.utf8)
        } else {try audio.mix.writeWAV(stage)}
        if fm.fileExists(atPath:url.path){try fm.moveItem(at:url,to:backup);moved=true}
        do{try fm.moveItem(at:stage,to:url);complete=true}catch{if moved{try? fm.moveItem(at:backup,to:url)};throw error}
        if moved{try? fm.removeItem(at:backup)}
    }
}
