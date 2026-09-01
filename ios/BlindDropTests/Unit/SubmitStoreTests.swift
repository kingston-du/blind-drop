import Foundation
import Testing
@testable import BlindDrop

/// The search sheet's machine: the debounce, the paste path, and the seal (`docs/08` §3).
///
/// `.serialized` because these count requests against a process-wide stub.
@MainActor
@Suite(.serialized) struct SubmitStoreTests {

    private func makeStore(_ responses: [RoundStub.Response] = []) -> (SubmitStore, StubSession) {
        let (env, stub) = RoundFixture.environment(responses: responses)
        return (SubmitStore(api: env.api, circles: env.circles), stub)
    }

    // MARK: - Searching (`docs/08` §3.1)

    /// **Minimum two characters.** One character is a keystroke, not a query, and sending it would
    /// spend a request and miss the server's cache on every prefix (`docs/06` §4).
    @Test func asingleCharacterDoesNotSearch() async throws {
        let (store, stub) = makeStore([try RoundFixture.envelope("tracks_search")])

        store.query = "r"
        try await Task.sleep(for: .milliseconds(400))

        #expect(stub.count(matching: "/tracks/search") == 0)
        #expect(store.results.value == nil, "and the sheet stays blank")
    }

    /// **Debounce 250ms.** Typing "ribs" is four keystrokes and one request.
    @Test func rapidTypingProducesOneRequest() async throws {
        let (store, stub) = makeStore([try RoundFixture.envelope("tracks_search")])

        for prefix in ["r", "ri", "rib", "ribs"] {
            store.query = prefix
            try await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .milliseconds(500))

        #expect(stub.count(matching: "/tracks/search") == 1)
        #expect((store.results.value ?? []).isEmpty == false)
    }

    /// `docs/08` §3.1: *"Empty query: no results list, no suggestions, no trending."* Including
    /// after a delete — leaving the last results under an emptied field would be the app having an
    /// opinion about a query nobody made.
    @Test func clearingTheFieldReturnsToABlankSheet() async throws {
        let (store, _) = makeStore([try RoundFixture.envelope("tracks_search")])

        store.query = "ribs"
        try await Task.sleep(for: .milliseconds(500))
        #expect(store.results.value != nil)

        store.query = ""
        #expect(store.results.value == nil)
        #expect(store.searchErrorKey == nil, "a blank sheet is not an error state")
    }

    /// An outage takes search away, and the line under the field says so **without pointing at
    /// anything** (`docs/06` §7, `docs/11` `search.error`).
    ///
    /// It used to send the reader to the paste-a-link box. That box is gone (`E37-01`), and a
    /// failure message naming a control that does not exist is worse than no message — so the
    /// assertion is now the other way round: whatever this line says, it must not say "Paste".
    @Test func anUpstreamOutageSaysSoWithoutOfferingAPastePath() async throws {
        let (store, _) = makeStore([RoundFixture.failure(502, "UPSTREAM_UNAVAILABLE")])

        store.query = "ribs"
        try await Task.sleep(for: .milliseconds(500))

        #expect(store.searchErrorKey == "search.error")
        #expect(!Copy.string("search.error").contains("Paste"))
    }

    /// Offline is its own line: nothing can be dropped right now, and that is a different fact
    /// from *"search is down"*.
    @Test func offlineSaysSoInItsOwnWords() async throws {
        let (store, _) = makeStore([RoundStub.Response(failure: URLError(.notConnectedToInternet))])

        store.query = "ribs"
        // Longer than the others on purpose: a transport failure is the one error worth retrying,
        // so a search spends its 200ms and 600ms backoffs before it gives up (`docs/13` §3). The
        // wait is the debounce plus both of those plus a margin — and the fact that it *takes* that
        // long is the retry policy working.
        try await Task.sleep(for: .milliseconds(1_600))

        #expect(store.searchErrorKey == "search.error.offline")
    }

    // MARK: - Pasting (`docs/08` §3.1, `docs/06` §4)

