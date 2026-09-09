import Foundation

/// URL helpers that deliberately mirror JavaScript's WHATWG `URL` semantics,
/// because the rule engine's behaviour was specified (and tested) against them.
///
/// Every function here is total: malformed input yields nil rather than
/// throwing. The TypeScript original wrapped every call site in try/catch
/// returning null/false, and rules must never crash the tracker just because a
/// user typed a bad pattern or an app reported a strange URL.
public enum URLish {
    /// Host with a leading `www.` stripped, or nil if the string isn't a URL
    /// with a host. Matches `new URL(u).hostname.replace(/^www\./, "")`.
    public static func extractDomain(_ string: String) -> String? {
        guard let components = URLComponents(string: string),
              components.scheme != nil,
              let host = components.host,
              !host.isEmpty
        else { return nil }

        if host.lowercased().hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    /// Path component. WHATWG reports "/" for a bare origin where
    /// `URLComponents` reports ""; normalise to match, since `path_contains`
    /// rules were written against the JS behaviour.
    public static func path(_ string: String) -> String? {
        guard let components = URLComponents(string: string),
              components.scheme != nil
        else { return nil }

        let path = components.percentEncodedPath
        if path.isEmpty && components.host != nil { return "/" }
        return path.removingPercentEncoding ?? path
    }

    /// Value of a query parameter, matching `searchParams.get(name)`.
    ///
    /// `URLComponents` leaves `+` literal, whereas WHATWG's URLSearchParams
    /// decodes it to a space. We match WHATWG.
    public static func queryValue(_ string: String, name: String) -> String? {
        guard let components = URLComponents(string: string),
              components.scheme != nil,
              let items = components.percentEncodedQueryItems
        else { return nil }

        guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
        let plusDecoded = raw.replacingOccurrences(of: "+", with: " ")
        return plusDecoded.removingPercentEncoding ?? plusDecoded
    }

    /// Host + path, elided to `maxLength`. Used for compact UI display.
    public static func truncate(_ string: String, maxLength: Int = 60) -> String {
        let display: String
        if let components = URLComponents(string: string),
           let host = components.host {
            display = host + components.path
        } else {
            display = string
        }
        guard display.count > maxLength else { return display }
        return String(display.prefix(maxLength)) + "\u{2026}"
    }
}
