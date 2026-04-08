import Foundation

struct AnalysisDisplaySection: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [String]
}

enum AnalysisResponseFormatter {
    private static let requiredTitles = [
        "What You Did",
        "Patterns That Matter",
        "Recommended Adjustment",
    ]

    private static let optionalTitles = [
        "Biggest Shifts",
        "Top Apps by Time",
        "Summary of Focus and Reactive Work",
        "Conclusion",
    ]

    private static let allTitles = requiredTitles + optionalTitles
    private static let headingRegex = try! NSRegularExpression(pattern: #"(?m)^##\s+(.+)$"#)
    private static let listItemRegex = try! NSRegularExpression(pattern: #"^\s*(?:[-*•]|\d+\.)\s+(.+)$"#)

    static func sanitize(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.isEmpty else { return result }

        result = normalizeHeadings(in: result)
        result = rewriteFirstPerson(in: result)
        result = collapseSpacing(in: result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sections(from text: String) -> [AnalysisDisplaySection] {
        let sanitized = sanitize(text)
        let nsText = sanitized as NSString
        let matches = headingRegex.matches(in: sanitized, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return [] }

        var sections: [AnalysisDisplaySection] = []
        for index in matches.indices {
            let title = nsText.substring(with: matches[index].range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyStart = matches[index].range.location + matches[index].range.length
            let bodyEnd = index < matches.index(before: matches.endIndex)
                ? matches[index + 1].range.location
                : nsText.length
            let bodyRange = NSRange(location: bodyStart, length: max(0, bodyEnd - bodyStart))
            let body = nsText.substring(with: bodyRange)
            let items = bodyItems(from: body)

            guard !items.isEmpty else { continue }
            sections.append(AnalysisDisplaySection(id: "\(title)-\(index)", title: title, items: items))
        }

        return sections
    }

    static func violatesContract(_ text: String) -> Bool {
        let sanitized = sanitize(text)
        let lowered = sanitized.lowercased()
        let hasFirstPerson = lowered.contains(" i ")
            || lowered.hasPrefix("i ")
            || lowered.contains("\ni ")
            || lowered.contains(" my ")
            || lowered.contains(" me ")
            || lowered.contains(" we ")
            || lowered.contains(" our ")
        let hasRequiredSections = requiredTitles.allSatisfy { sanitized.contains("## \($0)") }
        return hasFirstPerson || !hasRequiredSections
    }

    private static func bodyItems(from body: String) -> [String] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lines = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let listItems = lines.compactMap(strippedListItem(from:))
        if !listItems.isEmpty, listItems.count >= max(1, lines.count / 2) {
            return listItems
        }

        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if paragraphs.count > 1 {
            return paragraphs
        }

        let labeledParts = split(trimmed, pattern: #"(?<!^)(?=\s*[A-Z][A-Za-z0-9&/+ \-]{2,30}:)"#)
        if labeledParts.count > 1 {
            return labeledParts
        }

        let sentenceParts = split(trimmed, pattern: #"(?<=[.!?])\s+(?=[A-Z])"#)
        return sentenceParts.isEmpty ? [trimmed] : sentenceParts
    }

    private static func strippedListItem(from line: String) -> String? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = listItemRegex.firstMatch(in: line, range: range) else {
            return nil
        }
        return nsLine.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func split(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return [] }

        var parts: [String] = []
        var cursor = 0
        for match in matches {
            let location = match.range.location
            let range = NSRange(location: cursor, length: max(0, location - cursor))
            let piece = nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                parts.append(piece)
            }
            cursor = location
        }

        let tail = nsText.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            parts.append(tail)
        }
        return parts
    }

    private static func rewriteFirstPerson(in text: String) -> String {
        var result = text

        let replacements: [(pattern: String, replacement: String)] = [
            (#"\bI’m\b"#, "You're"),
            (#"\bI'm\b"#, "You're"),
            (#"\bI’ve\b"#, "You've"),
            (#"\bI've\b"#, "You've"),
            (#"\bI’d\b"#, "You'd"),
            (#"\bI'd\b"#, "You'd"),
            (#"\bI’ll\b"#, "You'll"),
            (#"\bI'll\b"#, "You'll"),
            (#"\bI\b"#, "You"),
            (#"\bMe\b"#, "You"),
            (#"\bme\b"#, "you"),
            (#"\bMy\b"#, "Your"),
            (#"\bmy\b"#, "your"),
            (#"\bMine\b"#, "Yours"),
            (#"\bmine\b"#, "yours"),
            (#"\bWe\b"#, "You"),
            (#"\bwe\b"#, "you"),
            (#"\bOur\b"#, "Your"),
            (#"\bour\b"#, "your"),
            (#"\bOurs\b"#, "Yours"),
            (#"\bours\b"#, "yours"),
        ]

        for replacement in replacements {
            guard let regex = try? NSRegularExpression(pattern: replacement.pattern) else { continue }
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement.replacement)
        }

        let grammarFixes: [(pattern: String, replacement: String)] = [
            (#"\byou am\b"#, "you are"),
            (#"\bYou am\b"#, "You are"),
            (#"\byou was\b"#, "you were"),
            (#"\bYou was\b"#, "You were"),
        ]

        for fix in grammarFixes {
            guard let regex = try? NSRegularExpression(pattern: fix.pattern) else { continue }
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: fix.replacement)
        }

        return result
    }

    private static func normalizeHeadings(in text: String) -> String {
        var result = text
        var tokens: [(token: String, title: String)] = []

        for (index, title) in allTitles.enumerated() {
            let token = "<<SECTION_\(index)>>"
            tokens.append((token, title))

            for variant in ["## \(title)", "### \(title)", "# \(title)"] {
                result = result.replacingOccurrences(of: variant, with: token)
            }
            result = replaceBareTitle(title, with: token, in: result)
            result = result.replacingOccurrences(of: "\(token):", with: token)
        }

        for token in tokens {
            result = result.replacingOccurrences(of: token.token, with: "\n## \(token.title)\n")
        }

        return result
    }

    private static func replaceBareTitle(_ title: String, with token: String, in text: String) -> String {
        let escapedTitle = NSRegularExpression.escapedPattern(for: title)
        let pattern = #"(?m)(^|(?<=[.!?]\s)|(?<=\n))\s*\#(escapedTitle)(?=[:\n]|[A-Z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            let fullRange = match.range(at: 0)
            let prefix = match.range(at: 1).location != NSNotFound ? nsText.substring(with: match.range(at: 1)) : ""
            let replacement = prefix + token
            let start = result.index(result.startIndex, offsetBy: fullRange.location)
            let end = result.index(start, offsetBy: fullRange.length)
            result.replaceSubrange(start..<end, with: replacement)
        }
        return result
    }

    private static func collapseSpacing(in text: String) -> String {
        let trimmedLines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        guard let regex = try? NSRegularExpression(pattern: #"\n{3,}"#) else {
            return trimmedLines
        }
        let range = NSRange(location: 0, length: (trimmedLines as NSString).length)
        return regex.stringByReplacingMatches(in: trimmedLines, range: range, withTemplate: "\n\n")
    }
}
