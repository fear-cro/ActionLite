local ADDON, AL = ...

-- ActionLITE Priest v0.28.4: original Leveling plus optional talent builds.

-- Leveling keeps the finalized pre-simulation implementation in its own
-- scope. Talent builds use the separate implementation below. Both observe
-- real casts so switching rotations retains resource and spell history.
do
    local root = AL
    local leveling, advanced
    local function UsesLeveling(profile)
        profile = profile or (root.Profile and root.Profile("PRIEST")) or (root.S and root.S())
        if advanced and type(profile) == "table" then
            return advanced.NormalizeBuild(profile) == "leveling"
        end
        return true
    end
    local function RotationScope(isLeveling)
        local scope = {
            RegisterRotation = function(token, module)
                assert(token == "PRIEST", "Unexpected class rotation")
                if isLeveling then leveling = module else advanced = module end
            end,
        }
        -- The original combo-point API predates talent-build extensions.
        if isLeveling then scope.ComboPoints = root.ComboPoints end
        return setmetatable(scope, {
            __index = root,
            __newindex = function(self, key, value)
                if key == "rotationSecretVisual" or key == "rogueSecretVisual" then
                    -- An inactive observer must not clear the active display.
                    if root.playerClass == "PRIEST" and UsesLeveling() == isLeveling then root[key] = value end
                elseif isLeveling then
                    -- Keep original module-specific API overrides private.
                    rawset(self, key, value)
                else
                    root[key] = value
                end
            end,
        })
    end

    ;(function(...)
-- BEGIN ORIGINAL LEVELING IMPLEMENTATION (Priest(20261012-035358).lua)
local ADDON, AL = ...

-- WoW Forever Priest leveling 1-30 - v0.26.4
-- Cible : beta 1.60.1.69913.
-- SHADOW favorise Mind Blast / Mind Flay ; SMITE favorise Holy Fire / Smite.
-- Les soins concernent le joueur : aucune cible de groupe n'est devinee.

local A = _G.Action

local M = {
	defaults = {
		priestRole = "SHADOW",
		buffs = true,
		divineSpirit = true,
		innerfire = true,
		shield = true,
		shieldHP = 65,
		fade = true,
		touchOfWeakness = true,
		renew = true,
		heal = true,
		healHP = 35,
		fear = true,
		fearHP = 50,
		silence = true,
		wand = true,
		wandMana = 25,
		wandTargetHP = 20,
		drink = true,
		drinkMana = 35,
		shadowWordPain = true,
		dotMinTargetHP = 35,
		devouringPlague = true,
		plagueMinMana = 40,
		plagueMinTargetHP = 60,
		vampiricEmbrace = true,
		vampiricMinTargetHP = 60,
		mindBlast = true,
		mindBlastMana = 50,
		usePenance = true,
		offensivePenanceMana = 80,
		holyFire = true,
		burstMinTargetHP = 40,
	},
}

-- IDs classiques de rang 1. Les raciaux et talents ne sont utilises que si
-- le grimoire Forever les expose reellement comme appris.
M.spells = {
	{ 20554, "Berserking" },
	{ 528, "Cure Disease" },
	{ 13908, "Desperate Prayer" },
	{ 2944, "Devouring Plague" },
	{ 527, "Dispel Magic" },
	{ 14752, "Divine Spirit" },
	{ 586, "Fade" },
	{ 2054, "Heal" },
	{ 14914, "Holy Fire" },
	{ 588, "Inner Fire" },
	{ 2050, "Lesser Heal" },
	{ 8092, "Mind Blast" },
	{ 15407, "Mind Flay" },
	{ 453, "Mind Soothe" },
	{ 2096, "Mind Vision" },
	{ 402174, "Penance" },
	{ 1243, "Power Word: Fortitude" },
	{ 17, "Power Word: Shield" },
	{ 596, "Prayer of Healing" },
	{ 8122, "Psychic Scream" },
	{ 139, "Renew" },
	{ 2006, "Resurrection" },
	{ 9484, "Shackle Undead" },
	{ 589, "Shadow Word: Pain" },
	{ 15487, "Silence" },
	{ 585, "Smite" },
	{ 5019, "Shoot" },
	{ 2652, "Touch of Weakness" },
	{ 15286, "Vampiric Embrace" },
}

local DIVINE_SPIRIT = "Divine Spirit"
local DIVINE_SPIRIT_ICON = AL.UNIVERSAL_ICONS[9]
local PENANCE = "Penance"
local PENANCE_ICON = AL.UNIVERSAL_ICONS[8]
local PENANCE_PROCS = { [402261] = true, [402277] = true, [402284] = true, [402289] = true,
	[1240723] = true, [1240727] = true, [1240732] = true, [1240734] = true }
local penance = { cooldown = 12, untilTime = 0, castAt = -math.huge, channelUntil = 0, seen = {} }
AL.IconOverrides = AL.IconOverrides or {}
AL.IconOverrides[DIVINE_SPIRIT] = function() return DIVINE_SPIRIT_ICON end
AL.IconOverrides[PENANCE] = function() return PENANCE_ICON end

-- Seed the default once in both new and existing Priest profiles. Keep a
-- user's later icon choice, including choosing the default icon again.
local FillDefaults = AL.FillDefaults
function AL.FillDefaults(profile, token)
	FillDefaults(profile, token)
	if token == "PRIEST" and not profile.divineSpiritIconInitialized then
		profile.icons = profile.icons or {}
		if profile.icons[DIVINE_SPIRIT] == nil then profile.icons[DIVINE_SPIRIT] = DIVINE_SPIRIT_ICON end
		profile.divineSpiritIconInitialized = true
	end
	if token == "PRIEST" and not profile.penanceIconInitialized then
		profile.icons = profile.icons or {}
		if profile.icons[PENANCE] == nil then profile.icons[PENANCE] = PENANCE_ICON end
		profile.penanceIconInitialized = true
	end
end

AL.selfCastSpells = AL.selfCastSpells or {}
for _, name in ipairs({
	"Power Word: Fortitude", "Divine Spirit", "Inner Fire", "Power Word: Shield", "Renew",
	"Heal", "Lesser Heal", "Desperate Prayer", "Berserking", "Fade", "Touch of Weakness",
}) do
	AL.selfCastSpells[name] = true
end

local MINLEVEL = {
	["Lesser Heal"] = 1,
	["Power Word: Fortitude"] = 1,
	["Divine Spirit"] = 30,
	["Penance"] = 30,
	["Smite"] = 1,
	["Shadow Word: Pain"] = 4,
	["Power Word: Shield"] = 6,
	["Fade"] = 8,
	["Touch of Weakness"] = 10,
	["Renew"] = 8,
	["Mind Blast"] = 10,
	["Resurrection"] = 10,
	["Inner Fire"] = 12,
	["Psychic Scream"] = 14,
	["Heal"] = 16,
	["Holy Fire"] = 20,
	["Dispel Magic"] = 18,
	["Shackle Undead"] = 20,
	["Cure Disease"] = 22,
	["Mind Soothe"] = 20,
	["Prayer of Healing"] = 30,
	["Mind Vision"] = 22,
}

local Ok = select(1, AL.LevelGates(MINLEVEL))
M.minLevels = MINLEVEL

-- Weakened Soul fallback is configured for 15 seconds on this Forever client.
-- Prefer the real player debuff when Core can read it; this timer is only the
-- fallback when combat hides the aura.
local shieldLockUntil = 0
local renewLockUntil = 0
local wandEventActive = false
local tracker = CreateFrame("Frame")
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_SPELLCAST_SUCCEEDED", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_SPELLCAST_SUCCEEDED")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_SPELLCAST_SENT", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_SPELLCAST_SENT")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_SPELLCAST_FAILED", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_SPELLCAST_FAILED")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_SPELLCAST_INTERRUPTED", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_SPELLCAST_INTERRUPTED")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_HEALTH", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_HEALTH")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_MAXHEALTH", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_MAXHEALTH")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_POWER_UPDATE", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_POWER_UPDATE")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_POWER_FREQUENT", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_POWER_FREQUENT")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_MAXPOWER", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_MAXPOWER")
end
pcall(tracker.RegisterEvent, tracker, "COMBAT_LOG_EVENT_UNFILTERED")
pcall(tracker.RegisterEvent, tracker, "START_AUTOREPEAT_SPELL")
pcall(tracker.RegisterEvent, tracker, "STOP_AUTOREPEAT_SPELL")
pcall(tracker.RegisterEvent, tracker, "PLAYER_DEAD")
pcall(tracker.RegisterEvent, tracker, "PLAYER_ENTERING_WORLD")
pcall(tracker.RegisterEvent, tracker, "PLAYER_REGEN_DISABLED")
pcall(tracker.RegisterEvent, tracker, "PLAYER_REGEN_ENABLED")

local function SafeValue(value)
	return not (issecretvalue and issecretvalue(value))
end

local TOUCH = "Touch of Weakness"
local TOUCH_CAST_IDS = { [2652] = true, [19261] = true, [19262] = true }
local TOUCH_PROC_IDS = { [2943] = true, [19249] = true, [19251] = true }
local touchBuffUntil, touchAppliedAt = 0, 0
local divineSpiritUntil, divineSpiritAppliedAt = 0, 0
local touchTargets, touchSent, touchLastSuccessGUID = {}, nil, nil

local function TouchSpellID(value, ids)
	if not SafeValue(value) or type(value) ~= "number" then return false end
	if ids[value] then return true end
	if ids == TOUCH_CAST_IDS then
		local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[TOUCH]
		local id = type(ref) == "table" and ref.id
		return SafeValue(id) and type(id) == "number" and id == value
	end
	return false
end

local function TouchGUID(value)
	if SafeValue(value) and type(value) == "string" then return value end
end

local function TouchCastGUID(value)
	local guid = TouchGUID(value)
	return guid and guid:find("^Cast%-") and guid or nil
end

local function DivineSpiritSpellID(value)
	if not SafeValue(value) or type(value) ~= "number" then return false end
	if value == 14752 then return true end
	local spiritRef = AL.rangeSpellRefs and AL.rangeSpellRefs[DIVINE_SPIRIT]
	local spiritID = type(spiritRef) == "table" and spiritRef.id
	return SafeValue(spiritID) and type(spiritID) == "number" and value == spiritID
end

local function PenanceSpellID(value)
	if not SafeValue(value) or type(value) ~= "number" or PENANCE_PROCS[value] then return false end
	if value == 402174 then return true end
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[PENANCE]
	local id = type(ref) == "table" and ref.id
	return SafeValue(id) and type(id) == "number" and value == id
end

local function CastName(arg2, arg3, arg4)
	if TouchSpellID(arg4, TOUCH_CAST_IDS) or TouchSpellID(arg3, TOUCH_CAST_IDS) then return TOUCH end
	if DivineSpiritSpellID(arg4) or DivineSpiritSpellID(arg3) then return DIVINE_SPIRIT end
	if PenanceSpellID(arg4) or PenanceSpellID(arg3) then return PENANCE end
	for _, value in ipairs({ arg4, arg3 }) do
		if type(value) == "number" and SafeValue(value) then
			local ok, name = pcall(AL.SpellName, value)
			if ok and type(name) == "string" and SafeValue(name) then return name end
		end
	end
	if type(arg2) == "string" and SafeValue(arg2) and not arg2:find("^Cast%-") then
		return arg2
	end
end

local function TouchSentSpell(arg2, arg3, arg4)
	local id = SafeValue(arg4) and type(arg4) == "number" and arg4
		or SafeValue(arg3) and type(arg3) == "number" and arg3
	if id then return TouchSpellID(id, TOUCH_CAST_IDS) end
	local name = CastName(arg2, arg3, arg4)
	return name == TOUCH or (not name or not (AL.known and AL.known[name]))
		and AL.lastSuggestion == TOUCH and Ok(TOUCH)
end


-- ============================================================================
-- TRACKED PRIEST MANA
-- ----------------------------------------------------------------------------
-- On this Forever client, current mana is never readable, but maximum mana is.
-- Therefore initialize from the readable maximum and track spending ourselves.
--
-- This tracked value supports Priest mana gates when current mana is protected.
-- ============================================================================
local trackedMana = nil
local trackedManaMax = nil
local trackedManaUpdatedAt = nil
local trackedLastSpendAt = nil
local trackedLastSpell = nil
local trackedLastCost = 0
local trackedSource = "uninitialized"
local cachedBaseManaRegen = 0
local cachedCastingManaRegen = 0

-- Robust event sensors / diagnostics.
local lastSentCastName = nil
local lastSentCastAt = 0
local castSentCount = 0
local castSucceededCount = 0
local castFallbackCount = 0
local lastSucceededCastName = nil

local eventHealthPct = nil
local eventHealthSource = "unreadable"
local eventHealthAt = nil
local healthEventCount = 0

local eventManaPct = nil
local eventManaSource = "unreadable"
local eventManaAt = nil
local manaEventCount = 0

-- When Forever keeps health secret, maintain a best-effort health estimate
-- from readable combat-log damage/heal amounts.
local trackedHealth = nil
local trackedHealthMax = nil
local trackedHealthSource = "uninitialized"
local trackedHealthLastEvent = nil
local trackedHealthLastAmount = nil
local trackedHealthAt = nil
local combatHealthEventCount = 0

local predictionHealthPct = nil
local predictionHealthSource = "unavailable"
local predictionHealthHasSecrets = nil
local predictionHealthAt = nil

local frameHealthPct = nil
local frameHealthSource = "unavailable"
local frameHealthAt = nil
local frameHealthText = nil
local cachedPlayerHealthBar = nil
local healthPredictionCalculator = nil

local function ReadableNumber(value)
	if type(value) ~= "number" then return nil end
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function ReadManaMaximum()
	local maximum

	if type(UnitPowerMax) == "function" then
		local ok, value = pcall(UnitPowerMax, "player")
		value = ok and ReadableNumber(value) or nil
		if value and value > 0 then maximum = value end

		if not maximum then
			ok, value = pcall(UnitPowerMax, "player", 0)
			value = ok and ReadableNumber(value) or nil
			if value and value > 0 then maximum = value end
		end
	end

	if not maximum and type(AL.ManaDebugSources) == "function" then
		local ok, d = pcall(AL.ManaDebugSources)
		if ok and type(d) == "table" then
			maximum = ReadableNumber(d.primaryMax)
				or ReadableNumber(d.typedMax)
				or ReadableNumber(d.cachedMax)
		end
	end

	return maximum
end

local function RefreshManaRegen()
	if type(GetManaRegen) ~= "function" then return end
	local ok, base, casting = pcall(GetManaRegen)
	if not ok then return end

	base = ReadableNumber(base)
	casting = ReadableNumber(casting)

	if base and base >= 0 then cachedBaseManaRegen = base end
	if casting and casting >= 0 then cachedCastingManaRegen = casting end
end

local function EnsureTrackedMana()
	local maximum = ReadManaMaximum()
	if maximum and maximum > 0 then
		if not trackedManaMax or trackedManaMax ~= maximum then
			-- Preserve percentage across a max-mana change when possible.
			if trackedMana and trackedManaMax and trackedManaMax > 0 then
				local pct = trackedMana / trackedManaMax
				trackedMana = math.max(0, math.min(maximum, maximum * pct))
			end
			trackedManaMax = maximum
		end
	end

	if not trackedManaMax or trackedManaMax <= 0 then return false end

	if trackedMana == nil then
		-- Critical difference from the failed estimator: current mana does NOT
		-- need to be readable. Start from the readable maximum.
		trackedMana = trackedManaMax
		trackedManaUpdatedAt = GetTime()
		trackedSource = "max-initialized"
	end

	RefreshManaRegen()
	return true
end

local function UpdateTrackedManaRegen()
	if not EnsureTrackedMana() then return end

	local now = GetTime()
	if not trackedManaUpdatedAt then
		trackedManaUpdatedAt = now
		return
	end

	local dt = now - trackedManaUpdatedAt
	if dt <= 0 then return end
	trackedManaUpdatedAt = now

	-- Use the client-provided regen rates when readable. During the 5-second
	-- rule, use the casting rate; afterward use the normal base rate.
	local rate
	if trackedLastSpendAt and (now - trackedLastSpendAt) < 5 then
		rate = cachedCastingManaRegen
	else
		rate = cachedBaseManaRegen
	end

	rate = tonumber(rate) or 0
	if rate > 0 then
		trackedMana = math.min(trackedManaMax, trackedMana + rate * dt)
	end
end

local function SpellManaCost(spellName)
	if type(spellName) ~= "string" or spellName == "" then return 0 end

	local identifiers = {}
	local seen = {}

	local function AddIdentifier(value)
		if value == nil or seen[value] then return end
		seen[value] = true
		identifiers[#identifiers + 1] = value
	end

	-- Prefer the exact learned spell/rank ID discovered by Core.
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[spellName]
	if type(ref) == "table" then AddIdentifier(ref.id) end

	-- Then the classic spell ID registered by the Priest module.
	for _, def in ipairs(M.spells or {}) do
		if def[2] == spellName then
			AddIdentifier(def[1])
			break
		end
	end

	-- Last fallback: name.
	AddIdentifier(spellName)

	for _, identifier in ipairs(identifiers) do
		local costs

		if C_Spell and type(C_Spell.GetSpellPowerCost) == "function" then
			local ok, result = pcall(C_Spell.GetSpellPowerCost, identifier)
			if ok and type(result) == "table" then costs = result end
		elseif type(GetSpellPowerCost) == "function" then
			local ok, result = pcall(GetSpellPowerCost, identifier)
			if ok and type(result) == "table" then costs = result end
		end

		if costs then
			for _, info in ipairs(costs) do
				if type(info) == "table" then
					local powerType = ReadableNumber(info.type)
					local token = SafeValue(info.name) and info.name or nil

					if powerType == 0 or token == "MANA" then
						local cost =
							ReadableNumber(info.cost)
							or ReadableNumber(info.minCost)

						if cost and cost > 0 then return cost end

						local pct = ReadableNumber(info.costPercent)
						if pct and pct > 0 and trackedManaMax and trackedManaMax > 0 then
							return trackedManaMax * pct / 100
						end
					end
				end
			end
		end
	end

	return 0
end

local function SpendTrackedMana(spellName)
	if not EnsureTrackedMana() then return end
	UpdateTrackedManaRegen()

	local cost = SpellManaCost(spellName)
	trackedLastSpell = spellName
	trackedLastCost = cost or 0

	if cost and cost > 0 then
		trackedMana = math.max(0, trackedMana - cost)
		trackedLastSpendAt = GetTime()
		trackedManaUpdatedAt = trackedLastSpendAt
		trackedSource = "tracked spell costs"
	end
end

local function TrackedManaPercent()
	if not EnsureTrackedMana() then return nil end
	UpdateTrackedManaRegen()

	if trackedMana == nil or not trackedManaMax or trackedManaMax <= 0 then
		return nil
	end

	return math.max(0, math.min(100, trackedMana / trackedManaMax * 100))
end




local function PredictionHealthPercent()
	if type(CreateUnitHealPredictionCalculator) ~= "function"
		or type(UnitGetDetailedHealPrediction) ~= "function"
	then
		predictionHealthSource = "API unavailable"
		return nil
	end

	if not healthPredictionCalculator then
		local ok, calc = pcall(CreateUnitHealPredictionCalculator)
		if not ok or not calc then
			predictionHealthSource = "calculator create failed"
			return nil
		end
		healthPredictionCalculator = calc
	end

	local calc = healthPredictionCalculator

	if type(calc.SetToDefaults) == "function" then
		pcall(calc.SetToDefaults, calc)
	end

	local okFill = pcall(UnitGetDetailedHealPrediction, "player", "player", calc)
	if not okFill then
		predictionHealthSource = "UnitGetDetailedHealPrediction failed"
		return nil
	end

	if type(calc.HasSecretValues) == "function" then
		local ok, secret = pcall(calc.HasSecretValues, calc)
		if ok and type(secret) == "boolean" then
			predictionHealthHasSecrets = secret
		end
	end

	-- Preferred path: the calculator evaluates the current health percentage
	-- against Blizzard's ScaleTo100 curve.
	if type(calc.EvaluateCurrentHealthPercent) == "function"
		and CurveConstants
		and CurveConstants.ScaleTo100
	then
		local ok, value = pcall(
			calc.EvaluateCurrentHealthPercent,
			calc,
			CurveConstants.ScaleTo100
		)
		value = ok and ReadableNumber(value) or nil
		if value ~= nil then
			value = math.max(0, math.min(100, value))
			predictionHealthPct = value
			predictionHealthSource = "HealPrediction EvaluateCurrentHealthPercent"
			predictionHealthAt = GetTime()
			return value
		end
	end

	-- Secondary calculator percentage path.
	if type(calc.GetCurrentHealthPercent) == "function" then
		local ok, value = pcall(calc.GetCurrentHealthPercent, calc)
		value = ok and ReadableNumber(value) or nil
		if value ~= nil then
			if value >= 0 and value <= 1 then value = value * 100 end
			if value >= 0 and value <= 100 then
				predictionHealthPct = value
				predictionHealthSource = "HealPrediction GetCurrentHealthPercent"
				predictionHealthAt = GetTime()
				return value
			end
		end
	end

	-- Last calculator fallback: current/max.
	if type(calc.GetCurrentHealth) == "function"
		and type(calc.GetMaximumHealth) == "function"
	then
		local okC, current = pcall(calc.GetCurrentHealth, calc)
		local okM, maximum = pcall(calc.GetMaximumHealth, calc)
		current = okC and ReadableNumber(current) or nil
		maximum = okM and ReadableNumber(maximum) or nil

		if current ~= nil and maximum ~= nil and maximum > 0 then
			local value = math.max(0, math.min(100, current / maximum * 100))
			predictionHealthPct = value
			predictionHealthSource = "HealPrediction current/max"
			predictionHealthAt = GetTime()
			return value
		end
	end

	predictionHealthSource = predictionHealthHasSecrets
		and "HealPrediction values still secret"
		or "HealPrediction unreadable"
	return nil
end

local function HealthPercentFromStatusBar(bar, expectedMaximum)
	if not bar
		or type(bar.GetValue) ~= "function"
		or type(bar.GetMinMaxValues) ~= "function"
	then
		return nil
	end

	local okV, value = pcall(bar.GetValue, bar)
	local okR, minimum, maximum = pcall(bar.GetMinMaxValues, bar)
	if not okV or not okR then return nil end

	value = ReadableNumber(value)
	minimum = ReadableNumber(minimum)
	maximum = ReadableNumber(maximum)

	if value == nil or minimum == nil or maximum == nil or maximum <= minimum then
		return nil
	end

	-- If max health is known, reject other PlayerFrame bars such as mana.
	if type(expectedMaximum) == "number" and expectedMaximum > 0 then
		local barRange = maximum - minimum
		if math.abs(barRange - expectedMaximum) > math.max(1, expectedMaximum * 0.05) then
			return nil
		end
	end

	if value < minimum or value > maximum then return nil end
	return (value - minimum) / (maximum - minimum) * 100
end

local function AlivePlayer()
	if type(UnitIsDeadOrGhost) == "function" then
		local ok, dead = pcall(UnitIsDeadOrGhost, "player")
		if ok and not (issecretvalue and issecretvalue(dead)) then
			return not dead
		end
	end
	return true
end

local function ParseReadableHealthText(text, expectedMaximum)
	if type(text) ~= "string"
		or (issecretvalue and issecretvalue(text))
		or text == ""
	then
		return nil
	end

	-- Strip color/formatting noise and thousands separators.
	local clean = text:gsub("|c%x%x%x%x%x%x%x%x", "")
		:gsub("|r", "")
		:gsub(",", "")
		:gsub("%s+", " ")

	local current, maximum = clean:match("(%d+)%s*/%s*(%d+)")
	current = tonumber(current)
	maximum = tonumber(maximum)

	if current and maximum and maximum > 0 then
		if expectedMaximum and expectedMaximum > 0
			and math.abs(maximum - expectedMaximum) > math.max(1, expectedMaximum * 0.05)
		then
			return nil
		end

		local pct = current / maximum * 100
		if pct <= 0 and AlivePlayer() then return nil end
		if pct >= 0 and pct <= 100 then
			return pct, clean
		end
	end

	local pct = tonumber(clean:match("(%d+%.?%d*)%%"))
	if pct and pct >= 0 and pct <= 100 then
		if pct <= 0 and AlivePlayer() then return nil end
		return pct, clean
	end

	return nil
end

local function FindReadablePlayerHealthText()
	local frame = _G.PlayerFrame
	if not frame then
		frameHealthSource = "PlayerFrame unavailable"
		return nil
	end

	local hpMax
	if type(UnitHealthMax) == "function" then
		local ok, value = pcall(UnitHealthMax, "player")
		hpMax = ok and ReadableNumber(value) or nil
	end

	local visited = {}
	local scanned = 0

	local function Walk(region, depth)
		if not region or visited[region] or depth > 8 or scanned > 400 then
			return nil
		end
		visited[region] = true
		scanned = scanned + 1

		if type(region.GetText) == "function" then
			local ok, text = pcall(region.GetText, region)
			if ok and type(text) == "string"
				and not (issecretvalue and issecretvalue(text))
			then
				local pct, parsed = ParseReadableHealthText(text, hpMax)
				if pct ~= nil then
					return pct, parsed
				end
			end
		end

		if type(region.GetRegions) == "function" then
			local ok, regions = pcall(function() return { region:GetRegions() } end)
			if ok then
				for _, child in ipairs(regions) do
					local pct, parsed = Walk(child, depth + 1)
					if pct ~= nil then return pct, parsed end
				end
			end
		end

		if type(region.GetChildren) == "function" then
			local ok, children = pcall(function() return { region:GetChildren() } end)
			if ok then
				for _, child in ipairs(children) do
					local pct, parsed = Walk(child, depth + 1)
					if pct ~= nil then return pct, parsed end
				end
			end
		end
	end

	local pct, parsed = Walk(frame, 0)
	if pct ~= nil then
		frameHealthPct = pct
		frameHealthText = parsed
		frameHealthSource = "PlayerFrame visible health text"
		frameHealthAt = GetTime()
		return pct
	end

	frameHealthPct = nil
	frameHealthText = nil
	frameHealthSource = "no readable PlayerFrame health text"
	return nil
end

local function FindReadablePlayerHealthBar()
	-- Only trust explicit Blizzard health-bar paths. Do NOT recursively scan
	-- arbitrary StatusBars: v0.25.6 matched a non-health bar at 0% and caused
	-- an endless healing loop.
	local hpMax
	if type(UnitHealthMax) == "function" then
		local ok, value = pcall(UnitHealthMax, "player")
		hpMax = ok and ReadableNumber(value) or nil
	end

	local frame = _G.PlayerFrame
	local content = frame and frame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local area = main and main.HealthBarArea

	local candidates = {
		_G.PlayerFrameHealthBar,
		area and area.HealthBar,
		frame and frame.healthbar,
		frame and frame.healthBar,
		frame and frame.HealthBar,
	}

	for _, bar in ipairs(candidates) do
		local pct = HealthPercentFromStatusBar(bar, hpMax)
		if pct ~= nil then
			-- A living character cannot have real 0% health. Reject poisoned
			--/placeholder status bars instead of caching them.
			if pct > 0 or not AlivePlayer() then
				frameHealthPct = pct
				frameHealthText = nil
				frameHealthSource = "known PlayerFrame health bar"
				frameHealthAt = GetTime()
				return pct
			end
		end
	end

	-- Safer fallback: visible text, not arbitrary StatusBars.
	return FindReadablePlayerHealthText()
end

local function ReadCurrentHealthPercent()
	-- 1) New Forever-safe heal prediction calculator.
	local pct = PredictionHealthPercent()
	if pct ~= nil then
		return pct, predictionHealthSource
	end

	-- 2) Visible PlayerFrame health bar. This is presentation state, not a raw
	-- UnitHealth arithmetic dependency.
	pct = FindReadablePlayerHealthBar()
	if pct ~= nil then
		return pct, frameHealthSource
	end

	-- 3) Raw percent APIs if they happen to be readable.
	if type(UnitHealthPercent) == "function" then
		if CurveConstants and CurveConstants.ScaleTo100 then
			for _, predicted in ipairs({ false, true }) do
				local ok, value = pcall(
					UnitHealthPercent,
					"player",
					predicted,
					CurveConstants.ScaleTo100
				)
				value = ok and ReadableNumber(value) or nil
				if value ~= nil then
					return math.max(0, math.min(100, value)),
						"UnitHealthPercent predicted=" .. tostring(predicted)
				end
			end
		end

		local ok, value = pcall(UnitHealthPercent, "player")
		value = ok and ReadableNumber(value) or nil
		if value ~= nil then
			if value >= 0 and value <= 1 then value = value * 100 end
			return math.max(0, math.min(100, value)), "UnitHealthPercent simple"
		end
	end

	-- 4) Raw current/max.
	if type(UnitHealth) == "function" and type(UnitHealthMax) == "function" then
		for _, predicted in ipairs({ false, true }) do
			local okH, hp = pcall(UnitHealth, "player", predicted)
			local okM, hpMax = pcall(UnitHealthMax, "player")
			hp = okH and ReadableNumber(hp) or nil
			hpMax = okM and ReadableNumber(hpMax) or nil

			if hp ~= nil and hpMax ~= nil and hpMax > 0 then
				return math.max(0, math.min(100, hp / hpMax * 100)),
					"UnitHealth/Max predicted=" .. tostring(predicted)
			end
		end
	end
end

