import Foundation
import CoreFoundation

/// App-local workspace preferences. UserDefaults.standard uses the current app's
/// bundle domain, so integration QA cannot overwrite the desktop app's choices.
struct ConsolePreferences {
    static let openKey="circlr.workspace.console.open"
    static let heightKey="circlr.workspace.console.logHeight"
    static let defaultHeight=122.0
    private let defaults:UserDefaults

    init(defaults:UserDefaults = .standard) {self.defaults=defaults}

    var isOpen:Bool {Self.decodeOpen(defaults.object(forKey:Self.openKey))}
    var logHeight:Double {Self.decodeHeight(defaults.object(forKey:Self.heightKey))}

    static func decodeOpen(_ value:Any?)->Bool {
        guard let number=value as? NSNumber,CFGetTypeID(number)==CFBooleanGetTypeID() else{return true}
        return number.boolValue
    }

    static func decodeHeight(_ value:Any?)->Double {
        guard let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID() else{return defaultHeight}
        return boundedHeight(number.doubleValue)
    }

    static func boundedHeight(_ height:Double)->Double {
        guard height.isFinite else{return defaultHeight}
        return min(180,max(40,height))
    }

    func saveOpen(_ open:Bool) {defaults.set(open,forKey:Self.openKey)}
    func saveHeight(_ height:Double) {defaults.set(Self.boundedHeight(height),forKey:Self.heightKey)}
}
