import Foundation
import Testing
@testable import BlindDrop

@Suite struct ProfileTests {

    @Test func profileDecodesNullableRatesAndCircleScopedTracks() throws {
        let json = """
        {
          "member":{"user_id":"u_ben","display_name":"Ben","role":"member"},
          "ear":{"value":null,"samples":0},
          "readability":{"value":0.5,"samples":5},
          "drop_count":5,
          "recent_tracks":[{"local_date":"2026-08-10","track":{
            "track_key":"am:1440818664","isrc":null,"title":"Redbone","artist":"Childish Gambino","album":"Awaken, My Love!","artwork_url":null,"artwork_bg_color":null,"duration_ms":327000,"preview_url":null,"apple_music_id":"1440818664","apple_music_url":"https://music.apple.com/us/song/1440818664","spotify_id":null,"spotify_url":null
          }}],
          "you_read_them":{"correct":3,"possible":5},
          "they_read_you":null
        }
        """
        let profile = try JSONDecoder.api.decode(MemberProfileDTO.self, from: Data(json.utf8))

        #expect(profile.member.displayName == "Ben")
        #expect(profile.ear.value == nil)
        #expect(profile.readability.value == 0.5)
        #expect(profile.dropCount == 5)
        #expect(profile.recentTracks.map(\.localDate) == ["2026-08-10"])
        #expect(profile.youReadThem?.rate == 0.6)
        #expect(profile.theyReadYou == nil)
    }

    @Test func theProfileEndpointNamesBothTheCircleAndMember() {
        let endpoint = Endpoint<MemberProfileDTO>.memberProfile("u_ben", in: "g_cove")
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/groups/g_cove/members/u_ben/profile")
        #expect(endpoint.retry.backoff == [.milliseconds(200), .milliseconds(600)])
    }
}
