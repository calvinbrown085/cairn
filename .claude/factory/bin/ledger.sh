#!/usr/bin/env bash
# Ledger queries and mutations. The orchestrator is the only caller that mutates.
#
#   ledger.sh summary               counts by status
#   ledger.sh list [status]         id/status/type/title, optionally filtered
#   ledger.sh get <id>              the raw task JSON
#   ledger.sh ready                 eligible, dispatchable type, all deps merged
#   ledger.sh inflight              in_progress | in_review | verifying
#   ledger.sh dispatchable          ready, minus anything whose touches overlap an in-flight task
#   ledger.sh set <id> <key> <json> e.g. set T-0011 status '"in_progress"'
#   ledger.sh log <id> <event> [detail]
#   ledger.sh validate              structural check of the whole ledger
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TASKS="$FACTORY/tasks"

all()   { jq -s '.' "$TASKS"/*.json; }
types() { jq -c '.dispatchable_types' "$CONFIG"; }

find_task() {
  local id="$1" hits
  hits=$(find "$TASKS" -maxdepth 1 -name "${id}-*.json" -o -maxdepth 1 -name "${id}.json" | head -2)
  [ -n "$hits" ] || { echo "no such task: $id" >&2; exit 1; }
  [ "$(echo "$hits" | wc -l)" -eq 1 ] || { echo "ambiguous task id: $id" >&2; exit 1; }
  echo "$hits"
}

# Two path patterns overlap when either is a prefix of the other at a path boundary.
JQ_OVERLAP='
# A bare "**" normalises to the empty string and must overlap EVERYTHING — it is
# how an exclusive task (the rename) declares a lease on the whole tree. Without
# the empty check it normalised to a prefix that matched nothing, so the task
# that conflicts with everything appeared to conflict with nothing.
def norm: sub("^\\*\\*$";"") | sub("/\\*\\*$";"") | sub("/\\*$";"") | sub("/+$";"");
def ov($a; $b): ($a|norm) as $x | ($b|norm) as $y
  | if ($x == "") or ($y == "") then true
    else (($x+"/")|startswith($y+"/")) or (($y+"/")|startswith($x+"/")) end;
'

ROW='"\(.id)  \(.status | . + "            "[0:12-length])  \(.type | . + "         "[0:9-length])  \(.title)"'

cmd="${1:-summary}"; shift || true
case "$cmd" in
  summary)
    all | jq -r 'group_by(.status) | map("\(.[0].status): \(length)") | join("   ")'
    ;;
  list)
    if [ $# -gt 0 ]; then all | jq -r --arg s "$1" "map(select(.status==\$s)) | sort_by(.id) | .[] | $ROW"
    else all | jq -r "sort_by(.id) | .[] | $ROW"; fi
    ;;
  get)
    jq '.' "$(find_task "$1")"
    ;;
  ready)
    all | jq --argjson types "$(types)" '
      . as $all
      | map(select(.factory_eligible == true))
      | map(select(.status == "todo" or .status == "ready"))
      | map(select(.type as $t | $types | index($t)))
      | map(select(
          [ .depends_on[]? as $d | (($all[] | select(.id == $d) | .status) // "MISSING") ]
          | all(. == "merged")))
      | sort_by(.id)'
    ;;
  inflight)
    all | jq 'map(select(.status | IN("in_progress","in_review","verifying"))) | sort_by(.id)'
    ;;
  dispatchable)
    ready=$("$0" ready); inflight=$("$0" inflight)
    jq -n --argjson ready "$ready" --argjson inflight "$inflight" "$JQ_OVERLAP"'
      [ $inflight[] | .touches[]? ] as $busy
      | $ready
      | map(select([ .touches[]? as $t | ($busy[] | ov($t; .)) ] | any | not))'
    ;;
  set)
    f=$(find_task "$1")
    tmp=$(mktemp); jq --arg k "$2" --argjson v "$3" '.[$k] = $v' "$f" > "$tmp" && mv "$tmp" "$f"
    echo "$1: $2 = $3"
    ;;
  log)
    f=$(find_task "$1")
    tmp=$(mktemp)
    jq --arg ts "$(date -u +%FT%TZ)" --arg e "$2" --arg d "${3:-}" \
       '.history += [{ts: $ts, event: $e, detail: $d}]' "$f" > "$tmp" && mv "$tmp" "$f"
    ;;
  drift)
    # A task's `touches` is its lease on the tree, and selection trusts it. If an
    # agent edits files the lease does not cover, two things are wrong at once:
    # the reviewer's X1 check has the wrong yardstick, and another task can be
    # dispatched onto the same files. T-0006 ran a whole attempt on stale globs.
    #
    # Note `set -f`: without it, `for g in $globs` pathname-expands the lease
    # patterns against the CURRENT directory, so "Stacks/Services/**" silently
    # becomes a list of existing files and is never matched as a pattern.
    fail=0
    set -f
    for id in $("$0" inflight | jq -r '.[].id' || true); do
      raw="$(jq -r '.worktree_root' "$CONFIG")"
      case "$raw" in /*) root="$raw";; *) root="$MAIN_ROOT/$raw";; esac
      p="$root/$id"
      [ -d "$p" ] || continue
      changed="$( { git -C "$p" diff --name-only main...HEAD 2>/dev/null || true; git -C "$p" status --porcelain 2>/dev/null | cut -c4- || true; } | sort -u | grep -v '^$' || true )"
      [ -n "$changed" ] || continue
      globs="$("$0" get "$id" | jq -r '.touches[]?' || true)"
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        # Ask git what is ignored rather than keeping a hardcoded list here —
        # build artefacts change names (.dd, .dd-signed, .dd-screenshots) and a
        # stale list makes the check cry wolf about output nobody tracks.
        git -C "$p" check-ignore -q "$f" 2>/dev/null && continue
        case "$f" in *.xcodeproj/*|*.xcuserstate) continue;; esac
        covered=0
        while IFS= read -r g; do
          [ -n "$g" ] || continue
          base="${g%/\*\*}"; base="${base%/\*}"
          [ "$g" = "**" ] && { covered=1; break; }
          case "$f" in $base|$base/*) covered=1; break;; esac
        done <<GLOBS_EOF
$globs
GLOBS_EOF
        [ "$covered" -eq 1 ] || { echo "$id: OUTSIDE touches -> $f"; fail=1; }
      done <<CHANGED_EOF
$changed
CHANGED_EOF
    done
    set +f
    [ $fail -eq 0 ] && echo "no drift: every in-flight change is inside its declared touches"
    exit $fail
    ;;
  validate)
    fail=0
    for f in "$TASKS"/*.json; do
      jq empty "$f" 2>/dev/null || { echo "INVALID JSON: $f"; fail=1; continue; }
      for k in id title type status depends_on acceptance touches factory_eligible; do
        jq -e "has(\"$k\")" "$f" >/dev/null || { echo "MISSING $k: $f"; fail=1; }
      done
    done
    dupes=$(all | jq -r 'group_by(.id) | map(select(length>1) | .[0].id) | .[]')
    [ -z "$dupes" ] || { echo "DUPLICATE IDS: $dupes"; fail=1; }
    missing=$(all | jq -r '. as $a | [.[] | .id as $i | .depends_on[]? | select(. as $d | ($a|map(.id)|index($d))|not) | "\($i) -> \(.)"] | .[]')
    [ -z "$missing" ] || { echo "UNRESOLVED DEPS: $missing"; fail=1; }
    badtype=$(all | jq -r '.[] | select(.type | IN("implement","chore","debt","decide","spike")|not) | "\(.id): \(.type)"')
    [ -z "$badtype" ] || { echo "BAD TYPE: $badtype"; fail=1; }
    [ $fail -eq 0 ] && echo "ledger valid: $(all | jq 'length') tasks"
    exit $fail
    ;;
  *) sed -n '2,14p' "$0"; exit 1;;
esac