local function ReadCurrentManaPercent()
	local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

	if type(UnitPowerPercent) == "function" and CurveConstants and CurveConstants.ScaleTo100 then
		local ok, pct = pcall(
			UnitPowerPercent,
			"player",
			powerType,
			false,
			CurveConstants.ScaleTo100
		)
		pct = ok and ReadableNumber(pct) or nil
		if pct ~= nil then
			return math.max(0, math.min(100, pct)), "UNIT_POWER UnitPowerPercent"
		end
	end

	if type(UnitPower) == "function" and type(UnitPowerMax) == "function" then
		local okC, current = pcall(UnitPower, "player", powerType)
		local okM, maximum = pcall(UnitPowerMax, "player", powerType)
		current = okC and ReadableNumber(current) or nil
		maximum = okM and ReadableNumber(maximum) or nil

		if current ~= nil and maximum ~= nil and maximum > 0 then
			return math.max(0, math.min(100, current / maximum * 100)),
				"UNIT_POWER UnitPower/Max"
		end
	end
end

local function RefreshHealthSensor()
	healthEventCount = healthEventCount + 1

	local pct, source = ReadCurrentHealthPercent()
	if pct ~= nil and (pct > 0 or not AlivePlayer()) then
		eventHealthPct = pct
		eventHealthSource = source or "event health"
		eventHealthAt = GetTime()

		local maximum = ReadableNumber(UnitHealthMax and UnitHealthMax("player"))
		if maximum and maximum > 0 then
			trackedHealthMax = maximum
			trackedHealth = maximum * pct / 100
			trackedHealthSource = "event health resync"
			trackedHealthAt = GetTime()
		end
	end
end

local function RefreshManaSensor()
	manaEventCount = manaEventCount + 1

	local pct, source = ReadCurrentManaPercent()
	if pct ~= nil then
		eventManaPct = pct
		eventManaSource = source or "event mana"
		eventManaAt = GetTime()

		if EnsureTrackedMana() and trackedManaMax then
			trackedMana = trackedManaMax * pct / 100
			trackedManaUpdatedAt = GetTime()
			trackedSource = "event mana resync"
		end
	end
end

local function EnsureTrackedHealth()
	local maximum
	if type(UnitHealthMax) == "function" then
		local ok, value = pcall(UnitHealthMax, "player")
		maximum = ok and ReadableNumber(value) or nil
	end

	if maximum and maximum > 0 then
		if not trackedHealthMax or trackedHealthMax ~= maximum then
			if trackedHealth and trackedHealthMax and trackedHealthMax > 0 then
				local pct = trackedHealth / trackedHealthMax
				trackedHealth = maximum * pct
			end
			trackedHealthMax = maximum
		end
	end

	if not trackedHealthMax or trackedHealthMax <= 0 then return false end

	if trackedHealth == nil then
		trackedHealth = trackedHealthMax
		trackedHealthSource = "max-initialized"
		trackedHealthAt = GetTime()
	end

	return true
end

local function ApplyTrackedHealthDelta(delta, eventName, amount)
	if not EnsureTrackedHealth() then return end
	if type(delta) ~= "number" then return end

	trackedHealth = math.max(
		0,
		math.min(trackedHealthMax, trackedHealth + delta)
	)
	trackedHealthSource = "combat-log tracked"
	trackedHealthLastEvent = eventName
	trackedHealthLastAmount = amount
	trackedHealthAt = GetTime()
	combatHealthEventCount = combatHealthEventCount + 1
end

local function TrackCombatLogHealth()
	if type(CombatLogGetCurrentEventInfo) ~= "function" then return end

	local ok, timestamp, subevent, hideCaster,
		sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
		destGUID, destName, destFlags, destRaidFlags,
		a12, a13, a14, a15, a16 = pcall(CombatLogGetCurrentEventInfo)

	if not ok or not SafeValue(subevent) then return end

	-- Prefer combat-log affiliation flags. GUIDs can themselves be secret on
	-- Forever, which previously caused every player damage/heal event to be
	-- discarded before we ever looked at the amount.
	local isPlayerDest = false
	if type(destFlags) == "number"
		and not (issecretvalue and issecretvalue(destFlags))
		and bit and bit.band
		and COMBATLOG_OBJECT_AFFILIATION_MINE
	then
		isPlayerDest = bit.band(destFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0
	end

	if not isPlayerDest and SafeValue(destGUID) then
		local okGuid, playerGUID = pcall(UnitGUID, "player")
		if okGuid and SafeValue(playerGUID) and playerGUID == destGUID then
			isPlayerDest = true
		end
	end

	if not isPlayerDest then return end

	local amount
	local delta

	if subevent == "SWING_DAMAGE" then
		amount = ReadableNumber(a12)
		if amount then delta = -amount end

	elseif subevent == "ENVIRONMENTAL_DAMAGE" then
		amount = ReadableNumber(a13)
		if amount then delta = -amount end

	elseif subevent == "SPELL_DAMAGE"
		or subevent == "SPELL_PERIODIC_DAMAGE"
		or subevent == "RANGE_DAMAGE"
		or subevent == "DAMAGE_SHIELD"
		or subevent == "DAMAGE_SPLIT"
	then
		amount = ReadableNumber(a15)
		if amount then delta = -amount end

	elseif subevent == "SPELL_HEAL"
		or subevent == "SPELL_PERIODIC_HEAL"
	then
		amount = ReadableNumber(a15)
		local overheal = ReadableNumber(a16) or 0
		if amount then
			delta = math.max(0, amount - overheal)
		end

	elseif subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
		if EnsureTrackedHealth() then
			trackedHealth = 0
			trackedHealthSource = "combat-log death"
			trackedHealthLastEvent = subevent
			trackedHealthLastAmount = 0
			trackedHealthAt = GetTime()
			combatHealthEventCount = combatHealthEventCount + 1
		end
		return
	end

	if delta then
		ApplyTrackedHealthDelta(delta, subevent, amount)
	end
end

local function TrackedHealthPercent()
	if not EnsureTrackedHealth() then return nil end
	if trackedHealthSource == "max-initialized" then
		return nil
	end
	if not trackedHealth or not trackedHealthMax or trackedHealthMax <= 0 then return nil end

	local pct = math.max(0, math.min(100, trackedHealth / trackedHealthMax * 100))
	if pct <= 0 and AlivePlayer()
		and trackedHealthSource == "event health resync"
	then
		return nil
	end
	return pct
end

tracker:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
	if event == "START_AUTOREPEAT_SPELL" then
		wandEventActive = true
		return
	end

	if event == "STOP_AUTOREPEAT_SPELL" then
		wandEventActive = false
		return
	end

	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		TrackCombatLogHealth()
		return
	end

	if event == "PLAYER_REGEN_DISABLED" then
		EnsureTrackedMana()
		EnsureTrackedHealth()
		trackedManaUpdatedAt = GetTime()
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		UpdateTrackedManaRegen()
		RefreshHealthSensor()
		RefreshManaSensor()
		return
	end

	if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
		shieldLockUntil = 0
		renewLockUntil = 0
		divineSpiritUntil, divineSpiritAppliedAt = 0, 0
		wandEventActive = false

		trackedMana = nil
		trackedManaMax = nil
		trackedManaUpdatedAt = nil
		trackedLastSpendAt = nil
		trackedLastSpell = nil
		trackedLastCost = 0
		trackedSource = "uninitialized"

		eventHealthPct = nil
		eventHealthSource = "unreadable"
		eventHealthAt = nil
		eventManaPct = nil
		eventManaSource = "unreadable"
		eventManaAt = nil

		trackedHealth = nil
		trackedHealthMax = nil
		trackedHealthSource = "uninitialized"
		trackedHealthLastEvent = nil
		trackedHealthLastAmount = nil
		trackedHealthAt = nil

		lastSentCastName = nil
		lastSentCastAt = 0

		EnsureTrackedMana()
		EnsureTrackedHealth()
		RefreshHealthSensor()
		RefreshManaSensor()
		return
	end

	if unit ~= "player" then return end

	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		RefreshHealthSensor()
		return
	end

	if event == "UNIT_POWER_UPDATE"
		or event == "UNIT_POWER_FREQUENT"
		or event == "UNIT_MAXPOWER"
	then
		-- Ignore non-mana power updates when the token is readable.
		if type(arg2) == "string"
			and SafeValue(arg2)
			and arg2 ~= "MANA"
		then
			return
		end

		RefreshManaSensor()
		return
	end

	if event == "UNIT_SPELLCAST_SENT" then
		local spellName = CastName(arg2, arg3, arg4)
		if TouchSentSpell(arg2, arg3, arg4) then spellName = TOUCH end
		if not (SafeValue(arg4) and type(arg4) == "number")
			and not (SafeValue(arg3) and type(arg3) == "number")
			and (not spellName or not (AL.known and AL.known[spellName]))
			and AL.lastSuggestion == DIVINE_SPIRIT and Ok(DIVINE_SPIRIT) then spellName = DIVINE_SPIRIT end
		if spellName then
			lastSentCastName = spellName
			lastSentCastAt = GetTime()
			castSentCount = castSentCount + 1
		end
		return
	end

	if event == "UNIT_SPELLCAST_FAILED"
		or event == "UNIT_SPELLCAST_INTERRUPTED"
	then
		lastSentCastName = nil
		lastSentCastAt = 0
		return
	end

	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
	-- The automatic damage/debuff proc is not another paid self-buff cast.
	if TouchSpellID(arg3, TOUCH_PROC_IDS) or TouchSpellID(arg4, TOUCH_PROC_IDS) then return end

	castSucceededCount = castSucceededCount + 1

	local spellName = CastName(arg2, arg3, arg4)

	-- Forever can secretize the SUCCEEDED spell payload. Core already solves
	-- this by remembering UNIT_SPELLCAST_SENT; Priest now does the same.
	if not spellName
		and lastSentCastName
		and (GetTime() - lastSentCastAt) < 5
	then
		spellName = lastSentCastName
		castFallbackCount = castFallbackCount + 1
	end

	lastSentCastName = nil
	lastSentCastAt = 0
	lastSucceededCastName = spellName

	if not spellName then return end
	-- Penance's confirmed channel/cast is charged once by its own observer.
	if spellName == PENANCE then return end

	SpendTrackedMana(spellName)

	if spellName == "Power Word: Shield" then
		shieldLockUntil = GetTime() + 15
	elseif spellName == "Renew" then
		renewLockUntil = GetTime() + 15
	elseif spellName == DIVINE_SPIRIT then
		divineSpiritUntil, divineSpiritAppliedAt = GetTime() + 3600, GetTime()
	end
end)

local function SettingNumber(s, key, defaultValue, minValue, maxValue)
	local value = tonumber(s and s[key])
	if value == nil then value = defaultValue end
	value = math.floor(value + 0.5)
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

-- Combat-safe player health percentage. Forever can secretize raw
-- UnitHealth/UnitHealthMax in combat while still exposing UnitHealthPercent.
-- Exact combat-safe health reader used by the working Rogue rotation.
local function PlayerHealthPercent()
	-- 1) Best source: a readable health sample captured on UNIT_HEALTH.
	if type(eventHealthPct) == "number" then
		if eventHealthPct > 0 or not AlivePlayer() then
			return eventHealthPct
		end
		-- Poisoned zero from an older frame scan: discard it.
		eventHealthPct = nil
		eventHealthSource = "discarded impossible 0%"
		eventHealthAt = nil
	end

	-- 2) Try a direct read now.
	local pct, source = ReadCurrentHealthPercent()
	if type(pct) == "number" and (pct > 0 or not AlivePlayer()) then
		eventHealthPct = pct
		eventHealthSource = source or "direct health"
		eventHealthAt = GetTime()
		return pct
	end

	-- 3) When current health is protected, use our combat-log estimate.
	pct = TrackedHealthPercent()
	if type(pct) == "number" then
		return pct
	end

	-- 4) Existing Core fallback.
	if type(AL.HealthPercent) == "function" then
		local ok, value = pcall(AL.HealthPercent, "player")
		value = ok and ReadableNumber(value) or nil
		if value ~= nil then return value end
	end

	return nil
end

-- Safe visible-mana status-bar reader used by GateManaPercent().
local function ManaFromStatusBar(bar)
	if not bar
		or type(bar.GetValue) ~= "function"
		or type(bar.GetMinMaxValues) ~= "function"
	then
		return nil
	end

	local okValue, value = pcall(bar.GetValue, bar)
	local okRange, minimum, maximum = pcall(bar.GetMinMaxValues, bar)
	if not okValue or not okRange then return nil end

	value = ReadableNumber(value)
	minimum = ReadableNumber(minimum)
	maximum = ReadableNumber(maximum)

	if value == nil or minimum == nil or maximum == nil or maximum <= minimum then
		return nil
	end

	if value < minimum or value > maximum then return nil end
	return (value - minimum) / (maximum - minimum) * 100
end

-- Count hostile nameplates that currently have the player on their threat table.
-- This is the same combat-safe signal used by the Rogue emergency logic.
local NAMEPLATE_UNITS = {}
for i = 1, 40 do
	NAMEPLATE_UNITS[i] = "nameplate" .. i
end

local engagedEnemyCount = 0
local engagedEnemyCountAt = -1

local function EngagedEnemies()
	local now = GetTime()
	if now - engagedEnemyCountAt < 0.20 then
		return engagedEnemyCount
	end

	local count = 0

	if UnitThreatSituation then
		for i = 1, #NAMEPLATE_UNITS do
			local unit = NAMEPLATE_UNITS[i]

			local okExists, exists = pcall(UnitExists, unit)
			if okExists and SafeValue(exists) and exists then
				local okAttack, canAttack = pcall(UnitCanAttack, "player", unit)
				if okAttack and SafeValue(canAttack) and canAttack then
					local okThreat, threat = pcall(UnitThreatSituation, "player", unit)

					-- nil means the player is not on this enemy's threat table.
					-- 0-3 are valid threat states.
					if okThreat and SafeValue(threat) and threat ~= nil then
						count = count + 1
						-- Fade only cares whether there is more than one.
						if count >= 2 then break end
					end
				end
			end
		end
	end

	engagedEnemyCount = count
	engagedEnemyCountAt = now
	return count
end

local function Role(s)
	return s and s.priestRole == "SMITE" and "SMITE" or "SHADOW"
end

local function ManaAtLeast(mana, threshold)
	return mana == nil or (type(mana) == "number" and mana >= threshold)
end

local function TargetWorthAtLeast(targetHP, threshold)
	return targetHP == nil or (type(targetHP) == "number" and targetHP >= threshold)
end

local function ReadyUsable(name)
	return Ok(name) and AL.IsReady(name) and AL.SpellUsable(name)
end

local HEALING_SPELL_IDS = {
	["Renew"] = 139,
	["Heal"] = 2054,
	["Lesser Heal"] = 2050,
	["Desperate Prayer"] = 13908,
}

local function HealingKnown(name)
	-- First trust ActionLITE's spellbook scan.
	if AL.known and AL.known[name] then
		return true
	end

	-- Secondary direct spell-known check when the client provides one.
	local spellID = HEALING_SPELL_IDS[name]
	if spellID and type(IsSpellKnown) == "function" then
		local ok, known = pcall(IsSpellKnown, spellID)
		if ok and SafeValue(known) and known then
			return true
		end
	end

	-- Final fallback to the normal Priest gate.
	return Ok(name) and true or false
end

local function PlayerMoving()
	if type(GetUnitSpeed) ~= "function" then return false end
	local ok, speed = pcall(GetUnitSpeed, "player")
	if not ok or not SafeValue(speed) or type(speed) ~= "number" then return false end
	return speed > 0
end


-- Priest low-mana wand mode.
--
-- This now mirrors the WORKING Warlock implementation structurally:
--   * read AL.ManaPercent() directly
--   * remember the last REAL numeric sample
--   * latch the low-mana Shoot state from that sample
--   * when the current read becomes nil/secret, keep evaluating the slider
--     against the last readable sample instead of inventing a new percentage
local shootModeActive = false
local lastReadableManaPct = nil
local lastManaSource = "unreadable"

local function CoreManaPercent()
	if type(AL.ManaPercent) ~= "function" then
		lastManaSource = lastReadableManaPct ~= nil and "cached" or "unreadable"
		return nil
	end

	local ok, value = pcall(AL.ManaPercent)
	if not ok
		or type(value) ~= "number"
		or (issecretvalue and issecretvalue(value))
	then
		lastManaSource = lastReadableManaPct ~= nil and "cached" or "unreadable"
		return nil
	end

	lastReadableManaPct = value
	lastManaSource = "Core"
	return value
end

local function LowManaShootMode(s, manaPct)
	local threshold = SettingNumber(s, "wandMana", 25, 0, 100)

	if type(manaPct) == "number" then
		lastReadableManaPct = manaPct
		shootModeActive = manaPct <= threshold
		lastManaSource = "Core"
	elseif type(lastReadableManaPct) == "number" then
		-- Exact Warlock behavior: if the live read disappears, re-evaluate the
		-- last real sample against the CURRENT slider value.
		shootModeActive = lastReadableManaPct <= threshold
		lastManaSource = "cached"
	else
		shootModeActive = false
		lastManaSource = "unreadable"
	end

	return shootModeActive, lastReadableManaPct, threshold
end

local function GroupSize()
	-- Raids are not part of the leveling proximity-shield rule.
	if type(IsInRaid) == "function" then
		local ok, inRaid = pcall(IsInRaid)
		if ok and SafeValue(inRaid) and inRaid then
			if type(GetNumGroupMembers) == "function" then
				local okCount, count = pcall(GetNumGroupMembers)
				if okCount and SafeValue(count) and type(count) == "number" then
					return count
				end
			end
			return 5
		end
	end

	if type(GetNumGroupMembers) == "function" then
		local ok, count = pcall(GetNumGroupMembers)
		if ok and SafeValue(count) and type(count) == "number" then
			if count <= 0 then return 1 end
			return count
		end
	end

	if type(GetNumPartyMembers) == "function" then
		local ok, count = pcall(GetNumPartyMembers)
		if ok and SafeValue(count) and type(count) == "number" then
			return count + 1
		end
	end

	return 1
end

local function LevelingShieldGroupAllowed()
	return GroupSize() < 5
end

local function TargetWithin10Yards()
	if not UnitExists("target") then return false end

	if type(UnitDistanceSquared) == "function" then
		local ok, distanceSquared = pcall(UnitDistanceSquared, "target")
		if ok and SafeValue(distanceSquared) and type(distanceSquared) == "number" then
			return distanceSquared <= 100
		end
	end

	if type(UnitPosition) == "function" then
		local okPlayer, px, py, pz, pInstance = pcall(UnitPosition, "player")
		local okTarget, tx, ty, tz, tInstance = pcall(UnitPosition, "target")
		if okPlayer and okTarget
			and type(px) == "number" and type(py) == "number"
			and type(tx) == "number" and type(ty) == "number"
			and SafeValue(px) and SafeValue(py) and SafeValue(tx) and SafeValue(ty)
			and (not pInstance or not tInstance or pInstance == tInstance)
		then
			local dx, dy = tx - px, ty - py
			return (dx * dx + dy * dy) <= 100
		end
	end

	-- Classic interaction index 3 is approximately 10 yards. Only a readable
	-- true result is used; false/unknown does not guess that the target is close.
	if type(CheckInteractDistance) == "function" then
		local ok, close = pcall(CheckInteractDistance, "target", 3)
		if ok and SafeValue(close) and close then return true end
	end

	-- Conservative last fallback: melee range is definitely inside 10 yards.
	if type(AL.TargetInMelee) == "function" then
		local ok, melee = pcall(AL.TargetInMelee)
		if ok and melee then return true end
	end

	return false
end

local function PlayerIsWanding()
	local player = A and type(A.Player) == "table" and A.Player or nil
	if player and type(player.IsShooting) == "function" then
		local ok, active = pcall(player.IsShooting, player)
		if ok and SafeValue(active) and type(active) == "boolean" then return active end
	end
	if type(IsCurrentSpell) == "function" then
		local ok, active = pcall(IsCurrentSpell, 5019)
		if ok and SafeValue(active) and active then return true end
	end
	return wandEventActive
end

local function WandEquipped()
	local ok, equipped = pcall(AL.WandEquipped)
	return ok and equipped and true or false
end

local function Wand(s, reason)
	-- Priest wand use is automatic whenever a wand is physically equipped.
	-- There is no separate enable/disable flag that can silently bypass the
	-- mana slider.
	if not WandEquipped() then return nil end
	return "Shoot", reason or "save mana"
end

local function LivePriestProfile(s)
	if type(AL.Profile) == "function" then
		local ok, profile = pcall(AL.Profile, "PRIEST")
		if ok and type(profile) == "table" then
			return profile
		end
	end
	return s
end

local function WandManaThreshold(s)
	-- `s` is the live rotation profile passed directly into NextSpell().
	-- Your runtime dump confirmed this table contains the actual slider value.
	return SettingNumber(s, "wandMana", 25, 0, 100)
end

local function MindBlastManaThreshold(s)
	-- Same rule as Smite: read the live table directly, never a second profile lookup.
	return SettingNumber(s, "mindBlastMana", 50, 0, 100)
end

local function GateManaPercent()
	-- ONE conservative mana value per rotation pass.
	--
	-- Important: do NOT let a stale/high source re-enable Smite or Mind Blast.
	-- We collect every readable current/tracked source and use the LOWEST value.
	-- This means a real low mana source always wins over a stale high one.
	local best = nil
	local bestSource = nil

	local function consider(value, source)
		value = ReadableNumber(value)
		if value == nil or value < 0 or value > 100 then return end
		if best == nil or value < best then
			best = value
			bestSource = source
		end
	end

	-- A) Event-cached current mana, when Forever exposes it on UNIT_POWER.
	consider(eventManaPct, eventManaSource or "event mana")

	-- B) Proven tracked-mana model.
	consider(TrackedManaPercent(), "tracked")

	-- B) Visible player mana bar.
	consider(ManaFromStatusBar(_G.PlayerFrameManaBar), "player bar")

	local frame = _G.PlayerFrame
	local content = frame and frame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local area = main and main.ManaBarArea
	local nestedBar = area and area.ManaBar
	consider(ManaFromStatusBar(nestedBar), "player bar")

	-- C) Forever's normalized power API. This source is never allowed to
	-- override a lower tracked/UI value.
	if type(UnitPowerPercent) == "function"
		and CurveConstants
		and CurveConstants.ScaleTo100
	then
		local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
		local ok, value = pcall(
			UnitPowerPercent,
			"player",
			powerType,
			false,
			CurveConstants.ScaleTo100
		)
		if ok then consider(value, "UnitPowerPercent") end
	end

	-- D) Raw current/max if the client exposes them.
	if type(UnitPower) == "function" and type(UnitPowerMax) == "function" then
		local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
		local okCurrent, current = pcall(UnitPower, "player", powerType)
		local okMaximum, maximum = pcall(UnitPowerMax, "player", powerType)
		current = okCurrent and ReadableNumber(current) or nil
		maximum = okMaximum and ReadableNumber(maximum) or nil
		if current ~= nil and maximum ~= nil and maximum > 0 then
			consider(current / maximum * 100, "UnitPower")
		end
	end

	if best ~= nil then
		lastReadableManaPct = best
		lastManaSource = bestSource or "gate"
		return best
	end

	-- If this frame is protected, keep the last conservative value rather than
	-- inventing a fresh high percentage.
	if type(lastReadableManaPct) == "number" then
		lastManaSource = "cached gate"
		return lastReadableManaPct
	end

	lastManaSource = "unreadable"
	return nil
end

local function SmiteShouldWand(s, mana)
	local threshold = WandManaThreshold(s)

	-- Exact semantics:
	--   mana <= slider -> Smite is blocked
	--   mana > slider  -> Smite may be used
	--   unreadable     -> fail closed and block Smite
	if type(mana) ~= "number" then
		return true, threshold, "Smite mana unavailable"
	end

	if mana <= threshold then
		return true, threshold,
			"Shoot instead of Smite: "
				.. tostring(math.floor(mana + 0.5))
				.. "% <= " .. tostring(threshold) .. "%"
	end

	return false, threshold
end

local mindBlastShootModeActive = false
local lastMindBlastManaPct = nil

local function MindBlastLowManaMode(s, mana)
	local threshold = MindBlastManaThreshold(s)

	if type(mana) == "number" then
		lastMindBlastManaPct = mana
		mindBlastShootModeActive = mana <= threshold
	elseif type(lastMindBlastManaPct) == "number" then
		mindBlastShootModeActive = lastMindBlastManaPct <= threshold
	else
		mindBlastShootModeActive = true
	end

	return mindBlastShootModeActive, lastMindBlastManaPct, threshold
end

local function ResolveFiller(s, filler, mana, reason)
	if not filler then return nil end

	if filler == "Smite" then
		local shouldWand, threshold, wandReason = SmiteShouldWand(s, mana)
		if shouldWand then
			local wand, why = Wand(
				s,
				wandReason or ("Smite blocked at " .. tostring(threshold) .. "% mana")
			)
			if wand then return wand, why end
			return nil, "Smite blocked by wand mana"
		end
	end

	if AL.SpellUsable(filler) then
		return filler, reason or "filler"
	end

	local wand, wandReason = Wand(s, "filler unavailable")
	if wand then return wand, wandReason end
	return nil, "Out of mana"
end

local function ResolveMindBlast(s, role, mana, reason)
	if role ~= "SHADOW" or not s.mindBlast then return nil end

	local lowMana, decisionMana, threshold = MindBlastLowManaMode(s, mana)

	-- Absolute interlock: the wand check only decides the replacement action.
	-- It can never re-enable Mind Blast.
	if lowMana then
		local reasonText
		if type(decisionMana) == "number" then
			reasonText =
				"Shoot instead of Mind Blast: "
					.. tostring(math.floor(decisionMana + 0.5))
					.. "% <= " .. tostring(threshold) .. "%"
		else
			reasonText = "Mind Blast mana unavailable"
		end

		local wand, why = Wand(s, reasonText)
		if wand then return wand, why end

		-- If wand detection fails, still do not permit Mind Blast.
		return nil, "Mind Blast blocked by mana gate"
	end

	if ReadyUsable("Mind Blast") then
		return "Mind Blast", reason or "on cooldown"
	end

	return nil
end

local function RealShieldActive()
	-- IMPORTANT:
	-- AL.HasBuff() falls back to a cast-inferred 30-second Shield timer when
	-- Forever hides player auras in combat. That fallback is too conservative
	-- for leveling because an absorbed Shield may be gone long before 30 sec.
	--
	-- Only let a REAL readable player-buff snapshot block the re-shield.
	if type(AL.DebugState) == "function" then
		local ok, state = pcall(AL.DebugState)
		if ok and type(state) == "table" and state.tooltipValid then
			return state.tooltipBuffs
				and state.tooltipBuffs["Power Word: Shield"] == true
		end
	end

	-- Aura state is unreadable. Do NOT trust the 30-second inferred Shield
	-- timer here; the 15-second Weakened Soul lock below is the authority.
	return false
end

local function HasWeakenedSoul()
	if type(AL.DebugState) == "function" then
		local ok, state = pcall(AL.DebugState)
		if ok and type(state) == "table" then
			-- 1) Real readable player-debuff snapshot is authoritative.
			if state.playerDebuffValid then
				return state.tooltipPlayerDebuffs
					and state.tooltipPlayerDebuffs["Weakened Soul"] == true
			end

			-- 2) If Forever hid the player aura, Core already maintains a
			-- 15-second inferred Weakened Soul state from the successful Shield
			-- cast. Use that before falling back to Priest's own timer.
			local inferred = state.playerDebuffs
				and state.playerDebuffs["Weakened Soul"]
			if type(inferred) == "table" then
				local expires = tonumber(inferred.expires)
				if not expires or expires > GetTime() then return true end
			elseif inferred then
				return true
			end
		end
	end

	-- 3) Final fallback if Core could not expose either state.
	return GetTime() < shieldLockUntil
end

local function ShieldReady()
	if not ReadyUsable("Power Word: Shield") then return false end
	if HasWeakenedSoul() then return false end
	if RealShieldActive() then return false end
	return true
end

local function MaintainCombatShield(s, inCombat)
	if not s.shield or not inCombat then return nil end
	if not ShieldReady() then return nil end
	return "Power Word: Shield", "maintain shield"
end

local function DirectHeal()
	if HealingKnown("Heal") then return "Heal" end
	if HealingKnown("Lesser Heal") then return "Lesser Heal" end
end

-- Original Priest filler selectors.
-- These were accidentally dropped during the healing/mana gate rebuild,
-- which caused the nil-function crash after Mind Blast was gated out.
local function ShadowFiller()
	if Ok("Mind Flay") then return "Mind Flay" end
	return Ok("Smite") and "Smite" or nil
end

local function SmiteFiller()
	if Ok("Smite") then return "Smite" end
	return Ok("Mind Flay") and "Mind Flay" or nil
end

-- Forward declaration is required because Preparation() calls the
-- healing decision function before its implementation appears below.
local PrioritySelfHealing

-- OUT-OF-COMBAT TOP PRIORITY TIER.
-- Lesser Heal is checked before Fortitude/Inner Fire.
local function TrackedPlayerBuffActive(name, expires, appliedAt, duration)
	local now = GetTime()
	local ok, state = pcall(AL.DebugState)
	if ok and SafeValue(state) and type(state) == "table"
		and SafeValue(state.tooltipValid) and state.tooltipValid == true then
		local buffs = state.tooltipBuffs
		local present = SafeValue(buffs) and type(buffs) == "table" and buffs[name]
		if SafeValue(present) then
			if present == true then
				if expires <= now then expires = now + duration end
				return true, expires
			end
			if expires > now and now - appliedAt < 0.5 then return true, expires end
			return false, 0
		end
	end
	local activeOK, active = pcall(AL.HasBuff, "player", name)
	if activeOK and SafeValue(active) and active == true then return true, expires end
	return expires > now, expires
end

local function DivineSpiritActive()
	local active
	active, divineSpiritUntil = TrackedPlayerBuffActive(DIVINE_SPIRIT, divineSpiritUntil, divineSpiritAppliedAt, 3600)
	return active
end

