// shortlist.test.ts — `_shared/shortlist.ts`, the four names a card offers.
//
// Pure, and deliberately not on the harness: nothing here touches the database or an endpoint,
// so nothing here should need the stack up to run. What is being asserted is that the narrowing
// is *invisible when it works* — a shortlist that dropped the owner, leaked the viewer's own
// name into the four, or reshuffled between two polls of `GET /current` would look from the
// outside exactly like a player having a bad night, and no endpoint test would catch it.

import { assert, assertEquals } from "jsr:@std/assert@1";

import { cardShortlist, SHORTLIST_SIZE } from "../../functions/_shared/shortlist.ts";

const SUBMITTERS = [
  "aaaaaaaa-0000-4000-8000-000000000001",
  "bbbbbbbb-0000-4000-8000-000000000002",
  "cccccccc-0000-4000-8000-000000000003",
  "dddddddd-0000-4000-8000-000000000004",
  "eeeeeeee-0000-4000-8000-000000000005",
  "ffffffff-0000-4000-8000-000000000006",
  "aaaaaaaa-0000-4000-8000-000000000007",
  "bbbbbbbb-0000-4000-8000-000000000008",
];
const ROUND = "99999999-0000-4000-8000-00000000000f";

Deno.test("shortlist — always contains the owner, never the viewer", () => {
  for (const [index, owner] of SUBMITTERS.entries()) {
    for (const viewer of SUBMITTERS) {
      const list = cardShortlist({
        roundId: ROUND,
        cardNo: index + 1,
        ownerId: owner,
        viewerId: viewer,
        submitterIds: SUBMITTERS,
      });
      assert(list.includes(owner), `card ${index + 1} dropped its own owner`);
      if (viewer !== owner) {
        assert(!list.includes(viewer), `card ${index + 1} offered the viewer their own name`);
      }
    }
  }
});

Deno.test("shortlist — four names, all of them submitters, no repeats", () => {
  const list = cardShortlist({
    roundId: ROUND,
    cardNo: 3,
    ownerId: SUBMITTERS[2],
    viewerId: SUBMITTERS[5],
    submitterIds: SUBMITTERS,
  });
  assertEquals(list.length, SHORTLIST_SIZE);
  assertEquals(new Set(list).size, SHORTLIST_SIZE);
  for (const id of list) assert(SUBMITTERS.includes(id));
});

Deno.test("shortlist — stable across calls and across row order", () => {
  const args = {
    roundId: ROUND,
    cardNo: 4,
    ownerId: SUBMITTERS[3],
    viewerId: SUBMITTERS[0],
    submitterIds: SUBMITTERS,
  };
  const first = cardShortlist(args);
  assertEquals(cardShortlist(args), first, "a second read moved the shortlist");
  // The database does not promise an order. Neither may this.
  assertEquals(
    cardShortlist({ ...args, submitterIds: [...SUBMITTERS].reverse() }),
    first,
    "the shortlist followed the order the rows arrived in",
  );
});

Deno.test("shortlist — a small circle gets the whole pool, so nothing is hidden", () => {
  // Five submitters: the viewer's pool is four names, and four is the shortlist. Below six
  // people this function has nothing to narrow, and must not pretend otherwise.
  const five = SUBMITTERS.slice(0, 5);
  const list = cardShortlist({
    roundId: ROUND,
    cardNo: 1,
    ownerId: five[0],
    viewerId: five[4],
    submitterIds: five,
  });
  assertEquals([...list].sort(), five.filter((id) => id !== five[4]).sort());
});

Deno.test("shortlist — three submitters, and the list is what is left", () => {
  const three = SUBMITTERS.slice(0, 3);
  const list = cardShortlist({
    roundId: ROUND,
    cardNo: 2,
    ownerId: three[1],
    viewerId: three[0],
    submitterIds: three,
  });
  assertEquals([...list].sort(), [three[1], three[2]].sort());
});

Deno.test("shortlist — different cards draw different names", () => {
  // A sanity check, not a fairness one: a seed that ignored `cardNo` would pass every test
  // above and hand the whole round one shortlist.
  const base = {
    roundId: ROUND,
    ownerId: SUBMITTERS[0],
    viewerId: SUBMITTERS[7],
    submitterIds: SUBMITTERS,
  };
  const byCard = new Set(
    [1, 2, 3, 4, 5, 6, 7, 8].map((cardNo) =>
      cardShortlist({ ...base, cardNo }).slice().sort().join(",")
    ),
  );
  assert(byCard.size > 1, "every card drew the same three others");
});

Deno.test("shortlist — everyone not in the four sees the identical four, in order", () => {
  // The sharing property. Order included: two people looking at the same card should be able to
  // describe it to each other, and "the second one" has to mean the same name to both.
  const owner = SUBMITTERS[2];
  const lists = new Map<string, string>();
  for (const viewer of SUBMITTERS) {
    if (viewer === owner) continue;
    const list = cardShortlist({
      roundId: ROUND,
      cardNo: 3,
      ownerId: owner,
      viewerId: viewer,
      submitterIds: SUBMITTERS,
    });
    lists.set(viewer, list.join(","));
  }

  // Exactly three people are in the canonical four besides the owner, so exactly three see a
  // substituted list. Everybody else — and there must be somebody else — sees the same one.
  const counts = new Map<string, number>();
  for (const list of lists.values()) counts.set(list, (counts.get(list) ?? 0) + 1);
  const majority = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
  assert(majority[1] >= 2, "no two members saw the same list");
  assertEquals(
    counts.size,
    lists.size - majority[1] + 1,
    "the members who differ from the majority did not each differ uniquely",
  );
});

Deno.test("shortlist — a member in the four sees one name swapped, in place", () => {
  // The substitution, and the reason it is a substitution rather than a re-draw: the list a
  // swapped-out member sees must still be the shared list everybody else is looking at, minus
  // the one slot that had their own name in it.
  const owner = SUBMITTERS[2];
  const card = { roundId: ROUND, cardNo: 3, ownerId: owner, submitterIds: SUBMITTERS };

  // Find someone who is in the canonical four. An outsider's list *is* the canonical four.
  const outsiders = SUBMITTERS.filter((id) => id !== owner);
  const canonical = cardShortlist({ ...card, viewerId: "nobody-at-all" });
  const insider = outsiders.find((id) => canonical.includes(id));
  assert(insider, "nobody but the owner was in the canonical four");

  const theirs = cardShortlist({ ...card, viewerId: insider });
  assertEquals(theirs.length, canonical.length, "the swap changed the number of candidates");
  assert(!theirs.includes(insider), "they were offered their own name");
  assert(theirs.includes(owner), "the swap lost the owner");

  const differing = canonical.filter((id, i) => theirs[i] !== id);
  assertEquals(differing, [insider], "more than the viewer's own slot moved");
});

Deno.test("shortlist — the substitute is stable and is a real submitter", () => {
  const owner = SUBMITTERS[2];
  const card = { roundId: ROUND, cardNo: 3, ownerId: owner, submitterIds: SUBMITTERS };
  const canonical = cardShortlist({ ...card, viewerId: "nobody-at-all" });
  const insider = SUBMITTERS.find((id) => id !== owner && canonical.includes(id))!;

  const first = cardShortlist({ ...card, viewerId: insider });
  assertEquals(cardShortlist({ ...card, viewerId: insider }), first, "the substitute moved");
  for (const id of first) assert(SUBMITTERS.includes(id), "the substitute is not a submitter");
});
