--!strict
--[[
	GameServer.server.luau
	Master Server Script for AURA BLADE: RNG & BOSS ARENA.
	Wires ReplicatedStorage RemoteEvents/RemoteFunctions, Player lifecycle,
	Rolling, Auto-Roll loop, Rebirths, Gem Shop, Daily Streak, Promo Codes,
	3D World generation, Character Auras, and Arena Boss combat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RollEngine = require(Shared:WaitForChild("RollEngine"))

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local MonetizationServer = require(script.Parent:WaitForChild("MonetizationServer"))
local VisualAuraBuilder = require(script.Parent:WaitForChild("VisualAuraBuilder"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local CombatAndBossServer = require(script.Parent:WaitForChild("CombatAndBossServer"))

-- Create RemoteEvents & RemoteFunctions Folder
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function createRemoteEvent(name: string): RemoteEvent
	local existing = (remotesFolder :: Folder):FindFirstChild(name) :: RemoteEvent?
	if existing then
		return existing
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = remotesFolder
	return ev
end

local function createRemoteFunction(name: string): RemoteFunction
	local existing = (remotesFolder :: Folder):FindFirstChild(name) :: RemoteFunction?
	if existing then
		return existing
	end
	local fn = Instance.new("RemoteFunction")
	fn.Name = name
	fn.Parent = remotesFolder
	return fn
end

local StateSyncEvent = createRemoteEvent("StateSync")
local RollResultEvent = createRemoteEvent("RollResult")
local ServerAnnounceEvent = createRemoteEvent("ServerAnnounce")
local CombatSlashEvent = createRemoteEvent("CombatSlash")
local CombatHitFeedbackEvent = createRemoteEvent("CombatHitFeedback")
local BossStateEvent = createRemoteEvent("BossState")
local ActionRequestFunc = createRemoteFunction("ActionRequest")

-- Timed Per-Player Buff Tracking (Sky Obby & VIP Fountain)
local obbyBuffExpiry: { [Player]: number } = {}
local vipFountainExpiry: { [Player]: number } = {}
local lastRollTimestamp: { [Player]: number } = {}

local function getObbyRemaining(player: Player): number
	return math.max(0, (obbyBuffExpiry[player] or 0) - os.time())
end

local function getVipFountainRemaining(player: Player): number
	return math.max(0, (vipFountainExpiry[player] or 0) - os.time())
end

local function buildLuckContext(player: Player, profile: DataManager.PlayerProfile, usePotion: boolean): RollEngine.LuckContext
	return {
		RebirthLevel = profile.Rebirths,
		OwnsDoubleLuck = MonetizationServer.OwnsGamepass(player, "DoubleLuck"),
		OwnsVIP = MonetizationServer.OwnsGamepass(player, "VIP"),
		IsPremium = (player.MembershipType == Enum.MembershipType.Premium),
		FriendsInServer = MonetizationServer.CountFriendsInServer(player),
		HasObbyBuff = getObbyRemaining(player) > 0,
		HasVipFountainBuff = getVipFountainRemaining(player) > 0,
		ServerBoostActive = MonetizationServer.IsServerBoostActive(),
		UseHeavenlyPotion = usePotion,
		TotalRolls = profile.TotalRolls,
	}
end

local function syncPlayerState(player: Player)
	local profile = DataManager.GetProfile(player)
	if not profile then
		return
	end
	local luckCtx = buildLuckContext(player, profile, false)
	local luckBreakdown = RollEngine.ComputeLuck(luckCtx)

	StateSyncEvent:FireClient(player, {
		Profile = profile,
		MaxVaultSlots = DataManager.GetMaxVaultSlots(player),
		TotalLuck = luckBreakdown.TotalLuck,
		ObbyBuffRemaining = getObbyRemaining(player),
		VipFountainRemaining = getVipFountainRemaining(player),
		ServerBoostRemaining = MonetizationServer.GetServerBoostRemaining(),
		ServerBoostSponsor = MonetizationServer.ServerBoostSponsor,
		FriendsInServer = luckCtx.FriendsInServer,
		IsPremium = luckCtx.IsPremium,
	})
end

local function refreshCharacterVisuals(player: Player)
	local profile = DataManager.GetProfile(player)
	if not profile then
		return
	end
	VisualAuraBuilder.ApplyAuraToCharacter(
		player,
		profile.EquippedAuraId,
		profile.Rebirths,
		MonetizationServer.OwnsGamepass(player, "VIP")
	)
end

local function performPlayerRoll(player: Player, useHeavenlyPotion: boolean, useFastToken: boolean): (boolean, string)
	local profile = DataManager.GetProfile(player)
	if not profile then
		return false, "Profile still loading..."
	end

	local now = os.clock()
	local ownsFast = MonetizationServer.OwnsGamepass(player, "FastRoll")
	local cooldown = if ownsFast then GameConfig.FAST_ROLL_COOLDOWN else GameConfig.BASE_ROLL_COOLDOWN

	if useFastToken and profile.FastRollTokens > 0 then
		profile.FastRollTokens -= 1
		cooldown = 0.12
	end

	if (lastRollTimestamp[player] or 0) + cooldown > now then
		return false, "Roll cooling down!"
	end
	lastRollTimestamp[player] = now

	local consumePotion = false
	if useHeavenlyPotion and profile.HeavenlyPotions > 0 then
		profile.HeavenlyPotions -= 1
		consumePotion = true
	end

	local tripleRoll = MonetizationServer.OwnsGamepass(player, "TripleRoll")
	local ctx = buildLuckContext(player, profile, consumePotion)
	local bestAura, allRolled, breakdown = RollEngine.RollBatch(ctx, tripleRoll)

	profile.TotalRolls += #allRolled

	-- Passive Coin gain per roll (scales with Aura + Rebirth + VIP + Premium)
	local equippedAura = GameConfig.GetAuraById(profile.EquippedAuraId)
	local rebInfo = GameConfig.GetRebirthTier(profile.Rebirths)
	local rebMult = if rebInfo then rebInfo.PermanentCoinMultiplier else 1.0
	local vipMult = if MonetizationServer.OwnsGamepass(player, "VIP") then 1.5 else 1.0
	local premMult = if player.MembershipType == Enum.MembershipType.Premium
		then GameConfig.PREMIUM_COIN_MULTIPLIER
		else 1.0
	local coinsFromRoll = math.max(1, math.floor(5 * equippedAura.CoinMultiplier * rebMult * vipMult * premMult))
	profile.Coins += coinsFromRoll

	-- Add newly rolled Aura to Vault if not already owned (and within capacity)
	local maxSlots = DataManager.GetMaxVaultSlots(player)
	if not table.find(profile.OwnedAuras, bestAura.Id) then
		if #profile.OwnedAuras < maxSlots then
			table.insert(profile.OwnedAuras, bestAura.Id)
		elseif bestAura.OneIn > profile.BestAuraOneIn then
			-- Always guarantee space for a new personal-best Aura!
			table.insert(profile.OwnedAuras, bestAura.Id)
		end
	end

	-- Auto-equip if strictly rarer than current best
	if bestAura.OneIn > profile.BestAuraOneIn then
		profile.BestAuraId = bestAura.Id
		profile.BestAuraOneIn = bestAura.OneIn
		profile.EquippedAuraId = bestAura.Id
		refreshCharacterVisuals(player)
	end

	-- Global Server Broadcast for 1-in-10,000+ Legendary / Mythic / Celestial rolls!
	if bestAura.ServerAnnounce then
		ServerAnnounceEvent:FireAllClients(
			string.format(
				"🌌 %s JUST ROLLED [%s] (1 IN %d) AT %.1fX LUCK! 🌌",
				player.DisplayName,
				string.upper(bestAura.Name),
				bestAura.OneIn,
				breakdown.TotalLuck
			),
			bestAura.PrimaryColor
		)
	end

	DataManager.MarkDirty(player)
	syncPlayerState(player)

	local batchIds: { string } = {}
	for _, a in ipairs(allRolled) do
		table.insert(batchIds, a.Id)
	end

	RollResultEvent:FireClient(player, {
		BestAuraId = bestAura.Id,
		AllAuraIds = batchIds,
		UsedPotion = consumePotion,
		CoinsEarned = coinsFromRoll,
		EffectiveLuck = breakdown.TotalLuck,
	})

	return true, bestAura.Name
end

-- Wire World Callbacks
WorldBuilder.BuildWorld(
	function(player: Player) -- Obby Summit Pad
		local profile = DataManager.GetProfile(player)
		if not profile then
			return
		end
		obbyBuffExpiry[player] = os.time() + GameConfig.OBBY_BUFF_DURATION
		profile.Coins += 500
		profile.Gems += 25
		DataManager.MarkDirty(player)
		syncPlayerState(player)
		ServerAnnounceEvent:FireClient(
			player,
			"🏆 Sky Obby Conquered! +100% (2X) Roll Luck for 5m + 500 Coins + 25 Gems!",
			Color3.fromRGB(50, 255, 130)
		)
	end,
	function(player: Player) -- VIP Fountain
		local profile = DataManager.GetProfile(player)
		if not profile then
			return
		end
		if MonetizationServer.OwnsGamepass(player, "VIP") or profile.Rebirths >= 3 then
			vipFountainExpiry[player] = os.time() + 300
			syncPlayerState(player)
			ServerAnnounceEvent:FireClient(
				player,
				"👑 VIP Sanctum Blessing Active: +35% Bonus Luck for 5 minutes!",
				Color3.fromRGB(255, 215, 50)
			)
		else
			MonetizationServer.PromptOrSimulatePurchase(player, "Gamepass", "VIP")
		end
	end,
	function(player: Player, kind: string, key: string) -- 3D Shop Pedestals
		local ok, msg = MonetizationServer.PromptOrSimulatePurchase(player, kind, key)
		if ok then
			ServerAnnounceEvent:FireClient(player, msg, Color3.fromRGB(0, 235, 255))
		end
	end
)

-- Wire Monetization & Boss Callbacks
MonetizationServer.OnServerAnnouncement = function(msg: string, color: Color3)
	ServerAnnounceEvent:FireAllClients(msg, color)
	for _, p in ipairs(Players:GetPlayers()) do
		syncPlayerState(p)
	end
end

MonetizationServer.OnForceSpawnOmegaBoss = function(_player: Player)
	local omegaDef = GameConfig.Bosses[#GameConfig.Bosses]
	CombatAndBossServer.SpawnBoss(omegaDef, 3.0)
end

MonetizationServer.OnProfileUpdated = function(player: Player)
	refreshCharacterVisuals(player)
	syncPlayerState(player)
end

CombatAndBossServer.OnBossStateChanged = function(name: string, hp: number, maxHp: number, color: Color3)
	BossStateEvent:FireAllClients({
		Name = name,
		HP = hp,
		MaxHP = maxHp,
		Color = color,
	})
end

CombatAndBossServer.OnBossDefeated = function(player: Player, bossName: string, coins: number, gems: number, fastRolls: number)
	syncPlayerState(player)
	ServerAnnounceEvent:FireClient(
		player,
		string.format("⚔️ %s Defeated! +%d Coins, +%d Gems, +%d Fast Rolls!", bossName, coins, gems, fastRolls),
		Color3.fromRGB(255, 195, 45)
	)
end

-- Client Combat Slash RemoteEvent
CombatSlashEvent.OnServerEvent:Connect(function(player: Player)
	local hit, dmg, isCrit = CombatAndBossServer.HandlePlayerSlash(player)
	if hit then
		CombatHitFeedbackEvent:FireClient(player, dmg, isCrit)
		syncPlayerState(player)
	end
end)

-- Unified Client Action Request Handler
ActionRequestFunc.OnServerInvoke = function(player: Player, action: string, payload: any): (boolean, string)
	local profile = DataManager.GetProfile(player)
	if not profile then
		return false, "Profile not loaded yet"
	end

	if action == "Roll" then
		local usePotion = type(payload) == "table" and payload.UsePotion == true
		local useFast = type(payload) == "table" and payload.UseFastToken == true
		return performPlayerRoll(player, usePotion, useFast)

	elseif action == "ToggleAutoRoll" then
		if not MonetizationServer.OwnsGamepass(player, "AutoRoll") and profile.Rebirths < 2 then
			local ok, msg = MonetizationServer.PromptOrSimulatePurchase(player, "Gamepass", "AutoRoll")
			return ok, msg
		end
		profile.AutoRollEnabled = not profile.AutoRollEnabled
		DataManager.MarkDirty(player)
		syncPlayerState(player)
		return true, if profile.AutoRollEnabled then "Auto-Roll ENABLED" else "Auto-Roll PAUSED"

	elseif action == "EquipAura" then
		local auraId = tostring(payload)
		if not table.find(profile.OwnedAuras, auraId) then
			return false, "You don't own that Aura yet!"
		end
		profile.EquippedAuraId = auraId
		DataManager.MarkDirty(player)
		refreshCharacterVisuals(player)
		syncPlayerState(player)
		local aura = GameConfig.GetAuraById(auraId)
		return true, "Equipped " .. aura.Name .. "!"

	elseif action == "Rebirth" then
		local nextTier = GameConfig.GetRebirthTier(profile.Rebirths + 1)
		if not nextTier then
			return false, "You have reached Maximum Rebirth (OMEGA DEITY)!"
		end
		if profile.Coins < nextTier.CoinCost then
			return false, string.format("Need %d Flux Coins to Rebirth!", nextTier.CoinCost)
		end
		if profile.BestAuraOneIn < nextTier.RequiredAuraOneIn then
			return false, string.format("Need a 1-in-%d+ Aura to Rebirth!", nextTier.RequiredAuraOneIn)
		end

		profile.Coins = 0
		profile.Rebirths = nextTier.Level
		profile.Gems += (nextTier.Level * 75)
		profile.FastRollTokens += 5
		DataManager.MarkDirty(player)
		refreshCharacterVisuals(player)
		syncPlayerState(player)

		ServerAnnounceEvent:FireAllClients(
			string.format("🔥 %s ascended to REBIRTH %d [%s]!", player.DisplayName, nextTier.Level, nextTier.Title),
			Color3.fromRGB(255, 175, 40)
		)
		return true, string.format("Rebirth %d Unlocked: %s!", nextTier.Level, nextTier.Title)

	elseif action == "BuyShopItem" then
		if type(payload) ~= "table" then
			return false, "Invalid request"
		end
		return MonetizationServer.PromptOrSimulatePurchase(player, tostring(payload.Kind), tostring(payload.Key))

	elseif action == "BuyGemItem" then
		local itemId = tostring(payload)
		for _, item in ipairs(GameConfig.GemShopItems) do
			if item.Id == itemId then
				if profile.Gems < item.GemCost then
					return false, "Not enough Luck Gems!"
				end
				profile.Gems -= item.GemCost
				if itemId == "gem_heavenly_potion" then
					profile.HeavenlyPotions += 1
				elseif itemId == "gem_fast_rolls_25" then
					profile.FastRollTokens += 25
				elseif itemId == "gem_vault_slots_10" then
					profile.BonusVaultSlots += 10
				end
				DataManager.MarkDirty(player)
				syncPlayerState(player)
				return true, "Purchased " .. item.Name .. "!"
			end
		end
		return false, "Unknown Gem Shop item"

	elseif action == "ClaimDaily" then
		local currentDay = math.floor(os.time() / 86400)
		if profile.LastDailyClaimDay == currentDay then
			return false, "Daily Reward already claimed today! Come back tomorrow!"
		end
		if profile.LastDailyClaimDay == currentDay - 1 then
			profile.DailyStreak = (profile.DailyStreak % #GameConfig.DailyRewards) + 1
		else
			profile.DailyStreak = 1
		end
		profile.LastDailyClaimDay = currentDay
		local reward = GameConfig.DailyRewards[profile.DailyStreak]
		profile.Coins += reward.Coins
		profile.Gems += reward.Gems
		profile.HeavenlyPotions += reward.Potions
		DataManager.MarkDirty(player)
		syncPlayerState(player)
		return true, string.format("Day %d Claimed: %s!", reward.Day, reward.Label)

	elseif action == "RedeemCode" then
		local code = string.upper(string.gsub(tostring(payload or ""), "%s+", ""))
		local codeReward = GameConfig.PromoCodes[code]
		if not codeReward then
			return false, "Invalid or expired code! Try: RELEASE, OMEGA2026, LUCKY777, CYBERBLADE"
		end
		if profile.RedeemedCodes[code] then
			return false, "Code '" .. code .. "' already redeemed!"
		end
		profile.RedeemedCodes[code] = true
		profile.Coins += codeReward.Coins
		profile.Gems += codeReward.Gems
		profile.HeavenlyPotions += codeReward.Potions
		DataManager.MarkDirty(player)
		syncPlayerState(player)
		return true, string.format("Code %s: +%d Coins, +%d Gems, +%d Potions!", code, codeReward.Coins, codeReward.Gems, codeReward.Potions)

	elseif action == "RequestState" then
		syncPlayerState(player)
		return true, "Synced"
	end

	return false, "Unknown action"
end

-- Player Lifecycle Connections
local function onPlayerAdded(player: Player)
	local profile = DataManager.LoadProfile(player)
	MonetizationServer.SyncPlayerGamepasses(player)

	player.CharacterAdded:Connect(function(_character)
		task.wait(0.25)
		refreshCharacterVisuals(player)
	end)

	if player.Character then
		task.spawn(function()
			refreshCharacterVisuals(player)
		end)
	end

	task.delay(0.5, function()
		if player.Parent then
			syncPlayerState(player)
			if CombatAndBossServer.CurrentBoss then
				local b = CombatAndBossServer.CurrentBoss
				BossStateEvent:FireClient(player, {
					Name = b.Def.Name,
					HP = b.CurrentHP,
					MaxHP = b.MaxHP,
					Color = b.Def.PrimaryColor,
				})
			end
		end
	end)
	local _ = profile
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

Players.PlayerRemoving:Connect(function(player: Player)
	obbyBuffExpiry[player] = nil
	vipFountainExpiry[player] = nil
	lastRollTimestamp[player] = nil
	DataManager.CleanupPlayer(player)
end)

-- Server Auto-Roll & Periodic HUD Sync Loop
task.spawn(function()
	while true do
		task.wait(0.65)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataManager.GetProfile(player)
			if profile and profile.AutoRollEnabled then
				performPlayerRoll(player, false, false)
			end
		end
	end
end)

MonetizationServer.Init()
VisualAuraBuilder.StartOrbitLoop()
DataManager.StartAutoSaveLoop()
CombatAndBossServer.StartDirectorLoop()
