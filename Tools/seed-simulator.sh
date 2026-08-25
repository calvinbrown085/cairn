#!/bin/bash
# Re-seeds a simulator's Stacks archive through the real share-inbox path.
# Usage: Tools/seed-simulator.sh "<device name>" [url ...]
set -e
DEVICE="${1:?device name required}"; shift
BUNDLE=com.calvinbrown.Stacks

G=$(xcrun simctl get_app_container "$DEVICE" $BUNDLE groups 2>/dev/null | awk '{print $2}')
[ -n "$G" ] || { echo "app not installed on $DEVICE"; exit 1; }

xcrun simctl terminate "$DEVICE" $BUNDLE 2>/dev/null || true
rm -f "$G"/Stacks.store*; rm -rf "$G"/.Stacks_SUPPORT; mkdir -p "$G/Inbox"

i=0
for u in "$@"; do
  i=$((i+1))
  python3 -c "
import sys, json, time, uuid
g, url, i = sys.argv[1], sys.argv[2], int(sys.argv[3])
uid = str(uuid.uuid4()); ts = time.time() + i
json.dump({'id': uid, 'url': url, 'receivedAt': ts - 978307200},
          open(f'{g}/Inbox/{ts}-{uid}.json', 'w'))
" "$G" "$u" "$i"
done

xcrun simctl launch "$DEVICE" $BUNDLE >/dev/null
sleep "${SEED_WAIT:-30}"
xcrun simctl terminate "$DEVICE" $BUNDLE 2>/dev/null || true
echo "seeded $i url(s); $(ls "$G/Inbox" 2>/dev/null | wc -l | tr -d ' ') left in inbox"
