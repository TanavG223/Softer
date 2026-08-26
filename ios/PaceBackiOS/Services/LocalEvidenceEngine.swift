@preconcurrency import OnnxRuntimeBindings
import CryptoKit
import Foundation

private let bgeQueryPrefix = "Represent this sentence for searching relevant passages: "
private let clearanceAbstention =
    "PaceBack cannot diagnose, predict recovery, choose treatment, or determine school, work, driving, exercise, or sports clearance. Ask a qualified healthcare professional who knows the person and their confirmed care plan."
private let unsupportedAbstention =
    "I could not find enough age-appropriate support in the installed evidence. PaceBack will not guess. Try a narrower evidence question or ask a qualified healthcare professional."
// Prototype-only support gates, selected from a small frozen-model smoke probe
// on 2026-08-25. These are not clinically calibrated and must be reviewed on a
// held-out evidence-QA set before any correctness claim or promotion.
private let lexicalRerankerFloor: Float = -7.0
private let semanticRerankerFloor: Float = 1.0
private let minimumTopMargin: Float = 1.5

struct EvidenceDocument: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let url: URL
    let published: String
    let scope: String
    let content: String
}

struct EvidencePassage: Equatable, Sendable {
    let id: String
    let sourceID: String
    let title: String
    let url: URL
    let published: String
    let scope: String
    let content: String
    let contentHash: String
}

struct EvidenceCorpus: Sendable {
    let passages: [EvidencePassage]

    init(documents: [EvidenceDocument]) throws {
        let allowedScopes = Set(["allAges"] + AgeBand.allCases.map(\.rawValue))
        var seenDocumentIDs: Set<String> = []
        var built: [EvidencePassage] = []

        for document in documents {
            guard !document.id.isEmpty,
                  seenDocumentIDs.insert(document.id).inserted,
                  allowedScopes.contains(document.scope),
                  document.url.scheme == "https",
                  !document.title.isEmpty,
                  !document.content.isEmpty else {
                throw AIEngineError.evidenceCorpusUnavailable
            }

            let chunks = Self.chunk(document.content, maximumTerms: 160, overlapTerms: 24)
            for (index, content) in chunks.enumerated() {
                let digest = SHA256.hash(data: Data(content.utf8))
                    .map { String(format: "%02x", $0) }
                    .joined()
                built.append(
                    EvidencePassage(
                        id: "\(document.id)#p\(index + 1)",
                        sourceID: document.id,
                        title: document.title,
                        url: document.url,
                        published: document.published,
                        scope: document.scope,
                        content: content,
                        contentHash: digest
                    )
                )
            }
        }
        guard !built.isEmpty else { throw AIEngineError.evidenceCorpusUnavailable }
        passages = built.sorted { $0.id < $1.id }
    }

    static func loadBundled(bundle: Bundle = .main) throws -> EvidenceCorpus {
        let resourceURL = bundle.url(
            forResource: "evidence_seed",
            withExtension: "json",
            subdirectory: "Evidence"
        ) ?? bundle.url(forResource: "evidence_seed", withExtension: "json")
        guard let resourceURL else { throw AIEngineError.evidenceCorpusUnavailable }
        do {
            let documents = try JSONDecoder().decode(
                [EvidenceDocument].self,
                from: Data(contentsOf: resourceURL, options: .mappedIfSafe)
            )
            return try EvidenceCorpus(documents: documents)
        } catch let error as AIEngineError {
            throw error
        } catch {
            throw AIEngineError.evidenceCorpusUnavailable
        }
    }

    func eligible(for request: EvidenceRequest) throws -> [EvidencePassage] {
        guard request.profileID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              RolePolicy.validRoles(for: request.ageBand).contains(request.actingRole),
              !request.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.question.count <= 2_000 else {
            throw AIEngineError.invalidRequest
        }
        // Filtering occurs before BM25 and dense inference. A wrong-age passage
        // therefore cannot become a candidate through either retrieval path.
        return passages.filter { request.evidenceScopes.contains($0.scope) }
    }

