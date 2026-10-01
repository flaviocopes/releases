import Foundation

/// A `major.minor.patch` version. Parses "1.2", "1.2.3" and "v1.2.3".
/// Anything after the numbers, like "-beta.1", is ignored.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
  public var major: Int
  public var minor: Int
  public var patch: Int

  public init(major: Int, minor: Int, patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  public init?(_ text: String) {
    var trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.first == "v" || trimmed.first == "V" {
      trimmed.removeFirst()
    }
    guard let match = trimmed.wholeMatch(of: /(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[-+].*)?/) else {
      return nil
    }
    major = Int(match.output.1) ?? 0
    minor = match.output.2.flatMap { Int($0) } ?? 0
    patch = match.output.3.flatMap { Int($0) } ?? 0
  }

  public var description: String {
    "\(major).\(minor).\(patch)"
  }

  public var tag: String {
    "v\(description)"
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }

  public enum Bump: String, CaseIterable, Sendable {
    case patch, minor, major
  }

  public func bumped(_ bump: Bump) -> SemanticVersion {
    switch bump {
    case .patch: SemanticVersion(major: major, minor: minor, patch: patch + 1)
    case .minor: SemanticVersion(major: major, minor: minor + 1, patch: 0)
    case .major: SemanticVersion(major: major + 1, minor: 0, patch: 0)
    }
  }
}