local function SpellAffordable(name)
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	local id = type(ref) == "table" and ReadableNumber(ref.id) or name
	local reader = IsUsableSpell or C_Spell and C_Spell.IsSpellUsable
	if type(reader) == "function" then
		local usableOK, usable, shortage = pcall(reader, id)
		if usableOK and (SafeValue(usable) and usable == false
			or SafeValue(shortage) and shortage == true) then return false end
	end
	local ok, cost = pcall(SpellManaCost, name)
	cost = ok and ReadableNumber(cost)
	if not cost or cost <= 0 then return true end
	local powerOK, amount = pcall(UnitPower, "player", 0)
	amount = powerOK and ReadableNumber(amount)
	if amount then return amount >= cost end
	local mana, maximum = GateManaPercent(), ReadManaMaximum()
	return type(mana) ~= "number" or not maximum or mana * maximum / 100 >= cost
end

local function Preparation(s, playerHP)
	-- Healing owns the top OOC priority tier.
	local heal, healReason = PrioritySelfHealing(s, false, playerHP)
	if heal then return heal, healReason end

	if not s.buffs then return nil end

	if Ok("Power Word: Fortitude")
		and not AL.HasBuff("player", "Power Word: Fortitude")
		and AL.SpellUsable("Power Word: Fortitude")
	then
		return "Power Word: Fortitude", "buff"
	end

	if s.divineSpirit and ReadyUsable(DIVINE_SPIRIT)
		and not DivineSpiritActive() and SpellAffordable(DIVINE_SPIRIT) then
		return DIVINE_SPIRIT, "buff"
	end

	if s.innerfire
		and Ok("Inner Fire")
		and not AL.HasBuff("player", "Inner Fire")
		and AL.SpellUsable("Inner Fire")
	then
		return "Inner Fire", "buff"
	end

	return nil
end

local function RenewAuraState()
	-- A readable Core tooltip sweep is authoritative for the REAL Renew aura.
	if type(AL.DebugState) == "function" then
		local ok, state = pcall(AL.DebugState)
		if ok and type(state) == "table" and state.tooltipValid then
			local active = state.tooltipBuffs
				and state.tooltipBuffs["Renew"] == true
				or false
			return active, active and "real aura present" or "real aura absent"
		end
	end

	-- If the live aura sweep is protected, only use a short lock after a
	-- positively observed successful Renew cast. Otherwise treat Renew as absent
	-- so healing is never silently suppressed.
	if GetTime() < renewLockUntil then
		return true, "successful Renew cast lock"
	end

	return false, "aura unreadable / no successful cast lock"
end

local function RenewActive()
	local active = RenewAuraState()
	return active
end

-- EXACT SELF-HEAL RULES:
--   Renew:
--     * in OR out of combat
--     * HP < 80%
--     * Renew aura/buff NOT present
--
--   Lesser Heal:
--     * in combat: HP < 60%
--     * out of combat: HP < 80% AND Renew aura/buff IS present
--
-- Renew is evaluated first, so at low HP with no Renew:
--   pass 1 -> Renew
--   next pass after successful Renew -> Lesser Heal when its rule is met.
PrioritySelfHealing = function(s, inCombat, playerHP)
	if type(playerHP) ~= "number" then
		return nil, "healing blocked: HP unreadable"
	end

	local renewActive, renewSource = RenewAuraState()

	if playerHP < 80
		and s.renew
		and not renewActive
		and HealingKnown("Renew")
	then
		return "Renew",
			"HP " .. tostring(math.floor(playerHP + 0.5))
				.. "% < 80%, Renew absent [" .. tostring(renewSource) .. "]"
	end

	if inCombat then
		if playerHP < 60
			and s.heal
			and HealingKnown("Lesser Heal")
		then
			return "Lesser Heal",
				"combat HP " .. tostring(math.floor(playerHP + 0.5))
					.. "% < 60%"
		end
	else
		if playerHP < 80
			and renewActive
			and s.heal
			and HealingKnown("Lesser Heal")
		then
			return "Lesser Heal",
				"OOC HP " .. tostring(math.floor(playerHP + 0.5))
					.. "% < 80% with Renew present"
		end
	end

	return nil
end

local function TouchBuffActive()
	local active
	active, touchBuffUntil = TrackedPlayerBuffActive(TOUCH, touchBuffUntil, touchAppliedAt, 600)
	return active
end

local function TouchTargetActive()
	local ok, active = pcall(AL.HasDebuff, "target", TOUCH)
	if ok and SafeValue(active) and active == true then return true end
	local guidOK, guid = pcall(UnitGUID, "target")
	guid = guidOK and TouchGUID(guid)
	local entry = guid and touchTargets[guid]
	if not entry then return false end
	if entry.expires <= GetTime() then touchTargets[guid] = nil; return false end
	local stateOK, state = pcall(AL.DebugState)
	if stateOK and SafeValue(state) and type(state) == "table"
		and SafeValue(state.debuffValid) and state.debuffValid == true
		and GetTime() - entry.appliedAt >= 0.5 then
		touchTargets[guid] = nil
		return false
	end
	return true
end

local function TouchReady()
	return ReadyUsable(TOUCH) and not TouchBuffActive() and not TouchTargetActive() and SpellAffordable(TOUCH)
end

local function EmergencyProtocol(s, inCombat, playerHP)
	if not inCombat then return nil end

	if s.fade and ReadyUsable("Fade") then
		local enemies = EngagedEnemies()
		if enemies > 1 then
			return "Fade", "multiple enemies"
		end
		if type(playerHP) == "number" and playerHP < 50 then
			return "Fade", "health below 50%"
		end
	end

	if s.touchOfWeakness and TouchReady() then
		if EngagedEnemies() > 1 then return TOUCH, "multiple enemies" end
		if type(playerHP) == "number" and playerHP < 50 then return TOUCH, "health below 50%" end
	end

	return nil
end

local function SelfRecovery(s, inCombat, hostile, playerHP, moving)
	if type(playerHP) ~= "number" then return nil end

	-- Desperate Prayer remains an emergency cooldown after the fixed
	-- Renew/Lesser Heal priority rules.
	if inCombat and s.heal and playerHP <= 20 and ReadyUsable("Desperate Prayer") then
		return "Desperate Prayer", "emergency heal"
	end

	if inCombat and hostile and s.fear
		and playerHP <= SettingNumber(s, "fearHP", 50, 5, 95)
		and AL.TargetInMelee() and ReadyUsable("Psychic Scream") then
		return "Psychic Scream", "make distance"
	end

	-- Existing pre-combat Shield behavior remains below the requested
	-- out-of-combat healing rules.
	if s.shield and not inCombat and hostile and ShieldReady() then
		return "Power Word: Shield", "pre-shield"
	end

	return nil
end

local function Burst(s, targetHP)
	if not AL.burst or not TargetWorthAtLeast(targetHP,
		SettingNumber(s, "burstMinTargetHP", 40, 0, 100)) then return nil end
	if ReadyUsable("Berserking") and not AL.HasBuff("player", "Berserking") then
		return "Berserking", "burst"
	end
	return nil
end

local function DamageOverTime(s, role, mana, targetHP)
	if role == "SHADOW" and s.vampiricEmbrace
		and TargetWorthAtLeast(targetHP, SettingNumber(s, "vampiricMinTargetHP", 60, 0, 100))
		and ReadyUsable("Vampiric Embrace")
		and not AL.HasDebuff("target", "Vampiric Embrace") then
		return "Vampiric Embrace", "shadow sustain"
	end
	if s.shadowWordPain
		and TargetWorthAtLeast(targetHP, SettingNumber(s, "dotMinTargetHP", 35, 0, 100))
		and ReadyUsable("Shadow Word: Pain")
		and not AL.HasDebuff("target", "Shadow Word: Pain") then
		return "Shadow Word: Pain", "dot"
	end
	if role == "SHADOW" and s.devouringPlague
		and ManaAtLeast(mana, SettingNumber(s, "plagueMinMana", 40, 0, 100))
		and TargetWorthAtLeast(targetHP, SettingNumber(s, "plagueMinTargetHP", 60, 0, 100))
		and ReadyUsable("Devouring Plague")
		and not AL.HasDebuff("target", "Devouring Plague") then
		return "Devouring Plague", "racial dot"
	end
	return nil
end

local function Opener(s, role, mana, targetHP, moving)
	-- DoTs ALWAYS come before direct-damage filler on a fresh target.
	-- This specifically prevents Smite from preceding Shadow Word: Pain.
	local dot, dotReason = DamageOverTime(s, role, mana, targetHP)
	if dot then return dot, dotReason end

	if moving then
		return nil, "Stop moving"
	end

	local mindBlast, mindBlastReason = ResolveMindBlast(s, role, mana, "ranged pull")
	if mindBlast then return mindBlast, mindBlastReason end

	if role == "SMITE" and s.holyFire and ReadyUsable("Holy Fire")
		and not AL.HasDebuff("target", "Holy Fire") then
		return "Holy Fire", "ranged pull"
	end

	if role == "SMITE" then
		local shouldWand, threshold, wandReason = SmiteShouldWand(s, mana)
		if shouldWand then
			local wand, why = Wand(s, wandReason or ("mana <= " .. tostring(threshold) .. "%"))
			if wand then return wand, why end
			return nil, "Smite blocked by wand mana"
		end
	end

	local filler = role == "SHADOW" and ShadowFiller() or SmiteFiller()
	local resolved, resolvedReason = ResolveFiller(s, filler, mana, "ranged pull")
	if resolved or resolvedReason then return resolved, resolvedReason end
	return Wand(s, "ranged pull")
end

local function PenanceNumber(value)
	value = ReadableNumber(value)
	if value and value == value and value > -math.huge and value < math.huge then return value end
end

local function PenanceCooldown()
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[PENANCE]
	local id = type(ref) == "table" and PenanceNumber(ref.id) or 402174
	if penance.cooldownID ~= id then
		penance.cooldownID, penance.cooldown, penance.liveCooldown = id, 12, false
	end
	local baseReader = C_Spell and C_Spell.GetSpellBaseCooldown or GetSpellBaseCooldown
	if not penance.liveCooldown and type(baseReader) == "function" then
		local ok, ms = pcall(baseReader, id)
		ms = ok and PenanceNumber(ms)
		if ms and ms > 1500 and ms < 120000 then penance.cooldown = ms / 1000 end
	end
	local start, duration, active, rate
	if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
		local ok, data = pcall(C_Spell.GetSpellCooldown, id)
		if ok and SafeValue(data) and type(data) == "table" then
			start, duration, rate = PenanceNumber(data.startTime), PenanceNumber(data.duration), PenanceNumber(data.modRate)
			if SafeValue(data.isActive) and type(data.isActive) == "boolean" then active = data.isActive end
		end
	elseif type(GetSpellCooldown) == "function" then
		local ok, first, second = pcall(GetSpellCooldown, id)
		if ok then start, duration = PenanceNumber(first), PenanceNumber(second) end
	end
	if duration and duration > 1.5 then
		local seconds = duration / (rate and rate > 0 and rate or 1)
		penance.cooldown, penance.liveCooldown = seconds, true
		if start and start > 0 then return start + seconds, active end
	end
	return nil, active
end

local function PenanceCastConfirmed(guid)
	local now = GetTime()
	for key, at in pairs(penance.seen) do if now - at > 30 then penance.seen[key] = nil end end
	if guid and penance.seen[guid] then return false end
	if not guid and (penance.sent and penance.sent.done or not penance.sent and now - penance.castAt < 2.5) then return false end
	local ending = PenanceCooldown()
	penance.castAt = now
	penance.untilTime = ending and ending > now and ending or now + penance.cooldown
	penance.castGUID = guid
	if guid then penance.seen[guid] = now end
	if penance.sent then penance.sent.done = true end
	SpendTrackedMana(PENANCE)
	return true
end

local function OffensivePenance(s, mana, moving)
	if not s.usePenance or moving or not Ok(PENANCE) then return nil end
	local threshold = s.offensivePenanceMana
	threshold = SafeValue(threshold) and PenanceNumber(tonumber(threshold)) or nil
	threshold = threshold and math.max(0, math.min(100, math.floor(threshold + 0.5))) or 80
	if type(mana) ~= "number" or mana < threshold then return nil end
	local targetOK, exists = pcall(UnitExists, "target")
	local attackOK, attackable = pcall(UnitCanAttack, "player", "target")
	local deadOK, dead = pcall(UnitIsDeadOrGhost, "target")
	if not targetOK or not SafeValue(exists) or exists ~= true
		or not attackOK or not SafeValue(attackable) or attackable ~= true
		or not deadOK or not SafeValue(dead) or dead ~= false then return nil end
	local rangeOK, inRange = pcall(AL.InRange, PENANCE)
	if rangeOK and SafeValue(inRange) and inRange == false then return nil end
	if not AL.SpellUsable(PENANCE) or not SpellAffordable(PENANCE) then return nil end
	local ending, active = PenanceCooldown()
	local now = GetTime()
	if now - penance.castAt < 0.5 then return nil end
	if ending then
		if ending > now then return nil end
	elseif active ~= nil then
		if active then return nil end
	elseif penance.untilTime > now then return nil end
	return PENANCE, "offensive penance"
end

local function Offense(s, role, mana, targetHP, moving)
	if s.silence and AL.TargetCasting() and ReadyUsable("Silence") then
		return "Silence", "interrupt"
	end

	-- Maintained DoTs are the first normal offensive priority.
	local dot, dotReason = DamageOverTime(s, role, mana, targetHP)
	if dot then return dot, dotReason end

	local burst, burstReason = Burst(s, targetHP)
	if burst then return burst, burstReason end

	local penanceSpell, penanceReason = OffensivePenance(s, mana, moving)
	if penanceSpell then return penanceSpell, penanceReason end

	-- Preserve the newest rev's target-health wand finisher. This is independent
	-- of the hard Smite/Mind Blast mana interlocks below.
	if type(targetHP) == "number"
		and targetHP <= SettingNumber(s, "wandTargetHP", 20, 0, 100)
		and not moving
	then
		local wand, wandReason = Wand(s, "wand finish")
		if wand or wandReason then return wand, wandReason end
	end

	if moving then return nil, "Stop moving" end

	local mindBlast, mindBlastReason = ResolveMindBlast(s, role, mana, "on cooldown")
	if mindBlast then return mindBlast, mindBlastReason end
	if role == "SMITE" and s.holyFire and ReadyUsable("Holy Fire")
		and TargetWorthAtLeast(targetHP, SettingNumber(s, "dotMinTargetHP", 35, 0, 100))
		and not AL.HasDebuff("target", "Holy Fire") then
		return "Holy Fire", "holy dot"
	end

	if role == "SMITE" then
		local shouldWand, threshold, wandReason = SmiteShouldWand(s, mana)
		if shouldWand then
			local wand, why = Wand(s, wandReason or ("mana <= " .. tostring(threshold) .. "%"))
			if wand then return wand, why end
			return nil, "Smite blocked by wand mana"
		end
	end

	local filler = role == "SHADOW" and ShadowFiller() or SmiteFiller()
	return ResolveFiller(s, filler, mana, "filler")
end


local priestDebug = {
	inCombat = false,
	hostile = false,
	hp = nil,
	mana = nil,
	manaSource = "unreadable",
	candidate = nil,
	candidateReason = nil,
	final = nil,
	finalReason = nil,
	smiteThreshold = nil,
	mindBlastThreshold = nil,
	smiteBlocked = nil,
	mindBlastBlocked = nil,
}

local function FinalManaGuard(s, spell, reason, mana)
	if spell ~= "Smite" and spell ~= "Mind Blast" then
		return spell, reason
	end

	local threshold
	if spell == "Smite" then
		threshold = WandManaThreshold(s)
	else
		threshold = MindBlastManaThreshold(s)
	end

	-- Fail CLOSED. If current mana cannot be established, Smite/Mind Blast
	-- are forbidden rather than allowed through.
	local blocked = type(mana) ~= "number" or mana <= threshold

	if spell == "Smite" then
		priestDebug.smiteThreshold = threshold
		priestDebug.smiteBlocked = blocked
	else
		priestDebug.mindBlastThreshold = threshold
		priestDebug.mindBlastBlocked = blocked
	end

	if blocked then
		local manaText = type(mana) == "number"
			and (tostring(math.floor(mana + 0.5)) .. "%")
			or "unreadable"
		local why = spell .. " FINAL BLOCK: mana " .. manaText
			.. " <= slider " .. tostring(threshold) .. "%"

		local wand = Wand(s, why)
		if wand then return "Shoot", why end
		return nil, why
	end

	return spell, reason
end

local function ComputeNextSpell(s, inCombat, hostile)
	local role = Role(s)
	local playerHP = PlayerHealthPercent()
	local mana = GateManaPercent()
	if type(mana) ~= "number" then
		mana = TrackedManaPercent()
	end
	local targetHP = hostile and AL.HealthPercent("target") or nil
	local moving = PlayerMoving()

	if not inCombat then
		-- HIGHEST OUT-OF-COMBAT PRIORITY TIER:
		-- Lesser Heal <=80% is checked first, then Fortitude/Inner Fire.
		local prep, prepReason = Preparation(s, playerHP)
		if prep then return prep, prepReason end
		local recovery, recoveryReason = SelfRecovery(s, false, hostile, playerHP, moving)
		if recovery then return recovery, recoveryReason end
		if s.drink and type(mana) == "number"
			and mana <= SettingNumber(s, "drinkMana", 35, 0, 80) then
			return nil, "Drink"
		end
		if not hostile then return nil, "Ready" end
		return Opener(s, role, mana, targetHP, moving)
	end

	-- HIGHEST COMBAT PRIORITY:
	-- Maintain Power Word: Shield before EVERY other Priest action.
	-- This runs before healing, fear, DoTs, burst, Mind Blast, Smite, Shoot/wand,
	-- and all other class-rotation recommendations.
	local combatShield, shieldReason = MaintainCombatShield(s, true)
	if combatShield then return combatShield, shieldReason end

	-- HIGHEST SELF-HEALING PRIORITY DIRECTLY AFTER SHIELD.
	local priorityHeal, priorityHealReason = PrioritySelfHealing(s, true, playerHP)
	if priorityHeal then return priorityHeal, priorityHealReason end

	local recovery, recoveryReason = SelfRecovery(s, true, hostile, playerHP, moving)
	if recovery then return recovery, recoveryReason end

	local emergency, emergencyReason = EmergencyProtocol(s, true, playerHP)
	if emergency then return emergency, emergencyReason end

	if not hostile then return nil, "No target" end
	return Offense(s, role, mana, targetHP, moving)
end

function M.NextSpell(s, inCombat, hostile)
	-- Existing saved profiles may be used before the menu first fills defaults.
	if type(s) == "table" and (not s.divineSpiritIconInitialized or not s.penanceIconInitialized) then AL.FillDefaults(s, "PRIEST") end
	if GetTime() < penance.channelUntil then return nil, "Channeling" end
	local role = Role(s)
	local hp = PlayerHealthPercent()
	local mana = GateManaPercent()

	-- Store the exact values that this rotation pass is using.
	priestDebug.inCombat = inCombat and true or false
	priestDebug.hostile = hostile and true or false
	priestDebug.hp = hp
	priestDebug.mana = mana
	priestDebug.manaSource = lastManaSource
	priestDebug.smiteThreshold = WandManaThreshold(s)
	priestDebug.mindBlastThreshold = MindBlastManaThreshold(s)
	priestDebug.smiteBlocked =
		type(mana) ~= "number" or mana <= priestDebug.smiteThreshold
	priestDebug.mindBlastBlocked =
		type(mana) ~= "number" or mana <= priestDebug.mindBlastThreshold

	local spell, reason = ComputeNextSpell(s, inCombat, hostile)
	priestDebug.candidate = spell
	priestDebug.candidateReason = reason

	-- Absolute final interlock. No internal branch can bypass this.
	local finalSpell, finalReason = FinalManaGuard(s, spell, reason, mana)
	priestDebug.final = finalSpell
	priestDebug.finalReason = finalReason

	return finalSpell, finalReason
end

function M.HealingState()
	local profile = AL.S()
	local hp = priestDebug.hp
	if type(hp) ~= "number" then hp = PlayerHealthPercent() end

	local renewActive, renewSource = RenewAuraState()
	local renewKnown = HealingKnown("Renew")
	local lesserKnown = HealingKnown("Lesser Heal")
	local inCombat = priestDebug.inCombat and true or false

	local renewDecision = "WAIT"
	if type(hp) ~= "number" then
		renewDecision = "BLOCK: HP unreadable"
	elseif hp < 80 and profile and profile.renew and not renewActive and renewKnown then
		renewDecision = "CAST RENEW"
	elseif hp >= 80 then
		renewDecision = "WAIT: HP >= 80"
	elseif renewActive then
		renewDecision = "WAIT: Renew present"
	elseif not (profile and profile.renew) then
		renewDecision = "BLOCK: Renew toggle off"
	elseif not renewKnown then
		renewDecision = "BLOCK: Renew not known"
	end

	local lesserDecision = "WAIT"
	if type(hp) ~= "number" then
		lesserDecision = "BLOCK: HP unreadable"
	elseif not (profile and profile.heal) then
		lesserDecision = "BLOCK: heal toggle off"
	elseif not lesserKnown then
		lesserDecision = "BLOCK: Lesser Heal not known"
	elseif inCombat and hp < 60 then
		if hp < 80 and profile.renew and not renewActive and renewKnown then
			lesserDecision = "WAIT: Renew first"
		else
			lesserDecision = "CAST LESSER HEAL"
		end
	elseif (not inCombat) and hp < 80 and renewActive then
		lesserDecision = "CAST LESSER HEAL"
	elseif inCombat then
		lesserDecision = "WAIT: combat HP >= 60"
	elseif hp >= 80 then
		lesserDecision = "WAIT: OOC HP >= 80"
	else
		lesserDecision = "WAIT: OOC requires Renew present"
	end

	return {
		inCombat = inCombat,
		hp = hp,
		renewEnabled = profile and profile.renew == true,
		renewKnown = renewKnown,
		renewActive = renewActive,
		renewSource = renewSource,
		renewDecision = renewDecision,
		healEnabled = profile and profile.heal == true,
		lesserHealKnown = lesserKnown,
		lesserDecision = lesserDecision,
		candidate = priestDebug.candidate,
		final = priestDebug.final,
		finalReason = priestDebug.finalReason,

		eventHealthPct = eventHealthPct,
		eventHealthSource = eventHealthSource,
		eventHealthAge = type(eventHealthAt) == "number" and (GetTime() - eventHealthAt) or nil,
		healthEventCount = healthEventCount,

		trackedHealth = trackedHealth,
		trackedHealthMax = trackedHealthMax,
		trackedHealthPct = TrackedHealthPercent(),
		trackedHealthSource = trackedHealthSource,
		trackedHealthLastEvent = trackedHealthLastEvent,
		trackedHealthLastAmount = trackedHealthLastAmount,
		combatHealthEventCount = combatHealthEventCount,

		predictionHealthPct = predictionHealthPct,
		predictionHealthSource = predictionHealthSource,
		predictionHealthHasSecrets = predictionHealthHasSecrets,
		predictionHealthAge = type(predictionHealthAt) == "number" and (GetTime() - predictionHealthAt) or nil,

		frameHealthPct = frameHealthPct,
		frameHealthSource = frameHealthSource,
		frameHealthText = frameHealthText,
		frameHealthAge = type(frameHealthAt) == "number" and (GetTime() - frameHealthAt) or nil,
	}
end

function M.ManaGateState()
	local profile = AL.S()
	local mana = priestDebug.mana
	if type(mana) ~= "number" then
		mana = GateManaPercent()
	end

	local smiteThreshold = WandManaThreshold(profile)
	local mindBlastThreshold = MindBlastManaThreshold(profile)
	local smiteBlocked = type(mana) ~= "number" or mana <= smiteThreshold
	local mindBlastBlocked = type(mana) ~= "number" or mana <= mindBlastThreshold

	return {
		mana = mana,
		source = priestDebug.manaSource or lastManaSource,
		trackedPct = TrackedManaPercent(),
		trackedMana = trackedMana,
		trackedManaMax = trackedManaMax,
		trackedSource = trackedSource,
		lastSpell = trackedLastSpell,
		lastCost = trackedLastCost,
		smiteThreshold = smiteThreshold,
		mindBlastThreshold = mindBlastThreshold,
		smiteBlocked = smiteBlocked,
		mindBlastBlocked = mindBlastBlocked,
		candidate = priestDebug.candidate,
		candidateReason = priestDebug.candidateReason,
		final = priestDebug.final,
		finalReason = priestDebug.finalReason,

		eventManaPct = eventManaPct,
		eventManaSource = eventManaSource,
		eventManaAge = type(eventManaAt) == "number" and (GetTime() - eventManaAt) or nil,
		manaEventCount = manaEventCount,

		castSentCount = castSentCount,
		castSucceededCount = castSucceededCount,
		castFallbackCount = castFallbackCount,
		lastSentCastName = lastSentCastName,
		lastSucceededCastName = lastSucceededCastName,
	}
end

function M.SecretHealVisualState()
	-- Forever can make the player's actual health percentage a Secret Value.
	-- Do not try to inspect it here.  Return only the NON-SECRET pieces needed
	-- by Display.lua / Glow.lua so they can let Blizzard's curve system drive
	-- the visual alpha directly from the protected health percentage.
	local s = AL.S()
	if type(s) ~= "table" then return nil end

	local inCombat = false
	if type(UnitAffectingCombat) == "function" then
		local ok, value = pcall(UnitAffectingCombat, "player")
		if ok and not (issecretvalue and issecretvalue(value)) then
			inCombat = value and true or false
		end
	end

	local renewActive = RenewActive()

	-- Highest healing priority:
	-- Renew below 80% whenever Renew is absent.
	if s.renew
		and HealingKnown("Renew")
		and not renewActive
	then
		return "Renew", 80, "Renew absent; secret-health threshold 80", inCombat, renewActive
	end

	-- Once Renew is active, Lesser Heal becomes the direct-heal layer.
	if s.heal and HealingKnown("Lesser Heal") then
		if inCombat then
			return "Lesser Heal", 60, "combat direct-heal threshold 60", true, renewActive
		end

		if renewActive then
			return "Lesser Heal", 80, "OOC direct-heal threshold 80 with Renew active", false, true
		end
	end

	return nil
end

function M.DecisionDebugState()
	return priestDebug
end

function M.ManaPercent()
	local gate = GateManaPercent()
	local tracked = TrackedManaPercent()
	local threshold = WandManaThreshold(AL.S())

	if type(gate) == "number" then
		return gate, lastManaSource, gate, threshold, tracked
	end

	if type(tracked) == "number" then
		return tracked, trackedSource, tracked, threshold, tracked
	end

	return nil, "unreadable", nil, threshold, nil
end

function M.MindBlastState()
	local profile = AL.S()
	local threshold = MindBlastManaThreshold(profile)
	local lowMana = mindBlastShootModeActive

	if type(lastMindBlastManaPct) == "number" then
		lowMana = lastMindBlastManaPct <= threshold
	end

	return {
		equipped = WandEquipped(),
		threshold = threshold,
		mana = lastMindBlastManaPct,
		lowMana = lowMana,
		decision = lowMana and "SHOOT/BLOCK" or "MIND BLAST",
	}
end

function M.WandState()
	local profile = AL.S()
	local mana = GateManaPercent()
	local threshold = WandManaThreshold(profile)
	local lowMana = type(mana) ~= "number" or mana <= threshold

	return {
		equipped = WandEquipped(),
		threshold = threshold,
		mana = mana,
		trackedMana = trackedMana,
		trackedManaMax = trackedManaMax,
		trackedPct = TrackedManaPercent(),
		trackedLastSpell = trackedLastSpell,
		trackedLastCost = trackedLastCost,
		trackedSource = trackedSource,
		lowMana = lowMana,
		decision = WandEquipped() and lowMana and "SHOOT" or "SMITE",
	}
end

function M.GetUIState()
	return {
		role = Role(AL.S()),
		mana = TrackedManaPercent(),
		moving = PlayerMoving(),
		wanding = PlayerIsWanding(),
		shieldLocked = GetTime() < shieldLockUntil,
	}
end

-- Keep the consumable self-buff separate from the ordinary damage proc. The
-- proc can use a different spell ID, and combat aura reads can be protected.
local touchTracker = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "COMBAT_LOG_EVENT_UNFILTERED",
	"PLAYER_DEAD", "PLAYER_ENTERING_WORLD" }) do pcall(touchTracker.RegisterEvent, touchTracker, event) end
touchTracker:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
	if AL.playerClass ~= "PRIEST" then return end
	if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
		touchBuffUntil, touchAppliedAt, touchTargets, touchSent, touchLastSuccessGUID = 0, 0, {}, nil, nil
		return
	end
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if type(CombatLogGetCurrentEventInfo) ~= "function" then return end
		local ok, _, sub, _, source, _, _, _, dest, _, _, _, id = pcall(CombatLogGetCurrentEventInfo)
		if not ok or not SafeValue(sub) then return end
		local playerOK, player = pcall(UnitGUID, "player")
		player, source, dest = playerOK and TouchGUID(player), TouchGUID(source), TouchGUID(dest)
		if not player then return end
		if TouchSpellID(id, TOUCH_CAST_IDS) and dest == player then
			if sub == "SPELL_AURA_REMOVED" then touchBuffUntil = 0
			elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" then
				touchBuffUntil, touchAppliedAt = GetTime() + 600, GetTime()
			end
		elseif TouchSpellID(id, TOUCH_PROC_IDS) and source == player and dest and dest ~= player then
			if sub == "SPELL_AURA_REMOVED" then touchTargets[dest] = nil
			elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" or sub == "SPELL_DAMAGE" then
				touchBuffUntil = 0
				touchTargets[dest] = { expires = GetTime() + 120, appliedAt = GetTime() }
			elseif sub == "SPELL_MISSED" then touchBuffUntil = 0 end
		end
		return
	end
	if not SafeValue(unit) or unit ~= "player" then return end
	if event == "UNIT_SPELLCAST_SENT" then
		touchSent = nil
		if TouchSentSpell(arg2, arg3, arg4) then
			touchSent = { at = GetTime(), guid = TouchCastGUID(arg3) }
		end
		return
	end
	local guid = TouchCastGUID(arg2)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		if touchSent and (not guid or not touchSent.guid or guid == touchSent.guid) then
			touchSent = nil
			if lastSentCastName == TOUCH then lastSentCastName, lastSentCastAt = nil, 0 end
		end
		return
	end
	if TouchSpellID(arg3, TOUCH_PROC_IDS) then return end
	local id = SafeValue(arg3) and type(arg3) == "number" and arg3
	local pending = touchSent and GetTime() - touchSent.at < 5
		and (not guid or not touchSent.guid or guid == touchSent.guid)
	if not TouchSpellID(id, TOUCH_CAST_IDS) and not (not id and pending) then return end
	if guid and guid == touchLastSuccessGUID then return end
	touchBuffUntil, touchAppliedAt, touchLastSuccessGUID = GetTime() + 600, GetTime(), guid
	touchSent = nil
