import Foundation

enum WordPieceTokenizerError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration(String)
    case inputTooShort

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let detail):
            "The downloaded tokenizer is not compatible with PaceBack: \(detail)"
        case .inputTooShort:
            "The model context is too short for the required BERT special tokens."
        }
    }
}

struct BERTEncoding: Equatable, Sendable {
    let inputIDs: [Int64]
    let attentionMask: [Int64]
    let tokenTypeIDs: [Int64]

    var sequenceLength: Int { inputIDs.count }
}

/// The exact tokenizer contract used by both frozen PaceBack ONNX artifacts.
///
/// The downloaded `tokenizer.json` declares a lowercase BertNormalizer,
/// BertPreTokenizer, WordPiece vocabulary, and the standard BERT template:
/// `[CLS] A [SEP]` or `[CLS] A [SEP] B [SEP]`. No tokenizer code or vocabulary
/// is fetched independently of the verified model pack.
struct WordPieceTokenizer: Sendable {
    private struct TokenizerFile: Decodable {
        let normalizer: Normalizer
        let preTokenizer: PreTokenizer
        let model: Model

        enum CodingKeys: String, CodingKey {
            case normalizer
            case preTokenizer = "pre_tokenizer"
            case model
        }
    }

    private struct Normalizer: Decodable {
        let type: String
        let cleanText: Bool
        let handleChineseCharacters: Bool
        let stripAccents: Bool?
        let lowercase: Bool

        enum CodingKeys: String, CodingKey {
            case type
            case cleanText = "clean_text"
            case handleChineseCharacters = "handle_chinese_chars"
            case stripAccents = "strip_accents"
            case lowercase
        }
    }

    private struct PreTokenizer: Decodable {
        let type: String
    }

    private struct Model: Decodable {
        let type: String
        let vocab: [String: Int64]
        let unknownToken: String
        let continuingPrefix: String
        let maxCharactersPerWord: Int

        enum CodingKeys: String, CodingKey {
            case type
            case vocab
            case unknownToken = "unk_token"
            case continuingPrefix = "continuing_subword_prefix"
            case maxCharactersPerWord = "max_input_chars_per_word"
        }
    }

    let vocabulary: [String: Int64]
    let unknownToken: String
    let continuingPrefix: String
    let maxCharactersPerWord: Int
    let lowercase: Bool
    let stripAccents: Bool
    let cleanText: Bool
    let handleChineseCharacters: Bool

    let paddingID: Int64
    let unknownID: Int64
    let classificationID: Int64
    let separatorID: Int64

