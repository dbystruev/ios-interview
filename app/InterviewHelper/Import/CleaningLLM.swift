import Foundation

public protocol CleaningLLM: Sendable {
    func complete(system: String, user: String) async throws -> String
}
