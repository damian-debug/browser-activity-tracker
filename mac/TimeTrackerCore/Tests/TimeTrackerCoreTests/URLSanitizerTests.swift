import Testing
@testable import TimeTrackerCore

@Suite("Credentials are removed from stored URLs")
struct URLSanitizerTests {
    @Test("an OAuth callback loses its code and state")
    func oauthCallback() {
        #expect(URLSanitizer.sanitized("https://linear.app/oauth/callback?code=abc123&state=xyz")
                == "https://linear.app/oauth/callback")
    }

    @Test("a sign-in request loses its state but keeps what it is")
    func oauthRequest() {
        #expect(URLSanitizer.sanitized("https://mcp.clickup.com/authorize?client_id=app&redirect_uri=https%3A%2F%2Fx&state=s3cr3t&response_type=code")
                == "https://mcp.clickup.com/authorize?client_id=app&redirect_uri=https%3A%2F%2Fx&response_type=code")
    }

    @Test("Google's re-auth tokens go; only on Google's sign-in host")
    func googleReauth() {
        #expect(URLSanitizer.sanitized("https://accounts.google.com/signin/oauth/id?authuser=0&part=AJi8h&rapt=AEjH&flowName=GeneralOAuthFlow")
                == "https://accounts.google.com/signin/oauth/id?authuser=0&flowName=GeneralOAuthFlow")
        #expect(URLSanitizer.sanitized("https://docs.example.com/book?part=2") == "https://docs.example.com/book?part=2")
    }

    @Test("a SharePoint guest link loses the guest's email and share nonce")
    func sharepoint() {
        #expect(URLSanitizer.sanitized("https://jvw.sharepoint.com/sites/X/_layouts/15/guestaccess.aspx?email=a%40b.com&e=Xyz1&share=IgDj")
                == "https://jvw.sharepoint.com/sites/X/_layouts/15/guestaccess.aspx?share=IgDj")
    }

    @Test("tokens and signatures go wherever they appear, whatever their case")
    func alwaysSecret() {
        #expect(URLSanitizer.sanitized("https://x.com/a?Access_Token=t&view=1") == "https://x.com/a?view=1")
        #expect(URLSanitizer.sanitized("https://bucket.s3.amazonaws.com/f.pdf?X-Amz-Signature=abc&X-Amz-Credential=k&X-Amz-Expires=60")
                == "https://bucket.s3.amazonaws.com/f.pdf?X-Amz-Expires=60")
        #expect(URLSanitizer.sanitized("https://x.com/a?csrf_token=1&authenticity_token=2&q=hi") == "https://x.com/a?q=hi")
    }

    @Test("an OAuth token in the fragment is removed; an ordinary anchor is kept")
    func fragments() {
        #expect(URLSanitizer.sanitized("https://app.example.com/cb#access_token=t&expires_in=3600")
                == "https://app.example.com/cb#expires_in=3600")
        #expect(URLSanitizer.sanitized("https://docs.google.com/document/d/1/edit#heading=h.abc")
                == "https://docs.google.com/document/d/1/edit#heading=h.abc")
        #expect(URLSanitizer.sanitized("https://site.com/page#pricing") == "https://site.com/page#pricing")
    }

    @Test("what identifies a page is never touched",
          arguments: [
            "https://bubble.io/page?id=meltx&tab=Data&name=gp-portal&version=33j34",
            "https://www.figma.com/design/QA6/MeltX?node-id=4171-1023&t=Uky9",
            "https://framer.com/projects/A--FC91PjIN9PCSOTMJzDXU-5ODEx?node=R198OJlPy",
            "https://docs.google.com/spreadsheets/d/1lk/edit?gid=1041490469",
            "https://github.com/acme/site/pulls?state=closed",
            "https://shop.example.com/cart?code=SPRING",
            "https://www.google.com/search?q=acme",
            "https://app.hubspot.com/contacts/5/record/0-2/58?eschref=%2Fcontacts",
            "https://example.com/plain",
          ])
    func identityKept(url: String) {
        #expect(URLSanitizer.sanitized(url) == url)
    }

    @Test("an invite or verification code goes, even outside a sign-in flow")
    func invites() {
        #expect(URLSanitizer.sanitized("https://cursor.com/accept-team-invite?code=Zq9&utm_source=email")
                == "https://cursor.com/accept-team-invite?utm_source=email")
        #expect(URLSanitizer.sanitized("https://app.example.com/verify-email?code=123456") == "https://app.example.com/verify-email")
        #expect(URLSanitizer.sanitized("https://app.example.com/password/reset?code=abc") == "https://app.example.com/password/reset")
    }

    @Test("a path merely containing a sign-in word inside another word does not count")
    func wholeWordsOnly() {
        #expect(URLSanitizer.sanitized("https://blog.example.com/authors?state=active") == "https://blog.example.com/authors?state=active")
    }

    @Test("a secret inside an address wrapped in another parameter goes too")
    func nested() {
        let cleaned = URLSanitizer.sanitized(
            "https://cursor.com/api/auth/login?redirect_uri=%2Faccept-team-invite%3Fcode%3DZq9%26utm_source%3Demail")
        #expect(!cleaned.contains("Zq9"))
        #expect(cleaned.removingPercentEncoding == "https://cursor.com/api/auth/login?redirect_uri=/accept-team-invite?utm_source=email")
    }

    @Test("a wrapped address with nothing to remove keeps its exact encoding")
    func nestedUntouched() {
        let url = "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fdocs.google.com%2Fdocument%2Fd%2F1%2Fedit%3Ftab%3Dt.0"
        #expect(URLSanitizer.sanitized(url) == url)
    }

    @Test("a URL left with no parameters loses its question mark")
    func emptied() {
        #expect(URLSanitizer.sanitized("https://x.com/cb?token=abc") == "https://x.com/cb")
    }
}
