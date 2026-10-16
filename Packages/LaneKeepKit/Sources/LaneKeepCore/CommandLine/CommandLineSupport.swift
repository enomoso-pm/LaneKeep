import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A mistake in the arguments of the `lanekeep` command.
public enum ArgumentError: Error, Equatable, Sendable {
    case missingValue(option: String)
    case notANumber(option: String, value: String)
    case unknownOptions([String])

    /// The message for the terminal.
    public var message: String {
        switch self {
        case .missingValue(let option):
            return "\(option) の値を指定してください。"
        case .notANumber(let option, let value):
            return "\(option) には数を指定してください（「\(value)」）。"
        case .unknownOptions(let options):
            return "不明なオプションです: \(options.joined(separator: " "))"
        }
    }
}

/// The arguments of the `lanekeep` command: positional values in order, flags and `--name value`
/// options anywhere.
public struct CommandLineArguments: Sendable {
    private var items: [String]

    public init(_ items: [String]) {
        self.items = items
    }

    /// The next positional argument.
    public mutating func next() -> String? {
        guard let index = items.firstIndex(where: { !$0.hasPrefix("--") }) else { return nil }
        return items.remove(at: index)
    }

    public mutating func flag(_ name: String) -> Bool {
        guard let index = items.firstIndex(of: name) else { return false }
        items.remove(at: index)
        return true
    }

    /// The value after `--name`, or `nil` when the option is not given.
    public mutating func value(for name: String) throws(ArgumentError) -> String? {
        guard let index = items.firstIndex(of: name) else { return nil }
        guard items.indices.contains(index + 1), !items[index + 1].hasPrefix("--") else {
            throw ArgumentError.missingValue(option: name)
        }
        let value = items[index + 1]
        items.removeSubrange(index...(index + 1))
        return value
    }

    public mutating func integer(for name: String) throws(ArgumentError) -> Int? {
        guard let text = try value(for: name) else { return nil }
        guard let number = Int(text) else {
            throw ArgumentError.notANumber(option: name, value: text)
        }
        return number
    }

    /// Fails when options are left that no command asked for (typically a typo).
    public func rejectUnknownOptions() throws(ArgumentError) {
        let unknown = items.filter { $0.hasPrefix("--") }
        if !unknown.isEmpty {
            throw ArgumentError.unknownOptions(unknown)
        }
    }
}

/// A position and size on a display, given as "x,y,w,h" fractions of the visible area.
public enum RelativeFrameArgument {
    public enum Problem: Error, Equatable, Sendable {
        /// Not four numbers.
        case format
        /// The frame does not fit in the visible area. `looksLikePercent` when the numbers were
        /// probably meant as percentages without the "%".
        case outOfRange(looksLikePercent: Bool)
    }

    /// Parses "0,0,0.5,1" or "0,0,50%,100%". The frame must lie within the visible area:
    /// 0 ≤ x, 0 ≤ y, width and height above 0, x + width ≤ 1 and y + height ≤ 1.
    public static func parse(_ text: String) -> Result<CGRect, Problem> {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4 else { return .failure(.format) }
        var values: [CGFloat] = []
        var hasPercent = false
        for part in parts {
            let isPercent = part.hasSuffix("%")
            hasPercent = hasPercent || isPercent
            guard let number = Double(isPercent ? String(part.dropLast()) : part), number.isFinite else {
                return .failure(.format)
            }
            values.append(CGFloat(isPercent ? number / 100 : number))
        }
        let frame = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        let slack: CGFloat = 0.000_001
        guard frame.minX >= 0, frame.minY >= 0, frame.width > 0, frame.height > 0,
              frame.minX + frame.width <= 1 + slack, frame.minY + frame.height <= 1 + slack
        else {
            return .failure(.outOfRange(looksLikePercent: !hasPercent && values.contains { $0 > 1 }))
        }
        return .success(frame)
    }
}

/// Finds the workspace a name or number on the command line refers to.
public enum WorkspaceLookup {
    /// Workspaces with exactly this name; when there are several, the most recently used first.
    public static func named(_ name: String, in workspaces: [Workspace]) -> [Workspace] {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return workspaces.enumerated()
            .filter { $0.element.name == name }
            .sorted { lhs, rhs in
                let lhsDate = lhs.element.lastUsedAt ?? .distantPast
                let rhsDate = rhs.element.lastUsedAt ?? .distantPast
                return lhsDate != rhsDate ? lhsDate > rhsDate : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// A workspace by name (the most recently used one, like automatic restores) or, when no
    /// workspace has that name, by its number in the list (1 is the first).
    public static func find(_ query: String, in workspaces: [Workspace]) -> Workspace? {
        if let byName = named(query, in: workspaces).first {
            return byName
        }
        guard let number = Int(query), workspaces.indices.contains(number - 1) else { return nil }
        return workspaces[number - 1]
    }
}
