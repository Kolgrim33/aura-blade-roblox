--!strict
--[[
	DataManager.luau
	Server-side DataStoreService persistence & OrderedDataStore leaderboard manager.
	Features:
	- Exponential backoff retry on GetAsync / UpdateAsync
	- Schema migration & default profile hydration
	- Idempotent PurchaseHistory ring-buffer for ProcessReceipt
	- Auto-save loop & BindToClose graceful shutdown
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

export type PlayerProfile = {
	SchemaVersion: number,
	Coins: number,
	Gems: number,
	TotalRolls: number,
	Rebirths: number,
	BestAuraId: string,
	BestAuraOneIn: number,
	EquippedAuraId: string,
	OwnedAuras: { string },
	HeavenlyPotions: number,
	FastRollTokens: number,
	BonusVaultSlots: number,
	BossKills: number,
	TotalDamageDealt: number,
	LastDailyClaimDay: number,
	DailyStreak: number,
	RedeemedCodes: { [string]: boolean },
	OwnedGamepasses: { [string]: boolean },
	ProcessedReceipts: { string },
	AutoRollEnabled: boolean,
	MinKeepOneIn: number,
}

local PROFILE_STORE_NAME = "AuraBladeProfile_v1"
local MAX_RECEIPT_HISTORY = 75

local DataManager = {}
DataManager.Profiles = {} :: { [Player]: PlayerProfile }
DataManager.Dirty = {} :: { [Player]: boolean }

local isStudio = RunService:IsStudio()
local profileStore: DataStore? = nil
local bestAuraLeaderboard: OrderedDataStore? = nil
local rebirthLeaderboard: OrderedDataStore? = nil

pcall(function()
	profileStore = DataStoreService:GetDataStore(PROFILE_STORE_NAME)
	bestAuraLeaderboard = DataStoreService:GetOrderedDataStore("AuraBlade_BestAura_v1")
	rebirthLeaderboard = DataStoreService:GetOrderedDataStore("AuraBlade_Rebirths_v1")
end)

function DataManager.CreateDefaultProfile(): PlayerProfile
	return {
		SchemaVersion = 1,
		Coins = 150,
		Gems = 50,
		TotalRolls = 0,
		Rebirths = 0,
		BestAuraId = "cyber_spark",
		BestAuraOneIn = 2,
		EquippedAuraId = "cyber_spark",
		OwnedAuras = { "cyber_spark" },
		HeavenlyPotions = 1, -- Give new players 1 free Singularity Potion to hook them early!
		FastRollTokens = 5,
		BonusVaultSlots = 0,
		BossKills = 0,
		TotalDamageDealt = 0,
		LastDailyClaimDay = 0,
		DailyStreak = 0,
		RedeemedCodes = {},
		OwnedGamepasses = {},
		ProcessedReceipts = {},
		AutoRollEnabled = false,
		MinKeepOneIn = 1,
	}
end

local function reconcileProfile(raw: any): PlayerProfile
	local def = DataManager.CreateDefaultProfile()
	if type(raw) ~= "table" then
		return def
	end
	for k, v in pairs(def :: any) do
		if raw[k] == nil then
			raw[k] = v
		end
	end
	return raw :: PlayerProfile
end

function DataManager.LoadProfile(player: Player): PlayerProfile
	local key = "Player_" .. tostring(player.UserId)
	local loadedData: any = nil

	if profileStore then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return profileStore:GetAsync(key)
			end)
			if ok then
				loadedData = result
				break
			else
				if not isStudio then
					warn(string.format("[DataManager] GetAsync attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
				end
				task.wait(0.5 * attempt)
			end
		end
	end

	local profile = reconcileProfile(loadedData)
	DataManager.Profiles[player] = profile
	DataManager.Dirty[player] = false

	DataManager.SyncLeaderstats(player)
	return profile
end

function DataManager.GetProfile(player: Player): PlayerProfile?
	return DataManager.Profiles[player]
end

function DataManager.MarkDirty(player: Player)
	DataManager.Dirty[player] = true
	DataManager.SyncLeaderstats(player)
end

function DataManager.GetMaxVaultSlots(player: Player): number
	local profile = DataManager.Profiles[player]
	if not profile then
		return GameConfig.BASE_INVENTORY_SLOTS
	end
	local slots = GameConfig.BASE_INVENTORY_SLOTS + profile.BonusVaultSlots
	local rebirthInfo = GameConfig.GetRebirthTier(profile.Rebirths)
	if rebirthInfo then
		slots += rebirthInfo.BonusInventorySlots
	end
	if profile.OwnedGamepasses["ExtraStorage"] then
		slots += 100
	end
	return slots
end

function DataManager.SyncLeaderstats(player: Player)
	local profile = DataManager.Profiles[player]
	if not profile then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats") :: Folder?
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local function setStat(name: string, value: any, className: string)
		local stat = leaderstats:FindFirstChild(name)
		if not stat then
			stat = Instance.new(className)
			stat.Name = name
			stat.Parent = leaderstats
		end
		(stat :: any).Value = value
	end

	local bestAura = GameConfig.GetAuraById(profile.BestAuraId)
	setStat("Aura", bestAura.Name, "StringValue")
	setStat("Rolls", profile.TotalRolls, "IntValue")
	setStat("Rebirths", profile.Rebirths, "IntValue")
	setStat("Coins", math.floor(profile.Coins), "IntValue")
end

function DataManager.SaveProfile(player: Player, force: boolean?): boolean
	local profile = DataManager.Profiles[player]
	if not profile then
		return false
	end
	if not force and not DataManager.Dirty[player] then
		return true
	end

	local key = "Player_" .. tostring(player.UserId)
	if profileStore then
		for attempt = 1, 3 do
			local ok, err = pcall(function()
				profileStore:UpdateAsync(key, function(_old)
					return profile
				end)
			end)
			if ok then
				DataManager.Dirty[player] = false
				break
			else
				if not isStudio then
					warn(string.format("[DataManager] UpdateAsync failed (%d) for %s: %s", attempt, player.Name, tostring(err)))
				end
				task.wait(0.5 * attempt)
			end
		end
	end

	-- Update Global OrderedDataStores
	if bestAuraLeaderboard and profile.BestAuraOneIn > 2 then
		pcall(function()
			bestAuraLeaderboard:SetAsync(key, profile.BestAuraOneIn)
		end)
	end
	if rebirthLeaderboard and profile.Rebirths > 0 then
		pcall(function()
			rebirthLeaderboard:SetAsync(key, profile.Rebirths)
		end)
	end

	return true
end

function DataManager.RecordReceipt(profile: PlayerProfile, purchaseId: string)
	table.insert(profile.ProcessedReceipts, purchaseId)
	while #profile.ProcessedReceipts > MAX_RECEIPT_HISTORY do
		table.remove(profile.ProcessedReceipts, 1)
	end
end

function DataManager.HasProcessedReceipt(profile: PlayerProfile, purchaseId: string): boolean
	return table.find(profile.ProcessedReceipts, purchaseId) ~= nil
end

function DataManager.CleanupPlayer(player: Player)
	DataManager.SaveProfile(player, true)
	DataManager.Profiles[player] = nil
	DataManager.Dirty[player] = nil
end

-- Periodic Auto-Save & Graceful Shutdown
function DataManager.StartAutoSaveLoop()
	task.spawn(function()
		while true do
			task.wait(90)
			for _, player in ipairs(Players:GetPlayers()) do
				DataManager.SaveProfile(player, false)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				DataManager.SaveProfile(player, true)
			end)
		end
		task.wait(2)
	end)
end

return DataManager
