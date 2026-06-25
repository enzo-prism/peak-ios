import Foundation

extension String {
    var normalizedKey: String {
        let parts = components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ").lowercased()
    }

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Case- and diacritic-insensitive form for matching user-typed queries against catalog text
    /// (so "sao", "São" and "SÃO" all match).
    var searchFolded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
    }
}
