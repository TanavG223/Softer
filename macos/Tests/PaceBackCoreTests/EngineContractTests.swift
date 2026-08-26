import XCTest
@testable import PaceBackCore

final class EngineContractTests: XCTestCase {
    func testDecodesCanonicalSynchronousRunResponse() throws {
        let json = #"""
        {
          "runID": "run-123",
          "answer": "A verified answer.",
          "supportStatus": "verified",
          "citations": [{
            "sourceID": "cdc-1",
            "title": "CDC Guidance",
            "url": "https://www.cdc.gov/example",
            "page": 2,
            "quote": "Supporting passage."
          }],
          "route": "single",
          "stopReason": "verified",
          "usage": {
            "retrievedTokens": 250,
            "inputTokens": 120,
            "outputTokens": 80,
            "retrievalRounds": 1,
            "latencyMS": 412.5
          }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(EvidenceAnswer.self, from: json)

        XCTAssertEqual(response.runID, "run-123")
        XCTAssertEqual(response.supportStatus, .verified)
        XCTAssertEqual(response.citations.first?.sourceID, "cdc-1")
        XCTAssertEqual(response.citations.first?.page, 2)
        XCTAssertEqual(response.usage.latencyMS, 412.5)
    }

    func testDecodesCanonicalHealthResponse() throws {
        let json = #"""
        {
          "status": "ok",
          "version": "1.0.0",
          "databaseReady": true,
          "fts5Ready": true,
          "releaseMode": true,
          "storageDriver": "sqlcipher",
          "storageEncryptionActive": true,
          "networkToolsEnabled": false
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(EngineHealth.self, from: json)

        XCTAssertTrue(response.databaseReady)
        XCTAssertTrue(response.fts5Ready)
        XCTAssertTrue(response.releaseMode)
        XCTAssertEqual(response.storageDriver, "sqlcipher")
        XCTAssertTrue(response.storageEncryptionActive)
        XCTAssertFalse(response.networkToolsEnabled)
    }

    func testAllFailClosedStatusesDecode() throws {
        for status in ["insufficientInformation", "dangerSignDetected", "cancelled", "partial"] {
            let data = "\"\(status)\"".data(using: .utf8)!
            XCTAssertNoThrow(try JSONDecoder().decode(SupportStatus.self, from: data))
        }
    }

    func testSidecarRejectsNonLoopbackAndMissingToken() {
        XCTAssertThrowsError(
            try URLSidecarAIEngine(
                baseURL: URL(string: "https://example.com")!,
                bearerToken: "secret"
            )
        )
        XCTAssertThrowsError(
            try URLSidecarAIEngine(
                baseURL: URL(string: "http://127.0.0.1:9876")!,
                bearerToken: ""
            )
        )
        XCTAssertNoThrow(
            try URLSidecarAIEngine(
                baseURL: URL(string: "http://127.0.0.1:9876")!,
                bearerToken: "per-launch-token"
            )
        )
    }

    func testNativeSyncSendsCanonicalProfileAndConfirmedRestrictionsOnly() async throws {
        let profileID = UUID()
        let profile = LocalProfile(
            id: profileID,
            alias: "Student",
            ageBand: .child6To12,
            actingRole: .caregiver,
            carePlanDraft: CarePlanDraft(
                profileID: profileID,
                sourceName: "private-file-name.pdf",
                restrictions: [
                    CarePlanRestriction(
                        text: "Use the confirmed quiet-room accommodation.",
                        page: 3,
                        isConfirmed: true
                    ),
                    CarePlanRestriction(
                        text: "Unconfirmed raw extraction must stay out.",
                        page: 4,
                        isConfirmed: false
                    )
                ]
            )
        )
        let recorder = URLRequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("PUT", "/v1/profiles/\(profileID.uuidString)"):
                return (200, Data("{}".utf8))
            case ("GET", "/v1/profiles/\(profileID.uuidString)/documents"):
                let data = #"[{"documentID":"stale-plan","sourceKind":"clinicianPlan","evidenceScope":"child6To12","contentHash":"stale"},{"documentID":"personal-note","sourceKind":"userProvided","evidenceScope":"child6To12","contentHash":"keep"}]"#
                return (200, Data(data.utf8))
            case ("POST", "/v1/profiles/\(profileID.uuidString)/documents"):
                return (201, Data("{}".utf8))
            case ("DELETE", "/v1/profiles/\(profileID.uuidString)/documents/stale-plan"):
                return (204, Data())
            default:
                XCTFail("Unexpected sidecar request: \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                return (500, Data())
            }
        }
        defer { StubURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let engine = try URLSidecarAIEngine(
            baseURL: URL(string: "http://127.0.0.1:9834/")!,
            bearerToken: "launch-secret",
            session: URLSession(configuration: configuration)
        )

        try await engine.syncProfile(profile)

        let requests = recorder.snapshot()
        XCTAssertEqual(requests.map(\.method), ["PUT", "GET", "POST", "DELETE"])

        let profileBody = try XCTUnwrap(requests[0].body)
        let profileJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: profileBody) as? [String: Any]
        )
        XCTAssertEqual(profileJSON["ageBand"] as? String, "child6To12")
        XCTAssertEqual(profileJSON["ownerRole"] as? String, "guardian")
        XCTAssertEqual(profileJSON["caregiverAccess"] as? Bool, false)

        let documentBody = try XCTUnwrap(requests[2].body)
        let documentJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: documentBody) as? [String: Any]
        )
        let indexedContent = try XCTUnwrap(documentJSON["content"] as? String)
        XCTAssertTrue(indexedContent.contains("Page 3: Use the confirmed quiet-room accommodation."))
        XCTAssertFalse(indexedContent.contains("Unconfirmed raw extraction"))
        XCTAssertFalse(indexedContent.contains("private-file-name.pdf"))
        XCTAssertEqual(documentJSON["sourceKind"] as? String, "clinicianPlan")
        XCTAssertEqual(documentJSON["evidenceScope"] as? String, "child6To12")
        XCTAssertEqual(documentJSON["actingRole"] as? String, "guardian")
        XCTAssertEqual(requests[3].headers["X-Acting-Role"], "guardian")
    }

    func testRunResponseMustMatchClientGeneratedRunID() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/runs")
            let response = #"{"runID":"different-run-id","answer":"No evidence.","supportStatus":"insufficientInformation","citations":[],"route":"direct","stopReason":"noEvidence","usage":{"retrievedTokens":0,"inputTokens":1,"outputTokens":1,"retrievalRounds":0,"latencyMS":1}}"#
            return (201, Data(response.utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let engine = try URLSidecarAIEngine(
            baseURL: URL(string: "http://127.0.0.1:9834/")!,
            bearerToken: "launch-secret",
            session: URLSession(configuration: configuration)
        )
        let profile = LocalProfile(
            alias: "Run",
            ageBand: .adult18To64,
            actingRole: .selfManaged
        )
        let query = EvidenceQuery(
            question: "What is supported?",
            profile: profile,
            runID: "7AF9A7B9-29E9-4871-A4F5-058BFBB9F451"
        )

        do {
            _ = try await engine.ask(query)
            XCTFail("A mismatched response runID must fail closed.")
        } catch AIEngineError.invalidResponse {
            // Expected: cancellation and replay must address the same client run.
        } catch {
            XCTFail("Expected invalidResponse, got \(error)")
        }
    }
}

private struct CapturedURLRequest: Sendable {
    let method: String?
    let path: String?
    let headers: [String: String]
    let body: Data?
}

private final class URLRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [CapturedURLRequest] = []

    func append(_ request: URLRequest) {
        let captured = CapturedURLRequest(
            method: request.httpMethod,
            path: request.url?.path,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? Self.readBody(from: request.httpBodyStream)
        )
        lock.lock()
        requests.append(captured)
        lock.unlock()
    }

    func snapshot() -> [CapturedURLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    private static func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(buffer, count: count)
        }
        return result.isEmpty ? nil : result
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw AIEngineError.unavailable }
            let (status, data) = try handler(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw AIEngineError.invalidResponse
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
