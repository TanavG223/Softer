import Foundation
import Testing
@testable import PaceBackiOS

@Suite("Pinned BERT WordPiece tokenizer")
struct WordPieceTokenizerTests {
    @Test("Normalization, punctuation, accents, and WordPiece IDs match BERT")
    func exactEncoding() throws {
        let tokenizer = try WordPieceTokenizer(data: tokenizerFixture())
        let encoding = try tokenizer.encode("Héllo, PLAYING!")

        #expect(tokenizer.normalize("Héllo\u{0000}\tPLAYING") == "hello playing")
        #expect(encoding.inputIDs == [101, 7_592, 1_010, 2_377, 2_075, 999, 102])
        #expect(encoding.attentionMask == Array(repeating: 1, count: 7))
        #expect(encoding.tokenTypeIDs == Array(repeating: 0, count: 7))
    }

    @Test("Pair encoding uses BERT segments and never exceeds the model window")
    func pairEncoding() throws {
        let tokenizer = try WordPieceTokenizer(data: tokenizerFixture())
        let encoding = try tokenizer.encodePair(
            "hello playing hello playing",
            "hello playing hello playing",
            maxLength: 9
        )

        #expect(encoding.sequenceLength == 9)
        #expect(encoding.inputIDs.first == 101)
        #expect(encoding.inputIDs.last == 102)
        #expect(encoding.tokenTypeIDs == [0, 0, 0, 0, 0, 1, 1, 1, 1])
    }

