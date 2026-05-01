# WLED Mass-Flash Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a USB-only flashing workflow (`flash.sh`) that takes a blank ESP8266 to a fully configured WLED device in a single command, so multiple Experts Live speaker-lamp boards can be provisioned in one sitting.

**Architecture:** Two bash scripts in `tools/mass-flash/`. `build-fs.sh` runs once to download the WLED firmware binary, generate `wsec.json` from environment variables, and build a LittleFS image from the JSON files in `wled/`. `flash.sh` runs once per board: auto-detects the USB-serial port, runs `esptool write-flash` with firmware + filesystem, reads the board MAC, and discovers the DHCP IP via ARP. The device comes up fully configured on the target WLAN with the correct boot playlist and LED map — no web UI uploads or AP-switching.

**Tech Stack:** bash, `esptool` (Python), `littlefs-python`, `curl` (firmware download), `jq` (JSON transformations). macOS host.

**Test strategy:** Bash tooling does not warrant unit-test infrastructure for a one-shot event. Each task ends with a **verification step** — run the script (or a fragment), inspect the output, confirm expectations. Phase 2 of the spec (one-board end-to-end test with real hardware) is the integration test.

**Implementation outcome:** The final implementation uses `esptool`, `littlefs-python`, a 1,024,000-byte LittleFS image at `0x300000`, `wsec.json` generated from environment variables, and ARP/MAC IP discovery. The BG image cannot be baked because WLED 0.15 stores it in browser `localStorage`.

---

## Task 1: Scaffold folder + README skeleton + .gitignore

**Files:**
- Create: `tools/mass-flash/README.md`
- Create: `tools/mass-flash/.gitignore`
- Create: `tools/mass-flash/build/.gitkeep`

- [ ] **Step 1: Create folder structure**

```bash
mkdir -p tools/mass-flash/build
touch tools/mass-flash/build/.gitkeep
```

- [ ] **Step 2: Write `.gitignore` to exclude built artifacts**

`tools/mass-flash/.gitignore`:
```
build/*
!build/.gitkeep
```

- [ ] **Step 3: Write README skeleton**

`tools/mass-flash/README.md`:
```markdown
# WLED Mass-Flash Tool

Flashes multiple ESP8266 boards with WLED + Experts Live 5 Years config in one USB step per board.

## Prerequisites (one-time, macOS)

    brew install esptool jq

`littlefs-python` is installed on demand by `build-fs.sh` via `python3 -m pip`.

If your boards use a CH340 USB-serial chip (common on cheap clones), install the WCH driver from https://www.wch.cn/downloads/CH341SER_MAC_ZIP.html.

## Build (once)

    ./build-fs.sh

Downloads the WLED firmware and builds `build/littlefs.bin` with baked config.

## Flash a single board

    ./flash.sh

Plug in the ESP8266 via USB, run the command, wait ~45s, unplug.

## Flash in a loop (for multiple boards)

    ./flash.sh --loop

Script waits for each new USB-serial device, flashes it, prompts for the next.
```

- [ ] **Step 4: Verify structure**

```bash
ls -la tools/mass-flash/
```
Expected: `.gitignore`, `README.md`, `build/` directory present.

- [ ] **Step 5: Commit**

```bash
git add tools/mass-flash/
git commit -m "Scaffold tools/mass-flash/ folder and README"
```

---

## Task 2: Dependency-check preamble in build-fs.sh

**Files:**
- Create: `tools/mass-flash/build-fs.sh`

- [ ] **Step 1: Write dependency-check script**

`tools/mass-flash/build-fs.sh`:
```bash
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

mkdir -p "$BUILD_DIR"

echo "Dependencies OK."
```

- [ ] **Step 2: Make executable**

```bash
chmod +x tools/mass-flash/build-fs.sh
```

- [ ] **Step 3: Verify**

```bash
./tools/mass-flash/build-fs.sh
```
Expected: prints `Dependencies OK.` (install anything missing first).

