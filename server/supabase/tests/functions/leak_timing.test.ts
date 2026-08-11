// leak_timing.test.ts — the side channel that has no key set. tasks/E04-04, docs/14 §3.
//
// The golden files close the obvious channel: no field on an `open`-phase response says how
// many people have submitted. This file closes the one you cannot see in a payload.
//
// If `GET /rounds/current` did any work proportional to participation — a `count(*)`, a join
// across the round's submissions, even a filter the database evaluates over every row before
// the handler discards them — then response *time* would carry the count. A member could sit
// on a timer all evening and watch the room fill up. docs/14 §3 puts the threshold at
// |r| < 0.2 over 100 samples, and this is that measurement.
//
// The handler is built so that the answer is structurally zero rather than merely small: the
// only read of `submissions` in the `open` path is keyed by `(round_id, user_id)` on a unique
// index and can return exactly one row, the caller's own. Nothing else looks at the table.
// This test exists to notice the day that stops being true.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { call, newGroupOwner, newMember, zoneWhereLocalHourIs } from "./_harness.ts";

/** Submitter counts to sample across, and how many timings at each. 7 × 15 = 105 samples. */
const COUNTS = [0, 1, 3, 5, 7, 9, 11];
const SAMPLES_PER_COUNT = 15;
const THRESHOLD = 0.2;

function pearson(xs: number[], ys: number[]): number {
  const n = xs.length;
  const meanX = xs.reduce((a, b) => a + b, 0) / n;
  const meanY = ys.reduce((a, b) => a + b, 0) / n;
  let cov = 0, varX = 0, varY = 0;
  for (let i = 0; i < n; i += 1) {
    const dx = xs[i] - meanX;
    const dy = ys[i] - meanY;
    cov += dx * dy;
    varX += dx * dx;
    varY += dy * dy;
  }
  if (varX === 0 || varY === 0) return 0;
  return cov / Math.sqrt(varX * varY);
}

/** The median of a small sample, used to report a readable summary. The correlation itself is
 *  computed over every sample, not over the medians — averaging first would hide variance
 *  that is exactly what a timing attack exploits. */
function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

Deno.test({
  name: "GET /rounds/current latency does not correlate with the number of submitters",
  // Builds groups spanning the supported sample counts and takes a hundred timings. It is the
  // slowest test in the suite and it is the one that proves AC-1's hardest clause.
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const fixtures: Array<{ count: number; token: string }> = [];

    for (const count of COUNTS) {
      const { user: ana, group } = await newGroupOwner("Ana", {
        name: `Timing ${count}`,
        timezone: zoneWhereLocalHourIs(12),
        reveal_hour: 20,
      });
      const code = group.invite_code as string;

      // Ana's own submission is present in every fixture, so every response has the same shape.
      await call("rounds", "/current/submission", {
        method: "PUT",
        token: ana.token,
        body: { apple_music_id: "1440818664" },
      });

      for (let other = 0; other < count; other += 1) {
        const member = await newMember(code, `T${other}`);
        await call("rounds", "/current/submission", {
          method: "PUT",
          token: member.token,
          // Distinct tracks, so a leak would have distinct things to leak and a join would
          // have real work to do.
          body: {
            apple_music_id: ["1440765580", "1452874255", "1440830827", "1442571948"][other % 4],
          },
        });
      }

      fixtures.push({ count, token: ana.token });
    }

    // Warm every caller's JWT path and the shared isolate/connection pool before measuring.
    for (const fixture of fixtures) {
      for (let i = 0; i < 5; i += 1) {
        await call("rounds", "/current", { token: fixture.token });
      }
    }

    const xs: number[] = [];
    const ys: number[] = [];
    const byCount = Object.fromEntries(COUNTS.map((count) => [count, [] as number[]]));

    // Rotate the fixture order for every sampling round. Measuring all zero-count requests,
    // then all one-count requests, and so on makes ordinary machine load drift indistinguishable
    // from participation-dependent work. Rotation balances every count across the run instead.
    for (let sample = 0; sample < SAMPLES_PER_COUNT; sample += 1) {
      for (let offset = 0; offset < fixtures.length; offset += 1) {
        const fixture = fixtures[(sample + offset) % fixtures.length];
        const started = performance.now();
        const res = await call("rounds", "/current", { token: fixture.token });
        const elapsed = performance.now() - started;
        assertEquals(res.status, 200);
        xs.push(fixture.count);
        ys.push(elapsed);
        byCount[fixture.count].push(elapsed);
      }
    }

    const r = pearson(xs, ys);
    const summary = COUNTS.map((c) => `${c}:${median(byCount[c]).toFixed(1)}ms`).join("  ");
    console.log(`  submitters → median latency   ${summary}`);
    console.log(
      `  Pearson r = ${r.toFixed(4)} over ${xs.length} samples (threshold ±${THRESHOLD})`,
    );

    assert(
      Math.abs(r) < THRESHOLD,
      `Latency correlates with submitter count (r = ${r.toFixed(4)}). Something in the open ` +
        `path is doing work proportional to participation — that is a count, delivered by ` +
        `stopwatch (docs/14 §3).`,
    );
  },
});
