#!/bin/bash
# Produces the screenshots App Store Connect asks for, in one command:
#
#   Tools/screenshots.sh
#
# Runs `AppStoreScreenshotUITests` (CairnUITests/AppStoreScreenshotUITests.swift)
# on two simulators — one per required source size — and turns the
# `XCTAttachment` screenshots it captures into named PNGs under
# `screenshots/<device>/`. Before each run, `Tools/seed-simulator.sh` drops
# one real article into the app's share-extension inbox and lets the app
# drain it, so the library already has something to look at — nothing to set
# up by hand.
#
# That seeding path, not the in-app "Save a link" sheet, is deliberate: while
# building this script, saving a link through the sheet on a genuinely empty
# library was found to race `RootView`'s own selection state and land back
# on the library, or its sidebar, instead of the reader — reproducible with
# `LibraryNavigation.swift`'s existing `seedArchive` completely unmodified,
# so it is a pre-existing gap in that path rather than anything this task
# introduced, and out of this task's touches to fix. The inbox drain calls
# the same `ArchiveService.save`, but never opens the sheet or touches
# `selectedPost`, so there is nothing there to race.
#
# App Store Connect accepts 1242x2688 or 1284x2778 for iPhone. Verified by
# screenshotting each candidate rather than trusting a spec sheet: iPhone 14
# Plus gives exactly 1284x2778, iPhone 11 Pro Max gives 1242x2688. The 6.9-inch
# iPhone 17 Pro Max produces 1320x2868, which Connect rejects — and its aspect
# ratio differs (0.4603 vs 0.4622), so rescaling would distort rather than fit.
# Apple asks for an iPhone and a 13-inch iPad; every other
# size App Store Connect wants is derived from those two, so those are the
# only devices this runs. Concretely: iPhone 14 Plus (6.7", 1284x2778) and iPad Pro
# 13-inch M5 (13") — the current simulator models matching each size.
#
# *** Simulator isolation ***
# Two `xcodebuild test` runs sharing a *named* simulator kill each other
# outright — every test dies with `signal kill` (see T-0044/T-0045 history,
# and the shared named simulator other factory tasks lock in
# .claude/factory/config.json). So this script never selects a simulator by
# name: it creates two simulators of its own on first run (named distinctly
# from anything else in the shared device pool), remembers their UDIDs, and
# always targets `-destination id=<UDID>` from then on. Nothing here ever
# touches a simulator this script did not create itself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/screenshots"
WORK="$ROOT/.dd-screenshots"
RESULTS="$WORK/results"
TEST_ID="CairnUITests/AppStoreScreenshotUITests"
MAX_ATTEMPTS=3

# name | device type identifier | output slug (also the upload-facing label) | orientation
# `LibraryNavigation.launchIntoLibrary()` forces landscape on iPad only (the
# split view's sidebar is a real column there, not an overlay) — orientation
# here just says which devices that applies to, for the rotation fix below.
DEVICES=(
  "Cairn-Screenshots-iPhone-6.7|com.apple.CoreSimulator.SimDeviceType.iPhone-14-Plus|iphone-6.7|portrait"
  "Cairn-Screenshots-iPad-13|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB|ipad-13|landscape"
)
# The numbered attachment names `AppStoreScreenshotUITests` captures, in
# upload order. Kept here, not discovered, so a missing shot fails loudly
# instead of shipping a silently incomplete set.
SHOTS=(01-library 02-full-screen-article 03-highlighted-passage 04-search-snippet)

say() { printf '%s\n' "$*"; }
die() { printf 'FAILED: %s\n' "$*" >&2; exit 1; }

