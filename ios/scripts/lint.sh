#!/usr/bin/env bash
# ios/scripts/lint.sh — E00-04.
#
# Grep-based rules, no SwiftLint dependency (docs/13 §1: zero third-party dependencies, and
# that includes the toolchain where it can be avoided). Each rule prints the offending
# file:line and the doc that says why.
#
#   ./ios/scripts/lint.sh              lint the tree
#   ./ios/scripts/lint.sh --self-test  prove each rule fires, using fixtures
#
# Comments are stripped before matching, so a rule can be discussed in a comment without
# tripping itself. String literals are not stripped — a banned word in a string is the point.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/ios/BlindDrop"
FAIL_FILE="$(mktemp)"
trap 'rm -f "$FAIL_FILE"' EXIT
RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'

# Print every match of $2 in the files listed on stdin, minus comment text.
# $1 = rule label, $2 = extended regex, $3 = doc reference
scan() {
  local label="$1" pattern="$2" doc="$3" file line n hit=0 matches
  matches="$(mktemp)"
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    : > "$matches"
    # Match one whole file at a time. The former line-by-line loop spawned grep and sed for
    # every source line, turning this small linter into a multi-minute CI step.
    sed -E -e 's,//.*$,,' -e 's,/\*.*$,,' "$file" | grep -nE "$pattern" > "$matches" || true
    while IFS=: read -r n _; do
      [ -n "$n" ] || continue
      line="$(sed -n "${n}p" "$file")"
      printf '%s%s:%d%s  %s\n' "$RED" "${file#"$ROOT"/}" "$n" "$OFF" \
        "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
        hit=1
    done < "$matches"
  done
  rm -f "$matches"
  if [ "$hit" = 1 ]; then
    printf '  %s%s — %s%s\n\n' "$DIM" "$label" "$doc" "$OFF"
    printf '%s\n' "$label" >> "$FAIL_FILE"
  fi
  return 0
}

swift_files() { [ -d "$1" ] && find "$1" -name '*.swift' -type f | sort || true; }

# Returns non-zero if any rule fired.
lint_tree() {
  local base="${1:-$APP}"
  : > "$FAIL_FILE"

  # 1 — Date() outside ServerClock. docs/13 §5: not in a view, not in a store, not in a
  #     formatter, not in a log. The device clock is not a source of truth.
  swift_files "$base" | grep -v 'Core/Time/ServerClock.swift$' \
    | scan "Date() outside ServerClock" '\bDate\(\)' 'docs/13 §5, AC-2'

  # 2 — design literals in Features/. docs/07: a raw hex, font size, or spacing number
  #     inside Features/ is a review failure. Pull from DesignSystem.
  swift_files "$base/Features" \
    | scan "raw hex colour in Features/" '(0x[0-9A-Fa-f]{6}|#colorLiteral|Color\(red:)' 'docs/07 §2'
  swift_files "$base/Features" \
    | scan "hardcoded font size in Features/" '\.font\(\.system\(size:' 'docs/07 §3'
  swift_files "$base/Features" \
    | scan "bare numeric spacing in Features/" '\.(padding|cornerRadius)\([0-9]|(spacing|width|height|lineWidth): *[0-9]' 'docs/07 §4'

  # 3 — inline copy. docs/11: every user-facing string is in Localizable.strings. What a
  #     screen may pass to Text(_:) is a *key* — DesignSystem/Copy.swift: "screens … write
  #     Text("some.key") and let SwiftUI resolve the LocalizedStringKey" — and a key is
  #     dotted and has no spaces. So the rule fires on a literal with a space in it, or on
  #     one with no dot at all. Both of those are prose; neither is a key.
  swift_files "$base/Features" \
    | scan "string literal in Text(_:)" 'Text\("([^".]*"|[^"]*[[:space:]][^"]*")' 'docs/11'

  # 4 — light mode only. docs/07: no colorScheme branching anywhere.
  { swift_files "$base/Features"; swift_files "$base/DesignSystem"; } \
    | scan "dark-mode branch" '(colorScheme|ColorScheme|\.dark\b)' 'docs/07, CLAUDE.md §2.4'

  # 5 — concurrency. docs/13 §6: no escapes from Swift 6 strict concurrency.
  swift_files "$base" \
    | scan "@unchecked Sendable" '@unchecked +Sendable' 'docs/13 §6, §9'

  # 6 — the client never decides a phase. docs/13 §2: there is exactly one place
  #     RoundDTO.state is assigned, and it is the decoder.
  swift_files "$base/Features" \
    | scan "round state assigned in a feature" '\.state *= *\.(open|revealed|scored|voided)' 'docs/13 §2, CLAUDE.md §2.2'

  # 9 — the refresh token's home. docs/14 §5: refresh tokens live in the Keychain,
  #     "never UserDefaults, never a file". Scoped to Core/Auth because that is the only
  #     directory that holds a credential; App/ reads UserDefaults for launch arguments.
  swift_files "$base/Core/Auth" \
    | scan "credential outside the Keychain" '(UserDefaults|FileManager|NSKeyedArchiver|\.write\(to:)' 'docs/14 §5'

  lint_strings "$base/Resources/Localizable.strings"

  [ ! -s "$FAIL_FILE" ]
}

