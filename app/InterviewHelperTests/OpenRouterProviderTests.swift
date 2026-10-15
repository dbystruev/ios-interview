import XCTest
@testable import InterviewHelper

final class TestStubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "TestStub", code: 0))
            return
        }
        do {
            let (response, data) = try handler(request)
            Self.lastRequest = request
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class OpenRouterProviderTests: XCTestCase {
    override func tearDown() {
        TestStubProtocol.handler = nil
        TestStubProtocol.lastRequest = nil
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestStubProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeBaseURL() -> URL {
        URL(string: "https://openrouter.ai/api/v1") ?? URL(fileURLWithPath: "/")
    }

    func testChatCompletionReturnsContent() async throws {
        let session = makeSession()
        let base = makeBaseURL()
        TestStubProtocol.handler = { request in
            guard let url = request.url else { throw LLMError.transport("no url") }
            let json = "{\"choices\":[{\"message\":{\"content\":\" Hello \"}}]}"
            guard let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                throw LLMError.transport("bad response")
            }
            return (resp, Data(json.utf8))
        }
        let provider = OpenRouterProvider(apiKey: "test-key", model: "openrouter/free", baseURL: base, session: session)
        let text = try await provider.complete(system: "sys", user: "hi")
        XCTAssertEqual(text, "Hello")
        let captured = try XCTUnwrap(TestStubProtocol.lastRequest)
        XCTAssertTrue(captured.url?.path.contains("/chat/completions") == true)
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testFetchFreeModelsFilters() async throws {
        let session = makeSession()
        let base = makeBaseURL()
        TestStubProtocol.handler = { request in
            guard let url = request.url else { throw LLMError.transport("no url") }
            let json = """
            {"data":[
              {"id":"openai/gpt-4","name":"GPT-4"},
              {"id":"meta/llama:free","name":"Llama"},
              {"id":"openrouter/free","name":"Router Free"},
              {"id":"anthropic/claude:free","name":"Claude"}
            ]}
            """
            guard let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                throw LLMError.transport("bad response")
            }
            return (resp, Data(json.utf8))
        }
        let provider = OpenRouterProvider(apiKey: "test-key", baseURL: base, session: session)
        let models = try await provider.fetchFreeModels()
        XCTAssertEqual(models.count, 3)
        let ids = models.map { $0.id }
        XCTAssertFalse(ids.contains("openai/gpt-4"))
        XCTAssertTrue(ids.contains("openrouter/free"))
        let names = models.map { $0.name }
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testEmptyApiKeyNotAvailable() {
        let base = makeBaseURL()
        let p1 = OpenRouterProvider(apiKey: "", baseURL: base)
        XCTAssertFalse(p1.isAvailable)
        let p2 = OpenRouterProvider(apiKey: "   \n ", baseURL: base)
        XCTAssertFalse(p2.isAvailable)
    }
}
