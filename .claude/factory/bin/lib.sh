#!/usr/bin/env bash
# Shared factory plumbing. Source this; do not execute it.
#
# The important subtlety: factory state (locks, logs, escalations) is gitignored,
# so it does NOT exist inside a worktree. Every script resolves the primary
# checkout and keeps state there, no matter where it is invoked from.

WORK_ROOT="$(git rev-parse --show-toplevel)"

_gcd="$(git rev-parse --git-common-dir)"
case "$_gcd" in /*) ;; *) _gcd="$WORK_ROOT/$_gcd";; esac
MAIN_ROOT="$(cd "$_gcd/.." && pwd)"

FACTORY="$MAIN_ROOT/.claude/factory"
# Always the primary checkout's scripts and state. A worktree carries a frozen
# copy of both from its branch point; trusting that copy means reading stale
# ledger records and running whatever gate existed when the branch was cut.
FACTORY_BIN="$FACTORY/bin"
STATE="$FACTORY/state"
CONFIG="$FACTORY/config.json"

# A worktree carries a frozen copy of these scripts from its branch point. A gate
# from before a gate fix is worse than no gate — the die() bug made verify.sh exit
# 0 on a failing test. So any script invoked from a worktree copy re-execs the
# primary checkout's version of itself, once.
if [ "${FACTORY_PRIMARY:-0}" != 1 ] && [ -n "${BASH_SOURCE[1]:-}" ]; then
  _caller_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
  _caller_name="$(basename "${BASH_SOURCE[1]}")"
  if [ "$_caller_dir" != "$FACTORY_BIN" ] && [ -x "$FACTORY_BIN/$_caller_name" ]; then
    export FACTORY_PRIMARY=1
    exec "$FACTORY_BIN/$_caller_name" "$@"
  fi
fi
export FACTORY_PRIMARY=1

cfg() { jq -r "$1" "$CONFIG"; }

say()  { printf '%s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; }
ok()   { printf 'ok    %s\n' "$*"; }

# Atomic lock via mkdir. Records pid and timestamp; reclaims a lock whose holder
# is dead or whose age exceeds the stale timeout.
lock_acquire() {
  local name="$1" wait_for="${2:-900}" stale="${3:-1800}" d waited=0 pid age
  d="$STATE/locks/$name.lock"
  mkdir -p "$STATE/locks"
  while ! mkdir "$d" 2>/dev/null; do
    pid="$(cat "$d/pid" 2>/dev/null || echo 0)"
    if [ "$pid" != 0 ] && ! kill -0 "$pid" 2>/dev/null; then
      say "reclaiming $name.lock from dead pid $pid"; rm -rf "$d"; continue
    fi
    age=$(( $(date +%s) - $(cat "$d/ts" 2>/dev/null || echo 0) ))
    if [ "$age" -gt "$stale" ]; then
      say "reclaiming $name.lock, held ${age}s (stale)"; rm -rf "$d"; continue
    fi
    sleep 2; waited=$((waited + 2))
    if [ "$waited" -ge "$wait_for" ]; then
      echo "timed out after ${waited}s waiting for $name.lock" >&2; return 1
    fi
  done
  echo $$ > "$d/pid"; date +%s > "$d/ts"
}

lock_release() { rm -rf "$STATE/locks/${1}.lock"; }
