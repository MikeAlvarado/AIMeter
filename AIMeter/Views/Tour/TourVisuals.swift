import SwiftUI
import UsageKit

/// The animation of what a tour step, or a new feature's note, is about,
/// drawn from the app's own pieces (its bars and colors, a notch island,
/// the pets) rather than pictures that would drift from the app. Each one
/// loops while it is on screen; under Reduce Motion it holds its last
/// frame. Decorative: the step's text says it all.
struct TourVisual: View {
    let feature: TourFeature
    var height: CGFloat = 170

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(backdrop)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch feature {
        case .welcome, .colors: BarsDemo()
        case .widgets: WidgetDemo()
        case .alerts: AlertDemo()
        case .connect: ConnectDemo()
        #if os(macOS)
        case .notchIsland: IslandDemo()
        case .sessions: PetsDemo()
        case .sessionNames: NamesDemo()
        case .openAtLogin: LoginDemo()
        #else
        case .notchIsland, .sessions, .sessionNames, .openAtLogin: ConnectDemo()
        #endif
        }
    }

    /// The Mac's top-edge scenes sit on a dark desk, like the island does;
    /// the rest on the app's own card colors.
    @ViewBuilder
    private var backdrop: some View {
        switch feature {
        case .notchIsland, .sessions, .sessionNames:
            LinearGradient(colors: [Color(hex: 0x3D2B22), Color(hex: 0x14110F)], startPoint: .top, endPoint: .bottom)
        default:
            Theme.accentWash
        }
    }
}

/// A phase that steps from 0 to `count - 1` and around every `interval`
/// seconds while the view is up, on a soft spring; held on the last one
/// under Reduce Motion.
struct LoopingPhase<Content: View>: View {
    let count: Int
    var interval: Double = 1.8
    @ViewBuilder let content: (Int) -> Content
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(reduceMotion ? count - 1 : phase)
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                        phase = (phase + 1) % count
                    }
                }
            }
    }
}

// MARK: - Bars

/// Three windows filling up, the session past 70 % turning yellow and
/// then past 85 % red: the app's rows and colors.
/// An account card as the Dashboard draws it (4.0): the window closest to
/// its limit large, the others one line each, the lead changing hands as
/// the figures climb, and the bars turning yellow and red past their lines.
private struct BarsDemo: View {
    private static let frames: [[Double]] = [[12, 20, 8], [42, 61, 18], [73, 63, 20], [91, 66, 22]]
    private static var titles: [String] {
        [String(localized: "5-hour session"), String(localized: "Weekly"), String(localized: "Credits")]
    }

    var body: some View {
        LoopingPhase(count: Self.frames.count) { phase in
            let values = Self.frames[phase]
            let lead = values.indices.max { values[$0] < values[$1] } ?? 0
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.titles[lead])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .contentTransition(.opacity)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: "\(Int(values[lead]))")
                            .font(Theme.figure(size: 40))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                        Text(verbatim: "%")
                            .font(Theme.figure(size: 18))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    UsageBarView(value: values[lead], tint: tint(values[lead]), height: 9, lit: true)
                        .padding(.top, 6)
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    ForEach(values.indices.filter { $0 != lead }, id: \.self) { index in
                        GridRow {
                            Text(Self.titles[index])
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            UsageBarView(value: values[index], tint: tint(values[index]), height: 4)
                            Text(verbatim: "\(Int(values[index]))%")
                                .font(Theme.figure(size: 13))
                                .foregroundStyle(Theme.ink)
                                .contentTransition(.numericText())
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
        }
    }

    private func tint(_ value: Double) -> Color {
        UsageWindow.tint(usedPct: value, severity: nil, usageColors: true)
    }
}

// MARK: - Widget

/// A medium widget's two columns, each with its big figure, rising.
private struct WidgetDemo: View {
    var body: some View {
        LoopingPhase(count: 2, interval: 2.2) { phase in
            HStack(spacing: 18) {
                column(String(localized: "5-hour session"), phase == 0 ? 18 : 42)
                column(String(localized: "Weekly"), phase == 0 ? 55 : 61)
            }
            .padding(18)
            .frame(width: 290, height: 128)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }

    private func column(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            Text(verbatim: "\(Int(value))%")
                .font(Theme.figure(size: 30))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            UsageBarView(value: value, tint: UsageWindow.tint(usedPct: value, severity: nil, usageColors: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Alert

/// A near-limit notification sliding in, in the app's own words, and
/// staying two beats before it goes.
private struct AlertDemo: View {
    var body: some View {
        LoopingPhase(count: 3, interval: 1.8) { phase in
            HStack(alignment: .top, spacing: 12) {
                ProviderMark(size: 36, cornerRadius: 9, prominent: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "\(UsageWindow.Kind.session.displayName) nearing its limit"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(String(localized: "You're at \(85)% of this window."))
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 300)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
            .offset(y: phase == 0 ? -150 : 0)
            .opacity(phase == 0 ? 0 : 1)
        }
    }
}

// MARK: - Connect

private struct ConnectDemo: View {
    var body: some View {
        LoopingPhase(count: 2, interval: 2) { phase in
            ZStack(alignment: .bottomTrailing) {
                ProviderMark(size: 74, cornerRadius: 18, prominent: true)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white, Theme.accent)
                    .background(Circle().fill(Theme.card).padding(2))
                    .offset(x: 8, y: 8)
                    .scaleEffect(phase == 1 ? 1 : 0.2)
                    .opacity(phase == 1 ? 1 : 0)
            }
        }
    }
}
