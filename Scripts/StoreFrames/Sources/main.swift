import SwiftUI
import AppKit
import UsageKit

@MainActor
func render<V: View>(_ view: V, size: CGSize, dark: Bool, name: String) {
    NSAppearance.current = NSAppearance(named: dark ? .darkAqua : .aqua)
    let wrapped = ZStack {
        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card)
        view.padding(16)
    }
    .frame(width: size.width, height: size.height)
    .environment(\.colorScheme, dark ? .dark : .light)
    .background(dark ? Color.black : Color(white: 0.92))
    .padding(12)
    let r = ImageRenderer(content: wrapped)
    r.scale = 3
    guard let cg = r.cgImage else { print("no image", name); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    let data = rep.representation(using: .png, properties: [:])!
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png")
    try! data.write(to: url)
    print("wrote", url.path)
}

if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "notch" {
    Task { @MainActor in
        renderNotch(islandDir: CommandLine.arguments[1], outDir: CommandLine.arguments[1] + "/notch-frames")
        exit(0)
    }
    RunLoop.main.run()
}

if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "frames" {
    Task { @MainActor in
        renderFrames(rawDir: CommandLine.arguments[1] + "/raw", outDir: CommandLine.arguments[1] + "/frames", specs: phoneSpecs + padSpecs)
        exit(0)
    }
    RunLoop.main.run()
}

let now = Date()
func snap(_ windows: [UsageWindow], plan: String? = "max", spend: SpendStatus? = nil) -> UsageSnapshot {
    UsageSnapshot(providerID: "claude", planName: plan, fetchedAt: now, windows: windows, spend: spend)
}
let two = snap([
    UsageWindow(kind: .session, usedPct: 58, resetsAt: now.addingTimeInterval(3 * 3600 + 12 * 60)),
    UsageWindow(kind: .weekly, usedPct: 89, resetsAt: now.addingTimeInterval(4 * 86400 + 5 * 3600)),
], plan: "pro")
let three = snap([
    UsageWindow(kind: .session, usedPct: 42, resetsAt: now.addingTimeInterval(3 * 3600)),
    UsageWindow(kind: .weekly, usedPct: 15, resetsAt: now.addingTimeInterval(3 * 86400)),
    UsageWindow(kind: .modelSpecific("Fable"), usedPct: 9, resetsAt: now.addingTimeInterval(3 * 86400)),
])
let missing = snap([
    UsageWindow(kind: .session, usedPct: 0, resetsAt: nil),
], plan: "pro")
var prefsRemaining = Preferences(); prefsRemaining.displayMode = .remaining
var prefsUsed = Preferences(); prefsUsed.displayMode = .used
var prefsAbs = Preferences(); prefsAbs.resetStyle = .absolute; prefsAbs.displayMode = .remaining

