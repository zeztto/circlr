import Foundation
import Darwin
import CirclrCore

/// STOP and the final WAV or stem rename share this gate. If STOP wins, publication
/// cannot begin; if publication wins, STOP waits for that rename to finish.
public final class WAVExportCommitGate: @unchecked Sendable {
    private let lock=NSLock()
    private var cancelled=false
    public init() {}
    public func cancel() {lock.lock();cancelled=true;lock.unlock()}
    func publish(_ body:()throws->Void) throws {
        lock.lock();defer{lock.unlock()}
        guard !cancelled else{throw CancellationError()}
        try Task.checkCancellation()
        try body()
    }
}

public enum AudioExport {
    /// Render each stem directly into a hidden sibling directory, then publish the complete set.
    public static func saveStems(project:Project,root:URL?,plan:ExecutionPlan,to url:URL,
                                 stemNames:[ID:String],
                                 commitGate:WAVExportCommitGate? = nil,
                                 progress:@escaping (String,Double)->Void = {_,_ in}) async throws {
        try await saveStems(project:project,root:root,plan:plan,to:url,stemNames:stemNames,
                            commitGate:commitGate,beforePublish:{},afterCommitStarted:{},progress:progress)
    }
    /// Internal hooks make the STOP/publication ordering deterministic in tests.
    static func saveStems(project:Project,root:URL?,plan:ExecutionPlan,to url:URL,
                          stemNames:[ID:String],commitGate:WAVExportCommitGate?,
                          beforePublish:()->Void,afterCommitStarted:()->Void,
                          progress:@escaping (String,Double)->Void = {_,_ in}) async throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at:parent,withIntermediateDirectories:true)
        try validateStemTarget(url)
        let filenames = try stemFilenames(tracks:project.tracks,names:stemNames)
        let stage = parent.appendingPathComponent(".circlr-export-\(newID())")
        try fm.createDirectory(at:stage,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:stage) }
        var writtenIDs:Set<ID> = []
        let audio = try await ArrangementRenderer.renderStems(project:project,root:root,plan:plan,progress:progress) { id,pcm in
            try Task.checkCancellation()
            guard let filename=filenames[id],writtenIDs.insert(id).inserted else { throw CirclrError("Stem 트랙 목록이 일치하지 않습니다") }
            try checkPeak(pcm)
            try pcm.writeWAV(stage.appendingPathComponent(filename))
            try Task.checkCancellation()
        }
        guard writtenIDs.count == project.tracks.count else { throw CirclrError("Stem 파일 수가 트랙 수와 일치하지 않습니다") }
        try checkPeak(audio.mix)
        try audio.mix.writeWAV(stage.appendingPathComponent("전체 mix.wav"))
        try writeStemMetadata(audio,at:stage,stemFiles:Array(filenames.values).sorted())
        let stagedWAVs = try fm.contentsOfDirectory(atPath:stage.path).filter{$0.hasSuffix(".wav")}
        guard stagedWAVs.count == project.tracks.count + 1 else { throw CirclrError("Stem 파일 수가 트랙 수와 일치하지 않습니다") }
        try Task.checkCancellation()
        beforePublish()
        try (commitGate ?? WAVExportCommitGate()).publish {
            try validateStemTarget(url)
            afterCommitStarted()
            try publishDirectory(stage,to:url)
        }
    }
    public static func save(_ audio:PreparedAudio,to url:URL,stemNames:[ID:String]? = nil) throws {
        guard let names=stemNames else {try saveWAV(audio,to:url);return}
        guard audio.peak <= 1,audio.stems.values.allSatisfy({$0.peak<=1}) else {throw CirclrError("Clipping을 방지하려면 트랙 또는 출력 Gain을 낮춘 뒤 내보내세요")}
        let fm=FileManager.default,parent=url.deletingLastPathComponent(),stage=parent.appendingPathComponent(".circlr-export-\(newID())"),backup=parent.appendingPathComponent(".circlr-export-backup-\(newID())")
        try fm.createDirectory(at:parent,withIntermediateDirectories:true)
        var complete=false,moved=false
        defer{if !complete{try? fm.removeItem(at:stage)}}
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
        if fm.fileExists(atPath:url.path){try fm.moveItem(at:url,to:backup);moved=true}
        do{try fm.moveItem(at:stage,to:url);complete=true}catch{if moved{try? fm.moveItem(at:backup,to:url)};throw error}
        if moved{try? fm.removeItem(at:backup)}
    }

    /// Write a complete WAV beside its destination before atomically publishing it.
    /// Call this from a background task; cancellation leaves the previous file intact.
    public static func saveWAV(_ audio:PreparedAudio,to url:URL,
                               progress:((Double)->Void)? = nil,
                               commitGate:WAVExportCommitGate? = nil) throws {
        try saveWAV(audio,to:url,progress:progress,commitGate:commitGate,beforePublish:{})
    }
    /// The final hook is internal so the cancellation/rename boundary can be tested.
    static func saveWAV(_ audio:PreparedAudio,to url:URL,
                        progress:((Double)->Void)?,commitGate:WAVExportCommitGate?,
                        beforePublish:()->Void) throws {
        try Task.checkCancellation()
        try checkPeak(audio.mix)
        let fm=FileManager.default,parent=url.deletingLastPathComponent()
        try fm.createDirectory(at:parent,withIntermediateDirectories:true)
        let stage=parent.appendingPathComponent(".circlr-export-\(newID()).wav")
        defer { try? fm.removeItem(at:stage) }
        try audio.mix.writeWAV(stage,progress:progress)
        try Task.checkCancellation()
        beforePublish()
        try (commitGate ?? WAVExportCommitGate()).publish {
            if let kind=try fileKind(url),kind != mode_t(S_IFREG) {
                throw CirclrError("기존 WAV 파일이 아닌 항목을 덮어쓸 수 없습니다")
            }
            if fm.fileExists(atPath:url.path) {
                let result=stage.path.withCString { source in
                    url.path.withCString { destination in
                        renamex_np(source,destination,UInt32(RENAME_SWAP))
                    }
                }
                guard result == 0 else {throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)}
            } else {
                try fm.moveItem(at:stage,to:url)
            }
        }
    }

    private static func checkPeak(_ pcm:PCM) throws {
        guard pcm.peak <= 1 else { throw CirclrError("Clipping을 방지하려면 트랙 또는 출력 Gain을 낮춘 뒤 내보내세요") }
    }
    static func stemFilenames(tracks:[Track],names:[ID:String]) throws -> [ID:String] {
        guard Set(tracks.map(\.id)).count == tracks.count else { throw CirclrError("Stem 트랙 ID가 중복되었습니다") }
        var result:[ID:String] = [:],used:Set<String> = []
        for (index,track) in tracks.enumerated() {
            let name=safeFilenamePart(names[track.id] ?? "트랙")
            let prefix=safeFilenamePart(String(track.id.prefix(6)))
            let base="\(name)-\(prefix)"
            var filename="\(base).wav",attempt=0
            while used.contains(filenameKey(filename)) {
                attempt += 1
                filename="\(base)-\(index+1)-\(attempt).wav"
            }
            used.insert(filenameKey(filename));result[track.id]=filename
        }
        return result
    }
    private static func filenameKey(_ value:String) -> String {
        value.decomposedStringWithCanonicalMapping.folding(
            options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],
            locale:Locale(identifier:"en_US_POSIX"))
    }
    private static func safeFilenamePart(_ value:String) -> String {
        let forbidden=CharacterSet(charactersIn:"/:").union(.controlCharacters)
        let cleaned=value.unicodeScalars.map{forbidden.contains($0) ? "-" : String($0)}.joined()
        return cleaned.isEmpty ? "트랙" : cleaned
    }
    private static func writeStemMetadata(_ audio:PreparedAudio,at directory:URL,stemFiles:[String]) throws {
        let manifest:[String:Any] = ["format":"circlr-stems-v1","musicRevision":audio.plan.revision,
            "arrangementID":audio.plan.arrangementID,"bodySeconds":audio.plan.duration,
            "tailSeconds":audio.tailSeconds,"sampleRate":PCM.rate,"bitDepth":24,
            "stemFiles":stemFiles]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys])
            .write(to:directory.appendingPathComponent("circlr-export.json"))
        try "Stem은 각 source의 signal 경로를 개별 render하며 원래 sidechain 입력을 유지합니다. 공유 nonlinear processor를 통과한 stem 합은 전체 mix와 다를 수 있습니다.\n"
            .write(to:directory.appendingPathComponent("내보내기 정보.txt"),atomically:true,encoding:.utf8)
    }
    private static func validateStemTarget(_ url:URL) throws {
        let fm = FileManager.default
        let invalid=CirclrError("기존 일반 폴더를 덮어쓸 수 없습니다. 새 stem 폴더 이름을 지정하세요")
        guard let targetKind=try fileKind(url) else {return}
        guard targetKind == mode_t(S_IFDIR) else {throw invalid}
        let marker=url.appendingPathComponent("circlr-export.json")
        guard try fileKind(marker) == mode_t(S_IFREG) else {throw invalid}
        let size=try fm.attributesOfItem(atPath:marker.path)[.size] as? NSNumber
        guard let size,size.intValue < 65_536,
              let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:marker)) as? [String:Any],
              manifest["format"] as? String == "circlr-stems-v1",
              manifest["musicRevision"] as? Int != nil,
              let arrangementID=manifest["arrangementID"] as? String,!arrangementID.isEmpty,
              manifest["bodySeconds"] as? Double != nil,
              manifest["tailSeconds"] as? Double != nil,
              manifest["sampleRate"] as? Double == PCM.rate,
              manifest["bitDepth"] as? Int == 24 else {throw invalid}
        let items=try fm.contentsOfDirectory(at:url,includingPropertiesForKeys:nil)
        let filenames=Set(items.map(\.lastPathComponent))
        let stems=filenames.filter{$0.hasSuffix(".wav") && $0 != "전체 mix.wav"}
        guard filenames.contains("전체 mix.wav"),filenames.contains("내보내기 정보.txt"),!stems.isEmpty else {throw invalid}
        guard let listed=manifest["stemFiles"] as? [String] else {
            throw CirclrError("기존 stem 폴더의 파일 목록을 확인할 수 없습니다. 새 stem 폴더 이름을 지정하세요")
        }
        guard !listed.isEmpty,Set(listed).count == listed.count,Set(listed) == stems else {throw invalid}
        for item in items {
            let filename=item.lastPathComponent
            guard filename == "circlr-export.json" || filename == "내보내기 정보.txt" ||
                    (filename.hasSuffix(".wav") && !filename.hasPrefix(".")),
                  try fileKind(item) == mode_t(S_IFREG) else {throw invalid}
            if filename.hasSuffix(".wav") {
                let handle=try FileHandle(forReadingFrom:item)
                defer {try? handle.close()}
                let header=try handle.read(upToCount:12) ?? Data()
                guard header.count == 12,header.prefix(4) == Data("RIFF".utf8),
                      header.suffix(4) == Data("WAVE".utf8) else {throw invalid}
            }
        }
    }
    private static func fileKind(_ url:URL) throws -> mode_t? {
        var info=stat()
        let result=url.path.withCString{lstat($0,&info)}
        if result == 0 {return info.st_mode & mode_t(S_IFMT)}
        if errno == ENOENT {return nil}
        throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)
    }
    private static func publishDirectory(_ stage:URL,to destination:URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath:destination.path) else {
            try fm.moveItem(at:stage,to:destination)
            return
        }
        // Both paths are siblings on the same volume. RENAME_SWAP keeps the old
        // complete export visible until the new complete export replaces it.
        let result = stage.path.withCString { source in
            destination.path.withCString { target in
                renamex_np(source,target,UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
        // The previous export now occupies the hidden staging path.
    }
}
