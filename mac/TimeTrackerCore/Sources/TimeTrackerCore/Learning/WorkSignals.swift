import Foundation

/// Signals that identify *which piece of work* is in progress, below the level
/// of "which app" or "which site".
///
/// None of these are features in their own right — a branch name is not a
/// project. They are evidence, fed to the same learning layer as everything
/// else, so picking "Payments" once while on `feature/payments` is what
/// creates the association. That keeps this to three small extractors instead
/// of a mapping system per tool.
public enum WorkSignals {
    // ── Ticket identifiers ───────────────────────────────────────────────

    /// Matches the near-universal `ABC-123` shape used by Jira, Linear and
    /// most issue trackers. Two-to-six uppercase letters, a hyphen, digits.
    private static let ticketPattern = try? NSRegularExpression(
        pattern: "\\b([A-Z][A-Z0-9]{1,5})-([0-9]{1,6})\\b"
    )

    /// GitHub-style issue and pull-request paths, which carry no project key.
    private static let githubPattern = try? NSRegularExpression(
        pattern: "/([^/]+)/([^/]+)/(?:issues|pull)/([0-9]+)"
    )

    /// A ticket key from a URL or window title, e.g. `ACME-123`.
    ///
    /// A ticket is usually one feature's worth of work, which makes it one of
    /// the few signals that generalises across every tool at once.
    public static func ticket(url: String?, title: String?) -> String? {
        for text in [url, title].compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)

            if let match = ticketPattern?.firstMatch(in: text, range: range),
               let keyRange = Range(match.range(at: 1), in: text),
               let numberRange = Range(match.range(at: 2), in: text) {
                return "\(text[keyRange])-\(text[numberRange])"
            }
        }

        // Fall back to GitHub, where the number alone is meaningless without
        // the repository it belongs to.
        if let url {
            let range = NSRange(url.startIndex..., in: url)
            if let match = githubPattern?.firstMatch(in: url, range: range),
               let repo = Range(match.range(at: 2), in: url),
               let number = Range(match.range(at: 3), in: url) {
                return "\(url[repo])#\(url[number])"
            }
        }
        return nil
    }

    // ── Git branch ───────────────────────────────────────────────────────

    /// Branches that say nothing about which feature is being worked on.
    private static let uninformativeBranches: Set<String> = [
        "main", "master", "develop", "development", "trunk", "staging", "production",
    ]

    /// The checked-out branch of the repository containing `path`.
    ///
    /// Reads `.git/HEAD` directly rather than shelling out to git: it is one
    /// small file, needs no subprocess, and works when git is not installed.
    /// A detached HEAD yields nil — a bare commit hash is not a feature name.
    public static func gitBranch(forFileAt path: String, fileManager: FileManager = .default) -> String? {
        guard let gitDirectory = repositoryRoot(for: path, fileManager: fileManager) else { return nil }

        let head = gitDirectory.appendingPathComponent("HEAD")
        guard let contents = try? String(contentsOf: head, encoding: .utf8) else { return nil }

        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("ref: refs/heads/") else { return nil }

        let branch = String(line.dropFirst("ref: refs/heads/".count))
        guard !branch.isEmpty, !uninformativeBranches.contains(branch.lowercased()) else { return nil }
        return branch
    }

    /// The folder a document path puts you in.
    ///
    /// Usually the path is a file and the folder is its parent. But a terminal
    /// reports its working directory, which is already the folder — marked by
    /// a trailing slash when captured. Going up from that missed the repository
    /// when a CLI (Claude Code, Codex) was started at its root, the usual case,
    /// and suggested rules for the folder above the project.
    public static func folder(ofDocument path: String) -> String {
        if path.hasSuffix("/") {
            let trimmed = String(path.dropLast())
            return trimmed.isEmpty ? "/" : trimmed
        }
        return URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    /// Walk up from a file looking for `.git`, bounded so a path outside any
    /// repository cannot walk to the filesystem root on every sample.
    static func repositoryRoot(
        for path: String, fileManager: FileManager = .default, maxDepth: Int = 12
    ) -> URL? {
        var directory = URL(fileURLWithPath: folder(ofDocument: path), isDirectory: true)

        for _ in 0..<maxDepth {
            guard directory.pathComponents.count > 1 else { return nil }
            let candidate = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
                // A worktree or submodule has .git as a file pointing elsewhere.
                if isDirectory.boolValue { return candidate }
                if let contents = try? String(contentsOf: candidate, encoding: .utf8),
                   contents.hasPrefix("gitdir: ") {
                    let target = contents
                        .dropFirst("gitdir: ".count)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return URL(fileURLWithPath: target, relativeTo: directory).standardized
                }
                return nil
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }
}
