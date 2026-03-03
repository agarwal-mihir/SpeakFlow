import Foundation

enum LanguageNormalizer {
    private static let multiSpace = try! NSRegularExpression(pattern: "\\s+", options: [])
    private static let devanagariRegex = try! NSRegularExpression(pattern: "[\\u0900-\\u097F]", options: [])

    static func decideOutputMode(languageMode: String, text: String, detectedLanguage: String?) -> String {
        if languageMode == "english" { return "english" }
        if languageMode == "hinglish_roman" { return "hinglish_roman" }

        let hasDevanagari = devanagariRegex.firstMatch(
            in: text,
            options: [],
            range: NSRange(location: 0, length: (text as NSString).length)
        ) != nil
        if hasDevanagari { return "hinglish_roman" }
        if detectedLanguage == "hi" { return "hinglish_roman" }
        return "english"
    }

    static func normalizeEnglish(_ text: String) -> String {
        var out = collapseSpace(text)
        if out.isEmpty { return out }
        out = out.prefix(1).uppercased() + out.dropFirst()
        if let last = out.last, ".!?".contains(last) {
            return out
        }
        return out + "."
    }

    static func normalizeHinglishRoman(_ text: String) -> String {
        var out = text
        out = transliterateDevanagariTokenByToken(out)
        out = collapseSpace(out)
        if out.isEmpty { return out }
        out = out.prefix(1).uppercased() + out.dropFirst()
        if let last = out.last, ".!?".contains(last) {
            return out
        }
        return out + "."
    }

    static func collapseSpace(_ text: String) -> String {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let collapsed = multiSpace.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func transliterateDevanagariTokenByToken(_ text: String) -> String {
        // Lightweight transliteration path for mixed-script utterances.
        guard let transform = NSMutableString(string: text).mutableCopy() as? NSMutableString else { return text }
        CFStringTransform(transform, nil, kCFStringTransformToLatin, false)
        CFStringTransform(transform, nil, kCFStringTransformStripCombiningMarks, false)
        return transform as String
    }
}
