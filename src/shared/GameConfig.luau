--!strict
--[[
	GameConfig.luau
	Central configuration for AURA BLADE: RNG & BOSS ARENA.
	Defines all 16 Aura/Blade tiers, Gamepasses, Developer Products,
	Rebirth milestones, Boss waves, Daily Rewards, and Promo Codes.
]]

export type AuraDefinition = {
	Id: string,
	Name: string,
	Tier: string,
	OneIn: number, -- 1 in X odds
	Weight: number,
	PrimaryColor: Color3,
	SecondaryColor: Color3,
	BaseDamage: number,
	CoinMultiplier: number,
	SpeedBonus: number,
	OrbitOrbs: number,
	HasCutscene: boolean,
	ServerAnnounce: boolean,
	Description: string,
}

export type GamepassInfo = {
	Key: string,
	Id: number, -- Replace with real Roblox Gamepass ID on publish
	Name: string,
	RobuxPrice: number,
	IconText: string,
	AccentColor: Color3,
	Description: string,
}

export type DevProductInfo = {
	Key: string,
	Id: number, -- Replace with real Roblox Developer Product ID on publish
	Name: string,
	RobuxPrice: number,
	AccentColor: Color3,
	Description: string,
}

export type RebirthTier = {
	Level: number,
	CoinCost: number,
	RequiredAuraOneIn: number,
	PermanentLuckBonus: number, -- e.g. 0.5 = +50% base luck
	PermanentCoinMultiplier: number,
	BonusInventorySlots: number,
	Title: string,
}

export type BossDefinition = {
	Id: string,
	Name: string,
	MaxHP: number,
	DamagePerPulse: number,
	AttackInterval: number,
	RewardCoins: number,
	RewardGems: number,
	RewardFastRolls: number,
	PrimaryColor: Color3,
	Scale: number,
}

local GameConfig = {}

-- Enable Studio Sandbox Purchases so you can test all Gamepasses & DevProducts
-- in Roblox Studio before replacing placeholder IDs with live asset IDs.
GameConfig.STUDIO_SANDBOX_PURCHASES = false

-- Core Economy & Pity Tuning
GameConfig.BASE_ROLL_COOLDOWN = 1.65
GameConfig.FAST_ROLL_COOLDOWN = 0.55
GameConfig.BASE_INVENTORY_SLOTS = 24
GameConfig.EPIC_PITY_THRESHOLD = 50
GameConfig.LEGENDARY_PITY_THRESHOLD = 250
GameConfig.PREMIUM_LUCK_BONUS = 0.25 -- +25% Luck for Roblox Premium (drives Engagement Payouts!)
GameConfig.PREMIUM_COIN_MULTIPLIER = 1.20
GameConfig.FRIEND_LUCK_BONUS_PER_FRIEND = 0.10 -- +10% Luck per friend in server (max +50%)
GameConfig.MAX_FRIEND_LUCK_BONUS = 0.50
GameConfig.OBBY_BUFF_DURATION = 300 -- 5 minutes of +100% Luck from completing the Sky Obby
GameConfig.OBBY_LUCK_BONUS = 1.00
GameConfig.VIP_FOUNTAIN_LUCK_BONUS = 0.35

