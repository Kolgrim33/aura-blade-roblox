--!strict
--[[
	VisualAuraBuilder.luau
	Procedural 3D Cyber Blade, Orbiting Aura Shards, Particle Rings, and
	Overhead Title BillboardGui generator for AURA BLADE: RNG & BOSS ARENA.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local VisualAuraBuilder = {}

type ActiveRigAura = {
	Folder: Folder,
	Orbs: { BasePart },
	PrimaryColor: Color3,
	OrbitRadius: number,
	OrbitSpeed: number,
}

local activeAuras: { [Model]: ActiveRigAura } = {}

local function formatCommaNumber(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

function VisualAuraBuilder.ClearCharacterVisuals(character: Model)
	activeAuras[character] = nil
	local existing = character:FindFirstChild("AuraBladeVisuals")
	if existing then
		existing:Destroy()
	end
	local head = character:FindFirstChild("Head")
	if head then
		local tag = head:FindFirstChild("AuraTitleBillboard")
		if tag then
			tag:Destroy()
		end
	end
end

function VisualAuraBuilder.ApplyAuraToCharacter(
	player: Player,
	auraId: string,
	rebirths: number,
	isVIP: boolean
)
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = character:FindFirstChild("Head") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not head or not humanoid then
		return
	end

	VisualAuraBuilder.ClearCharacterVisuals(character)
	local aura = GameConfig.GetAuraById(auraId)

	-- Apply movement speed bonus from equipped Aura
	humanoid.WalkSpeed = 18 + aura.SpeedBonus

	local visualsFolder = Instance.new("Folder")
	visualsFolder.Name = "AuraBladeVisuals"
	visualsFolder.Parent = character

	-- 1. Core PointLight & Particle Emitter on HumanoidRootPart
	local light = Instance.new("PointLight")
	light.Name = "AuraGlow"
	light.Color = aura.PrimaryColor
	light.Brightness = 2.5 + math.min(4, math.log10(math.max(2, aura.OneIn)))
	light.Range = 14 + math.min(18, aura.OrbitOrbs * 1.5)
	light.Parent = rootPart

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "AuraSparks"
	particles.Color = ColorSequence.new(aura.PrimaryColor, aura.SecondaryColor)
	particles.LightEmission = 1
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.6, 0.85),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = NumberRange.new(0.7, 1.35)
	particles.Rate = 18 + (aura.OrbitOrbs * 6)
	particles.Speed = NumberRange.new(3, 8)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Parent = rootPart

	-- 2. Procedural 3D Cyber Katana welded to RightHand / Right Arm
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") or rootPart) :: BasePart
	local bladeModel = Instance.new("Model")
	bladeModel.Name = "CyberKatana"
	bladeModel.Parent = visualsFolder

	local hilt = Instance.new("Part")
	hilt.Name = "Hilt"
	hilt.Size = Vector3.new(0.32, 0.32, 1.35)
	hilt.Material = Enum.Material.Metal
	hilt.Color = Color3.fromRGB(28, 32, 42)
	hilt.CanCollide = false
	hilt.Massless = true
	hilt.CFrame = hand.CFrame * CFrame.new(0, -0.4, -0.5)
	hilt.Parent = bladeModel

	local handWeld = Instance.new("WeldConstraint")
	handWeld.Part0 = hand
	handWeld.Part1 = hilt
	handWeld.Parent = hilt

	local bladeEdge = Instance.new("Part")
	bladeEdge.Name = "NeonEdge"
	bladeEdge.Size = Vector3.new(0.14, 0.36, 4.1)
	bladeEdge.Material = Enum.Material.Neon
	bladeEdge.Color = aura.PrimaryColor
	bladeEdge.CanCollide = false
	bladeEdge.Massless = true
	bladeEdge.CFrame = hilt.CFrame * CFrame.new(0, 0, -2.65)
	bladeEdge.Parent = bladeModel

	local bladeWeld = Instance.new("WeldConstraint")
	bladeWeld.Part0 = hilt
	bladeWeld.Part1 = bladeEdge
	bladeWeld.Parent = bladeEdge

	-- Slash Trail on the Neon Edge
	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0.18, -2.0)
	att0.Parent = bladeEdge

	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, -0.18, 2.0)
	att1.Parent = bladeEdge

	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = ColorSequence.new(aura.PrimaryColor, aura.SecondaryColor)
	trail.LightEmission = 1
	trail.Lifetime = 0.28
	trail.Transparency = NumberSequence.new(0.15, 1.0)
	trail.Parent = bladeEdge

	-- 3. Orbiting 3D Neon Shards around the player
	local orbs: { BasePart } = {}
	for i = 1, aura.OrbitOrbs do
		local orb = Instance.new("Part")
		orb.Name = "AuraOrb_" .. tostring(i)
		orb.Size = Vector3.new(0.65, 1.25, 0.65)
		orb.Material = Enum.Material.Neon
		orb.Color = if i % 2 == 0 then aura.SecondaryColor else aura.PrimaryColor
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CanTouch = false
		orb.CFrame = rootPart.CFrame
		orb.Parent = visualsFolder
		table.insert(orbs, orb)
	end

	activeAuras[character] = {
		Folder = visualsFolder,
		Orbs = orbs,
		PrimaryColor = aura.PrimaryColor,
		OrbitRadius = 4.2 + math.min(3.5, aura.OrbitOrbs * 0.25),
		OrbitSpeed = 2.0 + math.min(3.0, aura.OrbitOrbs * 0.2),
	}

	-- 4. Overhead Title & Odds BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "AuraTitleBillboard"
	bb.Adornee = head
	bb.Size = UDim2.new(0, 240, 0, 72)
	bb.StudsOffset = Vector3.new(0, 3.1, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.Parent = head

	local topLine = Instance.new("TextLabel")
	topLine.BackgroundTransparency = 1
	topLine.Size = UDim2.new(1, 0, 0.36, 0)
	topLine.Font = Enum.Font.GothamBold
	local vipPrefix = if isVIP then "👑 [VIP] " else ""
	local rebInfo = GameConfig.GetRebirthTier(rebirths)
	local rebTag = if rebInfo then string.format("[%s] ", rebInfo.Title) else ""
	topLine.Text = vipPrefix .. rebTag .. player.DisplayName
	topLine.TextColor3 = if isVIP then Color3.fromRGB(255, 220, 65) else Color3.fromRGB(235, 240, 255)
	topLine.TextScaled = true
	topLine.TextStrokeTransparency = 0.25
	topLine.Parent = bb

	local auraLine = Instance.new("TextLabel")
	auraLine.BackgroundTransparency = 1
	auraLine.Position = UDim2.new(0, 0, 0.36, 0)
	auraLine.Size = UDim2.new(1, 0, 0.64, 0)
	auraLine.Font = Enum.Font.GothamBlack
	auraLine.Text = string.format("★ %s [1 in %s] ★", string.upper(aura.Name), formatCommaNumber(aura.OneIn))
	auraLine.TextColor3 = aura.PrimaryColor
	auraLine.TextScaled = true
	auraLine.TextStrokeTransparency = 0.15
	auraLine.Parent = bb
end

function VisualAuraBuilder.StartOrbitLoop()
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for character, data in pairs(activeAuras) do
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not character.Parent or not root then
				activeAuras[character] = nil
				continue
			end

			local count = #data.Orbs
			for i, orb in ipairs(data.Orbs) do
				if orb.Parent then
					local angle = (t * data.OrbitSpeed) + ((i - 1) * (math.pi * 2 / count))
					local bob = math.sin((t * 3.2) + i) * 0.85
					local offset = Vector3.new(
						math.cos(angle) * data.OrbitRadius,
						bob,
						math.sin(angle) * data.OrbitRadius
					)
					local targetPos = root.Position + offset
					orb.CFrame = CFrame.lookAt(targetPos, root.Position) * CFrame.Angles(t * 2, 0, 0)
				end
			end
		end
	end)
end

return VisualAuraBuilder
