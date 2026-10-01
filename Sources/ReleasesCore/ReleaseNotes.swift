import Foundation

/// One change in a release: a bullet from the notes or the changelog.
public struct Change: Codable, Hashable, Sendable {
  /// The whole bullet, as Markdown.
  public var text: String
  /// The bold lead-in without its period, like "Updates from inside the app", or the first sentence.
  public var headline: String
  /// The Markdown after the bold lead-in. Empty when there's none.
  public var detail: String
  public var hasLeadIn: Bool

  public init(_ text: String) {
    self.text = text
    if text.hasPrefix("**"), let close = text.dropFirst(2).range(of: "**") {
      let lead = text[text.index(text.startIndex, offsetBy: 2)..<close.lowerBound]
      headline = String(lead).trimmingCharacters(in: CharacterSet(charactersIn: ".:").union(.whitespaces))
      detail = text[close.upperBound...].trimmingCharacters(in: .whitespaces)
      hasLeadIn = true
    } else if let end = text.range(of: ". ") {
      headline = String(text[..<end.lowerBound])
      detail = String(text[end.upperBound...])
      hasLeadIn = false
    } else {
      headline = text.trimmingCharacters(in: CharacterSet(charactersIn: "."))
      detail = ""
      hasLeadIn = false
    }
  }
}

/// Pulls the changes out of release notes, leaving out the intro, the install steps and the checksum.
public enum ReleaseNotes {
  /// Headings whose bullets are changes.
  static func isChangeHeading(_ title: String) -> Bool {
    title.firstMatch(of: /(?i)^(what['’]?s\s+(new|in|changed|fixed)|changes|changelog|change\s+log|highlights|new|features|improvements|fixes|fixed|bug\s+fixes|added|changed|removed)\b/) != nil
  }

  /// Headings whose bullets never are changes.
  static func isOtherHeading(_ title: String) -> Bool {
    title.firstMatch(of: /(?i)^(install|installation|upgrading|download|requirements|checksums?|sha|verify|getting\s+started|usage|license|legal|privacy)\b/) != nil
  }

  public static func changes(in markdown: String) -> [Change] {
    let lines = Markdown.lines(markdown)
    let sections = Markdown.sections(lines)

    let matching = sections.filter { $0.title.map(isChangeHeading) ?? false }
    if !matching.isEmpty {
      return matching.flatMap { Markdown.bullets(in: $0.lines) }
    }

    let others = sections.filter { !($0.title.map(isOtherHeading) ?? false) }
    let bullets = others.flatMap { Markdown.bullets(in: $0.lines) }
    if !bullets.isEmpty {
      return bullets
    }

    return Markdown.firstParagraph(lines).map { [Change($0)] } ?? []
  }
}

/// Reads a CHANGELOG.md with one heading per version, like `## 2.0.0 (September 30, 2026)` or `## [1.2.0] - 2026-09-30`.
public enum Changelog {
  /// The changes of each version, keyed by the version as `major.minor.patch`.
  public static func parse(_ markdown: String) -> [String: [Change]] {
    let lines = Markdown.lines(markdown)
    var result: [String: [Change]] = [:]

    for (index, line) in lines.enumerated() {
      guard let heading = Markdown.heading(line),
            let match = heading.title.firstMatch(of: /^\[?v?(\d+(?:\.\d+){1,2})\]?(?:\s|$|[(:\-–—])/),
            let version = SemanticVersion(String(match.output.1)) else { continue }

      let end = lines[(index + 1)...].firstIndex { next in
        Markdown.heading(next).map { $0.level <= heading.level } ?? false
      } ?? lines.endIndex
      let body = Array(lines[(index + 1)..<end])

      var changes = Markdown.bullets(in: body)
      if changes.isEmpty, let paragraph = Markdown.firstParagraph(body) {
        changes = [Change(paragraph)]
      }
      if result[version.description] == nil {
        result[version.description] = changes
      }
    }
    return result
  }

  static let fileNames = ["CHANGELOG.md", "Changelog.md", "changelog.md", "CHANGES.md", "HISTORY.md"]

  public static func load(in folder: URL) -> [String: [Change]]? {
    for name in fileNames {
      if let text = try? String(contentsOf: folder.appending(path: name), encoding: .utf8) {
        let parsed = parse(text)
        return parsed.isEmpty ? nil : parsed
      }
    }
    return nil
  }
}

enum Markdown {
  struct Section {
    /// Nil for the lines before the first heading.
    var title: String?
    var lines: [String]
  }

  /// Lines with code blocks removed, so a `#` or `-` inside them doesn't count.
  static func lines(_ markdown: String) -> [String] {
    var result: [String] = []
    var inCode = false
    for line in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
      if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
        inCode.toggle()
        result.append("")
        continue
      }
      result.append(inCode ? "" : line)
    }
    return result
  }

  static func heading(_ line: String) -> (level: Int, title: String)? {
    guard let match = line.wholeMatch(of: /(#{1,6})\s+(.+?)\s*#*\s*/) else { return nil }
    return (match.output.1.count, String(match.output.2))
  }

  /// Splits at every heading. A section runs until the next heading of the same or a higher level,
  /// so a `###` inside a matching `##` stays in it.
  static func sections(_ lines: [String]) -> [Section] {
    var sections = [Section(title: nil, lines: [])]
    var index = 0
    while index < lines.count {
      if let heading = heading(lines[index]) {
        let end = lines[(index + 1)...].firstIndex { next in
          Self.heading(next).map { $0.level <= heading.level } ?? false
        } ?? lines.endIndex
        sections.append(Section(title: heading.title, lines: Array(lines[(index + 1)..<end])))
        index = end
      } else {
        sections[0].lines.append(lines[index])
        index += 1
      }
    }
    return sections
  }

  /// Top-level list items. Wrapped lines join their item, nested items are left out.
  static func bullets(in lines: [String]) -> [Change] {
    var items: [String] = []
    var current: String?
    var inNested = false

    func finish() {
      if let item = current?.trimmingCharacters(in: .whitespaces), !item.isEmpty {
        items.append(item)
      }
      current = nil
      inNested = false
    }

    for line in lines {
      let indent = line.prefix { $0 == " " }.count + line.prefix { $0 == "\t" }.count * 4
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.isEmpty {
        if current != nil && !inNested { finish() }
        continue
      }
      if heading(line) != nil {
        finish()
        continue
      }
      if let match = trimmed.wholeMatch(of: /(?:[-*+]|\d+[.)])\s+(.*)/) {
        if indent < 2 {
          finish()
          current = String(match.output.1)
        } else {
          inNested = true
        }
        continue
      }
      if current != nil && !inNested {
        current! += " " + trimmed
      }
    }
    finish()
    return items.map(Change.init)
  }

  static func firstParagraph(_ lines: [String]) -> String? {
    var paragraph: [String] = []
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || heading(line) != nil {
        if !paragraph.isEmpty { break }
        continue
      }
      paragraph.append(trimmed)
    }
    return paragraph.isEmpty ? nil : paragraph.joined(separator: " ")
  }
}