end)

local penanceTracker = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
	"UNIT_SPELLCAST_INTERRUPTED", "PLAYER_DEAD", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_LOGIN" }) do
	pcall(penanceTracker.RegisterEvent, penanceTracker, event)
end
penanceTracker:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
	if AL.playerClass ~= "PRIEST" then return end
	if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
		penance.untilTime, penance.channelUntil, penance.castAt, penance.sent, penance.seen = 0, 0, -math.huge, nil, {}
		penance.cooldown, penance.cooldownID, penance.liveCooldown = 12, nil, false
		PenanceCooldown(); return
	elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_LOGIN" then
		penance.liveCooldown = false
		PenanceCooldown(); return
	end
	if not SafeValue(unit) or unit ~= "player" then return end
	local id = PenanceNumber(arg4) or PenanceNumber(arg3)
	if event == "UNIT_SPELLCAST_SENT" then
		if id and PENANCE_PROCS[id] then return end
		penance.sent = nil
		local name = CastName(arg2, arg3, arg4)
		if PenanceSpellID(id) or not id and (name == PENANCE
			or (not name or not (AL.known and AL.known[name])) and AL.lastSuggestion == PENANCE and Ok(PENANCE)) then
			penance.sent = { at = GetTime(), guid = TouchCastGUID(arg3), done = false }
		end
		return
	end
	local guid = TouchCastGUID(arg2)
	local pending = penance.sent and GetTime() - penance.sent.at < 5
		and (not guid or not penance.sent.guid or guid == penance.sent.guid)
	if event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED"
		or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
		if PenanceSpellID(id) or id and PENANCE_PROCS[id] or pending or guid and guid == penance.castGUID then
			penance.channelUntil = 0
			if pending and not penance.sent.done then penance.sent = nil end
			if lastSentCastName == PENANCE then lastSentCastName, lastSentCastAt = nil, 0 end
		end
		return
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if id and PENANCE_PROCS[id] then return end
		if PenanceSpellID(id) or not id and pending then PenanceCastConfirmed(guid) end
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		if PenanceSpellID(id) or id and PENANCE_PROCS[id] or not id and pending then
			local confirmed = PenanceCastConfirmed(guid)
			if confirmed or GetTime() - penance.castAt < 0.5 and (not guid or guid == penance.castGUID) then
				penance.channelUntil = GetTime() + 2.5
			end
		end
	end
end)

AL.RegisterRotation("PRIEST", M)
-- END ORIGINAL LEVELING IMPLEMENTATION
    end)(ADDON, RotationScope(true))

    ;(function(...)
-- BEGIN OPTIONAL TALENT BUILD IMPLEMENTATION
local ADDON, AL = ...

-- WoW Forever Priest leveling 1-60 - v0.28.4
-- Shadow reference: Forever 1.60.1.70338, MythicSim 944a791060db.
-- SHADOW favorise Mind Blast / Mind Flay ; SMITE favorise Holy Fire / Smite.
-- Les soins concernent le joueur : aucune cible de groupe n'est devinee.

local A = _G.Action

local M = {
	defaults = {
        leveling = true,
		priestRole = "SHADOW",
		shadow = false,
		shadowForm = true,
		shadowMindFlay = true,
		shadowWordDeath = true,
		shadowDeathMinHP = 50,
		shadowInnerFocus = true,
		shadowRacials = true,
		shadowFiend = true,
		shadowFiendMana = 70,
		shadowSacrifice = false,
		shadowSacrificeMana = 30,
		shadowSacrificeHP = 80,
		aoe = false,
		shadowHolyNova = false,
		aoeMinEnemies = 2,
		aoeMinMana = 40,
		buffs = true,
		divineSpirit = true,
		innerfire = true,
		shield = true,
		shieldHP = 65,
		fade = true,
		touchOfWeakness = true,
		renew = true,
		heal = true,
		healHP = 35,
		fear = true,
		fearHP = 50,
		silence = true,
		wand = true,
		wandMana = 25,
		wandTargetHP = 20,
		drink = true,
		drinkMana = 35,
		shadowWordPain = true,
		dotMinTargetHP = 35,
		devouringPlague = true,
		plagueMinMana = 40,
		plagueMinTargetHP = 60,
		vampiricEmbrace = true,
		vampiricMinTargetHP = 60,
		mindBlast = true,
		mindBlastMana = 50,
		usePenance = true,
		offensivePenanceMana = 80,
		holyFire = true,
		burstMinTargetHP = 40,
	},
}

local shadow = { cooldowns={}, dots={}, buffs={}, pending={}, completed={}, talents={},
    curves={}, curveFailures={}, form=nil, formAt=-math.huge, channelUntil=0 }

-- IDs classiques de rang 1. Les raciaux et talents ne sont utilises que si
-- le grimoire Forever les expose reellement comme appris.
-- Exactly one rotation stays selected. Leveling is the default and the
-- fallback when a selected specialization is switched off or saved flags
-- conflict. A valid saved specialization takes priority during migration.
M.buildKeys = { "leveling", "shadow" }
function M.NormalizeBuild(s)
    if type(s) ~= "table" then return end
    local selected, count = nil, 0
    for _, key in ipairs(M.buildKeys) do
        if key ~= "leveling" then
            local value = s[key]
            local checked = not (issecretvalue and issecretvalue(value)) and value == true
            s[key] = checked
            if checked then selected, count = key, count + 1 end
        end
    end
    if count ~= 1 then
        for _, key in ipairs(M.buildKeys) do s[key] = false end
        selected = "leveling"
    end
    s.leveling = selected == "leveling"
    return selected
end
function M.SetBuild(key, enabled, s)
    if (issecretvalue and issecretvalue(enabled)) or type(enabled) ~= "boolean" then return end
    local valid = false
    for _, candidate in ipairs(M.buildKeys) do if candidate == key then valid = true; break end end
    if not valid then return end
    s = s or AL.Profile("PRIEST")
    if type(s) ~= "table" then return end
    if enabled then
        for _, candidate in ipairs(M.buildKeys) do s[candidate] = candidate == key end
    else
        s[key] = false
    end
    local selected = M.NormalizeBuild(s)
    if AL.UI and type(AL.UI.Repaint) == "function" then AL.UI.Repaint() end
    return selected
end

M.spells = {
	{ 20554, "Berserking" },
	{ 528, "Cure Disease" },
	{ 1277324, "Dark Sacrifice" },
	{ 13908, "Desperate Prayer" },
	{ 2944, "Devouring Plague" },
	{ 527, "Dispel Magic" },
	{ 14752, "Divine Spirit" },
	{ 1259799, "Elune's Light" },
	{ 1259823, "Eureka!" },
	{ 586, "Fade" },
	{ 2054, "Heal" },
	{ 14914, "Holy Fire" },
	{ 15237, "Holy Nova" },
	{ 588, "Inner Fire" },
	{ 14751, "Inner Focus" },
	{ 2050, "Lesser Heal" },
	{ 8092, "Mind Blast" },
	{ 15407, "Mind Flay" },
	{ 453, "Mind Soothe" },
	{ 2096, "Mind Vision" },
	{ 402174, "Penance" },
	{ 1243, "Power Word: Fortitude" },
	{ 17, "Power Word: Shield" },
	{ 596, "Prayer of Healing" },
	{ 8122, "Psychic Scream" },
	{ 139, "Renew" },
	{ 2006, "Resurrection" },
	{ 9484, "Shackle Undead" },
	{ 589, "Shadow Word: Pain" },
	{ 1309595, "Shadow Word: Death" },
	{ 401977, "Shadowfiend" },
	{ 15473, "Shadowform" },
	{ 15487, "Silence" },
	{ 585, "Smite" },
	{ 5019, "Shoot" },
	{ 2652, "Touch of Weakness" },
	{ 15286, "Vampiric Embrace" },
}

local DIVINE_SPIRIT = "Divine Spirit"
local DIVINE_SPIRIT_ICON = AL.UNIVERSAL_ICONS[9]
local PENANCE = "Penance"
local PENANCE_ICON = AL.UNIVERSAL_ICONS[8]
local PENANCE_PROCS = { [402261] = true, [402277] = true, [402284] = true, [402289] = true,
	[1240723] = true, [1240727] = true, [1240732] = true, [1240734] = true }
local penance = { cooldown = 12, untilTime = 0, castAt = -math.huge, channelUntil = 0, seen = {} }
AL.IconOverrides = AL.IconOverrides or {}
AL.IconOverrides[DIVINE_SPIRIT] = function() return DIVINE_SPIRIT_ICON end
AL.IconOverrides[PENANCE] = function() return PENANCE_ICON end

-- Seed the default once in both new and existing Priest profiles. Keep a
-- user's later icon choice, including choosing the default icon again.
local FillDefaults = AL.FillDefaults
function AL.FillDefaults(profile, token)
	FillDefaults(profile, token)
	if token == "PRIEST" and not profile.divineSpiritIconInitialized then
		profile.icons = profile.icons or {}
		if profile.icons[DIVINE_SPIRIT] == nil then profile.icons[DIVINE_SPIRIT] = DIVINE_SPIRIT_ICON end
		profile.divineSpiritIconInitialized = true
	end
	if token == "PRIEST" and not profile.penanceIconInitialized then
		profile.icons = profile.icons or {}
		if profile.icons[PENANCE] == nil then profile.icons[PENANCE] = PENANCE_ICON end
		profile.penanceIconInitialized = true
	end
end

AL.selfCastSpells = AL.selfCastSpells or {}
for _, name in ipairs({
	"Power Word: Fortitude", "Divine Spirit", "Inner Fire", "Power Word: Shield", "Renew",
	"Heal", "Lesser Heal", "Desperate Prayer", "Berserking", "Fade", "Touch of Weakness",
	"Shadowform", "Inner Focus", "Dark Sacrifice", "Eureka!", "Elune's Light", "Holy Nova",
}) do
	AL.selfCastSpells[name] = true
end

local MINLEVEL = {
	["Lesser Heal"] = 1,
	["Power Word: Fortitude"] = 1,
	["Divine Spirit"] = 30,
	["Penance"] = 30,
	["Smite"] = 1,
	["Shadow Word: Pain"] = 4,
	["Power Word: Shield"] = 6,
	["Fade"] = 8,
	["Touch of Weakness"] = 10,
	["Renew"] = 8,
	["Mind Blast"] = 10,
	["Resurrection"] = 10,
	["Inner Fire"] = 12,
	["Psychic Scream"] = 14,
	["Heal"] = 16,
	["Holy Fire"] = 20,
	["Dispel Magic"] = 18,
	["Shackle Undead"] = 20,
	["Cure Disease"] = 22,
	["Mind Soothe"] = 20,
	["Prayer of Healing"] = 30,
	["Mind Vision"] = 22,
}

local Ok = select(1, AL.LevelGates(MINLEVEL))
M.minLevels = MINLEVEL

-- Weakened Soul fallback is configured for 15 seconds on this Forever client.
-- Prefer the real player debuff when Core can read it; this timer is only the
-- fallback when combat hides the aura.
local shieldLockUntil = 0
local renewLockUntil = 0
local wandEventActive = false
local tracker = CreateFrame("Frame")
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_SPELLCAST_SUCCEEDED", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_SPELLCAST_SUCCEEDED")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_SPELLCAST_SENT", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_SPELLCAST_SENT")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_SPELLCAST_FAILED", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_SPELLCAST_FAILED")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_SPELLCAST_INTERRUPTED", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_SPELLCAST_INTERRUPTED")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_HEALTH", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_HEALTH")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_MAXHEALTH", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_MAXHEALTH")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_POWER_UPDATE", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_POWER_UPDATE")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_POWER_FREQUENT", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_POWER_FREQUENT")
end
if not pcall(tracker.RegisterUnitEvent, tracker, "UNIT_MAXPOWER", "player") then
	pcall(tracker.RegisterEvent, tracker, "UNIT_MAXPOWER")
end
pcall(tracker.RegisterEvent, tracker, "COMBAT_LOG_EVENT_UNFILTERED")
pcall(tracker.RegisterEvent, tracker, "START_AUTOREPEAT_SPELL")
pcall(tracker.RegisterEvent, tracker, "STOP_AUTOREPEAT_SPELL")
pcall(tracker.RegisterEvent, tracker, "PLAYER_DEAD")
pcall(tracker.RegisterEvent, tracker, "PLAYER_ENTERING_WORLD")
pcall(tracker.RegisterEvent, tracker, "PLAYER_REGEN_DISABLED")
pcall(tracker.RegisterEvent, tracker, "PLAYER_REGEN_ENABLED")

local function SafeValue(value)
	return not (issecretvalue and issecretvalue(value))
end

local TOUCH = "Touch of Weakness"
local TOUCH_CAST_IDS = { [2652] = true, [19261] = true, [19262] = true }
local TOUCH_PROC_IDS = { [2943] = true, [19249] = true, [19251] = true }
local touchBuffUntil, touchAppliedAt = 0, 0
local divineSpiritUntil, divineSpiritAppliedAt = 0, 0
local touchTargets, touchSent, touchLastSuccessGUID = {}, nil, nil

local function TouchSpellID(value, ids)
	if not SafeValue(value) or type(value) ~= "number" then return false end
	if ids[value] then return true end
	if ids == TOUCH_CAST_IDS then
		local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[TOUCH]
		local id = type(ref) == "table" and ref.id
		return SafeValue(id) and type(id) == "number" and id == value
	end
	return false
end

local function TouchGUID(value)
	if SafeValue(value) and type(value) == "string" then return value end
end

local function TouchCastGUID(value)
	local guid = TouchGUID(value)
	return guid and guid:find("^Cast%-") and guid or nil
end

local function DivineSpiritSpellID(value)
	if not SafeValue(value) or type(value) ~= "number" then return false end
	if value == 14752 then return true end
	local spiritRef = AL.rangeSpellRefs and AL.rangeSpellRefs[DIVINE_SPIRIT]
	local spiritID = type(spiritRef) == "table" and spiritRef.id
	return SafeValue(spiritID) and type(spiritID) == "number" and value == spiritID
end

local function PenanceSpellID(value)
	if not SafeValue(value) or type(value) ~= "number" or PENANCE_PROCS[value] then return false end
	if value == 402174 then return true end
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[PENANCE]
	local id = type(ref) == "table" and ref.id
	return SafeValue(id) and type(id) == "number" and value == id
end

local function CastName(arg2, arg3, arg4)
	if TouchSpellID(arg4, TOUCH_CAST_IDS) or TouchSpellID(arg3, TOUCH_CAST_IDS) then return TOUCH end
	if DivineSpiritSpellID(arg4) or DivineSpiritSpellID(arg3) then return DIVINE_SPIRIT end
	if PenanceSpellID(arg4) or PenanceSpellID(arg3) then return PENANCE end
	for _, value in ipairs({ arg4, arg3 }) do
		if type(value) == "number" and SafeValue(value) then
			local ok, name = pcall(AL.SpellName, value)
			if ok and type(name) == "string" and SafeValue(name) then return name end
		end
	end
	if type(arg2) == "string" and SafeValue(arg2) and not arg2:find("^Cast%-") then
		return arg2
	end
end

local function TouchSentSpell(arg2, arg3, arg4)
	local id = SafeValue(arg4) and type(arg4) == "number" and arg4
		or SafeValue(arg3) and type(arg3) == "number" and arg3
	if id then return TouchSpellID(id, TOUCH_CAST_IDS) end
	local name = CastName(arg2, arg3, arg4)
	return name == TOUCH or (not name or not (AL.known and AL.known[name]))
		and AL.lastSuggestion == TOUCH and Ok(TOUCH)
end


-- ============================================================================
-- TRACKED PRIEST MANA
-- ----------------------------------------------------------------------------
-- On this Forever client, current mana is never readable, but maximum mana is.
-- Therefore initialize from the readable maximum and track spending ourselves.
--
-- This tracked value supports Priest mana gates when current mana is protected.
-- ============================================================================
local trackedMana = nil
local trackedManaMax = nil
local trackedManaUpdatedAt = nil
local trackedLastSpendAt = nil
local trackedLastSpell = nil
local trackedLastCost = 0
local trackedSource = "uninitialized"
local cachedBaseManaRegen = 0
local cachedCastingManaRegen = 0

-- Robust event sensors / diagnostics.
local lastSentCastName = nil
local lastSentCastAt = 0
local castSentCount = 0
local castSucceededCount = 0
local castFallbackCount = 0
local lastSucceededCastName = nil

local eventHealthPct = nil
local eventHealthSource = "unreadable"
local eventHealthAt = nil
local healthEventCount = 0

local eventManaPct = nil
local eventManaSource = "unreadable"
local eventManaAt = nil
local manaEventCount = 0

-- When Forever keeps health secret, maintain a best-effort health estimate
-- from readable combat-log damage/heal amounts.
local trackedHealth = nil
local trackedHealthMax = nil
local trackedHealthSource = "uninitialized"
local trackedHealthLastEvent = nil
local trackedHealthLastAmount = nil
local trackedHealthAt = nil
local combatHealthEventCount = 0

local predictionHealthPct = nil
local predictionHealthSource = "unavailable"
local predictionHealthHasSecrets = nil
local predictionHealthAt = nil

local frameHealthPct = nil
local frameHealthSource = "unavailable"
local frameHealthAt = nil
local frameHealthText = nil
local cachedPlayerHealthBar = nil
local healthPredictionCalculator = nil

local function ReadableNumber(value)
	if type(value) ~= "number" then return nil end
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function ReadManaMaximum()
	local maximum

	if type(UnitPowerMax) == "function" then
		local ok, value = pcall(UnitPowerMax, "player")
		value = ok and ReadableNumber(value) or nil
		if value and value > 0 then maximum = value end

		if not maximum then
			ok, value = pcall(UnitPowerMax, "player", 0)
			value = ok and ReadableNumber(value) or nil
			if value and value > 0 then maximum = value end
		end
	end

	if not maximum and type(AL.ManaDebugSources) == "function" then
		local ok, d = pcall(AL.ManaDebugSources)
		if ok and type(d) == "table" then
			maximum = ReadableNumber(d.primaryMax)
				or ReadableNumber(d.typedMax)
				or ReadableNumber(d.cachedMax)
		end
	end

	return maximum
end

local function RefreshManaRegen()
	if type(GetManaRegen) ~= "function" then return end
	local ok, base, casting = pcall(GetManaRegen)
	if not ok then return end

	base = ReadableNumber(base)
	casting = ReadableNumber(casting)

	if base and base >= 0 then cachedBaseManaRegen = base end
	if casting and casting >= 0 then cachedCastingManaRegen = casting end
end

local function EnsureTrackedMana()
	local maximum = ReadManaMaximum()
	if maximum and maximum > 0 then
		if not trackedManaMax or trackedManaMax ~= maximum then
			-- Preserve percentage across a max-mana change when possible.
			if trackedMana and trackedManaMax and trackedManaMax > 0 then
				local pct = trackedMana / trackedManaMax
				trackedMana = math.max(0, math.min(maximum, maximum * pct))
			end
			trackedManaMax = maximum
		end
	end

	if not trackedManaMax or trackedManaMax <= 0 then return false end

	if trackedMana == nil then
		-- Critical difference from the failed estimator: current mana does NOT
		-- need to be readable. Start from the readable maximum.
		trackedMana = trackedManaMax
		trackedManaUpdatedAt = GetTime()
		trackedSource = "max-initialized"
	end

	RefreshManaRegen()
	return true
end

local function UpdateTrackedManaRegen()
    if AL.S().shadow==true and shadow.Regen then return shadow.Regen() end
	if not EnsureTrackedMana() then return end

	local now = GetTime()
	if not trackedManaUpdatedAt then
		trackedManaUpdatedAt = now
		return
	end

	local dt = now - trackedManaUpdatedAt
	if dt <= 0 then return end
	trackedManaUpdatedAt = now

	-- Use the client-provided regen rates when readable. During the 5-second
	-- rule, use the casting rate; afterward use the normal base rate.
	local rate
	if trackedLastSpendAt and (now - trackedLastSpendAt) < 5 then
		rate = cachedCastingManaRegen
	else
		rate = cachedBaseManaRegen
	end

	rate = tonumber(rate) or 0
	if rate > 0 then
		trackedMana = math.min(trackedManaMax, trackedMana + rate * dt)
	end
end

local function SpellManaCost(spellName)
	if type(spellName) ~= "string" or spellName == "" then return 0 end

	local identifiers = {}
	local seen = {}

	local function AddIdentifier(value)
		if value == nil or seen[value] then return end
		seen[value] = true
		identifiers[#identifiers + 1] = value
	end

	-- Prefer the exact learned spell/rank ID discovered by Core.
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[spellName]
	if type(ref) == "table" then AddIdentifier(ref.id) end

	-- Then the classic spell ID registered by the Priest module.
	for _, def in ipairs(M.spells or {}) do
		if def[2] == spellName then
			AddIdentifier(def[1])
			break
		end
	end

	-- Last fallback: name.
	AddIdentifier(spellName)

	for _, identifier in ipairs(identifiers) do
		local costs

		if C_Spell and type(C_Spell.GetSpellPowerCost) == "function" then
			local ok, result = pcall(C_Spell.GetSpellPowerCost, identifier)
			if ok and type(result) == "table" then costs = result end
		elseif type(GetSpellPowerCost) == "function" then
			local ok, result = pcall(GetSpellPowerCost, identifier)
			if ok and type(result) == "table" then costs = result end
		end

		if costs then
			for _, info in ipairs(costs) do
				if type(info) == "table" then
					local powerType = ReadableNumber(info.type)
					local token = SafeValue(info.name) and info.name or nil

					if powerType == 0 or token == "MANA" then
						local cost =
							ReadableNumber(info.cost)
							or ReadableNumber(info.minCost)

						if cost and cost > 0 then return cost end

						local pct = ReadableNumber(info.costPercent)
						if pct and pct > 0 and trackedManaMax and trackedManaMax > 0 then
							return trackedManaMax * pct / 100
						end
					end
				end
			end
		end
	end

	return 0
end

local function SpendTrackedMana(spellName, capturedCost)
	if not EnsureTrackedMana() then return end
	UpdateTrackedManaRegen()

	local cost = capturedCost
	if cost == nil then cost = SpellManaCost(spellName) end
	trackedLastSpell = spellName
	trackedLastCost = cost or 0

	if cost and cost > 0 then
		trackedMana = math.max(0, trackedMana - cost)
		trackedLastSpendAt = GetTime()
		trackedManaUpdatedAt = trackedLastSpendAt
		trackedSource = "tracked spell costs"
	end
end

local function TrackedManaPercent()
	if not EnsureTrackedMana() then return nil end
	UpdateTrackedManaRegen()

	if trackedMana == nil or not trackedManaMax or trackedManaMax <= 0 then
		return nil
	end

	return math.max(0, math.min(100, trackedMana / trackedManaMax * 100))
end




local function PredictionHealthPercent()
	if type(CreateUnitHealPredictionCalculator) ~= "function"
		or type(UnitGetDetailedHealPrediction) ~= "function"
	then
		predictionHealthSource = "API unavailable"
		return nil
	end

	if not healthPredictionCalculator then
		local ok, calc = pcall(CreateUnitHealPredictionCalculator)
		if not ok or not calc then
			predictionHealthSource = "calculator create failed"
			return nil
		end
		healthPredictionCalculator = calc
	end

	local calc = healthPredictionCalculator

	if type(calc.SetToDefaults) == "function" then
		pcall(calc.SetToDefaults, calc)
	end

	local okFill = pcall(UnitGetDetailedHealPrediction, "player", "player", calc)
	if not okFill then
		predictionHealthSource = "UnitGetDetailedHealPrediction failed"
		return nil
	end

	if type(calc.HasSecretValues) == "function" then
		local ok, secret = pcall(calc.HasSecretValues, calc)
		if ok and type(secret) == "boolean" then
			predictionHealthHasSecrets = secret
		end
	end

	-- Preferred path: the calculator evaluates the current health percentage
	-- against Blizzard's ScaleTo100 curve.
	if type(calc.EvaluateCurrentHealthPercent) == "function"
		and CurveConstants
		and CurveConstants.ScaleTo100
	then
		local ok, value = pcall(
			calc.EvaluateCurrentHealthPercent,
			calc,
			CurveConstants.ScaleTo100
		)
		value = ok and ReadableNumber(value) or nil
		if value ~= nil then
			value = math.max(0, math.min(100, value))
			predictionHealthPct = value
			predictionHealthSource = "HealPrediction EvaluateCurrentHealthPercent"
			predictionHealthAt = GetTime()
			return value
		end
	end

	-- Secondary calculator percentage path.
	if type(calc.GetCurrentHealthPercent) == "function" then
		local ok, value = pcall(calc.GetCurrentHealthPercent, calc)
		value = ok and ReadableNumber(value) or nil
		if value ~= nil then
			if value >= 0 and value <= 1 then value = value * 100 end
			if value >= 0 and value <= 100 then
				predictionHealthPct = value
				predictionHealthSource = "HealPrediction GetCurrentHealthPercent"
				predictionHealthAt = GetTime()
				return value
			end
		end
	end

	-- Last calculator fallback: current/max.
	if type(calc.GetCurrentHealth) == "function"
		and type(calc.GetMaximumHealth) == "function"
	then
		local okC, current = pcall(calc.GetCurrentHealth, calc)
		local okM, maximum = pcall(calc.GetMaximumHealth, calc)
		current = okC and ReadableNumber(current) or nil
		maximum = okM and ReadableNumber(maximum) or nil

		if current ~= nil and maximum ~= nil and maximum > 0 then
			local value = math.max(0, math.min(100, current / maximum * 100))
			predictionHealthPct = value
			predictionHealthSource = "HealPrediction current/max"
			predictionHealthAt = GetTime()
			return value
		end
	end

	predictionHealthSource = predictionHealthHasSecrets
		and "HealPrediction values still secret"
		or "HealPrediction unreadable"
	return nil
end

local function HealthPercentFromStatusBar(bar, expectedMaximum)
	if not bar
		or type(bar.GetValue) ~= "function"
		or type(bar.GetMinMaxValues) ~= "function"
	then
		return nil
	end

	local okV, value = pcall(bar.GetValue, bar)
	local okR, minimum, maximum = pcall(bar.GetMinMaxValues, bar)
	if not okV or not okR then return nil end

	value = ReadableNumber(value)
	minimum = ReadableNumber(minimum)
	maximum = ReadableNumber(maximum)

	if value == nil or minimum == nil or maximum == nil or maximum <= minimum then
		return nil
	end

	-- If max health is known, reject other PlayerFrame bars such as mana.
	if type(expectedMaximum) == "number" and expectedMaximum > 0 then
		local barRange = maximum - minimum
		if math.abs(barRange - expectedMaximum) > math.max(1, expectedMaximum * 0.05) then
			return nil
		end
	end

	if value < minimum or value > maximum then return nil end
	return (value - minimum) / (maximum - minimum) * 100
end

local function AlivePlayer()
	if type(UnitIsDeadOrGhost) == "function" then
		local ok, dead = pcall(UnitIsDeadOrGhost, "player")
		if ok and not (issecretvalue and issecretvalue(dead)) then
			return not dead
		end
	end
	return true
end

local function ParseReadableHealthText(text, expectedMaximum)
	if type(text) ~= "string"
		or (issecretvalue and issecretvalue(text))
		or text == ""
	then
		return nil
	end

	-- Strip color/formatting noise and thousands separators.
	local clean = text:gsub("|c%x%x%x%x%x%x%x%x", "")
		:gsub("|r", "")
		:gsub(",", "")
		:gsub("%s+", " ")

	local current, maximum = clean:match("(%d+)%s*/%s*(%d+)")
	current = tonumber(current)
	maximum = tonumber(maximum)

	if current and maximum and maximum > 0 then
		if expectedMaximum and expectedMaximum > 0
			and math.abs(maximum - expectedMaximum) > math.max(1, expectedMaximum * 0.05)
		then
			return nil
		end

		local pct = current / maximum * 100
		if pct <= 0 and AlivePlayer() then return nil end
		if pct >= 0 and pct <= 100 then
			return pct, clean
		end
	end

	local pct = tonumber(clean:match("(%d+%.?%d*)%%"))
	if pct and pct >= 0 and pct <= 100 then
		if pct <= 0 and AlivePlayer() then return nil end
		return pct, clean
	end

	return nil
end

local function FindReadablePlayerHealthText()
	local frame = _G.PlayerFrame
	if not frame then
		frameHealthSource = "PlayerFrame unavailable"
		return nil
	end

	local hpMax
	if type(UnitHealthMax) == "function" then
		local ok, value = pcall(UnitHealthMax, "player")
		hpMax = ok and ReadableNumber(value) or nil
	end

	local visited = {}
	local scanned = 0

	local function Walk(region, depth)
		if not region or visited[region] or depth > 8 or scanned > 400 then
			return nil
		end
		visited[region] = true
		scanned = scanned + 1

		if type(region.GetText) == "function" then
			local ok, text = pcall(region.GetText, region)
			if ok and type(text) == "string"
				and not (issecretvalue and issecretvalue(text))
			then
				local pct, parsed = ParseReadableHealthText(text, hpMax)
				if pct ~= nil then
					return pct, parsed
				end
			end
		end

		if type(region.GetRegions) == "function" then
			local ok, regions = pcall(function() return { region:GetRegions() } end)
			if ok then
				for _, child in ipairs(regions) do
					local pct, parsed = Walk(child, depth + 1)
					if pct ~= nil then return pct, parsed end
				end
			end
		end

		if type(region.GetChildren) == "function" then
			local ok, children = pcall(function() return { region:GetChildren() } end)
			if ok then
				for _, child in ipairs(children) do
					local pct, parsed = Walk(child, depth + 1)
					if pct ~= nil then return pct, parsed end
				end
			end
		end
	end

	local pct, parsed = Walk(frame, 0)
	if pct ~= nil then
		frameHealthPct = pct
		frameHealthText = parsed
		frameHealthSource = "PlayerFrame visible health text"
		frameHealthAt = GetTime()
		return pct
	end

	frameHealthPct = nil
	frameHealthText = nil
	frameHealthSource = "no readable PlayerFrame health text"
	return nil
end

local function FindReadablePlayerHealthBar()
	-- Only trust explicit Blizzard health-bar paths. Do NOT recursively scan
	-- arbitrary StatusBars: v0.25.6 matched a non-health bar at 0% and caused
	-- an endless healing loop.
	local hpMax
	if type(UnitHealthMax) == "function" then
		local ok, value = pcall(UnitHealthMax, "player")
		hpMax = ok and ReadableNumber(value) or nil
	end

	local frame = _G.PlayerFrame
	local content = frame and frame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local area = main and main.HealthBarArea

	local candidates = {
		_G.PlayerFrameHealthBar,
		area and area.HealthBar,
		frame and frame.healthbar,
		frame and frame.healthBar,
		frame and frame.HealthBar,
	}

	for _, bar in ipairs(candidates) do
		local pct = HealthPercentFromStatusBar(bar, hpMax)
		if pct ~= nil then
			-- A living character cannot have real 0% health. Reject poisoned
			--/placeholder status bars instead of caching them.
			if pct > 0 or not AlivePlayer() then
				frameHealthPct = pct
				frameHealthText = nil
				frameHealthSource = "known PlayerFrame health bar"
				frameHealthAt = GetTime()
				return pct
			end
		end
	end

	-- Safer fallback: visible text, not arbitrary StatusBars.
	return FindReadablePlayerHealthText()
end

local function ReadCurrentHealthPercent()
	-- 1) New Forever-safe heal prediction calculator.
	local pct = PredictionHealthPercent()
	if pct ~= nil then
		return pct, predictionHealthSource
	end

	-- 2) Visible PlayerFrame health bar. This is presentation state, not a raw
	-- UnitHealth arithmetic dependency.
	pct = FindReadablePlayerHealthBar()
	if pct ~= nil then
		return pct, frameHealthSource
	end

	-- 3) Raw percent APIs if they happen to be readable.
	if type(UnitHealthPercent) == "function" then
		if CurveConstants and CurveConstants.ScaleTo100 then
			for _, predicted in ipairs({ false, true }) do
				local ok, value = pcall(
					UnitHealthPercent,
					"player",
					predicted,
					CurveConstants.ScaleTo100
				)
				value = ok and ReadableNumber(value) or nil
				if value ~= nil then
					return math.max(0, math.min(100, value)),
						"UnitHealthPercent predicted=" .. tostring(predicted)
				end
			end
		end

		local ok, value = pcall(UnitHealthPercent, "player")
		value = ok and ReadableNumber(value) or nil
		if value ~= nil then
			if value >= 0 and value <= 1 then value = value * 100 end
			return math.max(0, math.min(100, value)), "UnitHealthPercent simple"
		end
	end

	-- 4) Raw current/max.
	if type(UnitHealth) == "function" and type(UnitHealthMax) == "function" then
		for _, predicted in ipairs({ false, true }) do
			local okH, hp = pcall(UnitHealth, "player", predicted)
			local okM, hpMax = pcall(UnitHealthMax, "player")
			hp = okH and ReadableNumber(hp) or nil
			hpMax = okM and ReadableNumber(hpMax) or nil

			if hp ~= nil and hpMax ~= nil and hpMax > 0 then
				return math.max(0, math.min(100, hp / hpMax * 100)),
					"UnitHealth/Max predicted=" .. tostring(predicted)
			end
		end
	end