-- 16 Tiered Auras & Cyber Blades (Ordered from Common to Celestial)
GameConfig.Auras = {
	{
		Id = "cyber_spark",
		Name = "Cyber Spark",
		Tier = "Common",
		OneIn = 2,
		Weight = 500000,
		PrimaryColor = Color3.fromRGB(160, 175, 195),
		SecondaryColor = Color3.fromRGB(95, 110, 130),
		BaseDamage = 12,
		CoinMultiplier = 1.0,
		SpeedBonus = 0,
		OrbitOrbs = 1,
		HasCutscene = false,
		ServerAnnounce = false,
		Description = "A flickering static blade forged from starter neon conduits.",
	},
	{
		Id = "neon_pulse",
		Name = "Neon Pulse",
		Tier = "Common",
		OneIn = 5,
		Weight = 200000,
		PrimaryColor = Color3.fromRGB(0, 210, 255),
		SecondaryColor = Color3.fromRGB(0, 110, 200),
		BaseDamage = 18,
		CoinMultiplier = 1.25,
		SpeedBonus = 1,
		OrbitOrbs = 1,
		HasCutscene = false,
		ServerAnnounce = false,
		Description = "Streams of high-frequency cyan plasma hum along the katana edge.",
	},
	{
		Id = "emerald_circuit",
		Name = "Emerald Circuit",
		Tier = "Uncommon",
		OneIn = 12,
		Weight = 83333,
		PrimaryColor = Color3.fromRGB(40, 255, 130),
		SecondaryColor = Color3.fromRGB(10, 150, 75),
		BaseDamage = 26,
		CoinMultiplier = 1.6,
		SpeedBonus = 2,
		OrbitOrbs = 2,
		HasCutscene = false,
		ServerAnnounce = false,
		Description = "Overclocked bio-silicon runes orbit the wielder in twin rings.",
	},
	{
		Id = "cobalt_overdrive",
		Name = "Cobalt Overdrive",
		Tier = "Uncommon",
		OneIn = 30,
		Weight = 33333,
		PrimaryColor = Color3.fromRGB(55, 120, 255),
		SecondaryColor = Color3.fromRGB(120, 180, 255),
		BaseDamage = 38,
		CoinMultiplier = 2.1,
		SpeedBonus = 3,
		OrbitOrbs = 2,
		HasCutscene = false,
		ServerAnnounce = false,
		Description = "Magnetic turbine cores accelerate every slash.",
	},
	{
		Id = "crimson_blitz",
		Name = "Crimson Blitz",
		Tier = "Rare",
		OneIn = 75,
		Weight = 13333,
		PrimaryColor = Color3.fromRGB(255, 50, 80),
		SecondaryColor = Color3.fromRGB(160, 15, 35),
		BaseDamage = 55,
		CoinMultiplier = 3.0,
		SpeedBonus = 4,
		OrbitOrbs = 3,
		HasCutscene = false,
		ServerAnnounce = false,
		Description = "High-voltage crimson laser edge that scorches arena targets.",
	},
	{
		Id = "amethyst_phantom",
		Name = "Amethyst Phantom",
		Tier = "Rare",
		OneIn = 200,
		Weight = 5000,
		PrimaryColor = Color3.fromRGB(185, 70, 255),
		SecondaryColor = Color3.fromRGB(95, 25, 165),
		BaseDamage = 80,
		CoinMultiplier = 4.2,
		SpeedBonus = 5,
		OrbitOrbs = 3,
		HasCutscene = false,
		ServerAnnounce = false,
		Description = "Phase-shifted violet phantoms echo each strike.",
	},
	{
		Id = "solar_flare",
		Name = "Solar Flare",
		Tier = "Epic",
		OneIn = 500,
		Weight = 2000,
		PrimaryColor = Color3.fromRGB(255, 185, 35),
		SecondaryColor = Color3.fromRGB(255, 95, 15),
		BaseDamage = 120,
		CoinMultiplier = 6.0,
		SpeedBonus = 6,
		OrbitOrbs = 4,
		HasCutscene = false,
		ServerAnnounce = false,
		Description = "Radiant helios corona burning at ten thousand degrees.",
	},
	{
		Id = "frostbite_zero",
		Name = "Frostbite Zero",
		Tier = "Epic",
		OneIn = 1250,
		Weight = 800,
		PrimaryColor = Color3.fromRGB(135, 245, 255),
		SecondaryColor = Color3.fromRGB(45, 155, 255),
		BaseDamage = 175,
		CoinMultiplier = 8.5,
		SpeedBonus = 7,
		OrbitOrbs = 4,
		HasCutscene = false,
		ServerAnnounce = false,
		Description = "Absolute-zero cryo shards crystallize the air around you.",
	},
	{
		Id = "void_reaper",
		Name = "Void Reaper",
		Tier = "Legendary",
		OneIn = 3500,
		Weight = 285,
		PrimaryColor = Color3.fromRGB(130, 30, 220),
		SecondaryColor = Color3.fromRGB(255, 45, 165),
		BaseDamage = 260,
		CoinMultiplier = 13.0,
		SpeedBonus = 8,
		OrbitOrbs = 5,
		HasCutscene = true,
		ServerAnnounce = false,
		Description = "Cuts rifts through subspace, drawing dark matter into its wake.",
	},
	{
		Id = "starlight_valkyrie",
		Name = "Starlight Valkyrie",
		Tier = "Legendary",
		OneIn = 10000,
		Weight = 100,
		PrimaryColor = Color3.fromRGB(255, 235, 130),
		SecondaryColor = Color3.fromRGB(120, 220, 255),
		BaseDamage = 400,
		CoinMultiplier = 20.0,
		SpeedBonus = 10,
		OrbitOrbs = 6,
		HasCutscene = true,
		ServerAnnounce = true,
		Description = "Astral wings andsix star-forged lances command the arena.",
	},
	{
		Id = "abyssal_leviathan",
		Name = "Abyssal Leviathan",
		Tier = "Mythic",
		OneIn = 25000,
		Weight = 40,
		PrimaryColor = Color3.fromRGB(0, 255, 195),
		SecondaryColor = Color3.fromRGB(10, 45, 120),
		BaseDamage = 620,
		CoinMultiplier = 32.0,
		SpeedBonus = 12,
		OrbitOrbs = 6,
		HasCutscene = true,
		ServerAnnounce = true,
		Description = "Tidal maelstrom of bioluminescent deep-trench energy.",
	},
	{
		Id = "bloodmoon_shogun",
		Name = "Bloodmoon Shogun",
		Tier = "Mythic",
		OneIn = 65000,
		Weight = 15,
		PrimaryColor = Color3.fromRGB(255, 25, 55),
		SecondaryColor = Color3.fromRGB(30, 5, 15),
		BaseDamage = 950,
		CoinMultiplier = 50.0,
		SpeedBonus = 14,
		OrbitOrbs = 7,
		HasCutscene = true,
		ServerAnnounce = true,
		Description = "Ancient eclipse odachi wreathed in crimson lightning.",
	},
	{
		Id = "omega_singularity",
		Name = "OMEGA SINGULARITY",
		Tier = "Mythic",
		OneIn = 150000,
		Weight = 7,
		PrimaryColor = Color3.fromRGB(255, 120, 0),
		SecondaryColor = Color3.fromRGB(160, 0, 255),
		BaseDamage = 1450,
		CoinMultiplier = 80.0,
		SpeedBonus = 16,
		OrbitOrbs = 8,
		HasCutscene = true,
		ServerAnnounce = true,
		Description = "A collapsing event horizon bound inside a hyper-dimensional blade.",
	},
	{
		Id = "seraphim_genesis",
		Name = "SERAPHIM: GENESIS",
		Tier = "Celestial",
		OneIn = 400000,
		Weight = 3,
		PrimaryColor = Color3.fromRGB(255, 250, 200),
		SecondaryColor = Color3.fromRGB(255, 180, 60),
		BaseDamage = 2200,
		CoinMultiplier = 135.0,
		SpeedBonus = 18,
		OrbitOrbs = 9,
		HasCutscene = true,
		ServerAnnounce = true,
		Description = "Nine interlocking golden halos rain judgement across the colosseum.",
	},
	{
		Id = "hyperion_archon",
		Name = "HYPERION ARCHON",
		Tier = "Celestial",
		OneIn = 750000,
		Weight = 2,
		PrimaryColor = Color3.fromRGB(80, 255, 255),
		SecondaryColor = Color3.fromRGB(255, 60, 220),
		BaseDamage = 3200,
		CoinMultiplier = 210.0,
		SpeedBonus = 20,
		OrbitOrbs = 10,
		HasCutscene = true,
		ServerAnnounce = true,
		Description = "Twin quasars bends spacetime with every heartbeat.",
	},
	{
		Id = "chrono_sovereign",
		Name = "CHRONO SOVEREIGN",
		Tier = "Celestial",
		OneIn = 1000000,
		Weight = 1,
		PrimaryColor = Color3.fromRGB(255, 255, 255),
		SecondaryColor = Color3.fromRGB(0, 240, 255),
		BaseDamage = 5000,
		CoinMultiplier = 350.0,
		SpeedBonus = 24,
		OrbitOrbs = 12,
		HasCutscene = true,
		ServerAnnounce = true,
		Description = "1 IN 1,000,000. Master of past, present, and eternity.",
	},
} :: { AuraDefinition }

