#!/usr/bin/env python3
"""
publish_roblox.py — Build, Patch Monetization IDs, and Publish AuraBladeRNG.rbxlx

Features:
  1. Reads Gamepass IDs & Developer Product IDs from CLI flags or monetization_ids.json
     and patches src/shared/GameConfig.luau automatically.
  2. Rebuilds the standalone AuraBladeRNG.rbxlx XML place file from src/**/*.luau
     and validates the resulting XML with xml.etree.ElementTree.
  3. Optionally publishes AuraBladeRNG.rbxlx directly to Roblox via the Roblox Open Cloud
     Place Publishing API:
       POST https://apis.roblox.com/universes/v1/{universe_id}/places/{place_id}/versions?versionType=Published
     using the x-api-key header (or ROBLOX_API_KEY env var) — no Roblox Studio required!

Usage examples:
  # Rebuild AuraBladeRNG.rbxlx (picks up monetization_ids.json if present):
  python3 scripts/publish_roblox.py

  # Patch specific Gamepasses / DevProducts from CLI and disable Studio Sandbox mode:
  python3 scripts/publish_roblox.py --no-sandbox \
      --gamepass DoubleLuck=812345601 --gamepass VIP=812345605 \
      --devproduct ServerLuckBoost=912345601

  # Publish directly to Roblox via Open Cloud API:
  ROBLOX_API_KEY="your_open_cloud_key" python3 scripts/publish_roblox.py \
      --publish --universe-id 123456789 --place-id 987654321 --no-sandbox
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, Optional, Tuple

ROOT_DIR = Path(__file__).resolve().parent.parent
GAME_CONFIG_PATH = ROOT_DIR / "src" / "shared" / "GameConfig.luau"
RBXLX_OUTPUT_PATH = ROOT_DIR / "AuraBladeRNG.rbxlx"
DEFAULT_MONETIZATION_JSON = ROOT_DIR / "monetization_ids.json"

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


def parse_kv_pairs(pairs: list[str], valid_keys: list[str], label: str) -> Dict[str, int]:
    result: Dict[str, int] = {}
    for item in pairs:
        if "=" not in item:
            raise ValueError(f"Invalid {label} argument '{item}'. Expected format KEY=ID (e.g. {valid_keys[0]}=12345678).")
        key, val_str = item.split("=", 1)
        key = key.strip()
        if key not in valid_keys:
            raise ValueError(f"Unknown {label} key '{key}'. Valid keys: {', '.join(valid_keys)}")
        try:
            result[key] = int(val_str.strip())
        except ValueError as exc:
            raise ValueError(f"Invalid integer ID '{val_str}' for {label} '{key}'.") from exc
    return result


def load_monetization_json(path: Path) -> Tuple[Dict[str, int], Dict[str, int], Optional[bool], Optional[int], Optional[int]]:
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
            raise RuntimeError(f"Could not locate entry for Key = \"{key}\" in {config_path}")
        if new_source != source:
            source = new_source
            changes += count

    if changes > 0:
        config_path.write_text(source, encoding="utf-8")
    return changes


def cdata_wrap(script_source: str) -> str:
    # Escape any accidental ]]> sequences safely inside CDATA
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
            "x-api-key": api_key,
            "Content-Type": "application/xml",
            "Accept": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return body
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"Roblox Open Cloud API returned HTTP {exc.code} {exc.reason}: {err_body}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Network error contacting Roblox Open Cloud API: {exc.reason}") from exc


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Patch GameConfig.luau monetization IDs, rebuild AuraBladeRNG.rbxlx, and optionally publish via Roblox Open Cloud API."
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
        "--publish",
        action="store_true",
        help="Publish the generated .rbxlx file directly to Roblox via the Open Cloud Place Publishing API.",
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
        help="Roblox Place ID for Open Cloud publishing (or set ROBLOX_PLACE_ID).",
    )
    parser.add_argument(
        "--api-key",
        type=str,
        default=os.environ.get("ROBLOX_API_KEY"),
        help="Roblox Open Cloud API Key with universe-places:write permission (or set ROBLOX_API_KEY).",
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
        universe_id = args.universe_id or cfg_universe_id
        place_id = args.place_id or cfg_place_id
        api_key = args.api_key

        if not universe_id or not place_id:
            print(
                "[!] Error: --publish requires --universe-id and --place-id "
                "(or ROBLOX_UNIVERSE_ID / ROBLOX_PLACE_ID env vars, or universe_id / place_id in monetization_ids.json).",
                file=sys.stderr,
            )
            return 1
        if not api_key:
            print(
                "[!] Error: --publish requires --api-key (or ROBLOX_API_KEY env var).",
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
            print(f"[+] Successfully published to Roblox! Response: {response_body}")
        except RuntimeError as exc:
            print(f"[!] Publish failed: {exc}", file=sys.stderr)
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
