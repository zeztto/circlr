import Foundation

/// Storage support alone does not authorize rendering or exporting pedal expression.
public enum MIDISustainStorage {
    public static func validate(sustain: MIDISustainSequence?, pitchBend: MIDIPitchBendSequence?) throws {
        guard let sustain else { return }
        try sustain.validate()
        if let pitchBend {
            try pitchBend.validate()
            guard sustain.channel == pitchBend.channel else {
                throw CirclrError("같은 MIDI 소스의 Sustain과 피치 벤드 채널은 같아야 합니다")
            }
        }
    }
    private static func inspect(_ project: Project) throws -> Bool {
        var found = false
        func check(_ sustain: MIDISustainSequence?, _ bend: MIDIPitchBendSequence?) throws {
            try validate(sustain: sustain, pitchBend: bend)
            if sustain != nil { found = true }
        }
        for section in project.sections { for lane in section.lanes { try check(lane.sustain, lane.pitchBend) } }
        for arrangement in project.arrangements { for use in arrangement.uses {
            for lane in use.laneOverrides.values { try check(lane.sustain, lane.pitchBend) }
            for lane in use.addedLanes { try check(lane.sustain, lane.pitchBend) }
        } }
        for pattern in project.patterns { try check(pattern.sustain, pattern.pitchBend) }
        for take in project.takes ?? [] { try check(take.lane.sustain, take.lane.pitchBend) }
        return found
    }
    public static func validate(in project: Project) throws {
        let found = try inspect(project)
        guard !found || project.schemaVersion >= 7 else {
            throw CirclrError("Sustain 저장에는 version 7 프로젝트가 필요합니다")
        }
    }
    /// Explicit edits only. Validate every stored scope before changing the schema.
    public static func promote(in project: inout Project) throws {
        if try inspect(project) { project.schemaVersion = max(7, project.schemaVersion) }
    }
}
