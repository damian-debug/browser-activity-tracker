import Foundation

/// Regex rules, made safe to run on every sample.
///
/// A rule's pattern is user text — written in the editor, or arriving in a
/// backup someone shared. Some patterns backtrack catastrophically: `(a+)+$`
/// against a long URL can run for minutes, and it would run inside the tracker
/// on every observation. So patterns are length-capped, compiled once, and
/// every match has a time budget: a pattern that runs out simply does not
/// match, and tracking carries on.
public enum SafeRegex {
    public static let maxPatternLength = 500
    static let maxInputLength = 4096
    static let timeBudget: TimeInterval = 0.05

    /// Why a pattern cannot be used, or nil if it can.
    public static func problem(with pattern: String) -> String? {
        if pattern.count > maxPatternLength {
            return "Too long — at most \(maxPatternLength) characters."
        }
        if (try? NSRegularExpression(pattern: pattern)) == nil {
            return "Not a valid regular expression."
        }
        return nil
    }

    /// Whether `pattern` matches `text`, within the time budget. An invalid,
    /// over-long or runaway pattern never matches, and never throws.
    public static func matches(_ pattern: String, in text: String) -> Bool {
        guard let regex = cache.regex(for: pattern) else { return false }
        let input = String(text.prefix(maxInputLength))
        let range = NSRange(input.startIndex..., in: input)
        let deadline = Date().addingTimeInterval(timeBudget)
        var found = false
        // .reportProgress calls back periodically during a long match, which is
        // the only point at which a runaway pattern can be stopped.
        regex.enumerateMatches(in: input, options: [.reportProgress], range: range) { match, _, stop in
            if match != nil {
                found = true
                stop.pointee = true
            } else if Date() > deadline {
                stop.pointee = true
            }
        }
        return found
    }

    private static let cache = Cache()

    /// Compiled patterns, shared across threads. NSRegularExpression is
    /// immutable and documented as thread-safe once created.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var compiled: [String: NSRegularExpression] = [:]
        private var invalid: Set<String> = []

        func regex(for pattern: String) -> NSRegularExpression? {
            lock.lock(); defer { lock.unlock() }
            if let hit = compiled[pattern] { return hit }
            if invalid.contains(pattern) { return nil }
            guard pattern.count <= SafeRegex.maxPatternLength,
                  let regex = try? NSRegularExpression(pattern: pattern)
            else {
                invalid.insert(pattern)
                return nil
            }
            if compiled.count >= 128 { compiled.removeAll() }   // bounded
            compiled[pattern] = regex
            return regex
        }
    }
}

public extension ProjectRule {
    /// A rule from somewhere else — a backup — whose regex cannot be used is
    /// kept, switched off and labelled, rather than silently dropped.
    func disablingUnusableRegex() -> ProjectRule {
        guard conditions.contains(where: { $0.type == .regex && SafeRegex.problem(with: $0.value) != nil })
        else { return self }
        var rule = self
        rule.enabled = false
        let note = " (switched off: its regular expression cannot be used)"
        if !rule.name.hasSuffix(note) { rule.name += note }
        return rule
    }
}
