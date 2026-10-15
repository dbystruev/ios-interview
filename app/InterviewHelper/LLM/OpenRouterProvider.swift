import Foundation

public struct OpenRouterModel: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct OpenRouterProvider: LLMService, Sendable {
    public let id = "openrouter"
    public let displayName = "OpenRouter"
    public var apiKey: String
    public var model: String
    public var baseURL: URL
    public let session: URLSession

    public init(
        apiKey: String,
        model: String = "openrouter/free",
        baseURL: URL = URL(string: "https://openrouter.ai/api/v1") ?? URL(fileURLWithPath: "/"),
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    public var isAvailable: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func complete(system: String, user: String) async throws -> String {
        guard isAvailable else {
            throw LLMError.unavailable("OpenRouter API key is missing")
        }
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let payload = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user)
            ]
        )
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw LLMError.transport("Failed to encode request: \(error.localizedDescription)")
        }
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            throw LLMError.transport("Network error: \(error.localizedDescription)")
        }
        guard let http = urlResponse as? HTTPURLResponse else {
            throw LLMError.transport("Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.transport("OpenRouter HTTP \(http.statusCode): \(body)")
        }
        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let raw = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else {
                throw LLMError.badResponse("Empty completion")
            }
            return raw
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.badResponse("Failed to decode completion: \(error.localizedDescription)")
        }
    }

    public func fetchFreeModels() async throws -> [OpenRouterModel] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if isAvailable {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            throw LLMError.transport("Network error: \(error.localizedDescription)")
        }
        guard let http = urlResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw LLMError.transport("OpenRouter models HTTP \(code)")
        }
        do {
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            let free = decoded.data.filter { $0.id == "openrouter/free" || $0.id.hasSuffix(":free") }
            let mapped = free.map { OpenRouterModel(id: $0.id, name: $0.name ?? $0.id) }
            return mapped.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.badResponse("Failed to decode models: \(error.localizedDescription)")
        }
    }
}

private struct ChatMessage: Codable, Sendable {
    var role: String
    var content: String
}

private struct ChatRequest: Codable, Sendable {
    var model: String
    var messages: [ChatMessage]
}

private struct ResponseMessage: Decodable, Sendable {
    var content: String?
}

private struct Choice: Decodable, Sendable {
    var message: ResponseMessage
}

private struct ChatResponse: Decodable, Sendable {
    var choices: [Choice]
}

private struct ModelEntry: Decodable, Sendable {
    var id: String
    var name: String?
}

private struct ModelsResponse: Decodable, Sendable {
    var data: [ModelEntry]
}
