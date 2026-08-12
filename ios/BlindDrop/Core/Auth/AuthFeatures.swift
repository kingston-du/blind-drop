/// Build flags that gate an authentication method.
///
/// There is exactly one, and it is off.
enum AuthFeatures {

    /// Phone OTP. **Off in v1** (`docs/01` §5, `docs/14` §5): it needs an SMS provider we have
    /// not chosen, and SMS is a cost-amplification target that would need its own rate limiting
    /// before it could be turned on.
    ///
    /// A compilation condition rather than a runtime setting, so the flag being off means the
    /// phone path is not in the binary at all — not merely unreachable from the UI. `AuthTests`
    /// asserts it is off in every build we ship, which is what makes "flagged" a fact rather
    /// than a plan.
    static let isPhoneAuthEnabled: Bool = {
        #if BLINDDROP_PHONE_AUTH
        true
        #else
        false
        #endif
    }()
}
