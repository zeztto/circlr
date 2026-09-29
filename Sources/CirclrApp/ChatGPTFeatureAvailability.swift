import Foundation
import CoreFoundation

/// Account chat is opt-in for explicitly enabled QA bundles. A saved console
/// preference cannot enable an unavailable account feature in a release bundle.
struct ChatGPTFeatureAvailability {
    let accountChatEnabled: Bool
    init(info: [String: Any]?) {
        if let value = info?["CirclrAccountChatEnabled"] as? NSNumber,
           CFGetTypeID(value) == CFBooleanGetTypeID() {
            accountChatEnabled = value.boolValue
        } else { accountChatEnabled = false }
    }
    func consoleMode(preferred: ChatGPTConsoleMode) -> ChatGPTConsoleMode {
        accountChatEnabled ? preferred : .command
    }
    static let current = ChatGPTFeatureAvailability(info: Bundle.main.infoDictionary)
}
