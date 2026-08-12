#!/usr/bin/env bash
# ios/scripts/verify-signin.sh — E09-01.
#
# The epic's first verification line: "sign-in completes against the fixture server."
#
# Runs the real SupabaseAuthService, the real Keychain and the real APIClient through the whole
# path — exchange, store, GET /me, refresh, revoke — against ios/Fixtures/server.ts. Only
# Apple's sheet is stubbed.
#
#   ./ios/scripts/verify-signin.sh [simulator name]
#
# The machinery is verify-fixture.sh, which E09-03 uses too; this file is the name E09-01
# documents, kept because a task's verify line should stay runnable exactly as written.

set -euo pipefail

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-fixture.sh" \
  BlindDropUnitTests/FixtureSignInTests "Sign-in" "${1:-iPhone 17}"
