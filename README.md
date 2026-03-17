# High Five Hive — Setup Instructions

*Experts Live Netherlands · 5 Years · A thank you to our five-time speakers*

---

Thank you for being part of the Experts Live Netherlands community for **five years in a row**. This cube was made especially for you — a home for the four crystal cubes you collected at each edition, lit up to show them at their best.

Inside this box you'll find:

- The **High Five Hive** display cube (navy blue)
- A **USB-C power cable**
- Any spare screws or parts

---

## What's inside the cube

![Overview of all components](/img/instructions-overview.png)

The cube consists of several layers assembled from front to back:

- **Outer housing** — the dark navy blue shell
- **Crystal cube holders** — four individual compartments for each of your yearly speaker cubes
- **LED frames** — multiple layers holding the LED strip and cubes in place
- **Back cover plate** — the panel with the *Experts Live / 5 years* logo, secured by four twist-lock corner screws
- **WLED controller** — a tiny Wi-Fi-enabled electronics board (ESP8266) that drives all the lights and connects to your network

If you ever have to remove/place the inner frames, pay attention to the numbers on the side for correct placement:

![Overview of all components](/img/instructions-modules.png)


---

## Assembly

### Step 1 — Open the back cover

The back cover is secured by four **quarter-turn twist-lock screws** in the corners.

![Back cover with twist-lock screws](/img/instructions-01.png)

To open, insert the **connector end of the supplied USB-C cable** into each corner screw and rotate **in the opposite direction of the arrow**. Once all four screws are turned, the back panel will come free.

---

### Step 2 — Pull out the electronics board

![ESP circuit board in housing](/img/instructions-02.png)

Gently pull the **WLED circuit board** out from its slot inside the housing. You only need to move it aside — **do not disconnect the LED strip connector** unless absolutely necessary.

> **If the LED strip connector did come loose**, reconnect it as follows before proceeding:
>
> | Wire colour | Pin | Position on circuitboard (viewed from above) |
> | --- | --- | --- |
> | **Red** | 5V | Left-most pin |
> | **Green** | Data | Middle pin |
> | **White** | GND | Right-most pin |

---

### Step 3 — Remove the white back panel

![White back panel removed](/img/instructions-03.png)

Lift out the **white cover plate** to expose the four openings for the crystal cubes inside the housing.

---

### Step 4 — Place your crystal cubes

![Placing a crystal cube](/img/instructions-04.png)

Drop each of your four crystal speaker cubes into their compartment.

Each cube slides straight in and sits snugly in its slot. No forcing needed.

---

### Step 5 — Replace the white panel and reseat the board

![Reseating the white panel and circuit board](/img/instructions-05.png)

Place the **white cover plate** back in position over the crystal cubes, then slide the **circuit board** back into its slot in the housing. Make sure the USB-C port aligns with the opening on the side of the back cover.

---

### Step 6 — Close and lock the back cover

![Locking the back cover](/img/instructions-07.png)

Slide the back cover panel onto the housing and **lock all four corners in the direction of the arrows** using the USB-C connector. The arrows on the cover show the locked direction.

**Don't use excessive force!** If the screw wont turn freely, press down on the cover to make sure it slots in place neatly.

The cube is now fully assembled and ready to power on.

---

## Powering on

Connect a USB-C power cable (5V, at least 1A — a standard phone charger works perfectly) to the **USB-C port on the side** of the back panel.

![USB-C port location](/img/instructions-06.png)

The cube will power on automatically. After a few seconds, the lights will start and the built-in show will begin — cycling through all the preset lighting effects.

---

## Connecting to the cube via Wi-Fi

The cube runs **WLED** — open-source LED control software with a built-in web interface. Out of the box it broadcasts its own open Wi-Fi network so you can connect and customise it without any technical setup.

### Step 1 — Connect to the cube's Wi-Fi

On your phone, tablet, or computer, open your Wi-Fi settings and connect to:

> **Network name:** `ExpertsLive-5-years`
> **Password:** *(none — open network)*

