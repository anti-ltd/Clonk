import Foundation
import Testing

@testable import ClonkCore

@Suite("Update checker — version compare + URL resolution")
struct UpdateCheckerTests {

    // MARK: - isNewer

    @Test
    func equalVersionsAreNotNewer() {
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("1.0", than: "1.0.0"))  // padded to .0
    }

    @Test
    func patchBumpIsNewer() {
        #expect(UpdateChecker.isNewer("1.0.1", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.1"))
    }

    @Test
    func minorBumpIsNewer() {
        #expect(UpdateChecker.isNewer("1.1.0", than: "1.0.99"))
    }

    @Test
    func numericCompareNotLexicographic() {
        // "1.2.10" beats "1.2.9" — string compare would flip this.
        #expect(UpdateChecker.isNewer("1.2.10", than: "1.2.9"))
    }

    @Test
    func malformedSegmentsTreatedAsZero() {
        #expect(!UpdateChecker.isNewer("1.0.beta", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.beta"))
    }

    // MARK: - VersionInfo decoding

    @Test
    func decodesSampleResponse() throws {
        let json = #"""
        {
          "app": "clonk",
          "version": "1.2.3",
          "releasedAt": "2026-05-27T10:00:00Z",
          "notes": "Bug fixes and a new piano profile.",
          "minOS": "macOS 14.0",
          "sha256": "deadbeef",
          "size": 12345678,
          "downloadUrl": "/api/download?app=clonk"
        }
        """#
        let info = try JSONDecoder().decode(VersionInfo.self, from: Data(json.utf8))
        #expect(info.app == "clonk")
        #expect(info.version == "1.2.3")
        #expect(info.size == 12345678)
        #expect(info.downloadUrl == "/api/download?app=clonk")
    }

    @Test
    func decodesWithMissingOptionalFields() throws {
        // Server may omit everything except `app` + `version`.
        let json = #"""
        { "app": "clonk", "version": "1.0.0" }
        """#
        let info = try JSONDecoder().decode(VersionInfo.self, from: Data(json.utf8))
        #expect(info.notes == nil)
        #expect(info.size == nil)
        #expect(info.downloadUrl == nil)
    }

    // MARK: - resolvedDownloadURL

    @Test
    func relativeDownloadURLResolvesAgainstHost() throws {
        let info = try JSONDecoder().decode(VersionInfo.self, from: Data(#"""
        { "app": "clonk", "version": "1.0.0", "downloadUrl": "/api/download?app=clonk" }
        """#.utf8))
        let resolved = info.resolvedDownloadURL(
            relativeTo: URL(string: "https://anti.ltd/api1/version")!)
        #expect(resolved?.absoluteString == "https://anti.ltd/api/download?app=clonk")
    }

    @Test
    func absoluteDownloadURLPassesThrough() throws {
        let info = try JSONDecoder().decode(VersionInfo.self, from: Data(#"""
        { "app": "clonk", "version": "1.0.0", "downloadUrl": "https://cdn.example/clonk.dmg" }
        """#.utf8))
        let resolved = info.resolvedDownloadURL()
        #expect(resolved?.absoluteString == "https://cdn.example/clonk.dmg")
    }

    @Test
    func missingDownloadURLReturnsNil() throws {
        let info = try JSONDecoder().decode(VersionInfo.self, from: Data(#"""
        { "app": "clonk", "version": "1.0.0" }
        """#.utf8))
        #expect(info.resolvedDownloadURL() == nil)
    }
}