-- 6 High-Converting Gamepasses
GameConfig.Gamepasses = {
	{
		Key = "DoubleLuck",
		Id = 100000001,
		Name = "2x Luck Forever",
		RobuxPrice = 199,
		IconText = "2X LUCK",
		AccentColor = Color3.fromRGB(45, 255, 130),
		Description = "Permanently doubles your total Aura Roll Luck across all rolls!",
	},
	{
		Key = "FastRoll",
		Id = 100000002,
		Name = "Fast Roll + Skip Cutscene",
		RobuxPrice = 149,
		IconText = "FAST",
		AccentColor = Color3.fromRGB(0, 215, 255),
		Description = "Cuts roll cooldown by 67% (1.65s -> 0.55s) for rapid-fire rolling!",
	},
	{
		Key = "AutoRoll",
		Id = 100000003,
		Name = "Auto-Roll + AFK Guard",
		RobuxPrice = 99,
		IconText = "AUTO",
		AccentColor = Color3.fromRGB(185, 85, 255),
		Description = "Automatically rolls continuously hands-free and keeps your best Auras!",
	},
	{
		Key = "TripleRoll",
		Id = 100000004,
		Name = "Triple Roll (3x At Once)",
		RobuxPrice = 399,
		IconText = "3X ROLL",
		AccentColor = Color3.fromRGB(255, 180, 30),
		Description = "Roll 3 Auras simultaneously on every single click and keep the rarest!",
	},
	{
		Key = "VIP",
		Id = 100000005,
		Name = "VIP Cyber Sovereign",
		RobuxPrice = 499,
		IconText = "VIP",
		AccentColor = Color3.fromRGB(255, 215, 50),
		Description = "+50% Flux Coins, +25% Base Luck, Golden Overhead Crown, & VIP Lounge Access!",
	},
	{
		Key = "ExtraStorage",
		Id = 100000006,
		Name = "+100 Aura Vault Slots",
		RobuxPrice = 129,
		IconText = "+100 BAG",
		AccentColor = Color3.fromRGB(255, 80, 145),
		Description = "Expands your Aura & Blade inventory capacity by +100 permanent slots!",
	},
} :: { GamepassInfo }

