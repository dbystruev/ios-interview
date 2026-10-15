import XCTest
@testable import InterviewHelper

final class SourceRegistryTests: XCTestCase {
    private func makeSeed() -> [SourceEntry] {
        [
            SourceEntry(id: "apple-docs", name: "Apple Developer Documentation", baseURL: "https://developer.apple.com/documentation", notes: "Framework APIs"),
            SourceEntry(id: "swiftlee", name: "SwiftLee", baseURL: "https://www.avanderlee.com", notes: "Swift patterns"),
            SourceEntry(id: "hws", name: "Hacking with Swift", baseURL: "https://www.hackingwithswift.com", notes: "Examples"),
            SourceEntry(id: "sundell", name: "Swift by Sundell", baseURL: "https://www.swiftbysundell.com", notes: "Architecture")
        ]
    }

    func testSeedHostsContainExpected() {
        let reg = SourceRegistry(seed: makeSeed())
        let hosts = reg.allowedHosts
        XCTAssertTrue(hosts.contains("developer.apple.com"))
        XCTAssertTrue(hosts.contains("avanderlee.com") || hosts.contains("www.avanderlee.com"))
    }

    func testHostMatches() {
        XCTAssertTrue(HostUtil.hostMatches("www.avanderlee.com", allowedBase: "https://www.avanderlee.com"))
        XCTAssertTrue(HostUtil.hostMatches("docs.hackingwithswift.com", allowedBase: "hackingwithswift.com"))
        XCTAssertFalse(HostUtil.hostMatches("evil.com", allowedBase: "hackingwithswift.com"))
        XCTAssertFalse(HostUtil.hostMatches("evil.com", allowedBase: "https://www.avanderlee.com"))
    }

    func testFilterDropsOffList() throws {
        let reg = SourceRegistry(seed: makeSeed())
        let goodURL = try XCTUnwrap(URL(string: "https://developer.apple.com/documentation/swift"))
        let badURL = try XCTUnwrap(URL(string: "https://evil.com/steal"))
        let good = SourceCitation(sourceId: "apple-docs", title: "Apple", url: goodURL)
        let bad = SourceCitation(sourceId: "evil", title: "Evil", url: badURL)
        let result = reg.filter([good, bad])
        XCTAssertEqual(result.kept.count, 1)
        XCTAssertEqual(result.dropped, 1)
        XCTAssertEqual(result.kept.first?.sourceId, "apple-docs")
    }

    func testLoadSeedBadBundleReturnsEmpty() {
        let seeded = SourceRegistry.loadSeed(bundle: Bundle(for: SourceRegistryTests.self))
        XCTAssertTrue(seeded.isEmpty)
    }
}
