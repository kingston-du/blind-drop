import CryptoKit
import Foundation
import Security
import Testing
@testable import BlindDrop

@MainActor
private final class FakeTrackOpener: TrackLinkOpening {
    var openable: Set<URL> = []
    private(set) var opened: [URL] = []
    func canOpen(_ url: URL) -> Bool { openable.contains(url) }
    func open(_ url: URL) { opened.append(url) }
}

@MainActor
private final class FakeSpotifyBrowser: SpotifyWebAuthenticating {
    private(set) var authorizationURL: URL?
    private(set) var requests = 0
    var duplicatesCode = false

    func callbackURL(
        for authorizationURL: URL,
        callbackHost: String,
        callbackPath: String
    ) async throws -> URL {
        requests += 1
        self.authorizationURL = authorizationURL
        let state = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value ?? ""
        let code = duplicatesCode ? "code=code-1&code=code-2" : "code=code-1"
        return URL(string: "https://\(callbackHost)\(callbackPath)?\(code)&state=\(state)")!
    }
}

@MainActor
private final class FakeSpotifyAuthorization: SpotifyAuthorizing {
    private(set) var requests: [URLRequest] = []
    private var addCount = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url!
        let body: Data
        let status: Int
        if url.path().hasSuffix("/me/playlists") {
            body = Data(#"{"id":"playlist-1","external_urls":{"spotify":"https://open.spotify.com/playlist/playlist-1"}}"#.utf8)
            status = 201
        } else {
            addCount += 1
            body = Data(#"{"snapshot_id":"snapshot"}"#.utf8)
            status = 201
        }
        return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
private final class FakeAppleMusic: AppleMusicProviding {
    var authorization: AppleMusicAuthorization = .authorized
    var subscription = true
    var subscriptionFails = false
    var playlistURL = URL(string: "https://music.apple.com/library/playlist/p.1")
    private(set) var createdIDs: [String] = []

    func requestAuthorization() async -> AppleMusicAuthorization { authorization }
    func hasSubscription() async throws -> Bool {
        if subscriptionFails { throw URLError(.cannotConnectToHost) }
        return subscription
    }
    func createPlaylist(name: String, appleMusicIDs: [String]) async throws -> URL? {
        createdIDs = appleMusicIDs
        return playlistURL
    }
}

@MainActor
@Suite(.serialized)
struct RecordTests {
    @Test func spotifyAndAppleLinksTryTheAppThenTheWeb() throws {
        let track = try RoundFixture.track()
        let spotify = try #require(TrackLinkDestination.spotify(track: track))
        let apple = try #require(TrackLinkDestination.appleMusic(track: track))
        let opener = FakeTrackOpener()

        TrackLinkRouter.open(spotify, using: opener)
        #expect(opener.opened == [spotify.webURL])

        opener.openable = [spotify.appURL, apple.appURL]
        TrackLinkRouter.open(spotify, using: opener)
        TrackLinkRouter.open(apple, using: opener)
        #expect(opener.opened.suffix(2) == [spotify.appURL, apple.appURL])
    }

    @Test func missingSpotifyMetadataMeansThereIsNoSpotifyDestination() throws {
        let data = try RoundFixture.payload("track_resolved")
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["spotify_id"] = NSNull()
        json["spotify_url"] = NSNull()
        let track = try JSONDecoder.api.decode(
            TrackDTO.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        #expect(TrackLinkDestination.spotify(track: track) == nil)
        #expect(TrackLinkDestination.appleMusic(track: track) != nil)
    }

    @Test func pkceRoundTripHasNoSecretAndKeychainsBothTokens() async throws {
        let browser = FakeSpotifyBrowser()
        let secrets = MemorySecrets()
        let stub = RoundStub.session()
        stub.arm([.init(
            status: 200,
            body: Data(#"{"access_token":"access-1","refresh_token":"refresh-1"}"#.utf8)
        )])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoundStub.self]
        configuration.httpAdditionalHeaders = [RoundStub.tokenHeader: stub.token]
        let auth = SpotifyAuth(
            clientID: "public-client-id",
            secrets: secrets,
            browser: browser,
            transport: APIClient.makeTransport(configuration)
        )

        let access = try await auth.authorize()

        #expect(access == "access-1")
        #expect(secrets.stored[Keychain.Account.spotifyAccessToken] == "access-1")
        #expect(secrets.stored[Keychain.Account.spotifyRefreshToken] == "refresh-1")
        let query = try #require(URLComponents(url: browser.authorizationURL!, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "response_type" }?.value == "code")
        #expect(query.first { $0.name == "code_challenge_method" }?.value == "S256")
        #expect(query.first { $0.name == "scope" }?.value == SpotifyAuth.scopes)
        #expect(query.first { $0.name == "redirect_uri" }?.value == SpotifyAuth.redirectURI)
        let tokenRequest = try #require(stub.requests.first)
        let tokenBody = String(data: requestBody(tokenRequest), encoding: .utf8) ?? ""
        #expect(tokenBody.contains("code_verifier="))
        #expect(!tokenBody.lowercased().contains("secret"))
        var tokenForm = URLComponents()
        tokenForm.percentEncodedQuery = tokenBody
        let verifier = try #require(
            tokenForm.queryItems?.first { $0.name == "code_verifier" }?.value
        )
        let expectedChallenge = SpotifyAuth.base64URL(
            Data(SHA256.hash(data: Data(verifier.utf8)))
        )
        #expect(query.first { $0.name == "code_challenge" }?.value == expectedChallenge)
    }

    @Test func spotifyTokensUseTheRequiredKeychainProtectionClass() throws {
        let keychain = Keychain(service: "app.blinddrop.tests.spotify.\(UUID().uuidString)")
        let accounts = [
            Keychain.Account.spotifyAccessToken,
            Keychain.Account.spotifyRefreshToken,
        ]
        defer { accounts.forEach { try? keychain.delete($0) } }

        for account in accounts {
            try keychain.write("token", to: account)
            #expect(try keychain.accessibility(of: account)
                    == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        }
    }

    @Test func aDuplicateOAuthParameterIsRejectedInsteadOfCrashing() async {
        let browser = FakeSpotifyBrowser()
        browser.duplicatesCode = true
        let auth = SpotifyAuth(
            clientID: "public-client-id",
            secrets: MemorySecrets(),
            browser: browser
        )

        await #expect(throws: SpotifyAuthError.invalidCallback) {
            try await auth.authorize()
        }
    }

    @Test func a401RefreshesOnceAndRetriesWithTheReplacementToken() async throws {
        let secrets = MemorySecrets()
        secrets.preload("expired", to: Keychain.Account.spotifyAccessToken)
        secrets.preload("refresh-1", to: Keychain.Account.spotifyRefreshToken)
        let browser = FakeSpotifyBrowser()
        let stub = RoundStub.session()
        stub.arm([
            .init(status: 401, body: Data()),
            .init(status: 200, body: Data(#"{"access_token":"access-2"}"#.utf8)),
            .init(status: 200, body: Data(#"{}"#.utf8)),
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoundStub.self]
        configuration.httpAdditionalHeaders = [RoundStub.tokenHeader: stub.token]
        let auth = SpotifyAuth(
            clientID: "public-client-id",
            secrets: secrets,
            browser: browser,
            transport: APIClient.makeTransport(configuration)
        )

        let (_, response) = try await auth.data(
            for: URLRequest(url: URL(string: "https://api.spotify.com/v1/me/playlists")!)
        )

        #expect(response.statusCode == 200)
        #expect(browser.requests == 0)
        #expect(stub.requests.count == 3)
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer expired")
        #expect(stub.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
        #expect(secrets.stored[Keychain.Account.spotifyRefreshToken] == "refresh-1")
    }

    @Test func aRejectedRefreshClearsTheOldTokensAndReauthorizesOnce() async throws {
        let secrets = MemorySecrets()
        secrets.preload("expired", to: Keychain.Account.spotifyAccessToken)
        secrets.preload("dead-refresh", to: Keychain.Account.spotifyRefreshToken)
        let browser = FakeSpotifyBrowser()
        let stub = RoundStub.session()
        stub.arm([
            .init(status: 401, body: Data()),
            .init(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8)),
            .init(status: 200, body: Data(#"{"access_token":"access-3","refresh_token":"refresh-3"}"#.utf8)),
            .init(status: 200, body: Data(#"{}"#.utf8)),
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoundStub.self]
        configuration.httpAdditionalHeaders = [RoundStub.tokenHeader: stub.token]
        let auth = SpotifyAuth(
            clientID: "public-client-id",
            secrets: secrets,
            browser: browser,
            transport: APIClient.makeTransport(configuration)
        )

        let (_, response) = try await auth.data(
            for: URLRequest(url: URL(string: "https://api.spotify.com/v1/me/playlists")!)
        )

        #expect(response.statusCode == 200)
        #expect(browser.requests == 1)
        #expect(stub.requests.count == 4)
        #expect(stub.requests[3].value(forHTTPHeaderField: "Authorization") == "Bearer access-3")
        #expect(secrets.stored[Keychain.Account.spotifyAccessToken] == "access-3")
        #expect(secrets.stored[Keychain.Account.spotifyRefreshToken] == "refresh-3")
    }

    @Test func spotifyExportBatches250InOrderUsingCurrentEndpoints() async throws {
        let auth = FakeSpotifyAuthorization()
        let exporter = SpotifyExporter(auth: auth)
        let payload = try exportPayload(service: "spotify", count: 250, unresolved: 3)

        let result = try await exporter.export(payload)

        #expect(result.unresolvedCount == 3)
        #expect(auth.requests.map { $0.url?.path() } == [
            "/v1/me/playlists",
            "/v1/playlists/playlist-1/items",
            "/v1/playlists/playlist-1/items",
            "/v1/playlists/playlist-1/items",
        ])
        let added = try auth.requests.dropFirst().flatMap { request -> [String] in
            let json = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            return try #require(json["uris"] as? [String])
        }
        #expect(added == (0..<250).map { "spotify:track:\($0)" })
        #expect(SpotifyExporter.batches(Array(repeating: "x", count: 250)).map(\.count) == [100, 100, 50])
    }

    @Test func appleGatesAreIndependentAndTheOrderedIDsReachMusicKit() async throws {
        let music = FakeAppleMusic()
        let exporter = AppleMusicExporter(music: music)
        let payload = try exportPayload(service: "apple", count: 4, unresolved: 2)

        music.authorization = .denied
        await #expect(throws: PlaylistExportError.denied) { try await exporter.export(payload) }

        music.authorization = .authorized
        music.subscription = false
        await #expect(throws: PlaylistExportError.noSubscription) { try await exporter.export(payload) }

        music.subscriptionFails = true
        await #expect(throws: PlaylistExportError.failed) { try await exporter.export(payload) }

        music.subscriptionFails = false
        music.subscription = true
        let result = try await exporter.export(payload)
        #expect(music.createdIDs == ["0", "1", "2", "3"])
        #expect(result.unresolvedCount == 2)
        #expect(result.service == .appleMusic)
    }

    @Test func anAppleAuthorizationFailureDoesNotChangeSpotifyExportState() async throws {
        let (env, session) = RoundFixture.environment(responses: [
            try RoundFixture.envelope("record_export_apple"),
        ])
        let music = FakeAppleMusic()
        music.authorization = .denied
        let store = RecordStore(
            api: env.api,
            spotify: SpotifyExporter(auth: FakeSpotifyAuthorization()),
            apple: AppleMusicExporter(music: music),
            circles: env.circles
        )

        await store.exportToAppleMusic()

        #expect(store.appleExport == .failed(.denied))
        #expect(store.spotifyExport == .idle)
        // `GET /groups` (resolving the active circle, `E19-01`) plus the export GET itself.
        #expect(session.requests.count == 2)
    }

    @Test func recordLoadsAt50FiltersOnTheServerAndPrefetchesAtTen() async throws {
        let (env, session) = RoundFixture.environment()
        let firstPage = try recordPage(dayIndexes: [0], nextCursor: "older", entryCount: 12)
        let groupID = try RoundFixture.groupID()
        session.arm(routes: [
            "/groups/\(groupID)/record": RoundFixture.envelope(firstPage),
            "/groups/\(groupID)": try RoundFixture.envelope("group_current"),
        ])
        let spotifyAuth = FakeSpotifyAuthorization()
        let music = FakeAppleMusic()
        let store = RecordStore(
            api: env.api,
            spotify: SpotifyExporter(auth: spotifyAuth),
            apple: AppleMusicExporter(music: music),
            circles: env.circles
        )

        await store.load()
        let firstRequest = try #require(session.requests.first { $0.url?.path().hasSuffix("/record") == true })
        #expect(URLComponents(url: firstRequest.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "limit" }?.value == "50")

        let secondPage = try recordPage(dayIndexes: [1], nextCursor: nil)
        session.arm([RoundFixture.envelope(secondPage)])
        let rows = try #require(store.days.first?.entries)
        await store.loadMoreIfNeeded(
            row: RecordRowID(roundID: store.days[0].roundID, userID: rows[1].userID)
        )
        #expect(session.requests.isEmpty, "eleven rows from the end is too early")
        await store.loadMoreIfNeeded(
            row: RecordRowID(roundID: store.days[0].roundID, userID: rows[2].userID)
        )
        #expect(store.days.count == 2)
        let pageRequest = try #require(session.requests.first)
        let pageQuery = URLComponents(url: pageRequest.url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(pageQuery?.first { $0.name == "cursor" }?.value == "older")

        session.arm([RoundFixture.envelope(firstPage)])
        let member = try #require(store.members.first)
        await store.select(memberID: member.userID)
        let filterQuery = URLComponents(url: session.requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(filterQuery?.first { $0.name == "member" }?.value == member.userID)
    }

    /// The archive gains a night at `scores_at`, two hours after reveal — reliably while the app
    /// is backgrounded. `RecordStore.load()` used to bail on `guard state.value == nil`, which was
    /// right while a pop destroyed the store and wrong the moment `RouteStoreCache` started keeping
    /// it for the session: the Record froze at whatever it held when it was first opened, and last
    /// night never appeared. This asserts the three halves of the fix — it refetches, the fresh
    /// newest night lands in front of days already paged in rather than collapsing the list, and
    /// the cursor keeps pointing past the deepest day on screen instead of resuming above it.
    @Test func aSecondLoadRefetchesAndPutsTheNewNightInFrontOfPagedInDays() async throws {
        let (env, session) = RoundFixture.environment()
        let groupID = try RoundFixture.groupID()
        // The archive as it stood before tonight scored: one night, more behind it.
        let beforeScoring = try recordPage(dayIndexes: [1], nextCursor: "older")
        session.arm(routes: [
            "/groups/\(groupID)/record": RoundFixture.envelope(beforeScoring),
            "/groups/\(groupID)": try RoundFixture.envelope("group_current"),
        ])
        let store = RecordStore(
            api: env.api,
            spotify: SpotifyExporter(auth: FakeSpotifyAuthorization()),
            apple: AppleMusicExporter(music: FakeAppleMusic()),
            circles: env.circles
        )
        await store.load()

        // Page two: an older night the reader has scrolled to, and a cursor past it.
        session.arm([RoundFixture.envelope(try recordPage(deepDayWithCursor: "deeper"))])
        let rows = try #require(store.days.first?.entries)
        await store.loadMoreIfNeeded(
            row: RecordRowID(roundID: store.days[0].roundID, userID: rows[rows.count - 1].userID)
        )
        #expect(store.days.count == 2)
        #expect(store.nextCursor == "deeper")

        // Foreground, or a return to the screen: tonight has scored since. Routed, not queued —
        // `load()` fires its two GETs concurrently, and a queue would hand whichever won the race
        // whichever answer happened to be first (`StubSession.arm(routes:)`).
        let afterScoring = try recordPage(dayIndexes: [0, 1], nextCursor: "older")
        session.arm(routes: [
            "/groups/\(groupID)/record": RoundFixture.envelope(afterScoring),
            "/groups/\(groupID)": try RoundFixture.envelope("group_current"),
        ])
        await store.load()

        #expect(session.count(matching: "/record") == 1, "a cached store must still refetch")
        #expect(
            store.days.map(\.localDate) == ["2026-08-08", "2026-08-07", "2026-07-30"],
            "the newest night belongs in front, and the paged-in day behind it"
        )
        #expect(
            store.nextCursor == "deeper",
            "adopting the refresh's cursor would resume pagination above days already shown"
        )

        // And a refresh that fails keeps what is on screen — `LoadState.stale`, not `.failed`.
        session.arm(routes: [
            "/groups/\(groupID)/record": RoundStub.Response(failure: URLError(.notConnectedToInternet)),
            "/groups/\(groupID)": try RoundFixture.envelope("group_current"),
        ])
        await store.load()
        #expect(store.days.count == 3)
        #expect(store.state.error != nil)
    }

    /// `E29-02`: the past-round results screen must hand a real `PreviewPlayer` to
    /// `ResultsScreen`. A source-level invariant in the same style as `RoundInsetTests`: without
    /// it, a past round's cards render with no preview control at all, because `ResultsScreen`
    /// defaults its `player` to `nil`.
    ///
    /// **Now spread over three files, and that is the point of keeping it.** The screen used to
    /// be `private` inside `RecordScreen`; it is `PastResultsScreen` in `Features/Results` now
    /// that the dark hours push it too (owner, 2026-09-03), so there are two call sites that
    /// must each pass a player and one screen that must forward it. A push added later with the
    /// argument left off is exactly what this catches.
    @Test func pastResultsScreenWiresTheSharedPreviewPlayerThrough() throws {
        let screen = try source("Results/PastResultsScreen.swift")
        // Matched in two pieces rather than as one argument list. Pinning the whole call meant
        // that adding an unrelated argument to `ResultsScreen` failed this test without the
        // player ever having been dropped — `isPastRound:` did exactly that. The invariant is
        // that the screen is constructed from the store's state *and* handed the shared player;
        // an argument arriving between them is not a regression and should not read as one.
        #expect(screen.contains("ResultsScreen(state: store.viewState(resolve: nil)"))
        #expect(screen.contains("player: player)"))
        #expect(screen.contains("let player: PreviewPlayer"))

        for caller in ["Record/RecordScreen.swift", "Round/RoundScreen.swift"] {
            let source = try source(caller)
            #expect(
                source.contains("PastResultsScreen(roundID: route.id, player: player)"),
                "\(caller) pushes the past-round results without the shared player"
            )
        }
    }

    private func source(_ path: String) throws -> String {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
            .appending(path: "BlindDrop/Features/\(path)")
        return try String(contentsOf: file, encoding: .utf8)
    }

    private func exportPayload(service: String, count: Int, unresolved: Int) throws -> ExportDTO {
        let tracks: [[String: Any]] = (0..<count).map { index in
            [
                "spotify_uri": service == "spotify" ? "spotify:track:\(index)" : NSNull(),
                "apple_music_id": service == "apple" ? "\(index)" : NSNull(),
                "isrc": "USABC0000000",
                "title": "Song \(index)",
                "artist": "Artist",
            ]
        }
        return try JSONDecoder.api.decode(ExportDTO.self, from: JSONSerialization.data(withJSONObject: [
            "playlist_name": "The Cove — Blind Drop",
            "tracks": tracks,
            "unresolved_count": unresolved,
        ]))
    }

    /// A page holding one night older than either of the fixture's two, for the tests that need a
    /// third. Copied from the fixture's oldest day with a new id and date, because a merge that
    /// keeps paged-in days cannot be shown to keep them using days the refresh also returns.
    private func recordPage(deepDayWithCursor cursor: String?) throws -> Data {
        let source = try #require(
            JSONSerialization.jsonObject(with: RoundFixture.payload("record")) as? [String: Any]
        )
        var day = try #require((source["days"] as? [[String: Any]])?[1])
        day["round_id"] = "c0000000-0000-4000-8000-000000000009"
        day["local_date"] = "2026-07-30"
        return try JSONSerialization.data(withJSONObject: [
            "days": [day],
            "next_cursor": cursor.map { $0 as Any } ?? NSNull(),
        ])
    }

    private func recordPage(
        dayIndexes: [Int],
        nextCursor: String?,
        entryCount: Int? = nil
    ) throws -> Data {
        let source = try #require(
            JSONSerialization.jsonObject(with: RoundFixture.payload("record")) as? [String: Any]
        )
        let days = try #require(source["days"] as? [[String: Any]])
        let cursorValue: Any = nextCursor.map { $0 as Any } ?? NSNull()
        var selectedDays = dayIndexes.map { days[$0] }
        if let entryCount, !selectedDays.isEmpty {
            let sourceEntries = try #require(selectedDays[0]["entries"] as? [[String: Any]])
            selectedDays[0]["entries"] = (0..<entryCount).map { index in
                var entry = sourceEntries[index % sourceEntries.count]
                entry["user_id"] = "record-user-\(index)"
                entry["display_name"] = "Member \(index)"
                return entry
            }
        }
        return try JSONSerialization.data(withJSONObject: [
            "days": selectedDays,
            "next_cursor": cursorValue,
        ])
    }

    /// `URLSession` moves an `httpBody` into a stream before a `URLProtocol` sees it.
    private func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[..<count])
        }
        return data
    }
}
