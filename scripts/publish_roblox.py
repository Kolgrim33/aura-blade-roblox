#!/usr/bin/env python3
"""
publish_roblox.py — Build, Patch Monetization IDs, Auto-Discover, and Publish AuraBladeRNG.rbxlx

Features:
  1. Reads Gamepass IDs & Developer Product IDs from CLI flags or monetization_ids.json
     and patches src/shared/GameConfig.luau automatically.
  2. Rebuilds the standalone AuraBladeRNG.rbxlx XML place file from src/**/*.luau
     and validates the resulting XML with xml.etree.ElementTree.
  3. Supports --auto-discover to resolve Universe ID from Place ID (via Roblox API),
     discover the authenticated creator's experiences/gamepasses/developer products,
     or open https://create.roblox.com/dashboard/credentials via xdg-open if no
     credentials are set yet.
  4. Publishes AuraBladeRNG.rbxlx directly to Roblox using EITHER:
     (a) Roblox Open Cloud Place Publishing API (ROBLOX_API_KEY / --api-key):
         POST https://apis.roblox.com/universes/v1/{universe_id}/places/{place_id}/versions?versionType=Published
     (b) Roblox Cookie upload API (ROBLOSECURITY / --cookie):
         POST https://data.roblox.com/Data/Upload.ashx?assetid={place_id} (with automatic X-CSRF-TOKEN handshake)

Usage examples:
  # Patch GameConfig.luau from monetization_ids.json and rebuild AuraBladeRNG.rbxlx:
  ./scripts/publish_roblox.py --config monetization_ids.json

  # Auto-discover Universe/Place/Monetization IDs (or open Creator Dashboard if unconfigured):
  ./scripts/publish_roblox.py --auto-discover

  # Publish directly via Open Cloud API key:
  ROBLOX_API_KEY="your_open_cloud_key" ./scripts/publish_roblox.py \
      --publish --universe-id 123456789 --place-id 987654321 --no-sandbox

  # Publish directly via .ROBLOSECURITY cookie:
  ROBLOSECURITY="your_roblosecurity_cookie" ./scripts/publish_roblox.py \
      --publish --place-id 987654321 --no-sandbox
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

ROOT_DIR = Path(__file__).resolve().parent.parent
GAME_CONFIG_PATH = ROOT_DIR / "src" / "shared" / "GameConfig.luau"
RBXLX_OUTPUT_PATH = ROOT_DIR / "AuraBladeRNG.rbxlx"
DEFAULT_MONETIZATION_JSON = ROOT_DIR / "monetization_ids.json"
CREDENTIALS_DASHBOARD_URL = "https://create.roblox.com/dashboard/credentials"

GAMEPASS_KEYS = [
    "DoubleLuck",
    "FastRoll",
    "AutoRoll",
    "TripleRoll",
    "VIP",
    "ExtraStorage",
]

DEVPRODUCT_KEYS = [
    "ServerLuckBoost",
    "HeavenlyPotion",
    "SummonOmegaBoss",
    "GemPackSmall",
    "GemPackMedium",
    "GemPackMega",
]

NAME_TO_KEY_MAP = {
    "2x luck forever": "DoubleLuck",
    "doubleluck": "DoubleLuck",
    "fast roll + skip cutscene": "FastRoll",
    "fastroll": "FastRoll",
    "auto-roll + afk guard": "AutoRoll",
    "autoroll": "AutoRoll",
    "triple roll (3x at once)": "TripleRoll",
    "tripleroll": "TripleRoll",
    "vip cyber sovereign": "VIP",
    "vip": "VIP",
    "+100 aura vault slots": "ExtraStorage",
    "extrastorage": "ExtraStorage",
    "2x server luck party (15m)": "ServerLuckBoost",
    "serverluckboost": "ServerLuckBoost",
    "singularity luck potion (+500%)": "HeavenlyPotion",
    "heavenlypotion": "HeavenlyPotion",
    "summon omega mech boss": "SummonOmegaBoss",
    "summonomegaboss": "SummonOmegaBoss",
    "1,500 luck gems": "GemPackSmall",
    "gempacksmall": "GemPackSmall",
    "6,000 luck gems (+20% bonus)": "GemPackMedium",
    "gempackmedium": "GemPackMedium",
    "25,000 luck gems (mega vault)": "GemPackMega",
    "gempackmega": "GemPackMega",
}


def parse_kv_pairs(pairs: list[str], valid_keys: list[str], label: str) -> Dict[str, int]:
    result: Dict[str, int] = {}
    for item in pairs:
        if "=" not in item:
            raise ValueError(
                f"Invalid {label} argument '{item}'. Expected format KEY=ID (e.g. {valid_keys[0]}=12345678)."
            )
        key, val_str = item.split("=", 1)
        key = key.strip()
        if key not in valid_keys:
            raise ValueError(f"Unknown {label} key '{key}'. Valid keys: {', '.join(valid_keys)}")
        try:
            result[key] = int(val_str.strip())
        except ValueError as exc:
            raise ValueError(f"Invalid integer ID '{val_str}' for {label} '{key}'.") from exc
    return result


def load_monetization_json(
    path: Path,
) -> Tuple[Dict[str, int], Dict[str, int], Optional[bool], Optional[int], Optional[int]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    gp_raw = data.get("Gamepasses") or data.get("gamepasses") or {}
    dp_raw = data.get("DevProducts") or data.get("dev_products") or data.get("devProducts") or {}

    gamepasses: Dict[str, int] = {}
    for k, v in gp_raw.items():
        if k in GAMEPASS_KEYS:
            val = v.get("id") if isinstance(v, dict) else v
            if isinstance(val, int) and val > 0:
                gamepasses[k] = val

    devproducts: Dict[str, int] = {}
    for k, v in dp_raw.items():
        if k in DEVPRODUCT_KEYS:
            val = v.get("id") if isinstance(v, dict) else v
            if isinstance(val, int) and val > 0:
                devproducts[k] = val

    sandbox = data.get("studio_sandbox_purchases")
    if not isinstance(sandbox, bool):
        sandbox = None

    universe_id = data.get("universe_id")
    place_id = data.get("place_id")
    return (
        gamepasses,
        devproducts,
        sandbox,
        int(universe_id) if isinstance(universe_id, int) and universe_id > 0 else None,
        int(place_id) if isinstance(place_id, int) and place_id > 0 else None,
    )


def save_discovered_to_json(
    path: Path,
    universe_id: Optional[int],
    place_id: Optional[int],
    gamepasses: Dict[str, int],
    devproducts: Dict[str, int],
) -> None:
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            data = {}
    else:
        data = {}

    if universe_id and universe_id > 0:
        data["universe_id"] = universe_id
    if place_id and place_id > 0:
        data["place_id"] = place_id
    if gamepasses:
        gp_section = data.setdefault("Gamepasses", {})
        for k, v in gamepasses.items():
            gp_section[k] = v
    if devproducts:
        dp_section = data.setdefault("DevProducts", {})
        for k, v in devproducts.items():
            dp_section[k] = v

    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def patch_game_config(
    config_path: Path,
    gamepasses: Dict[str, int],
    devproducts: Dict[str, int],
    sandbox: Optional[bool],
) -> int:
    source = config_path.read_text(encoding="utf-8")
    changes = 0

    if sandbox is not None:
        sandbox_str = "true" if sandbox else "false"
        new_source, count = re.subn(
            r"(GameConfig\.STUDIO_SANDBOX_PURCHASES\s*=\s*)(true|false)",
            rf"\g<1>{sandbox_str}",
            source,
        )
        if count > 0 and new_source != source:
            source = new_source
            changes += count

    all_updates = {**gamepasses, **devproducts}
    for key, new_id in all_updates.items():
        pattern = re.compile(
            rf'(Key\s*=\s*"{re.escape(key)}"\s*,\s*\n\s*Id\s*=\s*)(\d+)',
            re.MULTILINE,
        )
        new_source, count = pattern.subn(rf"\g<1>{new_id}", source)
        if count == 0:
            raise RuntimeError(f'Could not locate entry for Key = "{key}" in {config_path}')
        if new_source != source:
            source = new_source
            changes += count

    if changes > 0:
        config_path.write_text(source, encoding="utf-8")
    return changes


def cdata_wrap(script_source: str) -> str:
    safe = script_source.replace("]]>", "]]]]><![CDATA[>")
    if not safe.endswith("\n"):
        safe += "\n"
    return f"<![CDATA[{safe}]]>"


def build_rbxlx(output_path: Path) -> None:
    shared_game_config = (ROOT_DIR / "src" / "shared" / "GameConfig.luau").read_text(encoding="utf-8")
    shared_roll_engine = (ROOT_DIR / "src" / "shared" / "RollEngine.luau").read_text(encoding="utf-8")

    srv_data_mgr = (ROOT_DIR / "src" / "server" / "DataManager.luau").read_text(encoding="utf-8")
    srv_monetization = (ROOT_DIR / "src" / "server" / "MonetizationServer.luau").read_text(encoding="utf-8")
    srv_visual_aura = (ROOT_DIR / "src" / "server" / "VisualAuraBuilder.luau").read_text(encoding="utf-8")
    srv_world_builder = (ROOT_DIR / "src" / "server" / "WorldBuilder.luau").read_text(encoding="utf-8")
    srv_combat_boss = (ROOT_DIR / "src" / "server" / "CombatAndBossServer.luau").read_text(encoding="utf-8")
    srv_game_server = (ROOT_DIR / "src" / "server" / "GameServer.server.luau").read_text(encoding="utf-8")

    cli_game_client = (ROOT_DIR / "src" / "client" / "GameClient.client.luau").read_text(encoding="utf-8")

    xml_content = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
        "\t<External>null</External>\n"
        "\t<External>nil</External>\n"
        '\t<Item class="Workspace" referent="RBX_WORKSPACE">\n'
        "\t\t<Properties>\n"
        '\t\t\t<string name="Name">Workspace</string>\n'
        '\t\t\t<bool name="FilteringEnabled">true</bool>\n'
        "\t\t</Properties>\n"
        "\t</Item>\n"
        '\t<Item class="ReplicatedStorage" referent="RBX_REPSTORAGE">\n'
        "\t\t<Properties>\n"
        '\t\t\t<string name="Name">ReplicatedStorage</string>\n'
        "\t\t</Properties>\n"
        '\t\t<Item class="Folder" referent="RBX_SHARED_FOLDER">\n'
        "\t\t\t<Properties>\n"
        '\t\t\t\t<string name="Name">Shared</string>\n'
        "\t\t\t</Properties>\n"
        '\t\t\t<Item class="ModuleScript" referent="RBX_MOD_GAMECONFIG">\n'
        "\t\t\t\t<Properties>\n"
        '\t\t\t\t\t<string name="Name">GameConfig</string>\n'
        f'\t\t\t\t\t<ProtectedString name="Source">{cdata_wrap(shared_game_config)}</ProtectedString>\n'
        "\t\t\t\t</Properties>\n"
        "\t\t\t</Item>\n"
        '\t\t\t<Item class="ModuleScript" referent="RBX_MOD_ROLLENGINE">\n'
        "\t\t\t\t<Properties>\n"
        '\t\t\t\t\t<string name="Name">RollEngine</string>\n'
        f'\t\t\t\t\t<ProtectedString name="Source">{cdata_wrap(shared_roll_engine)}</ProtectedString>\n'
        "\t\t\t\t</Properties>\n"
        "\t\t\t</Item>\n"
        "\t\t</Item>\n"
        "\t</Item>\n"
        '\t<Item class="ServerScriptService" referent="RBX_SSS">\n'
        "\t\t<Properties>\n"
        '\t\t\t<string name="Name">ServerScriptService</string>\n'
        "\t\t</Properties>\n"
        '\t\t<Item class="Folder" referent="RBX_SERVER_FOLDER">\n'
        "\t\t\t<Properties>\n"
        '\t\t\t\t<string name="Name">Server</string>\n'
        "\t\t\t</Properties>\n"
        '\t\t\t<Item class="ModuleScript" referent="RBX_MOD_DATAMGR">\n'
        "\t\t\t\t<Properties>\n"
        '\t\t\t\t\t<string name="Name">DataManager</string>\n'
        f'\t\t\t\t\t<ProtectedString name="Source">{cdata_wrap(srv_data_mgr)}</ProtectedString>\n'
        "\t\t\t\t</Properties>\n"
        "\t\t\t</Item>\n"
        '\t\t\t<Item class="ModuleScript" referent="RBX_MOD_MONETIZATION">\n'
        "\t\t\t\t<Properties>\n"
        '\t\t\t\t\t<string name="Name">MonetizationServer</string>\n'
        f'\t\t\t\t\t<ProtectedString name="Source">{cdata_wrap(srv_monetization)}</ProtectedString>\n'
        "\t\t\t\t</Properties>\n"
        "\t\t\t</Item>\n"
        '\t\t\t<Item class="ModuleScript" referent="RBX_MOD_VISUALAURA">\n'
        "\t\t\t\t<Properties>\n"
        '\t\t\t\t\t<string name="Name">VisualAuraBuilder</string>\n'
        f'\t\t\t\t\t<ProtectedString name="Source">{cdata_wrap(srv_visual_aura)}</ProtectedString>\n'
        "\t\t\t\t</Properties>\n"
        "\t\t\t</Item>\n"
        '\t\t\t<Item class="ModuleScript" referent="RBX_MOD_WORLDBUILDER">\n'
        "\t\t\t\t<Properties>\n"
        '\t\t\t\t\t<string name="Name">WorldBuilder</string>\n'
        f'\t\t\t\t\t<ProtectedString name="Source">{cdata_wrap(srv_world_builder)}</ProtectedString>\n'
        "\t\t\t\t</Properties>\n"
        "\t\t\t</Item>\n"
        '\t\t\t<Item class="ModuleScript" referent="RBX_MOD_COMBATBOSS">\n'
        "\t\t\t\t<Properties>\n"
        '\t\t\t\t\t<string name="Name">CombatAndBossServer</string>\n'
        f'\t\t\t\t\t<ProtectedString name="Source">{cdata_wrap(srv_combat_boss)}</ProtectedString>\n'
        "\t\t\t\t</Properties>\n"
        "\t\t\t</Item>\n"
        '\t\t\t<Item class="Script" referent="RBX_SCRIPT_GAMESERVER">\n'
        "\t\t\t\t<Properties>\n"
        '\t\t\t\t\t<string name="Name">GameServer</string>\n'
        f'\t\t\t\t\t<ProtectedString name="Source">{cdata_wrap(srv_game_server)}</ProtectedString>\n'
        "\t\t\t\t</Properties>\n"
        "\t\t\t</Item>\n"
        "\t\t</Item>\n"
        "\t</Item>\n"
        '\t<Item class="StarterPlayer" referent="RBX_STARTERPLAYER">\n'
        "\t\t<Properties>\n"
        '\t\t\t<string name="Name">StarterPlayer</string>\n'
        "\t\t</Properties>\n"
        '\t\t<Item class="StarterPlayerScripts" referent="RBX_SPS">\n'
        "\t\t\t<Properties>\n"
        '\t\t\t\t<string name="Name">StarterPlayerScripts</string>\n'
        "\t\t\t</Properties>\n"
        '\t\t\t<Item class="LocalScript" referent="RBX_LOCALSCRIPT_CLIENT">\n'
        "\t\t\t\t<Properties>\n"
        '\t\t\t\t\t<string name="Name">GameClient</string>\n'
        f'\t\t\t\t\t<ProtectedString name="Source">{cdata_wrap(cli_game_client)}</ProtectedString>\n'
        "\t\t\t\t</Properties>\n"
        "\t\t\t</Item>\n"
        "\t\t</Item>\n"
        "\t</Item>\n"
        "</roblox>\n"
    )

    output_path.write_text(xml_content, encoding="utf-8")


def validate_rbxlx(path: Path) -> Tuple[int, int]:
    tree = ET.parse(path)
    root = tree.getroot()
    if root.tag != "roblox":
        raise RuntimeError(f"Expected root tag <roblox>, got <{root.tag}>")
    items = list(root.iter("Item"))
    scripts = [
        el for el in items if el.attrib.get("class") in ("Script", "LocalScript", "ModuleScript")
    ]
    return len(items), len(scripts)


def http_json_get(url: str, headers: Optional[Dict[str, str]] = None) -> Any:
    req = urllib.request.Request(url, headers=headers or {"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def open_credentials_dashboard() -> None:
    print(f"[*] Opening Roblox Creator Credentials Dashboard: {CREDENTIALS_DASHBOARD_URL}")
    if shutil.which("xdg-open"):
        try:
            subprocess.Popen(
                ["xdg-open", CREDENTIALS_DASHBOARD_URL],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as exc:
            print(f"[!] Could not launch browser via xdg-open: {exc}", file=sys.stderr)
    else:
        print("[!] xdg-open not found; open the URL above in your browser manually.")


def auto_discover_roblox_ids(
    universe_id: Optional[int],
    place_id: Optional[int],
    api_key: Optional[str],
    cookie: Optional[str],
) -> Tuple[Optional[int], Optional[int], Dict[str, int], Dict[str, int]]:
    discovered_gp: Dict[str, int] = {}
    discovered_dp: Dict[str, int] = {}

    headers: Dict[str, str] = {"Accept": "application/json"}
    if api_key:
        headers["x-api-key"] = api_key
    if cookie:
        clean_cookie = cookie.strip()
        if not clean_cookie.startswith(".ROBLOSECURITY="):
            headers["Cookie"] = f".ROBLOSECURITY={clean_cookie}"
        else:
            headers["Cookie"] = clean_cookie

    # 1. If place_id is known but universe_id is not, resolve universe_id via Roblox API
    if place_id and not universe_id:
        try:
            url = f"https://apis.roblox.com/universes/v1/places/{place_id}/universe"
            data = http_json_get(url, headers=headers)
            u_id = data.get("universeId")
            if isinstance(u_id, int) and u_id > 0:
                universe_id = u_id
                print(f"[+] Auto-discovered Universe ID {universe_id} from Place ID {place_id}.")
        except Exception as exc:
            print(f"[!] Could not resolve Universe ID from Place ID {place_id}: {exc}", file=sys.stderr)

    # 2. If ROBLOSECURITY cookie is set and universe_id/place_id are still unknown, query authenticated user's games
    if cookie and (not universe_id or not place_id):
        try:
            user_data = http_json_get("https://users.roblox.com/v1/users/authenticated", headers=headers)
            user_id = user_data.get("id")
            user_name = user_data.get("name")
            if user_id:
                print(f"[+] Authenticated via ROBLOSECURITY as {user_name} (userId={user_id}).")
                games_url = f"https://games.roblox.com/v2/users/{user_id}/games?accessFilter=2&limit=50&sortOrder=Desc"
                games_resp = http_json_get(games_url, headers=headers)
                games_list = games_resp.get("data") or []
                if games_list:
                    chosen = games_list[0]
                    for g in games_list:
                        if "aura" in (g.get("name") or "").lower():
                            chosen = g
                            break
                    if not universe_id and isinstance(chosen.get("id"), int):
                        universe_id = chosen["id"]
                    root_place = chosen.get("rootPlace") or {}
                    if not place_id and isinstance(root_place.get("id"), int):
                        place_id = root_place["id"]
                    print(
                        f"[+] Auto-discovered experience '{chosen.get('name')}': "
                        f"universe_id={universe_id}, place_id={place_id}"
                    )
        except Exception as exc:
            print(f"[!] Could not auto-discover user experiences from ROBLOSECURITY: {exc}", file=sys.stderr)

    # 3. If universe_id is available, try discovering Gamepasses & DevProducts by name
    if universe_id:
        try:
            gp_url = f"https://games.roblox.com/v1/games/{universe_id}/game-passes?limit=100&sortOrder=Asc"
            gp_resp = http_json_get(gp_url, headers=headers)
            for item in gp_resp.get("data") or []:
                gp_id = item.get("id")
                gp_name = (item.get("name") or "").strip().lower()
                mapped_key = NAME_TO_KEY_MAP.get(gp_name)
                if mapped_key in GAMEPASS_KEYS and isinstance(gp_id, int) and gp_id > 0:
                    discovered_gp[mapped_key] = gp_id
                    print(f"[+] Auto-discovered Gamepass {mapped_key} = {gp_id} ('{item.get('name')}')")
        except Exception as exc:
            print(f"[!] Gamepass discovery skipped/failed for universe {universe_id}: {exc}", file=sys.stderr)

        if api_key or cookie:
            try:
                dp_url = (
                    f"https://apis.roblox.com/developer-products/v1/universes/{universe_id}/developerproducts"
                    "?pageNumber=1&pageSize=50"
                )
                dp_resp = http_json_get(dp_url, headers=headers)
                items = dp_resp.get("developerProducts") or dp_resp.get("data") or []
                for item in items:
                    dp_id = item.get("productId") or item.get("id")
                    dp_name = (item.get("name") or "").strip().lower()
                    mapped_key = NAME_TO_KEY_MAP.get(dp_name)
                    if mapped_key in DEVPRODUCT_KEYS and isinstance(dp_id, int) and dp_id > 0:
                        discovered_dp[mapped_key] = dp_id
                        print(f"[+] Auto-discovered DevProduct {mapped_key} = {dp_id} ('{item.get('name')}')")
            except Exception as exc:
                print(f"[!] DevProduct discovery skipped/failed for universe {universe_id}: {exc}", file=sys.stderr)

    if not api_key and not cookie:
        print(
            "[!] Neither ROBLOX_API_KEY nor ROBLOSECURITY is set in the environment or CLI flags."
        )
        open_credentials_dashboard()

    return universe_id, place_id, discovered_gp, discovered_dp


def publish_to_open_cloud(
    rbxlx_path: Path,
    universe_id: int,
    place_id: int,
    api_key: str,
    version_type: str = "Published",
) -> str:
    query = urllib.parse.urlencode({"versionType": version_type})
    url = f"https://apis.roblox.com/universes/v1/{universe_id}/places/{place_id}/versions?{query}"
    payload = rbxlx_path.read_bytes()

    req = urllib.request.Request(
        url=url,
        data=payload,
        method="POST",
        headers={
            "x-api-key": api_key.strip(),
            "Content-Type": "application/xml",
            "Accept": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"Roblox Open Cloud API returned HTTP {exc.code} {exc.reason}: {err_body}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Network error contacting Roblox Open Cloud API: {exc.reason}") from exc


def fetch_csrf_token(cookie_header: str) -> str:
    req = urllib.request.Request(
        url="https://auth.roblox.com/v2/logout",
        data=b"",
        method="POST",
        headers={"Cookie": cookie_header},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.headers.get("x-csrf-token", "")
    except urllib.error.HTTPError as exc:
        token = exc.headers.get("x-csrf-token") if exc.headers else None
        if token:
            return token
        raise RuntimeError(
            f"Failed to obtain X-CSRF-TOKEN from Roblox (HTTP {exc.code} {exc.reason}). Check ROBLOSECURITY cookie."
        ) from exc


def publish_with_cookie(
    rbxlx_path: Path,
    place_id: int,
    cookie: str,
) -> str:
    clean_cookie = cookie.strip()
    cookie_header = (
        clean_cookie
        if clean_cookie.startswith(".ROBLOSECURITY=")
        else f".ROBLOSECURITY={clean_cookie}"
    )
    csrf_token = fetch_csrf_token(cookie_header)
    payload = rbxlx_path.read_bytes()
    url = f"https://data.roblox.com/Data/Upload.ashx?assetid={place_id}"

    req = urllib.request.Request(
        url=url,
        data=payload,
        method="POST",
        headers={
            "Cookie": cookie_header,
            "X-CSRF-TOKEN": csrf_token,
            "User-Agent": "Roblox/WinInet",
            "Content-Type": "application/xml",
            "Accept": "application/json, text/plain, */*",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"Roblox Cookie Upload API returned HTTP {exc.code} {exc.reason}: {err_body}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Network error contacting Roblox Upload API: {exc.reason}") from exc


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Patch GameConfig.luau monetization IDs, rebuild AuraBladeRNG.rbxlx, "
            "auto-discover Roblox IDs, and publish via Roblox Open Cloud API or ROBLOSECURITY cookie."
        )
    )
    parser.add_argument(
        "--config",
        "-c",
        type=Path,
        default=None,
        help="Path to JSON file containing Gamepass & DevProduct IDs (defaults to monetization_ids.json if it exists).",
    )
    parser.add_argument(
        "--gamepass",
        "-g",
        action="append",
        default=[],
        metavar="KEY=ID",
        help=f"Set a Gamepass ID (repeatable). Keys: {', '.join(GAMEPASS_KEYS)}",
    )
    parser.add_argument(
        "--devproduct",
        "-d",
        action="append",
        default=[],
        metavar="KEY=ID",
        help=f"Set a Developer Product ID (repeatable). Keys: {', '.join(DEVPRODUCT_KEYS)}",
    )
    sandbox_group = parser.add_mutually_exclusive_group()
    sandbox_group.add_argument(
        "--sandbox",
        dest="sandbox",
        action="store_true",
        default=None,
        help="Enable STUDIO_SANDBOX_PURCHASES = true in GameConfig.luau.",
    )
    sandbox_group.add_argument(
        "--no-sandbox",
        dest="sandbox",
        action="store_false",
        help="Disable STUDIO_SANDBOX_PURCHASES = false in GameConfig.luau for live production publishing.",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        default=RBXLX_OUTPUT_PATH,
        help="Output path for the generated .rbxlx place file (default: AuraBladeRNG.rbxlx).",
    )
    parser.add_argument(
        "--auto-discover",
        action="store_true",
        help=(
            "Auto-discover Universe ID, Place ID, Gamepasses, and DevProducts via Roblox API "
            "(or open https://create.roblox.com/dashboard/credentials via xdg-open if no API key/cookie is set)."
        ),
    )
    parser.add_argument(
        "--publish",
        action="store_true",
        help="Publish the generated .rbxlx file directly to Roblox via Open Cloud API (ROBLOX_API_KEY) or ROBLOSECURITY cookie.",
    )
    parser.add_argument(
        "--universe-id",
        type=int,
        default=int(os.environ.get("ROBLOX_UNIVERSE_ID", "0")) or None,
        help="Roblox Universe ID for Open Cloud publishing (or set ROBLOX_UNIVERSE_ID).",
    )
    parser.add_argument(
        "--place-id",
        type=int,
        default=int(os.environ.get("ROBLOX_PLACE_ID", "0")) or None,
        help="Roblox Place ID for publishing (or set ROBLOX_PLACE_ID).",
    )
    parser.add_argument(
        "--api-key",
        type=str,
        default=os.environ.get("ROBLOX_API_KEY"),
        help="Roblox Open Cloud API Key with universe-places:write permission (or set ROBLOX_API_KEY).",
    )
    parser.add_argument(
        "--cookie",
        type=str,
        default=os.environ.get("ROBLOSECURITY"),
        help="Roblox .ROBLOSECURITY cookie for direct place upload (or set ROBLOSECURITY).",
    )
    parser.add_argument(
        "--version-type",
        choices=["Published", "Saved"],
        default="Published",
        help="Open Cloud versionType query parameter (default: Published).",
    )
    return parser


def main() -> int:
    parser = build_arg_parser()
    args = parser.parse_args()

    gamepasses: Dict[str, int] = {}
    devproducts: Dict[str, int] = {}
    sandbox: Optional[bool] = args.sandbox
    cfg_universe_id: Optional[int] = None
    cfg_place_id: Optional[int] = None

    config_file: Optional[Path] = args.config
    if config_file is None and DEFAULT_MONETIZATION_JSON.exists():
        config_file = DEFAULT_MONETIZATION_JSON

    if config_file is not None:
        if not config_file.exists():
            print(f"[!] Error: Config file not found: {config_file}", file=sys.stderr)
            return 1
        print(f"[*] Loading monetization IDs from {config_file}...")
        gp_json, dp_json, sb_json, cfg_universe_id, cfg_place_id = load_monetization_json(config_file)
        gamepasses.update(gp_json)
        devproducts.update(dp_json)
        if sandbox is None and sb_json is not None:
            sandbox = sb_json

    universe_id = args.universe_id or cfg_universe_id
    place_id = args.place_id or cfg_place_id

    if args.auto_discover:
        print("[*] Running Roblox API auto-discovery...")
        disc_u_id, disc_p_id, disc_gp, disc_dp = auto_discover_roblox_ids(
            universe_id=universe_id,
            place_id=place_id,
            api_key=args.api_key,
            cookie=args.cookie,
        )
        if disc_u_id:
            universe_id = disc_u_id
        if disc_p_id:
            place_id = disc_p_id
        gamepasses.update(disc_gp)
        devproducts.update(disc_dp)
        if disc_u_id or disc_p_id or disc_gp or disc_dp:
            target_json = config_file or DEFAULT_MONETIZATION_JSON
            save_discovered_to_json(target_json, universe_id, place_id, disc_gp, disc_dp)
            print(f"[+] Saved auto-discovered IDs to {target_json}.")

    try:
        gamepasses.update(parse_kv_pairs(args.gamepass, GAMEPASS_KEYS, "Gamepass"))
        devproducts.update(parse_kv_pairs(args.devproduct, DEVPRODUCT_KEYS, "DevProduct"))
    except ValueError as exc:
        print(f"[!] Error: {exc}", file=sys.stderr)
        return 1

    if gamepasses or devproducts or sandbox is not None:
        patched_count = patch_game_config(GAME_CONFIG_PATH, gamepasses, devproducts, sandbox)
        print(f"[+] Patched {GAME_CONFIG_PATH.relative_to(ROOT_DIR)} ({patched_count} field(s) updated).")
    else:
        print(f"[*] Keeping existing IDs in {GAME_CONFIG_PATH.relative_to(ROOT_DIR)}.")

    build_rbxlx(args.output)
    total_items, total_scripts = validate_rbxlx(args.output)
    size_kb = args.output.stat().st_size / 1024.0
    print(
        f"[+] Built & validated {args.output.name} "
        f"({size_kb:.1f} KB, {total_items} XML items, {total_scripts} Luau scripts)."
    )

    if args.publish:
        api_key = args.api_key
        cookie = args.cookie

        if place_id and not universe_id and api_key:
            # Try quick Universe ID resolution from Place ID before failing
            disc_u_id, _, _, _ = auto_discover_roblox_ids(
                universe_id=None, place_id=place_id, api_key=api_key, cookie=cookie
            )
            universe_id = disc_u_id

        if api_key:
            if not universe_id or not place_id:
                print(
                    "[!] Error: Open Cloud --publish requires --universe-id and --place-id "
                    "(or ROBLOX_UNIVERSE_ID / ROBLOX_PLACE_ID env vars, or universe_id / place_id in monetization_ids.json).",
                    file=sys.stderr,
                )
                return 1
            print(
                f"[*] Publishing {args.output.name} to Roblox Open Cloud "
                f"(universe_id={universe_id}, place_id={place_id}, versionType={args.version_type})..."
            )
            try:
                response_body = publish_to_open_cloud(
                    rbxlx_path=args.output,
                    universe_id=universe_id,
                    place_id=place_id,
                    api_key=api_key,
                    version_type=args.version_type,
                )
                print(f"[+] Successfully published to Roblox Open Cloud! Response: {response_body}")
            except RuntimeError as exc:
                print(f"[!] Publish failed: {exc}", file=sys.stderr)
                return 1
        elif cookie:
            if not place_id:
                print(
                    "[!] Error: Cookie --publish requires --place-id "
                    "(or ROBLOX_PLACE_ID env var, or place_id in monetization_ids.json).",
                    file=sys.stderr,
                )
                return 1
            print(f"[*] Publishing {args.output.name} via ROBLOSECURITY cookie (place_id={place_id})...")
            try:
                response_body = publish_with_cookie(
                    rbxlx_path=args.output,
                    place_id=place_id,
                    cookie=cookie,
                )
                print(f"[+] Successfully uploaded to Roblox! Response: {response_body}")
            except RuntimeError as exc:
                print(f"[!] Cookie publish failed: {exc}", file=sys.stderr)
                return 1
        else:
            print(
                "[!] Error: --publish requires either --api-key (ROBLOX_API_KEY) or --cookie (ROBLOSECURITY).",
                file=sys.stderr,
            )
            open_credentials_dashboard()
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