-- 6 Repeatable Developer Products (Whale & Impulse Spend Drivers)
GameConfig.DevProducts = {
	{
		Key = "ServerLuckBoost",
		Id = 200000001,
		Name = "2x Server Luck Party (15m)",
		RobuxPrice = 99,
		AccentColor = Color3.fromRGB(50, 255, 160),
		Description = "Doubles Aura Luck for EVERYONE in the server for 15 minutes + announces your name!",
	},
	{
		Key = "HeavenlyPotion",
		Id = 200000002,
		Name = "Singularity Luck Potion (+500%)",
		RobuxPrice = 49,
		AccentColor = Color3.fromRGB(200, 90, 255),
		Description = "Grants +500% massive Luck on your very next roll (stacks with 2x Luck)!",
	},
	{
		Key = "SummonOmegaBoss",
		Id = 200000003,
		Name = "Summon Omega Mech Boss",
		RobuxPrice = 79,
		AccentColor = Color3.fromRGB(255, 65, 85),
		Description = "Immediately spawns the Overlord Mech Boss in the arena with 3x Gem & Coin loot!",
	},
	{
		Key = "GemPackSmall",
		Id = 200000004,
		Name = "1,500 Luck Gems",
		RobuxPrice = 49,
		AccentColor = Color3.fromRGB(0, 200, 255),
		Description = "Instant bundle of 1,500 Luck Gems for potions & upgrades.",
	},
	{
		Key = "GemPackMedium",
		Id = 200000005,
		Name = "6,000 Luck Gems (+20% Bonus)",
		RobuxPrice = 169,
		AccentColor = Color3.fromRGB(95, 140, 255),
		Description = "High-value bundle of 6,000 Luck Gems!",
	},
	{
		Key = "GemPackMega",
		Id = 200000006,
		Name = "25,000 Luck Gems (MEGA VAULT)",
		RobuxPrice = 599,
		AccentColor = Color3.fromRGB(255, 200, 40),
		Description = "Massive 25,000 Luck Gems + 3 Free Singularity Potions!",
	},
} :: { DevProductInfo }

