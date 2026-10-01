import Foundation

/// A temporary folder with the given files. Paths ending in `.app` become folders.
func makeFolder(_ files: [String: String]) throws -> URL {
  let root = FileManager.default.temporaryDirectory.appending(path: "releases-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  for (path, contents) in files {
    let url = root.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if path.hasSuffix(".app") {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } else {
      try contents.write(to: url, atomically: true, encoding: .utf8)
    }
  }
  return root
}
