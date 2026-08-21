import Foundation
import Testing
@testable import limit_bar

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]

        init(status: Int, body: Data, headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }

        init(status: Int, json: String, headers: [String: String] = [:]) {
            self.status = status
            self.body = Data(json.utf8)
            self.headers = headers
        }
    }

    final class Router: @unchecked Sendable {
        typealias Handler = @Sendable (URLRequest) throws -> Response

        private let lock = NSLock()
        private var handlers: [String: Handler] = [:]
        private var recordedRequests: [String: [URLRequest]] = [:]

        func install(id: String, handler: @escaping Handler) {
            lock.lock()
            defer { lock.unlock() }
            handlers[id] = handler
        }

        func drop(id: String) {
            lock.lock()
            defer { lock.unlock() }
            handlers.removeValue(forKey: id)
            recordedRequests.removeValue(forKey: id)
        }

        func handle(_ request: URLRequest) throws -> Response? {
            guard let id = StubURLProtocol.id(for: request) else { return nil }
            lock.lock()
            defer { lock.unlock() }
            recordedRequests[id, default: []].append(request)
            return try handlers[id]?(request)
        }

        func requests(id: String) -> [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recordedRequests[id] ?? []
        }
    }

    static let router = Router()

    static func id(for request: URLRequest) -> String? {
        guard let authorization = request.value(forHTTPHeaderField: "Authorization"),
              let range = authorization.range(of: "stub-") else { return nil }
        return String(authorization[range.upperBound...])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let response = try Self.router.handle(request) else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func stubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

struct CredentialFake: CredentialStore, @unchecked Sendable {
    enum Mode {
        case token(String)
        case notFound
        case denied
    }

    private let mode: Mode

    init(_ mode: Mode) {
        self.mode = mode
    }

    func set(_ secret: String, forKey key: String) throws {}

    func secret(forKey key: String) throws -> String {
        switch mode {
        case .token(let token):
            return token
        case .notFound:
            throw KeychainStore.KeychainError.itemNotFound
        case .denied:
            throw KeychainStore.KeychainError.accessDenied
        }
    }

    func deleteSecret(forKey key: String) throws {}
}