end

local function ReadCurrentManaPercent()
	local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

	if type(UnitPowerPercent) == "function" and CurveConstants and CurveConstants.ScaleTo100 then
		local ok, pct = pcall(
			UnitPowerPercent,
			"player",
			powerType,
			false,
			CurveConstants.ScaleTo100
		)
		pct = ok and ReadableNumber(pct) or nil
		if pct ~= nil then
			return math.max(0, math.min(100, pct)), "UNIT_POWER UnitPowerPercent"
		end
	end

	if type(UnitPower) == "function" and type(UnitPowerMax) == "function" then
		local okC, current = pcall(UnitPower, "player", powerType)
		local okM, maximum = pcall(UnitPowerMax, "player", powerType)
		current = okC and ReadableNumber(current) or nil
		maximum = okM and ReadableNumber(maximum) or nil

		if current ~= nil and maximum ~= nil and maximum > 0 then
			return math.max(0, math.min(100, current / maximum * 100)),
				"UNIT_POWER UnitPower/Max"
		end
	end
end

local function RefreshHealthSensor()
	healthEventCount = healthEventCount + 1

	local pct, source = ReadCurrentHealthPercent()
	if pct ~= nil and (pct > 0 or not AlivePlayer()) then
		eventHealthPct = pct
		eventHealthSource = source or "event health"
		eventHealthAt = GetTime()

		local maximum = ReadableNumber(UnitHealthMax and UnitHealthMax("player"))
		if maximum and maximum > 0 then
			trackedHealthMax = maximum
			trackedHealth = maximum * pct / 100
			trackedHealthSource = "event health resync"
			trackedHealthAt = GetTime()
		end
	end
end

local function RefreshManaSensor()
	manaEventCount = manaEventCount + 1

	local pct, source = ReadCurrentManaPercent()
	if pct ~= nil then
		eventManaPct = pct
		eventManaSource = source or "event mana"
		eventManaAt = GetTime()

		if EnsureTrackedMana() and trackedManaMax then
			trackedMana = trackedManaMax * pct / 100
			trackedManaUpdatedAt = GetTime()
			trackedSource = "event mana resync"
		end
	end
end

local function EnsureTrackedHealth()
	local maximum
	if type(UnitHealthMax) == "function" then
		local ok, value = pcall(UnitHealthMax, "player")
		maximum = ok and ReadableNumber(value) or nil
	end

	if maximum and maximum > 0 then
		if not trackedHealthMax or trackedHealthMax ~= maximum then
			if trackedHealth and trackedHealthMax and trackedHealthMax > 0 then
				local pct = trackedHealth / trackedHealthMax
				trackedHealth = maximum * pct
			end
			trackedHealthMax = maximum
		end
	end

	if not trackedHealthMax or trackedHealthMax <= 0 then return false end

	if trackedHealth == nil then
		trackedHealth = trackedHealthMax
		trackedHealthSource = "max-initialized"
		trackedHealthAt = GetTime()
	end

	return true
end

local function ApplyTrackedHealthDelta(delta, eventName, amount)
	if not EnsureTrackedHealth() then return end
	if type(delta) ~= "number" then return end

	trackedHealth = math.max(
		0,
		math.min(trackedHealthMax, trackedHealth + delta)
	)
	trackedHealthSource = "combat-log tracked"
	trackedHealthLastEvent = eventName
	trackedHealthLastAmount = amount
	trackedHealthAt = GetTime()
	combatHealthEventCount = combatHealthEventCount + 1
end

local function TrackCombatLogHealth()
	if type(CombatLogGetCurrentEventInfo) ~= "function" then return end

	local ok, timestamp, subevent, hideCaster,
		sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
		destGUID, destName, destFlags, destRaidFlags,
		a12, a13, a14, a15, a16 = pcall(CombatLogGetCurrentEventInfo)

	if not ok or not SafeValue(subevent) then return end

	-- Prefer combat-log affiliation flags. GUIDs can themselves be secret on
	-- Forever, which previously caused every player damage/heal event to be
	-- discarded before we ever looked at the amount.
	local isPlayerDest = false
	if type(destFlags) == "number"
		and not (issecretvalue and issecretvalue(destFlags))
		and bit and bit.band
		and COMBATLOG_OBJECT_AFFILIATION_MINE
	then
		isPlayerDest = bit.band(destFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0
	end

	if not isPlayerDest and SafeValue(destGUID) then
		local okGuid, playerGUID = pcall(UnitGUID, "player")
		if okGuid and SafeValue(playerGUID) and playerGUID == destGUID then
			isPlayerDest = true
		end
	end

	if not isPlayerDest then return end

	local amount
	local delta

	if subevent == "SWING_DAMAGE" then
		amount = ReadableNumber(a12)
		if amount then delta = -amount end

	elseif subevent == "ENVIRONMENTAL_DAMAGE" then
		amount = ReadableNumber(a13)
		if amount then delta = -amount end

	elseif subevent == "SPELL_DAMAGE"
		or subevent == "SPELL_PERIODIC_DAMAGE"
		or subevent == "RANGE_DAMAGE"
		or subevent == "DAMAGE_SHIELD"
		or subevent == "DAMAGE_SPLIT"
	then
		amount = ReadableNumber(a15)
		if amount then delta = -amount end

	elseif subevent == "SPELL_HEAL"
		or subevent == "SPELL_PERIODIC_HEAL"
	then
		amount = ReadableNumber(a15)
		local overheal = ReadableNumber(a16) or 0
		if amount then
			delta = math.max(0, amount - overheal)
		end

	elseif subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
		if EnsureTrackedHealth() then
			trackedHealth = 0
			trackedHealthSource = "combat-log death"
			trackedHealthLastEvent = subevent
			trackedHealthLastAmount = 0
			trackedHealthAt = GetTime()
			combatHealthEventCount = combatHealthEventCount + 1
		end
		return
	end

	if delta then
		ApplyTrackedHealthDelta(delta, subevent, amount)
	end
end

local function TrackedHealthPercent()
	if not EnsureTrackedHealth() then return nil end
	if trackedHealthSource == "max-initialized" then
		return nil
	end
	if not trackedHealth or not trackedHealthMax or trackedHealthMax <= 0 then return nil end

	local pct = math.max(0, math.min(100, trackedHealth / trackedHealthMax * 100))
	if pct <= 0 and AlivePlayer()
		and trackedHealthSource == "event health resync"
	then
		return nil
	end
	return pct
end

tracker:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
	if event == "START_AUTOREPEAT_SPELL" then
		wandEventActive = true
		return
	end

	if event == "STOP_AUTOREPEAT_SPELL" then
		wandEventActive = false
		return
	end

	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		TrackCombatLogHealth()
		return
	end

	if event == "PLAYER_REGEN_DISABLED" then
		EnsureTrackedMana()
		EnsureTrackedHealth()
		trackedManaUpdatedAt = GetTime()
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		UpdateTrackedManaRegen()
		RefreshHealthSensor()
		RefreshManaSensor()
		return
	end

	if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
		shieldLockUntil = 0
		renewLockUntil = 0
		divineSpiritUntil, divineSpiritAppliedAt = 0, 0
		wandEventActive = false

		trackedMana = nil
		trackedManaMax = nil
		trackedManaUpdatedAt = nil
		trackedLastSpendAt = nil
		trackedLastSpell = nil
		trackedLastCost = 0
		trackedSource = "uninitialized"

		eventHealthPct = nil
		eventHealthSource = "unreadable"
		eventHealthAt = nil
		eventManaPct = nil
		eventManaSource = "unreadable"
		eventManaAt = nil

		trackedHealth = nil
		trackedHealthMax = nil
		trackedHealthSource = "uninitialized"
		trackedHealthLastEvent = nil
		trackedHealthLastAmount = nil
		trackedHealthAt = nil

		lastSentCastName = nil
		lastSentCastAt = 0

		EnsureTrackedMana()
		EnsureTrackedHealth()
		RefreshHealthSensor()
		RefreshManaSensor()
		return
	end

	if unit ~= "player" then return end
	if AL.S().shadow == true and (event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED"
		or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED") then return end

	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		RefreshHealthSensor()
		return
	end

	if event == "UNIT_POWER_UPDATE"
		or event == "UNIT_POWER_FREQUENT"
		or event == "UNIT_MAXPOWER"
	then
		-- Ignore non-mana power updates when the token is readable.
		if type(arg2) == "string"
			and SafeValue(arg2)
			and arg2 ~= "MANA"
		then
			return
		end

		RefreshManaSensor()
		return
	end

	if event == "UNIT_SPELLCAST_SENT" then
		local spellName = CastName(arg2, arg3, arg4)
		if TouchSentSpell(arg2, arg3, arg4) then spellName = TOUCH end
		if not (SafeValue(arg4) and type(arg4) == "number")
			and not (SafeValue(arg3) and type(arg3) == "number")
			and (not spellName or not (AL.known and AL.known[spellName]))
			and AL.lastSuggestion == DIVINE_SPIRIT and Ok(DIVINE_SPIRIT) then spellName = DIVINE_SPIRIT end
		if spellName then
			lastSentCastName = spellName
			lastSentCastAt = GetTime()
			castSentCount = castSentCount + 1
		end
		return
	end

	if event == "UNIT_SPELLCAST_FAILED"
		or event == "UNIT_SPELLCAST_INTERRUPTED"
	then
		lastSentCastName = nil
		lastSentCastAt = 0
		return
	end

	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
	-- The automatic damage/debuff proc is not another paid self-buff cast.
	if TouchSpellID(arg3, TOUCH_PROC_IDS) or TouchSpellID(arg4, TOUCH_PROC_IDS) then return end

	castSucceededCount = castSucceededCount + 1

	local spellName = CastName(arg2, arg3, arg4)

	-- Forever can secretize the SUCCEEDED spell payload. Core already solves
	-- this by remembering UNIT_SPELLCAST_SENT; Priest now does the same.
	if not spellName
		and lastSentCastName
		and (GetTime() - lastSentCastAt) < 5
	then
		spellName = lastSentCastName
		castFallbackCount = castFallbackCount + 1
	end

	lastSentCastName = nil
	lastSentCastAt = 0
	lastSucceededCastName = spellName

	if not spellName then return end
	-- Penance's confirmed channel/cast is charged once by its own observer.
	if spellName == PENANCE then return end

	SpendTrackedMana(spellName)

	if spellName == "Power Word: Shield" then
		shieldLockUntil = GetTime() + 15
	elseif spellName == "Renew" then
		renewLockUntil = GetTime() + 15
	elseif spellName == DIVINE_SPIRIT then
		divineSpiritUntil, divineSpiritAppliedAt = GetTime() + 3600, GetTime()
	end
end)

local function SettingNumber(s, key, defaultValue, minValue, maxValue)
	local value = tonumber(s and s[key])
	if value == nil then value = defaultValue end
	value = math.floor(value + 0.5)
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

-- Combat-safe player health percentage. Forever can secretize raw
-- UnitHealth/UnitHealthMax in combat while still exposing UnitHealthPercent.
-- Exact combat-safe health reader used by the working Rogue rotation.
local function PlayerHealthPercent()
	-- 1) Best source: a readable health sample captured on UNIT_HEALTH.
	if type(eventHealthPct) == "number" then
		if eventHealthPct > 0 or not AlivePlayer() then
			return eventHealthPct
		end
		-- Poisoned zero from an older frame scan: discard it.
		eventHealthPct = nil
		eventHealthSource = "discarded impossible 0%"
		eventHealthAt = nil
	end

	-- 2) Try a direct read now.
	local pct, source = ReadCurrentHealthPercent()
	if type(pct) == "number" and (pct > 0 or not AlivePlayer()) then
		eventHealthPct = pct
		eventHealthSource = source or "direct health"
		eventHealthAt = GetTime()
		return pct
	end

	-- 3) When current health is protected, use our combat-log estimate.
	pct = TrackedHealthPercent()
	if type(pct) == "number" then
		return pct
	end

	-- 4) Existing Core fallback.
	if type(AL.HealthPercent) == "function" then
		local ok, value = pcall(AL.HealthPercent, "player")
		value = ok and ReadableNumber(value) or nil
		if value ~= nil then return value end
	end

	return nil
end

-- Safe visible-mana status-bar reader used by GateManaPercent().
local function ManaFromStatusBar(bar)
	if not bar
		or type(bar.GetValue) ~= "function"
		or type(bar.GetMinMaxValues) ~= "function"
	then
		return nil
	end

	local okValue, value = pcall(bar.GetValue, bar)
	local okRange, minimum, maximum = pcall(bar.GetMinMaxValues, bar)
	if not okValue or not okRange then return nil end

	value = ReadableNumber(value)
	minimum = ReadableNumber(minimum)
	maximum = ReadableNumber(maximum)

	if value == nil or minimum == nil or maximum == nil or maximum <= minimum then
		return nil
	end

	if value < minimum or value > maximum then return nil end
	return (value - minimum) / (maximum - minimum) * 100
end

-- Count hostile nameplates that currently have the player on their threat table.
-- This is the same combat-safe signal used by the Rogue emergency logic.
local NAMEPLATE_UNITS = {}
for i = 1, 40 do
	NAMEPLATE_UNITS[i] = "nameplate" .. i
end

local engagedEnemyCount = 0
local engagedEnemyCountAt = -1

local function EngagedEnemies()
	local now = GetTime()
	if now - engagedEnemyCountAt < 0.20 then
		return engagedEnemyCount
	end

	local count = 0

	if UnitThreatSituation then
		for i = 1, #NAMEPLATE_UNITS do
			local unit = NAMEPLATE_UNITS[i]

			local okExists, exists = pcall(UnitExists, unit)
			if okExists and SafeValue(exists) and exists then
				local okAttack, canAttack = pcall(UnitCanAttack, "player", unit)
				if okAttack and SafeValue(canAttack) and canAttack then
					local okThreat, threat = pcall(UnitThreatSituation, "player", unit)

					-- nil means the player is not on this enemy's threat table.
					-- 0-3 are valid threat states.
					if okThreat and SafeValue(threat) and threat ~= nil then
						count = count + 1
						-- Fade only cares whether there is more than one.
						if count >= 2 then break end
					end
				end
			end
		end
	end

	engagedEnemyCount = count
	engagedEnemyCountAt = now
	return count
end

local function Role(s)
    if s and SafeValue(s.shadow) and s.shadow == true then return "SHADOW" end
    if AL.DPS60 and AL.DPS60.Active() then
        return AL.DPS60.Build("PRIEST", s, s.priestRole == "SMITE" and "SMITE" or "SHADOW")
    end
	return s and s.priestRole == "SMITE" and "SMITE" or "SHADOW"
end

local function ManaAtLeast(mana, threshold)
	return mana == nil or (type(mana) == "number" and mana >= threshold)
end

local function TargetWorthAtLeast(targetHP, threshold)
	return targetHP == nil or (type(targetHP) == "number" and targetHP >= threshold)
end

local function ReadyUsable(name)
	return Ok(name) and AL.IsReady(name) and AL.SpellUsable(name)
end

local HEALING_SPELL_IDS = {
	["Renew"] = 139,
	["Heal"] = 2054,
	["Lesser Heal"] = 2050,
	["Desperate Prayer"] = 13908,
}

local function HealingKnown(name)
	-- First trust ActionLITE's spellbook scan.
	if AL.known and AL.known[name] then
		return true
	end

	-- Secondary direct spell-known check when the client provides one.
	local spellID = HEALING_SPELL_IDS[name]
	if spellID and type(IsSpellKnown) == "function" then
		local ok, known = pcall(IsSpellKnown, spellID)
		if ok and SafeValue(known) and known then
			return true
		end
	end

	-- Final fallback to the normal Priest gate.
	return Ok(name) and true or false
end

local function PlayerMoving()
	if type(GetUnitSpeed) ~= "function" then return false end
	local ok, speed = pcall(GetUnitSpeed, "player")
	if not ok or not SafeValue(speed) or type(speed) ~= "number" then return false end
	return speed > 0
end


-- Priest low-mana wand mode.
--
-- This now mirrors the WORKING Warlock implementation structurally:
--   * read AL.ManaPercent() directly
--   * remember the last REAL numeric sample
--   * latch the low-mana Shoot state from that sample
--   * when the current read becomes nil/secret, keep evaluating the slider
--     against the last readable sample instead of inventing a new percentage
local shootModeActive = false
local lastReadableManaPct = nil
local lastManaSource = "unreadable"

local function CoreManaPercent()
	if type(AL.ManaPercent) ~= "function" then
		lastManaSource = lastReadableManaPct ~= nil and "cached" or "unreadable"
		return nil
	end

	local ok, value = pcall(AL.ManaPercent)
	if not ok
		or type(value) ~= "number"
		or (issecretvalue and issecretvalue(value))
	then
		lastManaSource = lastReadableManaPct ~= nil and "cached" or "unreadable"
		return nil
	end

	lastReadableManaPct = value
	lastManaSource = "Core"
	return value
end

local function LowManaShootMode(s, manaPct)
	local threshold = SettingNumber(s, "wandMana", 25, 0, 100)

	if type(manaPct) == "number" then
		lastReadableManaPct = manaPct
		shootModeActive = manaPct <= threshold
		lastManaSource = "Core"
	elseif type(lastReadableManaPct) == "number" then
		-- Exact Warlock behavior: if the live read disappears, re-evaluate the
		-- last real sample against the CURRENT slider value.
		shootModeActive = lastReadableManaPct <= threshold
		lastManaSource = "cached"
	else
		shootModeActive = false
		lastManaSource = "unreadable"
	end

	return shootModeActive, lastReadableManaPct, threshold
end

local function GroupSize()
	-- Raids are not part of the leveling proximity-shield rule.
	if type(IsInRaid) == "function" then
		local ok, inRaid = pcall(IsInRaid)
		if ok and SafeValue(inRaid) and inRaid then
			if type(GetNumGroupMembers) == "function" then
				local okCount, count = pcall(GetNumGroupMembers)
				if okCount and SafeValue(count) and type(count) == "number" then
					return count
				end
			end
			return 5
		end
	end

	if type(GetNumGroupMembers) == "function" then
		local ok, count = pcall(GetNumGroupMembers)
		if ok and SafeValue(count) and type(count) == "number" then
			if count <= 0 then return 1 end
			return count
		end
	end

	if type(GetNumPartyMembers) == "function" then
		local ok, count = pcall(GetNumPartyMembers)
		if ok and SafeValue(count) and type(count) == "number" then
			return count + 1
		end
	end

	return 1
end

local function LevelingShieldGroupAllowed()
	return GroupSize() < 5
end

local function TargetWithin10Yards()
	if not UnitExists("target") then return false end

	if type(UnitDistanceSquared) == "function" then
		local ok, distanceSquared = pcall(UnitDistanceSquared, "target")
		if ok and SafeValue(distanceSquared) and type(distanceSquared) == "number" then
			return distanceSquared <= 100
		end
	end

	if type(UnitPosition) == "function" then
		local okPlayer, px, py, pz, pInstance = pcall(UnitPosition, "player")
		local okTarget, tx, ty, tz, tInstance = pcall(UnitPosition, "target")
		if okPlayer and okTarget
			and type(px) == "number" and type(py) == "number"
			and type(tx) == "number" and type(ty) == "number"
			and SafeValue(px) and SafeValue(py) and SafeValue(tx) and SafeValue(ty)
			and (not pInstance or not tInstance or pInstance == tInstance)
		then
			local dx, dy = tx - px, ty - py
			return (dx * dx + dy * dy) <= 100
		end
	end

	-- Classic interaction index 3 is approximately 10 yards. Only a readable
	-- true result is used; false/unknown does not guess that the target is close.
	if type(CheckInteractDistance) == "function" then
		local ok, close = pcall(CheckInteractDistance, "target", 3)
		if ok and SafeValue(close) and close then return true end
	end

	-- Conservative last fallback: melee range is definitely inside 10 yards.
	if type(AL.TargetInMelee) == "function" then
		local ok, melee = pcall(AL.TargetInMelee)
		if ok and melee then return true end
	end

	return false
end

local function PlayerIsWanding()
	local player = A and type(A.Player) == "table" and A.Player or nil
	if player and type(player.IsShooting) == "function" then
		local ok, active = pcall(player.IsShooting, player)
		if ok and SafeValue(active) and type(active) == "boolean" then return active end
	end
	if type(IsCurrentSpell) == "function" then
		local ok, active = pcall(IsCurrentSpell, 5019)
		if ok and SafeValue(active) and active then return true end
	end
	return wandEventActive
end

local function WandEquipped()
	local ok, equipped = pcall(AL.WandEquipped)
	return ok and equipped and true or false
end

local function Wand(s, reason)
	-- Priest wand use is automatic whenever a wand is physically equipped.
	-- There is no separate enable/disable flag that can silently bypass the
	-- mana slider.
	if not WandEquipped() then return nil end
	return "Shoot", reason or "save mana"
end

local function LivePriestProfile(s)
	if type(AL.Profile) == "function" then
		local ok, profile = pcall(AL.Profile, "PRIEST")
		if ok and type(profile) == "table" then
			return profile
		end
	end
	return s
end

local function WandManaThreshold(s)
	-- `s` is the live rotation profile passed directly into NextSpell().
	-- Your runtime dump confirmed this table contains the actual slider value.
	return SettingNumber(s, "wandMana", 25, 0, 100)
end

local function MindBlastManaThreshold(s)
	-- Same rule as Smite: read the live table directly, never a second profile lookup.
	return SettingNumber(s, "mindBlastMana", 50, 0, 100)
end

local function GateManaPercent()
	-- ONE conservative mana value per rotation pass.
	--
	-- Important: do NOT let a stale/high source re-enable Smite or Mind Blast.
	-- We collect every readable current/tracked source and use the LOWEST value.
	-- This means a real low mana source always wins over a stale high one.
	local best = nil
	local bestSource = nil

	local function consider(value, source)
		value = ReadableNumber(value)
		if value == nil or value < 0 or value > 100 then return end
		if best == nil or value < best then
			best = value
			bestSource = source
		end
	end

	-- A) Event-cached current mana, when Forever exposes it on UNIT_POWER.
	consider(eventManaPct, eventManaSource or "event mana")

	-- B) Proven tracked-mana model.
	consider(TrackedManaPercent(), "tracked")

	-- B) Visible player mana bar.
	consider(ManaFromStatusBar(_G.PlayerFrameManaBar), "player bar")

	local frame = _G.PlayerFrame
	local content = frame and frame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local area = main and main.ManaBarArea
	local nestedBar = area and area.ManaBar
	consider(ManaFromStatusBar(nestedBar), "player bar")

	-- C) Forever's normalized power API. This source is never allowed to
	-- override a lower tracked/UI value.
	if type(UnitPowerPercent) == "function"
		and CurveConstants
		and CurveConstants.ScaleTo100
	then
		local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
		local ok, value = pcall(
			UnitPowerPercent,
			"player",
			powerType,
			false,
			CurveConstants.ScaleTo100
		)
		if ok then consider(value, "UnitPowerPercent") end
	end

	-- D) Raw current/max if the client exposes them.
	if type(UnitPower) == "function" and type(UnitPowerMax) == "function" then
		local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
		local okCurrent, current = pcall(UnitPower, "player", powerType)
		local okMaximum, maximum = pcall(UnitPowerMax, "player", powerType)
		current = okCurrent and ReadableNumber(current) or nil
		maximum = okMaximum and ReadableNumber(maximum) or nil
		if current ~= nil and maximum ~= nil and maximum > 0 then
			consider(current / maximum * 100, "UnitPower")
		end
	end

	if best ~= nil then
		lastReadableManaPct = best
		lastManaSource = bestSource or "gate"
		return best
	end

	-- If this frame is protected, keep the last conservative value rather than
	-- inventing a fresh high percentage.
	if type(lastReadableManaPct) == "number" then
		lastManaSource = "cached gate"
		return lastReadableManaPct
	end

	lastManaSource = "unreadable"
	return nil
end

local function SmiteShouldWand(s, mana)
	local threshold = WandManaThreshold(s)

	-- Exact semantics:
	--   mana <= slider -> Smite is blocked
	--   mana > slider  -> Smite may be used
	--   unreadable     -> fail closed and block Smite
	if type(mana) ~= "number" then
		return true, threshold, "Smite mana unavailable"
	end

	if mana <= threshold then
		return true, threshold,
			"Shoot instead of Smite: "
				.. tostring(math.floor(mana + 0.5))
				.. "% <= " .. tostring(threshold) .. "%"
	end

	return false, threshold
end

local mindBlastShootModeActive = false
local lastMindBlastManaPct = nil

local function MindBlastLowManaMode(s, mana)
	local threshold = MindBlastManaThreshold(s)

	if type(mana) == "number" then
		lastMindBlastManaPct = mana
		mindBlastShootModeActive = mana <= threshold
	elseif type(lastMindBlastManaPct) == "number" then
		mindBlastShootModeActive = lastMindBlastManaPct <= threshold
	else
		mindBlastShootModeActive = true
	end

	return mindBlastShootModeActive, lastMindBlastManaPct, threshold
end

