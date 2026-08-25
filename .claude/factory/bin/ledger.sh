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
def norm: sub("/\\*\\*$";"") | sub("/\\*$";"") | sub("/+$";"");
def ov($a; $b): (($a|norm)+"/") as $x | (($b|norm)+"/") as $y
  | ($x|startswith($y)) or ($y|startswith($x));
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