let medium = CGSize(width: 329, height: 155)
let mediumMax = CGSize(width: 364, height: 170)
let small = CGSize(width: 158, height: 158)
if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "marketing" {
    Task { @MainActor in
        // The widget cluster for the landscape assets: real widget views on a
        // transparent background, so it floats over the backdrop with no box.
        NSAppearance.current = NSAppearance(named: .darkAqua)
        let personal = ConnectedAccount(accountID: "demo", providerID: "claude", displayName: "Personal", credentialStrategy: .managed)
        let work = ConnectedAccount(accountID: "demo-2", providerID: "claude", displayName: "Work", credentialStrategy: .managed, icon: .symbol("briefcase.fill"))
        _ = personal
        let personalSnap = snap([
            UsageWindow(kind: .session, usedPct: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 58 * 60)),
            UsageWindow(kind: .weekly, usedPct: 61, resetsAt: now.addingTimeInterval(3 * 86400 + 3 * 3600)),
            UsageWindow(kind: .modelSpecific("Top model"), usedPct: 18, resetsAt: now.addingTimeInterval(3 * 86400 + 3 * 3600)),
        ], plan: "Demo")
        let workSnap = snap([
            UsageWindow(kind: .session, usedPct: 73, resetsAt: now.addingTimeInterval(1 * 3600 + 11 * 60)),
            UsageWindow(kind: .weekly, usedPct: 28, resetsAt: now.addingTimeInterval(5 * 86400 + 8 * 3600)),
        ], plan: "Demo", spend: SpendStatus(enabled: true, percent: 31, severity: .normal, usedAmount: 7.75, limitAmount: 25, currency: "USD"))
        var p = Preferences(); p.displayMode = .used
        func tile<V: View>(_ v: V, w: CGFloat, h: CGFloat) -> some View {
            ZStack { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card); v.padding(16) }
                .frame(width: w, height: h)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 16)
        }
        let cluster = VStack(spacing: 18) {
            HStack(spacing: 18) {
                tile(SingleUsageWidgetView(entry: SingleUsageEntry(date: now, snapshot: personalSnap, accountID: "demo", kind: .session, accountName: "Personal", prefs: p)), w: 158, h: 158)
                tile(SystemUsageView(snapshot: workSnap, prefs: p, date: now, accountID: "demo-2", accountName: "Work", accountIcon: work.icon), w: 158, h: 158)
            }
            tile(MediumUsageView(snapshot: personalSnap, prefs: p, date: now, accountID: "demo", accountName: "Personal"), w: 334, h: 158)
        }
        .padding(40)
        .environment(\.colorScheme, .dark)
        let cr = ImageRenderer(content: cluster); cr.scale = 3
        let clusterImage = cr.cgImage.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        renderMarketing(rawDir: CommandLine.arguments[1] + "/raw", outDir: CommandLine.arguments[1] + "/marketing", widgets: clusterImage)
        exit(0)
    }
    RunLoop.main.run()
}

