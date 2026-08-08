#!/usr/bin/env bash
# Cai GApps (MindTheGapps) vao Redroid dang chay, qua adb root + remount + push.
# Dung GitHub API de lay release moi nhat - khong hardcode URL vi file co timestamp
# thay doi moi lan MindTheGapps release ban moi.
#
# Usage: install-gapps.sh <android_version: 11|12|13>
#
# Ghi chu quan trong:
# - MindTheGapps khong co build cho Android 9/10. Goi script nay voi version
#   khac 11/12/13 se bi bo qua (khong fail job).
# - Luon dung build "arm64" bat ke host la amd64 hay arm64, vi Redroid da
#   cau hinh libndk_translation de dich binary ARM tren host x86_64. Day la
#   cach cong dong Redroid lam de tranh phai doi tim build x86_64 rieng
#   (khong phai version nao cung co ban x86_64).
# - Buoc nay CAN root tam thoi de remount /system, bat ke nguoi dung chon
#   root=0 hay 1 o input workflow - vi cai GApps he thong khong the lam
#   khac di. Neu root=0, day la lan remount duy nhat, khong anh huong toi
#   lua chon "khong giu root" cho phien lam viec cua nguoi dung sau do.

set -u
ANDROID_VER="${1:-}"

declare -A REPO_MAP=(
  [11]="11.0.0-arm64"
  [12]="12.1.0-arm64"
  [13]="13.0.0-arm64"
)

REPO="${REPO_MAP[$ANDROID_VER]:-}"

if [ -z "$REPO" ]; then
  echo "::warning::MindTheGapps khong co build cho Android ${ANDROID_VER}. Bo qua cai GApps."
  echo "::warning::GApps chi ho tro Android 11, 12, 13. Vao may se khong co Play Store."
  exit 0
fi

echo "Tra cuu release moi nhat: MindTheGapps/${REPO}"
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
except Exception as e:
    print('', file=sys.stderr)
")

if [ -z "$ZIP_URL" ]; then
  echo "::warning::Khong tim thay file zip trong release moi nhat cua MindTheGapps/${REPO}."
  echo "::warning::Bo qua cai GApps, tiep tuc workflow."
  exit 0
fi

echo "Tai: $ZIP_URL"
curl -L "$ZIP_URL" -o mindthegapps.zip
if [ ! -s mindthegapps.zip ]; then
  echo "::warning::Tai MindTheGapps that bai (file rong). Bo qua cai GApps."
  exit 0
fi

mkdir -p mindthegapps
unzip -o mindthegapps.zip -d mindthegapps >/dev/null

if [ ! -d mindthegapps/system ]; then
  echo "::warning::Cau truc zip khong nhu mong doi (thieu thu muc system/). Bo qua."
  exit 0
fi

echo "Bat root tam thoi de cai GApps he thong..."
adb -s localhost:5555 root
sleep 3
adb connect localhost:5555 || true
adb -s localhost:5555 wait-for-device

adb -s localhost:5555 remount
REMOUNT_STATUS=$?
if [ "$REMOUNT_STATUS" -ne 0 ]; then
  echo "::warning::adb remount that bai. Redroid co the khong cho phep ghi /system truc tiep."
  echo "::warning::Bo qua cai GApps he thong, tiep tuc workflow."
  exit 0
fi

echo "Day file GApps vao /system..."
adb -s localhost:5555 push mindthegapps/system /
adb -s localhost:5555 shell chmod -R 755 /system/product 2>/dev/null || true
adb -s localhost:5555 shell chmod -R 755 /system/system_ext 2>/dev/null || true

echo "Khoi dong lai container Redroid de ap dung thay doi..."
docker restart redroid
echo "Doi Redroid boot lai (60s)..."
sleep 60

adb connect localhost:5555 || true
for i in $(seq 1 24); do
  BOOTED=$(adb -s localhost:5555 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  if [ "$BOOTED" = "1" ]; then
    echo "Redroid da boot lai xong sau khi cai GApps."
    break
  fi
  echo "Doi boot lai... ($i/24)"
  sleep 10
done

if adb -s localhost:5555 shell pm list packages 2>/dev/null | grep -q "com.android.vending"; then
  echo "GApps cai thanh cong - Google Play Store da co."
else
  echo "::warning::Da cai GApps nhung khong thay com.android.vending. Kiem tra lai log o tren."
fi
