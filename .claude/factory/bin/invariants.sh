#!/usr/bin/env bash
# Mechanical constitution checks. No model judgement lives here.
#
#   invariants.sh [base-ref]
#
# Diff-scoped rules compare against the merge-base with main (or the ref given).
# Repo-scoped rules run over the whole tree. Exits 1 on any violation, printing
# the CONSTITUTION.md rule id for each.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAILURES=0
flag() { fail "$*"; FAILURES=$((FAILURES + 1)); }

BASE="${1:-}"
if [ -z "$BASE" ]; then
  BASE="$(git merge-base HEAD main 2>/dev/null || echo "")"
fi
CHANGED=""
if [ -n "$BASE" ] && [ "$(git rev-parse "$BASE")" != "$(git rev-parse HEAD)" ]; then
  CHANGED="$(git diff --name-only "$BASE"...HEAD)"
  say "diff scope: $BASE...HEAD ($(echo "$CHANGED" | grep -c .) files)"
else
  say "diff scope: none (at base) — repo-wide rules only"
fi
changed_swift() { echo "$CHANGED" | grep '\.swift$' || true; }

# --- P6: Dynamic Type. The count may only go down. -------------------------
count_sys() { # rev|WORKTREE
  if [ "$1" = WORKTREE ]; then
    git grep -h "system(size:" -- '*.swift' 2>/dev/null | grep -o "system(size:" | grep -c . || true
  else
    git grep -h "system(size:" "$1" -- '*.swift' 2>/dev/null | grep -o "system(size:" | grep -c . || true
  fi
}
if [ -n "$CHANGED" ]; then
  now=$(count_sys WORKTREE); before=$(count_sys "$BASE")
  if [ "$now" -gt "$before" ]; then
    flag "P6  .system(size:) call sites rose ${before} -> ${now}. Dynamic Type is the base."
  else
    ok "P6  .system(size:) ${before} -> ${now}"
  fi
fi

# --- P2: no third-party dependencies --------------------------------------
bad_imports="$(git grep -h "^\(@testable \)\?import " -- '*.swift' \
  | sed 's/@testable //' | awk '{print $2}' | sort -u \
  | grep -vxFf <(cfg '.invariant_baselines.allowed_imports[]') || true)"
if [ -n "$bad_imports" ]; then
  flag "P2  imports outside the Apple-framework allowlist: $(echo "$bad_imports" | tr '\n' ' ')"
else
  ok "P2  all imports on the allowlist"
fi
if git ls-files | grep -q 'Package.resolved'; then
  flag "P2  Package.resolved is tracked — the package graph must stay dependency-free"
elif git grep -q '\.package(url:' -- '*/Package.swift' 'Package.swift' 2>/dev/null; then
  flag "P2  a remote package dependency was declared"
else
  ok "P2  no external package dependencies"
fi

# --- P5: no guilt engines. Diff-scoped: the ban is on ADDING one. --------
# The sidebar's existing unreadCount predates this rule and is scheduled for
# removal by the Q2 "shed the queue" work. Failing on it repo-wide would block
# every task until then, so the gate holds the line rather than relitigating it.
hits=""
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if [ -n "$CHANGED" ]; then
    h="$(git diff "$BASE"...HEAD -- '*.swift' | grep -E "^\+.*\b${id}\b" || true)"
  else
    h=""
  fi
  [ -n "$h" ] && hits="$hits$h"$'\n'
done <<BANNED_EOF
$(cfg '.banned_identifiers[]')
BANNED_EOF
if [ -n "$hits" ]; then
  flag "P5  this diff adds a guilt-engine identifier:"; echo "$hits" | sed 's/^/        /' | head -5
else
  existing="$(git grep -nw unreadCount -- '*.swift' 2>/dev/null | grep -c . || true)"
  ok "P5  no guilt engine added (${existing} pre-existing unreadCount site(s), tracked as T-0017)"
fi

