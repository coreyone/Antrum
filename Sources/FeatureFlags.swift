import Foundation

enum FeatureFlags {
    static let dictationKey = "FeatureFlags.Dictation"

    static func dictation(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if let override = environment["ANTRUM_FEATURE_DICTATION"]?.lowercased() {
            return ["1", "true", "yes", "on"].contains(override)
        }
        if let override = defaults.object(forKey: dictationKey) as? Bool {
            return override
        }
        return true
    }
}
