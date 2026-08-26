import AppKit
import Foundation
import PDFKit
import Vision

public protocol CarePlanImporting: Sendable {
    func importDraft(from url: URL, profileID: UUID) async throws -> CarePlanDraft
}

public enum CarePlanUnsupportedReason: String, Sendable, Equatable {
    case notRegularFile
    case notPDF
}

public enum CarePlanResource: String, Sendable, Equatable {
    case fileBytes
    case pages
    case extractedCharacters
    case ocrPages
    case processingSeconds
}

public enum CarePlanImportError: LocalizedError, Sendable, Equatable {
    case unsupported(CarePlanUnsupportedReason)
    case resourceLimit(resource: CarePlanResource, maximum: Int)
    case unreadablePDF
    case noTextDetected

    public var errorDescription: String? {
        switch self {
        case .unsupported(.notRegularFile):
            "Choose a regular PDF file. Folders, links, and special files are not supported."
        case .unsupported(.notPDF):
            "Only PDF clinician plans are supported."
        case .resourceLimit(let resource, let maximum):
            switch resource {
            case .fileBytes:
                "The PDF is larger than the \(maximum / 1_048_576) MB import limit."
            case .pages:
                "The PDF has more than the \(maximum)-page import limit."
            case .extractedCharacters:
                "The PDF contains more than \(maximum) extracted characters."
            case .ocrPages:
                "The PDF requires OCR on more than \(maximum) pages."
            case .processingSeconds:
                "PDF processing exceeded the \(maximum)-second time limit."
            }
        case .unreadablePDF: "The selected PDF could not be opened."
        case .noTextDetected: "No readable text was found in this PDF."
        }
    }
}

struct CarePlanImportLimits: Sendable {
    let maxFileBytes: Int
    let maxPages: Int
    let maxExtractedCharacters: Int
    let maxOCRPages: Int
    let maxProcessingSeconds: Int

    static let production = CarePlanImportLimits(
        maxFileBytes: 25 * 1_048_576,
        maxPages: 100,
        maxExtractedCharacters: 200_000,
        maxOCRPages: 20,
        maxProcessingSeconds: 30
    )
}

public actor PDFCarePlanImporter: CarePlanImporting {
    private let limits: CarePlanImportLimits

    public init() {
        self.limits = .production
    }

    init(limits: CarePlanImportLimits) {
        self.limits = limits
    }

    public func importDraft(from url: URL, profileID: UUID) async throws -> CarePlanDraft {
        guard url.startAccessingSecurityScopedResource() else {
            return try await parse(url: url, profileID: profileID)
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try await parse(url: url, profileID: profileID)
    }

    private func parse(url: URL, profileID: UUID) async throws -> CarePlanDraft {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(limits.maxProcessingSeconds))
        try checkBudget(clock: clock, deadline: deadline)
        try preflight(url: url)
        try checkBudget(clock: clock, deadline: deadline)

        guard let document = PDFDocument(url: url) else { throw CarePlanImportError.unreadablePDF }
        guard document.pageCount <= limits.maxPages else {
            throw CarePlanImportError.resourceLimit(resource: .pages, maximum: limits.maxPages)
        }

        var pageTexts: [(page: Int, text: String)] = []
        var extractedCharacterCount = 0
        var ocrPageCount = 0

        for index in 0..<document.pageCount {
            try checkBudget(clock: clock, deadline: deadline)
            guard let page = document.page(at: index) else { continue }
            var text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.count < 20 {
                guard ocrPageCount < limits.maxOCRPages else {
                    throw CarePlanImportError.resourceLimit(
                        resource: .ocrPages,
                        maximum: limits.maxOCRPages
                    )
                }
                ocrPageCount += 1
                text = try recognizeText(on: page)
                try checkBudget(clock: clock, deadline: deadline)
            }
            if !text.isEmpty {
                extractedCharacterCount += text.count
                guard extractedCharacterCount <= limits.maxExtractedCharacters else {
                    throw CarePlanImportError.resourceLimit(
                        resource: .extractedCharacters,
                        maximum: limits.maxExtractedCharacters
                    )
                }
                pageTexts.append((page: index + 1, text: text))
            }
        }

        guard !pageTexts.isEmpty else { throw CarePlanImportError.noTextDetected }
        let keywords = [
            "avoid", "limit", "no ", "return", "break", "minutes", "accommodation",
            "screen", "school", "work", "restriction", "may", "should"
        ]
        var restrictions: [CarePlanRestriction] = []
        for page in pageTexts {
            let lines = page.text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 8 }
            for line in lines where keywords.contains(where: line.localizedCaseInsensitiveContains) {
                restrictions.append(CarePlanRestriction(text: String(line.prefix(500)), page: page.page))
                if restrictions.count == 20 { break }
            }
            if restrictions.count == 20 { break }
        }

        if restrictions.isEmpty, let first = pageTexts.first {
            restrictions = [CarePlanRestriction(text: String(first.text.prefix(500)), page: first.page)]
        }
        return CarePlanDraft(
            profileID: profileID,
            sourceName: url.lastPathComponent,
            restrictions: restrictions
        )
    }

    private func preflight(url: URL) throws {
        try Task.checkCancellation()
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw CarePlanImportError.unreadablePDF
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw CarePlanImportError.unsupported(.notRegularFile)
        }
        guard let byteCount = (attributes[.size] as? NSNumber)?.intValue,
              byteCount <= limits.maxFileBytes else {
            throw CarePlanImportError.resourceLimit(
                resource: .fileBytes,
                maximum: limits.maxFileBytes
            )
        }
        guard url.pathExtension.lowercased() == "pdf" else {
            throw CarePlanImportError.unsupported(.notPDF)
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw CarePlanImportError.unreadablePDF
        }
        defer { try? handle.close() }
        let signature: Data
        do {
            signature = try handle.read(upToCount: 5) ?? Data()
        } catch {
            throw CarePlanImportError.unreadablePDF
        }
        guard signature == Data("%PDF-".utf8) else {
            throw CarePlanImportError.unsupported(.notPDF)
        }
    }

    private func checkBudget(
        clock: ContinuousClock,
        deadline: ContinuousClock.Instant
    ) throws {
        try Task.checkCancellation()
        guard clock.now < deadline else {
            throw CarePlanImportError.resourceLimit(
                resource: .processingSeconds,
                maximum: limits.maxProcessingSeconds
            )
        }
    }

    private func recognizeText(on page: PDFPage) throws -> String {
        let image = page.thumbnail(of: CGSize(width: 2_000, height: 2_000), for: .mediaBox)
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return ""
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
