import SwiftUI

/// Semantic visual tokens for the PaceBack "recovery field guide" aesthetic.
/// The palette stays restrained so evidence, permissions, and safety state—not
/// decoration—carry the hierarchy.
public enum PaceBackDesign {
    public static let contentWidth: CGFloat = 1_080
    public static let sidebarWidth: CGFloat = 252
    public static let cornerRadius: CGFloat = 18
    public static let smallCornerRadius: CGFloat = 12
    public static let compactSpacing: CGFloat = 14
    public static let comfortableSpacing: CGFloat = 22
    public static let minimumControlHeight: CGFloat = 44

    public static let accent = Color(red: 0.13, green: 0.44, blue: 0.46)
    public static let accentDeep = Color(red: 0.07, green: 0.25, blue: 0.34)
    public static let calmBlue = Color(red: 0.20, green: 0.39, blue: 0.60)
    public static let warm = Color(red: 0.75, green: 0.45, blue: 0.22)
    public static let critical = Color(red: 0.72, green: 0.16, blue: 0.15)

    public static func dynamicTypeSize(for scale: Double) -> DynamicTypeSize {
        switch scale {
        case ..<0.96: .small
        case ..<1.08: .medium
        case ..<1.2: .large
        case ..<1.4: .xLarge
        default: .xxLarge
        }
    }

    public static func controlSize(for scale: Double) -> ControlSize {
        scale >= 1.25 ? .extraLarge : .regular
    }
}

