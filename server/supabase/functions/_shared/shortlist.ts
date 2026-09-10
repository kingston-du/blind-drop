/**
 * The four names a card offers (`docs/02` §3.1).
 *
 * A guess sheet is `S − 1` decisions over `S − 1` names, and both halves grow with the circle
 * while the knowledge anyone actually has does not. Somebody who can read three people cold
 * still has to be right about those three *and* not be dragged off by eight cards they are
 * flipping a coin on — so in a large circle a real read is diluted to nothing and the round is
 * decided by luck. Narrowing each card to four candidates makes the *decision* the same size in
 * every circle: one card, four names, one of whom dropped it.
 *
 * Four properties this file exists to guarantee:
 *
 * 1. **The owner is always in it.** The shortlist narrows the field; it never removes the
 *    answer. A card whose four names excluded its owner would be unwinnable and the player
 *    would have no way to know.
 * 2. **The viewer is never in it.** You know you did not drop it, so your own name among the
 *    four is a wasted slot — it would quietly make your cards 1-in-3 while everyone else played
 *    1-in-4. Excluding the viewer is what keeps the odds identical for every member.
 * 3. **It is otherwise the same list for everybody.** A card draws **one** canonical four, from
 *    a seed with no viewer in it, and every member who is not in that four sees exactly it —
 *    same names, same order. The three who *are* in it see their own name replaced, in place,
 *    by one other name. So a card is one shared object that differs for three people by one
 *    chip, which is as close to identical as excluding the viewer permits: any scheme that
 *    keeps you out of your own four must differ for the people who would have been in it, and
 *    this one differs for nobody else and by nothing else.
 * 4. **It never moves.** The same (round, card, viewer) yields the same four on every read, for
 *    the life of the round, from any instance. `GET /current` is polled; a shortlist that
 *    reshuffled under a half-finished sheet would be indistinguishable from the app lying.
 *
 * **What two colluding players can work out**, stated rather than left to be discovered: if one
 * of them is in a card's canonical four, their two lists differ in one slot, and neither of the
 * two differing names is the owner — four narrows to three. It needs two people comparing
 * screens, which is a thing players who want to break the game can already do far more directly
 * by comparing reasoning, and it is the price of the shared list being shared at all.
 *
 * Nothing here is a secret and nothing here is security. The shortlist is *derived* from what
 * the revealed round already hands out — the card numbering and the name pool — and is only
 * ever computed for a round in `revealed` or later. It narrows the field on who owns a card,
 * which is the entire intent, and it does so strictly after the blind window has closed.
 */

/** Four: the owner, and three others. See the file comment for why this number and not another. */
export const SHORTLIST_SIZE = 4;

/**
 * FNV-1a, 32-bit. A hash, not a digest — it needs to be stable and cheap, not unguessable, and
 * `crypto.subtle` is async and would make every caller in this file async with it.
 */
function fnv1a(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** mulberry32. Seeded, deterministic, and self-contained — `Math.random()` would be none of those. */
function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Fisher–Yates, in place, drawing from `next`. */
function shuffle<T>(items: T[], next: () => number): T[] {
  for (let i = items.length - 1; i > 0; i--) {
    const j = Math.floor(next() * (i + 1));
    [items[i], items[j]] = [items[j], items[i]];
  }
  return items;
}

/**
 * The candidate names for one card, as seen by one member.
 *
 * Always contains `ownerId`, never contains `viewerId`, and is `min(SHORTLIST_SIZE, S − 1)`
 * long — so a circle small enough that four names *is* the whole pool gets the whole pool and
 * nothing changes for it. With `S = 6` submitters the first name is dropped; below that this
 * function is a no-op in effect, which is the intended shape: the problem it solves does not
 * exist in a circle of five.
 *
 * `submitterIds` is sorted before anything is drawn, so the result does not depend on the order
 * the database happened to return the rows in.
 */
export function cardShortlist(params: {
  roundId: string;
  cardNo: number;
  ownerId: string;
  viewerId: string;
  submitterIds: readonly string[];
}): string[] {
  const { roundId, cardNo, ownerId, viewerId, submitterIds } = params;

  // Sorted, so nothing below depends on the order the database returned the rows in.
  const others = [...new Set(submitterIds)].filter((id) => id !== ownerId).sort();

  // **The caller's own card is the one case with nobody to hide.** They never guess it —
  // `my_card_no` takes it out of the sheet and the quick pass steps over it — and here the
  // viewer *is* the owner, so removing them would remove the one name property 1 promises is
  // always present. The list is emitted whole and goes unread.
  const hidesViewer = viewerId !== ownerId;

  // A circle small enough that four names *is* the pool. There is nothing to narrow and nothing
  // to substitute: everybody sees everybody, minus themselves. Below six submitters this
  // function is a no-op in effect, which is the intended shape — the problem it solves does not
  // exist in a circle of five.
  if (others.length <= SHORTLIST_SIZE - 1) {
    const all = shuffle([ownerId, ...others], mulberry32(fnv1a(`${roundId}|${cardNo}`)));
    return hidesViewer ? all.filter((id) => id !== viewerId) : all;
  }

  // The card's one canonical four. No viewer in the seed, so every member derives the same list
  // in the same order.
  const shared = mulberry32(fnv1a(`${roundId}|${cardNo}`));
  const drawn = shuffle([...others], shared).slice(0, SHORTLIST_SIZE - 1);
  const canonical = shuffle([ownerId, ...drawn], shared);

  if (!hidesViewer || !canonical.includes(viewerId)) return canonical;

  // The viewer was drawn into their own card's four. Swap them out **in place**: same length,
  // same order, one name different. Re-drawing the whole list instead would give this one member
  // a list unrelated to everyone else's for no gain — the only thing wrong with the canonical
  // list, for them, is the one slot with their name in it.
  const spare = others.filter((id) => id !== viewerId && !canonical.includes(id));
  if (spare.length === 0) {
    // Unreachable by arithmetic — this branch has at least four `others` and only three are
    // drawn, so at least one is always left over. It is here because the alternative to a guard
    // is writing `undefined` into a name pool.
    return canonical.filter((id) => id !== viewerId);
  }
  const [substitute] = shuffle(
    [...spare],
    mulberry32(fnv1a(`${roundId}|${cardNo}|${viewerId}`)),
  );

  return canonical.map((id) => (id === viewerId ? substitute : id));
}
