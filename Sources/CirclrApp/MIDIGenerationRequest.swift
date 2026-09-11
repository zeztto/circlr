import CirclrCore

/// The menu describes exactly this append operation, including the cursor before normalization.
struct MIDIGenerationRequest:Equatable {
    let identity:NumberEditIdentity
    let cursor:Double
    let start:Double
    let end:Double
    let context:MusicContext
    var duration:Double {end-start}
    var rangeLabel:String {
        "\(NumberEditSession<Int>.format(start+1))박부터 · 남은 \(NumberEditSession<Int>.format(duration))박"
    }
}

extension AppStore {
    var midiGenerationRequest:MIDIGenerationRequest? {
        guard currentLane != nil,selectedBeat.isFinite,editorBeats.isFinite,editorBeats>0 else{return nil}
        let start=max(0,min(editorBeats-0.03125,selectedBeat))
        return MIDIGenerationRequest(identity:numberEditIdentity,cursor:selectedBeat,start:start,end:editorBeats,context:currentContext)
    }
}

/// Native Menu content must refresh when its displayed generation request changes.
struct MIDIGenerationMenuIdentity:Hashable {
    let request:MIDIGenerationRequest?
    static func == (lhs:Self,rhs:Self)->Bool {lhs.request==rhs.request}
    func hash(into hasher:inout Hasher) {
        hasher.combine(request?.identity.projectID)
        hasher.combine(request?.identity.revision)
        hasher.combine(request?.cursor)
        hasher.combine(request?.end)
    }
}