-- Gem Shop (F2P & P2W Sink for Luck Gems)
GameConfig.GemShopItems = {
	{
		Id = "gem_heavenly_potion",
		Name = "Singularity Potion (+500% Next Roll)",
		GemCost = 250,
		Description = "Supercharges your next roll with +500% bonus Luck.",
	},
	{
		Id = "gem_fast_rolls_25",
		Name = "+25 Instant Fast-Roll Tokens",
		GemCost = 150,
		Description = "Grants 25 instant zero-cooldown rolls.",
	},
	{
		Id = "gem_vault_slots_10",
		Name = "+10 Aura Vault Slots",
		GemCost = 400,
		Description = "Permanently adds +10 Aura storage slots.",
	},
}

-- 10 Progression Rebirth Tiers
GameConfig.Rebirths = {
	{ Level = 1, CoinCost = 500, RequiredAuraOneIn = 12, PermanentLuckBonus = 0.25, PermanentCoinMultiplier = 1.35, BonusInventorySlots = 4, Title = "Neon Initiate" },
	{ Level = 2, CoinCost = 2500, RequiredAuraOneIn = 30, PermanentLuckBonus = 0.55, PermanentCoinMultiplier = 1.75, BonusInventorySlots = 8, Title = "Circuit Runner" },
	{ Level = 3, CoinCost = 12000, RequiredAuraOneIn = 75, PermanentLuckBonus = 0.90, PermanentCoinMultiplier = 2.25, BonusInventorySlots = 12, Title = "Cyber Ronin" },
	{ Level = 4, CoinCost = 50000, RequiredAuraOneIn = 200, PermanentLuckBonus = 1.35, PermanentCoinMultiplier = 3.00, BonusInventorySlots = 16, Title = "Phantom Striker" },
	{ Level = 5, CoinCost = 220000, RequiredAuraOneIn = 500, PermanentLuckBonus = 1.90, PermanentCoinMultiplier = 4.00, BonusInventorySlots = 22, Title = "Solar Vanguard" },
	{ Level = 6, CoinCost = 950000, RequiredAuraOneIn = 1250, PermanentLuckBonus = 2.60, PermanentCoinMultiplier = 5.50, BonusInventorySlots = 28, Title = "Zero-Kelvin Lord" },
	{ Level = 7, CoinCost = 4500000, RequiredAuraOneIn = 3500, PermanentLuckBonus = 3.50, PermanentCoinMultiplier = 7.50, BonusInventorySlots = 36, Title = "Void Sovereign" },
	{ Level = 8, CoinCost = 20000000, RequiredAuraOneIn = 10000, PermanentLuckBonus = 4.75, PermanentCoinMultiplier = 10.5, BonusInventorySlots = 45, Title = "Astral Valkyrie" },
	{ Level = 9, CoinCost = 100000000, RequiredAuraOneIn = 25000, PermanentLuckBonus = 6.25, PermanentCoinMultiplier = 15.0, BonusInventorySlots = 60, Title = "Abyssal Emperor" },
	{ Level = 10, CoinCost = 500000000, RequiredAuraOneIn = 150000, PermanentLuckBonus = 8.50, PermanentCoinMultiplier = 25.0, BonusInventorySlots = 80, Title = "OMEGA DEITY" },
} :: { RebirthTier }

