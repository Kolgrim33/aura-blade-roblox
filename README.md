# ⚔️ AURA BLADE: RNG & BOSS ARENA (Roblox Monetized Place & Rojo Project)

A complete, production-ready, zero-external-asset **Roblox Luau Game** engineered for maximum **Session Time**, **D1/D7 Retention**, **Engagement-Based Payouts (EBP)**, and **Robux Conversion (Gamepasses + Repeatable Developer Products)**.

You can open **`AuraBladeRNG.rbxlx`** directly in Roblox Studio (or sync via [Rojo](https://rojo.space/) using `default.project.json`) and press **Play** immediately — the entire 3D Neon Cyber Arena, Sky Obby Course, VIP Sanctum, Boss Colosseum, Character 3D Katanas/Orbiting Auras, and Cyberpunk HUD are generated procedurally on startup!

---

## 💰 Why This Game Architecture Prints Robux

1. **Dual-Core Gameplay Loop (AFK RNG + Active Arena Bosses):**
   - **Loop 1 (Aura & Blade Rolling):** 16 tiered Auras & Cyber Katanas ranging from *Cyber Spark (1 in 2)* to *CHRONO SOVEREIGN (1 in 1,000,000)* with deterministic Pity (guaranteed Epic every 50 rolls, Legendary every 250 rolls), procedural 3D orbiting neon shards, particle emitters, and full-screen Mythic cutscenes + server-wide announcements.
   - **Loop 2 (Active Boss Colosseum & Sky Obby):** Equipped Auras grant real combat stats (`BaseDamage`, `CoinMultiplier`, `WalkSpeed`). Players slash & dash (`Click` / `[F]` / `[Q]`) against scaling Cyber Bosses in the center Colosseum for Flux Coins, Luck Gems, and Free Fast-Roll Tokens, or run the 12-stage **Neon Sky Obby** for a **5-minute `2x Luck` buff**!
2. **6 High-Converting Gamepasses (`MarketplaceService`):**
   - `2x Luck Forever` (199 R$)
   - `Fast Roll + Skip Cutscene` (149 R$)
   - `Auto-Roll + AFK Guard` (99 R$)
   - `Triple Roll (3x At Once)` (399 R$)
   - `VIP Cyber Sovereign` (499 R$ — +50% Coins, +25% Base Luck, Golden Crown, VIP Fountain access)
   - `+100 Aura Vault Slots` (129 R$)
3. **6 Repeatable Whale / Impulse Developer Products (`ProcessReceipt` Idempotent):**
   - `2x Server Luck Party (15m)` (99 R$ — boosts the entire server & announces the sponsor's name!)
   - `Singularity Luck Potion (+500% Next Roll)` (49 R$)
   - `Summon Omega Mech Boss (3x Loot)` (79 R$)
   - `1,500 / 6,000 / 25,000 Luck Gems` bundles (49 / 169 / 599 R$)
4. **Built-In Viral & EBP Loops:**
   - **Roblox Premium Subscriber Bonus:** Automatic `+25% Passive Luck` and `+20% Flux Coins` to maximize Roblox Engagement-Based Payouts.
   - **Friend Invite Multiplier:** `+10% Base Luck` per friend in the same server (up to `+50%`).
   - **7-Day Login Streak & Promo Codes:** `RELEASE`, `OMEGA2026`, `LUCKY777`, `CYBERBLADE`.

---

## 🚀 Quick Start (2 Ways to Open & Publish)

### Option A: Open `AuraBladeRNG.rbxlx` Directly in Roblox Studio
1. Open **`AuraBladeRNG.rbxlx`** in Roblox Studio (on Linux via [Vinegar](https://vinegarhq.org/) or on Windows/macOS).
2. Click **Play (F5)** — `STUDIO_SANDBOX_PURCHASES = true` is enabled by default in [`src/shared/GameConfig.luau`](./src/shared/GameConfig.luau), allowing you to test buying every Gamepass and Developer Product for free inside Studio!
3. When publishing to Roblox:
   - Go to **File -> Publish to Roblox** and enable **Security -> Enable Studio Access to API Services** (for `DataStoreService`).
   - Create your 6 Gamepasses and 6 Developer Products in the Roblox Creator Dashboard, paste their IDs into `GameConfig.Gamepasses` and `GameConfig.DevProducts` in `ReplicatedStorage.Shared.GameConfig`, and set `STUDIO_SANDBOX_PURCHASES = false`.

### Option B: Live Sync with Rojo
```bash
rojo serve default.project.json
# Or build the standalone place file:
rojo build default.project.json -o AuraBladeRNG.rbxlx
```
