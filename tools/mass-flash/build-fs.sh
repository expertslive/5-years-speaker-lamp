#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
WLED_DIR="$REPO_ROOT/wled"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing: $1" >&2
    echo "Install with: $2" >&2
    exit 1
  fi
}

require_cmd esptool "brew install esptool"
require_cmd jq "brew install jq"
require_cmd curl "already in macOS"
require_cmd python3 "already in macOS"

# WLED's on-ESP8266 LittleFS library is v2.0; brew mklittlefs writes v2.11.
# We build the filesystem image via littlefs-python with disk_version pinned to v2.0.
if ! python3 -c "import littlefs" >/dev/null 2>&1; then
  echo "Installing littlefs-python..." >&2
  python3 -m pip install --quiet littlefs-python
fi

mkdir -p "$BUILD_DIR"

echo "Dependencies OK."

WLED_VERSION="0.15.0"
FIRMWARE_URL="https://github.com/Aircoookie/WLED/releases/download/v${WLED_VERSION}/WLED_${WLED_VERSION}_ESP8266.bin"
FIRMWARE_BIN="$BUILD_DIR/WLED_${WLED_VERSION}_ESP8266.bin"

if [[ ! -f "$FIRMWARE_BIN" ]]; then
  echo "Downloading WLED $WLED_VERSION firmware..."
  curl -fL --retry 3 -o "$FIRMWARE_BIN" "$FIRMWARE_URL"
fi

ls -la "$FIRMWARE_BIN"

SOURCE_CFG="$WLED_DIR/wled_cfg_experts-live-5-years.json"
BAKED_CFG="$BUILD_DIR/cfg-baked.json"
BAKED_WSEC="$BUILD_DIR/wsec-baked.json"

: "${WLED_WIFI_PSK:?Set WLED_WIFI_PSK before running build-fs.sh}"
: "${WLED_AP_PSK:?Set WLED_AP_PSK before running build-fs.sh}"
: "${WLED_OTA_PASSWORD:?Set WLED_OTA_PASSWORD before running build-fs.sh}"
WLED_MQTT_PSK="${WLED_MQTT_PSK:-}"
WLED_HUE_KEY="${WLED_HUE_KEY:-}"

if [[ ! -f "$SOURCE_CFG" ]]; then
  echo "Missing source config: $SOURCE_CFG" >&2
  exit 1
fi

cp "$SOURCE_CFG" "$BAKED_CFG"

jq -n \
  --arg wifi_psk "$WLED_WIFI_PSK" \
  --arg ap_psk "$WLED_AP_PSK" \
  --arg mqtt_psk "$WLED_MQTT_PSK" \
  --arg hue_key "$WLED_HUE_KEY" \
  --arg ota_pwd "$WLED_OTA_PASSWORD" '{
  nw: { ins: [ { psk: $wifi_psk } ] },
  ap: { psk: $ap_psk },
  if: { mqtt: { psk: $mqtt_psk }, hue: { key: $hue_key } },
  pin: "",
  ota: { pwd: $ota_pwd, lock: false, "lock-wifi": false, aota: true }
}' > "$BAKED_WSEC"

echo "Wrote $BAKED_CFG and $BAKED_WSEC"

FS_STAGE="$BUILD_DIR/fs-stage"
LITTLEFS_BIN="$BUILD_DIR/littlefs.bin"

rm -rf "$FS_STAGE"
mkdir -p "$FS_STAGE"
cp "$BAKED_CFG"  "$FS_STAGE/cfg.json"
cp "$BAKED_WSEC" "$FS_STAGE/wsec.json"
cp "$WLED_DIR/wled_presets_experts-live-5-years.json" "$FS_STAGE/presets.json"
cp "$WLED_DIR/wled_ledmap.json" "$FS_STAGE/ledmap.json"

python3 - "$FS_STAGE" "$LITTLEFS_BIN" <<'PY'
import sys, os
from littlefs import LittleFS, UserContext

stage, out = sys.argv[1], sys.argv[2]

# WLED ESP8266 (Arduino core) LittleFS parameters:
# - block_size=8192, block_count=125  → 1,024,000 bytes at partition 0x300000
# - disk_version=2.0                   → matches WLED's on-device library
# - name_max=32                        → WLED's name_max; our v2.11 default of 255
#                                        would otherwise fail WLED's mount check
BLOCK_SIZE, BLOCK_COUNT = 8192, 125

ctx = UserContext(BLOCK_SIZE * BLOCK_COUNT)
fs = LittleFS(
    context=ctx,
    block_size=BLOCK_SIZE,
    block_count=BLOCK_COUNT,
    name_max=32,
    disk_version=0x00020000,
    mount=False,
)
fs.format()
fs.mount()

for fname in sorted(os.listdir(stage)):
    with open(os.path.join(stage, fname), 'rb') as r:
        data = r.read()
    with fs.open('/' + fname, 'wb') as w:
        w.write(data)
    print(f"  /{fname} ({len(data)} bytes)")

fs.unmount()
with open(out, 'wb') as f:
    f.write(bytes(ctx.buffer))
PY

echo "Wrote $LITTLEFS_BIN ($(stat -f%z "$LITTLEFS_BIN") bytes, LittleFS v2.0 format)"
