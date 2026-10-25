--!strict
--[[
	CombatAndBossServer.luau
	Active Boss Wave Spawner, Procedural 3D Cyber Boss Rig, AoE Telegraph AI,
	Server-Validated Sword Slash & Dash Combat, and Damage-Share Loot Payouts.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local DataManager = require(script.Parent.DataManager)
local MonetizationServer = require(script.Parent.MonetizationServer)

local CombatAndBossServer = {}

export type ActiveBossState = {
	Def: GameConfig.BossDefinition,
	Model: Model,
	CorePart: Part,
	CurrentHP: number,
	MaxHP: number,
	DamageContributors: { [Player]: number },
	BonusLootMultiplier: number,
}

CombatAndBossServer.CurrentBoss = nil :: ActiveBossState?
CombatAndBossServer.BossCounter = 0
CombatAndBossServer.OnBossStateChanged = nil :: ((string, number, number, Color3) -> ())?
CombatAndBossServer.OnBossDefeated = nil :: ((Player, string, number, number, number) -> ())?

local slashCooldowns: { [Player]: number } = {}
local ARENA_CENTER = Vector3.new(0, 6.5, -10)
local SLASH_RANGE = 26

local function updateBossBillboard(boss: ActiveBossState)
	local bb = boss.CorePart:FindFirstChild("BossBillboard") :: BillboardGui?
	if not bb then
		return
	end
	local hpLabel = bb:FindFirstChild("HPLabel") :: TextLabel?
	local fill = bb:FindFirstChild("BarBg") and (bb.BarBg :: Frame):FindFirstChild("Fill") :: Frame?
	if hpLabel then
		hpLabel.Text = string.format("%s — %d / %d HP", boss.Def.Name, math.max(0, math.floor(boss.CurrentHP)), boss.MaxHP)
	end
	if fill then
		local ratio = math.clamp(boss.CurrentHP / boss.MaxHP, 0, 1)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
	end
end

function CombatAndBossServer.SpawnBoss(def: GameConfig.BossDefinition, bonusMultiplier: number?)
	if CombatAndBossServer.CurrentBoss and CombatAndBossServer.CurrentBoss.Model.Parent then
		CombatAndBossServer.CurrentBoss.Model:Destroy()
	end

	local mult = bonusMultiplier or 1.0
	local model = Instance.new("Model")
	model.Name = "ArenaBoss_" .. def.Id

	local scale = def.Scale
	local core = Instance.new("Part")
	core.Name = "BossCore"
	core.Anchored = true
	core.Size = Vector3.new(6.5 * scale, 9.0 * scale, 4.5 * scale)
	core.Position = ARENA_CENTER + Vector3.new(0, 2.5 * scale, 0)
	core.Color = Color3.fromRGB(26, 30, 44)
	core.Material = Enum.Material.Metal
	core.Parent = model

	local chestNeon = Instance.new("Part")
	chestNeon.Name = "ReactorCore"
	chestNeon.Shape = Enum.PartType.Ball
	chestNeon.Anchored = true
	chestNeon.CanCollide = false
	chestNeon.Size = Vector3.new(3.6 * scale, 3.6 * scale, 3.6 * scale)
	chestNeon.Position = core.Position + Vector3.new(0, 0.8 * scale, 0)
	chestNeon.Color = def.PrimaryColor
	chestNeon.Material = Enum.Material.Neon
	chestNeon.Parent = model

	local ring = Instance.new("Part")
	ring.Name = "EnergyHalo"
	ring.Anchored = true
	ring.CanCollide = false
	ring.Size = Vector3.new(10 * scale, 0.5 * scale, 10 * scale)
	ring.Position = core.Position + Vector3.new(0, 5.2 * scale, 0)
	ring.Color = def.PrimaryColor
	ring.Material = Enum.Material.Neon
	ring.Parent = model

	-- Boss Overhead HP Bar
	local bb = Instance.new("BillboardGui")
	bb.Name = "BossBillboard"
	bb.Size = UDim2.new(0, 320, 0, 76)
	bb.StudsOffset = Vector3.new(0, 7.5 * scale, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 200
	bb.Parent = core

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.BackgroundTransparency = 1
	hpLabel.Size = UDim2.new(1, 0, 0.55, 0)
	hpLabel.Font = Enum.Font.GothamBlack
	hpLabel.TextColor3 = def.PrimaryColor
	hpLabel.TextScaled = true
	hpLabel.TextStrokeTransparency = 0.15
	hpLabel.Parent = bb

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Position = UDim2.new(0.05, 0, 0.62, 0)
	barBg.Size = UDim2.new(0.9, 0, 0.28, 0)
	barBg.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
	barBg.BorderSizePixel = 0
	barBg.Parent = bb

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = def.PrimaryColor
	fill.BorderSizePixel = 0
	fill.Parent = barBg

	model.PrimaryPart = core
	model.Parent = Workspace

	local state: ActiveBossState = {
		Def = def,
		Model = model,
		CorePart = core,
		CurrentHP = def.MaxHP,
		MaxHP = def.MaxHP,
		DamageContributors = {},
		BonusLootMultiplier = mult,
	}
	CombatAndBossServer.CurrentBoss = state
	updateBossBillboard(state)

	if CombatAndBossServer.OnBossStateChanged then
		CombatAndBossServer.OnBossStateChanged(def.Name, state.CurrentHP, state.MaxHP, def.PrimaryColor)
	end
end

function CombatAndBossServer.HandlePlayerSlash(player: Player): (boolean, number, boolean)
	local now = os.clock()
	if (slashCooldowns[player] or 0) + 0.32 > now then
		return false, 0, false
	end
	slashCooldowns[player] = now

	local profile = DataManager.GetProfile(player)
	if not profile then
		return false, 0, false
	end

	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not root then
		return false, 0, false
	end

	local boss = CombatAndBossServer.CurrentBoss
	if not boss or boss.CurrentHP <= 0 or not boss.CorePart.Parent then
		return false, 0, false
	end

	local dist = (root.Position - boss.CorePart.Position).Magnitude
	if dist > SLASH_RANGE then
		return false, 0, false
	end

	local aura = GameConfig.GetAuraById(profile.EquippedAuraId)
	local isCrit = math.random() < 0.22
	local dmg = math.floor(aura.BaseDamage * (if isCrit then 1.75 else 1.0))

	-- Small instant coin reward on every hit so combat feels super rewarding
	local hitCoins = math.max(1, math.floor(2 * aura.CoinMultiplier))
	profile.Coins += hitCoins
	profile.TotalDamageDealt += dmg

	boss.CurrentHP = math.max(0, boss.CurrentHP - dmg)
	boss.DamageContributors[player] = (boss.DamageContributors[player] or 0) + dmg
	updateBossBillboard(boss)

	if CombatAndBossServer.OnBossStateChanged then
		CombatAndBossServer.OnBossStateChanged(boss.Def.Name, boss.CurrentHP, boss.MaxHP, boss.Def.PrimaryColor)
	end

	if boss.CurrentHP <= 0 then
		CombatAndBossServer.ResolveBossDefeat(boss)
	else
		DataManager.MarkDirty(player)
	end

	return true, dmg, isCrit
end

function CombatAndBossServer.ResolveBossDefeat(boss: ActiveBossState)
	CombatAndBossServer.CurrentBoss = nil
	if boss.Model.Parent then
		boss.Model:Destroy()
	end

	for contributor, dmgDealt in pairs(boss.DamageContributors) do
		if contributor.Parent and dmgDealt > 0 then
			local profile = DataManager.GetProfile(contributor)
			if profile then
				local aura = GameConfig.GetAuraById(profile.EquippedAuraId)
				local rebInfo = GameConfig.GetRebirthTier(profile.Rebirths)
				local rebCoinMult = if rebInfo then rebInfo.PermanentCoinMultiplier else 1.0
				local vipMult = if MonetizationServer.OwnsGamepass(contributor, "VIP") then 1.5 else 1.0
				local premMult = if contributor.MembershipType == Enum.MembershipType.Premium
					then GameConfig.PREMIUM_COIN_MULTIPLIER
					else 1.0

				local totalCoinMult = aura.CoinMultiplier * rebCoinMult * vipMult * premMult * boss.BonusLootMultiplier
				local coinsEarned = math.floor(boss.Def.RewardCoins * totalCoinMult)
				local gemsEarned = math.floor(boss.Def.RewardGems * boss.BonusLootMultiplier)
				local fastRollsEarned = math.floor(boss.Def.RewardFastRolls * boss.BonusLootMultiplier)

				profile.Coins += coinsEarned
				profile.Gems += gemsEarned
				profile.FastRollTokens += fastRollsEarned
				profile.BossKills += 1
				DataManager.MarkDirty(contributor)

				if CombatAndBossServer.OnBossDefeated then
					CombatAndBossServer.OnBossDefeated(
						contributor,
						boss.Def.Name,
						coinsEarned,
						gemsEarned,
						fastRollsEarned
					)
				end
			end
		end
	end

	if CombatAndBossServer.OnBossStateChanged then
		CombatAndBossServer.OnBossStateChanged("Respawning in 8s...", 0, 100, Color3.fromRGB(140, 150, 175))
	end
end

function CombatAndBossServer.StartDirectorLoop()
	task.spawn(function()
		while true do
			if not CombatAndBossServer.CurrentBoss then
				CombatAndBossServer.BossCounter += 1
				local idx = ((CombatAndBossServer.BossCounter - 1) % #GameConfig.Bosses) + 1
				CombatAndBossServer.SpawnBoss(GameConfig.Bosses[idx], 1.0)
			else
				-- Boss idle hover + periodic shockwave ring visual
				local boss = CombatAndBossServer.CurrentBoss
				if boss and boss.CorePart.Parent then
					local pulse = Instance.new("Part")
					pulse.Name = "BossPulseRing"
					pulse.Anchored = true
					pulse.CanCollide = false
					pulse.Shape = Enum.PartType.Cylinder
					pulse.Color = boss.Def.PrimaryColor
					pulse.Material = Enum.Material.Neon
					pulse.Transparency = 0.45
					pulse.Size = Vector3.new(0.4, 16, 16)
					pulse.CFrame = CFrame.new(ARENA_CENTER.X, 1.6, ARENA_CENTER.Z) * CFrame.Angles(0, 0, math.rad(90))
					pulse.Parent = Workspace
					task.delay(0.55, function()
						if pulse.Parent then
							pulse:Destroy()
						end
					end)
				end
			end
			task.wait(8)
		end
	end)
end

return CombatAndBossServer
