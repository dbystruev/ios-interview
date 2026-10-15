#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, *)
public final class FoundationModelsProvider: LLMService, Sendable {
    public let id = "on-device"
    public let displayName = "On-device (Apple Intelligence)"

    public init() {}

    public var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public func complete(system: String, user: String) async throws -> String {
        guard isAvailable else {
            throw LLMError.unavailable("Apple Intelligence is not available")
        }
        do {
            let session = LanguageModelSession(instructions: system)
            let response = try await session.respond(to: user)
            return response.content
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.transport("On-device model failed: \(error.localizedDescription)")
        }
    }
}
#endif
