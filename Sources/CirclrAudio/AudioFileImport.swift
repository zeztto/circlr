import Foundation
import AVFAudio
import CryptoKit
import CirclrCore

public struct StagedAudioImport {
    public let directory:URL
    public let assets:[Asset]
    public func discard() {try? FileManager.default.removeItem(at:directory)}
}
public enum AudioFileImport {
    public static let extensions:Set<String>=["wav","wave","aif","aiff","aifc","mp3","m4a","aac","flac","caf","au","snd"]
    public static let maximumFileBytes:Int64=2_147_483_648
    public static let maximumBatchBytes:Int64=4_294_967_296
    /// Copies into an owned directory before inspecting media. Never changes a selected source.
    public static func stage(_ urls:[URL],under root:URL,progress:@Sendable (Double)->Void={_ in}) throws -> StagedAudioImport {
        guard !urls.isEmpty,urls.count<=64 else {throw CirclrError("한 번에 1–64개 오디오 파일을 가져오세요")}
        try Task.checkCancellation()
        let fm=FileManager.default
        var sizes:[Int64]=[],total:Int64=0
        for url in urls {
            guard url.isFileURL,extensions.contains(url.pathExtension.lowercased()) else {throw CirclrError("지원하는 로컬 오디오 파일을 선택하세요: \(url.lastPathComponent)")}
            let attrs=try fm.attributesOfItem(atPath:url.resolvingSymlinksInPath().path),size=(attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard attrs[.type] as? FileAttributeType == .typeRegular,size>0,size<=maximumFileBytes,total<=maximumBatchBytes-size else {throw CirclrError("파일당 2 GiB·한 번에 4 GiB 이하의 일반 오디오 파일을 선택하세요")}
            sizes.append(size);total+=size
        }
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let directory=root.appendingPathComponent("import-"+UUID().uuidString)
        try fm.createDirectory(at:directory,withIntermediateDirectories:false)
        var retained=false;defer{if !retained{try? fm.removeItem(at:directory)}}
        var assets:[Asset]=[],processed:Int64=0,lastPercent = -1
        for (i,url) in urls.enumerated() {
            try Task.checkCancellation()
            var asset=Asset(name:url.lastPathComponent,path:"",duration:0,sampleRate:0)
            let target=directory.appendingPathComponent(asset.id+"."+url.pathExtension.lowercased())
            asset.checksum=try copy(url,to:target,expected:sizes[i]){copied in
                let fraction=Double(processed+copied)/Double(total),percent=Int(fraction*100)
                if percent != lastPercent {lastPercent=percent;progress(fraction)}
            }
            try Task.checkCancellation()
            let file:AVAudioFile
            do {file=try AVAudioFile(forReading:target)}
            catch {throw CirclrError("오디오를 읽을 수 없습니다: \(asset.name). 파일 형식과 손상 여부를 확인하세요")}
            let rate=file.processingFormat.sampleRate
            guard rate.isFinite,rate>0,file.length>0,file.processingFormat.channelCount>0,file.processingFormat.channelCount<=2 else {throw CirclrError("Mono 또는 stereo 오디오를 선택하세요: \(asset.name)")}
            let duration=Double(file.length)/rate
            guard duration.isFinite,duration>0,duration<=3600 else {throw CirclrError("오디오 길이는 1시간 이하여야 합니다")}
            asset.path=target.path;asset.duration=duration;asset.sampleRate=rate;assets.append(asset);processed+=sizes[i]
        }
        try Task.checkCancellation();retained=true;progress(1)
        return StagedAudioImport(directory:directory,assets:assets)
    }
    private static func copy(_ source:URL,to target:URL,expected:Int64,progress:(Int64)->Void)throws->String {
        let input=try FileHandle(forReadingFrom:source);defer{try? input.close()}
        guard FileManager.default.createFile(atPath:target.path,contents:nil) else {throw CirclrError("오디오 복사본을 만들 수 없습니다")}
        let output=try FileHandle(forWritingTo:target);defer{try? output.close()}
        var hash=SHA256(),count:Int64=0
        while let bytes=try input.read(upToCount:1_048_576),!bytes.isEmpty {
            try Task.checkCancellation();count+=Int64(bytes.count)
            guard count<=expected else {throw CirclrError("읽는 동안 파일 크기가 바뀌었습니다. 다시 가져오세요")}
            try output.write(contentsOf:bytes);hash.update(data:bytes);progress(count)
        }
        guard count==expected else {throw CirclrError("오디오 파일을 끝까지 읽지 못했습니다")}
        try output.synchronize()
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
}
