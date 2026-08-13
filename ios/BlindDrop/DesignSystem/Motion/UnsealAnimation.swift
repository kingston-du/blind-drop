import SwiftUI

enum UnsealPhase: Equatable, Sendable {
    case sealed
    case revealed
}

/// One card's immutable presentation inputs. `FlightCard` remains reusable by results and
/// snapshots: only the reveal host supplies this value.
struct UnsealPresentation: Equatable, Sendable {
    let phase: UnsealPhase
    let groupInitial: String
    let reducedMotion: Bool
}

/// Coordinates the sequence without owning an unstructured task. `RevealHost` awaits `run` from
/// SwiftUI's `.task`, so leaving the screen cancels the sleeps. A card is released only after both
/// its scheduled instant and its frame becoming visible; below-fold cards therefore stay sealed
/// until the person scrolls to them.
@Observable @MainActor
final class UnsealAnimation {
    private(set) var revealedCards: Set<Int>

    private let cardNumbers: [Int]
    private let flags: LocalFlags
    private let haptics: any HapticEngine
    private var scheduledCards: Set<Int> = []
    private var visibleCards: Set<Int> = []
    private var started = false
    private var firedHaptic = false

    init(
        roundID: String,
        cardNumbers: [Int],
        flags: LocalFlags,
        haptics: any HapticEngine
    ) {
        self.cardNumbers = cardNumbers
        self.flags = flags
        self.haptics = haptics
        self.revealedCards = flags.hasSeenUnseal(roundID: roundID) ? Set(cardNumbers) : []
        self.roundID = roundID
    }

    private let roundID: String

    func phase(for cardNumber: Int) -> UnsealPhase {
        revealedCards.contains(cardNumber) ? .revealed : .sealed
    }

    func updateVisibleCards(_ cards: Set<Int>) {
        visibleCards = cards
        releaseEligibleCards()
    }

    func run(reducedMotion: Bool) async {
        guard !started else { return }
        started = true
        guard flags.beginUnseal(roundID: roundID) else {
            revealedCards = Set(cardNumbers)
            return
        }

        haptics.prepare(.coverMoves)
        let stagger = reducedMotion
            ? Motion.Unseal.reducedStagger(cardCount: cardNumbers.count)
            : Motion.Unseal.stagger(cardCount: cardNumbers.count)

        for (index, cardNumber) in cardNumbers.enumerated() {
            if index > 0 {
                do {
                    try await Task.sleep(for: .milliseconds(stagger))
                } catch {
                    revealedCards = Set(cardNumbers)
                    return
                }
            }
            scheduledCards.insert(cardNumber)
            releaseEligibleCards()
        }
    }

    private func releaseEligibleCards() {
        let eligible = scheduledCards.intersection(visibleCards).subtracting(revealedCards)
        guard !eligible.isEmpty else { return }

        for cardNumber in cardNumbers where eligible.contains(cardNumber) {
            revealedCards.insert(cardNumber)
            if cardNumber == cardNumbers.first, !firedHaptic {
                firedHaptic = true
                haptics.fire(.coverMoves)
            }
        }
    }
}

/// The sealed artwork that lifts away. All motion is transform/opacity; its geometry is fixed for
/// the entire sequence, matching the no-layout rule used by the seal.
struct UnsealingArtwork: View {
    let track: TrackDTO
    let presentation: UnsealPresentation

    private var revealed: Bool { presentation.phase == .revealed }

    var body: some View {
        ArtworkView(track, size: Layout.Artwork.flightCard)
            .scaleEffect(presentation.reducedMotion || revealed ? 1 : 0.98)
            .animation(presentation.reducedMotion ? nil : Motion.Unseal.artwork.animation,
                       value: presentation.phase)
            .overlay {
                GeometryReader { proxy in
                    cover(height: proxy.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous))
    }

    private func cover(height: CGFloat) -> some View {
        Palette.amberWash
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.amberDeep).frame(height: Stroke.border)
            }
            .overlay(alignment: .bottomTrailing) {
                SealStamp(initial: presentation.groupInitial)
                    .scaleEffect(revealed && !presentation.reducedMotion ? 1.06 : 1)
                    .opacity(revealed ? 0 : 1)
                    .animation(
                        presentation.reducedMotion
                            ? .easeInOut(duration: 0.240)
                            : Motion.Unseal.stamp.animation,
                        value: presentation.phase
                    )
                    .padding(Space.md)
            }
            .shadow(
                color: Palette.ink.opacity(revealed || presentation.reducedMotion ? 0 : 0.08),
                radius: revealed || presentation.reducedMotion ? 0 : 12,
                y: revealed || presentation.reducedMotion ? 0 : 4
            )
            .opacity(presentation.reducedMotion && revealed ? 0 : 1)
            .offset(y: presentation.reducedMotion || !revealed ? 0 : -height)
            .animation(
                presentation.reducedMotion
                    ? .easeInOut(duration: 0.240)
                    : Motion.Unseal.cover.animation,
                value: presentation.phase
            )
    }
}
