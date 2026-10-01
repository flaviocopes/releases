import Foundation

enum Shell {
  struct Result {
    var status: Int32
    var output: String

    var succeeded: Bool { status == 0 }
  }

  /// Runs an executable and waits for it. Stderr is discarded.
  static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) -> Result {
    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    if let directory {
      process.currentDirectoryURL = directory
    }

    var environment = ProcessInfo.processInfo.environment
    environment["GIT_TERMINAL_PROMPT"] = "0"
    process.environment = environment

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      return Result(status: -1, output: "")
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return Result(status: process.terminationStatus, output: output)
  }

  /// Finds a command in the usual install locations. Apps launched from the Finder
  /// don't get the shell's PATH, so this doesn't rely on it.
  static func find(_ command: String) -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var directories = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/usr/bin"]
    if let path = ProcessInfo.processInfo.environment["PATH"] {
      directories += path.split(separator: ":").map(String.init)
    }
    return directories
      .map { "\($0)/\(command)" }
      .first { FileManager.default.isExecutableFile(atPath: $0) }
  }
}

/// Reads a git repository with the `git` command.
struct Git {
  let directory: URL

  private func run(_ arguments: String...) -> Shell.Result {
    Shell.run("/usr/bin/git", ["-C", directory.path] + arguments)
  }

  var root: String? {
    let result = run("rev-parse", "--show-toplevel")
    return result.succeeded && !result.output.isEmpty ? result.output : nil
  }

  var remoteURL: String? {
    let result = run("remote", "get-url", "origin")
    return result.succeeded && !result.output.isEmpty ? result.output : nil
  }

  var branch: String? {
    let result = run("branch", "--show-current")
    return result.succeeded && !result.output.isEmpty ? result.output : nil
  }

  var hasUncommittedChanges: Bool {
    let result = run("status", "--porcelain")
    return result.succeeded && !result.output.isEmpty
  }

  /// Commits on the current branch that aren't pushed to its upstream. Nil without an upstream.
  var unpushedCommitCount: Int? {
    let result = run("rev-list", "--count", "@{upstream}..HEAD")
    return result.succeeded ? Int(result.output) : nil
  }

  /// Nil outside a repository, or in one with no commits.
  var lastCommitDate: Date? {
    let result = run("log", "-1", "--format=%cI")
    guard result.succeeded, !result.output.isEmpty else { return nil }
    return try? Date(result.output, strategy: .iso8601)
  }

  func hasTag(_ tag: String) -> Bool {
    run("rev-parse", "--verify", "--quiet", "refs/tags/\(tag)").succeeded
  }

  /// Commits after `tag`, newest first. Nil when the tag isn't in the local repository.
  func commits(since tag: String) -> [Commit]? {
    guard hasTag(tag) else { return nil }
    let result = run("log", "--no-merges", "--format=%h%x09%aI%x09%s", "refs/tags/\(tag)..HEAD")
    guard result.succeeded else { return nil }
    return Self.parseLog(result.output)
  }

  /// Every commit on the current branch, newest first, for projects with no release yet.
  func allCommits(limit: Int = 200) -> [Commit] {
    let result = run("log", "--no-merges", "--max-count=\(limit)", "--format=%h%x09%aI%x09%s")
    return result.succeeded ? Self.parseLog(result.output) : []
  }

  static func parseLog(_ output: String) -> [Commit] {
    output.split(separator: "\n").compactMap { line in
      let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
      guard parts.count == 3 else { return nil }
      return Commit(
        hash: String(parts[0]),
        subject: String(parts[2]),
        date: try? Date(String(parts[1]), strategy: .iso8601)
      )
    }
  }
}
