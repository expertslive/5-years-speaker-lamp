# WLED Mass-Flash Tool — Design

**Date:** 2026-04-19
**Context:** Flashing multiple ESP8266 boards with WLED + event-specific config for the Experts Live 5 Years speaker lamp.

## Problem

The current manual per-board process (see `wled/readme.md`) takes ~10–15 minutes per device: flash firmware via browser web installer, connect to device AP, upload presets JSON via web UI, upload config JSON via web UI, create `ledmap.json` via `/edit`, set BG image URL via UI, reboot. For multiple boards that becomes tedious AP-switching and file uploads.

We want a USB-only workflow: plug in, run one command, unplug.

## Approach

Flash **firmware + a pre-built LittleFS filesystem image** in a single `esptool` invocation. The LittleFS image contains the WLED config, presets, LED map, and generated secret config that WLED reads at boot, so the device comes up fully configured — no AP dance, no web UI steps.

Rejected alternatives:
- **Post-flash HTTP provisioning** (flash firmware, then script POSTs to WLED's JSON API): requires each Mac to hop onto each WLED AP in sequence. Fragile on macOS.
- **Parallel flashing via USB hub**: sequential is simple enough for this batch. Not worth the added complexity.

## Deliverables

New folder `tools/mass-flash/` in the repo:

```
tools/mass-flash/
├── flash.sh              # main — flashes one board per invocation (optional loop mode)
├── build-fs.sh           # one-time — builds LittleFS image from wled/ JSONs
├── build/                # gitignored — generated artifacts
│   ├── WLED_0.15.0_ESP8266.bin    # firmware (downloaded on first build)
│   ├── littlefs.bin                # filesystem image
│   ├── cfg-baked.json              # config copied from wled/ for the FS image
│   └── wsec-baked.json             # generated from WLED_* env vars, not committed
└── README.md
```

## Config transformations

The baked `cfg.json` derives from `wled/wled_cfg_experts-live-5-years.json`. Plaintext credentials are not committed; `build-fs.sh` generates `wsec.json` from environment variables at build time.

1. **Credentials** — WLED's export format uses password-length fields in `cfg.json` and stores plaintext values in `wsec.json`. The build step requires `WLED_WIFI_PSK`, `WLED_AP_PSK`, and `WLED_OTA_PASSWORD`, plus optional MQTT/Hue values, and writes them only into the generated build artifact.

2. **BG image URL** — WLED 0.15 stores this browser-side in `localStorage`, so it cannot be baked into the device image. The README documents it as an optional one-time per-browser setting.

`presets.json` and `ledmap.json` go into the LittleFS image unchanged.

## Flash command

```
esptool --port $(auto-detect) write-flash \
  0x0        build/WLED_0.15.0_ESP8266.bin \
  0x300000   build/littlefs.bin
```

The LittleFS partition offset depends on the WLED build's partition map and must be confirmed against the official WLED ESP8266 partition layout before first flash.

Port auto-detection: scan `/dev/cu.usbserial-*` and `/dev/cu.wchusbserial-*`. If exactly one match, use it. If zero or multiple, prompt the user.

## Per-board workflow

1. Plug ESP8266 into USB.
2. Run `./flash.sh`.
3. Script writes firmware + LittleFS, reads the board MAC via `esptool read-mac`, then discovers the DHCP IP by matching that MAC in ARP.
4. Script prints the discovered URL, or a clear "IP not found" warning if the board has not joined Wi-Fi yet.
5. (Optional) loop mode: script waits for device disconnect, then reconnect, then repeats automatically.

## Dependencies (macOS, one-time)

```
brew install esptool jq
```

`build-fs.sh` installs `littlefs-python` with `python3 -m pip` if needed so the same interpreter imports the module later. If the WCH USB-serial driver is not already installed, some boards (CH340-based clones) will not enumerate.

## Phases

1. **Build tooling** — write `build-fs.sh`, `flash.sh`, README. Produce `littlefs.bin` with current (untransformed) JSONs to verify the filesystem build process.
2. **Test on 1 board** — flash once, verify:
   - Device boots and joins the configured Wi-Fi network
   - Boot preset (playlist 4) plays
   - LED map is active (correct cube segmentation)
  - BG URL remains an optional per-browser setting
3. **Document BG URL limitation** — keep BG URL as an optional per-browser setting because it is not stored on the device.
4. **Flash remaining boards** — sequential, optionally with loop mode.

## Unknowns resolved in phase 2

- BG image URL is browser-local in WLED 0.15 and cannot be baked into the device.
- Generated `wsec.json` credentials are the correct way to provide Wi-Fi/AP/OTA secrets.
- LittleFS partition offset for the official WLED ESP8266 binary is `0x300000`.

## Success criteria

- A fresh ESP8266 plugged into USB, with one invocation of `flash.sh`, boots into the Experts Live 5 Years playlist with correct LED mapping and correct Wi-Fi connection — no AP-switching or web UI upload steps.
- Total hands-on time stays low because each board is plug in, flash, unplug.

## Out of scope

- Parallel flashing via USB hub
- Per-board unique identifiers (mDNS collisions, MQTT client IDs) — each unit will live on a different network post-event
- Automated GitHub Actions CI for the tool — one-time event use