local function ResolveFiller(s, filler, mana, reason)
	if not filler then return nil end

	if filler == "Smite" then
		local shouldWand, threshold, wandReason = SmiteShouldWand(s, mana)
		if shouldWand then
			local wand, why = Wand(
				s,
				wandReason or ("Smite blocked at " .. tostring(threshold) .. "% mana")
			)
			if wand then return wand, why end
			return nil, "Smite blocked by wand mana"
		end
	end

	if AL.SpellUsable(filler) then
		return filler, reason or "filler"
	end

	local wand, wandReason = Wand(s, "filler unavailable")
	if wand then return wand, wandReason end
	return nil, "Out of mana"
end

local function ResolveMindBlast(s, role, mana, reason)
	if role ~= "SHADOW" or not s.mindBlast then return nil end

	local lowMana, decisionMana, threshold = MindBlastLowManaMode(s, mana)

	-- Absolute interlock: the wand check only decides the replacement action.
	-- It can never re-enable Mind Blast.
	if lowMana then
		local reasonText
		if type(decisionMana) == "number" then
			reasonText =
				"Shoot instead of Mind Blast: "
					.. tostring(math.floor(decisionMana + 0.5))
					.. "% <= " .. tostring(threshold) .. "%"
		else
			reasonText = "Mind Blast mana unavailable"
		end

		local wand, why = Wand(s, reasonText)
		if wand then return wand, why end

		-- If wand detection fails, still do not permit Mind Blast.
		return nil, "Mind Blast blocked by mana gate"
	end

	if ReadyUsable("Mind Blast") then
		return "Mind Blast", reason or "on cooldown"
	end

	return nil
end

local function RealShieldActive()
	-- IMPORTANT:
	-- AL.HasBuff() falls back to a cast-inferred 30-second Shield timer when
	-- Forever hides player auras in combat. That fallback is too conservative
	-- for leveling because an absorbed Shield may be gone long before 30 sec.
	--
	-- Only let a REAL readable player-buff snapshot block the re-shield.
	if type(AL.DebugState) == "function" then
		local ok, state = pcall(AL.DebugState)
		if ok and type(state) == "table" and state.tooltipValid then
			return state.tooltipBuffs
				and state.tooltipBuffs["Power Word: Shield"] == true
		end
	end

	-- Aura state is unreadable. Do NOT trust the 30-second inferred Shield
	-- timer here; the 15-second Weakened Soul lock below is the authority.
	return false
end

local function HasWeakenedSoul()
	if type(AL.DebugState) == "function" then
		local ok, state = pcall(AL.DebugState)
		if ok and type(state) == "table" then
			-- 1) Real readable player-debuff snapshot is authoritative.
			if state.playerDebuffValid then
				return state.tooltipPlayerDebuffs
					and state.tooltipPlayerDebuffs["Weakened Soul"] == true
			end

			-- 2) If Forever hid the player aura, Core already maintains a
			-- 15-second inferred Weakened Soul state from the successful Shield
			-- cast. Use that before falling back to Priest's own timer.
			local inferred = state.playerDebuffs
				and state.playerDebuffs["Weakened Soul"]
			if type(inferred) == "table" then
				local expires = tonumber(inferred.expires)
				if not expires or expires > GetTime() then return true end
			elseif inferred then
				return true
			end
		end
	end

	-- 3) Final fallback if Core could not expose either state.
	return GetTime() < shieldLockUntil
end

local function ShieldReady()
	if not ReadyUsable("Power Word: Shield") then return false end
	if HasWeakenedSoul() then return false end
	if RealShieldActive() then return false end
	return true
end

local function MaintainCombatShield(s, inCombat)
	if not s.shield or not inCombat then return nil end
	if not ShieldReady() then return nil end
	return "Power Word: Shield", "maintain shield"
end

local function DirectHeal()
	if HealingKnown("Heal") then return "Heal" end
	if HealingKnown("Lesser Heal") then return "Lesser Heal" end
end

-- Original Priest filler selectors.
-- These were accidentally dropped during the healing/mana gate rebuild,
-- which caused the nil-function crash after Mind Blast was gated out.
local function ShadowFiller()
	if Ok("Mind Flay") then return "Mind Flay" end
	return Ok("Smite") and "Smite" or nil
end

local function SmiteFiller()
	if Ok("Smite") then return "Smite" end
	return Ok("Mind Flay") and "Mind Flay" or nil
end

-- Forward declaration is required because Preparation() calls the
-- healing decision function before its implementation appears below.
local PrioritySelfHealing

-- OUT-OF-COMBAT TOP PRIORITY TIER.
-- Lesser Heal is checked before Fortitude/Inner Fire.
local function TrackedPlayerBuffActive(name, expires, appliedAt, duration)
	local now = GetTime()
	local ok, state = pcall(AL.DebugState)
	if ok and SafeValue(state) and type(state) == "table"
		and SafeValue(state.tooltipValid) and state.tooltipValid == true then
		local buffs = state.tooltipBuffs
		local present = SafeValue(buffs) and type(buffs) == "table" and buffs[name]
		if SafeValue(present) then
			if present == true then
				if expires <= now then expires = now + duration end
				return true, expires
			end
			if expires > now and now - appliedAt < 0.5 then return true, expires end
			return false, 0
		end
	end
	local activeOK, active = pcall(AL.HasBuff, "player", name)
	if activeOK and SafeValue(active) and active == true then return true, expires end
	return expires > now, expires
end

local function DivineSpiritActive()
	local active
	active, divineSpiritUntil = TrackedPlayerBuffActive(DIVINE_SPIRIT, divineSpiritUntil, divineSpiritAppliedAt, 3600)
	return active
end

local function SpellAffordable(name)
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	local id = type(ref) == "table" and ReadableNumber(ref.id) or name
	local reader = IsUsableSpell or C_Spell and C_Spell.IsSpellUsable
	if type(reader) == "function" then
		local usableOK, usable, shortage = pcall(reader, id)
		if usableOK and (SafeValue(usable) and usable == false
			or SafeValue(shortage) and shortage == true) then return false end
	end
	local ok, cost = pcall(SpellManaCost, name)
	cost = ok and ReadableNumber(cost)
	if not cost or cost <= 0 then return true end
	local powerOK, amount = pcall(UnitPower, "player", 0)
	amount = powerOK and ReadableNumber(amount)
	if amount then return amount >= cost end
	local mana, maximum = GateManaPercent(), ReadManaMaximum()
	return type(mana) ~= "number" or not maximum or mana * maximum / 100 >= cost
end

local function Preparation(s, playerHP)
	-- Healing owns the top OOC priority tier.
	local heal, healReason = PrioritySelfHealing(s, false, playerHP)
	if heal then return heal, healReason end

	if not s.buffs then return nil end

	if Ok("Power Word: Fortitude")
		and not AL.HasBuff("player", "Power Word: Fortitude")
		and AL.SpellUsable("Power Word: Fortitude")
	then
		return "Power Word: Fortitude", "buff"
	end

	if s.divineSpirit and ReadyUsable(DIVINE_SPIRIT)
		and not DivineSpiritActive() and SpellAffordable(DIVINE_SPIRIT) then
		return DIVINE_SPIRIT, "buff"
	end

	if s.innerfire
		and Ok("Inner Fire")
		and not AL.HasBuff("player", "Inner Fire")
		and AL.SpellUsable("Inner Fire")
	then
		return "Inner Fire", "buff"
	end

	return nil
end

local function RenewAuraState()
	-- A readable Core tooltip sweep is authoritative for the REAL Renew aura.
	if type(AL.DebugState) == "function" then
		local ok, state = pcall(AL.DebugState)
		if ok and type(state) == "table" and state.tooltipValid then
			local active = state.tooltipBuffs
				and state.tooltipBuffs["Renew"] == true
				or false
			return active, active and "real aura present" or "real aura absent"
		end
	end

	-- If the live aura sweep is protected, only use a short lock after a
	-- positively observed successful Renew cast. Otherwise treat Renew as absent
	-- so healing is never silently suppressed.
	if GetTime() < renewLockUntil then
		return true, "successful Renew cast lock"
	end

	return false, "aura unreadable / no successful cast lock"
end

local function RenewActive()
	local active = RenewAuraState()
	return active
end

-- EXACT SELF-HEAL RULES:
--   Renew:
--     * in OR out of combat
--     * HP < 80%
--     * Renew aura/buff NOT present
--
--   Lesser Heal:
--     * in combat: HP < 60%
--     * out of combat: HP < 80% AND Renew aura/buff IS present
--
-- Renew is evaluated first, so at low HP with no Renew:
--   pass 1 -> Renew
--   next pass after successful Renew -> Lesser Heal when its rule is met.
PrioritySelfHealing = function(s, inCombat, playerHP)
	if type(playerHP) ~= "number" then
		return nil, "healing blocked: HP unreadable"
	end

	local renewActive, renewSource = RenewAuraState()
	local wantsHolyHeal = playerHP < 80 and s.renew and not renewActive and HealingKnown("Renew")
		or s.heal and HealingKnown("Lesser Heal") and (inCombat and playerHP < 60 or not inCombat and playerHP < 80 and renewActive)
	if wantsHolyHeal and AL.DPS60 and AL.DPS60.Active() and AL.DPS60.ShadowformActive()
		and AL.DPS60.Ready("Shadowform") then return "Shadowform", "Leave Shadowform to heal" end

	if playerHP < 80
		and s.renew
		and not renewActive
		and HealingKnown("Renew")
	then
		return "Renew",
			"HP " .. tostring(math.floor(playerHP + 0.5))
				.. "% < 80%, Renew absent [" .. tostring(renewSource) .. "]"
	end

	if inCombat then
		if playerHP < 60
			and s.heal
			and HealingKnown("Lesser Heal")
		then
			return "Lesser Heal",
				"combat HP " .. tostring(math.floor(playerHP + 0.5))
					.. "% < 60%"
		end
	else
		if playerHP < 80
			and renewActive
			and s.heal
			and HealingKnown("Lesser Heal")
		then
			return "Lesser Heal",
				"OOC HP " .. tostring(math.floor(playerHP + 0.5))
					.. "% < 80% with Renew present"
		end
	end

	return nil
end

local function TouchBuffActive()
	local active
	active, touchBuffUntil = TrackedPlayerBuffActive(TOUCH, touchBuffUntil, touchAppliedAt, 600)
	return active
end

local function TouchTargetActive()
	local ok, active = pcall(AL.HasDebuff, "target", TOUCH)
	if ok and SafeValue(active) and active == true then return true end
	local guidOK, guid = pcall(UnitGUID, "target")
	guid = guidOK and TouchGUID(guid)
	local entry = guid and touchTargets[guid]
	if not entry then return false end
	if entry.expires <= GetTime() then touchTargets[guid] = nil; return false end
	local stateOK, state = pcall(AL.DebugState)
	if stateOK and SafeValue(state) and type(state) == "table"
		and SafeValue(state.debuffValid) and state.debuffValid == true
		and GetTime() - entry.appliedAt >= 0.5 then
		touchTargets[guid] = nil
		return false
	end
	return true
end

local function TouchReady()
	return ReadyUsable(TOUCH) and not TouchBuffActive() and not TouchTargetActive() and SpellAffordable(TOUCH)
end

local function EmergencyProtocol(s, inCombat, playerHP)
	if not inCombat then return nil end

	if s.fade and ReadyUsable("Fade") then
		local enemies = EngagedEnemies()
		if enemies > 1 then
			return "Fade", "multiple enemies"
		end
		if type(playerHP) == "number" and playerHP < 50 then
			return "Fade", "health below 50%"
		end
	end

	if s.touchOfWeakness and TouchReady() then
		if EngagedEnemies() > 1 then return TOUCH, "multiple enemies" end
		if type(playerHP) == "number" and playerHP < 50 then return TOUCH, "health below 50%" end
	end

	return nil
end

local function SelfRecovery(s, inCombat, hostile, playerHP, moving)
	if type(playerHP) ~= "number" then return nil end

	-- Desperate Prayer remains an emergency cooldown after the fixed
	-- Renew/Lesser Heal priority rules.
	if inCombat and s.heal and playerHP <= 20 and ReadyUsable("Desperate Prayer") then
		return "Desperate Prayer", "emergency heal"
	end

	if inCombat and hostile and s.fear
		and playerHP <= SettingNumber(s, "fearHP", 50, 5, 95)
		and AL.TargetInMelee() and ReadyUsable("Psychic Scream") then
		return "Psychic Scream", "make distance"
	end

	-- Existing pre-combat Shield behavior remains below the requested
	-- out-of-combat healing rules.
	if s.shield and not inCombat and hostile and ShieldReady() then
		return "Power Word: Shield", "pre-shield"
	end

	return nil
end

local function Burst(s, targetHP)
	if not AL.burst or not TargetWorthAtLeast(targetHP,
		SettingNumber(s, "burstMinTargetHP", 40, 0, 100)) then return nil end
	if ReadyUsable("Berserking") and not AL.HasBuff("player", "Berserking") then
		return "Berserking", "burst"
	end
	return nil
end

local function DamageOverTime(s, role, mana, targetHP)
	if role == "SHADOW" and s.vampiricEmbrace
		and TargetWorthAtLeast(targetHP, SettingNumber(s, "vampiricMinTargetHP", 60, 0, 100))
		and ReadyUsable("Vampiric Embrace")
		and not AL.HasDebuff("target", "Vampiric Embrace") then
		return "Vampiric Embrace", "shadow sustain"
	end
	if s.shadowWordPain
		and TargetWorthAtLeast(targetHP, SettingNumber(s, "dotMinTargetHP", 35, 0, 100))
		and ReadyUsable("Shadow Word: Pain")
		and not AL.HasDebuff("target", "Shadow Word: Pain") then
		return "Shadow Word: Pain", "dot"
	end
	if role == "SHADOW" and s.devouringPlague
		and ManaAtLeast(mana, SettingNumber(s, "plagueMinMana", 40, 0, 100))
		and TargetWorthAtLeast(targetHP, SettingNumber(s, "plagueMinTargetHP", 60, 0, 100))
		and ReadyUsable("Devouring Plague")
		and not AL.HasDebuff("target", "Devouring Plague") then
		return "Devouring Plague", "racial dot"
	end
	return nil
end

local function Opener(s, role, mana, targetHP, moving)
	if AL.DPS60 and AL.DPS60.Active() and role == "SMITE" and AL.DPS60.ShadowformActive()
		and AL.DPS60.Ready("Shadowform") then return "Shadowform", "Leave Shadowform for holy damage" end
	-- DoTs ALWAYS come before direct-damage filler on a fresh target.
	-- This specifically prevents Smite from preceding Shadow Word: Pain.
	local dot, dotReason = DamageOverTime(s, role, mana, targetHP)
	if dot then return dot, dotReason end

	if moving then
		return nil, "Stop moving"
	end

	local mindBlast, mindBlastReason = ResolveMindBlast(s, role, mana, "ranged pull")
	if mindBlast then return mindBlast, mindBlastReason end

	if role == "SMITE" and s.holyFire and ReadyUsable("Holy Fire")
		and not AL.HasDebuff("target", "Holy Fire") then
		return "Holy Fire", "ranged pull"
	end

	if role == "SMITE" then
		local shouldWand, threshold, wandReason = SmiteShouldWand(s, mana)
		if shouldWand then
			local wand, why = Wand(s, wandReason or ("mana <= " .. tostring(threshold) .. "%"))
			if wand then return wand, why end
			return nil, "Smite blocked by wand mana"
		end
	end

	local filler = role == "SHADOW" and ShadowFiller() or SmiteFiller()
	local resolved, resolvedReason = ResolveFiller(s, filler, mana, "ranged pull")
	if resolved or resolvedReason then return resolved, resolvedReason end
	return Wand(s, "ranged pull")
end

local function PenanceNumber(value)
	value = ReadableNumber(value)
	if value and value == value and value > -math.huge and value < math.huge then return value end
end

local function PenanceCooldown()
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[PENANCE]
	local id = type(ref) == "table" and PenanceNumber(ref.id) or 402174
	if penance.cooldownID ~= id then
		penance.cooldownID, penance.cooldown, penance.liveCooldown = id, 12, false
	end
	local baseReader = C_Spell and C_Spell.GetSpellBaseCooldown or GetSpellBaseCooldown
	if not penance.liveCooldown and type(baseReader) == "function" then
		local ok, ms = pcall(baseReader, id)
		ms = ok and PenanceNumber(ms)
		if ms and ms > 1500 and ms < 120000 then penance.cooldown = ms / 1000 end
	end
	local start, duration, active, rate
	if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
		local ok, data = pcall(C_Spell.GetSpellCooldown, id)
		if ok and SafeValue(data) and type(data) == "table" then
			start, duration, rate = PenanceNumber(data.startTime), PenanceNumber(data.duration), PenanceNumber(data.modRate)
			if SafeValue(data.isActive) and type(data.isActive) == "boolean" then active = data.isActive end
		end
	elseif type(GetSpellCooldown) == "function" then
		local ok, first, second = pcall(GetSpellCooldown, id)
		if ok then start, duration = PenanceNumber(first), PenanceNumber(second) end
	end
	if duration and duration > 1.5 then
		local seconds = duration / (rate and rate > 0 and rate or 1)
		penance.cooldown, penance.liveCooldown = seconds, true
		if start and start > 0 then return start + seconds, active end
	end
	return nil, active
end

local function PenanceCastConfirmed(guid)
	local now = GetTime()
	for key, at in pairs(penance.seen) do if now - at > 30 then penance.seen[key] = nil end end
	if guid and penance.seen[guid] then return false end
	if not guid and (penance.sent and penance.sent.done or not penance.sent and now - penance.castAt < 2.5) then return false end
	local ending = PenanceCooldown()
	penance.castAt = now
	penance.untilTime = ending and ending > now and ending or now + penance.cooldown
	penance.castGUID = guid
	if guid then penance.seen[guid] = now end
	if penance.sent then penance.sent.done = true end
	SpendTrackedMana(PENANCE)
	return true
end

local function OffensivePenance(s, mana, moving)
	if not s.usePenance or moving or not Ok(PENANCE) then return nil end
	local threshold = s.offensivePenanceMana
	threshold = SafeValue(threshold) and PenanceNumber(tonumber(threshold)) or nil
	threshold = threshold and math.max(0, math.min(100, math.floor(threshold + 0.5))) or 80
	if type(mana) ~= "number" or mana < threshold then return nil end
	local targetOK, exists = pcall(UnitExists, "target")
	local attackOK, attackable = pcall(UnitCanAttack, "player", "target")
	local deadOK, dead = pcall(UnitIsDeadOrGhost, "target")
	if not targetOK or not SafeValue(exists) or exists ~= true
		or not attackOK or not SafeValue(attackable) or attackable ~= true
		or not deadOK or not SafeValue(dead) or dead ~= false then return nil end
	local rangeOK, inRange = pcall(AL.InRange, PENANCE)
	if rangeOK and SafeValue(inRange) and inRange == false then return nil end
	if not AL.SpellUsable(PENANCE) or not SpellAffordable(PENANCE) then return nil end
	local ending, active = PenanceCooldown()
	local now = GetTime()
	if now - penance.castAt < 0.5 then return nil end
	if ending then
		if ending > now then return nil end
	elseif active ~= nil then
		if active then return nil end
	elseif penance.untilTime > now then return nil end
	return PENANCE, "offensive penance"
end

local function Offense(s, role, mana, targetHP, moving)
	if s.silence and AL.TargetCasting() and ReadyUsable("Silence") then
		return "Silence", "interrupt"
	end

    if role == "SMITE" and AL.DPS60 and AL.DPS60.Active() and AL.DPS60.ShadowformActive()
        and AL.DPS60.Ready("Shadowform") then return "Shadowform", "Leave Shadowform for holy damage" end
    if role == "SHADOW" and AL.DPS60 and AL.DPS60.Active() and not AL.DPS60.ShadowformActive()
        and AL.DPS60.Ready("Shadowform") and AL.SpellUsable("Shadowform") and SpellAffordable("Shadowform") then
        return "Shadowform", "Shadow form"
    end
	-- Maintained DoTs are the first normal offensive priority.
	local dot, dotReason = DamageOverTime(s, role, mana, targetHP)
	if dot then return dot, dotReason end

	local burst, burstReason = Burst(s, targetHP)
	if burst then return burst, burstReason end

	local penanceSpell, penanceReason = OffensivePenance(s, mana, moving)
	if penanceSpell then return penanceSpell, penanceReason end

	-- Preserve the newest rev's target-health wand finisher. This is independent
	-- of the hard Smite/Mind Blast mana interlocks below.
	if type(targetHP) == "number"
		and targetHP <= SettingNumber(s, "wandTargetHP", 20, 0, 100)
		and not moving
	then
		local wand, wandReason = Wand(s, "wand finish")
		if wand or wandReason then return wand, wandReason end
	end

	if moving then return nil, "Stop moving" end

	local mindBlast, mindBlastReason = ResolveMindBlast(s, role, mana, "on cooldown")
	if mindBlast then return mindBlast, mindBlastReason end
    if AL.DPS60 and AL.DPS60.Active() and role == "SHADOW" and type(mana) == "number"
        and mana > MindBlastManaThreshold(s) and AL.DPS60.Ready("Shadow Word: Death")
        and AL.SpellUsable("Shadow Word: Death") and SpellAffordable("Shadow Word: Death") then
        local hp = PlayerHealthPercent()
        if type(hp) == "number" and hp > 35 then
            return "Shadow Word: Death", "Shadow damage; health safety passed"
        end
    end
	if role == "SMITE" and s.holyFire and ReadyUsable("Holy Fire")
		and TargetWorthAtLeast(targetHP, SettingNumber(s, "dotMinTargetHP", 35, 0, 100))
		and not AL.HasDebuff("target", "Holy Fire") then
		return "Holy Fire", "holy dot"
	end

	if role == "SMITE" then
		local shouldWand, threshold, wandReason = SmiteShouldWand(s, mana)
		if shouldWand then
			local wand, why = Wand(s, wandReason or ("mana <= " .. tostring(threshold) .. "%"))
			if wand then return wand, why end
			return nil, "Smite blocked by wand mana"
		end
	end

	local filler = role == "SHADOW" and ShadowFiller() or SmiteFiller()
	return ResolveFiller(s, filler, mana, "filler")
end


local priestDebug = {
	inCombat = false,
	hostile = false,
	hp = nil,
	mana = nil,
	manaSource = "unreadable",
	candidate = nil,
	candidateReason = nil,
	final = nil,
	finalReason = nil,
	smiteThreshold = nil,
	mindBlastThreshold = nil,
	smiteBlocked = nil,
	mindBlastBlocked = nil,
}

local function FinalManaGuard(s, spell, reason, mana)
	if spell ~= "Smite" and spell ~= "Mind Blast" then
		return spell, reason
	end

	local threshold
	if spell == "Smite" then
		threshold = WandManaThreshold(s)
	else
		threshold = MindBlastManaThreshold(s)
	end

	-- Fail CLOSED. If current mana cannot be established, Smite/Mind Blast
	-- are forbidden rather than allowed through.
	local blocked = type(mana) ~= "number" or mana <= threshold

	if spell == "Smite" then
		priestDebug.smiteThreshold = threshold
		priestDebug.smiteBlocked = blocked
	else
		priestDebug.mindBlastThreshold = threshold
		priestDebug.mindBlastBlocked = blocked
	end

	if blocked then
		local manaText = type(mana) == "number"
			and (tostring(math.floor(mana + 0.5)) .. "%")
			or "unreadable"
		local why = spell .. " FINAL BLOCK: mana " .. manaText
			.. " <= slider " .. tostring(threshold) .. "%"

		local wand = Wand(s, why)
		if wand then return "Shoot", why end
		return nil, why
	end

	return spell, reason
end

local function ComputeNextSpell(s, inCombat, hostile)
	local role = Role(s)
	local playerHP = PlayerHealthPercent()
	local mana = GateManaPercent()
	if type(mana) ~= "number" then
		mana = TrackedManaPercent()
	end
	local targetHP = hostile and AL.HealthPercent("target") or nil
	local moving = PlayerMoving()

	if not inCombat then
		-- HIGHEST OUT-OF-COMBAT PRIORITY TIER:
		-- Lesser Heal <=80% is checked first, then Fortitude/Inner Fire.
		local prep, prepReason = Preparation(s, playerHP)
		if prep then return prep, prepReason end
		local recovery, recoveryReason = SelfRecovery(s, false, hostile, playerHP, moving)
		if recovery then return recovery, recoveryReason end
		if s.drink and type(mana) == "number"
			and mana <= SettingNumber(s, "drinkMana", 35, 0, 80) then
			return nil, "Drink"
		end
		if not hostile then return nil, "Ready" end
		return Opener(s, role, mana, targetHP, moving)
	end

	-- HIGHEST COMBAT PRIORITY:
	-- Maintain Power Word: Shield before EVERY other Priest action.
	-- This runs before healing, fear, DoTs, burst, Mind Blast, Smite, Shoot/wand,
	-- and all other class-rotation recommendations.
	local combatShield, shieldReason = MaintainCombatShield(s, true)
	if combatShield then return combatShield, shieldReason end

	-- HIGHEST SELF-HEALING PRIORITY DIRECTLY AFTER SHIELD.
	local priorityHeal, priorityHealReason = PrioritySelfHealing(s, true, playerHP)
	if priorityHeal then return priorityHeal, priorityHealReason end

	local recovery, recoveryReason = SelfRecovery(s, true, hostile, playerHP, moving)
	if recovery then return recovery, recoveryReason end

	local emergency, emergencyReason = EmergencyProtocol(s, true, playerHP)
	if emergency then return emergency, emergencyReason end

	if not hostile then return nil, "No target" end
	return Offense(s, role, mana, targetHP, moving)
end

-- Standalone Shadow 18/0/33. Native percentage gates feed only our display
-- alphas. Successful player casts, rather than recommendations, own timers.
function shadow.Number(v)
    if not SafeValue(v) or type(v)~="number" or v~=v or v==math.huge or v==-math.huge then return nil end
    return v
