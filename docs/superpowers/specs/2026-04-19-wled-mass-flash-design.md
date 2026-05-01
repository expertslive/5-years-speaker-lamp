# WLED Mass-Flash Tool — Design

**Date:** 2026-04-19
**Context:** Flashing 32 ESP8266 boards with WLED + event-specific config for the Experts Live 5 Years speaker lamp.

## Problem

The current manual per-board process (see `wled/readme.md`) takes ~10–15 minutes per device: flash firmware via browser web installer, connect to device AP, upload presets JSON via web UI, upload config JSON via web UI, create `ledmap.json` via `/edit`, set BG image URL via UI, reboot. For 32 boards that is 5–8 hours of tedious AP-switching and file uploads.

We want a USB-only workflow: plug in, run one command, unplug.

## Approach

Flash **firmware + a pre-built LittleFS filesystem image** in a single `esptool.py` invocation. The LittleFS image contains the three config files WLED reads at boot, so the device comes up fully configured — no AP dance, no web UI steps.

Rejected alternatives:
- **Post-flash HTTP provisioning** (flash firmware, then script POSTs to WLED's JSON API): requires each Mac to hop onto 32 different WLED APs in sequence. Fragile on macOS.
- **Parallel flashing via USB hub**: sequential is simple enough for 32 units (~25 min of hands-on time). Not worth the added complexity.

## Deliverables

New folder `tools/mass-flash/` in the repo:

```
tools/mass-flash/
├── flash.sh              # main — flashes one board per invocation (optional loop mode)
├── build-fs.sh           # one-time — builds LittleFS image from wled/ JSONs
├── build/                # gitignored — generated artifacts
│   ├── WLED_0.15.0_ESP8266.bin    # firmware (downloaded on first build)
│   ├── littlefs.bin                # filesystem image
│   └── cfg-baked.json              # config copied from wled/ for the FS image
└── README.md
```

## Config transformations

The baked `cfg.json` derives from `wled/wled_cfg_experts-live-5-years.json`. Plaintext credentials are not committed; `build-fs.sh` generates `wsec.json` from environment variables at build time.

1. **Credentials** — WLED's export format uses password-length fields in `cfg.json` and stores plaintext values in `wsec.json`. The build step requires `WLED_WIFI_PSK`, `WLED_AP_PSK`, and `WLED_OTA_PASSWORD`, plus optional MQTT/Hue values, and writes them only into the generated build artifact.

2. **BG image URL** — current export does not contain this field because it was set manually after export. The exact JSON path is unknown; likely `id.ui_bg` or similar. **We determine the field name empirically** in the test phase before committing to a bake: set the URL via web UI on the test board → re-export cfg.json → diff against the original → copy the new field into `cfg-baked.json`.

`presets.json` and `ledmap.json` go into the LittleFS image unchanged.

## Flash command

```
esptool.py --port $(auto-detect) write_flash \
  0x0        build/WLED_0.15.0_ESP8266.bin \
  0x300000   build/littlefs.bin
```

The LittleFS partition offset depends on the WLED build's partition map and must be confirmed against the official WLED ESP8266 partition layout before first flash.

Port auto-detection: scan `/dev/cu.usbserial-*` and `/dev/cu.wchusbserial-*`. If exactly one match, use it. If zero or multiple, prompt the user.

## Per-board workflow

1. Plug ESP8266 into USB.
2. Run `./flash.sh`.
3. Script erases flash, writes firmware + LittleFS, reads serial for ~5s to confirm boot (`WLED` banner expected).
4. Script prints "Done — unplug and insert next."
5. (Optional) loop mode: script waits for device disconnect, then reconnect, then repeats automatically.

## Dependencies (macOS, one-time)

```
brew install esptool mklittlefs
```

If the WCH USB-serial driver is not already installed, some boards (CH340-based clones) will not enumerate. The script checks and prints install instructions.

## Phases

1. **Build tooling** — write `build-fs.sh`, `flash.sh`, README. Produce `littlefs.bin` with current (untransformed) JSONs to verify the filesystem build process.
2. **Test on 1 board** — flash once, verify:
   - Device boots and joins the configured Wi-Fi network
   - Boot preset (playlist 4) plays
   - LED map is active (correct cube segmentation)
   - BG URL field — manually set via UI, re-export, diff, record the field name
3. **Bake BG URL** — update `build-fs.sh` to inject the BG URL field into `cfg-baked.json`, rebuild, test on same board.
4. **Flash remaining 31** — sequential, optionally with loop mode.

## Unknowns resolved in phase 2

- Exact JSON path for BG image URL in WLED 0.15 cfg.json
- Whether generated `wsec.json` credentials are respected (fallback: post-boot one-time `curl` per board if not)
- LittleFS partition offset for the official WLED ESP8266 binary

## Success criteria

- A fresh ESP8266 plugged into USB, with one invocation of `flash.sh`, boots into the Experts Live 5 Years playlist with correct LED mapping, correct Wi-Fi connection, and correct WLED UI background — no browser, no AP-switching, no web UI steps.
- Total hands-on time for all 32 boards: under 45 minutes including board swapping.

## Out of scope

- Parallel flashing via USB hub
- Per-board unique identifiers (mDNS collisions, MQTT client IDs) — each unit will live on a different network post-event
- Automated GitHub Actions CI for the tool — one-time event use
