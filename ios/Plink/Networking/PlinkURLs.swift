import Foundation

/// Every URL the app shows to a user, in one place.
///
/// There are two origins, and the difference between them is the point of this
/// file:
///
///   • `webOrigin` — the host that actually serves the app's public pages. It is
///     the same host as the API (`PlinkConfig.baseURLString`), which is the one
///     origin the app is guaranteed to reach: it answers `/terms`, `/privacy`,
///     `/support`, `/r/<code>` and `/u/<username>` today. Everything that MUST
///     resolve goes here — App Review 3.1.2 rejects a subscription app whose
///     Terms and Privacy links are dead.
///
///   • `shareOrigin` — the brand host embedded in links a user sends to other
///     people. It is deliberately NOT the API host: an invite that lands in
///     someone else's chat is the product's face, and choosing what host appears
///     there is a product decision, not a networking detail.
///
/// The default share origin follows the currently deployed web origin so an
/// invite remains usable while the branded domain is being provisioned.
enum PlinkURLs {

    // MARK: - Origins

    /// Brand origin as shipped. A literal, so it is also the safe fallback.
    static let brandOrigin = "https://plink.app"

    /// Optional staging override. It is accepted only for HTTPS hosts that the
    /// app already trusts; an arbitrary UserDefaults value must never become an
    /// open redirect or a phishing origin in a share sheet.
    ///
    /// One thing it does not change: `DeepLinkRouter.domain`, which decides
    /// which hosts the app accepts *inbound*. Host matching is strict on
    /// purpose (ADR-0004), so a new share host has to be added there too before
    /// its links can open the app — which only matters once Associated Domains
    /// are provisioned, since universal links are off today.
    static let shareOriginOverrideKey = "plink.share_origin"

    /// Host that serves the public pages the app links to. Follows the API host
    /// by construction, so pointing the app at a staging backend points its
    /// legal and support links at the same place.
    static var webOrigin: String { PlinkConfig.baseURLString }

    /// Plink+ purchase page on the website (YooKassa). Purchases happen only
    /// there; the app reads the resulting entitlement from
    /// `/api/billing/entitlements`. `plan` preselects a tariff (`1m|3m|12m`).
    static func plusSite(plan: String? = nil) -> URL? {
        var components = URLComponents(string: webOrigin + "/plus")
        if let plan, !plan.isEmpty {
            components?.queryItems = [URLQueryItem(name: "plan", value: plan)]
        }
        return components?.url
    }

    /// Host used in links the user hands to other people.
    static var shareOrigin: String {
        if let override = UserDefaults.standard.string(forKey: shareOriginOverrideKey),
           let safeOverride = validatedShareOrigin(override) {
            return safeOverride
        }
        // The backend currently serves the working web join flow. Keep invites
        // usable until plink.app has a live web deployment and universal links.
        return webOrigin
    }

    private static func validatedShareOrigin(_ raw: String) -> String? {
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https",
              let host = components.host?.lowercased(),
              host == "plink.app" || host == "www.plink.app" || host == URL(string: webOrigin)?.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.queryItems == nil,
              components.fragment == nil else {
            return nil
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Brand home page. Force-unwrapped on purpose: `brandOrigin` is a literal
    /// constant, so a failure here is a compile-time typo that the test suite
    /// catches long before a user does.
    static let brandHome = URL(string: brandOrigin)!

    static var shareHome: URL { URL(string: shareOrigin) ?? brandHome }

    // MARK: - Legal and support
    //
    // Optional rather than force-unwrapped: a link that cannot be built is not
    // drawn, instead of crashing the view that draws it.

    static var terms: URL? { URL(string: webOrigin + "/terms") }

    static var privacy: URL? { URL(string: webOrigin + "/privacy") }

    /// Support page: the answers users write in about, plus the contact address.
    /// Also the Support URL for App Store Connect metadata.
    static var support: URL? { URL(string: webOrigin + "/support") }

    /// Where users are told to write.
    ///
    /// Known broken: `plink.app` publishes a null MX record (`0 .`, RFC 7505),
    /// meaning the domain declares that it accepts no mail, so this address
    /// bounces by design. The Settings row therefore opens the support page,
    /// which works, rather than a mail composer that does not. Fix the MX (or
    /// change the address here) before shipping mail as a support channel.
    static let supportEmail = "support@plink.app"

    static var supportMail: URL? {
        URL(string: "mailto:\(supportEmail)?subject=Plink%20Support")
    }

    // MARK: - Share links

    /// Web fallback for a room invite, for someone without the app installed.
    /// The deep link (`plink://r/<code>`) is what opens the app; this is what
    /// opens in a browser when the deep link does not.
    static func roomLink(code: String) -> URL? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            return nil
        }
        return URL(string: "\(shareOrigin)/r/\(trimmed)")
    }

    /// Public profile link. `handle` is a username or a user id — both are
    /// served by `/u/:username` on the backend.
    static func profileLink(_ handle: String) -> URL? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }
        return URL(string: "\(shareOrigin)/u/\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed)")
    }
}
