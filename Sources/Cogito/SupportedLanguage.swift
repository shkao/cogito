import Foundation

struct SupportedLanguage {
    let code: String
    let label: String
    let englishName: String

    static let all: [SupportedLanguage] = [
        SupportedLanguage(code: "zh-tw", label: "繁體中文", englishName: "Traditional Chinese (繁體中文)"),
        SupportedLanguage(code: "ja", label: "日本語", englishName: "Japanese"),
        SupportedLanguage(code: "es", label: "Español", englishName: "Spanish"),
        SupportedLanguage(code: "fr", label: "Français", englishName: "French"),
        SupportedLanguage(code: "de", label: "Deutsch", englishName: "German"),
        SupportedLanguage(code: "ko", label: "한국어", englishName: "Korean"),
        SupportedLanguage(code: "pt", label: "Português", englishName: "Portuguese"),
        SupportedLanguage(code: "it", label: "Italiano", englishName: "Italian"),
    ]

    static func englishName(for code: String) -> String {
        all.first { $0.code == code }?.englishName ?? "Chinese"
    }
}
