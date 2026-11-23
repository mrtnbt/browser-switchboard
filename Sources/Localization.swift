import Foundation

enum AppLanguage: String, CaseIterable {
    case system, english, german

    static func preferred(from languages: [String]) -> AppLanguage {
        for language in languages {
            switch language.split(separator: "-").first?.lowercased() {
            case "de": return .german
            case "en": return .english
            default: continue
            }
        }
        return .english
    }

    var label: String {
        switch self {
        case .system: return ""
        case .english: return "English"
        case .german: return "Deutsch"
        }
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        let language = self == .system ? Self.preferred(from: Locale.preferredLanguages) : self
        let code = language == .german ? "de" : "en"
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        let translation = bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
        return arguments.isEmpty ? translation : String(format: translation, locale: Locale(identifier: code), arguments: arguments)
    }
}
