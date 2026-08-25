#!/usr/bin/env bash
# Is main green? Run at the head of every factory cycle. Nothing is dispatched
# onto a broken base.
#
#   main-health.sh [--force]
#
# Result is cached by main's SHA, so an unchanged main is not rebuilt every
# cycle. A dirty primary checkout is verified in a throwaway worktree so the
# answer is about main itself, not about whatever is in progress locally.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
SHA="$(git -C "$MAIN_ROOT" rev-parse main)"
CACHE="$STATE/health/$SHA.green"
mkdir -p "$STATE/health"

if [ "$FORCE" -eq 0 ] && [ -f "$CACHE" ]; then
  say "main ${SHA:0:7} green (cached $(cat "$CACHE"))"; exit 0
fi

dirty="$(git -C "$MAIN_ROOT" status --porcelain)"
head_sha="$(git -C "$MAIN_ROOT" rev-parse HEAD)"

if [ -z "$dirty" ] && [ "$head_sha" = "$SHA" ]; then
  say "verifying main ${SHA:0:7} in place"
  if "$FACTORY_BIN/verify.sh" --task main-health >/dev/null 2>&1; then
    date -u +%FT%TZ > "$CACHE"; say "main ${SHA:0:7} GREEN"; exit 0
  fi
  say "main ${SHA:0:7} RED — halt the factory"; exit 1
fi

say "primary checkout is dirty or detached; verifying main in a throwaway worktree"
tmp="$(mktemp -d)/main-health"
git -C "$MAIN_ROOT" worktree add --detach "$tmp" main >/dev/null 2>&1 || {
  say "could not create health worktree"; exit 1; }
if (cd "$tmp" && "$FACTORY_BIN/verify.sh" --task main-health) >/dev/null 2>&1; then
  result=0; say "main ${SHA:0:7} GREEN"; date -u +%FT%TZ > "$CACHE"
else
  result=1; say "main ${SHA:0:7} RED — halt the factory"
fi
git -C "$MAIN_ROOT" worktree remove --force "$tmp" >/dev/null 2>&1
exit $result
