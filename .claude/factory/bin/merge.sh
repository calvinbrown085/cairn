#!/usr/bin/env bash
# Serialized merge queue for one task.
#
#   merge.sh <task-id>
#
# Holds the merge lock, rebases onto main, RE-RUNS the gate (the rebase produces
# code no gate has seen), then squash-merges — or opens a PR when auto_merge is
# false. A failed post-rebase gate is not routed around: the task goes back to
# its implementer.
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

if [ "$(cfg '.auto_merge')" != "true" ]; then
  say "auto_merge is off — pushing branch and opening a PR"
  git -C "$WT" push -u origin "$BRANCH" >/dev/null 2>&1 || { say "push failed"; exit 5; }
  body="$(printf 'Task: %s\n\n%s\n\n---\nGate: verify.sh passed after rebase onto main.\nReview: see .claude/factory/state/runs/%s/\n' "$ID" "$TITLE" "$ID")"
  gh pr create --title "$TYPE: $TITLE" --body "$body" --head "$BRANCH" --base main \
    || { say "gh pr create failed"; exit 5; }
  "$LEDGER" set "$ID" status '"in_review"' >/dev/null
  "$LEDGER" log "$ID" pr-opened "auto_merge off; awaiting human merge"
  say "PR opened. Task left in_review."
  exit 0
fi

say "squash-merging into main"
[ -z "$(git -C "$MAIN_ROOT" status --porcelain)" ] || {
  say "primary checkout is dirty; refusing to merge"; exit 6; }
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
git -C "$MAIN_ROOT" branch -D "$BRANCH" >/dev/null 2>&1 || true
"$FACTORY_BIN/worktree.sh" destroy "$ID" --force >/dev/null 2>&1 || true
say "worktree destroyed; $ID complete"
