# 09 — Motion spec

Two moments get the entire motion budget. Everything else is standard iOS springs.

> **The seal is the one moment the app is remembered by.** It is the physical confirmation
> that the blind window is real. Spend disproportionate effort here and keep everything
> around it restrained.

All of this lives in `ios/BlindDrop/DesignSystem/Motion/`. Target: **60fps on an iPhone 12**,
verified with Instruments (`15-TESTING-AND-ACCEPTANCE.md` AC-11).

> **Open question (E14-03):** no iPhone 12 was available for this pass; verification ran on a
> physical iPhone 13 instead. The 13 is strictly faster, so a clean run there is a weaker
> guarantee than a clean run on the 12 — it does not prove the 12 hits 60fps, only that the 13
> does. Noted in the release note; re-verify on an actual iPhone 12 (or the oldest device the
> app still supports) before shipping if one becomes available.

---

## 1. Budget

| Moment | Duration | Effort |
|---|---|---|
| **The seal** | ~600ms | disproportionate |
| **The unseal** | ~380ms per card, staggered | disproportionate |
| Results name-resolve | 220ms × 120ms stagger | moderate |
| Screen transitions | iOS default | none |
| Button press | 120ms, scale 0.985 | none |
| Everything else | iOS default spring | none |

If a task proposes an animation not in this table, the answer is no.

---

## 2. The seal — 600ms

Runs on the Confirm screen (`08-SCREEN-SPECS.md` §3.2) **after** the submission API call
succeeds. Never speculatively. It is a confirmation of a fact.

### Timeline

```
   0ms                200                400                600
   │──────────────────│──────────────────│──────────────────│
 A ██████                                      button collapse (0–120)
 B    ████████████████████                     cover slides down (80–340)
 C                    ███                      cover settle overshoot (320–400)
 D                       ████████████          stamp lands (360–540)
 E                              ███████████    ring dissipates (480–640)
 F                                    ██████   countdown fades in (560–680)
       ▲                    ▲
       │                    └─ haptic .impact(.rigid) at 380ms, intensity 0.9
       └─ haptic .impact(.soft) at 100ms, intensity 0.4
```

### Phase A — the button collapses (0–120ms)
**Seal it** contracts horizontally toward its centre into a 52pt-wide pill, opacity to 0 over
the last 40ms. `spring(response: 0.22, dampingFraction: 0.85)`. The screen's primary action
disappearing is what makes the next 500ms feel inevitable.

### Phase B — the cover slides (80–340ms)
A solid `amberWash` panel with an `amberDeep` 1pt top edge translates from `y = -cardHeight`
to `y = 0`, covering the artwork completely. 260ms, custom curve
`cubicBezier(0.20, 0.90, 0.10, 1.00)` — fast out, long settle. Simultaneously:
- artwork translates `y: 0 → -8` and scales `1.0 → 0.98`
- artwork brightness `1.0 → 0.92`
- the cover carries a shadow `ink @ 8%, radius 0 → 12, y 0 → 4` **while moving only**,
  resolving to zero on land. This is the one shadow in the app (`07-DESIGN-SYSTEM.md` §2).

### Phase C — settle (320–400ms)
The cover overshoots by 2pt and returns. `spring(response: 0.18, dampingFraction: 0.62)`.
Small, but it is the difference between a panel arriving and a lid closing.

### Phase D — the stamp (360–540ms)
The seal mark lands at the cover's lower-right, inset `Space.xl` from both edges.

- Mark: a 56pt circular `amberDeep` outline at `Stroke.mark` (2pt) enclosing the group's
  initial in Bricolage Grotesque, plus a hairline inner ring at 4pt inset.
- `scale: 1.6 → 1.0`, `rotation: -8° → -4°`, `opacity: 0 → 1`.
- `spring(response: 0.28, dampingFraction: 0.72)` over 180ms.
- It lands **off-axis by 4°**. A stamp that lands square reads as a UI element; one that lands
  slightly crooked reads as a physical act. Do not "fix" this.
- Haptic `.impact(.rigid)` intensity 0.9 fires at the moment of contact (380ms), not at the
  start of the phase.

### Phase E — the ring (480–640ms)
A single `amberDeep` ring expands from the stamp's centre, `scale 1.0 → 1.9`,
`opacity 0.35 → 0`, 200ms, `easeOut`. One ring. Not three, not a pulse loop.

### Phase F — the countdown (560–680ms)
The countdown and *"Sealed until 8:00."* fade up 120ms, `easeOut`, offset `y: 6 → 0`.

### Implementation notes
- Drive with a single `phase` enum through `.phaseAnimator` or one `withAnimation` chain on a
  timeline — **not** six nested `DispatchQueue.main.asyncAfter` calls. It must be
  interruptible and it must be testable.
