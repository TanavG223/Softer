import AppKit
import PDFKit
import XCTest
@testable import PaceBackCore

final class CarePlanImporterTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "PaceBackCarePlanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testRejectsNonPDFExtensionEvenWhenHeaderLooksLikePDF() async throws {
        let url = temporaryDirectory.appending(path: "plan.txt")
        try Data("%PDF-not-a-document".utf8).write(to: url)

        await assertImportError(.unsupported(.notPDF)) {
            try await PDFCarePlanImporter().importDraft(from: url, profileID: UUID())
        }
    }

    func testRejectsForgedPDFExtensionWithoutPDFSignature() async throws {
        let url = temporaryDirectory.appending(path: "plan.pdf")
        try Data("plain text".utf8).write(to: url)

        await assertImportError(.unsupported(.notPDF)) {
            try await PDFCarePlanImporter().importDraft(from: url, profileID: UUID())
        }
    }

    func testRejectsDirectoryAsUnsupportedFile() async {
        let url = temporaryDirectory.appending(path: "folder.pdf", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        await assertImportError(.unsupported(.notRegularFile)) {
            try await PDFCarePlanImporter().importDraft(from: url, profileID: UUID())
        }
    }

    func testRejectsFileOverConfiguredByteLimit() async throws {
        let url = try writeTextPDF(["Limit screen time to 10 minutes."], named: "large.pdf")
        let limits = limits(maxFileBytes: 4)

        await assertImportError(.resourceLimit(resource: .fileBytes, maximum: 4)) {
            try await PDFCarePlanImporter(limits: limits).importDraft(from: url, profileID: UUID())
        }
    }

    func testRejectsDocumentOverConfiguredPageLimit() async throws {
        let url = try writeTextPDF(["Page one has enough text.", "Page two has enough text."], named: "pages.pdf")
        let limits = limits(maxPages: 1)

        await assertImportError(.resourceLimit(resource: .pages, maximum: 1)) {
            try await PDFCarePlanImporter(limits: limits).importDraft(from: url, profileID: UUID())
        }
    }

    func testRejectsExtractedTextOverConfiguredCharacterLimit() async throws {
        let url = try writeTextPDF(
            ["Limit screen use and take a break after ten minutes."],
            named: "text-limit.pdf"
        )
        let limits = limits(maxExtractedCharacters: 10, maxOCRPages: 0)

        await assertImportError(.resourceLimit(resource: .extractedCharacters, maximum: 10)) {
            try await PDFCarePlanImporter(limits: limits).importDraft(from: url, profileID: UUID())
        }
    }

    func testRejectsOCRBeyondConfiguredPageLimit() async throws {
        let url = try writeBlankImagePDF(named: "scan.pdf")
        let limits = limits(maxOCRPages: 0)

        await assertImportError(.resourceLimit(resource: .ocrPages, maximum: 0)) {
            try await PDFCarePlanImporter(limits: limits).importDraft(from: url, profileID: UUID())
        }
    }

    func testRejectsWorkWhenDeadlineAlreadyExpired() async throws {
        let url = try writeTextPDF(["Limit screen time to 10 minutes."], named: "deadline.pdf")
        let limits = limits(maxProcessingSeconds: 0)

        await assertImportError(.resourceLimit(resource: .processingSeconds, maximum: 0)) {
            try await PDFCarePlanImporter(limits: limits).importDraft(from: url, profileID: UUID())
        }
    }

    func testExtractsPageCitedRestrictionFromValidPDF() async throws {
        let profileID = UUID()
        let url = try writeTextPDF(
            ["Clinician plan\nLimit screen time to 10 minutes and take a break."],
            named: "valid.pdf"
        )

        let draft = try await PDFCarePlanImporter().importDraft(from: url, profileID: profileID)

        XCTAssertEqual(draft.profileID, profileID)
        XCTAssertEqual(draft.sourceName, "valid.pdf")
        XCTAssertEqual(draft.restrictions.first?.page, 1)
        XCTAssertTrue(draft.restrictions.first?.text.contains("Limit screen time") == true)
        XCTAssertTrue(draft.restrictions.allSatisfy { !$0.isConfirmed })
    }

    func testPackagedSyntheticDemoPlansAreImportableAndRemainUnconfirmed() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectory = repositoryRoot.appending(path: "output/pdf", directoryHint: .isDirectory)
        let fixtureNames = [
            "synthetic-child-school.pdf",
            "synthetic-teen-school.pdf",
            "synthetic-adult-work.pdf",
            "synthetic-older-adult.pdf"
        ]

        for fixtureName in fixtureNames {
            let draft = try await PDFCarePlanImporter().importDraft(
                from: fixtureDirectory.appending(path: fixtureName),
                profileID: UUID()
            )
            XCTAssertEqual(draft.sourceName, fixtureName)
            XCTAssertFalse(draft.restrictions.isEmpty)
            XCTAssertTrue(draft.restrictions.contains { $0.page == 1 })
            XCTAssertTrue(draft.restrictions.contains { $0.page == 2 })
            XCTAssertTrue(draft.restrictions.allSatisfy { !$0.isConfirmed })
        }
    }

    func testCancellationFailsBeforeParsing() async throws {
        let url = try writeTextPDF(["Limit screen time to 10 minutes."], named: "cancelled.pdf")
        let task = Task {
            try Task.checkCancellation()
            return try await PDFCarePlanImporter().importDraft(from: url, profileID: UUID())
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected fail-closed cancellation.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
    }

    private func limits(
        maxFileBytes: Int = 25 * 1_048_576,
        maxPages: Int = 100,
        maxExtractedCharacters: Int = 200_000,
        maxOCRPages: Int = 20,
        maxProcessingSeconds: Int = 30
    ) -> CarePlanImportLimits {
        CarePlanImportLimits(
            maxFileBytes: maxFileBytes,
            maxPages: maxPages,
            maxExtractedCharacters: maxExtractedCharacters,
            maxOCRPages: maxOCRPages,
            maxProcessingSeconds: maxProcessingSeconds
        )
    }

    private func assertImportError(
        _ expected: CarePlanImportError,
        operation: () async throws -> CarePlanDraft
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as CarePlanImportError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Expected CarePlanImportError, received \(error)")
        }
    }

    private func writeTextPDF(_ pageTexts: [String], named name: String) throws -> URL {
        let url = temporaryDirectory.appending(path: name)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        for text in pageTexts {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSString(string: text).draw(
                in: CGRect(x: 54, y: 650, width: 504, height: 100),
                withAttributes: [.font: NSFont.systemFont(ofSize: 16)]
            )
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    private func writeBlankImagePDF(named name: String) throws -> URL {
        let image = NSImage(size: NSSize(width: 300, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 300, height: 300).fill()
        image.unlockFocus()

        guard let page = PDFPage(image: image) else { throw CocoaError(.fileWriteUnknown) }
        let document = PDFDocument()
        document.insert(page, at: 0)
        let url = temporaryDirectory.appending(path: name)
        guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
