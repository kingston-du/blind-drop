#!/usr/bin/env bash
# ios/scripts/verify-signin.sh — E09-01.
#
# The epic's first verification line: "sign-in completes against the fixture server."
#
# Starts ios/Fixtures/server.ts, points BlindDropUnitTests/FixtureSignInTests at it, and runs
# the real SupabaseAuthService, the real Keychain and the real APIClient through the whole
# path — exchange, store, GET /me, refresh, revoke. Only Apple's sheet is stubbed.
#
#   ./ios/scripts/verify-signin.sh [simulator name]
#
# Without the server the suite is skipped rather than silently passing, which is why it is
# started here rather than assumed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIMULATOR="${1:-iPhone 17}"
PORT="${PORT:-8788}"
DENO="$ROOT/server/node_modules/.bin/deno"
GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; OFF=$'\033[0m'

if [ ! -x "$DENO" ] && ! command -v deno >/dev/null 2>&1; then
  printf '%sDeno is missing. Run `cd server && npm install`.%s\n' "$RED" "$OFF"
  exit 2
fi
[ -x "$DENO" ] || DENO="$(command -v deno)"

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

# TEST_RUNNER_-prefixed settings reach the test process with the prefix stripped, which is how
# an environment variable gets past xcodebuild into the simulator.
xcodebuild test \
  -project "$ROOT/ios/BlindDrop.xcodeproj" \
  -scheme BlindDrop \
  -destination "platform=iOS Simulator,OS=latest,name=$SIMULATOR" \
  -derivedDataPath "$ROOT/ios/.build" \
  -only-testing:BlindDropUnitTests/FixtureSignInTests \
  TEST_RUNNER_BLINDDROP_FIXTURE_API="http://127.0.0.1:$PORT" \
  | grep -E '✔|✘|Test run|error:' || true

# xcodebuild's exit status is what decides, not the grep's.
if xcodebuild test-without-building \
  -project "$ROOT/ios/BlindDrop.xcodeproj" \
  -scheme BlindDrop \
  -destination "platform=iOS Simulator,OS=latest,name=$SIMULATOR" \
  -derivedDataPath "$ROOT/ios/.build" \
  -only-testing:BlindDropUnitTests/FixtureSignInTests \
  TEST_RUNNER_BLINDDROP_FIXTURE_API="http://127.0.0.1:$PORT" >/dev/null 2>&1
then
  printf '%sSign-in completes against the fixture server.%s\n' "$GREEN" "$OFF"
else
  printf '%sSign-in did not complete against the fixture server.%s\n' "$RED" "$OFF"
  exit 1
fi
