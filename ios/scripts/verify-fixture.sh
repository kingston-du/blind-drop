#!/usr/bin/env bash
# ios/scripts/verify-fixture.sh — E09.
#
# Runs one test suite against a live ios/Fixtures/server.ts, which is how the epics' "completes
# against the fixture server" lines are actually checked: the real APIClient, the real DTO
# decoding, and payloads that are docs/04 verbatim (E00-05).
#
#   ./ios/scripts/verify-fixture.sh <suite> [description] [simulator name]
#
#   ./ios/scripts/verify-fixture.sh BlindDropUnitTests/FixtureSignInTests "Sign-in"
#   ./ios/scripts/verify-fixture.sh BlindDropUnitTests/FixtureOnboardingTests "Onboarding"
#
# The server is started here rather than assumed, because the suites skip themselves when
# BLINDDROP_FIXTURE_API is unset — and a suite that silently passes when its server is not
# running is worse than no suite at all.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE="${1:?usage: verify-fixture.sh <suite> [description] [simulator]}"
WHAT="${2:-$SUITE}"
SIMULATOR="${3:-iPhone 17}"
PORT="${PORT:-8788}"
DENO="$ROOT/server/node_modules/.bin/deno"
GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; OFF=$'\033[0m'

if [ ! -x "$DENO" ] && ! command -v deno >/dev/null 2>&1; then
  printf '%sDeno is missing. Run `cd server && npm install`.%s\n' "$RED" "$OFF"
  exit 2
fi
[ -x "$DENO" ] || DENO="$(command -v deno)"

# Do not silently attach a test run to another session's fixture server. Its phase, latency, or
# source tree may differ from this checkout, which turns a passing result into evidence about
# somebody else's process. Pick another explicit `PORT` when one is already occupied.
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  printf '%sPort :%s is already in use; choose a free PORT for this fixture run.%s\n' "$RED" "$PORT" "$OFF"
  exit 2
fi

printf '%sStarting the fixture server on :%s%s\n' "$DIM" "$PORT" "$OFF"
PORT="$PORT" "$DENO" run --allow-net --allow-read --allow-env "$ROOT/ios/Fixtures/server.ts" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

# Wait for it, rather than sleeping and hoping.
for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:$PORT/__fixture" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
if ! curl -fsS "http://127.0.0.1:$PORT/__fixture" >/dev/null 2>&1; then
  printf '%sThe fixture server never came up on :%s.%s\n' "$RED" "$PORT" "$OFF"
  exit 1
fi

# TEST_RUNNER_-prefixed environment variables reach the test process with the prefix stripped.
# They must be *environment variables*, before `xcodebuild`; trailing words are Xcode build
# settings and silently leave the suite disabled (every fixture test then reports skipped).
TEST_RUNNER_BLINDDROP_FIXTURE_API="http://127.0.0.1:$PORT" xcodebuild test \
  -project "$ROOT/ios/BlindDrop.xcodeproj" \
  -scheme BlindDrop \
  -destination "platform=iOS Simulator,OS=latest,name=$SIMULATOR" \
  -derivedDataPath "$ROOT/ios/.build" \
  -only-testing:"$SUITE" \
  | grep -E '✔|✘|Test run|error:' || true

# xcodebuild's exit status is what decides, not the grep's.
if TEST_RUNNER_BLINDDROP_FIXTURE_API="http://127.0.0.1:$PORT" xcodebuild test-without-building \
  -project "$ROOT/ios/BlindDrop.xcodeproj" \
  -scheme BlindDrop \
  -destination "platform=iOS Simulator,OS=latest,name=$SIMULATOR" \
  -derivedDataPath "$ROOT/ios/.build" \
  -only-testing:"$SUITE" >/dev/null 2>&1
then
  printf '%s%s completes against the fixture server.%s\n' "$GREEN" "$WHAT" "$OFF"
else
  printf '%s%s did not complete against the fixture server.%s\n' "$RED" "$WHAT" "$OFF"
  exit 1
fi