    private func tokenizerFixture() -> Data {
        var vocabulary: [String: Int] = [
            "[PAD]": 0,
            "[UNK]": 100,
            "[CLS]": 101,
            "[SEP]": 102,
            "!": 999,
            ",": 1_010,
            "##ing": 2_075,
            "play": 2_377,
            "hello": 7_592
        ]
        var index = 0
        while vocabulary.count < 30_522 {
            vocabulary["fixture_\(index)"] = 40_000 + index
            index += 1
        }
        let document: [String: Any] = [
            "normalizer": [
                "type": "BertNormalizer",
                "clean_text": true,
                "handle_chinese_chars": true,
                "strip_accents": NSNull(),
                "lowercase": true
            ],
            "pre_tokenizer": ["type": "BertPreTokenizer"],
            "model": [
                "type": "WordPiece",
                "vocab": vocabulary,
                "unk_token": "[UNK]",
                "continuing_subword_prefix": "##",
                "max_input_chars_per_word": 100
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }
}

@Suite("Verified local hybrid evidence engine")
struct LocalEvidenceEngineTests {
    @Test("Age scope is applied before sparse and model retrieval")
    func filtersBeforeBothRetrievers() async throws {
        let fixture = try EngineFixture(documents: [
            document("shared", scope: "allAges", content: "A shared concussion evidence passage."),
            document("child", scope: "child6To12", content: "A child school rest break passage."),
            document("teen", scope: "teen13To17", content: "A teen school quiet room passage."),
            document("adult", scope: "adult18To64", content: "An adult work schedule passage.")
        ])
        defer { fixture.remove() }
        let request = EvidenceRequest(
            question: "What school support includes a quiet room?",
            profileID: UUID(),
            ageBand: .teen13To17,
            actingRole: .teenUser,
            careContext: .school
        )

        let eligible = try fixture.corpus.eligible(for: request)
        #expect(Set(eligible.map(\.scope)) == ["allAges", "teen13To17"])
        #expect(!LocalEvidenceEngine.bm25(query: request.question, passages: eligible, limit: 50)
            .contains(where: { $0.scope == "child6To12" || $0.scope == "adult18To64" }))

        let response = try await fixture.engine.ask(request)
        #expect(response.isSourceLinked)
        #expect(response.answer.contains("teen school quiet room"))
        #expect(!response.answer.contains("child school"))
        #expect(!response.answer.contains("adult work"))

        let observed = await fixture.inference.observedPassages()
        #expect(!observed.isEmpty)
        #expect(observed.allSatisfy { !$0.contains("child school") && !$0.contains("adult work") })
    }

    @Test("Answers are short extractive excerpts with locatable citations")
    func extractiveAndCited() async throws {
        let source = document(
            "school",
            scope: "child6To12",
            content: "Extra time can be documented by the school team. A clinician remains responsible for medical decisions."
        )
        let fixture = try EngineFixture(documents: [source])
        defer { fixture.remove() }

        let response = try await fixture.engine.ask(
            EvidenceRequest(
                question: "Who can document extra time at school?",
                profileID: UUID(),
                ageBand: .child6To12,
                actingRole: .guardian,
                careContext: .school
            )
        )

        #expect(response.isSourceLinked)
        #expect(response.citations.count == 1)
        #expect(response.citations[0].passageID == "school#p1")
        #expect(response.citations[0].url.absoluteString == "https://example.invalid/school")
        #expect(response.citations[0].exactQuote == "Extra time can be documented by the school team.")
        #expect(response.citations[0].contentHash.count == 64)
        #expect(response.answer.contains("Extra time can be documented by the school team."))
        #expect(source.content.contains("Extra time can be documented by the school team."))
    }

    @Test("Results enforce eight total and three passages per source")
    func resultCaps() async throws {
        let repeated = Array(repeating: "School support evidence is reviewed by a care team.", count: 70)
            .joined(separator: " ")
        var documents = [document("many", scope: "teen13To17", content: repeated)]
        for index in 0..<10 {
            documents.append(
                document(
                    "other-\(index)",
                    scope: "allAges",
                    content: "School support evidence item \(index) remains clinician guided."
                )
            )
        }
        let fixture = try EngineFixture(documents: documents)
        defer { fixture.remove() }

        let response = try await fixture.engine.ask(
            EvidenceRequest(
                question: "What reviewed care team school support evidence is available?",
                profileID: UUID(),
                ageBand: .teen13To17,
                actingRole: .teenUser,
                careContext: .school
            )
        )

        #expect(!response.citations.isEmpty)
        #expect(response.citations.count <= 8)
        #expect(response.citations.filter { $0.passageID.contains("many#p") }.count <= 3)
    }

    @Test("Personal clearance requests abstain before model inference")
    func clearanceAbstains() async throws {
        let fixture = try EngineFixture(documents: [
            document("sport", scope: "allAges", content: "A clinician oversees return to sport.")
        ])
        defer { fixture.remove() }

        let response = try await fixture.engine.ask(
            EvidenceRequest(
                question: "Am I cleared to return to soccer practice?",
                profileID: UUID(),
                ageBand: .teen13To17,
                actingRole: .teenUser,
                careContext: .school
            )
        )

        #expect(!response.isSourceLinked)
        #expect(response.citations.isEmpty)
        #expect(response.answer.contains("cannot diagnose"))
        #expect(response.answer.contains("clearance"))
        #expect(await fixture.inference.callCount() == 0)
    }

    @Test("Unrelated factual, recipe, finance, and astronomy prompts abstain")
    func unsupportedAbstains() async throws {
        let fixture = try EngineFixture(documents: [
            document("school", scope: "allAges", content: "School support should involve the care team.")
        ])
        defer { fixture.remove() }

        for question in [
            "What is the capital of France?",
            "How do I bake chocolate chip cookies?",
            "Which stock should I buy?",
            "How far away is the Andromeda galaxy?"
        ] {
            let response = try await fixture.engine.ask(
                EvidenceRequest(
                    question: question,
                    profileID: UUID(),
                    ageBand: .adult18To64,
                    actingRole: .selfManaged,
                    careContext: .home
                )
            )

            #expect(!response.isSourceLinked)
            #expect(response.citations.isEmpty)
            #expect(response.answer.contains("will not guess"))
        }
    }

    @Test("Missing active pack fails closed")
    func missingPackFailsClosed() async {
        let engine = LocalEvidenceEngine(modelPackProvider: ThrowingModelPackProvider())
        let availability = await engine.availability()
        #expect(!availability.isReady)

        do {
            _ = try await engine.ask(adultRequest())
            Issue.record("A missing verified pack must not produce an answer")
        } catch let error as AIEngineError {
            #expect(error == .onDeviceModelUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("A provider root without a verified manifest fails closed")
    func corruptPackFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "paceback-corrupt-pack-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = LocalEvidenceEngine(modelPackProvider: FixedModelPackProvider(root: root))

        #expect(!(await engine.availability()).isReady)
        do {
            _ = try await engine.ask(adultRequest())
            Issue.record("A corrupt pack must not produce an answer")
        } catch let error as AIEngineError {
            #expect(error == .invalidModelPack)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func adultRequest() -> EvidenceRequest {
        EvidenceRequest(
            question: "What does the evidence say about work support?",
            profileID: UUID(),
            ageBand: .adult18To64,
            actingRole: .selfManaged,
            careContext: .work
        )
    }

    private func document(_ id: String, scope: String, content: String) -> EvidenceDocument {
        EvidenceDocument(
            id: id,
            title: "Source \(id)",
            url: URL(string: "https://example.invalid/\(id)")!,
            published: "2026-08-25",
            scope: scope,
            content: content
        )
    }
}

private final class FixedModelPackProvider: ModelPackProviding, @unchecked Sendable {
    let root: URL

    init(root: URL) { self.root = root }

    func installedRootURL() throws -> URL { root }
}

private struct ThrowingModelPackProvider: ModelPackProviding, Sendable {
    func installedRootURL() throws -> URL { throw AIEngineError.onDeviceModelUnavailable }
}

private actor RecordingInference: EvidenceInference {
    private var passages: [String] = []
    private var calls = 0

    func embedding(for text: String, isQuery: Bool) async throws -> [Float] {
        calls += 1
        if !isQuery { passages.append(text) }
        return vector(for: text)
    }

    func relevance(query: String, passage: String) async throws -> Float {
        calls += 1
        passages.append(passage)
        let stopwords: Set<Substring> = [
            "about", "are", "could", "does", "from", "have", "how", "into", "should", "the",
            "this", "what", "which", "with", "would", "your"
        ]
        let queryTerms = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }
            .filter { $0.count > 2 && !stopwords.contains($0) })
        let passageTerms = Set(passage.lowercased().split { !$0.isLetter && !$0.isNumber }
            .filter { $0.count > 2 && !stopwords.contains($0) })
        let overlap = queryTerms.intersection(passageTerms).count
        return overlap == 0 ? -10 : Float(overlap)
    }

    func observedPassages() -> [String] { passages }
    func callCount() -> Int { calls }

    private func vector(for text: String) -> [Float] {
        let normalized = text.lowercased()
        var result: [Float] = [
            normalized.contains("school") ? 1 : 0,
            normalized.contains("work") ? 1 : 0,
            normalized.contains("danger") ? 1 : 0
        ]
        if result == [0, 0, 0] { result = [0.1, 0.1, 0.1] }
        let norm = sqrt(result.reduce(Float.zero) { $0 + $1 * $1 })
        return result.map { $0 / norm }
    }
}

private struct EngineFixture {
    let root: URL
    let corpus: EvidenceCorpus
    let inference: RecordingInference
    let engine: LocalEvidenceEngine

    init(documents: [EvidenceDocument]) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "paceback-engine-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        corpus = try EvidenceCorpus(documents: documents)
        inference = RecordingInference()
        engine = LocalEvidenceEngine(
            modelPackProvider: FixedModelPackProvider(root: root),
            corpus: corpus,
            inference: inference
        )
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
