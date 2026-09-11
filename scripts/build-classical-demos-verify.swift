// Offline verification against circlr's actual decoder, compiler and MIDI importer.
// Link against the existing CirclrCore/CirclrAudio build; never opens an audio device.
import Foundation
import CirclrCore
import CirclrAudio

@main struct ClassicalDemoVerifier {
static func main() async throws {
let root=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1]:FileManager.default.currentDirectoryPath)
func signature(_ n:Note,offset:Double=0)->String {
    "\(Int(((n.beat+offset)*384).rounded())):\(Int((n.length*384).rounded())):\(n.pitch):\(n.velocity)"
}
for slug in ["bach-invention-08","bach-invention-07","fur-elise"] {
    let folder=root.appendingPathComponent("Resources/Demos/classical/\(slug)")
    let p=try ProjectStore.load(folder.appendingPathComponent("\(slug).circlr")).project
    try ProjectStore.validateStructure(p)
    let plan=try ArrangementCompiler.compile(p)
    let midi=try MIDIImport.read(Data(contentsOf:folder.appendingPathComponent("source.mid")))
    precondition(midi.tracks.count==2 && p.tracks.count==2)
    precondition(p.assets.isEmpty && plan.warnings.isEmpty)
    for (index,track) in p.tracks.enumerated() {
        var rebuilt:[String]=[];var offset=0.0
        for occurrence in plan.occurrences {
            let notes=occurrence.lanes.filter{$0.trackID==track.id}.flatMap(\.notes)
            rebuilt += notes.map{signature($0,offset:offset)}
            offset += Double(occurrence.section.bars)*Double(p.global.meter.numerator)*4/Double(p.global.meter.denominator)
        }
        precondition(rebuilt.sorted()==midi.tracks[index].notes.map{signature($0)}.sorted(),"MIDI mismatch \(slug) voice \(index)")
    }
    if CommandLine.arguments.contains("--render") {
        let audio=try await ArrangementRenderer.render(project:p,root:folder.appendingPathComponent("\(slug).circlr"),plan:plan,tailSeconds:2,includeStems:false)
        precondition(audio.mix.left.allSatisfy(\.isFinite) && audio.mix.right.allSatisfy(\.isFinite))
        precondition(audio.peak>0.01 && audio.peak<1)
        precondition(abs(audio.mix.duration-plan.duration-2)<1/PCM.rate)
        let output=root.appendingPathComponent("qa/generated/r40/classical")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        try AudioExport.save(audio,to:output.appendingPathComponent("\(slug).wav"))
        let sum=zip(audio.mix.left,audio.mix.right).reduce(0.0){$0+Double($1.0)*Double($1.0)+Double($1.1)*Double($1.1)}
        let report:[String:Any]=["slug":slug,"bodySeconds":plan.duration,"tailSeconds":audio.tailSeconds,"frames":audio.mix.count,"sampleRate":PCM.rate,"peak":audio.peak,"rms":sqrt(sum/Double(audio.mix.count*2)),"finite":true,"noteComparison":"PASS"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("\(slug).json"))
        print("\(slug): offline render PASS peak=\(audio.peak) frames=\(audio.mix.count)")
    }
    print("\(slug): decode/structure/compiler/MIDIImport PASS; \(plan.occurrences.count) sections; \(plan.duration) seconds")
}

}
}