-- Arena Boss Definitions
GameConfig.Bosses = {
	{
		Id = "sentinel_drone",
		Name = "MK-I Cyber Sentinel",
		MaxHP = 450,
		DamagePerPulse = 15,
		AttackInterval = 3.5,
		RewardCoins = 350,
		RewardGems = 25,
		RewardFastRolls = 2,
		PrimaryColor = Color3.fromRGB(0, 210, 255),
		Scale = 1.0,
	},
	{
		Id = "crimson_enforcer",
		Name = "MK-IV Crimson Enforcer",
		MaxHP = 1400,
		DamagePerPulse = 22,
		AttackInterval = 3.0,
		RewardCoins = 1200,
		RewardGems = 55,
		RewardFastRolls = 4,
		PrimaryColor = Color3.fromRGB(255, 50, 80),
		Scale = 1.25,
	},
	{
		Id = "void_colossus",
		Name = "Void Core Colossus",
		MaxHP = 4200,
		DamagePerPulse = 30,
		AttackInterval = 2.6,
		RewardCoins = 4000,
		RewardGems = 120,
		RewardFastRolls = 8,
		PrimaryColor = Color3.fromRGB(175, 60, 255),
		Scale = 1.5,
	},
	{
		Id = "omega_overlord",
		Name = "OMEGA MECH OVERLORD",
		MaxHP = 12500,
		DamagePerPulse = 38,
		AttackInterval = 2.2,
		RewardCoins = 15000,
		RewardGems = 350,
		RewardFastRolls = 20,
		PrimaryColor = Color3.fromRGB(255, 145, 0),
		Scale = 1.85,
	},
} :: { BossDefinition }

-- 7-Day Login Streak Rewards (Retention Engine)
GameConfig.DailyRewards = {
	{ Day = 1, Coins = 250, Gems = 50, Potions = 0, Label = "250 Coins + 50 Gems" },
	{ Day = 2, Coins = 600, Gems = 100, Potions = 1, Label = "600 Coins + 1 Singularity Potion" },
	{ Day = 3, Coins = 1500, Gems = 175, Potions = 1, Label = "1,500 Coins + 175 Gems" },
	{ Day = 4, Coins = 3500, Gems = 250, Potions = 2, Label = "3,500 Coins + 2 Potions" },
	{ Day = 5, Coins = 8000, Gems = 400, Potions = 2, Label = "8,000 Coins + 400 Gems" },
	{ Day = 6, Coins = 18000, Gems = 650, Potions = 3, Label = "18,000 Coins + 3 Potions" },
	{ Day = 7, Coins = 50000, Gems = 1500, Potions = 5, Label = "JACKPOT: 50K Coins + 1.5K Gems + 5 Potions!" },
}

-- Redeemable Promo Codes (Social / Discord / TikTok Growth Loop)
GameConfig.PromoCodes = {
	["RELEASE"] = { Coins = 1000, Gems = 250, Potions = 1, Description = "Launch Starter Pack!" },
	["OMEGA2026"] = { Coins = 3500, Gems = 500, Potions = 2, Description = "Omega Update Pack!" },
	["LUCKY777"] = { Coins = 777, Gems = 777, Potions = 3, Description = "Triple Lucky 777 Drop!" },
	["CYBERBLADE"] = { Coins = 2500, Gems = 300, Potions = 1, Description = "Cyber Blade Community Reward!" },
}

-- Helper Lookups
local auraById: { [string]: AuraDefinition } = {}
for _, aura in ipairs(GameConfig.Auras) do
	auraById[aura.Id] = aura
end

function GameConfig.GetAuraById(auraId: string): AuraDefinition
	return auraById[auraId] or GameConfig.Auras[1]
end

function GameConfig.GetGamepassByKey(key: string): GamepassInfo?
	for _, gp in ipairs(GameConfig.Gamepasses) do
		if gp.Key == key then
			return gp
		end
	end
	return nil
end

function GameConfig.GetGamepassById(id: number): GamepassInfo?
	for _, gp in ipairs(GameConfig.Gamepasses) do
		if gp.Id == id then
			return gp
		end
	end
	return nil
end

function GameConfig.GetDevProductByKey(key: string): DevProductInfo?
	for _, dp in ipairs(GameConfig.DevProducts) do
		if dp.Key == key then
			return dp
		end
	end
	return nil
end

function GameConfig.GetDevProductById(id: number): DevProductInfo?
	for _, dp in ipairs(GameConfig.DevProducts) do
		if dp.Id == id then
			return dp
		end
	end
	return nil
end

function GameConfig.GetRebirthTier(level: number): RebirthTier?
	return GameConfig.Rebirths[level]
end

return GameConfig