/// A compact brand mark made entirely from vector shapes so it remains crisp
/// at sidebar, onboarding, and large-text sizes without a resource dependency.
public struct PaceBackMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 42) {
        self.size = size
    }

    public var body: some View {
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
            .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: max(2, size * 0.065), lineCap: .round))

            Circle()
                .fill(PaceBackDesign.warm)
                .frame(width: size * 0.17, height: size * 0.17)
                .offset(x: size * 0.23, y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

public struct PaceBackCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency && colorSchemeContrast != .increased {
                LinearGradient(
                    colors: [
                        PaceBackDesign.calmBlue.opacity(colorScheme == .dark ? 0.09 : 0.055),
                        .clear,
                        PaceBackDesign.accent.opacity(colorScheme == .dark ? 0.055 : 0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

public struct PaceBackCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public enum Style {
        case standard
        case prominent
        case quiet
        case caution
    }

    private let style: Style
    private let contentPadding: CGFloat
    private let content: Content

    public init(
        style: Style = .standard,
        padding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.contentPadding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: PaceBackDesign.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaceBackDesign.cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: style == .prominent ? 1.25 : 1)
            }
            .shadow(color: shadowColor, radius: 12, y: 4)
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .standard:
            AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.94))
        case .prominent:
            AnyShapeStyle(
                LinearGradient(
                    colors: [PaceBackDesign.accent.opacity(0.14), PaceBackDesign.calmBlue.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .quiet:
            AnyShapeStyle(Color.primary.opacity(0.035))
        case .caution:
            AnyShapeStyle(PaceBackDesign.warm.opacity(0.095))
        }
    }

    private var stroke: Color {
        let multiplier = colorSchemeContrast == .increased ? 1.8 : 1
        switch style {
        case .standard: return .secondary.opacity(0.20 * multiplier)
        case .prominent: return PaceBackDesign.accent.opacity(0.32 * multiplier)
        case .quiet: return .secondary.opacity(0.13 * multiplier)
        case .caution: return PaceBackDesign.warm.opacity(0.35 * multiplier)
        }
    }

    private var shadowColor: Color {
        style == .prominent ? PaceBackDesign.accentDeep.opacity(0.08) : .black.opacity(0.025)
    }
}

public struct ContentScaffold<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let eyebrow: String
    private let spacing: CGFloat
    private let content: Content

    public init(
        _ title: String,
        subtitle: String? = nil,
        eyebrow: String = "PRIVATE RECOVERY WORKSPACE",
        comfortableSpacing: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.spacing = comfortableSpacing ? PaceBackDesign.comfortableSpacing : PaceBackDesign.compactSpacing
        self.content = content()
    }

    public var body: some View {
        ZStack {
            PaceBackCanvasBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    pageHeader
                    content
                }
                .frame(maxWidth: PaceBackDesign.contentWidth, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.top, 34)
                .padding(.bottom, 42)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [PaceBackDesign.warm, PaceBackDesign.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: subtitle == nil ? 58 : 84)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(PaceBackDesign.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

public struct PaceBackSectionHeader: View {
    private let title: String
    private let detail: String?
    private let systemImage: String?

    public init(_ title: String, detail: String? = nil, systemImage: String? = nil) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(PaceBackDesign.accent)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

public struct StatusBadge: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public enum Kind {
        case safe
        case caution
        case informational

        var color: Color {
            switch self {
            case .safe: PaceBackDesign.accent
            case .caution: PaceBackDesign.warm
            case .informational: PaceBackDesign.calmBlue
            }
        }

        var icon: String {
            switch self {
            case .safe: "checkmark.circle.fill"
            case .caution: "exclamationmark.triangle.fill"
            case .informational: "info.circle.fill"
            }
        }
    }

    private let text: String
    private let kind: Kind

    public init(_ text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        Label(text, systemImage: kind.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(kind.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(kind.color.opacity(colorSchemeContrast == .increased ? 0.18 : 0.11), in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    kind.color.opacity(colorSchemeContrast == .increased ? 0.48 : 0.18),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
            }
            .accessibilityElement(children: .combine)
    }
}

public struct ProfileContextStrip: View {
    private let profile: LocalProfile
    private let evidenceFiltered: Bool

    public init(profile: LocalProfile, evidenceFiltered: Bool = false) {
        self.profile = profile
        self.evidenceFiltered = evidenceFiltered
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { tokens }
            VStack(alignment: .leading, spacing: 8) { tokens }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Active profile context: \(profile.ageBand.title), \(profile.actingRole.title), \(profile.careContext.title)"
        )
    }

    @ViewBuilder
    private var tokens: some View {
        ContextToken(icon: "person.crop.circle", text: profile.ageBand.title)
        ContextToken(icon: "person.badge.key", text: profile.actingRole.title)
        ContextToken(icon: "location", text: profile.careContext.title)
        if evidenceFiltered {
            ContextToken(icon: "line.3.horizontal.decrease.circle", text: "Age-filtered evidence")
        }
    }
}

private struct ContextToken: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.045), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

public struct PaceBackNotice: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public enum Style {
        case boundary
        case local
        case caution
        case error

        var icon: String {
            switch self {
            case .boundary: "cross.case"
            case .local: "lock.shield"
            case .caution: "exclamationmark.triangle"
            case .error: "xmark.octagon"
            }
        }

        var color: Color {
            switch self {
            case .boundary: PaceBackDesign.calmBlue
            case .local: PaceBackDesign.accent
            case .caution: PaceBackDesign.warm
            case .error: PaceBackDesign.critical
            }
        }
    }

    private let title: String?
    private let message: String
    private let style: Style

    public init(_ message: String, title: String? = nil, style: Style) {
        self.title = title
        self.message = message
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: style.icon)
                .font(.headline)
                .foregroundStyle(style.color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title).font(.callout.weight(.semibold))
                }
                Text(message)
                    .font(.callout)
                    .foregroundStyle(title == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            style.color.opacity(colorSchemeContrast == .increased ? 0.14 : 0.075),
            in: RoundedRectangle(cornerRadius: PaceBackDesign.smallCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PaceBackDesign.smallCornerRadius)
                .strokeBorder(
                    style.color.opacity(colorSchemeContrast == .increased ? 0.52 : 0.16),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
        }
        .accessibilityElement(children: .combine)
    }
}

public struct SafetyBoundaryNotice: View {
    public init() {}

    public var body: some View {
        PaceBackNotice(
            "PaceBack supports a clinician’s plan. It does not diagnose, treat, predict recovery, or provide clearance.",
            title: "Support, never clearance",
            style: .boundary
        )
    }
}

public struct PaceBackActionRow: View {
    private let title: String
    private let detail: String
    private let systemImage: String
    private let action: () -> Void

    public init(title: String, detail: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PaceBackDesign.accent)
                    .frame(width: 34, height: 34)
                    .background(PaceBackDesign.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: PaceBackDesign.minimumControlHeight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

extension View {
    func paceBackTextScale(_ scale: Double) -> some View {
        environment(\.dynamicTypeSize, PaceBackDesign.dynamicTypeSize(for: scale))
            .environment(\.controlSize, PaceBackDesign.controlSize(for: scale))
    }

    func paceBackControlTarget() -> some View {
        frame(minHeight: PaceBackDesign.minimumControlHeight)
            .contentShape(Rectangle())
    }
}
