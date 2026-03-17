# WLED Configuration Files

This folder contains the WLED configuration for the **5 Years** speaker cubes lamp. Use these files to restore or clone the device if the ESP8266 controller needs to be replaced or reset.

---

## Files

| File | Purpose |
| --- | --- |
| `wled_cfg_experts-live-5-years.json` | Full device configuration (network, hardware, LED settings) |
| `wled_presets_experts-live-5-years.json` | All lighting presets and the boot playlist |
| `wled_ledmap.json` | Custom LED index remap for the physical strip layout |
| `wled-ui-bg-expertslive.jpg` | Custom background image shown in the WLED web UI |

---

## Device configuration summary

| Setting | Value |
| --- | --- |
| Device name | `Experts Live 5 Years` |
| mDNS hostname | `expertslive` → `http://expertslive.local` |
| Access point SSID | `ExpertsLive-5-years` (open, no password) |
| Access point IP | `4.3.2.1` |
| LED count | 56 |
| LED type | WS2812B |
| GPIO pin | 2 |
| Max current | 950 mA |
| Target FPS | 42 |
| Default brightness | 128 / 255 (~50%) |
| Boot preset | `4` — Experts Live 5 Years (playlist) |

---

## Presets

| ID | Name | Description |
| --- | --- | --- |
| `4` | `Experts Live 5 Years` | **Main boot playlist** — cycles through all effects automatically |
| `15` | `Microsoft-Logo` | Each cube in a Microsoft brand colour (blue / red / green / yellow) |
| `16` | `Microsoft-Logo-90deg` | Brand colours rotated 90° — used in boot sequence |
| `17` | `Microsoft-Logo-180deg` | Brand colours rotated 180° — used in boot sequence |
| `18` | `Microsoft-Logo-720deg` | Brand colours rotated 270° — used in boot sequence |
| `19` | `Microsoft-Matripix` | Matrix-style falling pixels in brand colours |
| `20` | `Microsoft-SolidGlitter` | Solid brand colours with glitter sparkle |
| `21` | `Microsoft-Flow` | Smooth flowing colour per cube |
| `22` | `Microsoft-Blink` | Fast blink in brand colours |
| `23` | `Microsoft-Candle` | Warm candlelight flicker per cube |
| `24` | `Fireworks Starburst` | Fireworks bursting across all four cubes |
| `2` | `Rainbow-Chase` | Flowing rainbow chase across all four cubes |
| `3` | `Red-Solid` | All cubes solid red |
| `8` | `Green-Solid` | All cubes solid green |
| `11` | `Yellow-Solid` | All cubes solid yellow |
| `14` | `Blue-Solid` | All cubes solid blue |
| `1` | `Red-Loading` | Red loading animation — used in boot sequence |
| `6` | `Green-Loading` | Green loading animation — used in boot sequence |
| `9` | `Yellow-Loading` | Yellow loading animation — used in boot sequence |
| `12` | `Blue-Loading` | Blue loading animation — used in boot sequence |
| `5` | `Off` | All LEDs off — used at end of boot sequence |

---

## LED map

The physical LED strip is wired so that three LEDs at the end of the strip (indices 53, 54, 55) are physically located after LED 10. The `wled_ledmap.json` remaps the logical indices to match the physical positions, ensuring segment boundaries align correctly with the four cube compartments.

---

## Restoring to a new device

1. Flash the device with [WLED](https://install.wled.me) (v0.15 or later recommended).
2. Connect to the `WLED-xxxxxx` access point and open `http://4.3.2.1`.
3. Go to **Config → Security & Updates** and upload `wled_presets_experts-live-5-years.json` under `Restore presets` using the **Restore** option.
4. Go to **Config → Security & Updates** and upload `wled_cfg_experts-live-5-years.json` unser `Restore configuration` using the **Restore** option.
5. Go to `http://expertslive.local/edit`, create a new file named `ledmap.json`, and paste in the contents of `wled_ledmap.json`.
6. Go to **Config → User Interface** and set `BG image URL` to `https://github.com/expertslive/5-years-speaker-lamp/blob/main/wled/wled-ui-bg-expertslive.jpg?raw=true`
7. Reboot the device. It will start the boot playlist automatically.
