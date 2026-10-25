--!strict
--[[
	WorldBuilder.luau
	Procedural 3D Neon Cyber Arena, Sky Obby Course, VIP Lounge,
	Mythic Showcase Pedestals, and Physical Leaderboard builder.
	Generates the entire playable world automatically on Server boot!
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local WorldBuilder = {}

local function createPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

local function attachBillboardSign(parent: BasePart, title: string, subtitle: string, accentColor: Color3)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 260, 0, 80)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 150
	bb.Parent = parent

	local lbl1 = Instance.new("TextLabel")
	lbl1.BackgroundTransparency = 1
	lbl1.Size = UDim2.new(1, 0, 0.55, 0)
	lbl1.Font = Enum.Font.GothamBlack
	lbl1.Text = title
	lbl1.TextColor3 = accentColor
	lbl1.TextScaled = true
	lbl1.TextStrokeTransparency = 0.2
	lbl1.Parent = bb

	local lbl2 = Instance.new("TextLabel")
	lbl2.BackgroundTransparency = 1
	lbl2.Position = UDim2.new(0, 0, 0.55, 0)
	lbl2.Size = UDim2.new(1, 0, 0.45, 0)
	lbl2.Font = Enum.Font.GothamBold
	lbl2.Text = subtitle
	lbl2.TextColor3 = Color3.fromRGB(235, 240, 255)
	lbl2.TextScaled = true
	lbl2.TextStrokeTransparency = 0.3
	lbl2.Parent = bb
end

function WorldBuilder.ConfigureLighting()
	Lighting.Ambient = Color3.fromRGB(22, 26, 42)
	Lighting.OutdoorAmbient = Color3.fromRGB(32, 38, 64)
	Lighting.Brightness = 2.2
	Lighting.ClockTime = 0
	Lighting.FogEnd = 1200
	Lighting.FogColor = Color3.fromRGB(10, 12, 24)

	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.65
		bloom.Size = 24
		bloom.Threshold = 0.85
		bloom.Parent = Lighting
	end
end

function WorldBuilder.BuildWorld(
	onObbyPadTouched: (Player) -> (),
	onVipFountainTouched: (Player) -> (),
	onQuickShopPedestalTouched: (Player, string, string) -> ()
): Folder
	WorldBuilder.ConfigureLighting()

	local existing = Workspace:FindFirstChild("AuraBladeWorld")
	if existing then
		existing:Destroy()
	end

	-- Remove default Baseplate if present so our custom Cyber Plaza shines
	local defaultBaseplate = Workspace:FindFirstChild("Baseplate")
	if defaultBaseplate then
		defaultBaseplate:Destroy()
	end

	local world = Instance.new("Folder")
	world.Name = "AuraBladeWorld"
	world.Parent = Workspace

	-- 1. CENTRAL CYBER PLAZA FLOOR
	createPart({
		Name = "CyberPlazaFloor",
		Size = Vector3.new(280, 4, 280),
		Position = Vector3.new(0, -2, 0),
		Color = Color3.fromRGB(18, 22, 34),
		Material = Enum.Material.Concrete,
		Parent = world,
	})

	-- Glowing Neon Grid Lines on the Plaza
	for offset = -120, 120, 30 do
		createPart({
			Name = "NeonGridX_" .. tostring(offset),
			Size = Vector3.new(260, 0.15, 0.65),
			Position = Vector3.new(0, 0.05, offset),
			Color = Color3.fromRGB(0, 180, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = world,
		})
		createPart({
			Name = "NeonGridZ_" .. tostring(offset),
			Size = Vector3.new(0.65, 0.15, 260),
			Position = Vector3.new(offset, 0.05, 0),
			Color = Color3.fromRGB(0, 180, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = world,
		})
	end

	-- 2. SPAWN LOCATION (South Plaza)
	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "CyberSpawn"
	spawnLoc.Anchored = true
	spawnLoc.Size = Vector3.new(18, 1.2, 18)
	spawnLoc.Position = Vector3.new(0, 0.6, 70)
	spawnLoc.Color = Color3.fromRGB(0, 225, 255)
	spawnLoc.Material = Enum.Material.Neon
	spawnLoc.Neutral = true
	spawnLoc.TopSurface = Enum.SurfaceType.Smooth
	spawnLoc.Parent = world

	attachBillboardSign(
		spawnLoc,
		"⚔️ AURA BLADE: RNG & BOSS ARENA ⚔️",
		"Roll Mythic Auras • Slash Arena Bosses • Conquer the 2x Luck Sky Obby!",
		Color3.fromRGB(0, 235, 255)
	)

	-- 3. CENTER BOSS COLOSSEUM ARENA (Origin 0, 0, -10)
	local arenaFloor = createPart({
		Name = "BossColosseumFloor",
		Size = Vector3.new(76, 1.5, 76),
		Position = Vector3.new(0, 0.75, -10),
		Color = Color3.fromRGB(28, 18, 42),
		Material = Enum.Material.Granite,
		Parent = world,
	})

	createPart({
		Name = "BossSpawnAltar",
		Size = Vector3.new(14, 1.2, 14),
		Position = Vector3.new(0, 1.8, -10),
		Color = Color3.fromRGB(255, 55, 95),
		Material = Enum.Material.Neon,
		Parent = world,
	})

	attachBillboardSign(
		arenaFloor,
		"🔥 BOSS COLOSSEUM ARENA 🔥",
		"Click or Press [F] to Slash Bosses for Massive Flux Coins, Gems & Free Fast Rolls!",
		Color3.fromRGB(255, 75, 95)
	)

	-- 4. PHYSICAL ROBUX & BOOSTER PEDESTALS (High-visibility 3D impulse conversion pads)
	local shopPads = {
		{
			Pos = Vector3.new(-32, 1.2, 52),
			Kind = "Gamepass",
			Key = "DoubleLuck",
			Title = "🍀 2X LUCK FOREVER",
			Sub = "Step to Unlock Permanent 2x Roll Luck!",
			Color = Color3.fromRGB(45, 255, 130),
		},
		{
			Pos = Vector3.new(-16, 1.2, 52),
			Kind = "Gamepass",
			Key = "TripleRoll",
			Title = "⚡ 3X TRIPLE ROLL",
			Sub = "Roll 3 Auras At Once!",
			Color = Color3.fromRGB(255, 185, 35),
		},
		{
			Pos = Vector3.new(16, 1.2, 52),
			Kind = "Gamepass",
			Key = "VIP",
			Title = "👑 VIP CYBER SOVEREIGN",
			Sub = "+50% Coins, +25% Luck & Crown!",
			Color = Color3.fromRGB(255, 220, 55),
		},
		{
			Pos = Vector3.new(32, 1.2, 52),
			Kind = "DevProduct",
			Key = "ServerLuckBoost",
			Title = "🎉 2X SERVER LUCK PARTY",
			Sub = "Boost the Entire Server for 15m!",
			Color = Color3.fromRGB(185, 85, 255),
		},
	}

	local padDebounce: { [Player]: number } = {}
	for _, info in ipairs(shopPads) do
		local pad = createPart({
			Name = "ShopPad_" .. info.Key,
			Size = Vector3.new(8, 1.4, 8),
			Position = info.Pos,
			Color = info.Color,
			Material = Enum.Material.Neon,
			Parent = world,
		})
		attachBillboardSign(pad, info.Title, info.Sub, info.Color)

		pad.Touched:Connect(function(hit)
			local char = hit.Parent
			local player = if char then game:GetService("Players"):GetPlayerFromCharacter(char) else nil
			if player then
				local now = os.clock()
				if (padDebounce[player] or 0) + 3.0 < now then
					padDebounce[player] = now
					onQuickShopPedestalTouched(player, info.Kind, info.Key)
				end
			end
		end)
	end

	-- 5. VIP CYBER LOUNGE (+35% LUCK FOUNTAIN) - West Plaza
	local vipBase = createPart({
		Name = "VipLoungePlatform",
		Size = Vector3.new(36, 2, 36),
		Position = Vector3.new(-82, 1, 0),
		Color = Color3.fromRGB(48, 40, 18),
		Material = Enum.Material.Marble,
		Parent = world,
	})

	local vipFountain = createPart({
		Name = "VipLuckFountain",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 12, 12),
		CFrame = CFrame.new(-82, 3.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 215, 50),
		Material = Enum.Material.Neon,
		Parent = world,
	})
	attachBillboardSign(
		vipFountain,
		"👑 VIP & REBIRTH 3+ SANCTUM 👑",
		"Touch for +35% Bonus Aura Roll Luck!",
		Color3.fromRGB(255, 215, 50)
	)
	local _ = vipBase

	local vipDebounce: { [Player]: number } = {}
	vipFountain.Touched:Connect(function(hit)
		local char = hit.Parent
		local player = if char then game:GetService("Players"):GetPlayerFromCharacter(char) else nil
		if player then
			local now = os.clock()
			if (vipDebounce[player] or 0) + 2.0 < now then
				vipDebounce[player] = now
				onVipFountainTouched(player)
			end
		end
	end)

	-- 6. NEON SKY OBBY COURSE (East Plaza -> Ascends to +100% 2X LUCK SUMMIT PAD)
	local obbyFolder = Instance.new("Folder")
	obbyFolder.Name = "NeonSkyObby"
	obbyFolder.Parent = world

	local startSign = createPart({
		Name = "ObbyStartPad",
		Size = Vector3.new(12, 1.5, 12),
		Position = Vector3.new(62, 1, 45),
		Color = Color3.fromRGB(0, 255, 155),
		Material = Enum.Material.Neon,
		Parent = obbyFolder,
	})
	attachBillboardSign(
		startSign,
		"🏃 NEON SKY OBBY START 🏃",
		"Reach the Summit for 5 Minutes of +100% (2X) ROLL LUCK + 500 Bonus Coins!",
		Color3.fromRGB(0, 255, 155)
	)

	local numStages = 12
	for i = 1, numStages do
		local zPos = 45 - (i * 10)
		local xOffset = math.sin(i * 0.9) * 8
		local yPos = 1 + (i * 3.2)
		createPart({
			Name = "ObbyStep_" .. tostring(i),
			Size = Vector3.new(7, 1.2, 5.5),
			Position = Vector3.new(68 + xOffset, yPos, zPos),
			Color = Color3.fromHSV((i / numStages) * 0.75, 0.85, 1.0),
			Material = Enum.Material.Neon,
			Parent = obbyFolder,
		})
	end

	local summitPad = createPart({
		Name = "ObbySummitPad",
		Size = Vector3.new(16, 2, 16),
		Position = Vector3.new(68, 1 + ((numStages + 1) * 3.2), 45 - ((numStages + 1) * 10)),
		Color = Color3.fromRGB(50, 255, 130),
		Material = Enum.Material.Neon,
		Parent = obbyFolder,
	})
	attachBillboardSign(
		summitPad,
		"🏆 SKY OBBY SUMMIT: +100% LUCK! 🏆",
		"Step Here to Claim +100% Roll Luck (5m) + 500 Flux Coins & Return to Plaza!",
		Color3.fromRGB(50, 255, 130)
	)

	local obbyDebounce: { [Player]: number } = {}
	summitPad.Touched:Connect(function(hit)
		local char = hit.Parent
		local player = if char then game:GetService("Players"):GetPlayerFromCharacter(char) else nil
		if player then
			local now = os.clock()
			if (obbyDebounce[player] or 0) + 4.0 < now then
				obbyDebounce[player] = now
				onObbyPadTouched(player)
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					root.CFrame = spawnLoc.CFrame + Vector3.new(0, 4, 0)
				end
			end
		end
	end)

	-- 7. MYTHIC & CELESTIAL AURA SHOWCASE MONOLITHS (North Plaza)
	local showcaseIndices = { 10, 12, 13, 16 }
	for idx, auraIndex in ipairs(showcaseIndices) do
		local aura = GameConfig.Auras[auraIndex]
		if aura then
			local xPos = -45 + ((idx - 1) * 30)
			local pedestal = createPart({
				Name = "Showcase_" .. aura.Id,
				Size = Vector3.new(8, 10, 4),
				Position = Vector3.new(xPos, 5, -78),
				Color = aura.PrimaryColor,
				Material = Enum.Material.Neon,
				Parent = world,
			})
			attachBillboardSign(
				pedestal,
				string.format("★ %s ★", aura.Name),
				string.format("[%s • 1 in %d] +%d DMG | %gx Coins", aura.Tier, aura.OneIn, aura.BaseDamage, aura.CoinMultiplier),
				aura.PrimaryColor
			)
		end
	end

	return world
end

return WorldBuilder
