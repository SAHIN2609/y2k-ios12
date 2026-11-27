//
//  AppLanguage.swift
//  y2k
//
//  The original ships 21 localisations (English, Arabic, Bengali, French,
//  German, Hindi, Indonesian, Italian, Japanese, Marathi, Portuguese, Russian,
//  Simplified/Traditional Chinese, Spanish, Tamil, Telugu, Turkish, Ukrainian,
//  Urdu, Vietnamese). This clone keeps the subset that has a bundled .lproj and
//  falls back to the system language, exactly like the original's
//  AppLanguageManager.
//

import Foundation

final class AppLanguageManager {
    static let shared = AppLanguageManager()

    private let defaultsKey = "y2k_selected_language"

    struct Language {
        let code: String      // lproj name
        let endonym: String   // name in its own language
        let englishName: String
    }

    /// Languages that actually have strings in this build.
    let available: [Language] = [
        .init(code: "en", endonym: "English", englishName: "English"),
        .init(code: "ar", endonym: "العربية", englishName: "Arabic"),
        .init(code: "de", endonym: "Deutsch", englishName: "German"),
        .init(code: "es", endonym: "Español", englishName: "Spanish"),
        .init(code: "fr", endonym: "Français", englishName: "French"),
        .init(code: "hi", endonym: "हिन्दी", englishName: "Hindi"),
        .init(code: "it", endonym: "Italiano", englishName: "Italian"),
        .init(code: "pt-BR", endonym: "Português", englishName: "Portuguese"),
        .init(code: "ru", endonym: "Русский", englishName: "Russian"),
        .init(code: "uk", endonym: "Українська", englishName: "Ukrainian"),
        .init(code: "zh-Hant", endonym: "繁體中文", englishName: "Chinese (Traditional)")
    ]

    var currentCode: String {
        get {
            if let stored = UserDefaults.standard.string(forKey: defaultsKey) { return stored }
            let preferred = Locale.preferredLanguages.first ?? "en"
            if let match = available.first(where: { preferred.hasPrefix($0.code) }) {
                return match.code
            }
            return "en"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }

    /// Localised lookup against the bundled bundle for the chosen language.
    func string(_ key: String) -> String {
        let code = currentCode
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Shortcut used everywhere instead of NSLocalizedString so language switches
/// take effect without a relaunch.
func Y2KString(_ key: String) -> String {
    return AppLanguageManager.shared.string(key)
}