latest_ios_runtime() {
  xcrun simctl list runtimes available -j | /usr/bin/python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["runtimes"]
ios = [r for r in runtimes if r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS")]
if not ios:
    sys.exit("no available iOS simulator runtime")
ios.sort(key=lambda r: r["version"])
print(ios[-1]["identifier"])
'
}

# Prints the UDID of a simulator with this exact name, creating it against
# the given device type if it does not already exist. Reusing by name (just
# to find our own UDID, never to target xcodebuild) is what makes the script
# idempotent instead of growing a new simulator on every run.
udid_for() {
  local name="$1" devtype="$2"
  local found
  found="$(xcrun simctl list devices -j | /usr/bin/python3 -c "
import json, sys
data = json.load(sys.stdin)['devices']
name = sys.argv[1]
for devices in data.values():
    for d in devices:
        if d['name'] == name and d.get('isAvailable', True):
            print(d['udid'])
            sys.exit(0)
" "$name")"
  if [ -n "$found" ]; then
    echo "$found"
  else
    xcrun simctl create "$name" "$devtype" "$RUNTIME" >&2 || true
    xcrun simctl list devices -j | /usr/bin/python3 -c "
import json, sys
data = json.load(sys.stdin)['devices']
name = sys.argv[1]
for devices in data.values():
    for d in devices:
        if d['name'] == name:
            print(d['udid'])
            sys.exit(0)
sys.exit('could not find or create ' + name)
" "$name"
  fi
}

RUNTIME="$(latest_ios_runtime)"
say "runtime: $RUNTIME"

rm -rf "$OUT" "$RESULTS"
mkdir -p "$OUT" "$RESULTS"

say "project: generate"
(cd "$ROOT" && xcodegen generate) >"$WORK/xcodegen.log" 2>&1 || {
  cat "$WORK/xcodegen.log" >&2
  die "xcodegen generate"
}

XCPROJ="$(cd "$ROOT" && ls -d *.xcodeproj 2>/dev/null | head -1)"
[ -n "$XCPROJ" ] || die "no .xcodeproj found in $ROOT (xcodegen generate should have made one)"
SCHEME="${XCPROJ%.xcodeproj}"
say "project: $XCPROJ  scheme: $SCHEME"

for entry in "${DEVICES[@]}"; do
  IFS='|' read -r NAME DEVTYPE SLUG ORIENTATION <<< "$entry"
  say ""
  say "== $SLUG ($NAME) =="

  UDID="$(udid_for "$NAME" "$DEVTYPE")"
  say "udid: $UDID"

  # Boot only if needed. This simulator is kept warm across runs on purpose —
  # see the note above on why seeding happens through the inbox rather than
  # the sheet, and `seed-simulator.sh` below wipes Cairn's own local store
  # before reseeding, which is what actually makes each run a clean
  # regeneration rather than a build on top of last time's leftovers.
  BOOT_STATE="$(xcrun simctl list devices -j | /usr/bin/python3 -c "
import json, sys
data = json.load(sys.stdin)['devices']
udid = sys.argv[1]
for devices in data.values():
    for d in devices:
        if d['udid'] == udid:
            print(d['state']); sys.exit(0)
" "$UDID")"
  if [ "$BOOT_STATE" != "Booted" ]; then
    xcrun simctl boot "$UDID"
  fi
  xcrun simctl bootstatus "$UDID" -b >/dev/null

  RESULT_BUNDLE="$RESULTS/$SLUG.xcresult"
  LOG="$RESULTS/$SLUG.log"
  DEVICE_OUT="$OUT/$SLUG"
  rm -rf "$DEVICE_OUT"
  mkdir -p "$DEVICE_OUT"

  say "build: installing the app so it can be seeded before the UI test opens it…"
  BUILD_LOG="$RESULTS/$SLUG-build.log"
  if ! (cd "$ROOT" && xcodebuild build \
      -project "$XCPROJ" -scheme "$SCHEME" \
      -destination "id=$UDID" \
      -derivedDataPath "$WORK/DerivedData" \
      ) >"$BUILD_LOG" 2>&1; then
    tail -40 "$BUILD_LOG" >&2
    die "xcodebuild build for $SLUG — see $BUILD_LOG"
  fi
  APP_PATH="$WORK/DerivedData/Build/Products/Debug-iphonesimulator/Cairn.app"
  [ -d "$APP_PATH" ] || die "build did not produce $APP_PATH"
  xcrun simctl install "$UDID" "$APP_PATH"

  say "seeding one article through the share-extension inbox…"
  "$ROOT/Tools/seed-simulator.sh" "$UDID" "https://www.paulgraham.com/own.html" >>"$LOG" 2>&1 \
    || die "seed-simulator.sh for $SLUG — see $LOG"

  attempt=1
  while :; do
    say "xcodebuild test (attempt $attempt/$MAX_ATTEMPTS)…"
    rm -rf "$RESULT_BUNDLE"
    if (cd "$ROOT" && xcodebuild test \
        -project "$XCPROJ" -scheme "$SCHEME" \
        -destination "id=$UDID" \
        -derivedDataPath "$WORK/DerivedData" \
        -resultBundlePath "$RESULT_BUNDLE" \
        -only-testing:"$TEST_ID" \
        ) >"$LOG" 2>&1; then
      break
    fi
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
      grep -E "error:|Testing failed" "$LOG" | sort -u | tail -20 | sed 's/^/  /' >&2
      die "xcodebuild test for $SLUG did not pass after $MAX_ATTEMPTS attempts — see $LOG"
    fi
    attempt=$((attempt + 1))
  done

  EXPORT_DIR="$RESULTS/$SLUG-attachments"
  rm -rf "$EXPORT_DIR"
  xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" --output-path "$EXPORT_DIR" >/dev/null

  /usr/bin/python3 - "$EXPORT_DIR/manifest.json" "$EXPORT_DIR" "$DEVICE_OUT" "${SHOTS[@]}" <<'PY'
import json, shutil, sys, os

manifest_path, export_dir, device_out = sys.argv[1], sys.argv[2], sys.argv[3]
expected = sys.argv[4:]

with open(manifest_path) as f:
    manifest = json.load(f)

# xcresulttool renames every attachment on export to
# "<name we set>_<index>_<uuid>.<ext>" — even on a clean pass, not just for
# its own failure-diagnostic attachments — so this matches by prefix rather
# than the exact name `XCTAttachment.name` was given.
all_names = []
by_name = {}
for test in manifest:
    for attachment in test["attachments"]:
        human_name = attachment["suggestedHumanReadableName"]
        all_names.append(human_name)
        for name in expected:
            if human_name == name or human_name.startswith(name + "_"):
                by_name[name] = attachment["exportedFileName"]

missing = [name for name in expected if name not in by_name]
if missing:
    sys.exit(f"missing screenshots in test output: {missing} (found: {sorted(all_names)})")

for name in expected:
    src = os.path.join(export_dir, by_name[name])
    dst = os.path.join(device_out, f"{name}.png")
    shutil.copyfile(src, dst)
    print(f"  {dst}")
PY

  if [ "$ORIENTATION" = "landscape" ]; then
    # `XCUIScreen.main.screenshot()` on a landscape iPad captures the
    # sensor's native portrait pixel grid, not the rotated frame the app is
    # actually drawing into — so the file comes out portrait-shaped with the
    # UI sideways inside it. App Store Connect wants the landscape shape
    # this device is really being captured in, so rotate every shot back.
    for png in "$DEVICE_OUT"/*.png; do
      sips --rotate 270 "$png" >/dev/null
    done
  fi

  say "$SLUG: $(ls "$DEVICE_OUT" | wc -l | tr -d ' ') screenshots"
done

say ""
say "done: $(find "$OUT" -name '*.png' | wc -l | tr -d ' ') screenshots in $OUT"
