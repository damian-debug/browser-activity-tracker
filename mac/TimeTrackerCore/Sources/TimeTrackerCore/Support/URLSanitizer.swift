import Foundation

/// Removes credentials and personal data from a URL before it is stored.
///
/// Addresses carry secrets more often than you would think: OAuth sign-in
/// codes, Google's re-authentication tokens, signed download links, a guest's
/// email on a SharePoint share. Stored as-is they sat in the database and went
/// out in every CSV and backup a person chose to share.
///
/// Deliberately a list of known credential parameters, never "strip the query":
/// the query is where Bubble keeps its app and page, Figma and Framer their
/// screen, Sheets its tab — the things rules and parsers depend on. And
/// ambiguous names (`code`, `state`) are only treated as secrets inside a
/// sign-in flow, since `?state=closed` on GitHub or `?code=SPRING` in a shop
/// are ordinary.
///
/// What it cannot catch: a secret that IS the address (a SharePoint "anyone
/// with the link" path), and parameter names it has never seen.
public enum URLSanitizer {
    /// Secret wherever they appear. Matched case-insensitively.
    static let alwaysSensitive: Set<String> = [
        "access_token", "id_token", "refresh_token", "token", "client_secret",
        "oauth_token", "oauth_verifier", "assertion", "jwt", "otp",
        "password", "passwd", "pwd", "api_key", "apikey",
        "sig", "signature", "x-amz-signature", "x-amz-credential", "x-amz-security-token",
        "x-goog-signature", "x-goog-credential",
        "samlrequest", "samlresponse", "magic_link", "login_token",
        "email", "login_hint",
    ]

    /// Any parameter whose name contains one of these is treated as secret —
    /// `csrf_token`, `authenticity_token`, `db_password`, `x-signature`.
    static let sensitiveNameParts = ["token", "secret", "password", "signature"]

    /// Secret only inside a sign-in flow.
    static let signInFlowOnly: Set<String> = ["code", "state", "nonce", "code_verifier", "session_state"]

    /// Marks a query as an OAuth / OpenID sign-in or its callback.
    static let signInFlowMarkers: Set<String> = ["client_id", "redirect_uri", "response_type", "code_challenge"]

    /// Words in a path that make its `code` or `state` a secret too: an invite
    /// (`/accept-team-invite?code=` lets anyone holding it join the team), a
    /// verification or reset link, a sign-in callback. Whole words only, so
    /// `/authors` is not `auth`.
    static let signInPathWords: Set<String> = [
        "oauth", "oauth2", "callback", "signin", "login", "auth", "authorize", "sso",
        "invite", "invitation", "accept", "verify", "verification", "confirm", "reset", "magic", "activate",
    ]

    /// Secret only on one site, because elsewhere the name is too generic.
    static let perHost: [(hostSuffix: String, names: Set<String>)] = [
        ("accounts.google.com", ["rapt", "part"]),   // re-auth proof
        ("sharepoint.com", ["e"]),                   // share-link nonce
    ]

    public static func sanitized(_ url: String) -> String {
        sanitized(url, depth: 0)
    }

    /// `depth` bounds the recursion into addresses nested in parameter values.
    private static func sanitized(_ url: String, depth: Int) -> String {
        guard url.contains("?") || url.contains("#") else { return url }

        var base = url
        var fragment: String?
        if let hash = base.firstIndex(of: "#") {
            fragment = String(base[base.index(after: hash)...])
            base = String(base[..<hash])
        }
        var query: String?
        if let mark = base.firstIndex(of: "?") {
            query = String(base[base.index(after: mark)...])
            base = String(base[..<mark])
        }

        let host = URLComponents(string: url)?.host?.lowercased() ?? ""
        let hostOnly = perHost.filter { host == $0.hostSuffix || host.hasSuffix("." + $0.hostSuffix) }
            .reduce(into: Set<String>()) { $0.formUnion($1.names) }

        let pathWords = Set((URLComponents(string: base)?.path ?? "").lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let signInPath = !pathWords.isDisjoint(with: signInPathWords)

        var result = base
        if let query {
            let kept = strip(query, hostOnly: hostOnly, signInPath: signInPath, depth: depth)
            if !kept.isEmpty { result += "?" + kept }
        }
        if let fragment, !fragment.isEmpty {
            // A fragment is usually an anchor (#pricing), but OAuth's implicit
            // flow returns tokens there. Parameter-shaped fragments are
            // filtered the same way; plain anchors are kept.
            if fragment.contains("=") {
                let kept = strip(fragment, hostOnly: hostOnly, signInPath: signInPath, depth: depth)
                if !kept.isEmpty { result += "#" + kept }
            } else {
                result += "#" + fragment
            }
        }
        return result
    }

    /// Keeps the query's own order and encoding; only whole items are removed.
    private static func strip(_ query: String, hostOnly: Set<String>, signInPath: Bool, depth: Int) -> String {
        let items = query.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
        let names = items.map(name(of:))
        let inSignInFlow = signInPath
            || !signInFlowMarkers.isDisjoint(with: names)
            || (names.contains("code") && names.contains("state"))

        return zip(items, names).filter { _, name in
            !(alwaysSensitive.contains(name)
              || sensitiveNameParts.contains(where: name.contains)
              || hostOnly.contains(name)
              || (inSignInFlow && signInFlowOnly.contains(name)))
        }
        .map { item, _ in depth < 2 ? cleaningNestedAddress(in: item, depth: depth) : item }
        .joined(separator: "&")
    }

    /// Sign-in flows wrap the page you were heading to — `redirect_uri`,
    /// `continue`, `next` — and that address can carry its own secret, such as
    /// an invite code. A value that decodes to an address is cleaned the same
    /// way, and re-encoded only if something was actually removed from it.
    private static func cleaningNestedAddress(in item: String, depth: Int) -> String {
        guard let equals = item.firstIndex(of: "=") else { return item }
        let raw = String(item[item.index(after: equals)...])
        guard let value = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
              value.hasPrefix("/") || value.hasPrefix("http://") || value.hasPrefix("https://"),
              value.contains("?") || value.contains("#")
        else { return item }
        let clean = sanitized(value, depth: depth + 1)
        guard clean != value,
              let encoded = clean.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return item }
        return String(item[...equals]) + encoded
    }

    private static let queryValueAllowed = CharacterSet.urlQueryAllowed
        .subtracting(CharacterSet(charactersIn: "&=?#+"))

    private static func name(of item: String) -> String {
        let raw = item.split(separator: "=", maxSplits: 1).first.map(String.init) ?? item
        return (raw.removingPercentEncoding ?? raw).lowercased()
    }
}
