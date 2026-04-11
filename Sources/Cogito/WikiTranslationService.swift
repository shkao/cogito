import Foundation

struct WikiTranslation {
    let sourceWord: String
    let targetTitle: String
    let description: String?
}

enum WikiTranslationError: LocalizedError {
    case noArticleFound
    case noTranslation

    var errorDescription: String? {
        switch self {
        case .noArticleFound: return "No Wikipedia article found"
        case .noTranslation:  return "No translation available"
        }
    }
}

struct WikiTranslationService {

    static func translate(word: String, targetLang: String) async throws -> WikiTranslation {
        let targetTitle = try await fetchTargetTitle(word: word, targetLang: targetLang)
        let description = try? await fetchDescription(title: targetTitle, lang: targetLang)
        return WikiTranslation(sourceWord: word, targetTitle: targetTitle, description: description)
    }

    private static func fetchTargetTitle(word: String, targetLang: String) async throws -> String {
        var comps = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        comps.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "prop", value: "langlinks"),
            URLQueryItem(name: "titles", value: word),
            URLQueryItem(name: "lllang", value: targetLang),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = comps.url else { throw WikiTranslationError.noArticleFound }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json   = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query  = json["query"]  as? [String: Any],
              let pages  = query["pages"] as? [String: Any],
              let page   = pages.values.first as? [String: Any],
              page["missing"] == nil
        else { throw WikiTranslationError.noArticleFound }

        guard let links = page["langlinks"] as? [[String: Any]],
              let first = links.first,
              let title = first["*"] as? String
        else { throw WikiTranslationError.noTranslation }

        return title
    }

    private static func fetchDescription(title: String, lang: String) async throws -> String {
        let baseLang = lang.components(separatedBy: "-").first ?? lang
        let encoded  = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://\(baseLang).wikipedia.org/api/rest_v1/page/summary/\(encoded)") else { return "" }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let desc = json["description"] as? String
        else { return "" }

        return desc
    }
}
