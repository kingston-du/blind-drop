import Foundation
import Testing
@testable import BlindDrop

/// `docs/05` §5 lists four `blinddrop://` routes, plus the `E19-01` circle prefix. This suite
/// asserts all of it parses, and that everything else parses to `nil` — a link we do not
/// recognise must do nothing visible rather than fall back to the round.
@Suite struct DeepLinkTests {

    @Test func theFourRoutesFromDocs05Parse() {
        #expect(DeepLink(URL(string: "blinddrop://round/current")!) == .round(groupID: nil))
        #expect(DeepLink(URL(string: "blinddrop://round/current/results")!) == .results(groupID: nil))
        #expect(DeepLink(URL(string: "blinddrop://record")!) == .record(groupID: nil))
        #expect(DeepLink(URL(string: "blinddrop://join/K7MQ2X")!) == .join(code: "K7MQ2X"))
        #expect(DeepLink(URL(string: "blinddrop://invite/c0000000-0000-4000-8000-000000000001")!)
                == .invitation(id: "c0000000-0000-4000-8000-000000000001"))
    }

    /// docs/04 §3: invite codes are case-insensitive and whitespace-stripped. The fixture
    /// server's only valid code is `K7MQ2X`, so a lowercase link has to reach it.
    @Test func inviteCodesAreNormalised() {
        #expect(DeepLink(URL(string: "blinddrop://join/k7mq2x")!) == .join(code: "K7MQ2X"))
        #expect(DeepLink(URL(string: "blinddrop://join/%20k7mq2x%20")!) == .join(code: "K7MQ2X"))
    }

    /// The invite universal link (`docs/05` §5, E09-04). It arrives through
    /// `.onContinueUserActivity` rather than `.onOpenURL`, and it is the **same** destination as
    /// the custom scheme — parsed here so there is one grammar for what an invite code is.
    @Test func theInviteUniversalLinkParsesToTheSameJoin() {
        #expect(DeepLink(URL(string: "https://blinddrop.app/j/K7MQ2X")!) == .join(code: "K7MQ2X"))
        #expect(DeepLink(URL(string: "https://blinddrop.app/j/k7mq2x")!) == .join(code: "K7MQ2X"))
        #expect(DeepLink(URL(string: "blinddrop://join/K7MQ2X")!)
                == DeepLink(URL(string: "https://blinddrop.app/j/K7MQ2X")!))
        #expect(DeepLink(URL(string: "https://blinddrop.app/i/c0000000-0000-4000-8000-000000000001")!)
                == .invitation(id: "c0000000-0000-4000-8000-000000000001"))
    }

    /// `E19-01`: `blinddrop://circle/<id>/…` names which circle the rest of the link belongs
    /// to. The bare forms above are unchanged — `groupID: nil` still means "the active circle".
    @Test func acirclePrefixNamesWhichCircleTheLinkBelongsTo() {
        #expect(DeepLink(URL(string: "blinddrop://circle/g_1/round/current")!)
                == .round(groupID: "g_1"))
        #expect(DeepLink(URL(string: "blinddrop://circle/g_1/round/current/results")!)
                == .results(groupID: "g_1"))
        #expect(DeepLink(URL(string: "blinddrop://circle/g_1/record")!)
                == .record(groupID: "g_1"))
    }

    /// Joining is how a circle is acquired, not a thing that already has one — a circle prefix
    /// ahead of `join` is malformed rather than silently dropped.
    @Test func acirclePrefixOnAJoinLinkIsRejected() {
        #expect(DeepLink(URL(string: "blinddrop://circle/g_1/join/K7MQ2X")!) == nil)
    }

    /// `applinks:blinddrop.app` hands the app **every** URL on the domain, so everything that
    /// is not `/j/<CODE>` has to fall through to the browser. The entitlement cannot express
    /// that; this initialiser is where it is expressed on the client.
    @Test(arguments: [
        "https://blinddrop.app",                  // the root
        "https://blinddrop.app/j",                // no code
        "https://blinddrop.app/j/",               // empty code
        "https://blinddrop.app/j/A/B",            // a code is one path component
        "https://blinddrop.app/i/not-a-uuid",     // direct invitation ids are UUIDs
        "https://blinddrop.app/privacy",          // some other page on the domain
        "https://blinddrop.app/record",           // a scheme route's name, on the web host
        "https://evil.example/j/K7MQ2X",          // the right shape, the wrong domain
        "http://blinddrop.app/j/K7MQ2X",          // http, not https
    ])
    func onlyTheInvitePathOnTheInviteHostIsAUniversalLink(_ raw: String) {
        #expect(URL(string: raw).flatMap(DeepLink.init) == nil)
    }

    @Test(arguments: [
        "blinddrop://",                          // no route at all
        "blinddrop://round",                     // "current" is not optional
        "blinddrop://round/current/guesses",     // not a route in docs/05 §5
        "blinddrop://results",                   // results hang off the round, not the root
        "blinddrop://join",                      // no code
        "blinddrop://join/",                     // empty code
        "blinddrop://join/A/B",                  // a code is one path component
        "blinddrop://circle",                    // no id, no route
        "blinddrop://circle/",                   // empty id
        "blinddrop://circle/g_1",                // an id with no route after it
        "http://127.0.0.1:8787/rounds/current",  // the API, not a deep link
    ])
    func malformedOrForeignURLsParseToNil(_ raw: String) {
        // `flatMap`, not a force-unwrap: a string Foundation refuses to make a URL from is
        // just as much "does nothing" as one we parse and reject.
        #expect(URL(string: raw).flatMap(DeepLink.init) == nil)
    }

    /// An unrecognised link must not wipe a good pending one — `receive(nil)` is a no-op, and
    /// that is only true because `DeepLink.init?` is total.
    @MainActor
    @Test func anUnrecognisedLinkDoesNotClearAPendingOne() {
        let router = Router()
        router.receive(DeepLink(URL(string: "blinddrop://record")!))
        router.receive(DeepLink(URL(string: "blinddrop://nope")!))
        #expect(router.pending == .record(groupID: nil))
    }

    /// The web host is declared in three places that cannot see each other: this constant,
    /// `SpotifyAuth.redirectURI`/`callbackHost`, and the `applinks:`/`webcredentials:` strings
    /// in `BlindDrop.entitlements`. Two of the three are reachable from a test and are pinned
    /// here; the entitlement is not, so it stays a checklist item on any host change. Drift is
    /// silent in the worst way — invite links open Safari, and Spotify's callback never
    /// returns — so it is worth one assertion.
    @MainActor
    @Test func theWebHostAgreesAcrossTheConstantsThatDeclareIt() {
        #expect(SpotifyAuth.callbackHost == DeepLink.inviteHost)
        #expect(SpotifyAuth.redirectURI
                == "https://\(DeepLink.inviteHost)\(SpotifyAuth.callbackPath)")
        // Not the preview host it was parked on while the domain was unregistered.
        #expect(!DeepLink.inviteHost.contains("vercel"))
    }
}
