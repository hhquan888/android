#!/usr/bin/env bash
# Install GApps (MindTheGapps) onto a running Redroid container via
# adb root + remount + push. Uses the GitHub API to fetch the latest
# release dynamically - never hardcode the download URL, since
# MindTheGapps filenames carry a timestamp that changes every release.
#
# Usage: install-gapps.sh <android_version>
#
# Notes:
# - This workflow is fixed to Android 12, so the only real path used is
#   the "12" -> "12.1.0-arm64" mapping below (verified against the real
#   MindTheGapps/12.1.0-arm64 GitHub repo).
# - Always uses the arm64 build regardless of host arch, because Redroid
#   is configured with libndk_translation to translate ARM binaries on
#   x86_64 hosts - this is the standard community approach and avoids
#   depending on per-version x86_64 GApps builds that don't consistently
#   exist.
# - This step needs root temporarily to remount /system, independent of
#   the workflow's "root" input (which only controls whether ADB stays
#   rooted afterward for the user's own session).

set -u
ANDROID_VER="${1:-}"

declare -A REPO_MAP=(
  [11]="11.0.0-arm64"
  [12]="12.1.0-arm64"
  [13]="13.0.0-arm64"
)

REPO="${REPO_MAP[$ANDROID_VER]:-}"

if [ -z "$REPO" ]; then
  echo "::warning::MindTheGapps has no build for Android ${ANDROID_VER}. Skipping GApps install."
  exit 0
fi

echo "Looking up latest release: MindTheGapps/${REPO}"
API_URL="https://api.github.com/repos/MindTheGapps/${REPO}/releases/latest"
RELEASE_JSON=$(curl -s -H "Accept: application/vnd.github+json" "$API_URL")

ZIP_URL=$(echo "$RELEASE_JSON" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    assets = data.get('assets', [])
    for a in assets:
        if a['name'].endswith('.zip'):
            print(a['browser_download_url'])
            break
except Exception:
    print('', file=sys.stderr)
")

if [ -z "$ZIP_URL" ]; then
  echo "::warning::No zip asset found in the latest MindTheGapps/${REPO} release."
  echo "::warning::Skipping GApps install, continuing workflow."
  exit 0
fi

echo "Downloading: $ZIP_URL"
curl -L "$ZIP_URL" -o mindthegapps.zip
if [ ! -s mindthegapps.zip ]; then
  echo "::warning::MindTheGapps download failed (empty file). Skipping GApps install."
  exit 0
fi

mkdir -p mindthegapps
unzip -o mindthegapps.zip -d mindthegapps >/dev/null

if [ ! -d mindthegapps/system ]; then
  echo "::warning::Unexpected zip layout (missing system/ folder). Skipping."
  exit 0
fi

echo "Enabling temporary root to install system-level GApps..."
adb -s localhost:5555 root
sleep 3
adb connect localhost:5555 || true
adb -s localhost:5555 wait-for-device

adb -s localhost:5555 remount
if [ $? -ne 0 ]; then
  echo "::warning::adb remount failed. Redroid may not allow direct /system writes."
  echo "::warning::Skipping system GApps install, continuing workflow."
  exit 0
fi

echo "Pushing GApps files to /system..."
adb -s localhost:5555 push mindthegapps/system /
adb -s localhost:5555 shell chmod -R 755 /system/product 2>/dev/null || true
adb -s localhost:5555 shell chmod -R 755 /system/system_ext 2>/dev/null || true

echo "Restarting Redroid container to apply changes..."
docker restart redroid
echo "Waiting for Redroid to reboot (60s)..."
sleep 60

adb connect localhost:5555 || true
for i in $(seq 1 24); do
  BOOTED=$(adb -s localhost:5555 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  if [ "$BOOTED" = "1" ]; then
    echo "Redroid finished rebooting after GApps install."
    break
  fi
  echo "Waiting for reboot... ($i/24)"
  sleep 10
done

if adb -s localhost:5555 shell pm list packages 2>/dev/null | grep -q "com.android.vending"; then
  echo "GApps installed successfully - Google Play Store is present."
else
  echo "::warning::GApps was installed but com.android.vending was not found. Check the log above."
fi
