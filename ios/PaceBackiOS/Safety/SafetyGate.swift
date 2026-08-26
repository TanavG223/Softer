import Foundation

enum DangerSign: String, CaseIterable, Codable, Identifiable, Sendable {
    case worseningHeadache
    case repeatedVomiting
    case seizure
    case lossOfConsciousness
    case weaknessOrNumbness
    case slurredSpeech
    case unusualConfusionOrAgitation
    case onePupilLarger
    case cannotWake
    case neckPainOrTenderness
    case inconsolableCrying
    case refusesToNurseOrEat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .worseningHeadache: "A headache that gets worse and does not go away"
        case .repeatedVomiting: "Repeated vomiting or nausea"
        case .seizure: "Convulsions or seizures"
        case .lossOfConsciousness: "Loss of consciousness"
        case .weaknessOrNumbness: "Weakness, numbness, or decreased coordination"
        case .slurredSpeech: "Slurred speech"
        case .unusualConfusionOrAgitation: "Unusual confusion, restlessness, or agitation"
        case .onePupilLarger: "One pupil larger than the other or double vision"
        case .cannotWake: "Very drowsy or cannot be awakened"
        case .neckPainOrTenderness: "Neck pain or tenderness"
        case .inconsolableCrying: "Will not stop crying and cannot be consoled"
        case .refusesToNurseOrEat: "Will not nurse or eat"
        }
    }

    var isYoungChildSpecific: Bool {
        self == .inconsolableCrying || self == .refusesToNurseOrEat
    }
}

enum SafetyGateResult: Equatable, Sendable {
    case clear
    case emergency(signs: [DangerSign], instructions: String)

    var isEmergency: Bool {
        if case .emergency = self { true } else { false }
    }
}

enum SafetyGate {
    static let emergencyInstructions =
        "Get emergency medical help now. Call 911 or go to the nearest emergency department. Do not wait for an AI response."

    static func signs(for ageBand: AgeBand) -> [DangerSign] {
        DangerSign.allCases.filter { sign in
            !sign.isYoungChildSpecific || ageBand == .youngChild0To5
        }
    }

    static func evaluate(selected: Set<DangerSign>, ageBand: AgeBand) -> SafetyGateResult {
        let permitted = Set(signs(for: ageBand))
        let relevant = selected.intersection(permitted).sorted { $0.rawValue < $1.rawValue }
        guard !relevant.isEmpty else { return .clear }
        return .emergency(signs: relevant, instructions: emergencyInstructions)
    }
}
