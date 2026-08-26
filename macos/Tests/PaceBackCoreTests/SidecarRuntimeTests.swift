import XCTest
@testable import PaceBackCore

final class SidecarRuntimeTests: XCTestCase {
    func testStrictReleaseHealthIsAccepted() throws {
        XCTAssertNoThrow(
            try SidecarEngineRuntime.validateHealth(
                health(),
                developmentOverrideActive: false
            )
        )
    }

    func testHealthRejectsWrongStatusVersionReadinessAndNetworkTools() {
        let invalidHealthResponses = [
            health(status: "degraded"),
            health(version: "0.2.0"),
            health(databaseReady: false),
            health(fts5Ready: false),
            health(networkToolsEnabled: true),
            health(storageDriver: "sqlite"),
            health(storageEncryptionActive: false),
            health(releaseMode: false)
        ]

        for response in invalidHealthResponses {
            XCTAssertThrowsError(
                try SidecarEngineRuntime.validateHealth(
                    response,
                    developmentOverrideActive: false
                )
            )
        }
    }

    func testSQLiteHealthRequiresExplicitDebugDevelopmentOverride() throws {
        let development = health(
            releaseMode: false,
            storageDriver: "sqlite",
            storageEncryptionActive: false
        )

        #if DEBUG
        XCTAssertNoThrow(
            try SidecarEngineRuntime.validateHealth(
                development,
                developmentOverrideActive: true
            )
        )
        #else
        XCTAssertThrowsError(
            try SidecarEngineRuntime.validateHealth(
                development,
                developmentOverrideActive: true
            )
        )
        #endif
        XCTAssertThrowsError(
            try SidecarEngineRuntime.validateHealth(
                development,
                developmentOverrideActive: false
            )
        )
    }

    func testOnlyZeroPointOneEngineVersionsAreSupported() {
        for version in ["0.1.0", "0.1.27", "0.1.4-beta.1"] {
            XCTAssertTrue(SidecarEngineRuntime.isSupportedEngineVersion(version), version)
        }
        for version in ["", "0.1", "0.1.x", "0.1.-1", "0.2.0", "1.0.0"] {
            XCTAssertFalse(SidecarEngineRuntime.isSupportedEngineVersion(version), version)
        }
    }

    func testSwitchingEngineDefaultsToUnavailable() async {
        let engine = SwitchingAIEngine()
        do {
            _ = try await engine.health()
            XCTFail("Expected unavailable engine")
        } catch let error as AIEngineError {
            guard case .unavailable = error else {
                return XCTFail("Expected unavailable, received \(error)")
            }
        } catch {
            XCTFail("Expected AIEngineError.unavailable, received \(error)")
        }
    }

    func testSignedLocalBGEAndMiniLMManifestIsAccepted() throws {
        XCTAssertNoThrow(try SidecarEngineRuntime.validateModelManifest(activeModelManifest()))
    }

    func testFallbackOrUnsafeModelManifestIsRejected() {
        var fallbackComponents = activeModelManifest().components
        fallbackComponents[2] = modelComponent(
            name: "bge-small-en-v1.5-onnx",
            modelID: "BAAI/bge-small-en-v1.5",
            revision: "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a",
            dimensions: 384,
            activation: "fallback"
        )
        let fallback = EngineModelManifest(
            components: fallbackComponents,
            modelPackID: "paceback-bge-small-minilm-onnx-v1",
            modelPackActivation: "failed",
            webSearchEnabled: false,
            codeExecutionEnabled: false,
            runtimeWeightUpdatesEnabled: false,
            storageDriver: "sqlcipher",
            storageEncryptionActive: true
        )
        XCTAssertThrowsError(try SidecarEngineRuntime.validateModelManifest(fallback))

        let unsafe = EngineModelManifest(
            components: activeModelManifest().components,
            modelPackID: "paceback-bge-small-minilm-onnx-v1",
            modelPackActivation: "active",
            webSearchEnabled: true,
            codeExecutionEnabled: false,
            runtimeWeightUpdatesEnabled: false,
            storageDriver: "sqlcipher",
            storageEncryptionActive: true
        )
        XCTAssertThrowsError(try SidecarEngineRuntime.validateModelManifest(unsafe))
    }

    private func health(
        status: String = "ok",
        version: String = "0.1.0",
        databaseReady: Bool = true,
        fts5Ready: Bool = true,
        releaseMode: Bool = true,
        storageDriver: String = "sqlcipher",
        storageEncryptionActive: Bool = true,
        networkToolsEnabled: Bool = false
    ) -> EngineHealth {
        EngineHealth(
            status: status,
            version: version,
            databaseReady: databaseReady,
            fts5Ready: fts5Ready,
            releaseMode: releaseMode,
            storageDriver: storageDriver,
            storageEncryptionActive: storageEncryptionActive,
            networkToolsEnabled: networkToolsEnabled
        )
    }

    private func activeModelManifest() -> EngineModelManifest {
        EngineModelManifest(
            components: [
                modelComponent(name: "sqlite-fts5-bm25"),
                modelComponent(name: "reciprocal-rank-fusion"),
                modelComponent(
                    name: "bge-small-en-v1.5-onnx",
                    modelID: "BAAI/bge-small-en-v1.5",
                    revision: "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a",
                    dimensions: 384
                ),
                modelComponent(
                    name: "ms-marco-MiniLM-L6-v2-onnx",
                    modelID: "cross-encoder/ms-marco-MiniLM-L-6-v2",
                    revision: "233902d25c440f23af6f7d6e94d2946bac0bee0a"
                )
            ],
            modelPackID: "paceback-bge-small-minilm-onnx-v1",
            modelPackActivation: "active",
            webSearchEnabled: false,
            codeExecutionEnabled: false,
            runtimeWeightUpdatesEnabled: false,
            storageDriver: "sqlcipher",
            storageEncryptionActive: true
        )
    }

    private func modelComponent(
        name: String,
        modelID: String? = nil,
        revision: String? = nil,
        dimensions: Int? = nil,
        activation: String = "active"
    ) -> EngineModelComponent {
        EngineModelComponent(
            name: name,
            version: "1",
            purpose: "test fixture",
            localOnly: true,
            active: activation == "active",
            activation: activation,
            modelID: modelID,
            revision: revision,
            artifactSHA256: modelID == nil ? nil : String(repeating: "a", count: 64),
            dimensions: dimensions,
            provider: modelID == nil ? nil : "CPUExecutionProvider",
            failureReason: nil
        )
    }
}
