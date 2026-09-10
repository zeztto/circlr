import Foundation

/// Storage validation does not imply that a renderer can play the expression.
public enum MIDIPitchBendStorage {
    private static func sequences(in project:Project)->[MIDIPitchBendSequence] {
        var sequences=project.sections.flatMap(\.lanes).compactMap(\.pitchBend)
        for arrangement in project.arrangements {for use in arrangement.uses {
            sequences+=use.laneOverrides.values.compactMap(\.pitchBend)
            sequences+=use.addedLanes.compactMap(\.pitchBend)
        }}
        sequences+=project.patterns.compactMap(\.pitchBend)
        sequences+=(project.takes ?? []).compactMap{$0.lane.pitchBend}
        return sequences
    }
    public static func validate(in project:Project)throws {
        let values=sequences(in:project)
        guard values.isEmpty || project.schemaVersion>=5 else{throw CirclrError("피치 벤드 저장에는 version 5 프로젝트가 필요합니다")}
        for value in values {try value.validate()}
    }
    /// Called only by an explicit edit. Failure leaves even the schema unchanged.
    public static func promote(in project:inout Project)throws {
        let values=sequences(in:project)
        for value in values {try value.validate()}
        if !values.isEmpty {project.schemaVersion=max(5,project.schemaVersion)}
    }
}
