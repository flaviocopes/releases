import Foundation
import Testing
@testable import ReleasesCLI

struct CapabilitiesManifestTests {
  @Test
  func manifestEncodesExpectedKeys() throws {
    let data = try JSONEncoder().encode(CapabilitiesManifest.current)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["name"] as? String == "releases")
    #expect(object["version"] as? String == Commands.version)
    #expect(object["summary"] as? String != nil)
    #expect((object["capabilities"] as? [[String: Any]])?.isEmpty == false)
    #expect((object["changelog"] as? [[String: Any]])?.isEmpty == false)
  }

  @Test
  func versionMatchesManifest() {
    #expect(CapabilitiesManifest.current.version == Commands.version)
  }
}
