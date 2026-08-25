#!/usr/bin/env bash
# The gate. One exit code. Fails fast, loudest stage first.
#
#   verify.sh [--task ID] [--attempt N] [--quick]
#
#   --quick   package tests + invariants only; skips the app build
#
# Notably needs NO simulator: the package suite runs on macOS, and the app is
# built for a generic iOS Simulator destination, which requires no booted
# device. Nothing here contends on simctl, so worktrees verify in parallel.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TASK=""; ATTEMPT=1; QUICK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK="$2"; shift 2;;
    --attempt) ATTEMPT="$2"; shift 2;;
    --quick) QUICK=1; shift;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done

LOG_DIR="$STATE/runs/${TASK:-adhoc}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/verify-${ATTEMPT}.log"
: > "$LOG"

started=$(date +%s)
stage() { printf '\n=== %s ===\n' "$1" | tee -a "$LOG"; }
# Always exits non-zero. Never derive the code from $? here: inside
# `if ! cmd; then die; fi` the status of `! cmd` is 0, which would report a
# failing gate as green — the one bug this whole system cannot tolerate.
die() {
  printf '\nGATE FAILED at: %s\n' "$1" | tee -a "$LOG"
  printf 'full log: %s\n' "$LOG"
  tail -25 "$LOG" | sed 's/^/  /'
  exit 1
}

say "verifying ${TASK:-working tree} in $WORK_ROOT (attempt $ATTEMPT)"
say "log: $LOG"

stage "package: build and test"
if ! swift test --package-path "$WORK_ROOT/Packages/SwiftReadability" >>"$LOG" 2>&1; then
  die "swift test"
fi
grep -E "Test run with .* passed|Executed .* tests" "$LOG" | tail -2 | sed 's/^/  /'

if [ "$QUICK" -eq 0 ]; then
  stage "project: generate"
  (cd "$WORK_ROOT" && xcodegen generate) >>"$LOG" 2>&1 || die "xcodegen"

  stage "app: build"
  # Discover the project rather than hardcoding its name: the app is being
  # renamed, and a gate that only builds a project called Stacks would fail the
  # moment the rename lands — in a task that is forbidden from editing the gate.
  XCPROJ="$(cd "$WORK_ROOT" && ls -d *.xcodeproj 2>/dev/null | head -1)"
  [ -n "$XCPROJ" ] || die "no .xcodeproj found in $WORK_ROOT"
  SCHEME="${XCPROJ%.xcodeproj}"
  echo "  project: $XCPROJ  scheme: $SCHEME" | tee -a "$LOG"
  if ! (cd "$WORK_ROOT" && xcodebuild \
        -project "$XCPROJ" -scheme "$SCHEME" \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$WORK_ROOT/$(cfg '.derived_data_dir')" \
        CODE_SIGNING_ALLOWED=NO build) >>"$LOG" 2>&1; then
    grep -E "error:" "$LOG" | sort -u | head -10 | sed 's/^/  /'
    die "xcodebuild"
  fi
  echo "  app + share extension built" | tee -a "$LOG"
fi

stage "invariants"
if ! "$FACTORY_BIN/invariants.sh" 2>&1 | tee -a "$LOG"; then
  die "invariants"
fi

printf '\nGATE PASSED in %ss\n' "$(( $(date +%s) - started ))" | tee -a "$LOG"