    init(contentsOf fileURL: URL) throws {
        try self.init(data: Data(contentsOf: fileURL, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        let document: TokenizerFile
        do {
            document = try JSONDecoder().decode(TokenizerFile.self, from: data)
        } catch {
            throw WordPieceTokenizerError.invalidConfiguration("tokenizer.json could not be decoded")
        }

        guard document.normalizer.type == "BertNormalizer" else {
            throw WordPieceTokenizerError.invalidConfiguration("normalizer must be BertNormalizer")
        }
        guard document.preTokenizer.type == "BertPreTokenizer" else {
            throw WordPieceTokenizerError.invalidConfiguration("pre-tokenizer must be BertPreTokenizer")
        }
        guard document.model.type == "WordPiece" else {
            throw WordPieceTokenizerError.invalidConfiguration("model must be WordPiece")
        }
        guard document.model.vocab.count == 30_522 else {
            throw WordPieceTokenizerError.invalidConfiguration("expected the pinned 30,522-token vocabulary")
        }
        guard document.model.unknownToken == "[UNK]",
              document.model.continuingPrefix == "##",
              document.model.maxCharactersPerWord == 100 else {
            throw WordPieceTokenizerError.invalidConfiguration("WordPiece parameters do not match the pinned artifacts")
        }
        guard document.normalizer.lowercase,
              document.normalizer.cleanText,
              document.normalizer.handleChineseCharacters else {
            throw WordPieceTokenizerError.invalidConfiguration("BERT normalization flags do not match the pinned artifacts")
        }
        guard let paddingID = document.model.vocab["[PAD]"], paddingID == 0,
              let unknownID = document.model.vocab["[UNK]"], unknownID == 100,
              let classificationID = document.model.vocab["[CLS]"], classificationID == 101,
              let separatorID = document.model.vocab["[SEP]"], separatorID == 102 else {
            throw WordPieceTokenizerError.invalidConfiguration("BERT special-token IDs do not match the model contract")
        }

        vocabulary = document.model.vocab
        unknownToken = document.model.unknownToken
        continuingPrefix = document.model.continuingPrefix
        maxCharactersPerWord = document.model.maxCharactersPerWord
        lowercase = document.normalizer.lowercase
        // Hugging Face BertNormalizer treats nil as matching `lowercase`.
        stripAccents = document.normalizer.stripAccents ?? document.normalizer.lowercase
        cleanText = document.normalizer.cleanText
        handleChineseCharacters = document.normalizer.handleChineseCharacters
        self.paddingID = paddingID
        self.unknownID = unknownID
        self.classificationID = classificationID
        self.separatorID = separatorID
    }

    func encode(_ text: String, maxLength: Int = 512) throws -> BERTEncoding {
        guard maxLength >= 2 else { throw WordPieceTokenizerError.inputTooShort }
        let content = Array(tokenIDs(for: text).prefix(maxLength - 2))
        let inputIDs = [classificationID] + content + [separatorID]
        return BERTEncoding(
            inputIDs: inputIDs,
            attentionMask: Array(repeating: 1, count: inputIDs.count),
            tokenTypeIDs: Array(repeating: 0, count: inputIDs.count)
        )
    }

    func encodePair(_ first: String, _ second: String, maxLength: Int = 512) throws -> BERTEncoding {
        guard maxLength >= 3 else { throw WordPieceTokenizerError.inputTooShort }
        var firstIDs = tokenIDs(for: first)
        var secondIDs = tokenIDs(for: second)
        let contentLimit = maxLength - 3

        // This matches BERT's deterministic longest-first truncation for a pair.
        while firstIDs.count + secondIDs.count > contentLimit {
            if firstIDs.count > secondIDs.count {
                firstIDs.removeLast()
            } else {
                secondIDs.removeLast()
            }
        }

        let inputIDs = [classificationID] + firstIDs + [separatorID] + secondIDs + [separatorID]
        let firstSegmentCount = firstIDs.count + 2
        let secondSegmentCount = secondIDs.count + 1
        return BERTEncoding(
            inputIDs: inputIDs,
            attentionMask: Array(repeating: 1, count: inputIDs.count),
            tokenTypeIDs: Array(repeating: 0, count: firstSegmentCount)
                + Array(repeating: 1, count: secondSegmentCount)
        )
    }

    func tokenIDs(for text: String) -> [Int64] {
        preTokenize(normalize(text)).flatMap { wordPieceIDs(for: $0) }
    }

    func normalize(_ text: String) -> String {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(text.unicodeScalars.count)

        for scalar in text.unicodeScalars {
            if cleanText && shouldRemove(scalar) { continue }
            if isWhitespace(scalar) {
                scalars.append(" ")
                continue
            }
            if handleChineseCharacters && isChineseCharacter(scalar) {
                scalars.append(" ")
                scalars.append(scalar)
                scalars.append(" ")
                continue
            }
            scalars.append(scalar)
        }

        var normalized = String(String.UnicodeScalarView(scalars))
        if lowercase { normalized = normalized.lowercased() }
        if stripAccents {
            let decomposed = normalized.decomposedStringWithCanonicalMapping
            normalized = String(
                decomposed.unicodeScalars.filter {
                    !CharacterSet.nonBaseCharacters.contains($0)
                }
            )
        }
        return normalized
    }

    func preTokenize(_ normalized: String) -> [String] {
        var tokens: [String] = []
        var current = String.UnicodeScalarView()

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(String(current))
            current.removeAll(keepingCapacity: true)
        }

        for scalar in normalized.unicodeScalars {
            if isWhitespace(scalar) {
                flush()
            } else if isPunctuation(scalar) {
                flush()
                tokens.append(String(scalar))
            } else {
                current.append(scalar)
            }
        }
        flush()
        return tokens
    }

    private func wordPieceIDs(for token: String) -> [Int64] {
        let characters = Array(token)
        guard characters.count <= maxCharactersPerWord else { return [unknownID] }
        guard !characters.isEmpty else { return [] }

        var ids: [Int64] = []
        var start = 0
        while start < characters.count {
            var end = characters.count
            var matchedID: Int64?
            while start < end {
                let slice = String(characters[start..<end])
                let candidate = start == 0 ? slice : continuingPrefix + slice
                if let id = vocabulary[candidate] {
                    matchedID = id
                    break
                }
                end -= 1
            }
            guard let matchedID else { return [unknownID] }
            ids.append(matchedID)
            start = end
        }
        return ids
    }

    private func shouldRemove(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value == 0 || scalar.value == 0xFFFD { return true }
        if scalar == "\t" || scalar == "\n" || scalar == "\r" { return false }
        return CharacterSet.controlCharacters.contains(scalar)
    }

    private func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
            || CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if (33...47).contains(value) || (58...64).contains(value)
            || (91...96).contains(value) || (123...126).contains(value) {
            return true
        }
        return CharacterSet.punctuationCharacters.contains(scalar)
    }

    private func isChineseCharacter(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value)
            || (0x3400...0x4DBF).contains(value)
            || (0x20000...0x2A6DF).contains(value)
            || (0x2A700...0x2B73F).contains(value)
            || (0x2B740...0x2B81F).contains(value)
            || (0x2B820...0x2CEAF).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0x2F800...0x2FA1F).contains(value)
    }
}
