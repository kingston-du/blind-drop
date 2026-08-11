import Foundation

/// `docs/04` §1. Every successful response, without exception: the resource, and the server's
/// clock beside it.
///
/// `serverNow` is not decoration. It is how the app knows what time it is (`docs/13` §5): the
/// client re-anchors `ServerClock` from **every** response, so the offset stays fresh with no
/// extra requests and drift never accumulates. `APIClient` feeds it to the clock *before*
/// returning the payload, which is what makes "the countdown is server time" true for the very
/// first screen rather than one request later.
struct Envelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let serverNow: Date
    let data: Payload

    enum CodingKeys: String, CodingKey {
        case serverNow = "server_now"
        case data
    }
}

/// The failure half of `docs/04` §1: `{ server_now, error: { code, message, … } }`.
///
/// It carries `server_now` too, and the client re-anchors from it — a failed request is still
/// evidence about the time, and a phone that has been refused three times in a row is exactly
/// the phone whose clock should not be guessing.
struct ErrorEnvelope: Decodable, Sendable {
    let serverNow: Date
    let error: Failure

    struct Failure: Decodable, Sendable {
        let code: String
        /// User-presentable, and the only prose the server sends. The client shows the string
        /// from `docs/11` keyed by the code (see `APIError.copyKey`) rather than this one, so
        /// that copy is translatable and lives in one place — but the field is decoded because
        /// a `message` that does not match the deck is a contract drift worth catching.
        let message: String
        /// `WRONG_PHASE` only, and it is the round's state and nothing else (`docs/04` §1).
        let state: RoundState?
        let details: Details?

        struct Details: Decodable, Sendable {
            /// `INVALID_INPUT` only — the offending field's name, never its value.
            let field: String?
        }

        enum CodingKeys: String, CodingKey {
            case code, message, state, details
        }
    }

    enum CodingKeys: String, CodingKey {
        case serverNow = "server_now"
        case error
    }
}

extension ErrorEnvelope.Failure {
    /// The typed error, with whatever this code is allowed to carry attached.
    func apiError(retryAfter: TimeInterval?) -> APIError {
        APIError(code: code, state: state, field: details?.field, retryAfter: retryAfter)
    }
}

extension JSONDecoder {
    /// The one decoder configuration the app uses.
    ///
    /// `.iso8601` because `docs/04` says every timestamp on the wire is RFC 3339 UTC with a
    /// `Z`, and there is no second format to be tolerant of. Keys are **not** converted
    /// automatically: every DTO writes its `CodingKeys` out, so the field names in this app
    /// are the field names in the contract and a renamed key fails loudly at the one place
    /// that names it.
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
