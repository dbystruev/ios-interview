import Foundation

public struct MockProvider: LLMService, Sendable {
    public let id = "mock"
    public let displayName = "Mock"
    public var isAvailable = true
    public var handler: @Sendable (String, String) async throws -> String

    public init(handler: @escaping @Sendable (String, String) async throws -> String) {
        self.handler = handler
    }

    public func complete(system: String, user: String) async throws -> String {
        try await handler(system, user)
    }

    public static func canned(_ text: String) -> MockProvider {
        MockProvider(handler: { _, _ in text })
    }

    public static func cannedExtraction(_ json: String) -> MockProvider {
        MockProvider(handler: { _, _ in json })
    }
}
