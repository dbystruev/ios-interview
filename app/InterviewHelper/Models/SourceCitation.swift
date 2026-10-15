import Foundation

public struct SourceCitation: Codable, Hashable, Sendable {
    public var sourceId: String
    public var title: String
    public var url: URL

    public init(sourceId: String, title: String, url: URL) {
        self.sourceId = sourceId
        self.title = title
        self.url = url
    }
}

public struct SourceEntry: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var notes: String

    public init(id: String, name: String, baseURL: String, notes: String = "") {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.notes = notes
    }
}

public enum HostUtil: Sendable {
    public static func normalizedHost(_ host: String) -> String {
        var result = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("www.") {
            result = String(result.dropFirst(4))
        }
        if result.hasSuffix(".") {
            result = String(result.dropLast())
        }
        return result
    }

    public static func hostMatches(_ host: String, allowedBase: String) -> Bool {
        let normalized = normalizedHost(host)
        let rawBase: String
        if let parsed = URL(string: allowedBase), let parsedHost = parsed.host, !parsedHost.isEmpty {
            rawBase = parsedHost
        } else {
            rawBase = allowedBase
        }
        let base = normalizedHost(rawBase)
        if normalized == base {
            return true
        }
        return normalized.hasSuffix("." + base)
    }
}

public struct CitationFilter: Sendable {
    public var allowedHosts: Set<String>

    public init(allowedHosts: Set<String>) {
        self.allowedHosts = allowedHosts
    }

    public func filter(_ citations: [SourceCitation]) -> (kept: [SourceCitation], dropped: Int) {
        guard !allowedHosts.isEmpty else {
            return (kept: citations, dropped: 0)
        }
        var kept: [SourceCitation] = []
        var dropped = 0
        for citation in citations {
            guard let host = citation.url.host, !host.isEmpty else {
                dropped += 1
                continue
            }
            let allowed = allowedHosts.contains { base in
                HostUtil.hostMatches(host, allowedBase: base)
            }
            if allowed {
                kept.append(citation)
            } else {
                dropped += 1
            }
        }
        return (kept: kept, dropped: dropped)
    }
}
