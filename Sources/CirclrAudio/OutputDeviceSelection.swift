import Foundation

/// App preference, independent of a project and its musical revision.
public enum OutputDeviceSelection: Codable, Equatable, Sendable {
    case systemDefault
    case deviceUID(String)

    public func validate() throws {
        if case .deviceUID(let uid) = self {
            guard !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  uid.utf8.count <= 1024,
                  !uid.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw OutputDeviceBindingError.invalidSelection
            }
        }
    }
}
