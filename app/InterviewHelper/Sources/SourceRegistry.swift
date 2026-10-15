import Foundation

public struct SourceRegistry: Sendable {
    public var seed: [SourceEntry]
    public var customHosts: [String]

    public init(seed: [SourceEntry], customHosts: [String] = []) {
        self.seed = seed
        self.customHosts = customHosts
    }

    public static func loadSeed(bundle: Bundle = .main) -> [SourceEntry] {
        guard let url = bundle.url(forResource: "Sources", withExtension: "json") else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let entries = try? JSONDecoder().decode([SourceEntry].self, from: data) else { return [] }
        return entries
    }

    public var allowedHosts: Set<String> {
        var hosts = Set<String>()
        for entry in seed {
            let base: String
            if let host = URL(string: entry.baseURL)?.host, !host.isEmpty {
                base = host
            } else {
                base = entry.baseURL
            }
            hosts.insert(HostUtil.normalizedHost(base))
        }
        for h in customHosts {
            hosts.insert(HostUtil.normalizedHost(h))
        }
        return hosts
    }

    public func filter(_ citations: [SourceCitation]) -> (kept: [SourceCitation], dropped: Int) {
        let f = CitationFilter(allowedHosts: allowedHosts)
        return f.filter(citations)
    }
}
