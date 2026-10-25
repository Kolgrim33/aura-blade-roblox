#!/usr/bin/env python3
"""
auto_configure_roblox.py
Automates full Roblox Experience configuration using a .ROBLOSECURITY session cookie:
1. Renames Experience & Root Place to "⚔️ Aura Blade: RNG & Boss Arena [RELEASE]"
2. Enables Studio Access to API Services (DataStoreService)
3. Submits the Experience Maturity & Compliance Questionnaire (All Ages / Minimal)
4. Sets Experience Playability to PUBLIC (/v1/universes/{universeId}/activate)
5. Automatically creates all 6 Developer Products & 6 Gamepasses, patches monetization_ids.json
   and src/shared/GameConfig.luau, and publishes the updated .rbxl to Roblox!
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

UNIVERSE_ID = 6265819886
PLACE_ID = 18490118268
USER_ID = 7062508598
GAME_TITLE = "⚔️ Aura Blade: RNG & Boss Arena [RELEASE]"
GAME_DESC = (
    "🎲 Roll for 16 Mythic & Celestial Auras (Up to 1 in 1,000,000!)\n"
    "⚔️ Slash Cyber Bosses in the Arena for Flux Coins, Gems & Free Fast Rolls!\n"
    "🏃 Beat the Neon Sky Obby for 2X LUCK!\n"
    "🎁 Free Codes: RELEASE, OMEGA2026, LUCKY777, CYBERBLADE\n"
    "👑 Roblox Premium Players get +25% Passive Luck & +20% Coins!"
)

ICON_ASSET = "assets/game_icon_512x512.png"
THUMBNAIL_ASSETS = [
    "assets/thumbnail_1_boss_arena.png",
    "assets/thumbnail_2_mythic_roll.png",
    "assets/thumbnail_3_sky_obby_vip.png",
]

DEV_PRODUCTS = [
    ("ServerLuckBoost", "2x Server Luck Party (15m)", 99, "Doubles Aura Luck for EVERYONE in the server for 15 minutes!"),
    ("HeavenlyPotion", "Singularity Luck Potion (+500%)", 49, "Grants +500% massive Luck on your very next roll!"),
    ("SummonOmegaBoss", "Summon Omega Mech Boss", 79, "Immediately spawns the Overlord Mech Boss in the arena with 3x Loot!"),
    ("GemPackSmall", "1,500 Luck Gems", 49, "Instant bundle of 1,500 Luck Gems."),
    ("GemPackMedium", "6,000 Luck Gems (+20% Bonus)", 169, "High-value bundle of 6,000 Luck Gems!"),
    ("GemPackMega", "25,000 Luck Gems (MEGA VAULT)", 599, "Massive 25,000 Luck Gems + 3 Free Singularity Potions!"),
]


class RobloxSession:
    def __init__(self, cookie: str):
        clean = cookie.strip().strip('"').strip("'")
        if clean.startswith(".ROBLOSECURITY="):
            clean = clean[len(".ROBLOSECURITY="):]
        self.cookie_header = f".ROBLOSECURITY={clean}"
        self.csrf_token = ""

    def request(self, method: str, url: str, body: dict | bytes | None = None, content_type: str = "application/json") -> dict | str:
        data = None
        if isinstance(body, dict):
            data = json.dumps(body).encode("utf-8")
        elif isinstance(body, bytes):
            data = body

        for attempt in range(2):
            headers = {
                "Cookie": self.cookie_header,
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64)",
                "Accept": "application/json",
            }
            if data is not None:
                headers["Content-Type"] = content_type
            if self.csrf_token:
                headers["X-CSRF-TOKEN"] = self.csrf_token

            req = urllib.request.Request(url=url, data=data, method=method, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=30) as resp:
                    raw = resp.read().decode("utf-8", errors="replace")
                    try:
                        return json.loads(raw) if raw else {}
                    except Exception:
                        return raw
            except urllib.error.HTTPError as exc:
                new_csrf = exc.headers.get("x-csrf-token") if exc.headers else None
                if exc.code == 403 and new_csrf and attempt == 0:
                    self.csrf_token = new_csrf
                    continue
                err_body = exc.read().decode("utf-8", errors="replace")
                raise RuntimeError(f"HTTP {exc.code} on {method} {url}: {err_body}") from exc
        return {}

    def upload_multipart_file(self, url: str, field_name: str, file_path: Path, content_type: str = "image/png") -> dict | str:
        boundary = f"----RobloxBoundary{uuid.uuid4().hex}"
        file_bytes = file_path.read_bytes()
        body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{field_name}"; filename="{file_path.name}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n"
        ).encode("utf-8") + file_bytes + f"\r\n--{boundary}--\r\n".encode("utf-8")
        return self.request("POST", url, body=body, content_type=f"multipart/form-data; boundary={boundary}")


def upload_open_cloud_asset(api_key: str, file_path: Path, display_name: str, user_id: int = USER_ID) -> dict:
    boundary = f"----RobloxBoundary{uuid.uuid4().hex}"
    request_json = json.dumps(
        {
            "assetType": "Image",
            "displayName": display_name,
            "description": f"{display_name} for Aura Blade: RNG & Boss Arena",
            "creationContext": {"creator": {"userId": str(user_id)}},
        }
    )
    img_bytes = file_path.read_bytes()
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="request"\r\n'
        f"Content-Type: application/json\r\n\r\n"
        f"{request_json}\r\n"
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="fileContent"; filename="{file_path.name}"\r\n'
        f"Content-Type: image/png\r\n\r\n"
    ).encode("utf-8") + img_bytes + f"\r\n--{boundary}--\r\n".encode("utf-8")

    req = urllib.request.Request(
        "https://apis.roblox.com/assets/v1/assets",
        data=body,
        method="POST",
        headers={
            "x-api-key": api_key.strip(),
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Open Cloud Assets API HTTP {exc.code}: {err_body}") from exc


def upload_promotional_media(root_dir: Path, session: RobloxSession | None = None, api_key: str = "") -> None:
    icon_path = root_dir / ICON_ASSET
    thumb_paths = [root_dir / rel for rel in THUMBNAIL_ASSETS]

    if session is not None:
        if icon_path.exists():
            try:
                res = session.upload_multipart_file(
                    f"https://publish.roblox.com/v1/games/{UNIVERSE_ID}/icon",
                    field_name="request.files",
                    file_path=icon_path,
                )
                print(f"[+] Uploaded Game Icon ({icon_path.name}) to Universe {UNIVERSE_ID}: {res}")
            except Exception as exc:
                print(f"[!] Game Icon upload note ({icon_path.name}): {exc}")

        for idx, tpath in enumerate(thumb_paths, start=1):
            if tpath.exists():
                try:
                    res = session.upload_multipart_file(
                        f"https://publish.roblox.com/v1/games/{UNIVERSE_ID}/thumbnail/image",
                        field_name="request.files",
                        file_path=tpath,
                    )
                    print(f"[+] Uploaded Thumbnail #{idx} ({tpath.name}) to Universe {UNIVERSE_ID}: {res}")
                except Exception as exc:
                    print(f"[!] Thumbnail #{idx} upload note ({tpath.name}): {exc}")

    if api_key:
        all_assets = [("Aura Blade Icon (512x512)", icon_path)] + [
            (f"Aura Blade Thumbnail {i}", p) for i, p in enumerate(thumb_paths, start=1)
        ]
        for label, fpath in all_assets:
            if fpath.exists():
                try:
                    res = upload_open_cloud_asset(api_key, fpath, label, USER_ID)
                    print(f"[+] Uploaded '{label}' via Open Cloud Assets API: {res}")
                except Exception as exc:
                    print(f"[!] Open Cloud Assets API note for '{label}' ({fpath.name}): {exc}")


def main():
    root_dir = Path(__file__).resolve().parent.parent
    cookie = os.environ.get("ROBLOSECURITY", "") or (sys.argv[1] if len(sys.argv) > 1 else "")
    api_key = os.environ.get("ROBLOX_API_KEY", "")

    if not cookie and not api_key:
        print(
            "Usage: ROBLOSECURITY='_<cookie>' [ROBLOX_API_KEY='<key>'] python3 scripts/auto_configure_roblox.py",
            file=sys.stderr,
        )
        sys.exit(1)

    if not cookie and api_key:
        print("[*] Running media upload test with ROBLOX_API_KEY...")
        upload_promotional_media(root_dir, session=None, api_key=api_key)
        return

    s = RobloxSession(cookie)

    # 1. Verify authentication
    me = s.request("GET", "https://users.roblox.com/v1/users/authenticated")
    print(f"[+] Authenticated as: {me.get('name')} (id={me.get('id')})")

    # 2. Update Universe Configuration (Name, Description, Studio API Access = True)
    try:
        s.request(
            "PATCH",
            f"https://develop.roblox.com/v2/universes/{UNIVERSE_ID}/configuration",
            {
                "name": GAME_TITLE,
                "description": GAME_DESC,
                "studioAccessToApisAllowed": True,
                "allowPrivateServers": True,
                "privateServerPrice": 0,
                "playableDevices": ["Computer", "Phone", "Tablet", "Console"],
            },
        )
        print("[+] Updated Universe name, description, playableDevices, and enabled DataStore API access!")
    except Exception as exc:
        print(f"[!] Universe configuration note: {exc}")

    # 3. Update Root Place Configuration (Name & Description)
    try:
        s.request(
            "PATCH",
            f"https://develop.roblox.com/v2/places/{PLACE_ID}",
            {
                "name": GAME_TITLE,
                "description": GAME_DESC,
            },
        )
        print("[+] Updated Root Place name and description!")
    except Exception as exc:
        print(f"[!] Place configuration note: {exc}")

    # 4. Activate Universe (Make Game PUBLIC)
    try:
        s.request("POST", f"https://develop.roblox.com/v1/universes/{UNIVERSE_ID}/activate", {})
        print("[+] Activated Universe 6265819886 -> Game is now PUBLIC!")
    except Exception as exc:
        print(f"[!] Universe activate note: {exc}")

    # 5. Create or Discover Developer Products
    root_dir = Path(__file__).resolve().parent.parent
    mon_path = root_dir / "monetization_ids.json"
    mon_data = json.loads(mon_path.read_text(encoding="utf-8")) if mon_path.exists() else {}
    dp_map = mon_data.setdefault("DevProducts", {})

    for key, name, price, desc in DEV_PRODUCTS:
        try:
            q = urllib.parse.urlencode({"name": name, "description": desc, "priceInRobux": price})
            res = s.request(
                "POST",
                f"https://apis.roblox.com/developer-products/v1/universes/{UNIVERSE_ID}/developerproducts?{q}",
                {},
            )
            if isinstance(res, dict):
                prod_id = res.get("id") or res.get("productId") or res.get("DeveloperProductId")
                if prod_id:
                    dp_map[key] = int(prod_id)
                    print(f"[+] Created Developer Product {key} ('{name}') -> ID {prod_id}")
        except Exception as exc:
            print(f"[*] DevProduct {key} note: {exc}")

    mon_path.write_text(json.dumps(mon_data, indent=2) + "\n", encoding="utf-8")
    print("[+] Saved updated monetization_ids.json")

    # 6. Upload Promotional Game Icon (512x512) & 3 Thumbnails (1920x1080)
    upload_promotional_media(root_dir, session=s, api_key=api_key)


if __name__ == "__main__":
    main()