- [ ] **Step 4: Commit**

```bash
git add tools/mass-flash/build-fs.sh
git commit -m "build-fs.sh: dependency preamble"
```

---

## Task 3: Firmware download in build-fs.sh

**Files:**
- Modify: `tools/mass-flash/build-fs.sh`

**Note on firmware source:** WLED's GitHub releases publish ESP8266 binaries at predictable URLs. The 0.15.0 ESP8266 release asset is `WLED_0.15.0_ESP8266.bin`. If WLED has published a newer 0.15.x stable, upgrade at the top of the script — there is no compelling reason to pin. Pin to a version this plan was tested with: **0.15.0**.

- [ ] **Step 1: Append firmware-download block**

Add to `tools/mass-flash/build-fs.sh` (after dependency checks):

```bash
WLED_VERSION="0.15.0"
FIRMWARE_URL="https://github.com/Aircoookie/WLED/releases/download/v${WLED_VERSION}/WLED_${WLED_VERSION}_ESP8266.bin"
FIRMWARE_BIN="$BUILD_DIR/WLED_${WLED_VERSION}_ESP8266.bin"

if [[ ! -f "$FIRMWARE_BIN" ]]; then
  echo "Downloading WLED $WLED_VERSION firmware..."
  curl -fL --retry 3 -o "$FIRMWARE_BIN" "$FIRMWARE_URL"
fi

ls -la "$FIRMWARE_BIN"
```

- [ ] **Step 2: Run**

```bash
./tools/mass-flash/build-fs.sh
```
Expected: downloads the `.bin` file, prints size. File should be between ~500KB and ~800KB (typical WLED ESP8266 binary).

- [ ] **Step 3: Verify it is a valid ESP8266 image**

```bash
esptool --chip esp8266 image-info tools/mass-flash/build/WLED_0.15.0_ESP8266.bin
```
Expected: output shows ESP8266 image header, segments, entry point — no parse errors.

- [ ] **Step 4: Commit**

```bash
git add tools/mass-flash/build-fs.sh
git commit -m "build-fs.sh: download and verify WLED ESP8266 firmware"
```

---

## Task 4: Generate wsec-baked.json from environment credentials

**Files:**
- Modify: `tools/mass-flash/build-fs.sh`

**Why this works:** WLED's config exporter replaces plaintext secrets with password-length fields to avoid leaking credentials. WLED reads plaintext values from `wsec.json`, so `build-fs.sh` generates that file from environment variables instead of storing secrets in Git.

- [ ] **Step 1: Append cfg/wsec generator**

Add to `tools/mass-flash/build-fs.sh`:

```bash
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
```

- [ ] **Step 2: Run**

```bash
./tools/mass-flash/build-fs.sh
```
Expected: `Wrote tools/mass-flash/build/cfg-baked.json and tools/mass-flash/build/wsec-baked.json`.

- [ ] **Step 3: Verify transformation**

```bash
jq '.nw.ins[0] | has("psk")' tools/mass-flash/build/wsec-baked.json
```
Expected: `true`. Do not print the credential value.

```bash
jq '.nw.ins[0] | has("pskl")' tools/mass-flash/build/cfg-baked.json
```
Expected: `false`.

- [ ] **Step 4: Commit**

```bash
git add tools/mass-flash/build-fs.sh
git commit -m "build-fs.sh: generate wsec from env credentials"
```

---

## Task 5: Build LittleFS image

**Files:**
- Modify: `tools/mass-flash/build-fs.sh`

**LittleFS sizing rationale:** WLED ESP8266 stock builds using the 4m1m layout reserve a **1,024,000 byte** LittleFS partition starting at flash offset `0x300000`. WLED 0.15 on ESP8266 uses LittleFS v2.0 with `name_max=32`, so the image is built with `littlefs-python` rather than `brew mklittlefs`.

- [ ] **Step 1: Append LittleFS build block**

Add to `tools/mass-flash/build-fs.sh`:

```bash
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

echo "Wrote $LITTLEFS_BIN ($(stat -f%z "$LITTLEFS_BIN") bytes)"
```

- [ ] **Step 2: Run**

```bash
./tools/mass-flash/build-fs.sh
```
Expected: prints size of `littlefs.bin`. File size should equal `1024000` bytes.

- [ ] **Step 3: Verify contents**

```bash
python3 - <<'PY'
from littlefs import LittleFS, UserContext
with open('tools/mass-flash/build/littlefs.bin', 'rb') as f:
    ctx = UserContext(bytearray(f.read()))
fs = LittleFS(context=ctx, block_size=8192, block_count=125, name_max=32, disk_version=0x00020000)
print(fs.listdir('/'))
PY
```
Expected: lists `cfg.json`, `wsec.json`, `presets.json`, `ledmap.json` with non-zero sizes.

- [ ] **Step 4: Commit**

```bash
git add tools/mass-flash/build-fs.sh
git commit -m "build-fs.sh: build LittleFS image from wled/ configs"
```

---

## Task 6: flash.sh port auto-detection

**Files:**
- Create: `tools/mass-flash/flash.sh`

- [ ] **Step 1: Write flash.sh with port detection**

`tools/mass-flash/flash.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
FIRMWARE_BIN="$BUILD_DIR/WLED_0.15.0_ESP8266.bin"
LITTLEFS_BIN="$BUILD_DIR/littlefs.bin"
LITTLEFS_OFFSET=0x300000

if [[ ! -f "$FIRMWARE_BIN" || ! -f "$LITTLEFS_BIN" ]]; then
  echo "Build artifacts missing. Run ./build-fs.sh first." >&2
  exit 1
fi

detect_port() {
  # CP210x on macOS appears as /dev/cu.usbserial-*, CH340 as /dev/cu.wchusbserial-*
  local matches=()
  for p in /dev/cu.usbserial-* /dev/cu.wchusbserial-* /dev/cu.SLAB_USBtoUART; do
    [[ -e "$p" ]] && matches+=("$p")
  done
  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "No USB-serial device found. Plug in an ESP8266 and retry." >&2
    exit 1
  fi
  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "Multiple USB-serial devices found:" >&2
    printf '  %s\n' "${matches[@]}" >&2
    echo "Disconnect all but one and retry." >&2
    exit 1
  fi
  echo "${matches[0]}"
}

PORT="$(detect_port)"
echo "Detected port: $PORT"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x tools/mass-flash/flash.sh
```

- [ ] **Step 3: Verify (no board plugged in)**

```bash
./tools/mass-flash/flash.sh
```
Expected: `No USB-serial device found. Plug in an ESP8266 and retry.` and exit code 1.

- [ ] **Step 4: Verify (one board plugged in)**

Plug in one ESP8266 via USB, then:
```bash
./tools/mass-flash/flash.sh
```
Expected: `Detected port: /dev/cu.usbserial-XXXX` (or `wchusbserial-XXXX`), then exits cleanly (flashing not yet implemented).

- [ ] **Step 5: Commit**

```bash
git add tools/mass-flash/flash.sh
git commit -m "flash.sh: USB-serial port auto-detection"
```

---

## Task 7: flash.sh — esptool write-flash + IP discovery

**Files:**
- Modify: `tools/mass-flash/flash.sh`

- [ ] **Step 1: Append flash + discovery block**

Add at the bottom of `tools/mass-flash/flash.sh`:

```bash
echo "Writing firmware + LittleFS..."
esptool --chip esp8266 --port "$PORT" write-flash \
  0x0                "$FIRMWARE_BIN" \
  "$LITTLEFS_OFFSET" "$LITTLEFS_BIN"

echo "Reading MAC..."
mac_output=$(esptool --chip esp8266 --port "$PORT" read-mac 2>&1)
mac=$(printf '%s\n' "$mac_output" | awk '/^MAC:/ {print $2; exit}')
echo "MAC: $mac"
echo "Done. Unplug and insert the next board."
```