    /// A string that is not a link is refused **without a request**. The server would answer it
    /// with the same `INVALID_INPUT` it uses for a song it cannot find, and the copy deck gives
    /// those two different words.
    @Test func somethingThatIsNotALinkNeverReachesTheServer() async throws {
        let (store, stub) = makeStore([try RoundFixture.envelope("track_resolved")])

        store.pasted = "have you heard the new lorde"
        let track = await store.resolve()

        #expect(track == nil)
        #expect(store.pasteErrorKey == "resolve.error.badlink")
        #expect(stub.count(matching: "/tracks/resolve") == 0)
    }

    /// A real link resolves through `POST /tracks/resolve`.
    @Test func alinkResolvesToATrack() async throws {
        let (store, stub) = makeStore([try RoundFixture.envelope("track_resolved")])

        store.pasted = "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"
        let track = await store.resolve()

        #expect(track?.title == "Ribs")
        #expect(store.pasteErrorKey == nil)
        #expect(stub.count(matching: "/tracks/resolve") == 1)
    }

    /// A link the catalog does not carry is the *other* paste error — *"That song isn't in the
    /// Apple catalog. Search for it instead."*
    @Test func alinkTheCatalogDoesNotCarrySaysSo() async throws {
        let (store, _) = makeStore([RoundFixture.failure(400, "INVALID_INPUT")])

        store.pasted = "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"
        let track = await store.resolve()

        #expect(track == nil)
        #expect(store.pasteErrorKey == "resolve.error.notfound")
    }

    // MARK: - Sealing (`docs/08` §3.2)

    /// The happy path: the server seals it and hands back the submission the client adopts.
    @Test func sealingReturnsWhatTheServerSealed() async throws {
        let (store, _) = makeStore([RoundFixture.envelope(sealed())])
        let track = try RoundFixture.track()

        let submission = await store.seal(track)

        #expect(submission?.track.title == "Ribs")
        #expect(store.sealErrorKey == nil)
        #expect(!store.isSealing)
    }

    /// **A failure seals nothing** and says one line in `alert`. The screen runs no animation on
    /// this path — that is `ConfirmScreen`'s half, and it is a `guard let` over this return value.
    @Test func afailedSealSealsNothing() async throws {
        let (store, _) = makeStore([RoundFixture.failure(500, "INTERNAL")])

        let submission = await store.seal(try RoundFixture.track())

        #expect(submission == nil)
        #expect(store.sealErrorKey == "confirm.error")
    }

    /// **Sealing offline fails honestly.** It is never queued: a submission that "sends when you
    /// reconnect" could land at 20:01 and be silently rejected, or worse, silently accepted into
    /// tomorrow (`docs/13` §7).
    @Test func sealingOfflineFailsRatherThanQueueing() async throws {
        let (store, _) = makeStore([RoundStub.Response(failure: URLError(.notConnectedToInternet))])

        let submission = await store.seal(try RoundFixture.track())

        #expect(submission == nil)
        #expect(store.sealErrorKey == "search.error.offline")
    }

    /// The submission body is the one `docs/04` §4 takes, with the **Apple id** rather than the
    /// track key — the server re-resolves it so the sealed snapshot is the server's.
    @Test func thesealBodyIsTheContractsShape() async throws {
        let (store, stub) = makeStore([RoundFixture.envelope(sealed())])

        _ = await store.seal(try RoundFixture.track())

        let request = try #require(stub.requests.last)
        #expect(request.httpMethod == "PUT")
        let body = try #require(request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(contentsOf: buffer[0..<read])
            }
            return data
        })
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["apple_music_id"] as? String == "1440818664")
        #expect(json["spotify_url"] == nil, "exactly one of the three fields, or the server refuses")
    }

    /// The submission payload the fixture server answers a seal with.
    private func sealed() -> Data {
        Data(#"{"track":\#(String(data: (try? RoundFixture.payload("track_resolved")) ?? Data(), encoding: .utf8) ?? "{}"),"sealed_at":"2026-08-10T16:11:02Z"}"#.utf8)
    }
}
