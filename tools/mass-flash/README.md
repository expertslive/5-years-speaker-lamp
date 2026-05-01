# WLED Mass-Flash Tool

Flashes multiple ESP8266 boards with WLED 0.15 + Experts Live 5 Years config in one USB step per board. After each flash the script discovers the board's IP on the local network (via MAC in ARP) and prints a clickable URL.

## Prerequisites (one-time, macOS)

    brew install esptool jq

`littlefs-python` is installed on demand by `build-fs.sh` via `python3 -m pip`.

If your boards use a CH340 USB-serial chip (common on cheap clones), install the WCH driver from https://www.wch.cn/downloads/CH341SER_MAC_ZIP.html.

## Build (once)

    WLED_WIFI_PSK='<wifi-password>' \
    WLED_AP_PSK='<device-ap-password>' \
    WLED_OTA_PASSWORD='<ota-password>' \
    ./build-fs.sh

Downloads the WLED 0.15.0 ESP8266 firmware and builds `build/littlefs.bin` containing:

- `cfg.json` — device config (LED count, boot preset, hardware pins, mDNS name)
- `wsec.json` — Wi-Fi/AP/OTA credentials supplied from environment variables
- `presets.json` — all lighting presets and the Experts Live boot playlist
- `ledmap.json` — physical-to-logical LED index remap

## Flash a single board

    ./flash.sh

Plug in the ESP8266 via USB, run the command, wait ~75s, unplug.

## Flash multiple boards in a loop

    ./flash.sh --loop

The script waits for a USB-serial device, flashes it, prints the board's IP, then waits for you to unplug before moving on to the next.

## Flash one specific port (when multiple devices are plugged in)

    ./flash.sh --port /dev/cu.usbserial-10

Useful on a workstation that hosts multiple flashing sessions at the same time.

## IP discovery overrides

By default `flash.sh` uses the interface from `route get default` and sweeps that interface's `/24` prefix. Override this when the active LAN is not on the default interface or when you need to force the scan range:

    ./flash.sh --iface en0
    ./flash.sh --subnet 192.168.1.0/24

## Per-flash output

    Board #7: /dev/cu.usbserial-10 -> MAC aa:bb:cc:dd:ee:ff -> http://192.168.1.123

Open the URL to verify the board joined Wi-Fi and is playing the boot playlist.

## Implementation notes

**LittleFS version:** WLED 0.15 on ESP8266 uses LittleFS v2.0 with `name_max=32`. `brew mklittlefs` writes v2.11 with `name_max=255` which WLED silently refuses to mount (it then reformats the partition with defaults, throwing away our config). We build the image via `littlefs-python` with the on-device parameters: `disk_version=0x00020000`, `name_max=32`, `block_size=8192`, `block_count=125` (total 1,024,000 bytes).

**Partition offset:** LittleFS lives at flash offset `0x300000` in WLED's ESP8266 4m1m partition layout. Not `0x200000` — a common misconfiguration.

**Credential storage:** WLED splits credentials between `cfg.json` (SSID + password length fields) and `wsec.json` (plaintext secrets). Injecting `psk` into `cfg.json` has no effect; credentials must be supplied through environment variables and written into `wsec.json` at build time.

**mDNS collisions:** all boards claim the same mDNS name `expertslive`. Only one can hold the name at a time, so hostname-based discovery (`expertslive.local`) is unreliable in bulk. The script uses ARP + MAC match instead — reliable even with many identical devices on one LAN.

**BG image URL (optional, per-browser):** WLED 0.15 stores the UI background URL in `localStorage`, not on the device, so it cannot be baked into the firmware image. Recipients who want the Experts Live background can set it themselves at **Config → User Interface → BG image URL** to:

    https://github.com/expertslive/5-years-speaker-lamp/blob/main/wled/wled-ui-bg-expertslive.jpg?raw=true

This is a one-time per-browser setting and does not affect LED behavior.

## Troubleshooting

**Board not detected:** Check the USB cable (some are charge-only). For CH340 clones, install the WCH driver.

**`Could not open <port>, the port is busy`:** another process is holding the serial port. Close any `install.wled.me` browser tab or other Web-Serial session, then retry.

**`Failed to connect to ESP8266`:** some clone boards don't auto-reset. Hold GPIO0 to GND while plugging in, then release.

**Device boots but doesn't join Wi-Fi:** verify the required `WLED_*` environment variables were set before building. Rebuild with `./build-fs.sh` if needed.

**IP not found within 60s:** the board flashed successfully but hasn't joined Wi-Fi yet, or the wrong LAN was scanned. Wait another 30s and check your router's DHCP list, or re-run with `--iface <name>` / `--subnet <prefix>`.
