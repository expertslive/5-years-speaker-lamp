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

# -- port detection ----------------------------------------------------------

list_ports() {
  local matches=()
  for p in /dev/cu.usbserial-* /dev/cu.wchusbserial-* /dev/cu.SLAB_USBtoUART; do
    [[ -e "$p" ]] && matches+=("$p")
  done
  printf '%s\n' "${matches[@]-}"
}

detect_port() {
  local matches
  matches=$(list_ports | sed '/^$/d')
  local count
  count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
  if [[ "$count" -eq 0 ]]; then
    echo "No USB-serial device found. Plug in an ESP8266 and retry." >&2
    exit 1
  fi
  if [[ "$count" -gt 1 ]]; then
    echo "Multiple USB-serial devices found:" >&2
    printf '  %s\n' $matches >&2
    echo "Disconnect all but one, or pass --port <path> to select." >&2
    exit 1
  fi
  printf '%s\n' "$matches"
}

wait_for_port() {
  # Block until exactly one USB-serial device is present.
  local warned_multi=0
  while :; do
    local matches count
    matches=$(list_ports | sed '/^$/d')
    count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
    if [[ "$count" -eq 1 ]]; then
      printf '%s\n' "$matches"
      return 0
    fi
    if [[ "$count" -gt 1 && "$warned_multi" -eq 0 ]]; then
      echo "Multiple USB-serial devices detected — unplug extras to continue:" >&2
      printf '  %s\n' $matches >&2
      warned_multi=1
    fi
    if [[ "$count" -le 1 ]]; then
      warned_multi=0
    fi
    sleep 1
  done
}

wait_for_disconnect() {
  local port="$1"
  echo "Unplug the board to continue..."
  while [[ -e "$port" ]]; do
    sleep 1
  done
}

# -- MAC helpers -------------------------------------------------------------

# Normalize a MAC to lowercase, single-digit bytes (macOS arp drops leading zeros).
# Input:  aa:bb:cc:0d:0e:0f  or  AA:BB:CC:0D:0E:0F
# Output: aa:bb:cc:d:e:f
normalize_mac() {
  local mac="$1"
  mac=$(echo "$mac" | tr 'A-Z' 'a-z')
  local out="" part
  local IFS=':'
  for part in $mac; do
    # strip leading zeros, keep at least one digit
    part=$(echo "$part" | sed 's/^0*\([0-9a-f]\)/\1/')
    if [[ -z "$out" ]]; then out="$part"; else out="$out:$part"; fi
  done
  printf '%s\n' "$out"
}

# -- IP discovery ------------------------------------------------------------

get_subnet() {
  if [[ -n "$SUBNET_OVERRIDE" ]]; then
    local subnet="$SUBNET_OVERRIDE"
    subnet="${subnet%/24}"
    if [[ "$subnet" =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})(\.0)?$ ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
    echo "--subnet must be a /24 prefix like 192.168.1 or 192.168.1.0/24" >&2
    return 1
  fi

  local iface ip
  iface="${IFACE_OVERRIDE:-$(route get default 2>/dev/null | awk '/interface:/ {print $2; exit}')}"
  if [[ -z "$iface" ]]; then
    echo "Could not determine default network interface. Pass --iface or --subnet." >&2
    return 1
  fi
  ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
  if [[ -z "$ip" ]]; then
    ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet / {print $2; exit}')
  fi
  if [[ -z "$ip" ]]; then
    echo "Could not determine IPv4 address for $iface. Pass --subnet." >&2
    return 1
  fi
  printf '%s\n' "$ip" | awk -F. '{print $1"."$2"."$3}'
}

arp_sweep() {
  local subnet="$1"
  # Ping every host on /24 in parallel so the ARP table gets populated.
  seq 2 254 | xargs -I{} -P64 ping -c1 -W150 "$subnet.{}" >/dev/null 2>&1 || true
}

find_ip_for_mac() {
  local target_mac="$1"
  local target_norm
  target_norm=$(normalize_mac "$target_mac")
  # arp -a lines: "? (192.168.1.123) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]"
  # Use process substitution so `return` actually exits this function (not a subshell).
  local ip mac norm
  while read -r ip mac; do
    [[ "$mac" == "(incomplete)" ]] && continue
    norm=$(normalize_mac "$mac")
    if [[ "$norm" == "$target_norm" ]]; then
      printf '%s\n' "$ip"
      return 0
    fi
  done < <(arp -an 2>/dev/null | awk '/at / {gsub(/[()]/,"",$2); print $2, $4}')
  return 1
}