# 7, 8 — voice rules on the copy deck (docs/11).
lint_strings() {
  local f="$1"
  if [ ! -f "$f" ]; then
    printf '%s· Localizable.strings not present yet — copy rules idle until E09.%s\n' "$DIM" "$OFF"
    return 0
  fi

  local n=0 line value hit_bang=0 hit_word=0
  # docs/11: "no exclamation marks. Anywhere."
  # Words we don't use, verbatim from docs/11's voice section.
  local banned='submit|post|share your vibe|awesome|oops|whoops|congrats|streak|level up|don.t miss out|hurry'
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in \/\/*|"") continue;; esac
    value="$(printf '%s' "$line" | sed -n 's/^[^=]*= *"\(.*\)" *;.*$/\1/p')"
    [ -z "$value" ] && continue
    if printf '%s' "$value" | grep -q '!'; then
      printf '%s%s:%d%s  %s\n' "$RED" "${f#"$ROOT"/}" "$n" "$OFF" "$value"
      hit_bang=1
    fi
    if printf '%s' "$value" | grep -Eqi "\\b($banned)\\b"; then
      printf '%s%s:%d%s  %s\n' "$RED" "${f#"$ROOT"/}" "$n" "$OFF" "$value"
      hit_word=1
    fi
  done < "$f"
  if [ "$hit_bang" = 1 ]; then
    printf '  %sexclamation mark in copy — the app never cheers (docs/11 voice)%s\n\n' "$DIM" "$OFF"
    printf 'exclamation mark\n' >> "$FAIL_FILE"
  fi
  if [ "$hit_word" = 1 ]; then
    printf '  %sbanned word in copy — docs/11 voice: "Drop a song → Seal it → Sealed"%s\n\n' "$DIM" "$OFF"
    printf 'banned word\n' >> "$FAIL_FILE"
  fi
  return 0
}

# ─── self-test ───────────────────────────────────────────────────────────────
# Each rule is given something it must catch, and a clean tree it must pass. A lint script
# nobody has seen fail is a lint script that does not work.
self_test() {
  SELF_TEST_TMP="$(mktemp -d)"
  trap 'rm -rf "$SELF_TEST_TMP"; rm -f "$FAIL_FILE"' EXIT
  local tmp="$SELF_TEST_TMP"
  mkdir -p "$tmp/Features" "$tmp/DesignSystem" "$tmp/Core/Time" "$tmp/Core/Auth" "$tmp/Resources"
  local passed=0 failed=0

  expect_catch() { # $1 = name, $2 = file path under tmp, $3 = contents
    printf '%s' "$3" > "$tmp/$2"
    if ! lint_tree "$tmp" >/dev/null 2>&1; then
      printf '%s  ok%s   catches %s\n' "$GREEN" "$OFF" "$1"; passed=$((passed + 1))
    else
      printf '%snot ok%s catches %s\n' "$RED" "$OFF" "$1"; failed=$((failed + 1))
    fi
    rm -f "$tmp/$2"
  }

  expect_catch "Date() in a store"            "Features/S.swift" 'let t = Date()
'
  expect_catch "a raw hex in Features/"       "Features/S.swift" 'let c = Color(hex: 0xF3F4F7)
'
  expect_catch "a hardcoded font size"        "Features/S.swift" 'Text(x).font(.system(size: 17))
'
  expect_catch "bare numeric padding"         "Features/S.swift" 'v.padding(20)
'
  expect_catch "a string literal in Text"     "Features/S.swift" 'Text("Drop a song")
'
  expect_catch "a one-word literal in Text"   "Features/S.swift" 'Text("Sealed")
'
  expect_catch "a colorScheme branch"         "Features/S.swift" 'if colorScheme == .dark { }
'
  expect_catch "a colorScheme branch in DS"   "DesignSystem/P.swift" 'let x: ColorScheme = .light
'
  expect_catch "@unchecked Sendable"          "Core/C.swift" 'final class X: @unchecked Sendable {}
'
  expect_catch "a phase assigned client-side" "Features/S.swift" 'round.state = .revealed
'
  expect_catch "a token in UserDefaults"      "Core/Auth/S.swift" 'UserDefaults.standard.set(token, forKey: "refresh")
'
  expect_catch "an exclamation mark in copy"  "Resources/Localizable.strings" '"a.b" = "Sealed!";
'
  expect_catch "a banned word in copy"        "Resources/Localizable.strings" '"a.b" = "Submit your song";
'

  # And the things that must NOT fire.
  printf 'let now = Date()\n' > "$tmp/Core/Time/ServerClock.swift"
  cat > "$tmp/Features/Clean.swift" <<'EOF'
// Date() is fine to mention in a comment, and .padding(20) too.
struct SubmitScreen: View {
    var body: some View {
        Text("submit.headline")
            .padding(Space.xl)
            .foregroundStyle(Palette.ink)
        Text(verbatim: title)
            .accessibilityLabel(Text("a11y.sealed"))
    }
}
EOF
  cat > "$tmp/Resources/Localizable.strings" <<'EOF'
"submit.action" = "Drop a song";
"confirm.action" = "Seal it";
"sealed.status" = "Sealed until %@.";
EOF
  local out; out="$(lint_tree "$tmp" 2>&1)"; local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s  ok%s   passes a clean tree (a dotted key in Text(_:) is not copy)\n' "$GREEN" "$OFF"
    passed=$((passed + 1))
  else
    printf '%snot ok%s passes a clean tree\n%s\n' "$RED" "$OFF" "$out"; failed=$((failed + 1))
  fi

  printf '\n%d passed, %d failed\n' "$passed" "$failed"
  [ "$failed" -eq 0 ]
}

# ─── main ────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--self-test" ]; then
  self_test; exit $?
fi

printf 'Linting %s\n\n' "${APP#"$ROOT"/}"
if ! lint_tree "$APP"; then
  printf '%s%d lint rule(s) violated.%s\n' "$RED" "$(wc -l < "$FAIL_FILE" | tr -d ' ')" "$OFF"
  exit 1
fi
printf '%sClean.%s\n' "$GREEN" "$OFF"
