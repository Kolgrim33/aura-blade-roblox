--!strict
--[[
	MonetizationServer.luau
	Complete Robux & Gem monetization system for AURA BLADE: RNG & BOSS ARENA.
	Handles:
	- MarketplaceService.ProcessReceipt (idempotent Developer Products)
	- Gamepass ownership checks & PromptGamePassPurchaseFinished live grants
	- Studio Sandbox Purchase Mode (test all passes & products in Studio for free!)
	- Server-wide 2x Luck Party Boost timer
	- Friend-in-Server viral luck bonus & Roblox Premium EBP multiplier
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local DataManager = require(script.Parent.DataManager)

local MonetizationServer = {}
MonetizationServer.ServerLuckEndTime = 0
MonetizationServer.ServerBoostSponsor = ""
MonetizationServer.OnServerAnnouncement = nil :: ((string, Color3) -> ())?
MonetizationServer.OnForceSpawnOmegaBoss = nil :: ((Player) -> ())?
MonetizationServer.OnProfileUpdated = nil :: ((Player) -> ())?

function MonetizationServer.IsServerBoostActive(): boolean
	return os.time() < MonetizationServer.ServerLuckEndTime
end

function MonetizationServer.GetServerBoostRemaining(): number
	return math.max(0, MonetizationServer.ServerLuckEndTime - os.time())
end

function MonetizationServer.SyncPlayerGamepasses(player: Player)
	local profile = DataManager.GetProfile(player)
	if not profile then
		return
	end

	for _, gp in ipairs(GameConfig.Gamepasses) do
		if not profile.OwnedGamepasses[gp.Key] then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gp.Id)
			end)
			if ok and owns then
				profile.OwnedGamepasses[gp.Key] = true
			end
		end
	end
end

function MonetizationServer.OwnsGamepass(player: Player, key: string): boolean
	local profile = DataManager.GetProfile(player)
	if not profile then
		return false
	end
	return profile.OwnedGamepasses[key] == true
end

function MonetizationServer.CountFriendsInServer(player: Player): number
	local count = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local ok, isFriend = pcall(function()
				return player:IsFriendsWith(other.UserId)
			end)
			if ok and isFriend then
				count += 1
			end
		end
	end
	return count
end

function MonetizationServer.GrantDevProductByKey(player: Player, key: string): boolean
	local profile = DataManager.GetProfile(player)
	if not profile then
		return false
	end

	if key == "ServerLuckBoost" then
		local now = os.time()
		local baseTime = math.max(now, MonetizationServer.ServerLuckEndTime)
		MonetizationServer.ServerLuckEndTime = baseTime + (15 * 60)
		MonetizationServer.ServerBoostSponsor = player.DisplayName
		if MonetizationServer.OnServerAnnouncement then
			MonetizationServer.OnServerAnnouncement(
				string.format("⚡ %s activated 2X SERVER LUCK PARTY for 15 minutes!", player.DisplayName),
				Color3.fromRGB(50, 255, 160)
			)
		end
	elseif key == "HeavenlyPotion" then
		profile.HeavenlyPotions += 1
	elseif key == "SummonOmegaBoss" then
		if MonetizationServer.OnForceSpawnOmegaBoss then
			MonetizationServer.OnForceSpawnOmegaBoss(player)
		end
		if MonetizationServer.OnServerAnnouncement then
			MonetizationServer.OnServerAnnouncement(
				string.format("🔥 %s summoned the OMEGA MECH OVERLORD in the Arena!", player.DisplayName),
				Color3.fromRGB(255, 85, 65)
			)
		end
	elseif key == "GemPackSmall" then
		profile.Gems += 1500
	elseif key == "GemPackMedium" then
		profile.Gems += 6000
	elseif key == "GemPackMega" then
		profile.Gems += 25000
		profile.HeavenlyPotions += 3
	else
		return false
	end

	DataManager.MarkDirty(player)
	if MonetizationServer.OnProfileUpdated then
		MonetizationServer.OnProfileUpdated(player)
	end
	return true
end

function MonetizationServer.GrantGamepassByKey(player: Player, key: string): boolean
	local profile = DataManager.GetProfile(player)
	if not profile then
		return false
	end
	local gp = GameConfig.GetGamepassByKey(key)
	if not gp then
		return false
	end

	profile.OwnedGamepasses[key] = true
	if key == "VIP" then
		profile.Coins += 2500
		profile.Gems += 300
	end

	DataManager.MarkDirty(player)
	if MonetizationServer.OnProfileUpdated then
		MonetizationServer.OnProfileUpdated(player)
	end
	if MonetizationServer.OnServerAnnouncement then
		MonetizationServer.OnServerAnnouncement(
			string.format("👑 %s unlocked the [%s] Gamepass!", player.DisplayName, gp.Name),
			gp.AccentColor
		)
	end
	return true
end

function MonetizationServer.PromptOrSimulatePurchase(player: Player, kind: string, key: string): (boolean, string)
	local isStudio = RunService:IsStudio()

	if kind == "Gamepass" then
		local gp = GameConfig.GetGamepassByKey(key)
		if not gp then
			return false, "Unknown Gamepass"
		end
		if MonetizationServer.OwnsGamepass(player, key) then
			return false, "You already own " .. gp.Name .. "!"
		end

		if isStudio and GameConfig.STUDIO_SANDBOX_PURCHASES then
			MonetizationServer.GrantGamepassByKey(player, key)
			return true, "[Studio Sandbox] Unlocked " .. gp.Name .. "!"
		end

		pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, gp.Id)
		end)
		return true, "Prompted " .. gp.Name
	elseif kind == "DevProduct" then
		local dp = GameConfig.GetDevProductByKey(key)
		if not dp then
			return false, "Unknown Product"
		end

		if isStudio and GameConfig.STUDIO_SANDBOX_PURCHASES then
			MonetizationServer.GrantDevProductByKey(player, key)
			return true, "[Studio Sandbox] Activated " .. dp.Name .. "!"
		end

		pcall(function()
			MarketplaceService:PromptProductPurchase(player, dp.Id)
		end)
		return true, "Prompted " .. dp.Name
	end

	return false, "Invalid purchase request"
end

function MonetizationServer.Init()
	-- Live Gamepass purchase listener
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if not wasPurchased then
			return
		end
		local gp = GameConfig.GetGamepassById(gamePassId)
		if gp then
			MonetizationServer.GrantGamepassByKey(player, gp.Key)
		end
	end)

	-- Idempotent ProcessReceipt handler for all Developer Products
	MarketplaceService.ProcessReceipt = function(receiptInfo): Enum.ProductPurchaseDecision
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local profile = DataManager.GetProfile(player)
		if not profile then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local purchaseId = tostring(receiptInfo.PurchaseId)
		if DataManager.HasProcessedReceipt(profile, purchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local dp = GameConfig.GetDevProductById(receiptInfo.ProductId)
		if not dp then
			warn("[MonetizationServer] Unrecognized ProductId:", receiptInfo.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local granted = MonetizationServer.GrantDevProductByKey(player, dp.Key)
		if not granted then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		DataManager.RecordReceipt(profile, purchaseId)
		DataManager.SaveProfile(player, true)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return MonetizationServer
