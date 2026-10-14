import Foundation

/// A release's dotted version ("2.1.0", or a tag such as "v2.1"), compared
/// number by number with missing parts counting as zero: "2.10.0" is newer
/// than "2.9.0", and "2.1" is the same release as "2.1.0".
nonisolated struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let components: [Int]

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let numbers = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        components = numbers.compactMap { $0 }
    }

    /// The running app's `CFBundleShortVersionString`.
    static var current: AppVersion? {
        version(of: .main)
    }

    static func version(of bundle: Bundle) -> AppVersion? {
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = lhs.components.indices.contains(index) ? lhs.components[index] : 0
            let right = rhs.components.indices.contains(index) ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }
}
