import Foundation

/// An app-local recording preference. Selecting a UID never changes the macOS default.
public enum InputDeviceSelection:Codable,Equatable,Sendable {
    case systemDefault
    case deviceUID(String)

    public func validate() throws {
        if case .deviceUID(let uid)=self {
            guard !uid.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  uid.utf8.count<=1024,
                  !uid.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) else {
                throw InputDeviceBindingError.invalidSelection
            }
        }
    }
}

public struct InputDeviceDescriptor:Codable,Equatable,Sendable {
    public let uid:String
    public let name:String
    public let isDefault:Bool
    public init(uid:String,name:String,isDefault:Bool){self.uid=uid;self.name=name;self.isDefault=isDefault}
}
