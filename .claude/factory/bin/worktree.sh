#!/usr/bin/env bash
# Worktree lifecycle for factory tasks. One worktree per in-flight task, each
# with its own DerivedData, because the .xcodeproj is generated per checkout.
#
#   worktree.sh create <task-id> <branch>   create from current main
#   worktree.sh path <task-id>              print its path
#   worktree.sh list                        all factory worktrees
#   worktree.sh destroy <task-id> [--force] remove worktree + DerivedData
#   worktree.sh prune                       clean up stale git metadata
set -euo pipefail

FACTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(git -C "$FACTORY" rev-parse --show-toplevel)"
RAW="$(jq -r '.worktree_root' "$FACTORY/config.json")"
case "$RAW" in /*) ROOT="$RAW";; *) ROOT="$REPO/$RAW";; esac
mkdir -p "$ROOT"; ROOT="$(cd "$ROOT" && pwd)"
DD="$(jq -r '.derived_data_dir' "$FACTORY/config.json")"

wt_path() { echo "$ROOT/$1"; }

case "${1:-}" in
  create)
    id="${2:?task id required}"; branch="${3:?branch required}"
    p="$(wt_path "$id")"
    [ -e "$p" ] && { echo "worktree already exists: $p" >&2; exit 1; }
    mkdir -p "$ROOT"
    git -C "$REPO" fetch --quiet origin main 2>/dev/null || true
    git -C "$REPO" worktree add -b "$branch" "$p" main >&2
    mkdir -p "$p/$DD"
    echo "$p"
    ;;
  path)
    p="$(wt_path "${2:?task id required}")"
    [ -d "$p" ] || { echo "no worktree for ${2}" >&2; exit 1; }
    echo "$p"
    ;;
  list)
    git -C "$REPO" worktree list | grep -v "^$REPO " || echo "(none)"
    ;;
  destroy)
    id="${2:?task id required}"; p="$(wt_path "$id")"
    [ -d "$p" ] || { echo "no worktree for $id"; exit 0; }
    if [ "${3:-}" != "--force" ] && [ -n "$(git -C "$p" status --porcelain)" ]; then
      echo "worktree $id has uncommitted changes; refusing. Use --force to discard." >&2
      exit 1
    fi
    rm -rf "${p:?}/$DD"
    git -C "$REPO" worktree remove --force "$p"
    echo "destroyed $id"
    ;;
  prune)
    git -C "$REPO" worktree prune -v
    ;;
  *) sed -n '2,10p' "$0"; exit 1;;
esac