- [ ] **Step 2: Verify `esptool` is available**

```bash
esptool version
```
Expected: version string.

- [ ] **Step 3: Flash one test board**

Plug in one ESP8266, then:
```bash
./tools/mass-flash/flash.sh
```
Expected output (summarized):
- `Writing firmware + LittleFS...` → two write blocks, both end `Hash of data verified.`
- `Reading MAC...` → shows the board MAC address
- IP discovery prints a URL after the board joins Wi-Fi
- `Done. Unplug and insert the next board.`

- [ ] **Step 4: Verify the flashed device**

Within a minute after flashing:
- Device joins the configured Wi-Fi network automatically (check router DHCP list or `http://expertslive.local`).
- LEDs begin playing the Experts Live boot playlist.
- WLED web UI loads and shows all presets and the correct device name.

If all three check out, proceed. If any fails, stop and debug before continuing.

- [ ] **Step 5: Commit**

```bash
git add tools/mass-flash/flash.sh
git commit -m "flash.sh: erase, write firmware+fs, verify via serial"
```

---

## Task 8: ~~Discover BG image URL field name~~ (DROPPED)

**Investigation outcome:** In WLED 0.15, the "BG image URL" setting is stored in the browser's `localStorage` (via the `wledUiCfg` key), not on the device. There is no server-side field to bake. The `skin.css` fallback also requires the browser's "Enable custom CSS" toggle (`comp.css` in localStorage) which is also browser-local. Therefore no device-side mechanism to propagate the BG image to every recipient exists in stock WLED 0.15.

**Decision:** drop Task 8 and Task 9. The BG image becomes an optional one-time per-browser step, documented in the tool README. The baked device config (boot playlist, LED map, Wi-Fi, presets) is unchanged by this decision.

---

## ~~Task 8/9: Bake BG URL~~ (DROPPED)

WLED 0.15 stores the UI background URL in browser `localStorage`, not on the device. The mass-flash image therefore cannot bake this setting. The README documents it as an optional one-time per-browser step instead.

---

## Task 10: Loop mode in flash.sh

**Files:**
- Modify: `tools/mass-flash/flash.sh`

- [ ] **Step 1: Wrap the main block in a loop when `--loop` is passed**

Restructure `tools/mass-flash/flash.sh` so the existing single-flash logic lives in a function `flash_one()`, and add a `--loop` dispatcher at the end. Final structure:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
FIRMWARE_BIN="$BUILD_DIR/WLED_0.15.0_ESP8266.bin"
LITTLEFS_BIN="$BUILD_DIR/littlefs.bin"
LITTLEFS_OFFSET=0x300000

if [[ ! -f "$FIRMWARE_BIN" || ! -f "$LITTLEFS_BIN" ]]; then
  echo "Build artifacts missing. Run ./build-fs.sh first." >&2
  exit 1
fi