Task { @MainActor in
    render(MediumUsageView(snapshot: two, prefs: prefsRemaining, date: now, accountID: "a", accountName: "Personal"), size: medium, dark: true, name: "01-two-dark")
    render(MediumUsageView(snapshot: two, prefs: prefsRemaining, date: now, accountID: "a", accountName: "Personal"), size: medium, dark: false, name: "02-two-light")
    render(MediumUsageView(snapshot: three, prefs: prefsUsed, date: now, accountID: "a", accountName: "Work"), size: medium, dark: true, name: "03-three-used-dark")
    render(MediumUsageView(snapshot: three, prefs: prefsAbs, date: now, accountID: "a", accountName: "Work"), size: mediumMax, dark: false, name: "04-three-abs-light-max")
    render(MediumUsageView(snapshot: missing, prefs: prefsRemaining, date: now, accountID: "a", accountName: "Personal"), size: medium, dark: true, name: "05-missing-dark")
    render(SystemUsageView(snapshot: three, prefs: prefsRemaining, date: now, accountID: "a", accountName: "Personal"), size: small, dark: true, name: "06-small-dark")
    // Tweet composite: two medium widgets on a dark backdrop.
    NSAppearance.current = NSAppearance(named: .darkAqua)
    let tweet = VStack(spacing: 18) {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card)
            MediumUsageView(snapshot: two, prefs: prefsRemaining, date: now, accountID: "a", accountName: "Personal").padding(16)
        }.frame(width: 329, height: 155)
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card)
            MediumUsageView(snapshot: three, prefs: prefsUsed, date: now, accountID: "b", accountName: "Work").padding(16)
        }.frame(width: 329, height: 155)
    }
    .padding(36)
    .background(Theme.background)
    .environment(\.colorScheme, .dark)
    let tr = ImageRenderer(content: tweet); tr.scale = 3
    if let cg = tr.cgImage {
        let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("tweet-widgets.png"))
        print("wrote tweet-widgets.png")
    }
    // Icon tiles: default, Claude, Claude Code, two symbols — header, picker and sheet sizes.
    for dark in [false, true] {
        NSAppearance.current = NSAppearance(named: dark ? .darkAqua : .aqua)
        let icons: [AccountIcon?] = [nil, .mark(.claude), .mark(.claudeCode), .symbol("bolt.fill"), .symbol("terminal")]
        let row = VStack(spacing: 20) {
            HStack(spacing: 14) { ForEach(0..<icons.count, id: \.self) { i in ProviderMark(size: 22, cornerRadius: 6, icon: icons[i]) } }
            HStack(spacing: 14) { ForEach(0..<icons.count, id: \.self) { i in ProviderMark(size: 48, cornerRadius: 13, icon: icons[i]) } }
            HStack(spacing: 14) { ForEach(0..<icons.count, id: \.self) { i in ProviderMark(size: 72, cornerRadius: 20, icon: icons[i], prominent: true) } }
        }
        .padding(28).background(Theme.card).environment(\.colorScheme, dark ? .dark : .light)
        let ir = ImageRenderer(content: row); ir.scale = 3
        if let cg = ir.cgImage {
            let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
            try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("icons-\(dark ? "dark" : "light")-\(Int(Date().timeIntervalSince1970)).png"))
            print("wrote icons", dark)
        }
    }
    // Home-screen composite for the store frame: the three widget kinds on a wallpaper.
    do {
        NSAppearance.current = NSAppearance(named: .darkAqua)
        let personal = ConnectedAccount(accountID: "demo", providerID: "claude", displayName: "Personal", credentialStrategy: .managed)
        let work = ConnectedAccount(accountID: "demo-2", providerID: "claude", displayName: "Work", credentialStrategy: .managed, icon: .symbol("briefcase.fill"))
        let personalSnap = snap([
            UsageWindow(kind: .session, usedPct: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 58 * 60)),
            UsageWindow(kind: .weekly, usedPct: 61, resetsAt: now.addingTimeInterval(3 * 86400 + 3 * 3600)),
            UsageWindow(kind: .modelSpecific("Top model"), usedPct: 18, resetsAt: now.addingTimeInterval(3 * 86400 + 3 * 3600)),
        ], plan: "Demo")
        let workSnap = snap([
            UsageWindow(kind: .session, usedPct: 73, resetsAt: now.addingTimeInterval(1 * 3600 + 11 * 60)),
            UsageWindow(kind: .weekly, usedPct: 28, resetsAt: now.addingTimeInterval(5 * 86400 + 8 * 3600)),
        ], plan: "Demo", spend: SpendStatus(enabled: true, percent: 31, severity: .normal, usedAmount: 7.75, limitAmount: 25, currency: "USD"))
        var p = Preferences(); p.displayMode = .used
        func tile<V: View>(_ v: V, w: CGFloat, h: CGFloat) -> some View {
            ZStack { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card); v.padding(16) }.frame(width: w, height: h)
        }
        let small = tile(SingleUsageWidgetView(entry: SingleUsageEntry(date: now, snapshot: personalSnap, accountID: "demo", kind: .session, accountName: "Personal", prefs: p)), w: 158, h: 158)
        let small2 = tile(SystemUsageView(snapshot: workSnap, prefs: p, date: now, accountID: "demo-2", accountName: "Work", accountIcon: work.icon), w: 158, h: 158)
        let medium = tile(MediumUsageView(snapshot: personalSnap, prefs: p, date: now, accountID: "demo", accountName: "Personal"), w: 338, h: 158)
        let large = tile(AllAccountsWidgetView(entry: AllAccountsEntry(date: now, rows: [.init(account: personal, snapshot: personalSnap), .init(account: work, snapshot: workSnap)], prefs: p)), w: 338, h: 354)
        let home = ZStack {
            LinearGradient(colors: [Color(hex: 0x2B2622), Color(hex: 0x5A3A2E), Color(hex: 0x1C1A18)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 22) {
                HStack(spacing: 22) { small; small2 }
                medium
                large
            }
        }
        .frame(width: 402, height: 874)
        .environment(\.colorScheme, .dark)
        let hr = ImageRenderer(content: home); hr.scale = 3
        if let cg = hr.cgImage {
            let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
            try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("home-widgets.png"))
            print("wrote home-widgets.png")
        }
    }
    exit(0)
}
RunLoop.main.run()