# --- X3: the factory's own state is off limits to worktree agents ----------
if [ -n "$CHANGED" ]; then
  touched="$(echo "$CHANGED" | grep -E '^\.claude/(factory|skills|agents)/' || true)"
  if [ -n "$touched" ] && [ "${ALLOW_FACTORY_EDITS:-0}" != 1 ]; then
    flag "X3  diff modifies factory state: $(echo "$touched" | tr '\n' ' ')"
  else
    ok "X3  factory state untouched"
  fi
fi

# --- X6: no build output or user state committed ---------------------------
# Any generated .xcodeproj, not one named for the app: the app is being renamed.
junk="$(git ls-files | grep -E '^(build|build-device)/|\.xcresult|xcuserdata|^\.dd/|\.build/|\.DS_Store|\.xcodeproj/' || true)"
if [ -n "$junk" ]; then
  flag "X6  build output or user state is tracked: $(echo "$junk" | head -3 | tr '\n' ' ')"
else
  ok "X6  no build output tracked"
fi

# --- X7: signing and identity are fixed ------------------------------------
# Two tiers, because they are not equally dangerous.
#
# DEVELOPMENT_TEAM is the signing identity. Changing it to make a build pass is
# forgery, and NOTHING unlocks it — not a task brief, not this flag.
#
# The bundle identifiers, app group and CloudKit container are product identity.
# They are normally frozen because changing one orphans a user's library, but a
# deliberate rename has to change them. ALLOW_IDENTITY_CHANGE=1 permits exactly
# that, still printing every changed line so the diff stays auditable. A prose
# exception in a task brief cannot be read by a grep — the exception has to be
# mechanical or the gate blocks the very change it was told to allow.
if [ -n "$CHANGED" ]; then
  team="$(git diff "$BASE"...HEAD -- project.yml '*.entitlements' \
    | grep -E '^[+-].*DEVELOPMENT_TEAM' || true)"
  ident="$(git diff "$BASE"...HEAD -- project.yml '*.entitlements' \
    | grep -E '^[+-].*(PRODUCT_BUNDLE_IDENTIFIER|group\.|iCloud\.)' || true)"
  if [ -n "$team" ]; then
    flag "X7  DEVELOPMENT_TEAM changed — never permitted:"; echo "$team" | sed 's/^/        /' | head -4
  elif [ -n "$ident" ] && [ "${ALLOW_IDENTITY_CHANGE:-0}" != 1 ]; then
    flag "X7  product identity changed without ALLOW_IDENTITY_CHANGE=1:"
    echo "$ident" | sed 's/^/        /' | head -6
  elif [ -n "$ident" ]; then
    ok "X7  product identity changed under explicit waiver ($(echo "$ident" | grep -c '^+') added lines); DEVELOPMENT_TEAM untouched"
    echo "$ident" | sed 's/^/        /' | head -8
  else
    ok "X7  signing and identity unchanged"
  fi
fi

# --- X8: the gate may not be weakened --------------------------------------
if [ -n "$CHANGED" ]; then
  # XCTSkip anywhere is always a skipped test. `.disabled(` is NOT: it is
  # swift-testing's trait in a test file, and SwiftUI's View.disabled(_:)
  # everywhere else — the app already has dozens of legitimate uses. Scoping the
  # trait check to test paths is what keeps this from flagging ordinary UI code.
  skips="$(git diff "$BASE"...HEAD -- '*.swift' | grep -E '^\+.*XCTSkip' || true)"
  test_skips="$(git diff "$BASE"...HEAD -- '*Tests/*.swift' '*Tests.swift' | grep -E '^\+.*\.disabled\(' || true)"
  skips="$skips$test_skips"
  if [ -n "$skips" ]; then
    flag "X8  tests disabled or skipped in this diff:"; echo "$skips" | sed 's/^/        /' | head -4
  else
    ok "X8  no tests skipped or disabled"
  fi
fi

echo
if [ "$FAILURES" -gt 0 ]; then
  echo "invariants: $FAILURES violation(s) — see CONSTITUTION.md"; exit 1
fi
echo "invariants: clean"