### Step 2 — Open the WLED interface

Once connected, open a browser and go to:

> **<http://expertslive.local>** (or <http://4.3.2.1>)

You will see the WLED interface with the custom Experts Live Netherlands background.

![WLED dashboard](/img/wled-dashboard.png)

### Using the WLED app (optional)

WLED has a free mobile app that makes it easy to control the cube from your phone. Search for **"WLED"** in the App Store or Google Play. When you open the app on the same Wi-Fi network, it will automatically discover the cube.

---

## Understanding the lights

The four cube compartments are each independently controlled. They are set up as named segments:

| Segment | Default colour |
| --- | --- |
| `Bottom-Left` | Blue |
| `Top-Left` | Red |
| `Top-Right` | Green |
| `Bottom-Right` | Yellow / Orange |

---

## Using the pre-built presets

A full set of lighting presets has been pre-loaded onto the cube. You can find them in the WLED interface under the **Presets** tab:

| Preset name | What it does |
| --- | --- |
| `Experts Live 5 Years` | **The main playlist** — cycles through all effects automatically |
| `Microsoft-Logo` | Each cube lights up in a Microsoft brand colour (blue / red / green / yellow) |
| `Microsoft-Matripix` | Matrix-style falling effect in brand colours |
| `Microsoft-Flow` | Smooth flowing colour per cube |
| `Microsoft-SolidGlitter` | Solid brand colours with a glitter sparkle |
| `Microsoft-Blink` | Fast blinking in brand colours |
| `Microsoft-Candle` | Warm candlelight flicker per cube |
| `Fireworks Starburst` | Fireworks bursting across all four cubes |
| `Rainbow-Chase` | A flowing rainbow chase across all four cubes |
| `Microsoft-Logo-90/180/270deg` | Microsoft colours rotated, used as a `boot sequence` |
| `Red/Green/Blue/Yellow-Solid/Loading` | Each cube individually lit in a single solid colour, used as a `boot sequence` |
| `Off` | All lights off, used as a `boot sequence` |

### The default playlist

By default, when you power the cube on it will automatically start the **"Experts Live 5 Years"** playlist. This cycles through all the presets in a scripted sequence — it starts with a loading animation, builds up to all four cubes lit and runs through the Microsoft-themed effects.
You don't need to do anything — just plug it in and enjoy the show.

If you want to set one preset as default, you can select the preset als make sure `Apply at boot` is selected before you click `Save`.

![Setting a preset](/img/instructions-08.png)

---

## Connecting to your home Wi-Fi (optional)

If you'd like to control the cube from your normal home network (so you don't need to switch Wi-Fi on your phone every time), you can connect it to your router:

1. Connect to `ExpertsLive-5-years` and open **<http://expertslive.local>** (or <http://4.3.2.1>)
2. Go to **Config → WiFi Setup**
3. Enter your home Wi-Fi network name and password and click **Save**
4. The cube will restart and join your home network
5. You can now reach it at **http://expertslive.local** from any device on the same network

> **Note:** After connecting to your home Wi-Fi, the `ExpertsLive-5-years` hotspot will no longer appear and will only show up if the device is unable to connect to a known network.

---

## Tips

- **Power:** Any USB-C charger (phone charger, laptop USB-C port, USB hub) will work. The cube draws under 1A at full brightness.
- **Brightness:** You can dim the lights in the WLED interface using the brightness slider — useful if you use it as a night-light ambience.
- **Custom effects:** WLED has hundreds of built-in effects and palettes. Feel free to explore — nothing you change can break the cube, and the pre-built presets are always there to return to.

---

## About this cube

Designed and built by [**Koos Goossens**](https://www.linkedin.com/in/koos-goossens/) for [Experts Live Netherlands](https://www.expertslive.nl)

This cube was created to give the four crystal cubes you earned over the years a permanent home and to say **thank you** for your continued contribution to the Microsoft community! 🙏🏻

*See you at the next one.*