end
function shadow.Bool(v) if SafeValue(v) and type(v)=="boolean" then return v end end
function shadow.Call(fn,...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c,d,e=pcall(fn,...);if ok then return a,b,c,d,e end
end
function shadow.Enabled(s,key)
    local v=s and s[key];if not SafeValue(v) then return false end
    if v==nil then v=M.defaults[key] end
    return SafeValue(v) and v==true
end
function shadow.Setting(s,key,fallback,low,high)
    local v=s and s[key];v=SafeValue(v) and tonumber(v) or nil
    return math.max(low,math.min(high,math.floor((shadow.Number(v) or fallback)+0.5)))
end
function shadow.ID(name)
    local ref=AL.rangeSpellRefs and AL.rangeSpellRefs[name]
    return type(ref)=="table" and shadow.Number(ref.id) or nil
end
function shadow.Known(name)
    if type(AL.Ok)=="function" then return shadow.Bool((shadow.Call(AL.Ok,name)))==true end
    return AL.known and shadow.Bool(AL.known[name])==true
end
function shadow.Health(unit)
    local value,max=shadow.Number((shadow.Call(UnitHealth,unit))),shadow.Number((shadow.Call(UnitHealthMax,unit)))
    if value and max and max>0 then return math.max(0,math.min(100,value/max*100)) end
    local pct=shadow.Number((shadow.Call(AL.HealthPercent,unit)))
    if pct and pct>=0 and pct<=100 then return pct end
    local scale=CurveConstants and CurveConstants.ScaleTo100
    pct=shadow.Number((shadow.Call(UnitHealthPercent,unit,false,scale)))
    if pct then pct=scale and pct or pct*100;if pct>=0 and pct<=100 then return pct end end
end
function shadow.RawMana()
    local amount=shadow.Number((shadow.Call(UnitPower,"player",0)))
    local maximum=shadow.Number((shadow.Call(UnitPowerMax,"player",0)))
    if amount and maximum and maximum>0 then return math.max(0,math.min(maximum,amount)),maximum end
end
function shadow.Regen()
    if not EnsureTrackedMana() then return end
    RefreshManaRegen()
    local now=GetTime();local previous=trackedManaUpdatedAt or now
    local dt=math.max(0,now-previous)
    local casting=trackedLastSpendAt and math.max(0,math.min(now,trackedLastSpendAt+5)-math.max(previous,trackedLastSpendAt)) or 0
    trackedMana=math.max(0,math.min(trackedManaMax,trackedMana+casting*cachedCastingManaRegen+(dt-casting)*cachedBaseManaRegen))
    trackedManaUpdatedAt=now
end
function shadow.Mana()
    local amount,maximum=shadow.RawMana()
    if amount then
        shadow.Regen();trackedMana,trackedManaMax,trackedManaUpdatedAt=amount,maximum,GetTime()
        shadow.costsKnown=true;return amount/maximum*100
    end
    if shadow.CurveAvailable("power","player",0) then return nil end
    shadow.Regen()
    if shadow.costsKnown~=false and trackedMana and trackedManaMax and trackedManaMax>0 then return trackedMana/trackedManaMax*100 end
end
function shadow.Cost(name)
    local api=C_Spell and C_Spell.GetSpellPowerCost or GetSpellPowerCost
    local costs=shadow.Call(api,shadow.ID(name) or name)
    if not SafeValue(costs) or type(costs)~="table" then return nil end
    local unknown=false
    for _,info in ipairs(costs) do
        if not SafeValue(info) or type(info)~="table" then return nil end
        local kind=shadow.Number(info.type)
        if kind==0 or SafeValue(info.name) and info.name=="MANA" then
            local cost=shadow.Number(info.cost)
            if cost~=nil then return math.max(0,cost) end
            cost=shadow.Number(info.minCost);if cost~=nil then return math.max(0,cost) end
            local pct=shadow.Number(info.costPercent)
            local maximum=shadow.Number((shadow.Call(UnitPowerMax,"player",0)))
            if pct and maximum and maximum>0 then return math.max(0,pct*maximum/100) end
            return nil
        elseif kind==nil then unknown=true end
    end
    if not unknown then return 0 end
end
function shadow.NextFloat(v)
    if v<=0 then return 2^-149 end
    local step=2^(math.floor(math.log(v)/math.log(2))-23)
    return (math.floor(v/step+0.5)+1)*step
end
function shadow.CurveAvailable(kind,unit,powerType)
    unit=unit or "target"
    local reader=kind=="power" and UnitPowerPercent or UnitHealthPercent
    local key=kind..":"..unit..":"..tostring(powerType or "")
    local factory=C_CurveUtil and C_CurveUtil.CreateColorCurve
    local failure=shadow.curveFailures[key]
    if failure and failure.reader==reader and failure.factory==factory then return false end
    if type(factory)~="function" or type(CreateColor)~="function" or type(reader)~="function" then return false end
    shadow.capabilities=shadow.capabilities or {}
    local ready=shadow.capabilities[key]
    if ready and ready.reader==reader and ready.factory==factory then return true end
    local ok=pcall(function()
        local alpha=shadow.ReadVisualAlpha({kind=kind,unit=unit,powerType=powerType,low=0,high=0.5})
        shadow.probe=shadow.probe or CreateFrame("Frame");shadow.probe:Hide();shadow.probe:SetAlpha(alpha)
    end)
    if not ok then shadow.curveFailures[key]={reader=reader,factory=factory};return false end
    shadow.capabilities[key]={reader=reader,factory=factory};return true
end
function shadow.Gate(kind,unit,value,threshold,below,strict)
    value=shadow.Number(value)
    if value~=nil then
        if math.abs(value-threshold)<1e-7 then value=threshold end
        if below then return strict and value<threshold or not strict and value<=threshold end
        return strict and value>threshold or not strict and value>=threshold
    end
    if not below and threshold<=0 and not strict then return true end
    if not shadow.CurveAvailable(kind,unit,kind=="power" and 0 or nil) then return false end
    local cut=threshold/100
    if below and not strict or not below and strict then cut=shadow.NextFloat(cut) end
    return {axis=kind..":"..unit,kind=kind,unit=unit,powerType=kind=="power" and 0 or nil,cut=cut,below=below}
end
function shadow.HP(unit,value,threshold,below,strict) return shadow.Gate("health",unit,value,threshold,below,strict) end
function shadow.MP(value,threshold,below,strict) return shadow.Gate("power","player",value,threshold,below,strict) end
function shadow.Add(name,reason,gates)
    local conditions={}
    for _,gate in ipairs(gates or {}) do
        if gate==false then return false end
        if type(gate)=="table" then conditions[#conditions+1]=gate end
    end
    local actions=shadow.decision.actions
    if #actions>0 and #actions[#actions].conditions==0 then return false end
    actions[#actions+1]={spell=name,reason=reason,conditions=conditions}
    if #conditions>0 then shadow.decision.visualCandidate=true end
    return true
end
function shadow.Talent(name)
    if not shadow.talentWarm then
        shadow.talentWarm=true
        local translated={ ["Improved Mind Blast"]=shadow.Call(C_Spell and C_Spell.GetSpellName,15273),
            ["Improved Shadow Word: Pain"]=shadow.Call(C_Spell and C_Spell.GetSpellName,15275) }
        for tab=1,3 do for i=1,40 do
            local n,_,_,_,rank=shadow.Call(GetTalentInfo,tab,i,false,false);rank=shadow.Number(rank)
            if SafeValue(n) and type(n)=="string" and rank and rank>=0 then
                local english=(AL.englishNames and AL.englishNames[n]) or n
                for key,native in pairs(translated) do if SafeValue(native) and type(native)=="string" and n==native then english=key;break end end
                shadow.talents[english]=rank
            end
        end end
    end
    return shadow.talents[name]
end
shadow.baseCooldowns={ ["Mind Blast"]=8,["Devouring Plague"]=24,["Vampiric Embrace"]=30,
    ["Shadow Word: Death"]=18,["Inner Focus"]=180,["Shadowfiend"]=300,["Dark Sacrifice"]=600,
    ["Berserking"]=180,["Eureka!"]=120,["Elune's Light"]=180,["Silence"]=45,
    ["Psychic Scream"]=30,["Fade"]=30,["Penance"]=12 }
function shadow.Ready(name)
    local record=shadow.cooldowns[name]
    if record and GetTime()-record.at<0.5 then return false end
    local info=shadow.Call(C_Spell and C_Spell.GetSpellCooldown,shadow.ID(name) or name)
    if SafeValue(info) and type(info)=="table" then
        if shadow.Bool(info.isEnabled)==false then return false end
        local start,duration,rate=shadow.Number(info.startTime),shadow.Number(info.duration),shadow.Number(info.modRate) or 1
        if start and duration and start>=0 and duration>=0 and rate>0 then return start==0 or duration<=1.5 or start+duration/rate<=GetTime() end
        if shadow.Bool(info.isActive)==false then return true end
    end
    if record then return record.ends<=GetTime() end
    if shadow.baseCooldowns[name] then return true end
    return shadow.Bool((shadow.Call(AL.IsReady,name)))==true
end
function shadow.Affordable(name,mana)
    local cost=shadow.Cost(name)
    if cost==nil then
        local usable,shortage=shadow.Call(C_Spell and C_Spell.IsSpellUsable or IsUsableSpell,shadow.ID(name) or name)
        return shadow.Bool(usable)==true and shadow.Bool(shortage)==false
    end
    if cost<=0 then return true end
    local amount,maximum=shadow.RawMana()
    if amount then return amount>=cost end
    maximum=shadow.Number((shadow.Call(UnitPowerMax,"player",0)))
    if maximum and maximum>0 then return shadow.MP(mana,cost/maximum*100,false) end
    return false
end
function shadow.Offer(name,reason,gates,exitForm)
    if not shadow.Known(name) or not shadow.Ready(name) then return false end
    if not exitForm then
        local usable,shortage=shadow.Call(C_Spell and C_Spell.IsSpellUsable or IsUsableSpell,shadow.ID(name) or name)
        if shadow.Bool(usable)==false or shadow.Bool(shortage)==true then return false end
        if shadow.Bool((shadow.Call(AL.InRange,name)))==false then return false end
    end
    local conditions={}
    for _,gate in ipairs(gates or {}) do conditions[#conditions+1]=gate end
    conditions[#conditions+1]=exitForm and true or shadow.Affordable(name,shadow.mana)
    if name~="Shoot" and shadow.Wanding() and shadow.Known("Shoot") then
        if GetTime()<(shadow.wandStopUntil or 0) then return shadow.Add(nil,"Stopping wand",conditions) end
        return shadow.Add("Shoot","Stop wand for "..name,conditions)
    end
    return shadow.Add(name,reason,conditions)
end
function shadow.Wanding()
    if shadow.shootAt and GetTime()-shadow.shootAt<0.6 then return shadow.shooting==true end
    return shadow.Bool((shadow.Call(IsAutoRepeatSpell,5019)))==true or shadow.Bool((shadow.Call(IsCurrentSpell,5019)))==true
        or wandEventActive==true
end
function shadow.Auras(unit,harmful)
    local key=unit..(harmful and ":harmful" or ":helpful")
    shadow.auraCache=shadow.auraCache or {};shadow.auraBlocked=shadow.auraBlocked or {}
    local cached=shadow.auraCache[key]
    if cached and GetTime()-cached.at<0.1 then return cached.values,cached.complete end
    local values,complete,uncertain={},false,false
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not shadow.auraBlocked[key] and type(reader)=="function" then
        for i=1,40 do
            local ok,aura=pcall(reader,unit,i,harmful and "HARMFUL" or "HELPFUL")
            if not ok or not SafeValue(aura) then shadow.auraBlocked[key]=true;break end
            if aura==nil then complete=true;break end
            if type(aura)~="table" then break end
            local id=shadow.Number(aura.spellId)
            local name=SafeValue(aura.name) and type(aura.name)=="string" and aura.name or nil
            name=name and ((AL.englishNames and AL.englishNames[name]) or name)
            if not name and id then name=shadow.Name(id) end
            if id==15258 then name="Shadow Weaving" end
            local own=not harmful or shadow.Bool(aura.isFromPlayerOrPlayerPet)==true or SafeValue(aura.sourceUnit) and aura.sourceUnit=="player"
            if not name or harmful and shadow.Bool(aura.isFromPlayerOrPlayerPet)==nil
                and not (SafeValue(aura.sourceUnit) and type(aura.sourceUnit)=="string") then uncertain=true end
            if name and own then values[name]={expires=shadow.Number(aura.expirationTime),stacks=shadow.Number(aura.applications)} end
            if id==15258 then values["Shadow Weaving"]={expires=shadow.Number(aura.expirationTime),stacks=shadow.Number(aura.applications)} end
        end
    end
    if uncertain then complete=false end
    shadow.auraCache[key]={at=GetTime(),values=values,complete=complete}
    return values,complete
end
function shadow.Active(name,target)
    local unit=target and "target" or "player"
    local guid=target and shadow.Call(UnitGUID,"target") or "player"
    if not SafeValue(guid) or type(guid)~="string" then return false end
    local bucket=target and shadow.dots[guid] or shadow.buffs
    local saved=bucket and bucket[name]
    if saved and saved.expires<=GetTime() then bucket[name]=nil;saved=nil end
    if saved and GetTime()-saved.at<0.6 then return true end
    local auras,complete=shadow.Auras(unit,target)
    local aura=auras[name]
    if aura then
        if aura.expires and aura.expires>0 and aura.expires<=GetTime() then return false end
        return true
    end
    if complete then if bucket then bucket[name]=nil end;return false end
    if saved then return true end
    if not target then return shadow.Bool((shadow.Call(AL.HasBuff,"player",name)))==true end
    return false
end
function shadow.Form()
    if GetTime()-shadow.formAt<0.6 then return shadow.form end
    local auras,complete=shadow.Auras("player",false)
    if auras.Shadowform then shadow.form=true;return true end
    if complete then shadow.form=false;return false end
    local form=shadow.Number((shadow.Call(GetShapeshiftForm)))
    if form and form>0 then shadow.form,shadow.formObserved=true,true;return true end
    if form==0 and (shadow.formObserved or shadow.form~=true) then shadow.form=false;return false end
    return shadow.form
end
function shadow.Within(unit,radius)
    local square,checked=shadow.Call(UnitDistanceSquared,unit);square=shadow.Number(square)
    if square and square>=0 and shadow.Bool(checked)~=false then return square<=radius*radius end
    local object=A and shadow.Call(A.Unit,unit)
    if SafeValue(object) and (type(object)=="table" or type(object)=="userdata") then
        local low,high=shadow.Call(object.GetRange,object)
        if not SafeValue(high) then return nil end
        local bound;if high~=nil then bound=shadow.Number(high) else bound=shadow.Number(low) end
        if bound and bound>=0 then return bound<=radius end
    end
    if radius>=10 then return shadow.Bool((shadow.Call(CheckInteractDistance,unit,3))) end
end
function shadow.Enemies()
    local count
    local function accept(value)
        value=shadow.Number(value)
        if value and value>=0 and value<=40 and value==math.floor(value) then count=math.max(count or 0,value) end
    end
    accept((shadow.Call(AL.EnemyCount,10)))
    if A and A.MultiUnits then accept((shadow.Call(A.MultiUnits.GetByRangeInCombat,A.MultiUnits,10,5))) end
    local seen,n={},0
    local function visit(unit)
        if shadow.Bool((shadow.Call(UnitExists,unit)))~=true or shadow.Bool((shadow.Call(UnitCanAttack,"player",unit)))~=true
            or shadow.Bool((shadow.Call(UnitIsDeadOrGhost,unit)))~=false or shadow.Bool((shadow.Call(UnitAffectingCombat,unit)))~=true
            or shadow.Within(unit,10)~=true then return end
        local guid=shadow.Call(UnitGUID,unit)
        if SafeValue(guid) and type(guid)=="string" and not seen[guid] then seen[guid]=true;n=n+1 end
    end
    visit("target");for i=1,40 do visit("nameplate"..i) end
    if n>0 then accept(n) end
    return count
end
function shadow.Moving()
    if shadow.moving~=nil then return shadow.moving end
    return (shadow.Number((shadow.Call(GetUnitSpeed,"player"))) or 0)>0
end
function shadow.Casting()
    if GetTime()<shadow.channelUntil or GetTime()<(shadow.castUntil or 0) then return true end
    for _,reader in pairs({UnitCastingInfo,UnitChannelInfo}) do
        local name=shadow.Call(reader,"player")
        if not SafeValue(name) or name~=nil then return true end
    end
    return false
end
function shadow.Heal(s,inCombat,hp,form)
    local renew=shadow.Enabled(s,"renew") and shadow.Known("Renew") and not shadow.Active("Renew",false)
    local direct=shadow.Enabled(s,"heal") and shadow.Known("Lesser Heal")
    local limit=inCombat and 60 or 80
    local canDirect=inCombat or shadow.Active("Renew",false)
    if form==true then
        if renew then shadow.Offer("Shadowform","Leave Shadowform to heal",{shadow.HP("player",hp,80,true,true),shadow.Affordable("Renew",shadow.mana)},true) end
        if direct and canDirect then shadow.Offer("Shadowform","Leave Shadowform to heal",{shadow.HP("player",hp,limit,true,true),shadow.Affordable("Lesser Heal",shadow.mana)},true) end
        return
    end
    if renew then shadow.Offer("Renew","Self healing",{shadow.HP("player",hp,80,true,true)}) end
    if direct and canDirect and not shadow.Moving() then shadow.Offer("Lesser Heal","Self healing",{shadow.HP("player",hp,limit,true,true)}) end
end
function shadow.Burst(s,mana,hp,targetHP,moving)
    if shadow.Bool(AL.burst)~=true then return end
    local gates={shadow.HP("target",targetHP,shadow.Setting(s,"burstMinTargetHP",40,0,100),false)}
    if shadow.Enabled(s,"shadowFiend") then shadow.Offer("Shadowfiend","Shadow Burst mana support",{gates[1],shadow.MP(mana,shadow.Setting(s,"shadowFiendMana",70,0,100),true)}) end
    if shadow.Enabled(s,"shadowSacrifice") then shadow.Offer("Dark Sacrifice","Shadow Burst mana support",{gates[1],
        shadow.MP(mana,shadow.Setting(s,"shadowSacrificeMana",30,0,100),true),shadow.HP("player",hp,shadow.Setting(s,"shadowSacrificeHP",80,20,100),false)}) end
    if moving or not shadow.Known("Mind Blast") or not shadow.Enabled(s,"mindBlast") or not shadow.Ready("Mind Blast")
        or shadow.Bool((shadow.Call(AL.InRange,"Mind Blast")))==false then return end
    local auras,complete=shadow.Auras("player",false)
    local stacks=auras["Shadow Weaving"] and auras["Shadow Weaving"].stacks
    local established=stacks~=nil and stacks>=5 or stacks==nil and not complete and GetTime()-(shadow.combatAt or GetTime())>=8
    if not established or not shadow.Active("Shadow Word: Pain",true) then return end
    gates[#gates+1]=shadow.MP(mana,shadow.Setting(s,"mindBlastMana",50,0,100),false,true)
    if shadow.Enabled(s,"shadowRacials") then
        shadow.Offer("Eureka!","Shadow Burst",gates);shadow.Offer("Elune's Light","Shadow Burst",gates);shadow.Offer("Berserking","Shadow Burst",gates)
    end
    if shadow.Enabled(s,"shadowInnerFocus") and not shadow.Active("Inner Focus",false) then shadow.Offer("Inner Focus","Inner Focus for Mind Blast",gates) end
end
function shadow.Wand(s,reason,gates)
    if shadow.Enabled(s,"wand") and shadow.Bool((shadow.Call(AL.WandEquipped)))==true then shadow.Offer("Shoot",reason,gates) end
end
function shadow.NextSpell(s,inCombat,hostile)
    shadow.decision={at=GetTime(),actions={}}
    if not inCombat then shadow.Talent("Improved Mind Blast") end
    if inCombat and not shadow.combatAt then shadow.combatAt=GetTime() elseif not inCombat then shadow.combatAt=nil end
    local hp,targetHP=shadow.Health("player"),hostile and shadow.Health("target") or nil
    local mana=shadow.Mana();shadow.mana=mana
    local moving,form=shadow.Moving(),shadow.Form()
    if shadow.Casting() then shadow.Add(nil,"Channeling")
    else
        if shadow.Enabled(s,"shield") and not HasWeakenedSoul() and not shadow.Active("Power Word: Shield",false) then
            if inCombat then shadow.Offer("Power Word: Shield","Low-health shield",{shadow.HP("player",hp,shadow.Setting(s,"shieldHP",65,5,100),true)})
            elseif hostile then shadow.Offer("Power Word: Shield","Pre-shield") end
        end
        shadow.Heal(s,inCombat,hp,form)
        if inCombat then
            if shadow.Enabled(s,"fade") then
                local gates=EngagedEnemies()>=2 and {} or {shadow.HP("player",hp,50,true,true)}
                shadow.Offer("Fade","Emergency Fade",gates)
            end
            if shadow.Enabled(s,"touchOfWeakness") and not TouchBuffActive() and not TouchTargetActive() then
                local gates=EngagedEnemies()>=2 and {} or {shadow.HP("player",hp,50,true,true)}
                shadow.Offer(TOUCH,"Touch of Weakness emergency",gates)
            end
            if hostile and shadow.Enabled(s,"fear") and shadow.Bool((shadow.Call(AL.TargetInMelee)))==true then
                shadow.Offer("Psychic Scream","Make distance",{shadow.HP("player",hp,shadow.Setting(s,"fearHP",50,5,95),true)})
            end
            if shadow.Enabled(s,"heal") then shadow.Offer("Desperate Prayer","Emergency heal",{shadow.HP("player",hp,20,true)}) end
            if hostile and shadow.Enabled(s,"silence") and shadow.Bool((shadow.Call(AL.TargetCasting)))==true then shadow.Offer("Silence","Interrupt") end
        else
            if not moving then
                if shadow.Enabled(s,"buffs") and not shadow.Active("Power Word: Fortitude",false) then shadow.Offer("Power Word: Fortitude","Fortitude") end
                if shadow.Enabled(s,"divineSpirit") and not shadow.Active(DIVINE_SPIRIT,false) then shadow.Offer(DIVINE_SPIRIT,"Divine Spirit") end
                if shadow.Enabled(s,"innerfire") and not shadow.Active("Inner Fire",false) then shadow.Offer("Inner Fire","Inner Fire") end
            end
            if shadow.Enabled(s,"drink") then shadow.Add(nil,"Drink",{shadow.MP(mana,shadow.Setting(s,"drinkMana",35,0,80),true)}) end
        end
        if hostile then
            if shadow.Enabled(s,"shadowForm") and form==false then shadow.Offer("Shadowform","Shadow form") end
            if not inCombat and not moving and shadow.Enabled(s,"mindBlast") then
                shadow.Offer("Mind Blast","Ranged pull",{shadow.MP(mana,shadow.Setting(s,"mindBlastMana",50,0,100),false,true)})
            end
            if shadow.Enabled(s,"shadowWordPain") and not shadow.Active("Shadow Word: Pain",true) then
                shadow.Offer("Shadow Word: Pain","Shadow damage over time",{shadow.HP("target",targetHP,shadow.Setting(s,"dotMinTargetHP",35,0,100),false)})
            end
            if shadow.Enabled(s,"devouringPlague") and not shadow.Active("Devouring Plague",true) then
                shadow.Offer("Devouring Plague","Devouring Plague",{shadow.MP(mana,shadow.Setting(s,"plagueMinMana",40,0,100),false),
                    shadow.HP("target",targetHP,shadow.Setting(s,"plagueMinTargetHP",60,0,100),false)})
            end
            if shadow.Enabled(s,"vampiricEmbrace") and not shadow.Active("Vampiric Embrace",true) then
                shadow.Offer("Vampiric Embrace","Shadow sustain",{shadow.HP("target",targetHP,shadow.Setting(s,"vampiricMinTargetHP",60,0,100),false)})
            end
            if inCombat then shadow.Burst(s,mana,hp,targetHP,moving) end
            if inCombat and shadow.Enabled(s,"aoe") and shadow.Enabled(s,"shadowHolyNova") and form==false
                and shadow.Within("target",10)==true and (shadow.Enemies() or 0)>=shadow.Setting(s,"aoeMinEnemies",2,2,5) then
                shadow.Offer("Holy Nova","Shadow optional AoE",{shadow.MP(mana,shadow.Setting(s,"aoeMinMana",40,0,100),false)})
            end
            if inCombat and shadow.Enabled(s,"usePenance") and not moving then
                shadow.Offer(PENANCE,"Offensive Penance",{shadow.MP(mana,shadow.Setting(s,"offensivePenanceMana",80,0,100),false)})
            end
            if not moving then
                shadow.Wand(s,"Wand finish",{shadow.HP("target",targetHP,shadow.Setting(s,"wandTargetHP",20,0,80),true)})
                shadow.Wand(s,"Conserve mana",{shadow.MP(mana,shadow.Setting(s,"wandMana",25,0,100),true)})
                if shadow.Enabled(s,"mindBlast") and shadow.Known("Mind Blast") then
                    shadow.Wand(s,"Mind Blast mana threshold",{shadow.MP(mana,shadow.Setting(s,"mindBlastMana",50,0,100),true)})
                end
            end
            if not moving and shadow.Enabled(s,"mindBlast") then shadow.Offer("Mind Blast","Shadow Mind Blast",{shadow.MP(mana,shadow.Setting(s,"mindBlastMana",50,0,100),false,true)}) end
            if shadow.Enabled(s,"shadowWordDeath") then shadow.Offer("Shadow Word: Death","Shadow Word: Death",{
                shadow.HP("player",hp,shadow.Setting(s,"shadowDeathMinHP",50,20,95),false,true)}) end
            if not moving then
                if shadow.Enabled(s,"shadowMindFlay") then shadow.Offer("Mind Flay","Shadow filler") end
                -- Forever Shadowform blocks healing, not offensive Smite.
                shadow.Offer("Smite","Learned leveling fallback",{shadow.MP(mana,shadow.Setting(s,"wandMana",25,0,100),false,true)})
                shadow.Wand(s,"Conserve mana")
            end
        end
    end
    shadow.Add(nil,inCombat and not hostile and "No target" or moving and "Stop moving" or "Ready")
    local base=shadow.decision.actions[#shadow.decision.actions]
    shadow.decision.baseSpell,shadow.decision.baseReason=base.spell,base.reason
    return base.spell,base.reason
end

function M.NextSpell(s, inCombat, hostile)
    M.NormalizeBuild(s)
	-- Existing saved profiles may be used before the menu first fills defaults.
	if type(s) == "table" and (not s.divineSpiritIconInitialized or not s.penanceIconInitialized) then AL.FillDefaults(s, "PRIEST") end
	if shadow.Enabled(s,"shadow") then return shadow.NextSpell(s,inCombat,hostile) end
    shadow.decision=nil
	if GetTime() < penance.channelUntil then return nil, "Channeling" end
	local role = Role(s)
	local hp = PlayerHealthPercent()
	local mana = GateManaPercent()

	-- Store the exact values that this rotation pass is using.
	priestDebug.inCombat = inCombat and true or false
	priestDebug.hostile = hostile and true or false
	priestDebug.hp = hp
	priestDebug.mana = mana
	priestDebug.manaSource = lastManaSource
	priestDebug.smiteThreshold = WandManaThreshold(s)
	priestDebug.mindBlastThreshold = MindBlastManaThreshold(s)
	priestDebug.smiteBlocked =
		type(mana) ~= "number" or mana <= priestDebug.smiteThreshold
	priestDebug.mindBlastBlocked =
		type(mana) ~= "number" or mana <= priestDebug.mindBlastThreshold

	local spell, reason = ComputeNextSpell(s, inCombat, hostile)
	priestDebug.candidate = spell
	priestDebug.candidateReason = reason

	-- Absolute final interlock. No internal branch can bypass this.
	local finalSpell, finalReason = FinalManaGuard(s, spell, reason, mana)
	priestDebug.final = finalSpell
	priestDebug.finalReason = finalReason

	return finalSpell, finalReason
end

function M.HealingState()
	local profile = AL.S()
	local hp = priestDebug.hp
	if type(hp) ~= "number" then hp = PlayerHealthPercent() end

	local renewActive, renewSource = RenewAuraState()
	local renewKnown = HealingKnown("Renew")
	local lesserKnown = HealingKnown("Lesser Heal")
	local inCombat = priestDebug.inCombat and true or false

	local renewDecision = "WAIT"
	if type(hp) ~= "number" then
		renewDecision = "BLOCK: HP unreadable"
	elseif hp < 80 and profile and profile.renew and not renewActive and renewKnown then
		renewDecision = "CAST RENEW"
	elseif hp >= 80 then
		renewDecision = "WAIT: HP >= 80"
	elseif renewActive then
		renewDecision = "WAIT: Renew present"
	elseif not (profile and profile.renew) then
		renewDecision = "BLOCK: Renew toggle off"
	elseif not renewKnown then
		renewDecision = "BLOCK: Renew not known"
	end

	local lesserDecision = "WAIT"
	if type(hp) ~= "number" then
		lesserDecision = "BLOCK: HP unreadable"
	elseif not (profile and profile.heal) then
		lesserDecision = "BLOCK: heal toggle off"
	elseif not lesserKnown then
		lesserDecision = "BLOCK: Lesser Heal not known"
	elseif inCombat and hp < 60 then
		if hp < 80 and profile.renew and not renewActive and renewKnown then
			lesserDecision = "WAIT: Renew first"
		else
			lesserDecision = "CAST LESSER HEAL"
		end
	elseif (not inCombat) and hp < 80 and renewActive then
		lesserDecision = "CAST LESSER HEAL"
	elseif inCombat then
		lesserDecision = "WAIT: combat HP >= 60"
	elseif hp >= 80 then
		lesserDecision = "WAIT: OOC HP >= 80"
	else
		lesserDecision = "WAIT: OOC requires Renew present"
	end

	return {
		inCombat = inCombat,
		hp = hp,
		renewEnabled = profile and profile.renew == true,
		renewKnown = renewKnown,
		renewActive = renewActive,
		renewSource = renewSource,
		renewDecision = renewDecision,
		healEnabled = profile and profile.heal == true,
		lesserHealKnown = lesserKnown,
		lesserDecision = lesserDecision,
		candidate = priestDebug.candidate,
		final = priestDebug.final,
		finalReason = priestDebug.finalReason,

		eventHealthPct = eventHealthPct,
		eventHealthSource = eventHealthSource,
		eventHealthAge = type(eventHealthAt) == "number" and (GetTime() - eventHealthAt) or nil,
		healthEventCount = healthEventCount,

		trackedHealth = trackedHealth,
		trackedHealthMax = trackedHealthMax,
		trackedHealthPct = TrackedHealthPercent(),
		trackedHealthSource = trackedHealthSource,
		trackedHealthLastEvent = trackedHealthLastEvent,
		trackedHealthLastAmount = trackedHealthLastAmount,
		combatHealthEventCount = combatHealthEventCount,

		predictionHealthPct = predictionHealthPct,
		predictionHealthSource = predictionHealthSource,
		predictionHealthHasSecrets = predictionHealthHasSecrets,
		predictionHealthAge = type(predictionHealthAt) == "number" and (GetTime() - predictionHealthAt) or nil,

		frameHealthPct = frameHealthPct,
		frameHealthSource = frameHealthSource,
		frameHealthText = frameHealthText,
		frameHealthAge = type(frameHealthAt) == "number" and (GetTime() - frameHealthAt) or nil,
	}
end

function M.ManaGateState()
	local profile = AL.S()
	local mana = priestDebug.mana
	if type(mana) ~= "number" then
		mana = GateManaPercent()
	end

	local smiteThreshold = WandManaThreshold(profile)
	local mindBlastThreshold = MindBlastManaThreshold(profile)
	local smiteBlocked = type(mana) ~= "number" or mana <= smiteThreshold
	local mindBlastBlocked = type(mana) ~= "number" or mana <= mindBlastThreshold

	return {
		mana = mana,
		source = priestDebug.manaSource or lastManaSource,
		trackedPct = TrackedManaPercent(),
		trackedMana = trackedMana,
		trackedManaMax = trackedManaMax,
		trackedSource = trackedSource,
		lastSpell = trackedLastSpell,
		lastCost = trackedLastCost,
		smiteThreshold = smiteThreshold,
		mindBlastThreshold = mindBlastThreshold,
		smiteBlocked = smiteBlocked,
		mindBlastBlocked = mindBlastBlocked,
		candidate = priestDebug.candidate,
		candidateReason = priestDebug.candidateReason,
		final = priestDebug.final,
		finalReason = priestDebug.finalReason,

		eventManaPct = eventManaPct,
		eventManaSource = eventManaSource,
		eventManaAge = type(eventManaAt) == "number" and (GetTime() - eventManaAt) or nil,
		manaEventCount = manaEventCount,

		castSentCount = castSentCount,
		castSucceededCount = castSucceededCount,
		castFallbackCount = castFallbackCount,
		lastSentCastName = lastSentCastName,
		lastSucceededCastName = lastSucceededCastName,
	}
end

function M.SecretHealVisualState()
	-- Forever can make the player's actual health percentage a Secret Value.
	-- Do not try to inspect it here.  Return only the NON-SECRET pieces needed
	-- by Display.lua / Glow.lua so they can let Blizzard's curve system drive
	-- the visual alpha directly from the protected health percentage.
	local s = AL.S()
	if type(s) ~= "table" then return nil end
	if shadow.Enabled(s,"shadow") then return nil end

	local inCombat = false
	if type(UnitAffectingCombat) == "function" then
		local ok, value = pcall(UnitAffectingCombat, "player")
		if ok and not (issecretvalue and issecretvalue(value)) then
			inCombat = value and true or false
		end
	end

	local renewActive = RenewActive()

	-- Highest healing priority:
	-- Renew below 80% whenever Renew is absent.
	if s.renew
		and HealingKnown("Renew")
		and not renewActive
	then
		return "Renew", 80, "Renew absent; secret-health threshold 80", inCombat, renewActive
	end

	-- Once Renew is active, Lesser Heal becomes the direct-heal layer.
	if s.heal and HealingKnown("Lesser Heal") then
		if inCombat then
			return "Lesser Heal", 60, "combat direct-heal threshold 60", true, renewActive
		end

		if renewActive then
			return "Lesser Heal", 80, "OOC direct-heal threshold 80 with Renew active", false, true
		end
	end

	return nil
end

function M.DecisionDebugState()
	return priestDebug
end

function M.ManaPercent()
    if shadow.Enabled(AL.S(),"shadow") then return shadow.Mana(),"native/readable/confirmed casts" end
	local gate = GateManaPercent()
	local tracked = TrackedManaPercent()
	local threshold = WandManaThreshold(AL.S())

	if type(gate) == "number" then
		return gate, lastManaSource, gate, threshold, tracked
	end

	if type(tracked) == "number" then
		return tracked, trackedSource, tracked, threshold, tracked
	end

	return nil, "unreadable", nil, threshold, nil
end

function M.MindBlastState()
	local profile = AL.S()
	local threshold = MindBlastManaThreshold(profile)
	local lowMana = mindBlastShootModeActive

	if type(lastMindBlastManaPct) == "number" then
		lowMana = lastMindBlastManaPct <= threshold
	end

	return {
		equipped = WandEquipped(),
		threshold = threshold,
		mana = lastMindBlastManaPct,
		lowMana = lowMana,
		decision = lowMana and "SHOOT/BLOCK" or "MIND BLAST",
	}
end

function M.WandState()
	local profile = AL.S()
	local mana = GateManaPercent()
	local threshold = WandManaThreshold(profile)
	local lowMana = type(mana) ~= "number" or mana <= threshold

	return {
		equipped = WandEquipped(),
		threshold = threshold,
		mana = mana,
		trackedMana = trackedMana,
		trackedManaMax = trackedManaMax,
		trackedPct = TrackedManaPercent(),
		trackedLastSpell = trackedLastSpell,
		trackedLastCost = trackedLastCost,
		trackedSource = trackedSource,
		lowMana = lowMana,
		decision = WandEquipped() and lowMana and "SHOOT" or "SMITE",
	}
end

function M.GetUIState()
	local mana
	if shadow.Enabled(AL.S(),"shadow") then mana=shadow.Mana() else mana=TrackedManaPercent() end
	return {
		role = Role(AL.S()),
		mana = mana,
		moving = PlayerMoving(),
		wanding = PlayerIsWanding(),
		shieldLocked = GetTime() < shieldLockUntil,
	}
end

-- Keep the consumable self-buff separate from the ordinary damage proc. The
-- proc can use a different spell ID, and combat aura reads can be protected.
local touchTracker = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "COMBAT_LOG_EVENT_UNFILTERED",
	"PLAYER_DEAD", "PLAYER_ENTERING_WORLD" }) do pcall(touchTracker.RegisterEvent, touchTracker, event) end
touchTracker:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
	if AL.playerClass ~= "PRIEST" then return end
	if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
		touchBuffUntil, touchAppliedAt, touchTargets, touchSent, touchLastSuccessGUID = 0, 0, {}, nil, nil
		return
	end
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if type(CombatLogGetCurrentEventInfo) ~= "function" then return end
		local ok, _, sub, _, source, _, _, _, dest, _, _, _, id = pcall(CombatLogGetCurrentEventInfo)
		if not ok or not SafeValue(sub) then return end
		local playerOK, player = pcall(UnitGUID, "player")
		player, source, dest = playerOK and TouchGUID(player), TouchGUID(source), TouchGUID(dest)
		if not player then return end
		if TouchSpellID(id, TOUCH_CAST_IDS) and dest == player then
			if sub == "SPELL_AURA_REMOVED" then touchBuffUntil = 0
			elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" then
				touchBuffUntil, touchAppliedAt = GetTime() + 600, GetTime()
			end
		elseif TouchSpellID(id, TOUCH_PROC_IDS) and source == player and dest and dest ~= player then
			if sub == "SPELL_AURA_REMOVED" then touchTargets[dest] = nil
			elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" or sub == "SPELL_DAMAGE" then
				touchBuffUntil = 0
				touchTargets[dest] = { expires = GetTime() + 120, appliedAt = GetTime() }
			elseif sub == "SPELL_MISSED" then touchBuffUntil = 0 end
		end
		return
	end
	if not SafeValue(unit) or unit ~= "player" then return end
	if event == "UNIT_SPELLCAST_SENT" then
		touchSent = nil
		if TouchSentSpell(arg2, arg3, arg4) then
			touchSent = { at = GetTime(), guid = TouchCastGUID(arg3) }
		end
		return
	end
	local guid = TouchCastGUID(arg2)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		if touchSent and (not guid or not touchSent.guid or guid == touchSent.guid) then
			touchSent = nil
			if lastSentCastName == TOUCH then lastSentCastName, lastSentCastAt = nil, 0 end
		end
		return
	end
	if TouchSpellID(arg3, TOUCH_PROC_IDS) then return end
	local id = SafeValue(arg3) and type(arg3) == "number" and arg3
	local pending = touchSent and GetTime() - touchSent.at < 5
		and (not guid or not touchSent.guid or guid == touchSent.guid)
	if not TouchSpellID(id, TOUCH_CAST_IDS) and not (not id and pending) then return end
	if guid and guid == touchLastSuccessGUID then return end
	touchBuffUntil, touchAppliedAt, touchLastSuccessGUID = GetTime() + 600, GetTime(), guid
	touchSent = nil
end)

local penanceTracker = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
	"UNIT_SPELLCAST_INTERRUPTED", "PLAYER_DEAD", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_LOGIN" }) do
	pcall(penanceTracker.RegisterEvent, penanceTracker, event)
end
penanceTracker:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
	if AL.playerClass ~= "PRIEST" then return end
	if shadow.Enabled(AL.S(),"shadow") then return end
	if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
		penance.untilTime, penance.channelUntil, penance.castAt, penance.sent, penance.seen = 0, 0, -math.huge, nil, {}
		penance.cooldown, penance.cooldownID, penance.liveCooldown = 12, nil, false
		PenanceCooldown(); return
	elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_LOGIN" then
		penance.liveCooldown = false
		PenanceCooldown(); return
	end
	if not SafeValue(unit) or unit ~= "player" then return end
	local id = PenanceNumber(arg4) or PenanceNumber(arg3)
	if event == "UNIT_SPELLCAST_SENT" then
		if id and PENANCE_PROCS[id] then return end
		penance.sent = nil
		local name = CastName(arg2, arg3, arg4)
		if PenanceSpellID(id) or not id and (name == PENANCE
			or (not name or not (AL.known and AL.known[name])) and AL.lastSuggestion == PENANCE and Ok(PENANCE)) then
			penance.sent = { at = GetTime(), guid = TouchCastGUID(arg3), done = false }
		end
		return
	end
	local guid = TouchCastGUID(arg2)
	local pending = penance.sent and GetTime() - penance.sent.at < 5
		and (not guid or not penance.sent.guid or guid == penance.sent.guid)
	if event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED"
		or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
		if PenanceSpellID(id) or id and PENANCE_PROCS[id] or pending or guid and guid == penance.castGUID then
			penance.channelUntil = 0
			if pending and not penance.sent.done then penance.sent = nil end
			if lastSentCastName == PENANCE then lastSentCastName, lastSentCastAt = nil, 0 end
		end
		return
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if id and PENANCE_PROCS[id] then return end
		if PenanceSpellID(id) or not id and pending then PenanceCastConfirmed(guid) end
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		if PenanceSpellID(id) or id and PENANCE_PROCS[id] or not id and pending then
			local confirmed = PenanceCastConfirmed(guid)
			if confirmed or GetTime() - penance.castAt < 0.5 and (not guid or guid == penance.castGUID) then
				penance.channelUntil = GetTime() + 2.5
			end
		end
	end
end)

shadow.IntervalCurve = function(low, high)
	local factory = C_CurveUtil.CreateColorCurve
	if shadow.curveFactory ~= factory then
		shadow.curves, shadow.curveFactory = {}, factory
	end
	local key = tostring(low) .. ":" .. tostring(high)
	if shadow.curves[key] then return shadow.curves[key] end
	local curve = factory()
	curve:SetType(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	curve:AddPoint(0, CreateColor(1, 1, 1, low == 0 and 1 or 0))
	if low > 0 and low <= 1 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
	if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
	if low ~= 1 and high ~= 1 then curve:AddPoint(1, CreateColor(1, 1, 1, low <= 1 and high > 1 and 1 or 0)) end
	shadow.curves[key] = curve
	return curve
end

shadow.ReadVisualAlpha = function(mask)
    local curve = shadow.IntervalCurve(mask.low, mask.high)
    local color
    if mask.kind == "power" then color = UnitPowerPercent(mask.unit, mask.powerType, false, curve)
    else color = UnitHealthPercent(mask.unit, false, curve) end
    local _, _, _, alpha = color:GetRGBA()
    if SafeValue(alpha) and shadow.Number(alpha) == nil then error("Shaman resource curve returned no display alpha") end
    return alpha
end

function M.SecretVisualPlan(spell, reason)
	local d = shadow.decision
	if not d or not d.visualCandidate or GetTime() - d.at > 0.3
		or spell ~= d.baseSpell or reason ~= d.baseReason then return nil end
	if d.visualPlan then return d.visualPlan end
	local axes, axisMap = {}, {}
	for _, action in ipairs(d.actions) do
		for _, c in ipairs(action.conditions) do
			local axis = axisMap[c.axis]
			if not axis then
				axis = { key = c.axis, kind = c.kind, unit = c.unit, powerType = c.powerType, cuts = { 0, 2 }, seen = { [0] = true, [2] = true } }
				axes[#axes + 1], axisMap[c.axis] = axis, axis
			end
			if not axis.seen[c.cut] then axis.cuts[#axis.cuts + 1], axis.seen[c.cut] = c.cut, true end
		end
	end
	for _, axis in ipairs(axes) do table.sort(axis.cuts) end
	local plan = { rows = {}, masks = {}, spells = {}, baseSpell = spell, baseReason = reason }
	local samples, masks = {}, {}
	local function Rows(index)
		if index <= #axes then
			local axis = axes[index]
			for i = 1, #axis.cuts - 1 do
				local low, high = axis.cuts[i], axis.cuts[i + 1]
				samples[axis.key] = (low + high) / 2
				local key = axis.key .. ":" .. tostring(low) .. ":" .. tostring(high)
				local mask = { key = key, kind = axis.kind, unit = axis.unit, powerType = axis.powerType, low = low, high = high }
				plan.masks[key], masks[index] = mask, mask
				Rows(index + 1)
			end
			return
		end
		local chosen
		for _, action in ipairs(d.actions) do
			local pass = true
			for _, c in ipairs(action.conditions) do
				local value = samples[c.axis]
				if (c.below and value >= c.cut) or (not c.below and value < c.cut) then pass = false; break end
			end
			if pass then chosen = action; break end
		end
		if chosen then
			local row = { spell = chosen.spell, reason = chosen.reason, masks = {} }
			for i, mask in ipairs(masks) do row.masks[i] = mask end
			plan.rows[#plan.rows + 1] = row
			if chosen.spell then plan.spells[chosen.spell] = true end
		end
	end
	Rows(1)
    -- Merge adjacent cells with the same decision before creating display
    -- rows. The mutually exclusive masks retain their exact boundaries.
    for axisIndex=#axes,1,-1 do
        local groups,order={},{}
        for _,row in ipairs(plan.rows) do
            local parts={row.spell or "",row.reason or ""}
            for i,mask in ipairs(row.masks) do if i~=axisIndex then parts[#parts+1]=mask.key end end
            local key=table.concat(parts,"|")
            if not groups[key] then groups[key]={};order[#order+1]=key end
            groups[key][#groups[key]+1]=row
        end
        local combined={}
        for _,key in ipairs(order) do
            local rows=groups[key]
            table.sort(rows,function(a,b)return a.masks[axisIndex].low<b.masks[axisIndex].low end)
            local previous
            for _,row in ipairs(rows) do
                local mask=row.masks[axisIndex]
                if previous and previous.masks[axisIndex].high==mask.low then
                    local first=previous.masks[axisIndex]
                    previous.masks[axisIndex]={key=axes[axisIndex].key..":"..tostring(first.low)..":"..tostring(mask.high),
                        kind=first.kind,unit=first.unit,powerType=first.powerType,low=first.low,high=mask.high}
                else combined[#combined+1]=row;previous=row end
            end
        end
        plan.rows=combined
    end
    plan.masks={}
    for _,row in ipairs(plan.rows) do for _,mask in ipairs(row.masks) do plan.masks[mask.key]=mask end end
	d.visualPlan = plan
	return plan
end

function M.EvaluateVisualMasks(plan)
	local values = {}
	local ok = pcall(function()
		for key, mask in pairs(plan.masks) do
			local success, value = pcall(shadow.ReadVisualAlpha, mask)
			if not success then
				shadow.curveFailures[mask.kind .. ":" .. mask.unit .. ":" .. tostring(mask.powerType or "")] = {
					reader = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent,
					factory = C_CurveUtil and C_CurveUtil.CreateColorCurve }
				error("Shaman resource curve unavailable")
			end
			values[key] = value
		end
	end)
	if ok then return values end
	return nil
end

function M.ApplyVisualRow(nodes, row, values)
	for i, node in ipairs(nodes) do
		local mask = row.masks[i]
		if mask then
            local ok = pcall(node.SetAlpha, node, values[mask.key])
            if not ok then
                shadow.curveFailures[mask.kind .. ":" .. mask.unit .. ":" .. tostring(mask.powerType or "")] = {
                    reader = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent,
                    factory = C_CurveUtil and C_CurveUtil.CreateColorCurve }
                error("Shaman resource alpha unavailable")
            end
        else node:SetAlpha(1) end
	end
end






function shadow.Name(id)
    id=shadow.Number(id);if not id then return nil end
    local name=AL.castSpellNamesByID and AL.castSpellNamesByID[id]
    if SafeValue(name) and type(name)=="string" then return (AL.englishNames and AL.englishNames[name]) or name end
    for n,ref in pairs(AL.rangeSpellRefs or {}) do if type(ref)=="table" and shadow.Number(ref.id)==id then return n end end
end
function shadow.GUID(v)
    if SafeValue(v) and type(v)=="string" and v:find("^Cast%-") then return v end
end
function shadow.ConsumeFocus(name)
    if name=="Inner Focus" or name=="Shoot" or name=="Berserking" or name=="Eureka!" or name=="Elune's Light" or name=="Dark Sacrifice" then return false end
    return true
end
function shadow.Confirm(name,id,guid,sent)
    if not name or not AL.known or shadow.Bool(AL.known[name])~=true then return false end
    if id and shadow.Name(id)~=name then return false end
    local now=GetTime()
    for key,at in pairs(shadow.completed) do if now-at>660 then shadow.completed[key]=nil end end
    if guid and shadow.completed[guid] or not guid and sent and sent.done then return false end
    if guid then shadow.completed[guid]=now end
    if guid then shadow.pending[guid]=nil end
    if sent then sent.done=true end
    if name=="Shoot" and sent and sent.stopShoot then shadow.wandStopUntil=now+0.6 end
    local cost=sent and sent.cost
    if cost==nil then cost=shadow.Cost(name) end
    if cost~=nil then SpendTrackedMana(name,cost) else shadow.costsKnown=false end
    local live,maximum=shadow.RawMana()
    if live then
        trackedMana=math.min(trackedMana or live,live);trackedManaMax=maximum;trackedManaUpdatedAt=now
        shadow.costsKnown=true
    end
    local duration=shadow.baseCooldowns[name]
    if name=="Mind Blast" then duration=8-0.5*math.min(5,shadow.Talent("Improved Mind Blast") or 0) end
    if name=="Inner Focus" then duration=nil end
    if duration then shadow.cooldowns[name]={at=now,ends=now+duration} end
    if shadow.buffs["Inner Focus"] and shadow.ConsumeFocus(name) then
        shadow.buffs["Inner Focus"]=nil;shadow.cooldowns["Inner Focus"]={at=now,ends=now+180}
    end
    local buffDurations={ ["Power Word: Fortitude"]=3600,["Divine Spirit"]=3600,["Inner Fire"]=600,["Renew"]=15,["Power Word: Shield"]=30 }
    if buffDurations[name] then shadow.buffs[name]={at=now,expires=now+buffDurations[name]} end
    if name=="Shadowform" then
        local before=sent and sent.formBefore
        if before==nil then before=shadow.Form() end
        shadow.form,shadow.formAt=before~=true,now
        shadow.buffs.Shadowform=shadow.form and {at=now,expires=math.huge} or nil
    elseif name=="Inner Focus" then shadow.buffs[name]={at=now,expires=math.huge}
    elseif name=="Renew" then renewLockUntil=now+15
    elseif name=="Power Word: Shield" then shieldLockUntil=now+15
    elseif name==DIVINE_SPIRIT then divineSpiritUntil,divineSpiritAppliedAt=now+3600,now end
    local durations={ ["Shadow Word: Pain"]=18+3*math.min(2,shadow.Talent("Improved Shadow Word: Pain") or 0),
        ["Devouring Plague"]=24,["Vampiric Embrace"]=30 }
    for target,bucket in pairs(shadow.dots) do
        for spell,record in pairs(bucket) do if record.expires<=now then bucket[spell]=nil end end
        if next(bucket)==nil then shadow.dots[target]=nil end
    end
    local target=sent and sent.targetGUID
    if durations[name] and SafeValue(target) and type(target)=="string" then
        shadow.dots[target]=shadow.dots[target] or {}
        shadow.dots[target][name]={at=now,expires=now+durations[name]}
    end
    if name=="Mind Flay" or name==PENANCE then
        shadow.channelGUID,shadow.channelName=guid,name
        shadow.channelUntil=math.max(shadow.channelUntil,now+(name==PENANCE and 2.5 or 3))
    end
    shadow.auraCache={}
    if type(AL.PopQueue)=="function" then AL.PopQueue(name) end
    return true
end
function shadow.Observe(_,event,unit,a,b,c)
    if AL.playerClass~="PRIEST" then return end
    if event=="SPELLS_CHANGED" or event=="PLAYER_TALENT_UPDATE" or event=="CHARACTER_POINTS_CHANGED" or event=="PLAYER_LOGIN" then
        shadow.talentWarm,shadow.talents=nil,{}
        if shadow.Bool((shadow.Call(UnitAffectingCombat,"player")))==false then shadow.Talent("Improved Mind Blast") end
        return
    end
    if event=="PLAYER_STARTED_MOVING" then shadow.moving=true;return elseif event=="PLAYER_STOPPED_MOVING" then shadow.moving=false;return end
    if event=="START_AUTOREPEAT_SPELL" or event=="STOP_AUTOREPEAT_SPELL" then
        shadow.shooting,shadow.shootAt,shadow.wandStopUntil=event=="START_AUTOREPEAT_SPELL",GetTime(),0;return
    end
    if event=="UNIT_AURA" or event=="PLAYER_TARGET_CHANGED" or event=="UPDATE_SHAPESHIFT_FORM" then shadow.auraCache,shadow.auraBlocked={},{};return end
    if event=="PLAYER_DEAD" or event=="PLAYER_ENTERING_WORLD" then
        shadow.dots,shadow.buffs,shadow.pending,shadow.auraCache,shadow.auraBlocked={},{},{},{},{}
        shadow.form,shadow.formObserved,shadow.formAt=nil,nil,-math.huge
        shadow.channelUntil,shadow.castUntil,shadow.combatAt,shadow.moving=0,0,nil,nil
        shadow.decision,shadow.lastSent,shadow.costsKnown=nil,nil,true
        shadow.wandStopUntil,shadow.shooting,shadow.shootAt=0,false,nil
        shadow.curves,shadow.capabilities,shadow.curveFailures={},{},{}
        shadow.talentWarm,shadow.talents=nil,{}
        return
    end
    if not shadow.Enabled(AL.S(),"shadow") then return end
    if event=="PLAYER_REGEN_DISABLED" then shadow.combatAt=GetTime();return
    elseif event=="PLAYER_REGEN_ENABLED" then
        shadow.combatAt,shadow.talentWarm,shadow.talents=nil,nil,{}
        shadow.Talent("Improved Mind Blast");return
    end
    if event=="COMBAT_LOG_EVENT_UNFILTERED" then
        if type(CombatLogGetCurrentEventInfo)~="function" then return end
        local ok,data=pcall(function()return {CombatLogGetCurrentEventInfo()}end)
        if not ok or not SafeValue(data[2]) then return end
        local player=shadow.Call(UnitGUID,"player")
        if not SafeValue(player) or type(player)~="string" then return end
        local sub=data[2]
        if (sub=="SPELL_ENERGIZE" or sub=="SPELL_PERIODIC_ENERGIZE") and SafeValue(data[8]) and data[8]==player
            and shadow.Number(data[16])==0 then
            local gain=shadow.Number(data[15]);if gain and gain>0 then shadow.Regen();if trackedMana and trackedManaMax then trackedMana=math.min(trackedManaMax,trackedMana+gain) end end
        end
        if SafeValue(data[4]) and data[4]==player then
            local name=shadow.Name(data[12]);local dest=SafeValue(data[8]) and type(data[8])=="string" and data[8]
            if name and dest and (sub=="SPELL_MISSED" or sub=="SPELL_AURA_REMOVED") and shadow.dots[dest] then shadow.dots[dest][name]=nil end
            if name=="Shadowform" and dest==player and sub=="SPELL_AURA_REMOVED" then shadow.form,shadow.formAt=false,GetTime() end
            if name=="Inner Focus" and dest==player and sub=="SPELL_AURA_REMOVED" then shadow.buffs[name]=nil;shadow.cooldowns[name]={at=GetTime(),ends=GetTime()+180} end
        end
        return
    end
    if not SafeValue(unit) or unit~="player" then return end
    local id=shadow.Number(c) or shadow.Number(b)
    local name=shadow.Name(id)
    if event=="UNIT_SPELLCAST_SENT" then
        for key,record in pairs(shadow.pending) do if GetTime()-record.at>15 then shadow.pending[key]=nil end end
        local guid=shadow.GUID(b)
        if not name and not id and shadow.decision and not shadow.decision.visualCandidate
            and GetTime()-shadow.decision.at<0.5 and AL.lastSuggestion==shadow.decision.baseSpell and shadow.Known(AL.lastSuggestion) then name=AL.lastSuggestion end
        shadow.lastSent=nil
        if name then
            shadow.Mana()
            local cost=shadow.Cost(name)
            if shadow.buffs["Inner Focus"] and shadow.ConsumeFocus(name) or name=="Shadowform" and shadow.Form()==true then cost=0 end
            local target=shadow.Call(UnitGUID,"target")
            local sent={at=GetTime(),guid=guid,name=name,id=id,cost=cost,
                targetGUID=SafeValue(target) and type(target)=="string" and target or nil,formBefore=shadow.Form(),stopShoot=name=="Shoot" and shadow.Wanding()}
            shadow.lastSent=sent;if guid then shadow.pending[guid]=sent end
        end
        return
    end
    local guid=shadow.GUID(a)
    local sent=guid and shadow.pending[guid] or shadow.lastSent
    if sent and (GetTime()-sent.at>15 or guid and sent.guid and guid~=sent.guid or not guid and GetTime()-sent.at>=5) then sent=nil end
    if event=="UNIT_SPELLCAST_CHANNEL_START" and id and PENANCE_PROCS[id] and sent and sent.name==PENANCE then
        name,id=PENANCE,sent.id or shadow.ID(PENANCE)
    end
    if not name and not id and sent then name=sent.name end
    if event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_FAILED_QUIET" or event=="UNIT_SPELLCAST_INTERRUPTED"
        or event=="UNIT_SPELLCAST_STOP" or event=="UNIT_SPELLCAST_CHANNEL_STOP" then
        if not guid or not shadow.castGUID or guid==shadow.castGUID then shadow.castUntil=0 end
        if event~="UNIT_SPELLCAST_STOP" and (not guid or not shadow.channelGUID or guid==shadow.channelGUID) then shadow.channelUntil=0 end
        if event~="UNIT_SPELLCAST_STOP" and event~="UNIT_SPELLCAST_CHANNEL_STOP" then
            if guid then shadow.pending[guid]=nil end
            if sent==shadow.lastSent then shadow.lastSent=nil end
        end
        return
    end
    if event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_DELAYED" then
        if name then
            local _,_,_,_,ends=shadow.Call(UnitCastingInfo,"player");ends=shadow.Number(ends)
            local info=shadow.Call(C_Spell and C_Spell.GetSpellInfo,shadow.ID(name) or name)
            local ms=SafeValue(info) and type(info)=="table" and shadow.Number(info.castTime)
            shadow.castGUID,shadow.castUntil=guid,ends and ends/1000 or GetTime()+(ms and ms/1000 or 3)+1
        end
        return
    end
    if event=="UNIT_SPELLCAST_SUCCEEDED" or event=="UNIT_SPELLCAST_CHANNEL_START" then
        local confirmed=shadow.Confirm(name,id,guid,sent)
        if confirmed and (not guid or not shadow.castGUID or guid==shadow.castGUID) then shadow.castUntil=0 end
        if event=="UNIT_SPELLCAST_CHANNEL_START" and (name=="Mind Flay" or name==PENANCE) then
            local _,_,_,_,ends=shadow.Call(UnitChannelInfo,"player");ends=shadow.Number(ends)
            if ends and ends/1000>GetTime() then shadow.channelUntil=ends/1000 end
        end
    end
end
shadow.observer=CreateFrame("Frame")
for _,event in ipairs({"UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_FAILED_QUIET","UNIT_SPELLCAST_INTERRUPTED",
    "PLAYER_STARTED_MOVING","PLAYER_STOPPED_MOVING","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_TARGET_CHANGED","UNIT_AURA",
    "UPDATE_SHAPESHIFT_FORM","START_AUTOREPEAT_SPELL","STOP_AUTOREPEAT_SPELL","PLAYER_DEAD","PLAYER_ENTERING_WORLD","PLAYER_LOGIN","SPELLS_CHANGED","CHARACTER_POINTS_CHANGED","PLAYER_TALENT_UPDATE","COMBAT_LOG_EVENT_UNFILTERED"}) do
    pcall(shadow.observer.RegisterEvent,shadow.observer,event)
end
shadow.observer:SetScript("OnEvent",shadow.Observe)

AL.RegisterRotation("PRIEST", M)
-- END OPTIONAL TALENT BUILD IMPLEMENTATION
    end)(ADDON, RotationScope(false))

    -- Preserve every pre-sim setting's default. Extra talent-build settings,
    -- the full spell list, UI builders and Universal icon choices stay current.
    for key, value in pairs(leveling.defaults) do advanced.defaults[key] = value end

    local modernNextSpell = advanced.NextSpell
    local wasLeveling = true
    function advanced.NextSpell(profile, ...)
        if UsesLeveling(profile) then
            wasLeveling = true
            return leveling.NextSpell(profile, ...)
        end
        if wasLeveling and advanced.OnRotationActivated then advanced.OnRotationActivated() end
        wasLeveling = false
        return modernNextSpell(profile, ...)
    end

    -- Decisions, display plans and state queries must all use the same engine.
    -- A missing original hook means there is no Leveling plan, rather than
    -- reusing a stale plan from a previously selected talent build.
    for _, name in ipairs({
        "SecretVisualPlan", "EvaluateVisualMasks", "ApplyVisualRow",
        "ApplySecretHealthVisibility", "SecretFinisherVisualState",
        "SecretHealVisualState", "CanTrackSuggestedSpell", "CanTrackSuggestedDebuff",
        "SelectedCurse", "ActiveCurse", "CurrentForm", "ManaPercent", "ManaGateState",
        "DecisionDebugState", "HealingState", "MindBlastState", "WandState",
        "GetUIState", "SoulShardCount", "DebugState",
    }) do
        local old, modern = leveling[name], advanced[name]
        if type(old) == "function" or type(modern) == "function" then
            advanced[name] = function(...)
                -- Menus may inspect a different class profile from the player.
                local profile = name == "GetUIState" and root.ES and root.ES() or nil
                if UsesLeveling(profile) then
                    if old then return old(...) end
                elseif modern then
                    return modern(...)
                end
            end
        end
    end

    local unpackValues = unpack or table.unpack
    local function ObserveInactive(fn, ...)
        local args, count = { ... }, select("#", ...)
        for i = 1, count do
            local value = args[i]
            if type(value) == "table" and not (issecretvalue and issecretvalue(value)) then
                local copy = {}
                for key, item in pairs(value) do copy[key] = item end
                args[i] = copy
            end
        end
        -- Cast records carry per-engine completion flags (for example mana
        -- accounting). The inactive tracker must never mark the active record.
        pcall(fn, unpackValues(args, 1, count))
    end

    for _, name in ipairs({
        "OnTargetChanged", "OnUIError", "OnCastSent", "OnCastResult",
        "RefreshManaCache", "OnManaCastSent", "OnManaCastSucceeded",
    }) do
        local old, modern = leveling[name], advanced[name]
        if type(old) == "function" or type(modern) == "function" then
            advanced[name] = function(...)
                -- Warm the inactive history first. Its optional tracker cannot
                -- prevent the active rotation from receiving the real event.
                if UsesLeveling() then
                    if modern then ObserveInactive(modern, ...) end
                    if old then return old(...) end
                else
                    if old then ObserveInactive(old, ...) end
                    if modern then return modern(...) end
                end
            end
        end
    end
    root.RegisterRotation("PRIEST", advanced)
end