    private static func chunk(_ text: String, maximumTerms: Int, overlapTerms: Int) -> [String] {
        let ranges = lexicalRanges(in: text)
        guard !ranges.isEmpty else { return [] }
        let step = maximumTerms - overlapTerms
        var chunks: [String] = []
        var start = 0
        while start < ranges.count {
            let end = min(start + maximumTerms, ranges.count)
            let lower = ranges[start].lowerBound
            let upper = ranges[end - 1].upperBound
            let content = String(text[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { chunks.append(content) }
            if end == ranges.count { break }
            start += step
        }
        return chunks
    }
}

protocol EvidenceInference: Sendable {
    func embedding(for text: String, isQuery: Bool) async throws -> [Float]
    func relevance(query: String, passage: String) async throws -> Float
}

private actor ONNXEvidenceInference: EvidenceInference {
    private let environment: ORTEnv
    private let denseSession: ORTSession
    private let rerankerSession: ORTSession
    private let denseTokenizer: WordPieceTokenizer
    private let rerankerTokenizer: WordPieceTokenizer

    init(rootURL: URL) throws {
        let denseModel = rootURL.appending(path: "dense/model.onnx")
        let denseTokenizerURL = rootURL.appending(path: "dense/tokenizer.json")
        let rerankerModel = rootURL.appending(path: "reranker/model.onnx")
        let rerankerTokenizerURL = rootURL.appending(path: "reranker/tokenizer.json")

        for url in [denseModel, denseTokenizerURL, rerankerModel, rerankerTokenizerURL] {
            guard url.isFileURL,
                  FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw AIEngineError.invalidModelPack
            }
        }

        denseTokenizer = try WordPieceTokenizer(contentsOf: denseTokenizerURL)
        rerankerTokenizer = try WordPieceTokenizer(contentsOf: rerankerTokenizerURL)
        environment = try ORTEnv(loggingLevel: .warning)

        let denseOptions = try Self.sessionOptions(logID: "paceback-dense")
        let rerankerOptions = try Self.sessionOptions(logID: "paceback-reranker")
        denseSession = try ORTSession(
            env: environment,
            modelPath: denseModel.path(percentEncoded: false),
            sessionOptions: denseOptions
        )
        rerankerSession = try ORTSession(
            env: environment,
            modelPath: rerankerModel.path(percentEncoded: false),
            sessionOptions: rerankerOptions
        )

        guard Set(try denseSession.inputNames()) == ["input_ids", "attention_mask", "token_type_ids"],
              Set(try denseSession.outputNames()) == ["last_hidden_state"],
              Set(try rerankerSession.inputNames()) == ["input_ids", "attention_mask", "token_type_ids"],
              Set(try rerankerSession.outputNames()) == ["logits"] else {
            throw AIEngineError.invalidModelPack
        }
    }

    func embedding(for text: String, isQuery: Bool) async throws -> [Float] {
        let modelInput = isQuery ? bgeQueryPrefix + text : text
        let encoding = try denseTokenizer.encode(modelInput, maxLength: 512)
        let output = try run(
            session: denseSession,
            encoding: encoding,
            outputName: "last_hidden_state"
        )
        let info = try output.tensorTypeAndShapeInfo()
        let shape = info.shape.map(\.intValue)
        guard info.elementType == .float,
              shape == [1, encoding.sequenceLength, 384] else {
            throw AIEngineError.inferenceFailed
        }
        let values = try floats(from: output)
        guard values.count == encoding.sequenceLength * 384 else {
            throw AIEngineError.inferenceFailed
        }
        var classification = Array(values.prefix(384))
        let norm = sqrt(classification.reduce(Float.zero) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 0 else { throw AIEngineError.inferenceFailed }
        for index in classification.indices { classification[index] /= norm }
        return classification
    }

    func relevance(query: String, passage: String) async throws -> Float {
        let encoding = try rerankerTokenizer.encodePair(query, passage, maxLength: 512)
        let output = try run(
            session: rerankerSession,
            encoding: encoding,
            outputName: "logits"
        )
        let info = try output.tensorTypeAndShapeInfo()
        guard info.elementType == .float,
              info.shape.map(\.intValue) == [1, 1] else {
            throw AIEngineError.inferenceFailed
        }
        let values = try floats(from: output)
        guard values.count == 1, values[0].isFinite else {
            throw AIEngineError.inferenceFailed
        }
        return values[0]
    }

    private static func sessionOptions(logID: String) throws -> ORTSessionOptions {
        let options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        try options.setIntraOpNumThreads(2)
        try options.setLogSeverityLevel(.warning)
        try options.setLogID(logID)
        return options
    }

    private func run(
        session: ORTSession,
        encoding: BERTEncoding,
        outputName: String
    ) throws -> ORTValue {
        let inputs = [
            "input_ids": try tensor(encoding.inputIDs),
            "attention_mask": try tensor(encoding.attentionMask),
            "token_type_ids": try tensor(encoding.tokenTypeIDs)
        ]
        let outputs = try session.run(
            withInputs: inputs,
            outputNames: [outputName],
            runOptions: nil
        )
        guard let output = outputs[outputName] else { throw AIEngineError.inferenceFailed }
        return output
    }

    private func tensor(_ values: [Int64]) throws -> ORTValue {
        let data = NSMutableData(length: values.count * MemoryLayout<Int64>.stride)!
        values.withUnsafeBytes { source in
            guard let baseAddress = source.baseAddress else { return }
            data.replaceBytes(in: NSRange(location: 0, length: source.count), withBytes: baseAddress)
        }
        return try ORTValue(
            tensorData: data,
            elementType: .int64,
            shape: [1, NSNumber(value: values.count)]
        )
    }

    private func floats(from value: ORTValue) throws -> [Float] {
        let data = try value.tensorData()
        guard data.length.isMultiple(of: MemoryLayout<Float>.stride) else {
            throw AIEngineError.inferenceFailed
        }
        var result = [Float](
            repeating: 0,
            count: data.length / MemoryLayout<Float>.stride
        )
        result.withUnsafeMutableBytes { destination in
            guard let baseAddress = destination.baseAddress else { return }
            data.getBytes(baseAddress, length: destination.count)
        }
        return result
    }
}

actor LocalEvidenceEngine: AIEngine {
    private struct Candidate: Sendable {
        let passage: EvidencePassage
        var sparseRank: Int?
        var denseRank: Int?
        var rrfScore: Double
        var rerankerScore: Float
        var lexicalOverlap: Int
    }

    private struct RuntimeIdentity: Equatable, Sendable {
        let rootPath: String
        let manifestSHA256: String
    }

    private let modelPackProvider: any ModelPackProviding
    private var corpus: EvidenceCorpus?
    private var inference: (any EvidenceInference)?
    private let injectedInference: Bool
    private var runtimeIdentity: RuntimeIdentity?
    private var embeddingCache: [String: [Float]] = [:]

    init(modelPackProvider: any ModelPackProviding) {
        self.modelPackProvider = modelPackProvider
        corpus = nil
        inference = nil
        injectedInference = false
    }

    init(
        modelPackProvider: any ModelPackProviding,
        corpus: EvidenceCorpus,
        inference: any EvidenceInference
    ) {
        self.modelPackProvider = modelPackProvider
        self.corpus = corpus
        self.inference = inference
        injectedInference = true
    }

    func availability() async -> AIEngineAvailability {
        do {
            let root = try verifiedActiveRoot()
            _ = try loadCorpus()
            if !injectedInference { _ = try identity(for: root) }
            return .ready(modelName: "BGE-small + MiniLM")
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    func ask(_ request: EvidenceRequest) async throws -> EvidenceResponse {
        let started = ContinuousClock.now
        let root = try verifiedActiveRoot()
        let activeCorpus = try loadCorpus()
        let eligible = try activeCorpus.eligible(for: request)
        guard !eligible.isEmpty else { throw AIEngineError.evidenceCorpusUnavailable }

        if Self.requiresProfessionalDecision(request.question) {
            return .abstention(
                clearanceAbstention,
                localInferenceMilliseconds: Self.elapsedMilliseconds(since: started)
            )
        }

        let activeInference = try await loadInference(root: root)
        let sparse = Self.bm25(query: request.question, passages: eligible, limit: 50)
        let queryEmbedding = try await activeInference.embedding(for: request.question, isQuery: true)
        guard queryEmbedding.count == 384 || injectedInference else {
            throw AIEngineError.inferenceFailed
        }

        var denseScores: [(EvidencePassage, Float)] = []
        denseScores.reserveCapacity(eligible.count)
        for passage in eligible {
            let vector: [Float]
            if let cached = embeddingCache[passage.contentHash] {
                vector = cached
            } else {
                vector = try await activeInference.embedding(for: passage.content, isQuery: false)
                embeddingCache[passage.contentHash] = vector
            }
            guard vector.count == queryEmbedding.count else { throw AIEngineError.inferenceFailed }
            denseScores.append((passage, Self.cosine(queryEmbedding, vector)))
        }
        denseScores.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.id < $1.0.id
        }
        let dense = Array(denseScores.prefix(50).map(\.0))

        let sparseRanks = Dictionary(uniqueKeysWithValues: sparse.enumerated().map { ($0.element.id, $0.offset + 1) })
        let denseRanks = Dictionary(uniqueKeysWithValues: dense.enumerated().map { ($0.element.id, $0.offset + 1) })
        let passageByID = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0) })
        var fused: [Candidate] = []
        for passageID in Set(sparseRanks.keys).union(denseRanks.keys) {
            guard let passage = passageByID[passageID] else { throw AIEngineError.inferenceFailed }
            let sparseRank = sparseRanks[passageID]
            let denseRank = denseRanks[passageID]
            let score = (sparseRank.map { 1.0 / Double(60 + $0) } ?? 0)
                + (denseRank.map { 1.0 / Double(60 + $0) } ?? 0)
            fused.append(
                Candidate(
                    passage: passage,
                    sparseRank: sparseRank,
                    denseRank: denseRank,
                    rrfScore: score,
                    rerankerScore: -.infinity,
                    lexicalOverlap: Self.meaningfulLexicalOverlap(request.question, passage.content)
                )
            )
        }
        fused.sort {
            if $0.rrfScore != $1.rrfScore { return $0.rrfScore > $1.rrfScore }
            return $0.passage.id < $1.passage.id
        }

        var reranked: [Candidate] = []
        for var candidate in fused.prefix(30) {
            candidate.rerankerScore = try await activeInference.relevance(
                query: request.question,
                passage: candidate.passage.content
            )
            guard candidate.rerankerScore.isFinite else { throw AIEngineError.inferenceFailed }
            reranked.append(candidate)
        }
        reranked.sort {
            if $0.rerankerScore != $1.rerankerScore { return $0.rerankerScore > $1.rerankerScore }
            if $0.rrfScore != $1.rrfScore { return $0.rrfScore > $1.rrfScore }
            return $0.passage.id < $1.passage.id
        }

        var uniqueReranked: [Candidate] = []
        var rankedContentHashes: Set<String> = []
        for candidate in reranked where rankedContentHashes.insert(candidate.passage.contentHash).inserted {
            uniqueReranked.append(candidate)
        }

        guard let best = uniqueReranked.first else {
            return .abstention(
                unsupportedAbstention,
                localInferenceMilliseconds: Self.elapsedMilliseconds(since: started)
            )
        }
        let runnerUpScore = uniqueReranked.dropFirst()
            .first(where: { $0.passage.sourceID != best.passage.sourceID })?
            .rerankerScore ?? -.infinity
        let hasSupport = Self.hasSupport(best)
        let hasSeparation = !runnerUpScore.isFinite
            || best.rerankerScore - runnerUpScore >= minimumTopMargin
        guard hasSupport, hasSeparation else {
            return .abstention(
                unsupportedAbstention,
                localInferenceMilliseconds: Self.elapsedMilliseconds(since: started)
            )
        }

        var selected: [Candidate] = []
        var seenContent: Set<String> = []
        var perSource: [String: Int] = [:]
        for candidate in uniqueReranked {
            guard Self.hasSupport(candidate),
                  seenContent.insert(candidate.passage.contentHash).inserted,
                  perSource[candidate.passage.sourceID, default: 0] < 3 else {
                continue
            }
            selected.append(candidate)
            perSource[candidate.passage.sourceID, default: 0] += 1
            if selected.count == 8 { break }
        }

        return Self.extractiveResponse(
            question: request.question,
            candidates: selected,
            localInferenceMilliseconds: Self.elapsedMilliseconds(since: started)
        )
    }