discover_ip() {
  local mac="$1"
  local subnet
  subnet=$(get_subnet) || return 1

  # Quick check first — the device may already be in ARP from a prior sweep.
  local ip
  ip=$(find_ip_for_mac "$mac" || true)
  if [[ -n "${ip:-}" ]]; then
    printf '%s\n' "$ip"
    return 0
  fi

  echo "Sweeping $subnet.0/24 for MAC $mac ..." >&2
  local deadline=$(( $(date +%s) + 60 ))
  while [[ $(date +%s) -lt $deadline ]]; do
    arp_sweep "$subnet"
    ip=$(find_ip_for_mac "$mac" || true)
    if [[ -n "${ip:-}" ]]; then
      printf '%s\n' "$ip"
      return 0
    fi
    sleep 2
  done
  return 1
}

# -- flash driver ------------------------------------------------------------

flash_one() {
  local port="$1"
  local index="${2:-}"
  local label="Board"
  [[ -n "$index" ]] && label="Board #$index"

  echo "=============================================="
  echo "$label on $port"
  echo "=============================================="

  echo "Writing firmware + LittleFS..."
  esptool --chip esp8266 --port "$port" write-flash \
    0x0                "$FIRMWARE_BIN" \
    "$LITTLEFS_OFFSET" "$LITTLEFS_BIN"

  echo "Reading MAC (also resets the chip for clean WLED boot)..."
  local mac_output mac
  mac_output=$(esptool --chip esp8266 --port "$port" read-mac 2>&1 || true)
  mac=$(printf '%s\n' "$mac_output" \
    | awk '/^MAC:/ {print $2; exit}')
  if [[ -z "$mac" ]]; then
    echo "Could not parse MAC from esptool output:" >&2
    printf '%s\n' "$mac_output" >&2
    return 1
  fi
  echo "MAC: $mac"

  local ip
  if ip=$(discover_ip "$mac"); then
    echo "$label: $port -> MAC $mac -> http://$ip"
  else
    echo "$label: $port -> MAC $mac -> IP not found within 60s (board may still be joining Wi-Fi)"
    return 2
  fi
}

# -- argument parsing --------------------------------------------------------

MODE="single"
PORT_OVERRIDE=""
IFACE_OVERRIDE=""
SUBNET_OVERRIDE=""

usage() {
  cat <<EOF
Usage: $0 [--loop] [--port PATH] [--iface NAME] [--subnet PREFIX]

  (no args)       Flash the single connected board and print its IP.
  --loop          Continuous mode: flash, print IP, wait for unplug, repeat.
  --port PATH     Override auto-detect (useful when multiple USB-serials
                  are plugged in and only one should be flashed).
  --iface NAME    Network interface to use for IP discovery, e.g. en0.
                  Defaults to the interface from route get default.
  --subnet PREFIX /24 subnet for IP discovery, e.g. 192.168.1 or
                  192.168.1.0/24. Overrides --iface.
EOF
}

require_value() {
  local flag="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    echo "$flag requires a value." >&2
    usage >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --loop)
      MODE="loop"
      shift
      ;;
    --port)
      require_value "$1" "${2:-}"
      PORT_OVERRIDE="$2"
      shift 2
      ;;
    --port=*)
      PORT_OVERRIDE="${1#--port=}"
      require_value "--port" "$PORT_OVERRIDE"
      shift
      ;;
    --iface)
      require_value "$1" "${2:-}"
      IFACE_OVERRIDE="$2"
      shift 2
      ;;
    --iface=*)
      IFACE_OVERRIDE="${1#--iface=}"
      require_value "--iface" "$IFACE_OVERRIDE"
      shift
      ;;
    --subnet)
      require_value "$1" "${2:-}"
      SUBNET_OVERRIDE="$2"
      shift 2
      ;;
    --subnet=*)
      SUBNET_OVERRIDE="${1#--subnet=}"
      require_value "--subnet" "$SUBNET_OVERRIDE"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# -- dispatch ----------------------------------------------------------------

if [[ "$MODE" == "single" ]]; then
  if [[ -n "$PORT_OVERRIDE" ]]; then
    if [[ ! -e "$PORT_OVERRIDE" ]]; then
      echo "Port $PORT_OVERRIDE does not exist." >&2
      exit 1
    fi
    PORT="$PORT_OVERRIDE"
  else
    PORT="$(detect_port)"
  fi
  echo "Detected port: $PORT"
  flash_one "$PORT"
  echo ""
  echo "Done."
  exit 0
fi

# loop mode
echo "Loop mode: plug in boards one at a time. Ctrl-C to stop."
count=0
while :; do
  count=$((count + 1))
  if [[ -n "$PORT_OVERRIDE" ]]; then
    echo "[$count] Waiting for $PORT_OVERRIDE..."
    while [[ ! -e "$PORT_OVERRIDE" ]]; do sleep 1; done
    PORT="$PORT_OVERRIDE"
  else
    echo "[$count] Waiting for a USB-serial device..."
    PORT="$(wait_for_port)"
  fi
  echo "[$count] Detected port: $PORT"
  # allow a moment for the OS to fully enumerate the device
  sleep 1
  flash_one "$PORT" "$count" || echo "[$count] flash_one returned non-zero — continuing."
  wait_for_disconnect "$PORT"
done
