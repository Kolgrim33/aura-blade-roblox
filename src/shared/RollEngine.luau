--!strict
--[[
	RollEngine.luau
	Weighted RNG & Pity calculation engine for AURA BLADE: RNG & BOSS ARENA.
	Computes effective player luck from all active sources (Rebirths, Gamepasses,
	Roblox Premium, Friends in Server, Sky Obby Buff, VIP Fountain, Server Boost,
	and Singularity Potions) and rolls single or triple Auras.
]]

local GameConfig = require(script.Parent.GameConfig)

export type LuckContext = {
	RebirthLevel: number,
	OwnsDoubleLuck: boolean,
	OwnsVIP: boolean,
	IsPremium: boolean,
	FriendsInServer: number,
	HasObbyBuff: boolean,
	HasVipFountainBuff: boolean,
	ServerBoostActive: boolean,
	UseHeavenlyPotion: boolean,
	TotalRolls: number,
}

export type LuckBreakdown = {
	BaseLuck: number,
	AdditiveBonus: number,
	Multiplier: number,
	TotalLuck: number,
	GuaranteedMinOneIn: number,
}

local RollEngine = {}

function RollEngine.ComputeLuck(ctx: LuckContext): LuckBreakdown
	local base = 1.0
	local additive = 0.0

	-- 1. Rebirth permanent luck bonus
	local rebirthInfo = GameConfig.GetRebirthTier(ctx.RebirthLevel)
	if rebirthInfo then
		additive += rebirthInfo.PermanentLuckBonus
	end

	-- 2. VIP Gamepass (+25% additive base luck)
	if ctx.OwnsVIP then
		additive += 0.25
	end

	-- 3. Roblox Premium subscriber bonus (+25% luck)
	if ctx.IsPremium then
		additive += GameConfig.PREMIUM_LUCK_BONUS
	end

	-- 4. Friends in server viral bonus (+10% per friend, up to +50%)
	local friendBonus = math.min(
		ctx.FriendsInServer * GameConfig.FRIEND_LUCK_BONUS_PER_FRIEND,
		GameConfig.MAX_FRIEND_LUCK_BONUS
	)
	additive += friendBonus

	-- 5. Sky Obby completion buff (+100% luck for 5 minutes)
	if ctx.HasObbyBuff then
		additive += GameConfig.OBBY_LUCK_BONUS
	end

	-- 6. VIP Fountain aura buff (+35% luck)
	if ctx.HasVipFountainBuff then
		additive += GameConfig.VIP_FOUNTAIN_LUCK_BONUS
	end

	-- 7. Singularity Potion (+500% next-roll burst)
	if ctx.UseHeavenlyPotion then
		additive += 5.0
	end

	-- Multiplicative stacks (2x Luck Gamepass & 2x Server Luck Party)
	local mult = 1.0
	if ctx.OwnsDoubleLuck then
		mult *= 2.0
	end
	if ctx.ServerBoostActive then
		mult *= 2.0
	end

	local totalLuck = (base + additive) * mult

	-- Pity floor calculation (next roll index = TotalRolls + 1)
	local nextRollNumber = ctx.TotalRolls + 1
	local guaranteedMinOneIn = 0
	if nextRollNumber % GameConfig.LEGENDARY_PITY_THRESHOLD == 0 then
		guaranteedMinOneIn = 3500 -- Guaranteed Legendary+
	elseif nextRollNumber % GameConfig.EPIC_PITY_THRESHOLD == 0 then
		guaranteedMinOneIn = 500 -- Guaranteed Epic+
	end

	return {
		BaseLuck = base,
		AdditiveBonus = additive,
		Multiplier = mult,
		TotalLuck = totalLuck,
		GuaranteedMinOneIn = guaranteedMinOneIn,
	}
end

--[[
	Rolls a single Aura using luck-scaled inverse-odds weighting.
	Higher luck boosts rare aura weights proportionally while clamping common weights
	so players genuinely feel every multiplier & potion!
]]
function RollEngine.RollSingle(ctx: LuckContext, rng: Random?): (GameConfig.AuraDefinition, LuckBreakdown)
	local randomGen = rng or Random.new()
	local breakdown = RollEngine.ComputeLuck(ctx)
	local luck = breakdown.TotalLuck

	-- Iterate from rarest (Celestial) down to Common
	for i = #GameConfig.Auras, 1, -1 do
		local aura = GameConfig.Auras[i]
		if aura.OneIn >= breakdown.GuaranteedMinOneIn then
			-- Effective 1-in-N odds scaled by total luck
			local effectiveOneIn = math.max(1.0, aura.OneIn / luck)
			local roll = randomGen:NextNumber() * effectiveOneIn
			if roll <= 1.0 then
				return aura, breakdown
			end
		end
	end

	-- Fallback to guaranteed pity tier if triggered
	if breakdown.GuaranteedMinOneIn > 0 then
		for _, aura in ipairs(GameConfig.Auras) do
			if aura.OneIn >= breakdown.GuaranteedMinOneIn then
				return aura, breakdown
			end
		end
	end

	return GameConfig.Auras[1], breakdown
end

--[[
	Rolls 1 or 3 Auras (when TripleRoll Gamepass is owned) and returns
	the best Aura rolled along with all rolled Auras for the UI display.
]]
function RollEngine.RollBatch(
	ctx: LuckContext,
	tripleRoll: boolean,
	rng: Random?
): (GameConfig.AuraDefinition, { GameConfig.AuraDefinition }, LuckBreakdown)
	local count = if tripleRoll then 3 else 1
	local allRolled: { GameConfig.AuraDefinition } = {}
	local bestAura: GameConfig.AuraDefinition? = nil
	local firstBreakdown: LuckBreakdown? = nil

	for i = 1, count do
		local subCtx: LuckContext = table.clone(ctx)
		subCtx.TotalRolls = ctx.TotalRolls + (i - 1)
		-- Heavenly Potion applies to the primary roll of the batch
		if i > 1 then
			subCtx.UseHeavenlyPotion = false
		end
		local rolled, breakdown = RollEngine.RollSingle(subCtx, rng)
		if not firstBreakdown then
			firstBreakdown = breakdown
		end
		table.insert(allRolled, rolled)
		if not bestAura or rolled.OneIn > bestAura.OneIn then
			bestAura = rolled
		end
	end

	return bestAura :: GameConfig.AuraDefinition, allRolled, firstBreakdown :: LuckBreakdown
end

return RollEngine
