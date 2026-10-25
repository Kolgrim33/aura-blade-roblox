--!strict
--[[
	GameClient.client.luau
	Complete Client HUD, Roll Animation, Mythic Cutscene, Modal Windows
	(Aura Vault, Robux & Gem Store, Rebirth Sanctum, Codes & Daily Rewards),
	and Active Sword Slash / Dash Controller for AURA BLADE: RNG & BOSS ARENA.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StateSyncEvent = Remotes:WaitForChild("StateSync") :: RemoteEvent
local RollResultEvent = Remotes:WaitForChild("RollResult") :: RemoteEvent
local ServerAnnounceEvent = Remotes:WaitForChild("ServerAnnounce") :: RemoteEvent
local CombatSlashEvent = Remotes:WaitForChild("CombatSlash") :: RemoteEvent
local CombatHitFeedbackEvent = Remotes:WaitForChild("CombatHitFeedback") :: RemoteEvent
local BossStateEvent = Remotes:WaitForChild("BossState") :: RemoteEvent
local ActionRequestFunc = Remotes:WaitForChild("ActionRequest") :: RemoteFunction

-- Client Cached State
local currentState: any = nil
local usePotionArmed = false
local activeModalName: string? = nil
local lastDashTime = 0

local function formatNumber(n: number): string
	if n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

local function formatCommas(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function addCorner(inst: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function addStroke(inst: GuiObject, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
end

-- Create Root ScreenGui
local existingGui = playerGui:FindFirstChild("AuraBladeHUD")
if existingGui then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AuraBladeHUD"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- 1. TOP CURRENCY & LUCK TELEMETRY BAR
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.AnchorPoint = Vector2.new(0.5, 0)
topBar.Position = UDim2.new(0.5, 0, 0, 14)
topBar.Size = UDim2.new(0, 820, 0, 48)
topBar.BackgroundColor3 = Color3.fromRGB(14, 17, 28)
topBar.BackgroundTransparency = 0.12
topBar.Parent = screenGui
addCorner(topBar, 12)
addStroke(topBar, Color3.fromRGB(0, 210, 255), 1.8)

local topLayout = Instance.new("UIListLayout")
topLayout.FillDirection = Enum.FillDirection.Horizontal
topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
topLayout.Padding = UDim.new(0, 14)
topLayout.Parent = topBar

local function createPillStat(text: string, color: Color3, width: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, width, 0, 34)
	lbl.BackgroundColor3 = Color3.fromRGB(22, 27, 44)
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextSize = 15
	lbl.Parent = topBar
	addCorner(lbl, 8)
	addStroke(lbl, color, 1)
	return lbl
end

local coinsLabel = createPillStat("🪙 150 Coins", Color3.fromRGB(255, 210, 60), 165)
local gemsLabel = createPillStat("💎 50 Gems", Color3.fromRGB(0, 225, 255), 155)
local luckLabel = createPillStat("🍀 1.0x Luck", Color3.fromRGB(60, 255, 140), 155)
local rebirthLabel = createPillStat("🔥 Rebirth 0", Color3.fromRGB(255, 120, 55), 145)
local boostTimerLabel = createPillStat("⚡ No Party Boost", Color3.fromRGB(190, 105, 255), 160)

-- 2. TOP BOSS HEALTH BAR BANNER
local bossBanner = Instance.new("Frame")
bossBanner.Name = "BossBanner"
bossBanner.AnchorPoint = Vector2.new(0.5, 0)
bossBanner.Position = UDim2.new(0.5, 0, 0, 70)
bossBanner.Size = UDim2.new(0, 480, 0, 38)
bossBanner.BackgroundColor3 = Color3.fromRGB(20, 14, 28)
bossBanner.BackgroundTransparency = 0.15
bossBanner.Parent = screenGui
addCorner(bossBanner, 10)
addStroke(bossBanner, Color3.fromRGB(255, 65, 95), 1.5)

local bossFill = Instance.new("Frame")
bossFill.Size = UDim2.new(1, 0, 1, 0)
bossFill.BackgroundColor3 = Color3.fromRGB(200, 35, 65)
bossFill.BackgroundTransparency = 0.35
bossFill.BorderSizePixel = 0
bossFill.Parent = bossBanner
addCorner(bossFill, 10)

local bossTitle = Instance.new("TextLabel")
bossTitle.Size = UDim2.new(1, 0, 1, 0)
bossTitle.BackgroundTransparency = 1
bossTitle.Font = Enum.Font.GothamBlack
bossTitle.Text = "⚔️ ARENA BOSS: MK-I Cyber Sentinel (450 / 450 HP) — Click / [F] to Slash!"
bossTitle.TextColor3 = Color3.fromRGB(255, 240, 245)
bossTitle.TextSize = 14
bossTitle.ZIndex = 2
bossTitle.Parent = bossBanner

-- 3. TOAST / SERVER ANNOUNCEMENT BANNER
local toastLabel = Instance.new("TextLabel")
toastLabel.AnchorPoint = Vector2.new(0.5, 0)
toastLabel.Position = UDim2.new(0.5, 0, 0, 116)
toastLabel.Size = UDim2.new(0, 680, 0, 34)
toastLabel.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
toastLabel.BackgroundTransparency = 0.2
toastLabel.Font = Enum.Font.GothamBlack
toastLabel.Text = "✨ Welcome to AURA BLADE! Press [ROLL AURA] below or Slash the Arena Boss!"
toastLabel.TextColor3 = Color3.fromRGB(0, 235, 255)
toastLabel.TextSize = 15
toastLabel.Parent = screenGui
addCorner(toastLabel, 8)

local function showToast(msg: string, color: Color3)
	toastLabel.Text = msg
	toastLabel.TextColor3 = color
	toastLabel.TextTransparency = 0
	TweenService:Create(toastLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
		Size = UDim2.new(0, 710, 0, 38),
	}):Play()
	task.delay(0.25, function()
		TweenService:Create(toastLabel, TweenInfo.new(0.2), {
			Size = UDim2.new(0, 680, 0, 34),
		}):Play()
	end)
end

-- 4. LEFT NAVIGATION DOCK (Vault, Shop, Rebirth, Daily/Codes)
local leftDock = Instance.new("Frame")
leftDock.AnchorPoint = Vector2.new(0, 0.5)
leftDock.Position = UDim2.new(0, 16, 0.52, 0)
leftDock.Size = UDim2.new(0, 150, 0, 250)
leftDock.BackgroundTransparency = 1
leftDock.Parent = screenGui

local leftLayout = Instance.new("UIListLayout")
leftLayout.Padding = UDim.new(0, 10)
leftLayout.Parent = leftDock

-- 5. BOTTOM ROLL & COMBAT ACTION DOCK
local bottomDock = Instance.new("Frame")
bottomDock.AnchorPoint = Vector2.new(0.5, 1)
bottomDock.Position = UDim2.new(0.5, 0, 1, -18)
bottomDock.Size = UDim2.new(0, 760, 0, 68)
bottomDock.BackgroundColor3 = Color3.fromRGB(14, 18, 30)
bottomDock.BackgroundTransparency = 0.1
bottomDock.Parent = screenGui
addCorner(bottomDock, 14)
addStroke(bottomDock, Color3.fromRGB(0, 200, 255), 1.8)

local bottomLayout = Instance.new("UIListLayout")
bottomLayout.FillDirection = Enum.FillDirection.Horizontal
bottomLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
bottomLayout.VerticalAlignment = Enum.VerticalAlignment.Center
bottomLayout.Padding = UDim.new(0, 10)
bottomLayout.Parent = bottomDock

local function createDockButton(parent: Instance, text: string, bg: Color3, size: UDim2): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.BackgroundColor3 = bg
	btn.Font = Enum.Font.GothamBlack
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 15
	btn.AutoButtonColor = true
	btn.Parent = parent
	addCorner(btn, 10)
	addStroke(btn, Color3.fromRGB(255, 255, 255), 1.2)
	return btn
end

local rollBtn = createDockButton(bottomDock, "🎲 ROLL AURA [R]", Color3.fromRGB(0, 175, 255), UDim2.new(0, 195, 0, 50))
local autoRollBtn = createDockButton(bottomDock, "🤖 AUTO: OFF", Color3.fromRGB(115, 55, 220), UDim2.new(0, 145, 0, 50))
local fastTokenBtn = createDockButton(bottomDock, "⚡ FAST ROLL (5)", Color3.fromRGB(235, 145, 20), UDim2.new(0, 150, 0, 50))
local potionBtn = createDockButton(bottomDock, "🧪 +500% POTION (1)", Color3.fromRGB(195, 45, 235), UDim2.new(0, 165, 0, 50))
local dashBtn = createDockButton(bottomDock, "💨 DASH [Q]", Color3.fromRGB(35, 195, 130), UDim2.new(0, 115, 0, 50))

-- 6. MODAL WINDOW CONTAINER
local modalFrame = Instance.new("Frame")
modalFrame.Name = "ModalWindow"
modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
modalFrame.Size = UDim2.new(0, 680, 0, 420)
modalFrame.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
modalFrame.Visible = false
modalFrame.Parent = screenGui
addCorner(modalFrame, 14)
addStroke(modalFrame, Color3.fromRGB(0, 220, 255), 2.2)

local modalTitle = Instance.new("TextLabel")
modalTitle.Position = UDim2.new(0, 20, 0, 12)
modalTitle.Size = UDim2.new(1, -90, 0, 34)
modalTitle.BackgroundTransparency = 1
modalTitle.Font = Enum.Font.GothamBlack
modalTitle.Text = "WINDOW"
modalTitle.TextColor3 = Color3.fromRGB(0, 230, 255)
modalTitle.TextSize = 22
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.Parent = modalFrame

local closeModalBtn = createDockButton(modalFrame, "✕", Color3.fromRGB(220, 45, 70), UDim2.new(0, 36, 0, 36))
closeModalBtn.Position = UDim2.new(1, -48, 0, 12)

local modalScroll = Instance.new("ScrollingFrame")
modalScroll.Position = UDim2.new(0, 18, 0, 56)
modalScroll.Size = UDim2.new(1, -36, 1, -72)
modalScroll.BackgroundTransparency = 1
modalScroll.BorderSizePixel = 0
modalScroll.ScrollBarThickness = 6
modalScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
modalScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
modalScroll.Parent = modalFrame

local modalListLayout = Instance.new("UIListLayout")
modalListLayout.Padding = UDim.new(0, 8)
modalListLayout.Parent = modalScroll

local function clearModalContent()
	for _, child in ipairs(modalScroll:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function populateModal(name: string)
	clearModalContent()
	local profile = if currentState then currentState.Profile else nil
	if not profile then
		return
	end

	if name == "Vault" then
		modalTitle.Text = string.format("⚔️ AURA & BLADE VAULT (%d / %d Slots)", #profile.OwnedAuras, currentState.MaxVaultSlots or 24)
		for _, auraId in ipairs(profile.OwnedAuras) do
			local aura = GameConfig.GetAuraById(auraId)
			local isEquipped = (profile.EquippedAuraId == aura.Id)

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -12, 0, 58)
			row.BackgroundColor3 = Color3.fromRGB(24, 30, 48)
			row.Parent = modalScroll
			addCorner(row, 10)
			addStroke(row, aura.PrimaryColor, 1.4)

			local infoLbl = Instance.new("TextLabel")
			infoLbl.Position = UDim2.new(0, 14, 0, 6)
			infoLbl.Size = UDim2.new(1, -150, 1, -12)
			infoLbl.BackgroundTransparency = 1
			infoLbl.Font = Enum.Font.GothamBold
			infoLbl.TextXAlignment = Enum.TextXAlignment.Left
			infoLbl.TextColor3 = aura.PrimaryColor
			infoLbl.TextSize = 15
			infoLbl.Text = string.format(
				"★ %s [%s • 1 in %s]\n⚔️ %d DMG  |  🪙 %.2fx Coins  |  👟 +%d Speed",
				aura.Name,
				aura.Tier,
				formatCommas(aura.OneIn),
				aura.BaseDamage,
				aura.CoinMultiplier,
				aura.SpeedBonus
			)
			infoLbl.Parent = row

			local eqBtn = createDockButton(
				row,
				if isEquipped then "EQUIPPED" else "EQUIP",
				if isEquipped then Color3.fromRGB(45, 185, 95) else Color3.fromRGB(0, 165, 240),
				UDim2.new(0, 115, 0, 38)
			)
			eqBtn.Position = UDim2.new(1, -128, 0.5, -19)
			eqBtn.MouseButton1Click:Connect(function()
				local ok, msg = ActionRequestFunc:InvokeServer("EquipAura", aura.Id)
				showToast(msg, if ok then aura.PrimaryColor else Color3.fromRGB(255, 80, 80))
				populateModal("Vault")
			end)
		end

	elseif name == "Shop" then
		modalTitle.Text = "💎 ROBUX GAMEPASSES, PARTY BOOSTS & GEM STORE"
		for _, gp in ipairs(GameConfig.Gamepasses) do
			local owned = profile.OwnedGamepasses[gp.Key] == true
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -12, 0, 62)
			row.BackgroundColor3 = Color3.fromRGB(24, 30, 50)
			row.Parent = modalScroll
			addCorner(row, 10)
			addStroke(row, gp.AccentColor, 1.5)

			local lbl = Instance.new("TextLabel")
			lbl.Position = UDim2.new(0, 14, 0, 6)
			lbl.Size = UDim2.new(1, -165, 1, -12)
			lbl.BackgroundTransparency = 1
			lbl.Font = Enum.Font.GothamBold
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextColor3 = gp.AccentColor
			lbl.TextSize = 14
			lbl.Text = string.format("[%s] %s\n%s", gp.IconText, gp.Name, gp.Description)
			lbl.Parent = row

			local buyBtn = createDockButton(
				row,
				if owned then "OWNED ✓" else string.format("R$ %d", gp.RobuxPrice),
				if owned then Color3.fromRGB(50, 165, 90) else gp.AccentColor,
				UDim2.new(0, 130, 0, 40)
			)
			buyBtn.Position = UDim2.new(1, -142, 0.5, -20)
			buyBtn.MouseButton1Click:Connect(function()
				local ok, msg = ActionRequestFunc:InvokeServer("BuyShopItem", { Kind = "Gamepass", Key = gp.Key })
				showToast(msg, if ok then gp.AccentColor else Color3.fromRGB(255, 90, 90))
				populateModal("Shop")
			end)
		end

		for _, dp in ipairs(GameConfig.DevProducts) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -12, 0, 60)
			row.BackgroundColor3 = Color3.fromRGB(28, 24, 46)
			row.Parent = modalScroll
			addCorner(row, 10)
			addStroke(row, dp.AccentColor, 1.3)

			local lbl = Instance.new("TextLabel")
			lbl.Position = UDim2.new(0, 14, 0, 6)
			lbl.Size = UDim2.new(1, -165, 1, -12)
			lbl.BackgroundTransparency = 1
			lbl.Font = Enum.Font.GothamBold
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextColor3 = dp.AccentColor
			lbl.TextSize = 14
			lbl.Text = string.format("⚡ %s\n%s", dp.Name, dp.Description)
			lbl.Parent = row

			local buyBtn = createDockButton(
				row,
				string.format("R$ %d", dp.RobuxPrice),
				dp.AccentColor,
				UDim2.new(0, 130, 0, 40)
			)
			buyBtn.Position = UDim2.new(1, -142, 0.5, -20)
			buyBtn.MouseButton1Click:Connect(function()
				local ok, msg = ActionRequestFunc:InvokeServer("BuyShopItem", { Kind = "DevProduct", Key = dp.Key })
				showToast(msg, if ok then dp.AccentColor else Color3.fromRGB(255, 90, 90))
			end)
		end

		for _, gItem in ipairs(GameConfig.GemShopItems) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -12, 0, 56)
			row.BackgroundColor3 = Color3.fromRGB(18, 32, 46)
			row.Parent = modalScroll
			addCorner(row, 10)
			addStroke(row, Color3.fromRGB(0, 215, 255), 1.2)

			local lbl = Instance.new("TextLabel")
			lbl.Position = UDim2.new(0, 14, 0, 6)
			lbl.Size = UDim2.new(1, -165, 1, -12)
			lbl.BackgroundTransparency = 1
			lbl.Font = Enum.Font.GothamBold
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextColor3 = Color3.fromRGB(160, 235, 255)
			lbl.TextSize = 14
			lbl.Text = string.format("💎 %s\n%s", gItem.Name, gItem.Description)
			lbl.Parent = row

			local buyBtn = createDockButton(
				row,
				string.format("💎 %d", gItem.GemCost),
				Color3.fromRGB(0, 165, 225),
				UDim2.new(0, 130, 0, 38)
			)
			buyBtn.Position = UDim2.new(1, -142, 0.5, -19)
			buyBtn.MouseButton1Click:Connect(function()
				local ok, msg = ActionRequestFunc:InvokeServer("BuyGemItem", gItem.Id)
				showToast(msg, if ok then Color3.fromRGB(0, 235, 255) else Color3.fromRGB(255, 90, 90))
			end)
		end

	elseif name == "Rebirth" then
		modalTitle.Text = "🔥 REBIRTH SANCTUM (Permanent Luck & Coin Multipliers)"
		for _, tier in ipairs(GameConfig.Rebirths) do
			local unlocked = profile.Rebirths >= tier.Level
			local isNext = (profile.Rebirths + 1 == tier.Level)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -12, 0, 64)
			row.BackgroundColor3 = Color3.fromRGB(26, 22, 38)
			row.Parent = modalScroll
			addCorner(row, 10)
			addStroke(row, if unlocked then Color3.fromRGB(50, 235, 120) else Color3.fromRGB(255, 140, 45), 1.4)

			local lbl = Instance.new("TextLabel")
			lbl.Position = UDim2.new(0, 14, 0, 6)
			lbl.Size = UDim2.new(1, -165, 1, -12)
			lbl.BackgroundTransparency = 1
			lbl.Font = Enum.Font.GothamBold
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextColor3 = Color3.fromRGB(245, 235, 255)
			lbl.TextSize = 14
			lbl.Text = string.format(
				"Rebirth %d: [%s] — Cost: %s Coins & 1-in-%s Aura\nRewards: +%.0f%% Base Luck | %.2fx Coins | +%d Vault Slots",
				tier.Level,
				tier.Title,
				formatNumber(tier.CoinCost),
				formatCommas(tier.RequiredAuraOneIn),
				tier.PermanentLuckBonus * 100,
				tier.PermanentCoinMultiplier,
				tier.BonusInventorySlots
			)
			lbl.Parent = row

			if isNext then
				local rebBtn = createDockButton(row, "ASCEND NOW", Color3.fromRGB(255, 130, 35), UDim2.new(0, 135, 0, 40))
				rebBtn.Position = UDim2.new(1, -146, 0.5, -20)
				rebBtn.MouseButton1Click:Connect(function()
					local ok, msg = ActionRequestFunc:InvokeServer("Rebirth")
					showToast(msg, if ok then Color3.fromRGB(255, 195, 50) else Color3.fromRGB(255, 85, 85))
					populateModal("Rebirth")
				end)
			end
		end

	elseif name == "Codes" then
		modalTitle.Text = "🎁 DAILY LOGIN STREAK & PROMO CODES"
		local dailyBtn = createDockButton(
			modalScroll,
			"📅 CLAIM DAILY STREAK REWARD",
			Color3.fromRGB(40, 195, 115),
			UDim2.new(1, -12, 0, 48)
		)
		dailyBtn.MouseButton1Click:Connect(function()
			local ok, msg = ActionRequestFunc:InvokeServer("ClaimDaily")
			showToast(msg, if ok then Color3.fromRGB(60, 255, 140) else Color3.fromRGB(255, 120, 90))
		end)

		local codeList = { "RELEASE", "OMEGA2026", "LUCKY777", "CYBERBLADE" }
		for _, code in ipairs(codeList) do
			local already = profile.RedeemedCodes[code] == true
			local info = GameConfig.PromoCodes[code]
			local btn = createDockButton(
				modalScroll,
				string.format(
					"%s — %s (%s)",
					code,
					info.Description,
					if already then "REDEEMED ✓" else "CLICK TO REDEEM!"
				),
				if already then Color3.fromRGB(55, 65, 85) else Color3.fromRGB(0, 155, 235),
				UDim2.new(1, -12, 0, 46)
			)
			btn.MouseButton1Click:Connect(function()
				local ok, msg = ActionRequestFunc:InvokeServer("RedeemCode", code)
				showToast(msg, if ok then Color3.fromRGB(0, 235, 255) else Color3.fromRGB(255, 95, 95))
				populateModal("Codes")
			end)
		end
	end
end

local function toggleModal(name: string)
	if activeModalName == name and modalFrame.Visible then
		modalFrame.Visible = false
		activeModalName = nil
	else
		activeModalName = name
		modalFrame.Visible = true
		populateModal(name)
	end
end

closeModalBtn.MouseButton1Click:Connect(function()
	modalFrame.Visible = false
	activeModalName = nil
end)

local navButtons = {
	{ Label = "🎒 AURA VAULT", Modal = "Vault", Color = Color3.fromRGB(0, 165, 235) },
	{ Label = "💎 ROBUX SHOP", Modal = "Shop", Color = Color3.fromRGB(45, 205, 120) },
	{ Label = "🔥 REBIRTHS", Modal = "Rebirth", Color = Color3.fromRGB(245, 125, 35) },
	{ Label = "🎁 FREE CODES", Modal = "Codes", Color = Color3.fromRGB(180, 75, 245) },
}

for _, nav in ipairs(navButtons) do
	local b = createDockButton(leftDock, nav.Label, nav.Color, UDim2.new(1, 0, 0, 50))
	b.MouseButton1Click:Connect(function()
		toggleModal(nav.Modal)
	end)
end

-- 7. MYTHIC / LEGENDARY FULL-SCREEN CUTSCENE OVERLAY
local cutsceneOverlay = Instance.new("Frame")
cutsceneOverlay.Size = UDim2.new(1, 0, 1, 0)
cutsceneOverlay.BackgroundColor3 = Color3.fromRGB(5, 6, 12)
cutsceneOverlay.BackgroundTransparency = 1
cutsceneOverlay.Visible = false
cutsceneOverlay.ZIndex = 20
cutsceneOverlay.Parent = screenGui

local cutsceneTitle = Instance.new("TextLabel")
cutsceneTitle.AnchorPoint = Vector2.new(0.5, 0.5)
cutsceneTitle.Position = UDim2.new(0.5, 0, 0.45, 0)
cutsceneTitle.Size = UDim2.new(0.85, 0, 0, 90)
cutsceneTitle.BackgroundTransparency = 1
cutsceneTitle.Font = Enum.Font.GothamBlack
cutsceneTitle.TextScaled = true
cutsceneTitle.ZIndex = 21
cutsceneTitle.Parent = cutsceneOverlay

local cutsceneSub = Instance.new("TextLabel")
cutsceneSub.AnchorPoint = Vector2.new(0.5, 0.5)
cutsceneSub.Position = UDim2.new(0.5, 0, 0.58, 0)
cutsceneSub.Size = UDim2.new(0.7, 0, 0, 44)
cutsceneSub.BackgroundTransparency = 1
cutsceneSub.Font = Enum.Font.GothamBold
cutsceneSub.TextColor3 = Color3.fromRGB(240, 245, 255)
cutsceneSub.TextScaled = true
cutsceneSub.ZIndex = 21
cutsceneSub.Parent = cutsceneOverlay

local function playMythicCutscene(aura: GameConfig.AuraDefinition)
	cutsceneOverlay.Visible = true
	cutsceneOverlay.BackgroundTransparency = 0.15
	cutsceneTitle.TextColor3 = aura.PrimaryColor
	cutsceneTitle.Text = string.format("★ %s ★", string.upper(aura.Name))
	cutsceneSub.Text = string.format("%s TIER  •  1 IN %s ODDS!", string.upper(aura.Tier), formatCommas(aura.OneIn))

	TweenService:Create(cutsceneOverlay, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(1.85, function()
		cutsceneOverlay.Visible = false
	end)
end

-- 8. WIRE ROLL, AUTO-ROLL, POTION, FAST-ROLL & DASH ACTIONS
local function triggerRoll(useFastToken: boolean)
	local ok, msg = ActionRequestFunc:InvokeServer("Roll", {
		UsePotion = usePotionArmed,
		UseFastToken = useFastToken,
	})
	if ok then
		usePotionArmed = false
	else
		showToast(msg, Color3.fromRGB(255, 110, 90))
	end
end

rollBtn.MouseButton1Click:Connect(function()
	triggerRoll(false)
end)

fastTokenBtn.MouseButton1Click:Connect(function()
	triggerRoll(true)
end)

potionBtn.MouseButton1Click:Connect(function()
	usePotionArmed = not usePotionArmed
	potionBtn.BackgroundColor3 = if usePotionArmed
		then Color3.fromRGB(50, 235, 130)
		else Color3.fromRGB(195, 45, 235)
	showToast(
		if usePotionArmed
			then "🧪 Singularity Potion ARMED (+500% Luck on next Roll)!"
			else "🧪 Singularity Potion disarmed.",
		Color3.fromRGB(215, 110, 255)
	)
end)

autoRollBtn.MouseButton1Click:Connect(function()
	local ok, msg = ActionRequestFunc:InvokeServer("ToggleAutoRoll")
	showToast(msg, if ok then Color3.fromRGB(165, 110, 255) else Color3.fromRGB(255, 95, 95))
end)

local function performDash()
	local now = os.clock()
	if now - lastDashTime < 1.4 then
		return
	end
	lastDashTime = now
	local char = localPlayer.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if root then
		root.AssemblyLinearVelocity = (root.CFrame.LookVector * 88) + Vector3.new(0, 18, 0)
	end
end

dashBtn.MouseButton1Click:Connect(performDash)

-- Keyboard & Mouse Combat / Roll Shortcuts
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		triggerRoll(false)
	elseif input.KeyCode == Enum.KeyCode.Q then
		performDash()
	elseif input.KeyCode == Enum.KeyCode.F or input.UserInputType == Enum.UserInputType.MouseButton1 then
		CombatSlashEvent:FireServer()
	end
end)

-- 9. SERVER EVENT LISTENERS
StateSyncEvent.OnClientEvent:Connect(function(state: any)
	currentState = state
	local p = state.Profile
	coinsLabel.Text = string.format("🪙 %s Coins", formatNumber(p.Coins))
	gemsLabel.Text = string.format("💎 %s Gems", formatNumber(p.Gems))
	luckLabel.Text = string.format("🍀 %.2fx Luck", state.TotalLuck or 1.0)
	rebirthLabel.Text = string.format("🔥 Rebirth %d", p.Rebirths)

	if (state.ServerBoostRemaining or 0) > 0 then
		boostTimerLabel.Text = string.format("🎉 2x Party: %ds", state.ServerBoostRemaining)
	elseif (state.ObbyBuffRemaining or 0) > 0 then
		boostTimerLabel.Text = string.format("🏃 2x Obby: %ds", state.ObbyBuffRemaining)
	else
		boostTimerLabel.Text = string.format("👥 Friends: +%d%%", (state.FriendsInServer or 0) * 10)
	end

	autoRollBtn.Text = if p.AutoRollEnabled then "🤖 AUTO: ON" else "🤖 AUTO: OFF"
	autoRollBtn.BackgroundColor3 = if p.AutoRollEnabled
		then Color3.fromRGB(45, 200, 110)
		else Color3.fromRGB(115, 55, 220)
	fastTokenBtn.Text = string.format("⚡ FAST ROLL (%d)", p.FastRollTokens)
	potionBtn.Text = string.format(
		"🧪 %s (%d)",
		if usePotionArmed then "ARMED!" else "+500% POTION",
		p.HeavenlyPotions
	)

	if activeModalName and modalFrame.Visible then
		populateModal(activeModalName)
	end
end)

RollResultEvent.OnClientEvent:Connect(function(result: any)
	local bestAura = GameConfig.GetAuraById(result.BestAuraId)
	local count = if result.AllAuraIds then #result.AllAuraIds else 1
	local prefix = if count > 1 then string.format("[%dx Roll Best] ", count) else ""
	showToast(
		string.format(
			"🎲 %sRolled [%s] (%s • 1 in %s)  |  +%d Coins!",
			prefix,
			bestAura.Name,
			bestAura.Tier,
			formatCommas(bestAura.OneIn),
			result.CoinsEarned or 0
		),
		bestAura.PrimaryColor
	)
	if bestAura.HasCutscene then
		playMythicCutscene(bestAura)
	end
end)

ServerAnnounceEvent.OnClientEvent:Connect(function(msg: string, color: Color3)
	showToast(msg, color)
end)

CombatHitFeedbackEvent.OnClientEvent:Connect(function(dmg: number, isCrit: boolean)
	showToast(
		string.format("⚔️ %sHit Boss for %d Damage! (+Coins)", if isCrit then "CRITICAL STRIKE! " else "", dmg),
		if isCrit then Color3.fromRGB(255, 215, 45) else Color3.fromRGB(0, 225, 255)
	)
end)

BossStateEvent.OnClientEvent:Connect(function(info: any)
	local ratio = if info.MaxHP > 0 then math.clamp(info.HP / info.MaxHP, 0, 1) else 0
	bossFill.Size = UDim2.new(ratio, 0, 1, 0)
	bossFill.BackgroundColor3 = info.Color or Color3.fromRGB(200, 35, 65)
	bossTitle.Text = string.format(
		"⚔️ %s (%d / %d HP) — Click or Press [F] in Arena to Slash!",
		info.Name,
		math.max(0, math.floor(info.HP)),
		info.MaxHP
	)
end)

task.defer(function()
	ActionRequestFunc:InvokeServer("RequestState")
end)