- Pre-decode the artwork before the animation begins. An image decode mid-seal is the most
  likely cause of a dropped frame.
- No blur, no `.drawingGroup()` unless profiling proves it necessary — it usually costs more
  than it saves at this size.
- The whole thing is one composited layer tree; nothing re-lays-out mid-animation. If
  Instruments shows layout passes during the seal, the view hierarchy is wrong.

---

## 3. The unseal — 8:00 PM

The counterpart. Cards unseal in sequence, amber giving way to ultramarine, on the first view
of `RevealScreen` for the round.

### Per-card, 380ms

```
   0ms          150         300         380
   │────────────│───────────│───────────│
 A ███████████████                        cover slides up (0–220)
 B    ██████████                          stamp fades (60–200)
 C          ████████████████              border amber → ultramarine (140–400)
 D              ██████████                artwork settles (200–340)
 E                     ██████████         number resolves (260–400)
```

- **A** — cover translates `y: 0 → -coverHeight`, 220ms, `easeOut`. Shadow re-appears while
  moving, resolves on exit.
- **B** — stamp `scale 1.0 → 1.06`, `opacity 1 → 0`, 140ms, `easeIn`. It lifts away with the
  cover rather than vanishing under it.
- **C** — card border and background interpolate `amberDeep → edge` and
  `amberWash → surface`, 260ms. The card number simultaneously interpolates
  `amberDeep → ultramarine`. **This is the only moment both accents exist on one screen**
  (`07-DESIGN-SYSTEM.md` §2), and it is exactly what the transition is for.
- **D** — artwork `scale 0.98 → 1.0`, `spring(response: 0.34, dampingFraction: 0.78)`.
- **E** — the number counts nothing and does not animate its value; it fades from 0.4 to 1.0
  opacity, 140ms. Numbers that spin up are a slot machine, not a tasting flight.

### Stagger

```swift
let stagger = min(80, 900 / max(1, cardCount - 1))   // milliseconds
```

80ms nominal, compressed so the full sequence never exceeds ~900ms + 380ms of tail. At 12
cards the stagger becomes 81ms → clamped to 80; at 20 (not reachable in v1) it would
compress. Total for 12 cards ≈ 1.26s, which is the correct length for a group all staring at
their phones at the same second.

One haptic only: `.impact(.soft)` at the **first** card's cover release. Twelve haptics is a
massage chair.

Cards below the fold animate when scrolled into view if the sequence has already passed them,
so nothing appears pre-unsealed.

Persist `hasSeenUnseal(roundId)` in `UserDefaults`. Runs exactly once per round.

---

## 4. Results name-resolve

Card owners' names arrive top-to-bottom, 120ms apart, each a 220ms crossfade plus `y: 4 → 0`.
The correct/incorrect mark on your guess arrives 80ms after its name.

**Any scroll gesture completes the entire sequence immediately.** A user who already knows
what they want to see must never be made to wait for an animation. Runs once per round.

---

## 5. Reduced motion

`@Environment(\.accessibilityReduceMotion)`. Under reduced motion the seal and unseal become
**crossfades between the same two states** — they are not eliminated, and no state is
skipped. The sealed card still exists; it simply arrives without traversal.

| Moment | Reduced-motion behaviour |
|---|---|
| Seal | 240ms crossfade from confirm layout to sealed layout. No translation, no scale, no rotation, no ring. Stamp appears at final position and rotation. **Haptic still fires once** at the crossfade midpoint — reduced motion is not reduced feedback. |
| Unseal | 240ms crossfade per card, stagger reduced to 40ms, capped at 400ms total. Colour interpolation retained (it is information, not motion). |
| Results resolve | All names appear at once, no stagger. |
| Button press | Opacity only, no scale. |
| Everything else | iOS handles it. |

Colour transitions are **kept** under reduced motion because the amber→ultramarine change is
semantic (`07-DESIGN-SYSTEM.md` §2). Reduced motion removes movement, not meaning.

---

## 6. Verification

| Check | How |
|---|---|
| 60fps on iPhone 12 (ran on iPhone 13 — see open question above) | Instruments → Animation Hitches. Zero hitches over 10 consecutive seals. |
| No layout during seal | Instruments → SwiftUI view-body counts flat during the animation. |
| Reduced motion path | UI test with `UIAccessibility.isReduceMotionEnabled` forced; assert final state matches the normal path's final state exactly. |
| Unseal runs once | Unit test on the `hasSeenUnseal` flag across relaunch. |
| Stagger clamp | Unit test `stagger(for: 6) == 80`, `stagger(for: 12) == 80`, `stagger(for: 30) == 31`. |
| Haptic count | Unit test: seal fires 2, unseal fires 1, reduced-motion seal fires 1. |