    private func verifiedActiveRoot() throws -> URL {
        do {
            let root = try modelPackProvider.installedRootURL()
            guard root.isFileURL else { throw AIEngineError.invalidModelPack }
            return root
        } catch let error as AIEngineError {
            throw error
        } catch {
            throw AIEngineError.onDeviceModelUnavailable
        }
    }

    private func loadCorpus() throws -> EvidenceCorpus {
        if let corpus { return corpus }
        let loaded = try EvidenceCorpus.loadBundled()
        corpus = loaded
        return loaded
    }

    private func loadInference(root: URL) async throws -> any EvidenceInference {
        if injectedInference, let inference { return inference }
        let newIdentity = try identity(for: root)
        if runtimeIdentity != newIdentity {
            inference = nil
            embeddingCache.removeAll(keepingCapacity: false)
            runtimeIdentity = newIdentity
        }
        if let inference { return inference }
        do {
            let loaded = try ONNXEvidenceInference(rootURL: root)
            inference = loaded
            return loaded
        } catch let error as AIEngineError {
            throw error
        } catch {
            throw AIEngineError.inferenceFailed
        }
    }

    private func identity(for root: URL) throws -> RuntimeIdentity {
        let manifestURL = root.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            throw AIEngineError.invalidModelPack
        }
        let data = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return RuntimeIdentity(
            rootPath: root.standardizedFileURL.path(percentEncoded: false),
            manifestSHA256: digest
        )
    }

    static func bm25(query: String, passages: [EvidencePassage], limit: Int) -> [EvidencePassage] {
        let queryTerms = lexicalTokens(query)
        guard !queryTerms.isEmpty, !passages.isEmpty else { return [] }
        let documentTerms = passages.map { lexicalTokens($0.content) }
        let averageLength = Double(documentTerms.reduce(0) { $0 + $1.count }) / Double(documentTerms.count)
        let documentCount = Double(passages.count)
        let queryFrequencies = Self.frequencies(queryTerms)
        var scored: [(EvidencePassage, Double)] = []

        for (index, passage) in passages.enumerated() {
            let terms = documentTerms[index]
            let frequencies = Self.frequencies(terms)
            var score = 0.0
            for (term, queryFrequency) in queryFrequencies {
                guard let termFrequency = frequencies[term] else { continue }
                let documentsContainingTerm = documentTerms.reduce(0) { count, candidate in
                    count + (candidate.contains(term) ? 1 : 0)
                }
                let idf = log(
                    1 + (documentCount - Double(documentsContainingTerm) + 0.5)
                        / (Double(documentsContainingTerm) + 0.5)
                )
                let tf = Double(termFrequency)
                let lengthNormalization = 1 - 0.75 + 0.75 * Double(terms.count) / max(averageLength, 1)
                score += Double(queryFrequency) * idf * (tf * 2.2) / (tf + 1.2 * lengthNormalization)
            }
            if score > 0 { scored.append((passage, score)) }
        }
        scored.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.id < $1.0.id
        }
        return Array(scored.prefix(limit).map(\.0))
    }

    private static func extractiveResponse(
        question: String,
        candidates: [Candidate],
        localInferenceMilliseconds: Int
    ) -> EvidenceResponse {
        var lines: [String] = []
        var citations: [EvidenceCitation] = []
        for candidate in candidates {
            guard let sentence = bestSentence(question: question, content: candidate.passage.content),
                  candidate.passage.content.contains(sentence) else {
                continue
            }
            let number = citations.count + 1
            lines.append("\(number). \(sentence) [\(number)]")
            citations.append(
                EvidenceCitation(
                    number: number,
                    title: candidate.passage.title,
                    published: candidate.passage.published,
                    sourceID: candidate.passage.sourceID,
                    passageID: candidate.passage.id,
                    url: candidate.passage.url,
                    exactQuote: sentence,
                    contentHash: candidate.passage.contentHash
                )
            )
            if citations.count == 8 { break }
        }
        guard !citations.isEmpty else {
            return .abstention(
                unsupportedAbstention,
                localInferenceMilliseconds: localInferenceMilliseconds
            )
        }
        return EvidenceResponse(
            answer: "Relevant source excerpts:\n" + lines.joined(separator: "\n"),
            citations: citations,
            isSourceLinked: true,
            localInferenceMilliseconds: localInferenceMilliseconds
        )
    }

    private static func bestSentence(question: String, content: String) -> String? {
        let queryTerms = Set(meaningfulLexicalTokens(question))
        let candidates = content.matches(of: /[^.!?\n]+(?:[.!?]+|$)/).map {
            String(content[$0.range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return candidates.enumerated().max {
            let leftOverlap = queryTerms.intersection(meaningfulLexicalTokens($0.element)).count
            let rightOverlap = queryTerms.intersection(meaningfulLexicalTokens($1.element)).count
            if leftOverlap != rightOverlap { return leftOverlap < rightOverlap }
            return $0.offset > $1.offset
        }?.element
    }

    private static func requiresProfessionalDecision(_ question: String) -> Bool {
        let normalized = lexicalTokens(question).joined(separator: " ")
        let terms = Set(normalized.split(separator: " ").map(String.init))
        if !terms.isDisjoint(with: [
            "diagnose", "diagnosis", "dose", "dosage", "prescribe", "prescription",
            "prognosis", "cleared", "clearance"
        ]) { return true }
        if normalized.contains("when will i recover") || normalized.contains("do i have a concussion") {
            return true
        }
        let personalDecision = ["can i", "may i", "am i", "should i", "is it safe"]
            .contains { normalized.contains($0) }
        let controlledActivity = !terms.isDisjoint(with: [
            "return", "drive", "driving", "play", "sport", "sports", "school", "work",
            "exercise", "run", "practice", "compete"
        ])
        return personalDecision && controlledActivity
    }

    private static func cosine(_ left: [Float], _ right: [Float]) -> Float {
        guard left.count == right.count, !left.isEmpty else { return -.infinity }
        return zip(left, right).reduce(Float.zero) { $0 + $1.0 * $1.1 }
    }

    private static func hasSupport(_ candidate: Candidate) -> Bool {
        (candidate.lexicalOverlap > 0 && candidate.rerankerScore >= lexicalRerankerFloor)
            || candidate.rerankerScore >= semanticRerankerFloor
    }

    private static func meaningfulLexicalOverlap(_ query: String, _ passage: String) -> Int {
        Set(meaningfulLexicalTokens(query)).intersection(meaningfulLexicalTokens(passage)).count
    }

    private static func frequencies(_ terms: [String]) -> [String: Int] {
        terms.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Int {
        let components = start.duration(to: .now).components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return max(0, Int(milliseconds.rounded()))
    }
}

private func lexicalRanges(in text: String) -> [Range<String.Index>] {
    text.matches(of: /[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)?/).map(\.range)
}

private func lexicalTokens(_ text: String) -> [String] {
    lexicalRanges(in: text).map {
        text[$0].lowercased().replacingOccurrences(of: "’", with: "'")
    }
}

private let evidenceStopwords: Set<String> = [
    "a", "about", "after", "again", "all", "also", "am", "an", "and", "any", "are",
    "as", "at", "be", "because", "been", "before", "being", "between", "both", "but",
    "by", "can", "could", "did", "do", "does", "doing", "during", "each", "for", "from",
    "had", "has", "have", "having", "he", "her", "here", "hers", "herself", "him", "himself",
    "his", "how", "i", "if", "in", "into", "is", "it", "its", "itself", "just", "may", "me",
    "more", "most", "my", "myself", "no", "nor", "not", "of", "on", "once", "only", "or",
    "other", "our", "ours", "ourselves", "out", "over", "same", "she", "should", "so", "some",
    "such", "than", "that", "the", "their", "theirs", "them", "themselves", "then", "there",
    "these", "they", "this", "those", "through", "to", "too", "under", "until", "up", "very",
    "was", "we", "were", "what", "when", "where", "which", "while", "who", "whom", "why",
    "will", "with", "would", "you", "your", "yours", "yourself", "yourselves"
]

private func meaningfulLexicalTokens(_ text: String) -> [String] {
    lexicalTokens(text).filter { token in
        token.count > 2 && !evidenceStopwords.contains(token)
    }
}
