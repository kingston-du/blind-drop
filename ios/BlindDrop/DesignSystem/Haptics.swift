import UIKit

/// The app's entire haptic vocabulary: three notes, from `docs/09` §1–3.
///
/// They are named for the moment rather than for the generator, because the moment is what is
/// being tested. `docs/09` §6 asserts *counts* — the seal fires two, the unseal fires one, and
/// a reduced-motion seal still fires one — and a count test only means something if the thing
/// being counted is "the stamp landed" rather than "some rigid impact happened somewhere".
///
/// The reveal's assignment is the one deliberate third note: it is a committed action, not a
/// selection. A tap that buzzes because buzzing is available is still how an app ends up feeling
/// like a slot machine, and `CLAUDE.md` §2.7 rules out the whole genre.
enum Haptic: Sendable, Equatable, CaseIterable {
    /// `.impact(.soft)`, intensity 0.4 — the seal cover starting to move (`docs/09` §2, 100ms),
    /// and the first card's cover release in the unseal (§3).
    case coverMoves
    /// `.impact(.rigid)`, intensity 0.9 — the stamp making contact (`docs/09` §2, 380ms). Fired
    /// at the moment of contact, not at the start of the phase that draws it.
    case stampLands
    /// `.impact(.light)`, intensity 0.5 — a name commits to a card in the reveal.
    case nameLands

    var style: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .coverMoves: .soft
        case .stampLands: .rigid
        case .nameLands: .light
        }
    }

    var intensity: CGFloat {
        switch self {
        case .coverMoves: 0.4
        case .stampLands: 0.9
        case .nameLands: 0.5
        }
    }
}

/// What plays a `Haptic`.
///
/// A protocol so the animations can be driven by a counting double in a test without a device
/// (`docs/09` §6). **Reduced motion does not reach this type**: `docs/12` §4 — the seal becomes
/// a crossfade and still fires, because reduced motion is not reduced feedback. A conformance
/// that checked `accessibilityReduceMotion` would silently break that rule for every caller.
@MainActor
protocol HapticEngine: AnyObject {
    func fire(_ haptic: Haptic)
    /// Warms the generator ahead of a sequence. Called at the top of the seal, where a
    /// cold-start delay would land the feedback after the frame it belongs to.
    func prepare(_ haptic: Haptic)
}

/// The real one.
@MainActor
final class SystemHaptics: HapticEngine {
    private var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    init() {}

    func fire(_ haptic: Haptic) {
        let generator = generator(for: haptic)
        generator.impactOccurred(intensity: haptic.intensity)
        // Re-prepared immediately: the seal's notes are 280ms apart, which is inside the
        // window where a generator that was allowed to go cold costs the second one its timing.
        generator.prepare()
    }

    func prepare(_ haptic: Haptic) {
        generator(for: haptic).prepare()
    }

    private func generator(for haptic: Haptic) -> UIImpactFeedbackGenerator {
        if let existing = generators[haptic.style] { return existing }
        let created = UIImpactFeedbackGenerator(style: haptic.style)
        generators[haptic.style] = created
        return created
    }
}
