import SwiftUI

enum PaceBackDesign {
    static let accent = Color(red: 0.11, green: 0.45, blue: 0.46)
    static let accentDeep = Color(red: 0.04, green: 0.24, blue: 0.31)
    static let calmBlue = Color(red: 0.18, green: 0.38, blue: 0.61)
    static let warm = Color(red: 0.80, green: 0.46, blue: 0.19)
    static let critical = Color(red: 0.72, green: 0.13, blue: 0.14)
    static let cornerRadius: CGFloat = 20
    static let minimumControlHeight: CGFloat = 44
}

struct PaceBackMark: View {
    let size: CGFloat

    init(size: CGFloat = 44) {
        self.size = size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [PaceBackDesign.accentDeep, PaceBackDesign.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Path { path in
                path.move(to: CGPoint(x: size * 0.20, y: size * 0.65))
                path.addCurve(
                    to: CGPoint(x: size * 0.80, y: size * 0.36),
                    control1: CGPoint(x: size * 0.37, y: size * 0.86),
                    control2: CGPoint(x: size * 0.57, y: size * 0.20)
                )
            }
            .stroke(
                .white.opacity(0.95),
                style: StrokeStyle(lineWidth: max(2, size * 0.065), lineCap: .round)
            )
            Circle()
                .fill(PaceBackDesign.warm)
                .frame(width: size * 0.17, height: size * 0.17)
                .offset(x: size * 0.23, y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PaceBackCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            if !reduceTransparency && contrast != .increased {
                LinearGradient(
                    colors: [
                        PaceBackDesign.calmBlue.opacity(colorScheme == .dark ? 0.12 : 0.07),
                        .clear,
                        PaceBackDesign.accent.opacity(colorScheme == .dark ? 0.08 : 0.045)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct PaceBackCard<Content: View>: View {
    enum Style {
        case standard
        case prominent
        case quiet
        case caution
    }

    @Environment(\.colorSchemeContrast) private var contrast
    private let style: Style
    private let content: Content

    init(style: Style = .standard, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: PaceBackDesign.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaceBackDesign.cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: contrast == .increased ? 1.8 : 1)
            }
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .standard:
            AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.96))
        case .prominent:
            AnyShapeStyle(
                LinearGradient(
                    colors: [PaceBackDesign.accent.opacity(0.17), PaceBackDesign.calmBlue.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .quiet:
            AnyShapeStyle(Color.primary.opacity(0.045))
        case .caution:
            AnyShapeStyle(PaceBackDesign.warm.opacity(0.12))
        }
    }

    private var stroke: Color {
        switch style {
        case .standard: .secondary.opacity(0.20)
        case .prominent: PaceBackDesign.accent.opacity(0.38)
        case .quiet: .secondary.opacity(0.14)
        case .caution: PaceBackDesign.warm.opacity(0.42)
        }
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    init(_ title: String, detail: String, eyebrow: String = "PRIVATE RECOVERY WORKSPACE") {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [PaceBackDesign.warm, PaceBackDesign.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 76)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.caption2.bold())
                    .tracking(1.0)
                    .foregroundStyle(PaceBackDesign.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct StatusPill: View {
    enum Kind {
        case local
        case caution
        case informational

        var color: Color {
            switch self {
            case .local: PaceBackDesign.accent
            case .caution: PaceBackDesign.warm
            case .informational: PaceBackDesign.calmBlue
            }
        }

        var symbol: String {
            switch self {
            case .local: "checkmark.shield.fill"
            case .caution: "exclamationmark.triangle.fill"
            case .informational: "info.circle.fill"
            }
        }
    }

    let text: String
    let kind: Kind

    var body: some View {
        Label(text, systemImage: kind.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(kind.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(kind.color.opacity(0.12), in: Capsule())
            .overlay { Capsule().strokeBorder(kind.color.opacity(0.24)) }
            .accessibilityElement(children: .combine)
    }
}

struct ProfileStrip: View {
    let profile: LocalProfile

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { pills }
            VStack(alignment: .leading, spacing: 8) { pills }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var pills: some View {
        StatusPill(text: profile.ageBand.title, kind: .informational)
        StatusPill(text: profile.actingRole.title, kind: .local)
        StatusPill(text: profile.careContext.title, kind: .informational)
    }
}

struct SafetyBoundaryNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(PaceBackDesign.warm)
                .accessibilityHidden(true)
            Text("Research prototype. PaceBack does not diagnose, predict recovery, prescribe treatment, or provide school, work, driving, or sports clearance. It supports—not replaces—professional care.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaceBackDesign.warm.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func paceBackControlTarget() -> some View {
        frame(minHeight: PaceBackDesign.minimumControlHeight)
            .contentShape(Rectangle())
    }
}
