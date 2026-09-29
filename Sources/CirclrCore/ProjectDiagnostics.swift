import Foundation

/// An explicit support projection. Never encode Project, media issues, errors,
/// activity logs, job messages, identifiers, or other arbitrary model objects.
public struct ProjectDiagnostics: Encodable {
    public enum IssueCode: String, Encodable { case mediaSourceIssue = "media_source_issue", structureInvalid = "project_structure_invalid" }
    public enum JobKind: String, Encodable { case none, bounce, export, save, open, importMIDI = "import_midi", other }
    public enum JobState: String, Encodable { case idle, running, completed, failed, cancelled, unknown }
    public struct Runtime: Encodable {
        public let playbackPlaying: Bool
        public let playbackPreparing: Bool
        public let midiRecording: Bool
        public let audioRecording: Bool
        public let audioRecordingBusy: Bool
        public let audioRecordingPending: Bool
        public let jobKind: JobKind
        public let jobState: JobState
        public init(playbackPlaying: Bool = false, playbackPreparing: Bool = false,
                    midiRecording: Bool = false, audioRecording: Bool = false,
                    audioRecordingBusy: Bool = false, audioRecordingPending: Bool = false,
                    jobKind: JobKind = .none, jobState: JobState = .idle) {
            self.playbackPlaying = playbackPlaying; self.playbackPreparing = playbackPreparing
            self.midiRecording = midiRecording; self.audioRecording = audioRecording
            self.audioRecordingBusy = audioRecordingBusy; self.audioRecordingPending = audioRecordingPending
            self.jobKind = jobKind; self.jobState = jobState
        }
    }
    public struct Counts: Encodable {
        public let tracks: Int
        public let sections: Int
        public let arrangements: Int
        public let sectionUses: Int
        public let sharedPatterns: Int
        public let assets: Int
        public let recordedTakes: Int
        public let signalNodes: Int
        public let signalEdges: Int
    }
    public struct MediaHealth: Encodable {
        /// Reuses the application's source inspector; no audio-quality claim.
        public let check = "media_source_inspection"
        public let healthy: Int
        public let issues: Int
        public let unchecked: Int
    }
    public let format = "circlr-project-diagnostics-v1"
    public let appVersion: String
    public let appBuild: String
    public let projectSchema: Int
    public let musicRevision: Int
    public let counts: Counts
    public let mediaHealth: MediaHealth
    public let issues: [IssueCode]
    public let runtime: Runtime

    public init(project: Project, mediaRoot: URL?, appVersion: String, appBuild: String, runtime: Runtime = Runtime(),
                checkCancellation: () throws -> Void = {}) throws {
        try checkCancellation()
        // Bundle metadata is expected to be numeric. Unexpected values are not
        // copied into a support artifact even if a caller supplies private text.
        self.appVersion = Self.numericVersion(appVersion) ? appVersion : "unknown"
        self.appBuild = !appBuild.isEmpty && appBuild.utf8.count <= 20 && appBuild.utf8.allSatisfy({ (48...57).contains($0) }) ? appBuild : "unknown"
        projectSchema = project.schemaVersion
        musicRevision = project.musicRevision
        counts = Counts(tracks: project.tracks.count, sections: project.sections.count,
            arrangements: project.arrangements.count, sectionUses: project.arrangements.reduce(0) { $0 + $1.uses.count },
            sharedPatterns: project.patterns.count, assets: project.assets.count,
            recordedTakes: project.takes?.count ?? 0, signalNodes: project.signal.nodes.count,
            signalEdges: project.signal.edges.count)
        // Reuse the existing media inspector; only its aggregate count crosses
        // this boundary. Its asset IDs, display names and reason text do not.
        let unavailable = try ProjectMediaRelink.diagnostics(project: project, root: mediaRoot,
            checkCancellation: checkCancellation).count
        try checkCancellation()
        mediaHealth = MediaHealth(healthy: project.assets.count - unavailable, issues: unavailable, unchecked: 0)
        var codes: [IssueCode] = unavailable > 0 ? [.mediaSourceIssue] : []
        do { try ProjectStore.validateStructure(project) } catch { codes.append(.structureInvalid) }
        issues = codes
        self.runtime = runtime
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    private static func numericVersion(_ value: String) -> Bool {
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        return value.utf8.count <= 32 && (1...4).contains(pieces.count) && pieces.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
        }
    }
}
