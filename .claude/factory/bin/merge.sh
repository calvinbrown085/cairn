#!/usr/bin/env bash
# Lands one task on main. Serialized.
#
#   merge.sh <task-id>
#
# Run ONLY when the overseer instructs it. This script is the mechanism, not the
# authority: it does not decide whether the work is ready, it makes landing safe
# once someone has decided. Holds the merge lock, rebases onto main, RE-RUNS the
# gate (a rebase produces code no gate has seen), then squash-merges.
#
# A failed post-rebase gate is not routed around: the task goes back to its
# implementer.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ID="${1:?task id required}"
LEDGER="$FACTORY_BIN/ledger.sh"
BRANCH="$("$LEDGER" get "$ID" | jq -r '.branch // empty')"
TITLE="$("$LEDGER" get "$ID" | jq -r '.title')"
TYPE="$("$LEDGER" get "$ID" | jq -r '.type')"
[ -n "$BRANCH" ] || { echo "$ID has no branch recorded" >&2; exit 2; }
WT="$("$FACTORY_BIN/worktree.sh" path "$ID")" || exit 2

cleanup() { lock_release merge; }
lock_acquire merge 900 1800 || exit 1
trap cleanup EXIT

say "merge queue: $ID ($BRANCH)"

git -C "$MAIN_ROOT" fetch --quiet origin main 2>/dev/null || true

say "rebasing onto main"
if ! git -C "$WT" rebase main >/dev/null 2>&1; then
  git -C "$WT" rebase --abort >/dev/null 2>&1 || true
  say "REBASE CONFLICT — human required, or return the task to its implementer"
  "$LEDGER" log "$ID" merge-failed "rebase conflict against main"
  exit 3
fi

say "re-verifying after rebase"
if ! (cd "$WT" && "$FACTORY_BIN/verify.sh" --task "$ID" --attempt rebase); then
  say "GATE FAILED after rebase — not merging"
  "$LEDGER" log "$ID" merge-failed "post-rebase gate failure"
  exit 4
fi

say "squash-merging into main"
# Ledger writes land on tracked files in the primary checkout, so orchestrator
# bookkeeping dirties it constantly. That is expected and is never part of the
# merge; anything else is a human's work in progress and must block.
dirty="$(git -C "$MAIN_ROOT" status --porcelain | cut -c4-)"
if [ -n "$dirty" ]; then
  outside="$(echo "$dirty" | grep -v '^\.claude/factory/' || true)"
  if [ -n "$outside" ]; then
    say "primary checkout has uncommitted work outside factory bookkeeping; refusing to merge:"
    echo "$outside" | sed 's/^/    /'
    exit 6
  fi
  say "committing factory bookkeeping first"
  git -C "$MAIN_ROOT" add .claude/factory >/dev/null 2>&1
  git -C "$MAIN_ROOT" commit --quiet -m "factory: ledger bookkeeping" \
    -m "Task state recorded by the orchestrator." >/dev/null 2>&1 || true
fi
git -C "$MAIN_ROOT" checkout --quiet main
git -C "$MAIN_ROOT" merge --squash "$BRANCH" >/dev/null 2>&1 || {
  say "squash merge failed"; git -C "$MAIN_ROOT" merge --abort 2>/dev/null || true; exit 6; }
git -C "$MAIN_ROOT" commit --quiet -m "$TYPE: $TITLE" -m "Task: $ID" \
  -m "Co-Authored-By: factory-implementer <noreply@anthropic.com>" || {
  say "nothing to commit"; exit 6; }

MERGED="$(git -C "$MAIN_ROOT" rev-parse --short HEAD)"
say "merged as $MERGED"
git -C "$MAIN_ROOT" push --quiet origin main 2>/dev/null && say "pushed" || say "push skipped or failed (merge stands locally)"

"$LEDGER" set "$ID" status '"merged"' >/dev/null
"$LEDGER" log "$ID" merged "$MERGED"
# Order matters: the branch is checked out in the worktree, so it cannot be
# deleted until the worktree is gone.
"$FACTORY_BIN/worktree.sh" destroy "$ID" --force >/dev/null 2>&1 || true
git -C "$MAIN_ROOT" branch -D "$BRANCH" >/dev/null 2>&1 || true
say "worktree destroyed; $ID complete"
