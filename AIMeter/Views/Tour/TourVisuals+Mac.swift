#if os(macOS)
import SwiftUI
import UsageKit

// The Mac's tour scenes: the top of a MacBook's screen, its notch and
// what the island draws there (see `TourVisual`).

/// The top of a MacBook's screen: the menu bar (menu titles on the left,
/// icons on the right) with an app's window under it, and the island's
/// slab fused to the top edge over them.
private struct NotchStage<Content: View>: View {
    var menus = 4
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.05))
                .frame(width: 250, height: 120)
                .offset(y: 54)
            MenuBarStrip(menus: menus)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A menu bar's strip: the open app's menu titles, and the status icons.
private struct MenuBarStrip: View {
    let menus: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<menus, id: \.self) { index in
                Capsule().fill(.white.opacity(0.5)).frame(width: index == 0 ? 14 : 26, height: 6)
            }
            Spacer(minLength: 0)
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(.white.opacity(0.5)).frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(.white.opacity(0.06))
    }
}

/// The island's black, square at the top and round below.
private struct Slab<Content: View>: View {
    var radius: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))
    }
}

/// Collapsed, peeking with the figures, open with every account.
struct IslandDemo: View {
    var body: some View {
        LoopingPhase(count: 3, interval: 1.9) { phase in
            NotchStage {
                Slab(radius: phase == 2 ? 20 : 10) {
                    VStack(spacing: 0) {
                        HStack {
                            if phase > 0 {
                                figure("5h", "42%")
                                Spacer()
                                figure("7d", "61%")
                            }
                        }
                        .frame(width: phase == 0 ? 120 : 280, height: 30)
                        .padding(.horizontal, phase == 0 ? 0 : 12)
                        if phase == 2 {
                            VStack(spacing: 10) {
                                account(42, 61)
                                account(73, 28)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(width: 304)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                        }
                    }
                }
            }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: label).foregroundStyle(.white.opacity(0.82))
            Text(verbatim: value).foregroundStyle(Theme.accent)
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .transition(.opacity)
    }

    private func account(_ session: Double, _ week: Double) -> some View {
        HStack(spacing: 12) {
            bar(session)
            bar(week)
        }
    }

    private func bar(_ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(Int(value))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(UsageWindow.tint(usedPct: value, severity: nil, usageColors: true))
            Capsule().fill(.white.opacity(0.14)).frame(height: 2)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(UsageWindow.tint(usedPct: value, severity: nil, usageColors: true))
                            .frame(width: proxy.size.width * value / 100)
                    }
                }
        }
    }
}

/// Pets beside the notch, one at work, one waiting with its "!", and the
/// count; then the peek: the session's name and what it is doing.
struct PetsDemo: View {
    private let working = SessionPet(creature: .frog, palette: .pink, accessory: .none)
    private let waiting = SessionPet(creature: .fox, palette: .orange, accessory: .sunglasses)

    var body: some View {
        LoopingPhase(count: 2, interval: 2.4) { phase in
            NotchStage {
                Slab {
                    HStack(spacing: 8) {
                        PetGroup(slots: [.init(id: "a", pet: working, pose: .working)], pixel: 2)
                        if phase == 1 {
                            Text(verbatim: "my-app")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))
                                .transition(.opacity)
                        }
                        Spacer(minLength: phase == 1 ? 24 : 110)
                        if phase == 0 {
                            PetGroup(slots: [.init(id: "b", pet: waiting, pose: .waiting)], pixel: 2)
                                .transition(.opacity)
                        } else {
                            Text(String(localized: "Working"))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                                .transition(.opacity)
                        }
                        SessionCount(count: 2)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                }
            }
        }
    }
}

/// A long menu bar meets the island: with room, the session's name shows;
/// once the menus would reach it, the island drops the name, and it never
/// reaches the icons on the right.
struct NamesDemo: View {
    private let pet = SessionPet(creature: .cat, palette: .blue, accessory: .headphones)

    var body: some View {
        LoopingPhase(count: 2, interval: 2.2) { phase in
            NotchStage(menus: phase == 0 ? 3 : 7) {
                Slab {
                    HStack(spacing: 8) {
                        PetGroup(slots: [.init(id: "c", pet: pet, pose: .working)], pixel: 2)
                        if phase == 0 {
                            Text(verbatim: "my-app")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))
                                .transition(.opacity)
                        }
                        Spacer(minLength: 0)
                        SessionCount(count: 1)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: phase == 0 ? 250 : 170, height: 34)
                }
            }
        }
    }
}

/// The login item's switch turning on.
struct LoginDemo: View {
    var body: some View {
        LoopingPhase(count: 2, interval: 2) { phase in
            HStack(spacing: 14) {
                Image(systemName: "power")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Open at Login")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 12)
                Capsule()
                    .fill(phase == 1 ? Theme.accent : Theme.track)
                    .frame(width: 42, height: 24)
                    .overlay(alignment: phase == 1 ? .trailing : .leading) {
                        Circle().fill(.white).padding(2).shadow(radius: 1)
                    }
            }
            .padding(16)
            .frame(width: 300)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
#endif
