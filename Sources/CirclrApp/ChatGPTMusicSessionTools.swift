import Foundation
import CirclrCore
import CirclrCodex

/// Strict schemas expose only musical arguments, never authority or filesystem destinations.
enum ChatGPTMusicTools {
    private static let string: CodexJSONValue = .object(["type": .string("string")])
    private static let integer: CodexJSONValue = .object(["type": .string("integer")])
    private static let number: CodexJSONValue = .object(["type": .string("number")])
    private static func object(_ fields: [String: CodexJSONValue]) -> CodexJSONValue {
        .object(["type": .string("object"), "properties": .object(fields),
                 "required": .array(fields.keys.sorted().map { .string($0) }), "additionalProperties": .bool(false)])
    }
    private static var binding: [String: CodexJSONValue] {
        ["projectID": string, "expectedRevision": integer, "arrangementID": string, "useID": string]
    }
    static var functions: [SIWCResponsesFunctionTool] {
        var notes = binding; notes["laneID"] = string; notes["append"] = .object(["type": .string("boolean")])
        notes["notes"] = .object(["type": .string("array"), "maxItems": .integer(256), "items": object([
            "beat": number, "duration": number, "pitch": integer, "velocity": integer])])
        var bounce = binding; bounce["trackID"] = string; bounce["tailSeconds"] = number
        return [
            .init(name: "read_selection", description: "Read the currently app-authorized section and MIDI lane, including up to 256 notes and fresh revision. If total exceeds 256, replacement is unavailable; append remains available. No arguments. Read again after a revision conflict.", parameters: object([:])),
            .init(name: "set_notes", description: "Replace or append MIDI notes on the selected lane in one undoable edit. Beats and duration are quarter notes; pitch 0..127, velocity 1..127. Replacement requires a complete read at the exact observed revision; read again after each edit.", parameters: object(notes)),
            .init(name: "bounce", description: "Render the selected section track to an audio circle. Returns asynchronous jobID. tailSeconds 0..120. No file path accepted.", parameters: object(bounce)),
            .init(name: "save_current_project", description: "Save the already-open project at its user-selected location. New unsaved projects cannot be saved by AI. Returns asynchronous jobID.", parameters: object(["projectID": string, "expectedRevision": integer])),
            .init(name: "job", description: "Read this turn's asynchronous job. Continue until completed or failed before reporting completion.", parameters: object(["projectID": string, "jobID": string]))
        ]
    }
    static func request(_ call: SIWCResponsesFunctionCall) throws -> AgentRequest {
        guard let raw = call.arguments.object,
              let schema = functions.first(where: { $0.name == call.name }),
              let allowed = schema.parameters["properties"]?.object,
              Set(raw.keys) == Set(allowed.keys),
              let projectID = raw["projectID"]?.string else { throw SIWCResponsesError.invalidRequest }
        var args = raw
        args.removeValue(forKey: "projectID")
        let revision = args.removeValue(forKey: "expectedRevision")
        var method: String
        switch call.name {
        case "read_selection": method = "inspect"
        case "set_notes":
            method = "apply"
            guard case .array(let notes)? = args["notes"], notes.count <= 256 else { throw SIWCResponsesError.invalidRequest }
            // Note's generated identity is app-owned, not model-controlled.
            let parsed = try notes.map { value -> Note in
                guard let object = value.object, Set(object.keys) == ["beat", "duration", "pitch", "velocity"] else { throw SIWCResponsesError.invalidRequest }
                struct Input: Decodable { let beat: Double; let duration: Double; let pitch: Int; let velocity: Int }
                let n = try JSONDecoder().decode(Input.self, from: JSONEncoder().encode(value))
                guard n.beat.isFinite, n.beat >= 0, n.duration.isFinite, n.duration > 0,
                      (0...127).contains(n.pitch), (1...127).contains(n.velocity) else { throw SIWCResponsesError.invalidRequest }
                return Note(beat: n.beat, length: n.duration, pitch: n.pitch, velocity: n.velocity)
            }
            args["notes"] = try JSONDecoder().decode(CodexJSONValue.self, from: JSONEncoder().encode(parsed))
            args["kind"] = .string("set_notes")
            args = ["operations": .array([.object(args)])]
        case "bounce": method = "bounce"
        case "job": method = "job"
        case "save_current_project": method = "save"
        default: throw SIWCResponsesError.invalidRequest
        }
        var request: [String: CodexJSONValue] = ["id": .string(UUID().uuidString), "method": .string(method),
            "projectID": .string(projectID), "arguments": .object(args)]
        if let revision { request["expectedRevision"] = revision }
        return try JSONDecoder().decode(AgentRequest.self, from: JSONEncoder().encode(CodexJSONValue.object(request)))
    }
}