detect_port() {
  local matches=()
  for p in /dev/cu.usbserial-* /dev/cu.wchusbserial-* /dev/cu.SLAB_USBtoUART; do
    [[ -e "$p" ]] && matches+=("$p")
  done
  if [[ ${#matches[@]} -eq 0 ]]; then return 1; fi
  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "Multiple USB-serial devices found:" >&2
    printf '  %s\n' "${matches[@]}" >&2
    return 2
  fi
  echo "${matches[0]}"
}

wait_for_port() {
  echo "Waiting for board to be plugged in..."
  while true; do
    local port
    port="$(detect_port 2>/dev/null || true)"
    if [[ -n "$port" ]]; then echo "$port"; return 0; fi
    sleep 1
  done
}

wait_for_disconnect() {
  local port="$1"
  echo "Unplug the board to flash the next one."
  while [[ -e "$port" ]]; do sleep 1; done
  echo "Board unplugged."
}

flash_one() {
  local port="$1"
  echo "Detected port: $port"
  echo "Writing firmware + LittleFS..."
  esptool --chip esp8266 --port "$port" write-flash \
    0x0               "$FIRMWARE_BIN" \
    "$LITTLEFS_OFFSET" "$LITTLEFS_BIN"
  echo "Reading MAC..."
  mac_output=$(esptool --chip esp8266 --port "$port" read-mac 2>&1)
  mac=$(printf '%s\n' "$mac_output" | awk '/^MAC:/ {print $2; exit}')
  echo "MAC: $mac"
  echo "Done."
}

if [[ "${1:-}" == "--loop" ]]; then
  count=0
  while true; do
    port="$(wait_for_port)"
    count=$((count + 1))
    echo "--- Board #$count ---"
    flash_one "$port"
    wait_for_disconnect "$port"
    echo ""
  done
else
  port="$(detect_port)" || {
    echo "No USB-serial device found. Plug in an ESP8266 and retry." >&2
    exit 1
  }
  flash_one "$port"
  echo "Unplug and insert the next board."
fi
```

- [ ] **Step 2: Verify single-shot still works**

```bash
./tools/mass-flash/flash.sh
```
Expected: flashes the currently plugged-in board (or errors cleanly if none).

- [ ] **Step 3: Verify loop mode**

```bash
./tools/mass-flash/flash.sh --loop
```
Expected: prints `Waiting for board to be plugged in...`. Plug in a board — it flashes, then prints `Unplug the board to flash the next one.`. Unplug — script returns to waiting. Ctrl-C to exit.

Do not flash the full batch in this step. Just verify the state machine works for 2 boards.

- [ ] **Step 4: Commit**

```bash
git add tools/mass-flash/flash.sh
git commit -m "flash.sh: loop mode for sequential mass-flash"
```

---

## Task 11: Mass-flash run + documentation

**Files:**
- Modify: `tools/mass-flash/README.md`

- [ ] **Step 1: Update README with final workflow**

Append to `tools/mass-flash/README.md`:

```markdown
## Mass-flashing multiple boards

1. Run `./build-fs.sh` once. Commits any new firmware to the build cache.
2. Run `./flash.sh --loop`.
3. For each board:
   - Plug into USB
   - Wait for "Done." message (~30–45s)
   - Unplug
4. Ctrl-C when done.

Expected total time: 25–40 minutes.

## Troubleshooting

**Board not detected:** Check USB cable (some are charge-only). For CH340 clones, install the WCH driver.

**`Failed to connect to ESP8266` from esptool:** Hold GPIO0 to GND while plugging in, then release. Some clone boards don't auto-reset.

**Device joins Wi-Fi but no LEDs:** Power delivery. The first flash draws heavy current — USB may not provide enough for the LED strip. Powering the LED strip from its own supply during flashing is the fix.

**Device boots but doesn't join Wi-Fi:** Verify the required `WLED_*` environment variables were set before building. Rebuild with `./build-fs.sh` if needed.
```

- [ ] **Step 2: Flash all boards**

```bash
./tools/mass-flash/flash.sh --loop
```
Work through all boards. After each, do a quick smoke check on one representative board mid-run (boot playlist plays, joins Wi-Fi, UI loads with correct BG).

- [ ] **Step 3: Commit**

```bash
git add tools/mass-flash/README.md
git commit -m "Document mass-flash workflow and troubleshooting"
```

---

## Completion Checklist

- [ ] `./build-fs.sh` runs cleanly on a fresh checkout.
- [ ] `./flash.sh` (single) flashes one board in under a minute.
- [ ] `./flash.sh --loop` state machine works across 2+ boards.
- [ ] Test board: joins the configured Wi-Fi network, plays boot playlist, shows correct UI background without any manual step.
- [ ] All boards flashed and spot-checked.
- [ ] README documents workflow + troubleshooting.
- [ ] All intermediate commits pushed (or batched for a single PR — your call).
