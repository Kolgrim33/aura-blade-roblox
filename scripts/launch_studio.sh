#!/usr/bin/env bash
# launch_studio.sh — Launch AuraBladeRNG.rbxlx in Roblox Studio on Linux via Vinegar (Flatpak)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLACE_FILE="${PROJECT_DIR}/AuraBladeRNG.rbxlx"
VINEGAR_APP_ID="org.vinegarhq.Vinegar"

if [[ ! -f "${PLACE_FILE}" ]]; then
    echo "[*] ${PLACE_FILE} not found. Rebuilding via scripts/publish_roblox.py..."
    python3 "${SCRIPT_DIR}/publish_roblox.py"
fi

if ! command -v flatpak >/dev/null 2>&1; then
    echo "[!] Error: 'flatpak' is not installed."
    echo "    Install Flatpak and Vinegar (${VINEGAR_APP_ID}) to run Roblox Studio on Linux,"
    echo "    or publish headless without Studio using:"
    echo "      ROBLOX_API_KEY=... python3 scripts/publish_roblox.py --publish --universe-id <ID> --place-id <ID>"
    exit 1
fi

if ! flatpak info "${VINEGAR_APP_ID}" >/dev/null 2>&1; then
    echo "[!] Vinegar (${VINEGAR_APP_ID}) is not installed in Flatpak."
    echo "    Install it with:"
    echo "      flatpak install -y flathub ${VINEGAR_APP_ID}"
    echo "    Or publish directly without Roblox Studio using:"
    echo "      ROBLOX_API_KEY=... python3 scripts/publish_roblox.py --publish --universe-id <ID> --place-id <ID>"
    exit 1
fi

echo "[+] Launching AuraBladeRNG.rbxlx in Roblox Studio via Vinegar (${VINEGAR_APP_ID})..."
exec flatpak run "${VINEGAR_APP_ID}" studio "${PLACE_FILE}"
