local ADDON, AL = ...

-- ActionLITE Mage v0.20.3: original Leveling plus optional talent builds.

-- Leveling keeps the finalized pre-simulation implementation in its own
-- scope. Talent builds use the separate implementation below. Both observe
-- real casts so switching rotations retains resource and spell history.
do
    local root = AL
    local leveling, advanced
    local function UsesLeveling(profile)
        profile = profile or (root.Profile and root.Profile("MAGE")) or (root.S and root.S())
        if advanced and type(profile) == "table" then
            return advanced.NormalizeBuild(profile) == "leveling"
        end
        return true
    end
    local function RotationScope(isLeveling)
        local scope = {
            RegisterRotation = function(token, module)
                assert(token == "MAGE", "Unexpected class rotation")
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
                    if root.playerClass == "MAGE" and UsesLeveling() == isLeveling then root[key] = value end
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
-- BEGIN ORIGINAL LEVELING IMPLEMENTATION (Mage(4).lua)
local ADDON, AL = ...

-- WoW Forever Mage leveling 1-30 - v0.15.6
-- Target: beta 1.60.1.69913.
-- Classic IDs and levels are only LIKELY references;
-- the client's spellbook remains authoritative. The learned rank's exact range controls
-- red/normal coloring; it does not replace the damage spell with a melee attack.

local A = _G.Action

local M = {
	defaults = {
		nuke = "AUTO",
		primaryFire = false,
		buffs = true,
		conjure = true,
		drink = true,
		drinkMana = 35,
		evocation = true,
		evocationMana = 15,
		wand = true,
		wandMana = 25,
		wandTargetHP = 20,
		nova = true,
		fireblast = true,
		fireBlastMinMana = 25,
		icelance = true,
		cspell = true,
		iceblock = true,
		iceBlockHP = 18,
		manaShield = false,
		manaShieldHP = 45,
		manaShieldMinMana = 25,
		aoe = false,
		aoeMinEnemies = 3,
		aoeMinMana = 35,
		burstMinTargetHP = 40,
	},
}

-- Classic rank-one IDs used for identification and icons.
-- Ice Lance is retained only if Forever actually lists it in the
-- spellbook; its TBC ID is not treated as evidence of Forever support.
M.spells = {
	{ 1008, "Amplify Magic" },
	{ 1449, "Arcane Explosion" },
	{ 1459, "Arcane Intellect" },
	{ 5143, "Arcane Missiles" },
	{ 1953, "Blink" },
	{ 10, "Blizzard" },
	{ 120, "Cone of Cold" },
	{ 587, "Conjure Food" },
	{ 759, "Conjure Mana Agate" },
	{ 5504, "Conjure Water" },
	{ 2139, "Counterspell" },
	{ 604, "Dampen Magic" },
	{ 2855, "Detect Magic" },
	{ 12051, "Evocation" },
	{ 2136, "Fire Blast" },
	{ 543, "Fire Ward" },
	{ 133, "Fireball" },
	{ 2120, "Flamestrike" },
	{ 168, "Frost Armor" },
	{ 122, "Frost Nova" },
	{ 6143, "Frost Ward" },
	{ 116, "Frostbolt" },
	{ 7302, "Ice Armor" },
	{ 11958, "Ice Block" },
	{ 30455, "Ice Lance" },
	{ 6117, "Mage Armor" },
	{ 1463, "Mana Shield" },
	{ 118, "Polymorph" },
	{ 475, "Remove Lesser Curse" },
	{ 2948, "Scorch" },
	{ 130, "Slow Fall" },
	{ 5019, "Shoot" },
}

AL.selfCastSpells = AL.selfCastSpells or {}
for _, name in ipairs({
	"Arcane Intellect", "Frost Armor", "Ice Armor", "Mage Armor",
	"Ice Block", "Mana Shield", "Evocation", "Conjure Water",
	"Conjure Food", "Conjure Mana Agate", "Berserking", "Frost Nova", "Arcane Explosion", "Cone of Cold",
}) do
	AL.selfCastSpells[name] = true
end

-- Classic learning levels. Talents and spells not confirmed on
-- Forever are deliberately absent from this table and gated by the book.
local MINLEVEL = {
	["Arcane Intellect"] = 1,
	["Fireball"] = 1,
	["Frost Armor"] = 1,
	["Conjure Water"] = 4,
	["Frostbolt"] = 4,
	["Conjure Food"] = 6,
	["Fire Blast"] = 6,
	["Polymorph"] = 8,
	["Frost Nova"] = 10,
	["Dampen Magic"] = 12,
	["Arcane Explosion"] = 14,
	["Arcane Missiles"] = 16,
	["Flamestrike"] = 16,
	["Detect Magic"] = 18,
	["Remove Lesser Curse"] = 18,
	["Blink"] = 20,
	["Blizzard"] = 20,
	["Evocation"] = 20,
	["Fire Ward"] = 20,
	["Mana Shield"] = 20,
	["Counterspell"] = 24,
	["Cone of Cold"] = 26,
	["Conjure Mana Agate"] = 28,
	["Ice Armor"] = 30,
	["Mage Armor"] = 34,
	["Frost Ward"] = 22,
}

local Ok = select(1, AL.LevelGates(MINLEVEL))
M.minLevels = MINLEVEL

-- Classic conjured items, from lowest to highest rank. A protected
-- bag count returns nil and never causes a repeated-conjuring loop.
local WATER_IDS = { 5350, 2288, 2136, 3772, 8077, 8078, 8079 }
local FOOD_IDS = { 5349, 1113, 1114, 1487, 8075, 8076 }
local GEM_IDS = { 5514 }

local FROZEN_DEBUFFS = { "Frost Nova", "Frostbite" }
local ARMORS = { "Ice Armor", "Frost Armor", "Mage Armor" }

-- Shared native gates keep opaque percentages in native display alpha only.
local lastRotation
local visibilityCurves, curveFailures, curveCapabilities = {}, {}, {}
local IntervalCurve, ReadVisualAlpha
local curveProbe
local visibilityCurveFactory
local movementEventActive
local LiveWandActive
local wandStopPendingUntil = 0
local wandRecoveryUntil = 0
local cooldownSnapshots = {}
local wandEventActive, wandPendingUntil = false, 0
local conjureLocks = {}
local function SafeValue(value)
    return not (issecretvalue and issecretvalue(value))
end
local function ReadableNumber(value)
    if not SafeValue(value) or type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then return nil end
    return value
end
local Number = ReadableNumber
local function SafeCall(reader, ...)
    if type(reader) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(reader, ...)
    if ok then return a, b, c, d end
end
local function Bool(value)
    if SafeValue(value) and type(value) == "boolean" then return value end
end
local function Percent(value)
    value = Number(value)
    if value and value >= 0 and value <= 100 then return value end
end
local function LearnedID(name)
    local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
    return ref and Number(ref.id)
end
local function SpellUsability(name)
    local usable, shortage = SafeCall(IsUsableSpell or (C_Spell and C_Spell.IsSpellUsable), LearnedID(name) or name)
    return Bool(usable), Bool(shortage)
end
local function HealthPercent(unit)
    if Bool((SafeCall(UnitExists, unit))) ~= true then return nil end
    local hp = Percent((SafeCall(AL.HealthPercent, unit)))
    if hp ~= nil then return hp end
    local scale = CurveConstants and CurveConstants.ScaleTo100
    local value = Number((SafeCall(UnitHealthPercent, unit, false, scale)))
    if value ~= nil then
        hp = Percent(scale and value or value * 100)
        if hp ~= nil then return hp end
    end
    local action = _G.Action
    local object = action and SafeCall(action.Unit, unit)
    if SafeValue(object) and (type(object) == "table" or type(object) == "userdata") then
        return Percent((SafeCall(object.HealthPercent, object)))
    end
end

local function CurveAvailable(kind, unit, powerType)
    unit = unit or "target"
    local reader = kind == "power" and UnitPowerPercent or UnitHealthPercent
    local key = kind .. ":" .. unit .. ":" .. tostring(powerType or "")
    local failure = curveFailures[key]
    local factory = C_CurveUtil and C_CurveUtil.CreateColorCurve
    if failure and failure.reader == reader and failure.factory == factory then return false end
    if type(factory) ~= "function" or type(CreateColor) ~= "function" or type(reader) ~= "function" then return false end
    local available = curveCapabilities[key]
    if available and available.reader == reader and available.factory == factory then return true end
    -- A present API can still reject a color curve in this client. Confirm
    -- that its result can reach a native display before relying on its gates.
    local ok = pcall(function()
        local alpha = ReadVisualAlpha({ kind=kind, unit=unit, powerType=powerType, low=0, high=0.5 })
        curveProbe = curveProbe or CreateFrame("Frame")
        curveProbe:Hide()
        curveProbe:SetAlpha(alpha)
    end)
    if not ok then
        curveFailures[key] = { reader=reader, factory=factory }
        return false
    end
    curveCapabilities[key] = { reader=reader, factory=factory }
    return true
end

local function NextFloat32(value)
    if value <= 0 then return 2 ^ -149 end
    local exponent = math.floor(math.log(value) / math.log(2))
    local step = 2 ^ (exponent - 23)
    return (math.floor(value / step + 0.5) + 1) * step
end

local function HealthGate(unit, value, threshold, below, strict)
    if value ~= nil then
        if math.abs(value - threshold) < 1e-7 then value = threshold end
        if below then return strict and value < threshold or not strict and value <= threshold end
        return strict and value > threshold or not strict and value >= threshold
    end
    if not below and threshold <= 0 then return true end
    if not CurveAvailable("health", unit) then return false end
    local cut = threshold / 100
    if below and not strict or not below and strict then cut = NextFloat32(cut) end
    return { axis = unit .. "HP", kind = "health", unit = unit, cut = cut, below = below }
end

local function AddAction(spell, reason, gates)
    local conditions = {}
    for _, gate in ipairs(gates or {}) do
        if gate == false then return false end
        if type(gate) == "table" then conditions[#conditions + 1] = gate end
    end
    local actions = lastRotation.actions
    if #actions > 0 and #actions[#actions].conditions == 0 then return false end
    actions[#actions + 1] = { spell = spell, reason = reason, conditions = conditions }
    if #conditions > 0 then lastRotation.visualCandidate = true end
    return true
end

local function SettingNumber(s, key, defaultValue, minValue, maxValue)
    local raw = s and s[key]
    local value = SafeValue(raw) and tonumber(raw) or nil
    value = Number(value) or defaultValue
    return math.max(minValue, math.min(maxValue, math.floor(value + 0.5)))
end


local function SettingChoice(s, key, allowed, defaultValue)
    local value = s and s[key]
    if SafeValue(value) and type(value) == "string" and allowed[value] then return value end
    return defaultValue
end

local trackedMana = nil
local trackedManaMax = nil
local trackedManaUpdatedAt = nil
local trackedLastSpendAt = nil
local trackedLastSpell = nil
local trackedLastCost = 0
local trackedSource = "uninitialized"
local trackedCostsKnown = true

local cachedBaseManaRegen = 0
local cachedCastingManaRegen = 0

local eventManaPct = nil
local eventManaSource = "unreadable"
local eventManaAt = nil
local manaEventCount = 0

local lastSentCastName = nil
local lastSentCastAt = 0
local castSentCount = 0
local castSucceededCount = 0
local castFallbackCount = 0
local lastSucceededCastName = nil

local lastManaSource = "unreadable"

local function ReadManaMaximum()
	local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

	if type(UnitPowerMax) == "function" then
		local ok, maximum = pcall(UnitPowerMax, "player", powerType)
		maximum = ok and ReadableNumber(maximum) or nil
		if maximum and maximum > 0 then return maximum end

		ok, maximum = pcall(UnitPowerMax, "player")
		maximum = ok and ReadableNumber(maximum) or nil
		if maximum and maximum > 0 then return maximum end
	end

	if type(AL.DebugPowerState) == "function" then
		local ok, state = pcall(AL.DebugPowerState)
		if ok and SafeValue(state) and type(state) == "table" then
			local maximum =
				ReadableNumber(state.typedMax)
				or ReadableNumber(state.primaryMax)
				or ReadableNumber(state.cachedMax)
			if maximum and maximum > 0 then return maximum end
		end
	end
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
			if trackedMana and trackedManaMax and trackedManaMax > 0 then
				local pct = trackedMana / trackedManaMax
				trackedMana = math.max(0, math.min(maximum, maximum * pct))
			end
			trackedManaMax = maximum
		end
	end

	if not trackedManaMax or trackedManaMax <= 0 then return false end

	if trackedMana == nil then
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
    local previous = trackedManaUpdatedAt or now
    local dt = math.max(0, now - previous)
    trackedManaUpdatedAt = now
    local castingTime = trackedLastSpendAt and math.max(0, math.min(now, trackedLastSpendAt + 5) - math.max(previous, trackedLastSpendAt)) or 0
    local gain = cachedCastingManaRegen * castingTime + cachedBaseManaRegen * (dt - castingTime)
    trackedMana = math.min(trackedManaMax, math.max(0, trackedMana + gain))
end

local function SpellManaCost(spellName)
	if type(spellName) ~= "string" or spellName == "" then return 0 end

	local identifiers = {}
	local seen = {}

	local function AddIdentifier(value)
		if not SafeValue(value) or value == nil or seen[value] then return end
		seen[value] = true
		identifiers[#identifiers + 1] = value
	end

	-- Prefer Core's exact learned-rank reference.
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[spellName]
	if SafeValue(ref) and type(ref) == "table" then AddIdentifier(ref.id) end

    AddIdentifier(spellName)
    if not (ref and ReadableNumber(ref.id)) then
        for _, def in ipairs(M.spells or {}) do if def[2] == spellName then AddIdentifier(def[1]); break end end
    end

	for _, identifier in ipairs(identifiers) do
		local costs

		if C_Spell and type(C_Spell.GetSpellPowerCost) == "function" then
			local ok, result = pcall(C_Spell.GetSpellPowerCost, identifier)
			if ok and SafeValue(result) and type(result) == "table" then costs = result end
		elseif type(GetSpellPowerCost) == "function" then
			local ok, result = pcall(GetSpellPowerCost, identifier)
			if ok and SafeValue(result) and type(result) == "table" then costs = result end
		end

		if costs then
			-- A readable empty cost list for this learned spell is a free cast.
			if next(costs) == nil then return 0 end
			for _, info in ipairs(costs) do
				if SafeValue(info) and type(info) == "table" then
					local powerType = ReadableNumber(info.type)
					local token = SafeValue(info.name) and info.name or nil

					if powerType == 0 or token == "MANA" then
						local cost =
							ReadableNumber(info.cost)
							or ReadableNumber(info.minCost)

						if cost and cost >= 0 then return cost end

						-- A percentage alone cannot confirm the actual current
						-- mana cost. Wait for a numeric cost instead of inventing it.
					end
				end
			end
		end
	end

	return nil
end

local function SpendTrackedMana(spellName, sentCost)
	if not EnsureTrackedMana() then return end

	UpdateTrackedManaRegen()

	local cost = ReadableNumber(sentCost)
	if cost == nil or cost < 0 then cost = SpellManaCost(spellName) end
	if cost == nil then trackedCostsKnown, trackedSource = false, "unreadable spell cost" end
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
	if not trackedCostsKnown then return nil end

	UpdateTrackedManaRegen()

	if trackedMana == nil or not trackedManaMax or trackedManaMax <= 0 then
		return nil
	end

	return math.max(0, math.min(100, trackedMana / trackedManaMax * 100))
end

local function ReadCurrentManaPercent()
	local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

	if type(UnitPowerPercent) == "function"
		and CurveConstants
		and CurveConstants.ScaleTo100
	then
		local ok, pct = pcall(
			UnitPowerPercent,
			"player",
			powerType,
			false,
			CurveConstants.ScaleTo100
		)

		pct = ok and ReadableNumber(pct) or nil
		if pct ~= nil then
			return Percent(pct), "UnitPowerPercent"
		end
	end

	if type(UnitPower) == "function" and type(UnitPowerMax) == "function" then
		local okC, current = pcall(UnitPower, "player", powerType)
		local okM, maximum = pcall(UnitPowerMax, "player", powerType)

		current = okC and ReadableNumber(current) or nil
		maximum = okM and ReadableNumber(maximum) or nil

		if current ~= nil and maximum ~= nil and maximum > 0 then
			return current >= 0 and Percent(current / maximum * 100) or nil,
				"UnitPower/Max"
		end
	end
end

local function RefreshManaSensor()
	manaEventCount = manaEventCount + 1

	local pct, source = ReadCurrentManaPercent()
	if pct == nil then return end

	eventManaPct = pct
	eventManaSource = source or "event mana"
	eventManaAt = GetTime()

	if EnsureTrackedMana() and trackedManaMax then
		trackedCostsKnown = true
		trackedMana = trackedManaMax * pct / 100
		trackedManaUpdatedAt = GetTime()
		trackedSource = "event mana resync"
	end
end


local function Enabled(s, key)
    local value = Bool(s and s[key])
    if value == nil then return M.defaults[key] == true end
    return value
end

local function LiveManaPercent()
    local pct, source = ReadCurrentManaPercent()
    pct = Percent(pct)
    if pct ~= nil then return pct, source end
    pct = Percent((SafeCall(AL.ManaPercent)))
    if pct ~= nil then return pct, "AL.ManaPercent" end
end

local function GateManaPercent()
    local pct, source = LiveManaPercent()
    if pct ~= nil then
        if EnsureTrackedMana() then
            trackedCostsKnown = true
            trackedMana = trackedManaMax * pct / 100
            trackedManaUpdatedAt, trackedSource = GetTime(), "readable mana"
        end
        lastManaSource = source
        return pct
    end
    -- Native percentages remain opaque to Lua. Their display curves take
    -- priority over the estimate, including after drinking or Evocation.
    if CurveAvailable("power", "player", 0) then lastManaSource = "native protected mana"; return nil end
    pct = Percent(TrackedManaPercent())
    lastManaSource = pct ~= nil and "tracked estimate" or "unreadable"
    return pct
end

local function ManaAmount()
    local amount = Number((SafeCall(UnitPower, "player", 0)))
    if amount and amount >= 0 then return amount end
    local pct = LiveManaPercent()
    local maximum = ReadManaMaximum()
    if pct and maximum then return pct * maximum / 100 end
    if not CurveAvailable("power", "player", 0) then
        UpdateTrackedManaRegen()
        if trackedCostsKnown then return trackedMana end
    end
end

local function ManaGate(value, threshold, below, strict)
    if value ~= nil and math.abs(value - threshold) < 1e-7 then value = threshold end
    if value ~= nil then
        if below then return strict and value < threshold or not strict and value <= threshold end
        return strict and value > threshold or not strict and value >= threshold
    end
    if not below and not strict and threshold <= 0 then return true end
    if not CurveAvailable("power", "player", 0) then return false end
    local cut = threshold / 100
    if below and not strict or not below and strict then cut = NextFloat32(cut) end
    return { axis = "mana", kind = "power", unit = "player", powerType = 0, cut = cut, below = below }
end

local function Affordable(name, usable, shortage)
    if shortage == true then return false end
    local cost = SpellManaCost(name)
    if cost == nil then return usable == true end
    if cost <= 0 then return true end
    local amount = ManaAmount()
    if amount ~= nil then return amount >= cost end
    local maximum = ReadManaMaximum()
    if maximum and CurveAvailable("power", "player", 0) then
        if cost > maximum then return false end
        return { axis = "mana", kind = "power", unit = "player", powerType = 0, cut = cost / maximum, below = false }
    end
    return usable == true
end

local function ObserveCooldowns()
    local observed = {}
    for _, entry in ipairs(M.spells) do
        local name = entry[2]
        local info = SafeCall(C_Spell and C_Spell.GetSpellCooldown, LearnedID(name) or name)
        if SafeValue(info) and type(info) == "table" then
            observed[name] = { active=Bool(info.isActive), enabled=Bool(info.isEnabled), onGCD=Bool(info.isOnGCD) }
        end
    end
    cooldownSnapshots = observed
end

local function CooldownState(name)
    local info = SafeCall(C_Spell and C_Spell.GetSpellCooldown, LearnedID(name) or name)
    if not SafeValue(info) or type(info) ~= "table" then return end
    local active, enabled = Bool(info.isActive), Bool(info.isEnabled)
    local observed = cooldownSnapshots[name]
    -- isOnGCD is reliable only inside SPELL_UPDATE_COOLDOWN. Never use a
    -- polled GCD flag to override a real spell cooldown.
    local onGCD
    if observed and observed.active == active and observed.enabled == enabled then onGCD = observed.onGCD end
    local start, duration = Number(info.startTime), Number(info.duration)
    local recovery = active == true and onGCD == true
    if active ~= false and onGCD == nil and start and duration and duration > 0 and duration <= 1.5 then
        recovery = start > 0 and start + duration > GetTime()
        if recovery then onGCD = true end
    end
    return active, onGCD, enabled, recovery
end

local function SpellReady(name)
    local active, onGCD, enabled, recovery = CooldownState(name)
    if enabled == false then return false, recovery end
    if active == true and onGCD ~= true then return false, recovery end
    if active == false or active == true and onGCD == true then return true, recovery end
    return Bool((SafeCall(AL.IsReady, name))) == true, recovery
end

local WAND_HANDOFF_SPELLS = { ["Fire Blast"]=true, ["Frost Nova"]=true, ["Frostbolt"]=true, ["Fireball"]=true, ["Scorch"]=true }

local function Offer(name, reason, gates, preparation, showRange)
    if not Ok(name) then return false end
    local ready, recovery = SpellReady(name)
    if not ready then return false end
    local usable, shortage = SpellUsability(name)
    if usable == false or shortage == true then return false end
    if not showRange and Bool((SafeCall(AL.InRange, name))) == false then return false end
    local conditions = {}
    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
    local affordable = Affordable(name, usable, shortage)
    if preparation and ManaAmount() == nil and usable == true and shortage == false then affordable = true end
    conditions[#conditions + 1] = affordable
    if WAND_HANDOFF_SPELLS[name] then
        if LiveWandActive() and Ok("Shoot") then
            local canStop = type(AL.WandReady) ~= "function" or AL.WandReady(true)
            if not canStop or GetTime() < wandStopPendingUntil then return AddAction(nil, "Stopping wand", conditions) end
            return AddAction("Shoot", "Stop wand for " .. name, conditions)
        end
        -- Shoot recovery may be absent from the spell's cooldown data. Use a
        -- 1.5 s fallback after an accepted shot before offering an instant.
        local shotRecovery = type(AL.WandRecoveryRemaining) == "function" and AL.WandRecoveryRemaining() > 0
            or type(AL.WandRecoveryRemaining) ~= "function" and GetTime() < wandRecoveryUntil
        if recovery or shotRecovery then return AddAction(nil, "Global cooldown", conditions) end
    end
    return AddAction(name, reason, conditions)
end

local function PlayerMoving()
    local speed = Number((SafeCall(GetUnitSpeed, "player")))
    if speed ~= nil then return speed > 0 end
    local player = A and SafeValue(A.Player) and A.Player
    if type(player) == "table" then
        local value = SafeCall(player.IsMoving, player)
        local moving = Bool(value)
        if moving ~= nil then return moving end
        local numeric = Number(value)
        if numeric ~= nil then return numeric > 0 end
    end
    -- Protected speed is unknown, not proof of movement. Movement events
    -- remain useful when neither the speed nor framework reader is public.
    return movementEventActive == true
end

local function PlayerIsCastingOrChanneling()
    local player = A and SafeValue(A.Player) and A.Player
    if type(player) == "table" then
        for _, reader in pairs({ player.IsCasting, player.IsChanneling }) do
            local value = SafeCall(reader, player)
            if not SafeValue(value) or value == true
                or (type(value) == "string" and value ~= "")
                or (Number(value) and Number(value) > 0) then return true end
        end
    end
    for _, reader in pairs({ UnitCastingInfo, UnitChannelInfo }) do
        local name = SafeCall(reader, "player")
        if not SafeValue(name) or name ~= nil then return true end
    end
    local name = SafeCall(AL.CastingSpell)
    if name == "Shoot" and type(AL.WandCasting) == "function" then return AL.WandCasting() end
    return SafeValue(name) and type(name) == "string"
end

LiveWandActive = function()
    if type(AL.WandAutoRepeatActive) == "function" then return AL.WandAutoRepeatActive() end
    local id = LearnedID("Shoot") or 5019
    local active = Bool((SafeCall(IsAutoRepeatSpell, id)))
    if active == nil then active = Bool((SafeCall(C_Spell and C_Spell.IsAutoRepeatSpell, id))) end
    if active ~= nil then
        -- Live stopped state must clear stale START_AUTOREPEAT events.
        wandEventActive = active
        return active
    end
    local player = A and SafeValue(A.Player) and A.Player
    if type(player) == "table" then
        active = Bool((SafeCall(player.IsShooting, player)))
        if active ~= nil then wandEventActive = active; return active end
    end
    active = Bool((SafeCall(IsCurrentSpell, id)))
    if active == nil then active = Bool((SafeCall(C_Spell and C_Spell.IsCurrentSpell, id))) end
    if active ~= nil then wandEventActive = active; return active end
    return wandEventActive
end

local function PlayerIsWanding()
    if type(AL.WandReady) == "function" then return not AL.WandReady() end
    if GetTime() < wandPendingUntil then return true end
    return LiveWandActive()
end

local function WandEligible(s)
    if not Enabled(s, "wand") or not Ok("Shoot") then return false end
    if type(GetInventoryItemID) ~= "function" then return Bool((SafeCall(AL.WandEquipped))) == true end
    for _, slot in ipairs({ 18, 16 }) do
        local id = Number((SafeCall(GetInventoryItemID, "player", slot)))
        if id and id > 0 then
            local class, subclass
            local readers = { C_Item and C_Item.GetItemInfoInstant, GetItemInfoInstant }
            for index = 1, 2 do
                local reader = readers[index]
                class, subclass = SafeCall(function()
                    if type(reader) ~= "function" then return end
                    local _, _, _, _, _, itemClass, itemSubclass = reader(id)
                    return itemClass, itemSubclass
                end)
                class, subclass = Number(class), Number(subclass)
                if class and subclass then break end
            end
            if class == 2 and subclass == 19 then return true end
            -- Legacy ranged-slot wands remain usable without item metadata.
            -- A main-hand weapon must positively identify as a wand.
            if slot == 18 and (not class or not subclass) then return true end
        end
    end
    return false
end

local function Wand(s, reason, gates, moving)
    if not WandEligible(s) then return false end
    if reason == "Out of mana" then
        for _, name in ipairs({ "Frostbolt", "Fireball", "Scorch" }) do
            if Ok(name) then
                local usable, shortage = SpellUsability(name)
                if shortage == false then
                    local conditions = {}
                    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
                    conditions[#conditions + 1] = Affordable(name, usable, shortage)
                    if AddAction(nil, "Waiting for spell readiness", conditions) then return true end
                end
            end
        end
    end
    if moving then return AddAction(nil, "Stop moving to wand", gates) end
    if type(AL.WandReady) == "function" then
        local ready, wait = AL.WandReady()
        if not ready then return AddAction(nil, wait, gates) end
    elseif PlayerIsWanding() then return AddAction(nil, "Wand active", gates) end
    if Bool((SafeCall(AL.InRange, "Shoot"))) == false then return AddAction(nil, "Wand out of range", gates) end
    local _, _, _, recovery = CooldownState("Shoot")
    if recovery then return AddAction(nil, "Global cooldown", gates) end
    return AddAction("Shoot", reason, gates)
end

local function WandManaThreshold(s) return SettingNumber(s, "wandMana", 25, 0, 95) end

local function DamageGates(s, mana, targetHP)
    if not WandEligible(s) then return {} end
    local gates = { ManaGate(mana, WandManaThreshold(s), false, true) }
    -- An unavailable target-health sensor cannot establish the finishing
    -- threshold. Continue the mana-based rotation instead of blocking nukes.
    if targetHP ~= nil or CurveAvailable("health", "target") then
        gates[#gates + 1] = HealthGate("target", targetHP, SettingNumber(s, "wandTargetHP", 20, 0, 80), false, true)
    end
    return gates
end

local function WandThresholds(s, mana, targetHP, moving)
    Wand(s, "Save mana", { ManaGate(mana, WandManaThreshold(s), true) }, moving)
    Wand(s, "Finish with wand", { HealthGate("target", targetHP, SettingNumber(s, "wandTargetHP", 20, 0, 80), true) }, moving)
end

local function UnitWithin(unit, radius)
    local distance, checked = SafeCall(UnitDistanceSquared, unit)
    distance = Number(distance)
    if distance and distance >= 0 and Bool(checked) ~= false then return distance <= radius * radius end
    local object = A and SafeCall(A.Unit, unit)
    if SafeValue(object) and (type(object) == "table" or type(object) == "userdata") then
        local range = Number((SafeCall(object.GetRange, object)))
        if range and range >= 0 then return range <= radius end
    end
    if radius >= 10 then return Bool((SafeCall(CheckInteractDistance, unit, 3))) end
end

local function EnemyCount(limit)
    local count
    local function Accept(value)
        value = Number(value)
        if value and value >= 0 and value <= 40 and value == math.floor(value) then count = math.max(count or 0, value) end
    end
    Accept((SafeCall(AL.EnemyCount, 10)))
    if A and A.MultiUnits then
        Accept((SafeCall(A.MultiUnits.GetByRangeInCombat, A.MultiUnits, 10, limit or 8)))
        Accept((SafeCall(A.MultiUnits.GetActiveEnemies, A.MultiUnits, 10)))
    end
    local seen, visible = {}, 0
    local function Count(unit)
        if not SafeValue(unit) or type(unit) ~= "string" then return end
        if Bool((SafeCall(UnitExists, unit))) ~= true or Bool((SafeCall(UnitCanAttack, "player", unit))) ~= true
            or Bool((SafeCall(UnitIsDeadOrGhost, unit))) ~= false or Bool((SafeCall(UnitAffectingCombat, unit))) ~= true then return end
        local guid = SafeCall(UnitGUID, unit)
        if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] or UnitWithin(unit, 10) ~= true then return end
        seen[guid], visible = true, visible + 1
    end
    Count("target")
    local plates = SafeCall(C_NamePlate and C_NamePlate.GetNamePlates)
    if SafeValue(plates) and type(plates) == "table" then
        for _, plate in pairs(plates) do
            if SafeValue(plate) and type(plate) == "table" then Count(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)) end
        end
    else
        for index = 1, 40 do Count("nameplate" .. index) end
    end
    if visible > 0 then count = math.max(count or 0, visible) end
    return count
end

local function TargetFrozen()
    return Bool((SafeCall(AL.TargetHasAnyDebuff, FROZEN_DEBUFFS))) == true
        or Bool((SafeCall(AL.HasBuff, "player", "Fingers of Frost"))) == true
end

local function NukeCandidates(s)
    local candidates, seen = {}, {}
    local function Add(name)
        if name and not seen[name] and (not Enabled(s, "primaryFire") or name ~= "Frostbolt") then
            seen[name], candidates[#candidates + 1] = true, name
        end
    end
    local names = { FROSTBOLT = "Frostbolt", FIREBALL = "Fireball", ARCANE_MISSILES = "Arcane Missiles", SCORCH = "Scorch" }
    if Enabled(s, "primaryFire") then
        Add("Fireball"); Add("Scorch"); Add("Arcane Missiles")
    else
        local selected = SettingChoice(s, "nuke", { AUTO=true,FROSTBOLT=true,FIREBALL=true,ARCANE_MISSILES=true,SCORCH=true }, "AUTO")
        Add(names[selected]); Add("Frostbolt"); Add("Fireball"); Add("Arcane Missiles"); Add("Scorch")
    end
    return candidates
end

local function PrimaryNuke(s)
    for _, name in ipairs(NukeCandidates(s)) do if Ok(name) then return name end end
end

local function Preparation(s)
    if Enabled(s, "buffs") then
        if not AL.HasBuff("player", "Arcane Intellect") then Offer("Arcane Intellect", "Intellect", nil, true) end
        local hasArmor
        for _, name in ipairs(ARMORS) do if AL.HasBuff("player", name) then hasArmor = true; break end end
        if not hasArmor then
            for _, name in ipairs(ARMORS) do if Ok(name) then Offer(name, "Armor", nil, true); break end end
        end
    end
    if Enabled(s, "conjure") then
        for _, entry in ipairs({ { "Conjure Water", WATER_IDS }, { "Conjure Food", FOOD_IDS }, { "Conjure Mana Agate", GEM_IDS } }) do
            local reader = GetItemCount or (C_Item and C_Item.GetItemCount)
            local count = 0
            for _, id in ipairs(entry[2]) do
                local value = Number((SafeCall(reader, id)))
                if not value or value < 0 then count = nil; break end
                count = count + value
            end
            if count == 0 and GetTime() >= (conjureLocks[entry[1]] or 0) then Offer(entry[1], "Conjure supplies", nil, true) end
        end
    end
end

local function RecoverMana(s, mana, moving, inCombat, hostile)
    if Enabled(s, "evocation") and not moving and (not inCombat or not hostile or UnitWithin("target", 10) == false) then
        Offer("Evocation", "Restore mana", { ManaGate(mana, SettingNumber(s, "evocationMana", 15, 0, 60), true) })
    end
end

local function Defense(s, hostile, hp, mana)
    if Enabled(s, "iceblock") and not AL.HasBuff("player", "Ice Block") then
        Offer("Ice Block", "Emergency", { HealthGate("player", hp, SettingNumber(s, "iceBlockHP", 18, 1, 60), true) })
    end
    if hostile and Enabled(s, "cspell") and Bool((SafeCall(AL.TargetCasting))) == true then Offer("Counterspell", "Interrupt") end
    if Enabled(s, "manaShield") and not AL.HasBuff("player", "Mana Shield") then
        Offer("Mana Shield", "Defense", {
            HealthGate("player", hp, SettingNumber(s, "manaShieldHP", 45, 5, 90), true),
            ManaGate(mana, SettingNumber(s, "manaShieldMinMana", 25, 0, 100), false),
        })
    end
    if hostile and Enabled(s, "nova") and UnitWithin("target", 10) == true then Offer("Frost Nova", "Make distance") end
end

local function Offensive(s, inCombat, targetHP, mana, moving)
    WandThresholds(s, mana, targetHP, moving)
    local gates = DamageGates(s, mana, targetHP)
    if inCombat then
        if AL.burst then Offer("Berserking", "Burst", { HealthGate("target", targetHP,
            SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false) }) end
        local minimum = SettingNumber(s, "aoeMinEnemies", 3, 2, 8)
        local count = Enabled(s, "aoe") and EnemyCount(minimum)
        if count and count >= minimum then
            local aoeGates = {}
            for _, gate in ipairs(gates) do aoeGates[#aoeGates + 1] = gate end
            aoeGates[#aoeGates + 1] = ManaGate(mana, SettingNumber(s, "aoeMinMana", 35, 0, 100), false)
            if Enabled(s, "primaryFire") and not moving then Offer("Flamestrike", "Fire AoE", aoeGates) end
            if UnitWithin("target", 10) == true then
                Offer("Cone of Cold", "Close AoE", aoeGates)
                Offer("Arcane Explosion", "Close AoE", aoeGates)
            end
            if not moving then Offer("Blizzard", "Ranged AoE", aoeGates) end
        end
        if not Enabled(s, "primaryFire") and Enabled(s, "icelance") and TargetFrozen() then Offer("Ice Lance", "Frozen", gates) end
    end
    local clearcasting = AL.HasBuff("player", "Clearcasting")
    if Enabled(s, "fireblast") and (inCombat or moving) and (moving or Enabled(s, "primaryFire") or not clearcasting) then
        local fireGates = {}
        for _, gate in ipairs(gates) do fireGates[#fireGates + 1] = gate end
        fireGates[#fireGates + 1] = ManaGate(mana, SettingNumber(s, "fireBlastMinMana", 25, 0, 100), false)
        Offer("Fire Blast", moving and "Moving" or "On cooldown", fireGates)
    end
    if not moving then
        for _, name in ipairs(NukeCandidates(s)) do Offer(name, clearcasting and "Clearcast" or "Ranged damage", gates, false, true) end
        Wand(s, "Out of mana", nil, false)
    end
    AddAction(nil, moving and "Stop moving" or "Out of mana")
end

local mageDebug = {}

function M.NextSpell(s, inCombat, hostile)
    lastRotation = { at = GetTime(), actions = {} }
    local mana, moving = GateManaPercent(), PlayerMoving()
    local hp, targetHP = HealthPercent("player"), hostile and HealthPercent("target") or nil
    if PlayerIsCastingOrChanneling() then AddAction(nil, "Casting")
    else
        if inCombat then Defense(s, hostile, hp, mana) end
        RecoverMana(s, mana, moving, inCombat, hostile)
        if not inCombat then Preparation(s) end
        if hostile then Offensive(s, inCombat, targetHP, mana, moving) end
    end
    AddAction(nil, not hostile and inCombat and "No target" or "Ready")
    local base = lastRotation.actions[#lastRotation.actions]
    lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
    mageDebug = { mana=mana, manaSource=lastManaSource, threshold=WandManaThreshold(s),
        blocked=mana ~= nil and WandEligible(s) and mana <= WandManaThreshold(s) or nil,
        candidate=base.spell, candidateReason=base.reason, final=base.spell, finalReason=base.reason }
    return base.spell, base.reason
end

function M.CanTrackSuggestedSpell(name)
    if not lastRotation or GetTime() - lastRotation.at > 0.5 or lastRotation.visualCandidate then return false end
    local visual = AL.rotationSecretVisual
    if visual and GetTime() - visual.at <= 0.5 then return false end
    if name ~= lastRotation.baseSpell or not Ok(name) then return false end
    for _, entry in ipairs(M.spells) do if entry[2] == name then return true end end
    return name == "Berserking"
end

function M.OnTargetChanged() lastRotation, AL.rotationSecretVisual = nil, nil end

function M.RefreshManaCache()
    EnsureTrackedMana(); RefreshManaRegen(); RefreshManaSensor()
end

function M.OnManaCastSent(name)
    castSentCount = castSentCount + 1
    local pct = LiveManaPercent()
    if pct ~= nil and EnsureTrackedMana() then
        trackedCostsKnown = true
        trackedMana = trackedManaMax * pct / 100
        trackedManaUpdatedAt = GetTime()
    end
    lastSentCastName, lastSentCastAt = name, GetTime()
    if name then cooldownSnapshots[name] = nil end
    if name == "Shoot" and LiveWandActive() then wandStopPendingUntil = GetTime() + 0.5 end
    return { cost = name and SpellManaCost(name), at=GetTime() }
end

function M.OnManaCastSucceeded(name, id, guid, sent)
    castSucceededCount = castSucceededCount + 1
    lastSucceededCastName, lastSentCastName, lastSentCastAt = name, nil, 0
    if not name then return end
    if WAND_HANDOFF_SPELLS[name] then cooldownSnapshots[name] = nil end
    if id == nil then castFallbackCount = castFallbackCount + 1 end
    local pct = LiveManaPercent()
    if pct ~= nil and EnsureTrackedMana() then
        trackedCostsKnown = true
        trackedMana = trackedManaMax * pct / 100
        trackedManaUpdatedAt, trackedSource = GetTime(), "successful-cast readable mana"
        trackedLastSpell, trackedLastCost = name, (sent and sent.mana and sent.mana.cost) or SpellManaCost(name) or 0
    else
        SpendTrackedMana(name, sent and sent.mana and sent.mana.cost)
    end
end

function M.OnCastResult(name, result)
    if result == "UNIT_SPELLCAST_SUCCEEDED" then
        if name == "Shoot" then
            wandPendingUntil = GetTime() + 0.5
            wandRecoveryUntil = GetTime() + 1.5
        end
        if name == "Conjure Water" or name == "Conjure Food" or name == "Conjure Mana Agate" then conjureLocks[name] = GetTime() + 1.5 end
    elseif result == "UNIT_SPELLCAST_FAILED" or result == "UNIT_SPELLCAST_FAILED_QUIET" or result == "UNIT_SPELLCAST_INTERRUPTED" then
        lastSentCastName, lastSentCastAt = nil, 0
        if name == "Shoot" then wandPendingUntil = 0 end
    end
end

local tracker = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_DEAD", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(tracker.RegisterEvent, tracker, event)
end
tracker:SetScript("OnEvent", function(_, event, unit, token)
    if event == "SPELL_UPDATE_COOLDOWN" then ObserveCooldowns()
    elseif event == "SPELLS_CHANGED" then cooldownSnapshots = {}
    elseif event == "PLAYER_STARTED_MOVING" then movementEventActive = true
    elseif event == "PLAYER_STOPPED_MOVING" then movementEventActive = false
    elseif event == "START_AUTOREPEAT_SPELL" then wandEventActive, wandPendingUntil = true, GetTime()+0.5
    elseif event == "STOP_AUTOREPEAT_SPELL" then wandEventActive, wandPendingUntil, wandStopPendingUntil = false, 0, 0
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
        trackedCostsKnown = true
        trackedMana, trackedManaMax, trackedManaUpdatedAt, trackedLastSpendAt = nil, nil, nil, nil
        trackedLastSpell, trackedLastCost, trackedSource = nil, 0, "uninitialized"
        eventManaPct, eventManaAt, eventManaSource = nil, nil, "unreadable"
        wandEventActive, wandPendingUntil, conjureLocks, curveFailures = false, 0, {}, {}
        movementEventActive, curveCapabilities, visibilityCurves = nil, {}, {}
        wandStopPendingUntil = 0
        wandRecoveryUntil = 0
        cooldownSnapshots = {}
        lastSentCastName, lastSentCastAt, lastRotation, AL.rotationSecretVisual = nil, 0, nil, nil
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        M.RefreshManaCache()
    elseif SafeValue(unit) and unit == "player" and (not SafeValue(token) or token == nil or token == "MANA") then
        RefreshManaSensor()
    end
end)

function M.GetUIState()
    local s = AL.S()
    return { nuke=PrimaryNuke(s), primaryFire=Enabled(s,"primaryFire"),
        mana=GateManaPercent(), manaSource=lastManaSource, wandThreshold=WandManaThreshold(s),
        moving=PlayerMoving(), enemyCount=Enabled(s,"aoe") and EnemyCount(SettingNumber(s,"aoeMinEnemies",3,2,8)) or nil,
        fireEnemyCount=Enabled(s,"primaryFire") and EnemyCount(8) or nil, wanding=PlayerIsWanding() }
end

function M.ManaGateState()
    local s = AL.S(); local mana = GateManaPercent()
    return { mana=mana, source=lastManaSource, threshold=WandManaThreshold(s), blocked=mageDebug.blocked,
        trackedPct=TrackedManaPercent(), trackedMana=trackedMana, trackedManaMax=trackedManaMax, trackedSource=trackedSource,
        lastSpell=trackedLastSpell, lastCost=trackedLastCost, eventManaPct=eventManaPct, eventManaSource=eventManaSource,
        eventManaAge=eventManaAt and GetTime()-eventManaAt, manaEventCount=manaEventCount,
        castSentCount=castSentCount, castSucceededCount=castSucceededCount, castFallbackCount=castFallbackCount,
        lastSentCastName=lastSentCastName, lastSucceededCastName=lastSucceededCastName,
        candidate=mageDebug.candidate, candidateReason=mageDebug.candidateReason, final=mageDebug.final, finalReason=mageDebug.finalReason }
end
function M.ManaPercent() return GateManaPercent(), lastManaSource, TrackedManaPercent() end
function M.DecisionDebugState() return mageDebug end

IntervalCurve = function(low, high)
	local factory = C_CurveUtil.CreateColorCurve
	if visibilityCurveFactory ~= factory then
		visibilityCurves, visibilityCurveFactory = {}, factory
	end
	local key = tostring(low) .. ":" .. tostring(high)
	if visibilityCurves[key] then return visibilityCurves[key] end
	local curve = factory()
	curve:SetType(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	curve:AddPoint(0, CreateColor(1, 1, 1, low == 0 and 1 or 0))
	if low > 0 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
	if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
	if low ~= 1 and high ~= 1 then curve:AddPoint(1, CreateColor(1, 1, 1, high > 1 and 1 or 0)) end
	visibilityCurves[key] = curve
	return curve
end

ReadVisualAlpha = function(mask)
    local curve = IntervalCurve(mask.low, mask.high)
    local color
    if mask.kind == "power" then color = UnitPowerPercent(mask.unit, mask.powerType, false, curve)
    else color = UnitHealthPercent(mask.unit, false, curve) end
    local _, _, _, alpha = color:GetRGBA()
    if SafeValue(alpha) and Number(alpha) == nil then error("Mage resource curve returned no display alpha") end
    return alpha
end

function M.SecretVisualPlan(spell, reason)
	local d = lastRotation
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
	d.visualPlan = plan
	return plan
end

function M.EvaluateVisualMasks(plan)
	local values = {}
	local ok = pcall(function()
		for key, mask in pairs(plan.masks) do
			local success, value = pcall(ReadVisualAlpha, mask)
			if not success then
				curveFailures[mask.kind .. ":" .. mask.unit .. ":" .. tostring(mask.powerType or "")] = {
					reader = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent,
					factory = C_CurveUtil and C_CurveUtil.CreateColorCurve }
				error("Mage resource curve unavailable")
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
                curveFailures[mask.kind .. ":" .. mask.unit .. ":" .. tostring(mask.powerType or "")] = {
                    reader = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent,
                    factory = C_CurveUtil and C_CurveUtil.CreateColorCurve }
                error("Mage resource alpha unavailable")
            end
        else node:SetAlpha(1) end
	end
end




AL.RegisterRotation("MAGE", M)
-- END ORIGINAL LEVELING IMPLEMENTATION
    end)(ADDON, RotationScope(true))

    ;(function(...)
-- BEGIN OPTIONAL TALENT BUILD IMPLEMENTATION
local ADDON, AL = ...

-- WoW Forever Mage leveling 1-60 - v0.20.4 (Frost, Fire, Arcane, Frostfire)
-- Live MythicSim tier preset, Forever engine 944a791060db (1.60.1.70338).
-- Classic IDs and levels are only LIKELY references;
-- the client's spellbook remains authoritative. The learned rank's exact range controls
-- red/normal coloring; it does not replace the damage spell with a melee attack.

local A = _G.Action

local M = {
	defaults = {
        leveling = true,
		frost = false,
		frostMissiles = true, frostFireBlast = true,
		frostColdSnap = true, frostEureka = true, frostBerserking = true,
		frostBurstMinMana = 40,
		frostBlizzard = true, frostBlizzardMinEnemies = 4,
		frostCone = true, frostExplosion = false,
		frostBarrier = true, frostBarrierHP = 70, frostBarrierMinMana = 25,
		fire = false,
		fireScorch = true, firePyroblast = true, fireMissiles = true, fireClearcasting = true,
		fireCombustion = true, fireEureka = true, fireBerserking = true,
		fireBurstMinMana = 40, fireFlamestrike = true, fireBlizzard = true,
		frostfire = false,
		frostfireBolt = true,
		frostfireScorch = true,
		frostfirePyroblast = true,
		frostfireEureka = true,
		frostfireBerserking = true,
		frostfireBurstMinMana = 40,
		frostfireFlamestrike = true,
		frostfireBlizzard = true,
		arcane = false,
		arcaneBlast = true, arcaneWrath = true, frostBlast = false, frostWinterChill = true,
		arcaneMissiles = true,
		arcanePower = true,
		presenceOfMind = true,
		arcanePyroblast = true,
		arcaneEureka = true,
		arcaneBerserking = true,
		arcaneBlizzard = false,
		arcaneThreeMana = 30,
		arcaneTwoMana = 20,
		arcaneBurstMinMana = 40,
		nuke = "AUTO",
		primaryFire = false,
		buffs = true,
		conjure = true,
		drink = true,
		drinkMana = 35,
		evocation = true,
		evocationMana = 15,
		wand = true,
		wandMana = 25,
		wandTargetHP = 20,
		nova = true,
		fireblast = true,
		fireBlastMinMana = 25,
		icelance = true,
		cspell = true,
		iceblock = true,
		iceBlockHP = 18,
		manaShield = false,
		manaShieldHP = 45,
		manaShieldMinMana = 25,
		aoe = false,
		aoeMinEnemies = 3,
		aoeMinMana = 35,
		burstMinTargetHP = 40,
	},
}

-- Classic rank-one IDs used for identification and icons.
-- Only the live spellbook grants learned status; Ice Lance uses Forever's
-- rank-one identity. Older IDs remain accepted for cast-event compatibility.
-- Exactly one rotation stays selected. Leveling is the default and the
-- fallback when a selected specialization is switched off or saved flags
-- conflict. A valid saved specialization takes priority during migration.
M.buildKeys = { "leveling", "frost", "fire", "frostfire", "arcane" }
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
    s = s or AL.Profile("MAGE")
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
	{ 1008, "Amplify Magic" },
	{ 400574, "Arcane Blast" },
	{ 0, "Arcane Wrath" },
	{ 0, "Frost Blast" },
	{ 1449, "Arcane Explosion" },
	{ 1459, "Arcane Intellect" },
	{ 5143, "Arcane Missiles" },
	{ 12042, "Arcane Power" },
	{ 20554, "Berserking" },
	{ 1953, "Blink" },
	{ 10, "Blizzard" },
	{ 12472, "Cold Snap" },
	{ 11129, "Combustion" },
	{ 120, "Cone of Cold" },
	{ 587, "Conjure Food" },
	{ 759, "Conjure Mana Agate" },
	{ 5504, "Conjure Water" },
	{ 2139, "Counterspell" },
	{ 604, "Dampen Magic" },
	{ 2855, "Detect Magic" },
	{ 1259817, "Eureka!" },
	{ 12051, "Evocation" },
	{ 2136, "Fire Blast" },
	{ 543, "Fire Ward" },
	{ 133, "Fireball" },
	{ 2120, "Flamestrike" },
	{ 168, "Frost Armor" },
	{ 122, "Frost Nova" },
	{ 6143, "Frost Ward" },
	{ 401502, "Frostfire Bolt" },
	{ 116, "Frostbolt" },
	{ 7302, "Ice Armor" },
	{ 11426, "Ice Barrier" },
	{ 11958, "Ice Block" },
	{ 1312002, "Ice Lance" },
	{ 6117, "Mage Armor" },
	{ 1463, "Mana Shield" },
	{ 118, "Polymorph" },
	{ 12043, "Presence of Mind" },
	{ 11366, "Pyroblast" },
	{ 475, "Remove Lesser Curse" },
	{ 2948, "Scorch" },
	{ 130, "Slow Fall" },
	{ 5019, "Shoot" },
}

AL.selfCastSpells = AL.selfCastSpells or {}
for _, name in ipairs({
	"Arcane Intellect", "Frost Armor", "Ice Armor", "Mage Armor",
	"Ice Block", "Mana Shield", "Evocation", "Conjure Water",
	"Conjure Food", "Conjure Mana Agate", "Berserking", "Frost Nova", "Arcane Explosion", "Cone of Cold",
	"Arcane Power", "Presence of Mind", "Eureka!", "Combustion", "Cold Snap", "Ice Barrier",
}) do
	AL.selfCastSpells[name] = true
end

-- Classic learning levels. Talents and spells not confirmed on
-- Forever are deliberately absent from this table and gated by the book.
local MINLEVEL = {
	["Frostfire Bolt"] = 40,
	["Arcane Blast"] = 20,
	["Frost Blast"] = 24,
	["Presence of Mind"] = 30,
	["Arcane Power"] = 40,
	["Pyroblast"] = 20,
	["Arcane Intellect"] = 1,
	["Fireball"] = 1,
	["Frost Armor"] = 1,
	["Conjure Water"] = 4,
	["Frostbolt"] = 4,
	["Conjure Food"] = 6,
	["Fire Blast"] = 6,
	["Polymorph"] = 8,
	["Frost Nova"] = 10,
	["Dampen Magic"] = 12,
	["Arcane Explosion"] = 14,
	["Arcane Missiles"] = 16,
	["Flamestrike"] = 16,
	["Detect Magic"] = 18,
	["Remove Lesser Curse"] = 18,
	["Blink"] = 20,
	["Blizzard"] = 20,
	["Evocation"] = 20,
	["Fire Ward"] = 20,
	["Mana Shield"] = 20,
	["Counterspell"] = 24,
	["Cone of Cold"] = 26,
	["Conjure Mana Agate"] = 28,
	["Ice Armor"] = 30,
	["Mage Armor"] = 34,
	["Frost Ward"] = 22,
}

local Ok = select(1, AL.LevelGates(MINLEVEL))
M.minLevels = MINLEVEL

-- Classic conjured items, from lowest to highest rank. A protected
-- bag count returns nil and never causes a repeated-conjuring loop.
local WATER_IDS = { 5350, 2288, 2136, 3772, 8077, 8078, 8079 }
local FOOD_IDS = { 5349, 1113, 1114, 1487, 8075, 8076 }
local GEM_IDS = { 5514 }

local FROZEN_DEBUFFS = { "Frost Nova", "Frostbite" }
local ARMORS = { "Ice Armor", "Frost Armor", "Mage Armor" }

-- Shared native gates keep opaque percentages in native display alpha only.
local lastRotation
local visibilityCurves, curveFailures, curveCapabilities = {}, {}, {}
local IntervalCurve, ReadVisualAlpha
local curveProbe
local visibilityCurveFactory
local movementEventActive
local LiveWandActive
local wandStopPendingUntil = 0
local wandRecoveryUntil = 0
local cooldownSnapshots = {}
local wandEventActive, wandPendingUntil = false, 0
local conjureLocks = {}
local arcaneState = { charges=0, expires=0, barrage=0, pom=false }
local arcaneChanged, arcaneAuraCache, arcaneAurasBlocked = {}, nil, nil
local arcaneEnds, arcaneCastAt, arcaneRetry = {}, {}, {}
local ff = { heat=0, heatEnd=0, heatChanged=-math.huge, vuln=0, vulnEnd=0,
    vulnChanged=-math.huge, fof=0, fofEnd=0, changed={}, retry={}, ends={},
    pending={}, finished={}, seen={}, talents={} }
local fireState = { clearEnd=0, clearChanged=-math.huge, clearSerial=0, combustion=false,
    combustionChanged=-math.huge, crits=0, ends=0, at=-math.huge }
local frostState = { barrierEnd=0, barrierChanged=-math.huge, fofSerial=0 }
local FROST_COOLDOWNS = { ["Cold Snap"]=600, ["Ice Barrier"]=30,
    ["Frost Nova"]=25, ["Cone of Cold"]=10, ["Ice Block"]=300,
    ["Fire Blast"]=8, ["Ice Lance"]=8 }
local FROST_RESETTABLE = { ["Ice Barrier"]=true, ["Frost Nova"]=true,
    ["Cone of Cold"]=true, ["Ice Block"]=true, ["Frost Ward"]=true }
local ARCANE_COOLDOWNS = { ["Arcane Wrath"]=6, ["Arcane Power"]=180, ["Presence of Mind"]=180, ["Eureka!"]=120, ["Berserking"]=180 }
local ARCANE_CASTS = { ["Arcane Wrath"]={}, ["Frost Blast"]={},
    ["Cold Snap"]={12472}, ["Ice Barrier"]={11426,13031,13032,13033},
    ["Ice Block"]={11958}, ["Frost Ward"]={6143,8461,8462,10177,28609},
    ["Combustion"]={11129},
    ["Frostfire Bolt"]={401502,1237312,1237313},
    ["Arcane Blast"]={400574,1239696,1239697,1239699,1239700},
    ["Arcane Missiles"]={5143,5144,5145,8416,8417,10211,10212,25345},
    ["Arcane Power"]={12042}, ["Presence of Mind"]={12043}, ["Eureka!"]={1259817}, ["Berserking"]={20554,26297},
    ["Pyroblast"]={11366,12505,12522,12523,12524,12525,12526,18809},
    ["Frostbolt"]={116,205,837,7322,8406,8407,8408,10179,10180,10181,25304},
    ["Fireball"]={133,143,145,3140,8400,8401,8402,10148,10149,10150,10151,25306},
    ["Scorch"]={2948,8444,8445,8446,10205,10206,10207},
    ["Fire Blast"]={2136,2137,2138,8412,8413,10197,10199},
    ["Frost Nova"]={122,865,6131,10230}, ["Ice Lance"]={1312002,400640,1240044,1240045,1240046,1240047,30455,42913,42914},
    ["Arcane Explosion"]={1449,8437,8438,8439,10201,10202},
    ["Cone of Cold"]={120,8492,10159,10160,10161}, ["Blizzard"]={10,6141,8427,10185,10186,10187},
    ["Flamestrike"]={2120,2121,8422,8423,10215,10216},
}
local ARCANE_DAMAGE = { ["Arcane Wrath"]=true, ["Frost Blast"]=true, ["Arcane Blast"]=true, ["Arcane Missiles"]=true, ["Pyroblast"]=true,
    ["Frostfire Bolt"]=true,
    ["Frostbolt"]=true, ["Fireball"]=true, ["Scorch"]=true, ["Fire Blast"]=true, ["Frost Nova"]=true,
    ["Arcane Explosion"]=true, ["Cone of Cold"]=true, ["Blizzard"]=true, ["Flamestrike"]=true, ["Ice Lance"]=true }
local POM_CASTS = { ["Arcane Wrath"]=true, ["Frost Blast"]=true, ["Arcane Blast"]=true, ["Pyroblast"]=true, ["Frostbolt"]=true,
    ["Frostfire Bolt"]=true,
    ["Fireball"]=true, ["Scorch"]=true, ["Flamestrike"]=true,
    ["Conjure Water"]=true, ["Conjure Food"]=true, ["Conjure Mana Agate"]=true }
local function SafeValue(value)
    return not (issecretvalue and issecretvalue(value))
end
local function ReadableNumber(value)
    if not SafeValue(value) or type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then return nil end
    return value
end
local Number = ReadableNumber
local function SafeCall(reader, ...)
    if type(reader) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(reader, ...)
    if ok then return a, b, c, d end
end
local function Bool(value)
    if SafeValue(value) and type(value) == "boolean" then return value end
end
local function Percent(value)
    value = Number(value)
    if value and value >= 0 and value <= 100 then return value end
end
local function LearnedID(name)
    local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
    return ref and Number(ref.id)
end

local function ArcaneCastName(id)
    id=Number(id)
    if not id then return end
    for name,ids in pairs(ARCANE_CASTS) do
        if id==LearnedID(name) then return name end
        for _,castID in ipairs(ids) do if id==castID then return name end end
    end
    for name in pairs(POM_CASTS) do if id==LearnedID(name) then return name end end
end
local function NativeArcaneEnd(name)
    local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,LearnedID(name) or name)
    if not SafeValue(info) or type(info)~="table" then return end
    local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate)
    if SafeValue(info.modRate) and info.modRate==nil then rate=1 end
    if start and start>0 and duration and duration>1.5 and rate and rate>0 then return start+duration/rate end
end
local function StartArcaneCooldown(name)
    local duration=ARCANE_COOLDOWNS[name]
    if not duration then return end
    local ms=Number((SafeCall(C_Spell and C_Spell.GetSpellBaseCooldown or GetSpellBaseCooldown,LearnedID(name) or name)))
    if ms and ms>1500 and ms<=3600000 then duration=ms/1000 end
    arcaneEnds[name],arcaneCastAt[name]=NativeArcaneEnd(name) or GetTime()+duration,GetTime()
end
local function SpendPresence()
    if arcaneState.pom then
        arcaneState.pom=false;arcaneChanged.pom=GetTime();StartArcaneCooldown("Presence of Mind")
    end
end
local function ReadArcaneState()
    local now=GetTime()
    if arcaneState.expires<=now then arcaneState.charges=0 end
    if arcaneAuraCache and now-arcaneAuraCache<0.15 then return arcaneState end
    arcaneAuraCache=now
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if arcaneAurasBlocked or type(reader)~="function" then return arcaneState end
    local found,complete={},false
    for index=1,40 do
        local ok,aura=pcall(reader,"player",index,"HELPFUL")
        if not ok or not SafeValue(aura) then arcaneAurasBlocked=true;return arcaneState end
        if aura==nil then complete=true;break end
        if type(aura)~="table" then return arcaneState end
        local id,name=Number(aura.spellId),aura.name
        if SafeValue(name) and type(name)=="string" then name=(AL.englishNames and AL.englishNames[name]) or name else name=nil end
        local key=(id==400573 or name=="Arcane Blast") and "charges"
            or (id==400589 or id==44404 or name=="Missile Barrage") and "barrage"
            or (id==12043 or name=="Presence of Mind") and "pom"
        if not id and not name then return arcaneState end
        if key then found[key]={stacks=Number(aura.applications),expires=Number(aura.expirationTime)} end
    end
    if not complete then return arcaneState end
    for _,key in ipairs({"charges","barrage","pom"}) do
        if not arcaneChanged[key] or now-arcaneChanged[key]>=0.5 then
            local aura=found[key]
            if key=="charges" then
                if not aura then arcaneState.charges,arcaneState.expires=0,0
                elseif aura.stacks and aura.stacks>=0 and aura.stacks<=4 then
                    arcaneState.charges=math.floor(aura.stacks)
                    if aura.expires and aura.expires>0 then arcaneState.expires=aura.expires
                    elseif arcaneState.expires<=now then arcaneState.expires=now+18 end
                end
            elseif key=="barrage" then
                if not aura then arcaneState.barrage=0
                elseif aura.expires and aura.expires>0 then arcaneState.barrage=aura.expires
                elseif arcaneState.barrage<=now then arcaneState.barrage=now+15 end
            elseif aura then arcaneState.pom=not aura.expires or aura.expires==0 or aura.expires>now
            elseif arcaneState.pom then SpendPresence() end
        end
    end
    if arcaneState.expires<=now then arcaneState.charges=0 end
    return arcaneState
end
local function SpellUsability(name)
    local usable, shortage = SafeCall(IsUsableSpell or (C_Spell and C_Spell.IsSpellUsable), LearnedID(name) or name)
    return Bool(usable), Bool(shortage)
end
local function HealthPercent(unit)
    if Bool((SafeCall(UnitExists, unit))) ~= true then return nil end
    local hp = Percent((SafeCall(AL.HealthPercent, unit)))
    if hp ~= nil then return hp end
    local scale = CurveConstants and CurveConstants.ScaleTo100
    local value = Number((SafeCall(UnitHealthPercent, unit, false, scale)))
    if value ~= nil then
        hp = Percent(scale and value or value * 100)
        if hp ~= nil then return hp end
    end
    local action = _G.Action
    local object = action and SafeCall(action.Unit, unit)
    if SafeValue(object) and (type(object) == "table" or type(object) == "userdata") then
        return Percent((SafeCall(object.HealthPercent, object)))
    end
end

local function CurveAvailable(kind, unit, powerType)
    unit = unit or "target"
    local reader = kind == "power" and UnitPowerPercent or UnitHealthPercent
    local key = kind .. ":" .. unit .. ":" .. tostring(powerType or "")
    local failure = curveFailures[key]
    local factory = C_CurveUtil and C_CurveUtil.CreateColorCurve
    if failure and failure.reader == reader and failure.factory == factory then return false end
    if type(factory) ~= "function" or type(CreateColor) ~= "function" or type(reader) ~= "function" then return false end
    local available = curveCapabilities[key]
    if available and available.reader == reader and available.factory == factory then return true end
    -- A present API can still reject a color curve in this client. Confirm
    -- that its result can reach a native display before relying on its gates.
    local ok = pcall(function()
        local alpha = ReadVisualAlpha({ kind=kind, unit=unit, powerType=powerType, low=0, high=0.5 })
        curveProbe = curveProbe or CreateFrame("Frame")
        curveProbe:Hide()
        curveProbe:SetAlpha(alpha)
    end)
    if not ok then
        curveFailures[key] = { reader=reader, factory=factory }
        return false
    end
    curveCapabilities[key] = { reader=reader, factory=factory }
    return true
end

local function NextFloat32(value)
    if value <= 0 then return 2 ^ -149 end
    local exponent = math.floor(math.log(value) / math.log(2))
    local step = 2 ^ (exponent - 23)
    return (math.floor(value / step + 0.5) + 1) * step
end

local function HealthGate(unit, value, threshold, below, strict)
    if value ~= nil then
        if math.abs(value - threshold) < 1e-7 then value = threshold end
        if below then return strict and value < threshold or not strict and value <= threshold end
        return strict and value > threshold or not strict and value >= threshold
    end
    if not below and threshold <= 0 then return true end
    if not CurveAvailable("health", unit) then return false end
    local cut = threshold / 100
    if below and not strict or not below and strict then cut = NextFloat32(cut) end
    return { axis = unit .. "HP", kind = "health", unit = unit, cut = cut, below = below }
end

local function AddAction(spell, reason, gates)
    local conditions = {}
    for _, gate in ipairs(gates or {}) do
        if gate == false then return false end
        if type(gate) == "table" then conditions[#conditions + 1] = gate end
    end
    local actions = lastRotation.actions
    if #actions > 0 and #actions[#actions].conditions == 0 then return false end
    actions[#actions + 1] = { spell = spell, reason = reason, conditions = conditions }
    if #conditions > 0 then lastRotation.visualCandidate = true end
    return true
end

local function SettingNumber(s, key, defaultValue, minValue, maxValue)
    local raw = s and s[key]
    local value = SafeValue(raw) and tonumber(raw) or nil
    value = Number(value) or defaultValue
    return math.max(minValue, math.min(maxValue, math.floor(value + 0.5)))
end


local function SettingChoice(s, key, allowed, defaultValue)
    local value = s and s[key]
    if SafeValue(value) and type(value) == "string" and allowed[value] then return value end
    return defaultValue
end

local trackedMana = nil
local trackedManaMax = nil
local trackedManaUpdatedAt = nil
local trackedLastSpendAt = nil
local trackedLastSpell = nil
local trackedLastCost = 0
local trackedSource = "uninitialized"
local trackedCostsKnown = true

local cachedBaseManaRegen = 0
local cachedCastingManaRegen = 0

local eventManaPct = nil
local eventManaSource = "unreadable"
local eventManaAt = nil
local manaEventCount = 0

local lastSentCastName = nil
local lastSentCastAt = 0
local castSentCount = 0
local castSucceededCount = 0
local castFallbackCount = 0
local lastSucceededCastName = nil

local lastManaSource = "unreadable"

local function ReadManaMaximum()
	local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

	if type(UnitPowerMax) == "function" then
		local ok, maximum = pcall(UnitPowerMax, "player", powerType)
		maximum = ok and ReadableNumber(maximum) or nil
		if maximum and maximum > 0 then return maximum end

		ok, maximum = pcall(UnitPowerMax, "player")
		maximum = ok and ReadableNumber(maximum) or nil
		if maximum and maximum > 0 then return maximum end
	end

	if type(AL.DebugPowerState) == "function" then
		local ok, state = pcall(AL.DebugPowerState)
		if ok and SafeValue(state) and type(state) == "table" then
			local maximum =
				ReadableNumber(state.typedMax)
				or ReadableNumber(state.primaryMax)
				or ReadableNumber(state.cachedMax)
			if maximum and maximum > 0 then return maximum end
		end
	end
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
			if trackedMana and trackedManaMax and trackedManaMax > 0 then
				local pct = trackedMana / trackedManaMax
				trackedMana = math.max(0, math.min(maximum, maximum * pct))
			end
			trackedManaMax = maximum
		end
	end

	if not trackedManaMax or trackedManaMax <= 0 then return false end

	if trackedMana == nil then
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
    local previous = trackedManaUpdatedAt or now
    local dt = math.max(0, now - previous)
    trackedManaUpdatedAt = now
    local castingTime = trackedLastSpendAt and math.max(0, math.min(now, trackedLastSpendAt + 5) - math.max(previous, trackedLastSpendAt)) or 0
    local gain = cachedCastingManaRegen * castingTime + cachedBaseManaRegen * (dt - castingTime)
    trackedMana = math.min(trackedManaMax, math.max(0, trackedMana + gain))
end

local function SpellManaCost(spellName)
	if type(spellName) ~= "string" or spellName == "" then return 0 end

	local identifiers = {}
	local seen = {}

	local function AddIdentifier(value)
		if not SafeValue(value) or value == nil or seen[value] then return end
		seen[value] = true
		identifiers[#identifiers + 1] = value
	end

	-- Prefer Core's exact learned-rank reference.
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[spellName]
	if SafeValue(ref) and type(ref) == "table" then AddIdentifier(ref.id) end

    AddIdentifier(spellName)
    if not (ref and ReadableNumber(ref.id)) then
        for _, def in ipairs(M.spells or {}) do if def[2] == spellName then AddIdentifier(def[1]); break end end
    end

	for _, identifier in ipairs(identifiers) do
		local costs

		if C_Spell and type(C_Spell.GetSpellPowerCost) == "function" then
			local ok, result = pcall(C_Spell.GetSpellPowerCost, identifier)
			if ok and SafeValue(result) and type(result) == "table" then costs = result end
		elseif type(GetSpellPowerCost) == "function" then
			local ok, result = pcall(GetSpellPowerCost, identifier)
			if ok and SafeValue(result) and type(result) == "table" then costs = result end
		end

		if costs then
			-- A readable empty cost list for this learned spell is a free cast.
			if next(costs) == nil then return 0, false end
			for _, info in ipairs(costs) do
				if SafeValue(info) and type(info) == "table" then
					local powerType = ReadableNumber(info.type)
					local token = SafeValue(info.name) and info.name or nil

					if powerType == 0 or token == "MANA" then
						local cost =
							ReadableNumber(info.cost)
							or ReadableNumber(info.minCost)

						if cost and cost >= 0 then return cost, true end

						-- A percentage alone cannot confirm the actual current
						-- mana cost. Wait for a numeric cost instead of inventing it.
					end
				end
			end
		end
	end

	return nil
end

local function SpendTrackedMana(spellName, sentCost)
	if not EnsureTrackedMana() then return end

	UpdateTrackedManaRegen()

	local cost = ReadableNumber(sentCost)
	if cost == nil or cost < 0 then cost = SpellManaCost(spellName) end
	if cost == nil then trackedCostsKnown, trackedSource = false, "unreadable spell cost" end
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
	if not trackedCostsKnown then return nil end

	UpdateTrackedManaRegen()

	if trackedMana == nil or not trackedManaMax or trackedManaMax <= 0 then
		return nil
	end

	return math.max(0, math.min(100, trackedMana / trackedManaMax * 100))
end

local function ReadCurrentManaPercent()
	local powerType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

	if type(UnitPowerPercent) == "function"
		and CurveConstants
		and CurveConstants.ScaleTo100
	then
		local ok, pct = pcall(
			UnitPowerPercent,
			"player",
			powerType,
			false,
			CurveConstants.ScaleTo100
		)

		pct = ok and ReadableNumber(pct) or nil
		if pct ~= nil then
			return Percent(pct), "UnitPowerPercent"
		end
	end

	if type(UnitPower) == "function" and type(UnitPowerMax) == "function" then
		local okC, current = pcall(UnitPower, "player", powerType)
		local okM, maximum = pcall(UnitPowerMax, "player", powerType)

		current = okC and ReadableNumber(current) or nil
		maximum = okM and ReadableNumber(maximum) or nil

		if current ~= nil and maximum ~= nil and maximum > 0 then
			return current >= 0 and Percent(current / maximum * 100) or nil,
				"UnitPower/Max"
		end
	end
end

local function RefreshManaSensor()
	manaEventCount = manaEventCount + 1

	local pct, source = ReadCurrentManaPercent()
	if pct == nil then return end

	eventManaPct = pct
	eventManaSource = source or "event mana"
	eventManaAt = GetTime()

	if EnsureTrackedMana() and trackedManaMax then
		trackedCostsKnown = true
		trackedMana = trackedManaMax * pct / 100
		trackedManaUpdatedAt = GetTime()
		trackedSource = "event mana resync"
	end
end


local function Enabled(s, key)
    local value = Bool(s and s[key])
    if value == nil then return M.defaults[key] == true end
    return value
end

local function LiveManaPercent()
    local pct, source = ReadCurrentManaPercent()
    pct = Percent(pct)
    if pct ~= nil then return pct, source end
    pct = Percent((SafeCall(AL.ManaPercent)))
    if pct ~= nil then return pct, "AL.ManaPercent" end
end

local function GateManaPercent()
    local pct, source = LiveManaPercent()
    if pct ~= nil then
        if EnsureTrackedMana() then
            trackedCostsKnown = true
            trackedMana = trackedManaMax * pct / 100
            trackedManaUpdatedAt, trackedSource = GetTime(), "readable mana"
        end
        lastManaSource = source
        return pct
    end
    -- Native percentages remain opaque to Lua. Their display curves take
    -- priority over the estimate, including after drinking or Evocation.
    if CurveAvailable("power", "player", 0) then lastManaSource = "native protected mana"; return nil end
    pct = Percent(TrackedManaPercent())
    lastManaSource = pct ~= nil and "tracked estimate" or "unreadable"
    return pct
end

local function ManaAmount()
    local amount = Number((SafeCall(UnitPower, "player", 0)))
    if amount and amount >= 0 then return amount end
    local pct = LiveManaPercent()
    local maximum = ReadManaMaximum()
    if pct and maximum then return pct * maximum / 100 end
    if not CurveAvailable("power", "player", 0) then
        UpdateTrackedManaRegen()
        if trackedCostsKnown then return trackedMana end
    end
end

local function ManaGate(value, threshold, below, strict)
    if value ~= nil and math.abs(value - threshold) < 1e-7 then value = threshold end
    if value ~= nil then
        if below then return strict and value < threshold or not strict and value <= threshold end
        return strict and value > threshold or not strict and value >= threshold
    end
    if not below and not strict and threshold <= 0 then return true end
    if not CurveAvailable("power", "player", 0) then return false end
    local cut = threshold / 100
    if below and not strict or not below and strict then cut = NextFloat32(cut) end
    return { axis = "mana", kind = "power", unit = "player", powerType = 0, cut = cut, below = below }
end

local function Affordable(name, usable, shortage)
    if shortage == true then return false end
    local cost = SpellManaCost(name)
    if cost == nil then return usable == true end
    if cost <= 0 then return true end
    local amount = ManaAmount()
    if amount ~= nil then return amount >= cost end
    local maximum = ReadManaMaximum()
    if maximum and CurveAvailable("power", "player", 0) then
        if cost > maximum then return false end
        return { axis = "mana", kind = "power", unit = "player", powerType = 0, cut = cost / maximum, below = false }
    end
    return usable == true
end

local function ObserveCooldowns()
    local observed = {}
    for _, entry in ipairs(M.spells) do
        local name = entry[2]
        local info = SafeCall(C_Spell and C_Spell.GetSpellCooldown, LearnedID(name) or name)
        if SafeValue(info) and type(info) == "table" then
            observed[name] = { active=Bool(info.isActive), enabled=Bool(info.isEnabled), onGCD=Bool(info.isOnGCD) }
        end
    end
    cooldownSnapshots = observed
end

local function CooldownState(name)
    local info = SafeCall(C_Spell and C_Spell.GetSpellCooldown, LearnedID(name) or name)
    if not SafeValue(info) or type(info) ~= "table" then return end
    local active, enabled = Bool(info.isActive), Bool(info.isEnabled)
    local observed = cooldownSnapshots[name]
    -- isOnGCD is reliable only inside SPELL_UPDATE_COOLDOWN. Never use a
    -- polled GCD flag to override a real spell cooldown.
    local onGCD
    if observed and observed.active == active and observed.enabled == enabled then onGCD = observed.onGCD end
    local start, duration = Number(info.startTime), Number(info.duration)
    local recovery = active == true and onGCD == true
    if active ~= false and onGCD == nil and start and duration and duration > 0 and duration <= 1.5 then
        recovery = start > 0 and start + duration > GetTime()
        if recovery then onGCD = true end
    end
    return active, onGCD, enabled, recovery
end

local function FrostfireTalent(name)
    if not ff.talentWarm then
        ff.talentWarm=true
        local localized={ ["Improved Scorch"]=SafeCall(C_Spell and C_Spell.GetSpellName,11095),
            ["Heating Up"]=SafeCall(C_Spell and C_Spell.GetSpellName,400624),
            ["Fingers of Frost"]=SafeCall(C_Spell and C_Spell.GetSpellName,400647) }
        for tab=1,3 do for index=1,40 do
            local ok,talent,_,_,_,rank=pcall(function()
                if type(GetTalentInfo)=="function" then return GetTalentInfo(tab,index,false,false) end
            end)
            rank=Number(rank)
            if ok and SafeValue(talent) and type(talent)=="string" and rank and rank>=0 then
                local canonical=(AL.englishNames and AL.englishNames[talent]) or talent
                for english,native in pairs(localized) do
                    if SafeValue(native) and type(native)=="string" and talent==native then canonical=english;break end
                end
                ff.talents[canonical]=rank
            end
        end end
    end
    return ff.talents[name]
end

-- These are personal player buffs in the Forever engine. Never borrow a
-- different mage's target debuff, or invent random crit/proc stacks.
local function ObserveFrostFingers(stacks,expires,signature)
    local now=GetTime()
    if signature and frostState.fofSignature==signature then return end
    stacks=Number(stacks)
    -- Positive aura presence proves one usable charge even if the count is
    -- hidden or reported as zero. It never grants an assumed second charge.
    if not stacks or stacks<1 or stacks>2 or stacks~=math.floor(stacks) then stacks=1 end
    expires=Number(expires)
    if not expires or expires<=0 then expires=ff.fofEnd>now and ff.fofEnd or now+15 end
    if expires<=now then return end
    if signature then
        local reported=stacks
        if frostState.fofReadCount and stacks<frostState.fofReadCount
            and expires<=(frostState.fofReadEnd or 0)+0.1 then
            -- A delayed native decrement acknowledges an earlier spend; it
            -- cannot restore a charge already consumed by a later cast.
            stacks=math.min(stacks,ff.fof)
        end
        frostState.fofReadCount,frostState.fofReadEnd=reported,expires
    end
    if stacks>ff.fof or ff.fofEnd<=now or expires>ff.fofEnd+0.1 then
        frostState.fofSerial=frostState.fofSerial+1
    end
    frostState.fofSignature=signature
    ff.fof,ff.fofEnd,ff.changed.fof=stacks,expires,now
end
local function FrostfireAuras()
    local now=GetTime()
    for _,key in ipairs({"heat","vuln","fof"}) do
        if ff[key.."End"]<=now then ff[key]=0 end
    end
    if ff.auraAt and now-ff.auraAt<0.15 then return ff end
    ff.auraAt=now
    ff.vulnReadable=false
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if ff.blocked or type(reader)~="function" then return ff end
    local found,complete={},false
    for index=1,40 do
        local ok,aura=pcall(reader,"player",index,"HELPFUL")
        if not ok or not SafeValue(aura) then ff.blocked=true;return ff end
        if aura==nil then complete=true;break end
        if type(aura)~="table" then return ff end
        local id,name=Number(aura.spellId),aura.name
        if SafeValue(name) and type(name)=="string" then name=(AL.englishNames and AL.englishNames[name]) or name else name=nil end
        if not id and not name then return ff end
        local key=(id==400625 or name=="Heating Up" or name=="Hot Streak") and "heat"
            or (id==22959 or name=="Fire Vulnerability") and "vuln"
            or (id==400669 or id==44544 or name=="Fingers of Frost") and "fof"
        if key then found[key]={stacks=Number(aura.applications),expires=Number(aura.expirationTime)} end
    end
    if not complete then return ff end
    ff.vulnReadable=not found.vuln or found.vuln.stacks~=nil
    if found.vuln and found.vuln.stacks then ff.vulnEvidenceAt=now end
    for _,key in ipairs({"heat","vuln","fof"}) do
        local changed=ff.changed[key] or -math.huge
        if key=="fof" and Enabled(AL.S(),"frost") then
            local aura=found.fof
            if aura then
                local signature=tostring(aura.stacks or "hidden")..":"..tostring(aura.expires or "hidden")
                ObserveFrostFingers(aura.stacks,aura.expires,signature)
            elseif now-changed>=0.5 then
                ff.fof,ff.fofEnd,frostState.fofSignature=0,0,nil
                frostState.fofReadCount,frostState.fofReadEnd=nil,nil
            end
        elseif now-changed>=0.5 then
            local aura=found[key]
            if not aura then ff[key],ff[key.."End"]=0,0
            else
                local cap=key=="vuln" and 5 or key=="heat" and 3 or 2
                if aura.stacks and aura.stacks>=0 and aura.stacks<=cap then
                    if key=="heat" and ff[key]~=math.floor(aura.stacks) then ff.heatAuraSerial=(ff.heatAuraSerial or 0)+1 end
                    ff[key]=math.floor(aura.stacks)
                end
                if aura.expires and aura.expires>0 then ff[key.."End"]=aura.expires
                elseif ff[key.."End"]==0 and ff[key]>0 then ff[key.."End"]=now+(key=="vuln" and 30 or key=="heat" and 20 or 15) end
                if ff[key.."End"]<=now then ff[key]=0 end
            end
        end
    end
    return ff
end

local function FrostfirePyroTime()
    local info=SafeCall(C_Spell and C_Spell.GetSpellInfo,LearnedID("Pyroblast") or "Pyroblast")
    if SafeValue(info) and type(info)=="table" then
        local value=Number(info.castTime)
        if value and value>=0 then return value end
    end
end

local function FinishFireCombustion()
    if not fireState.combustion then return end
    fireState.combustion,fireState.crits=false,0
    fireState.combustionChanged=GetTime()
    fireState.ends=NativeArcaneEnd("Combustion") or GetTime()+180
    -- Forever category 1151 is shared with Presence of Mind.
    arcaneEnds["Presence of Mind"]=math.max(arcaneEnds["Presence of Mind"] or 0,fireState.ends)
end
local function ReadFireBuffs()
    local now=GetTime()
    if fireState.auraAt and now-fireState.auraAt<0.15 then return fireState end
    fireState.auraAt=now
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not fireState.blocked and type(reader)=="function" then
        local found,complete={},false
        for index=1,40 do
            local ok,aura=pcall(reader,"player",index,"HELPFUL")
            if not ok or not SafeValue(aura) then fireState.blocked=true;break end
            if aura==nil then complete=true;break end
            if type(aura)~="table" then break end
            local id,name=Number(aura.spellId),aura.name
            if SafeValue(name) and type(name)=="string" then name=(AL.englishNames and AL.englishNames[name]) or name else name=nil end
            if not id and not name then break end
            if id==12536 or name=="Clearcasting" then found.clear={expires=Number(aura.expirationTime)} end
            if id==11129 or id==28682 or name=="Combustion" then found.combustion=true end
        end
        if now-fireState.clearChanged>=0.5 then
            if found.clear then
                local previous=fireState.clearEnd
                local expires=found.clear.expires
                if expires and expires>0 then fireState.clearEnd=expires
                elseif fireState.clearEnd==0 then fireState.clearEnd=now+15 end
                if previous<=now and fireState.clearEnd>now then fireState.clearSerial=fireState.clearSerial+1 end
            elseif complete then fireState.clearEnd=0 end
        end
        if now-fireState.combustionChanged>=0.5 then
            if found.combustion then
                if not fireState.combustion then fireState.crits=0 end
                fireState.combustion=true
            elseif complete then FinishFireCombustion() end
        end
    end
    -- A running real cooldown proves the indefinite buff has been consumed.
    local nativeEnd=NativeArcaneEnd("Combustion")
    if nativeEnd and nativeEnd>now and now-fireState.combustionChanged>=0.5 then
        FinishFireCombustion();fireState.ends=nativeEnd
    end
    return fireState
end
local function FireClearcasting()
    local state=ReadFireBuffs()
    if GetTime()-state.clearChanged<0.5 then return state.clearEnd>GetTime() end
    if state.clearEnd>GetTime() or Bool((SafeCall(AL.HasBuff,"player","Clearcasting")))==true then return true end
    local cost,explicit=SpellManaCost("Fireball")
    return explicit==true and cost==0
end
local function FireCombustionReady(active,onGCD,enabled)
    local state=ReadFireBuffs();local now=GetTime()
    if state.combustion or (ff.retry.Combustion or 0)>now or enabled==false then return false end
    local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,LearnedID("Combustion") or "Combustion")
    if SafeValue(info) and type(info)=="table" then
        local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate)
        if SafeValue(info.modRate) and info.modRate==nil then rate=1 end
        if start and start>=0 and duration and duration>=0 and rate and rate>0 then
            if onGCD==true and duration<=1.5 and state.ends>now then return false end
            return start==0 or duration<=1.5 or start+duration/rate<=now
        end
    end
    if active==true and onGCD~=true then return false end
    if active==false then return true end
    return state.ends<=now and (arcaneEnds["Presence of Mind"] or 0)<=now
end

local function FrostCooldownReady(name,active,onGCD,enabled,recovery)
    local now=GetTime()
    if enabled==false or (ff.retry[name] or 0)>now then return false end
    if FROST_RESETTABLE[name] and frostState.resetAt and now-frostState.resetAt<0.5
        and (ff.ends[name] or 0)<=now then return true end
    local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,LearnedID(name) or name)
    if SafeValue(info) and type(info)=="table" then
        local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate)
        if SafeValue(info.modRate) and info.modRate==nil then rate=1 end
        if start and start>=0 and duration and duration>=0 and rate and rate>0 then
            if (onGCD==true or recovery) and duration<=1.5 and (ff.ends[name] or 0)>now then return false end
            local ready=start==0 or duration<=1.5 or start+duration/rate<=now
            if ready and now-(ff.changed[name] or -math.huge)<0.5 and (ff.ends[name] or 0)>now then return false end
            return ready
        end
    end
    if active==true and onGCD~=true then return false end
    if active==false and now-(ff.changed[name] or -math.huge)>=0.5 then return true end
    return (ff.ends[name] or 0)<=now
end
local function FrostBarrierActive()
    local now=GetTime()
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if type(reader)=="function" and not frostState.barrierBlocked then
        for index=1,40 do
            local ok,aura=pcall(reader,"player",index,"HELPFUL")
            if not ok or not SafeValue(aura) then frostState.barrierBlocked=true;break end
            if aura==nil then
                if now-frostState.barrierChanged>=0.5 then frostState.barrierEnd=0 end
                return frostState.barrierEnd>now
            end
            if type(aura)~="table" then break end
            local id,name=Number(aura.spellId),aura.name
            if ArcaneCastName(id)=="Ice Barrier" or SafeValue(name) and
                (name=="Ice Barrier" or AL.englishNames and AL.englishNames[name]=="Ice Barrier") then
                local expires=Number(aura.expirationTime)
                frostState.barrierEnd=expires and expires>0 and expires or math.max(frostState.barrierEnd,now+1)
                return true
            end
        end
    end
    if Bool((SafeCall(AL.HasBuff,"player","Ice Barrier")))==true then return true end
    return frostState.barrierEnd>now
end
local function SpellReady(name)
    local active, onGCD, enabled, recovery = CooldownState(name)
    local frostfire=Enabled(AL.S(),"frostfire")
    local frost=Enabled(AL.S(),"frost")
    local fire=Enabled(AL.S(),"fire")
    if (frostfire or fire or frost) and (ff.retry[name] or 0)>GetTime() then return false,recovery end
    if frost and FROST_COOLDOWNS[name] then return FrostCooldownReady(name,active,onGCD,enabled,recovery),recovery end
    if fire and name=="Combustion" then return FireCombustionReady(active,onGCD,enabled),recovery end
    if (frostfire or fire) and (name=="Fire Blast" or name=="Cone of Cold") then
        if enabled==false then return false,recovery end
        local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,LearnedID(name) or name)
        if SafeValue(info) and type(info)=="table" then
            local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate)
            if SafeValue(info.modRate) and info.modRate==nil then rate=1 end
            if start and start>=0 and duration and duration>=0 and rate and rate>0 then
                if (onGCD==true or recovery) and duration<=1.5 and (ff.ends[name] or 0)>GetTime() then return false,recovery end
                local ready=start==0 or duration<=1.5 or start+duration/rate<=GetTime()
                if ready and GetTime()-(ff.changed[name] or -math.huge)<0.5 and (ff.ends[name] or 0)>GetTime() then return false,recovery end
                return ready,recovery
            end
        end
        if active==true and onGCD~=true then return false,recovery end
        if active==false and GetTime()-(ff.changed[name] or -math.huge)>=0.5 then return true,recovery end
        return (ff.ends[name] or 0)<=GetTime(),recovery
    end
    if Enabled(AL.S(),"arcane") and (arcaneRetry[name] or 0)>GetTime() then return false,recovery end
    if (Enabled(AL.S(),"arcane") or frostfire or fire or frost) and ARCANE_COOLDOWNS[name] then
        if (arcaneRetry[name] or 0)>GetTime() or enabled==false then return false,recovery end
        if name=="Presence of Mind" and ReadArcaneState().pom then return false,recovery end
        local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,LearnedID(name) or name)
        if SafeValue(info) and type(info)=="table" then
            local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate)
            if SafeValue(info.modRate) and info.modRate==nil then rate=1 end
            if start and start>=0 and duration and duration>=0 and rate and rate>0 then
                local ready=start==0 or duration<=1.5 or start+duration/rate<=GetTime()
                if ready and arcaneCastAt[name] and GetTime()-arcaneCastAt[name]<0.5
                    and (arcaneEnds[name] or 0)>GetTime() then return false,recovery end
                if (onGCD==true or recovery) and duration<=1.5 and (arcaneEnds[name] or 0)>GetTime() then return false,recovery end
                if ready then arcaneEnds[name]=GetTime() end
                return ready,recovery
            end
        end
        if active==true and onGCD~=true then return false,recovery end
        if active==false then
            if arcaneCastAt[name] and GetTime()-arcaneCastAt[name]<0.5
                and (arcaneEnds[name] or 0)>GetTime() then return false,recovery end
            arcaneEnds[name]=GetTime();return true,recovery
        end
        return not arcaneEnds[name] or arcaneEnds[name]<=GetTime(),recovery
    end
    if not Enabled(AL.S(),"arcane") and not frostfire and not fire and not frost and AL.DPS60 and AL.DPS60.Active() and AL.DPS60.Info(name) then return AL.DPS60.Ready(name), recovery end
    if enabled == false then return false, recovery end
    if active == true and onGCD ~= true then return false, recovery end
    if active == false or active == true and onGCD == true then return true, recovery end
    return Bool((SafeCall(AL.IsReady, name))) == true, recovery
end

local WAND_HANDOFF_SPELLS = { ["Fire Blast"]=true, ["Frost Nova"]=true, ["Frostbolt"]=true, ["Fireball"]=true, ["Scorch"]=true }
local function ArcaneHandoff(name)
    return (Enabled(AL.S(),"arcane") or Enabled(AL.S(),"frostfire") or Enabled(AL.S(),"fire") or Enabled(AL.S(),"frost"))
        and (ARCANE_DAMAGE[name] or ARCANE_COOLDOWNS[name] or FROST_COOLDOWNS[name] or name=="Combustion")
end

local function Offer(name, reason, gates, preparation, showRange)
    if not Ok(name) then return false end
    local ready, recovery = SpellReady(name)
    if not ready then return false end
    local usable, shortage = SpellUsability(name)
    if usable == false or shortage == true then return false end
    if not showRange and Bool((SafeCall(AL.InRange, name))) == false then return false end
    local conditions = {}
    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
    local affordable = Affordable(name, usable, shortage)
    if preparation and ManaAmount() == nil and usable == true and shortage == false then affordable = true end
    conditions[#conditions + 1] = affordable
    if WAND_HANDOFF_SPELLS[name] or ArcaneHandoff(name)
        or not Enabled(AL.S(),"arcane") and not Enabled(AL.S(),"frostfire") and not Enabled(AL.S(),"fire") and not Enabled(AL.S(),"frost") and AL.DPS60 and AL.DPS60.Active() and (name == "Ice Lance" or name == "Pyroblast") then
        if LiveWandActive() and Ok("Shoot") then
            local canStop = type(AL.WandReady) ~= "function" or AL.WandReady(true)
            if not canStop or GetTime() < wandStopPendingUntil then return AddAction(nil, "Stopping wand", conditions) end
            return AddAction("Shoot", "Stop wand for " .. name, conditions)
        end
        -- Shoot recovery may be absent from the spell's cooldown data. Use a
        -- 1.5 s fallback after an accepted shot before offering an instant.
        local shotRecovery = type(AL.WandRecoveryRemaining) == "function" and AL.WandRecoveryRemaining() > 0
            or type(AL.WandRecoveryRemaining) ~= "function" and GetTime() < wandRecoveryUntil
        if recovery or shotRecovery then return AddAction(nil, "Global cooldown", conditions) end
    end
    return AddAction(name, reason, conditions)
end

local function PlayerMoving()
    local speed = Number((SafeCall(GetUnitSpeed, "player")))
    if speed ~= nil then return speed > 0 end
    local player = A and SafeValue(A.Player) and A.Player
    if type(player) == "table" then
        local value = SafeCall(player.IsMoving, player)
        local moving = Bool(value)
        if moving ~= nil then return moving end
        local numeric = Number(value)
        if numeric ~= nil then return numeric > 0 end
    end
    -- Protected speed is unknown, not proof of movement. Movement events
    -- remain useful when neither the speed nor framework reader is public.
    return movementEventActive == true
end

local function PlayerIsCastingOrChanneling()
    local player = A and SafeValue(A.Player) and A.Player
    if type(player) == "table" then
        for _, reader in pairs({ player.IsCasting, player.IsChanneling }) do
            local value = SafeCall(reader, player)
            if not SafeValue(value) or value == true
                or (type(value) == "string" and value ~= "")
                or (Number(value) and Number(value) > 0) then return true end
        end
    end
    for _, reader in pairs({ UnitCastingInfo, UnitChannelInfo }) do
        local name = SafeCall(reader, "player")
        if not SafeValue(name) or name ~= nil then return true end
    end
    local name = SafeCall(AL.CastingSpell)
    if name == "Shoot" and type(AL.WandCasting) == "function" then return AL.WandCasting() end
    return SafeValue(name) and type(name) == "string"
end

LiveWandActive = function()
    if type(AL.WandAutoRepeatActive) == "function" then return AL.WandAutoRepeatActive() end
    local id = LearnedID("Shoot") or 5019
    local active = Bool((SafeCall(IsAutoRepeatSpell, id)))
    if active == nil then active = Bool((SafeCall(C_Spell and C_Spell.IsAutoRepeatSpell, id))) end
    if active ~= nil then
        -- Live stopped state must clear stale START_AUTOREPEAT events.
        wandEventActive = active
        return active
    end
    local player = A and SafeValue(A.Player) and A.Player
    if type(player) == "table" then
        active = Bool((SafeCall(player.IsShooting, player)))
        if active ~= nil then wandEventActive = active; return active end
    end
    active = Bool((SafeCall(IsCurrentSpell, id)))
    if active == nil then active = Bool((SafeCall(C_Spell and C_Spell.IsCurrentSpell, id))) end
    if active ~= nil then wandEventActive = active; return active end
    return wandEventActive
end

local function PlayerIsWanding()
    if type(AL.WandReady) == "function" then return not AL.WandReady() end
    if GetTime() < wandPendingUntil then return true end
    return LiveWandActive()
end

local function WandEligible(s)
    if not Enabled(s, "wand") or not Ok("Shoot") then return false end
    if type(GetInventoryItemID) ~= "function" then return Bool((SafeCall(AL.WandEquipped))) == true end
    for _, slot in ipairs({ 18, 16 }) do
        local id = Number((SafeCall(GetInventoryItemID, "player", slot)))
        if id and id > 0 then
            local class, subclass
            local readers = { C_Item and C_Item.GetItemInfoInstant, GetItemInfoInstant }
            for index = 1, 2 do
                local reader = readers[index]
                class, subclass = SafeCall(function()
                    if type(reader) ~= "function" then return end
                    local _, _, _, _, _, itemClass, itemSubclass = reader(id)
                    return itemClass, itemSubclass
                end)
                class, subclass = Number(class), Number(subclass)
                if class and subclass then break end
            end
            if class == 2 and subclass == 19 then return true end
            -- Legacy ranged-slot wands remain usable without item metadata.
            -- A main-hand weapon must positively identify as a wand.
            if slot == 18 and (not class or not subclass) then return true end
        end
    end
    return false
end

local function Wand(s, reason, gates, moving)
    if not WandEligible(s) then return false end
    if reason == "Out of mana" then
        for _, name in ipairs({ "Frostbolt", "Fireball", "Scorch" }) do
            if Ok(name) then
                local usable, shortage = SpellUsability(name)
                if shortage == false then
                    local conditions = {}
                    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
                    conditions[#conditions + 1] = Affordable(name, usable, shortage)
                    if AddAction(nil, "Waiting for spell readiness", conditions) then return true end
                end
            end
        end
    end
    if moving then return AddAction(nil, "Stop moving to wand", gates) end
    if type(AL.WandReady) == "function" then
        local ready, wait = AL.WandReady()
        if not ready then return AddAction(nil, wait, gates) end
    elseif PlayerIsWanding() then return AddAction(nil, "Wand active", gates) end
    if Bool((SafeCall(AL.InRange, "Shoot"))) == false then return AddAction(nil, "Wand out of range", gates) end
    local _, _, _, recovery = CooldownState("Shoot")
    if recovery then return AddAction(nil, "Global cooldown", gates) end
    return AddAction("Shoot", reason, gates)
end

local function WandManaThreshold(s) return SettingNumber(s, "wandMana", 25, 0, 95) end

local function DamageGates(s, mana, targetHP)
    if not WandEligible(s) then return {} end
    local gates = { ManaGate(mana, WandManaThreshold(s), false, true) }
    -- An unavailable target-health sensor cannot establish the finishing
    -- threshold. Continue the mana-based rotation instead of blocking nukes.
    if targetHP ~= nil or CurveAvailable("health", "target") then
        gates[#gates + 1] = HealthGate("target", targetHP, SettingNumber(s, "wandTargetHP", 20, 0, 80), false, true)
    end
    return gates
end

local function WandThresholds(s, mana, targetHP, moving)
    Wand(s, "Save mana", { ManaGate(mana, WandManaThreshold(s), true) }, moving)
    Wand(s, "Finish with wand", { HealthGate("target", targetHP, SettingNumber(s, "wandTargetHP", 20, 0, 80), true) }, moving)
end

local function UnitWithin(unit, radius)
    local distance, checked = SafeCall(UnitDistanceSquared, unit)
    distance = Number(distance)
    if distance and distance >= 0 and Bool(checked) ~= false then return distance <= radius * radius end
    local object = A and SafeCall(A.Unit, unit)
    if SafeValue(object) and (type(object) == "table" or type(object) == "userdata") then
        local first,second=SafeCall(object.GetRange,object)
        local range,other=Number(first),Number(second)
        if not SafeValue(second) then return nil end
        if range and other and other>=0 then range=math.max(range,other) end
        if range and range >= 0 then return range <= radius end
    end
    if radius >= 10 then return Bool((SafeCall(CheckInteractDistance, unit, 3))) end
end

local function EnemyCount(limit)
    local count
    local function Accept(value)
        value = Number(value)
        if value and value >= 0 and value <= 40 and value == math.floor(value) then count = math.max(count or 0, value) end
    end
    Accept((SafeCall(AL.EnemyCount, 10)))
    if A and A.MultiUnits then
        Accept((SafeCall(A.MultiUnits.GetByRangeInCombat, A.MultiUnits, 10, limit or 8)))
        Accept((SafeCall(A.MultiUnits.GetActiveEnemies, A.MultiUnits, 10)))
    end
    local seen, visible = {}, 0
    local function Count(unit)
        if not SafeValue(unit) or type(unit) ~= "string" then return end
        if Bool((SafeCall(UnitExists, unit))) ~= true or Bool((SafeCall(UnitCanAttack, "player", unit))) ~= true
            or Bool((SafeCall(UnitIsDeadOrGhost, unit))) ~= false or Bool((SafeCall(UnitAffectingCombat, unit))) ~= true then return end
        local guid = SafeCall(UnitGUID, unit)
        if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] or UnitWithin(unit, 10) ~= true then return end
        seen[guid], visible = true, visible + 1
    end
    Count("target")
    local plates = SafeCall(C_NamePlate and C_NamePlate.GetNamePlates)
    if SafeValue(plates) and type(plates) == "table" then
        for _, plate in pairs(plates) do
            if SafeValue(plate) and type(plate) == "table" then Count(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)) end
        end
    else
        for index = 1, 40 do Count("nameplate" .. index) end
    end
    if visible > 0 then count = math.max(count or 0, visible) end
    return count
end

local function TargetFrozen()
    return Bool((SafeCall(AL.TargetHasAnyDebuff, FROZEN_DEBUFFS))) == true
        or Bool((SafeCall(AL.HasBuff, "player", "Fingers of Frost"))) == true
end

local function NukeCandidates(s)
    if Enabled(s,"frost") then return {"Frostbolt","Fireball","Scorch","Arcane Missiles"} end
    if Enabled(s,"fire") then return {"Fireball","Scorch","Frostbolt","Arcane Missiles"} end
    if Enabled(s,"frostfire") then
        local names={}
        if Enabled(s,"frostfireBolt") then names[#names+1]="Frostfire Bolt" end
        for _,name in ipairs({"Fireball","Frostbolt","Scorch","Arcane Missiles"}) do names[#names+1]=name end
        return names
    end
    if Enabled(s,"arcane") then
        local names={}
        if Enabled(s,"arcaneBlast") then names[#names+1]="Arcane Blast" end
        for _,name in ipairs({"Frostbolt","Fireball","Scorch"}) do names[#names+1]=name end
        if Enabled(s,"arcaneMissiles") then names[#names+1]="Arcane Missiles" end
        return names
    end
    if AL.DPS60 and AL.DPS60.Active() then
        local build = AL.DPS60.Build("MAGE", s, "AUTO")
        if build == "ARCANE" then
            local _, _, stacks = AL.DPS60.Aura("Arcane Blast", false)
            return stacks and stacks >= 3 and { "Frostbolt", "Arcane Blast", "Arcane Missiles" }
                or { "Arcane Blast", "Frostbolt", "Arcane Missiles" }
        elseif build == "FROSTFIRE" then return { "Frostfire Bolt", "Fireball", "Frostbolt" }
        elseif build == "FIRE" then return { "Fireball", "Scorch", "Frostbolt" } end
        if build == "FROST" then return { "Frostbolt", "Fireball", "Arcane Missiles" } end
    end
    local candidates, seen = {}, {}
    local function Add(name)
        if name and not seen[name] and (not Enabled(s, "primaryFire") or name ~= "Frostbolt") then
            seen[name], candidates[#candidates + 1] = true, name
        end
    end
    local names = { FROSTBOLT = "Frostbolt", FIREBALL = "Fireball", ARCANE_MISSILES = "Arcane Missiles", SCORCH = "Scorch" }
    if Enabled(s, "primaryFire") then
        Add("Fireball"); Add("Scorch"); Add("Arcane Missiles")
    else
        local selected = SettingChoice(s, "nuke", { AUTO=true,FROSTBOLT=true,FIREBALL=true,ARCANE_MISSILES=true,SCORCH=true }, "AUTO")
        Add(names[selected]); Add("Frostbolt"); Add("Fireball"); Add("Arcane Missiles"); Add("Scorch")
    end
    return candidates
end

local function PrimaryNuke(s)
    for _, name in ipairs(NukeCandidates(s)) do if Ok(name) then return name end end
end

local function Preparation(s)
    if Enabled(s, "buffs") then
        if not AL.HasBuff("player", "Arcane Intellect") then Offer("Arcane Intellect", "Intellect", nil, true) end
        local hasArmor
        if (Enabled(s,"arcane") or Enabled(s,"frostfire") or Enabled(s,"fire") or Enabled(s,"frost")) and Ok("Mage Armor") then
            hasArmor=true
            if not AL.HasBuff("player","Mage Armor") then Offer("Mage Armor","Arcane mana regeneration",nil,true) end
        end
        for _, name in ipairs(ARMORS) do if AL.HasBuff("player", name) then hasArmor = true; break end end
        if not hasArmor then
            for _, name in ipairs(ARMORS) do if Ok(name) then Offer(name, "Armor", nil, true); break end end
        end
    end
    if Enabled(s, "conjure") then
        for _, entry in ipairs({ { "Conjure Water", WATER_IDS }, { "Conjure Food", FOOD_IDS }, { "Conjure Mana Agate", GEM_IDS } }) do
            local reader = GetItemCount or (C_Item and C_Item.GetItemCount)
            local count = 0
            for _, id in ipairs(entry[2]) do
                local value = Number((SafeCall(reader, id)))
                if not value or value < 0 then count = nil; break end
                count = count + value
            end
            if count == 0 and GetTime() >= (conjureLocks[entry[1]] or 0) then Offer(entry[1], "Conjure supplies", nil, true) end
        end
    end
end

local function RecoverMana(s, mana, moving, inCombat, hostile)
    if Enabled(s, "evocation") and not moving and (not inCombat or not hostile or UnitWithin("target", 10) == false) then
        Offer("Evocation", "Restore mana", { ManaGate(mana, SettingNumber(s, "evocationMana", 15, 0, 60), true) })
    end
end

local function Defense(s, hostile, hp, mana)
    if Enabled(s, "iceblock") and not AL.HasBuff("player", "Ice Block") then
        Offer("Ice Block", "Emergency", { HealthGate("player", hp, SettingNumber(s, "iceBlockHP", 18, 1, 60), true) })
    end
    if hostile and Enabled(s, "cspell") and Bool((SafeCall(AL.TargetCasting))) == true then Offer("Counterspell", "Interrupt") end
    if Enabled(s,"frost") and Enabled(s,"frostBarrier") and not FrostBarrierActive() then
        Offer("Ice Barrier","Frost defense",{
            HealthGate("player",hp,SettingNumber(s,"frostBarrierHP",70,1,100),true),
            ManaGate(mana,SettingNumber(s,"frostBarrierMinMana",25,0,100),false),
        })
    end
    if Enabled(s, "manaShield") and not AL.HasBuff("player", "Mana Shield") then
        Offer("Mana Shield", "Defense", {
            HealthGate("player", hp, SettingNumber(s, "manaShieldHP", 45, 5, 90), true),
            ManaGate(mana, SettingNumber(s, "manaShieldMinMana", 25, 0, 100), false),
        })
    end
    if hostile and Enabled(s, "nova") and UnitWithin("target", 10) == true then Offer("Frost Nova", "Make distance") end
end

-- Count close enemies separately from ranged ones. A generic active-enemy
-- total cannot prove that Cone of Cold or Arcane Explosion will hit them.
local function ArcaneEnemyCount(radius,limit)
    local count
    if A and A.MultiUnits then
        local n=Number((SafeCall(A.MultiUnits.GetByRangeInCombat,A.MultiUnits,radius,limit)))
        if n and n>=0 and n<=40 and n==math.floor(n) then count=n end
    end
    local seen,visible={},0
    local function Count(unit)
        if Bool((SafeCall(UnitExists,unit)))~=true or Bool((SafeCall(UnitCanAttack,"player",unit)))~=true
            or Bool((SafeCall(UnitIsDeadOrGhost,unit)))~=false or Bool((SafeCall(UnitAffectingCombat,unit)))~=true then return end
        local guid=SafeCall(UnitGUID,unit)
        if not SafeValue(guid) or type(guid)~="string" or seen[guid] then return end
        if UnitWithin(unit,radius)==true then seen[guid]=true;visible=visible+1 end
    end
    Count("target")
    local plates=SafeCall(C_NamePlate and C_NamePlate.GetNamePlates)
    if SafeValue(plates) and type(plates)=="table" then
        for _,plate in pairs(plates) do if SafeValue(plate) and type(plate)=="table" then
            local unit=plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if SafeValue(unit) and type(unit)=="string" then Count(unit) end
        end end
    end
    if visible>0 then count=math.max(count or 0,visible) end
    return count
end
local function CopyGates(gates,...)
    local result={}
    for _,gate in ipairs(gates) do result[#result+1]=gate end
    for index=1,select("#",...) do result[#result+1]=select(index,...) end
    return result
end
local function ArcaneOffensive(s,inCombat,targetHP,mana,moving)
    WandThresholds(s,mana,targetHP,moving)
    local gates=DamageGates(s,mana,targetHP)
    local state=ReadArcaneState()
    local canCast=not moving or state.pom
    local burstGates=CopyGates(gates,
        HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false),
        ManaGate(mana,SettingNumber(s,"arcaneBurstMinMana",40,0,100),false))
    local burstTarget
    if canCast then
        for _,name in ipairs(NukeCandidates(s)) do
            if Ok(name) and SpellReady(name) and Bool((SafeCall(AL.InRange,name)))~=false then burstTarget=name;break end
        end
    end
    if inCombat and AL.burst and burstTarget then
        local usable,shortage=SpellUsability(burstTarget)
        local eligible=CopyGates(burstGates,Affordable(burstTarget,usable,shortage),usable~=false,shortage~=true)
        if Enabled(s,"arcanePower") then Offer("Arcane Power","Arcane Burst",eligible) end
        if Enabled(s,"arcaneEureka") then Offer("Eureka!","Arcane Burst",eligible) end
        if Enabled(s,"arcaneBerserking") then Offer("Berserking","Arcane Burst",eligible) end
    end
    if inCombat and Enabled(s,"aoe") then
        local minimum=SettingNumber(s,"aoeMinEnemies",3,2,8)
        local close=ArcaneEnemyCount(10,minimum)
        local areaGates=CopyGates(gates,ManaGate(mana,SettingNumber(s,"aoeMinMana",35,0,100),false))
        if close and close>=minimum and UnitWithin("target",10)==true then
            Offer("Cone of Cold","Arcane close AoE",areaGates)
            Offer("Arcane Explosion","Arcane close AoE",areaGates)
        end
        if Enabled(s,"arcaneBlizzard") and not moving then
            local ranged=ArcaneEnemyCount(30,minimum)
            if ranged and ranged>=minimum then Offer("Blizzard","Arcane ranged ground AoE",areaGates) end
        end
    end
    if moving and Enabled(s,"fireblast") and inCombat then
        Offer("Fire Blast","Arcane moving instant",CopyGates(gates,
            ManaGate(mana,SettingNumber(s,"fireBlastMinMana",25,0,100),false)))
    end
    -- A zero live mana cost is useful even when the proc aura cannot be read.
    -- It never invents a Missile Barrage from a cast attempt or proc chance.
    local blastCost=SpellManaCost("Arcane Blast")
    local missileCost,explicitMissileCost=SpellManaCost("Arcane Missiles")
    local freeMissiles=explicitMissileCost==true and missileCost==0
        and (not Ok("Arcane Blast") or blastCost~=nil and blastCost>0)
    if not moving and Enabled(s,"arcaneMissiles") and (state.barrage>GetTime() or freeMissiles) then
        Offer("Arcane Missiles","Missile Barrage / free missiles",gates)
    end
    if inCombat and AL.burst and state.charges>=4 and Enabled(s,"arcanePyroblast") and Ok("Pyroblast") then
        if Enabled(s,"presenceOfMind") and not state.pom and Bool((SafeCall(AL.InRange,"Pyroblast")))~=false then
            local usable,shortage=SpellUsability("Pyroblast")
            Offer("Presence of Mind","prepare instant Pyroblast",CopyGates(burstGates,
                Affordable("Pyroblast",usable,shortage),usable~=false,shortage~=true))
        end
        if state.pom then Offer("Pyroblast","Presence of Mind Burst",burstGates) end
    end
    if not moving and Enabled(s,"arcaneMissiles") then
        if state.charges>=3 then Offer("Arcane Missiles","conserve at three charges",CopyGates(gates,
            ManaGate(mana,SettingNumber(s,"arcaneThreeMana",30,0,100),true,true))) end
        if state.charges>=2 then Offer("Arcane Missiles","conserve at two charges",CopyGates(gates,
            ManaGate(mana,SettingNumber(s,"arcaneTwoMana",20,0,100),true,true))) end
    end
    if canCast then
        if Enabled(s,"arcaneBlast") and state.charges<4 then Offer("Arcane Blast","build eighteen-second Arcane buff",gates) end
        if Enabled(s,"arcaneWrath") then Offer("Arcane Wrath","Arcane Wrath on cooldown",gates) end
        if not moving and Enabled(s,"arcaneMissiles") then
            Offer("Arcane Missiles","Arcane buff damage filler",gates)
        end
        if inCombat and not Ok("Arcane Blast") and Enabled(s,"fireblast") then
            Offer("Fire Blast","leveling instant",CopyGates(gates,
                ManaGate(mana,SettingNumber(s,"fireBlastMinMana",25,0,100),false)))
        end
        for _,name in ipairs({"Frostbolt","Fireball","Scorch"}) do Offer(name,"Arcane learned-spell fallback",gates,false,true) end
        if not moving and Enabled(s,"arcaneMissiles") then Offer("Arcane Missiles","learned channel fallback",gates,false,true) end
        Wand(s,"Out of mana",nil,moving)
    end
    AddAction(nil,moving and "Stop moving" or "Out of mana")
end

local function FrostfireOffensive(s,inCombat,targetHP,mana,moving)
    WandThresholds(s,mana,targetHP,moving)
    local gates=DamageGates(s,mana,targetHP)
    local state=FrostfireAuras()
    local scorchRank=FrostfireTalent("Improved Scorch")
    local maintain=Enabled(s,"frostfireScorch") and Ok("Scorch") and
        ((scorchRank and scorchRank>0) or state.vuln>0)
    local needsScorch=maintain and (state.vuln<5 or state.vulnEnd-GetTime()<=5)
    if scorchRank~=3 and not state.vulnReadable and (ff.scorchTries or 0)>=5
        and (ff.scorchTryUntil or 0)>GetTime() then needsScorch=false end
    local pyroTime=FrostfirePyroTime()
    local instantPyro=pyroTime==0 and GetTime()-(ff.pyroSpentAt or -math.huge)>=0.5
    local pyroProc=state.heat>=3 or pyroTime and pyroTime<=1500 and
        GetTime()-(ff.pyroSpentAt or -math.huge)>=0.5
    local minimum=SettingNumber(s,"aoeMinEnemies",3,2,8)
    local areaMode=inCombat and Enabled(s,"aoe")
    local ranged=areaMode and not moving and ArcaneEnemyCount(30,minimum)
    local close=areaMode and ArcaneEnemyCount(10,minimum)
    local areaAvailable=ranged and ranged>=minimum and
        ((Enabled(s,"frostfireFlamestrike") and Ok("Flamestrike")) or (Enabled(s,"frostfireBlizzard") and Ok("Blizzard")))
        or close and close>=minimum and UnitWithin("target",10)==true and (Ok("Cone of Cold") or Ok("Arcane Explosion"))
    local damageTarget
    if not moving then
        for _,name in ipairs(NukeCandidates(s)) do
            if Ok(name) and SpellReady(name) and Bool((SafeCall(AL.InRange,name)))~=false then damageTarget=name;break end
        end
    elseif instantPyro and Enabled(s,"frostfirePyroblast") and Ok("Pyroblast") then damageTarget="Pyroblast"
    elseif Enabled(s,"fireblast") and Ok("Fire Blast") and SpellReady("Fire Blast") then damageTarget="Fire Blast" end
    if inCombat and AL.burst and damageTarget and (not needsScorch or areaAvailable)
        and Bool((SafeCall(AL.InRange,damageTarget)))~=false then
        local usable,shortage=SpellUsability(damageTarget)
        local burst=CopyGates(gates,
            HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false),
            ManaGate(mana,SettingNumber(s,"frostfireBurstMinMana",40,0,100),false),
            Affordable(damageTarget,usable,shortage),usable~=false,shortage~=true)
        if needsScorch then burst[#burst+1]=ManaGate(mana,SettingNumber(s,"aoeMinMana",35,0,100),false) end
        if damageTarget=="Fire Blast" then burst[#burst+1]=ManaGate(mana,SettingNumber(s,"fireBlastMinMana",25,0,100),false) end
        if Enabled(s,"frostfireEureka") then Offer("Eureka!","Frostfire Burst",burst) end
        if Enabled(s,"frostfireBerserking") then Offer("Berserking","Frostfire Burst",burst) end
    end
    if areaMode then
        local area=CopyGates(gates,ManaGate(mana,SettingNumber(s,"aoeMinMana",35,0,100),false))
        if ranged and ranged>=minimum then
            if Enabled(s,"frostfireFlamestrike") and (ff.flamestrikeEnd or 0)<=GetTime() then
                Offer("Flamestrike","Frostfire ground AoE",area)
            end
        end
        if close and close>=minimum and UnitWithin("target",10)==true then
            Offer("Cone of Cold","Frostfire close AoE",area)
            Offer("Arcane Explosion","Frostfire close AoE",area)
        end
        if ranged and ranged>=minimum and Enabled(s,"frostfireBlizzard") then
            Offer("Blizzard","Frostfire ranged ground AoE",area)
        end
    end
    if not moving and needsScorch then Offer("Scorch","maintain personal Fire Vulnerability",gates) end
    if Enabled(s,"frostfirePyroblast") and pyroProc and (not moving or instantPyro) then
        Offer("Pyroblast",instantPyro and "confirmed instant Pyroblast" or "three Heating Up stacks",gates)
    end
    -- The reference has no Missile Barrage talent. Honor it only if a live
    -- customization supplies positive proc evidence, never from a chance.
    if not moving and ReadArcaneState().barrage>GetTime() then
        Offer("Arcane Missiles","confirmed Missile Barrage",gates)
    end
    if moving then
        if Enabled(s,"icelance") and (state.fof>0 or TargetFrozen()) then Offer("Ice Lance","moving frozen instant",gates) end
    end
    if inCombat and Enabled(s,"fireblast") then Offer("Fire Blast",moving and "Frostfire moving instant" or "Frostfire instant on cooldown",CopyGates(gates,
        ManaGate(mana,SettingNumber(s,"fireBlastMinMana",25,0,100),false))) end
    if not moving then
        for _,name in ipairs(NukeCandidates(s)) do Offer(name,"Frostfire learned-spell damage",gates,false,true) end
        Wand(s,"Out of mana",nil,false)
    end
    AddAction(nil,moving and "Stop moving" or "Out of mana")
end

local function FireOffensive(s,inCombat,targetHP,mana,moving)
    WandThresholds(s,mana,targetHP,moving)
    local gates=DamageGates(s,mana,targetHP)
    if not inCombat and not moving then Offer("Fireball","Fire opener",gates,false,true) end
    local state=FrostfireAuras()
    local scorchRank=FrostfireTalent("Improved Scorch")
    local maintain=Enabled(s,"fireScorch") and Ok("Scorch")
        and ((scorchRank and scorchRank>0) or state.vuln>0)
    local needsScorch=maintain and (state.vuln<5 or state.vulnEnd-GetTime()<=5)
    if scorchRank~=3 and not state.vulnReadable and (ff.scorchTries or 0)>=5
        and (ff.scorchTryUntil or 0)>GetTime() then needsScorch=false end
    local pyroTime=FrostfirePyroTime()
    local spent=GetTime()-(ff.pyroSpentAt or -math.huge)<0.5
    local instantPyro=not spent and pyroTime==0
    local pyroProc=not spent and (state.heat>=3 or pyroTime and pyroTime<=1500)
    local clear=Enabled(s,"fireClearcasting") and FireClearcasting()
    local minimum=SettingNumber(s,"aoeMinEnemies",3,2,8)
    local areaMode=inCombat and Enabled(s,"aoe")
    local ranged=areaMode and not moving and ArcaneEnemyCount(30,minimum)
    local close=areaMode and ArcaneEnemyCount(10,minimum)
    local areaTarget
    if ranged and ranged>=minimum and Enabled(s,"fireFlamestrike") and Ok("Flamestrike")
        and (ff.flamestrikeEnd or 0)<=GetTime() then areaTarget="Flamestrike"
    elseif close and close>=minimum and UnitWithin("target",10)==true then
        if Ok("Cone of Cold") and SpellReady("Cone of Cold") then areaTarget="Cone of Cold"
        elseif Ok("Arcane Explosion") then areaTarget="Arcane Explosion" end
    end
    if not areaTarget and ranged and ranged>=minimum and Enabled(s,"fireBlizzard") and Ok("Blizzard") then areaTarget="Blizzard" end
    local damageTarget=areaTarget
    if not damageTarget then
        if pyroProc and Enabled(s,"firePyroblast") and Ok("Pyroblast") and (not moving or instantPyro) then damageTarget="Pyroblast"
        elseif moving and Enabled(s,"fireblast") and Ok("Fire Blast") and SpellReady("Fire Blast") and not clear then damageTarget="Fire Blast"
        elseif not moving then
            for _,name in ipairs(NukeCandidates(s)) do
                if Ok(name) and SpellReady(name) and Bool((SafeCall(AL.InRange,name)))~=false then damageTarget=name;break end
            end
        end
    end
    if inCombat and AL.burst and damageTarget and (not needsScorch or areaTarget)
        and damageTarget~="Blizzard" and Bool((SafeCall(AL.InRange,damageTarget)))~=false then
        local usable,shortage=SpellUsability(damageTarget)
        local burst=CopyGates(gates,
            HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false),
            ManaGate(mana,SettingNumber(s,"fireBurstMinMana",40,0,100),false),
            Affordable(damageTarget,usable,shortage),usable~=false,shortage~=true)
        if areaTarget then burst[#burst+1]=ManaGate(mana,SettingNumber(s,"aoeMinMana",35,0,100),false) end
        if damageTarget=="Fire Blast" then burst[#burst+1]=ManaGate(mana,SettingNumber(s,"fireBlastMinMana",25,0,100),false) end
        local fireHit=damageTarget=="Fireball" or damageTarget=="Scorch" or damageTarget=="Pyroblast"
            or damageTarget=="Fire Blast" or damageTarget=="Flamestrike"
        if fireHit and Enabled(s,"fireCombustion") and (not maintain or state.vuln>=5) then
            Offer("Combustion","Fire Burst: empower eligible Fire damage",burst)
        end
        if Enabled(s,"fireEureka") then Offer("Eureka!","Fire Burst",burst) end
        if Enabled(s,"fireBerserking") then Offer("Berserking","Fire Burst",burst) end
    end
    -- Area attacks exist only in this explicit AoE On branch.
    if areaMode then
        local area=CopyGates(gates,ManaGate(mana,SettingNumber(s,"aoeMinMana",35,0,100),false))
        if ranged and ranged>=minimum and Enabled(s,"fireFlamestrike") and (ff.flamestrikeEnd or 0)<=GetTime() then
            Offer("Flamestrike","Fire ground AoE",area)
        end
        if close and close>=minimum and UnitWithin("target",10)==true then
            Offer("Cone of Cold","Fire close AoE",area)
            Offer("Arcane Explosion","Fire close AoE",area)
        end
        if ranged and ranged>=minimum and Enabled(s,"fireBlizzard") then Offer("Blizzard","Fire ranged ground AoE",area) end
    end
    if Enabled(s,"firePyroblast") and pyroProc and (not moving or instantPyro) then
        Offer("Pyroblast",instantPyro and "confirmed instant Pyroblast" or "three Heating Up stacks",gates)
    end
    if not moving and needsScorch then Offer("Scorch","maintain personal Fire Vulnerability",gates) end
    if inCombat and Enabled(s,"fireblast") and not clear then
        Offer("Fire Blast",moving and "Fire moving instant" or "Fire instant on cooldown",CopyGates(gates,
            ManaGate(mana,SettingNumber(s,"fireBlastMinMana",25,0,100),false)))
    end
    local missileCost,explicit=SpellManaCost("Arcane Missiles")
    local freeBarrage=explicit==true and missileCost==0 and (SpellManaCost("Fireball") or 0)>0
    if not moving and Enabled(s,"fireMissiles") and (ReadArcaneState().barrage>GetTime() or freeBarrage) then
        Offer("Arcane Missiles","Fire: confirmed Missile Barrage",gates)
    end
    if not moving then
        for _,name in ipairs(NukeCandidates(s)) do
            if name~="Arcane Missiles" or Enabled(s,"fireMissiles") then
                Offer(name,clear and "Fire: conserve confirmed Clearcasting" or "Fire learned-spell damage",gates,false,true)
            end
        end
        Wand(s,"Out of mana",nil,false)
    end
    AddAction(nil,moving and "Stop moving" or "Out of mana")
end

local function WinterChillCone(s)
    if not Enabled(s,"frostWinterChill") then return true end
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if type(reader)~="function" then return true end
    local localized=SafeCall(C_Spell and C_Spell.GetSpellName,12579)
    for i=1,40 do
        local ok,aura=pcall(reader,"target",i,"HARMFUL")
        if not ok or not SafeValue(aura) then return true end
        if aura==nil then return FrostfireTalent("Winter's Chill")==0 or FrostfireTalent("Winter's Chill")==nil end
        if type(aura)~="table" then return true end
        local name=SafeValue(aura.name) and type(aura.name)=="string" and aura.name or nil
        local match=Number(aura.spellId)==12579 or name=="Winter's Chill"
            or name and SafeValue(localized) and name==localized
        if match and (Bool(aura.isFromPlayerOrPlayerPet)==true or SafeValue(aura.sourceUnit) and aura.sourceUnit=="player") then
            local stacks,ending=Number(aura.applications),Number(aura.expirationTime)
            return not stacks or stacks>=5 or ending and ending>0 and ending-GetTime()<=3
        end
    end
    return true
end

local function FrostOffensive(s,inCombat,targetHP,mana,moving)
    WandThresholds(s,mana,targetHP,moving)
    local gates=DamageGates(s,mana,targetHP)
    local state=FrostfireAuras()
    local frozen=state.fof>0 or Bool((SafeCall(AL.TargetHasAnyDebuff,FROZEN_DEBUFFS)))==true
    local minimum=SettingNumber(s,"aoeMinEnemies",3,2,8)
    local blizzardMinimum=math.max(minimum,SettingNumber(s,"frostBlizzardMinEnemies",4,2,8))
    local close,ranged
    if inCombat and Enabled(s,"aoe") then
        close=ArcaneEnemyCount(10,minimum)
        ranged=ArcaneEnemyCount(30,blizzardMinimum)
    end
    local closeArea=close and close>=minimum and UnitWithin("target",10)==true
    local rangedArea=ranged and ranged>=blizzardMinimum
    local burst=CopyGates(gates,
        ManaGate(mana,SettingNumber(s,"frostBurstMinMana",40,0,100),false),
        HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false))
    if inCombat and AL.burst then
        -- Cold Snap does not improve Frostbolt, Ice Lance or Missiles. Spend
        -- the ten-minute reset only for an enabled, affordable close AoE Cone.
        if closeArea and Enabled(s,"frostColdSnap") and Enabled(s,"frostCone") and Ok("Cone of Cold") and WinterChillCone(s)
            and math.max(ff.ends["Cone of Cold"] or 0,NativeArcaneEnd("Cone of Cold") or 0)>GetTime()
            and not SpellReady("Cone of Cold") and Bool((SafeCall(AL.InRange,"Cone of Cold")))~=false then
            local usable,shortage=SpellUsability("Cone of Cold")
            Offer("Cold Snap","Frost Burst: reset close AoE",CopyGates(burst,
                ManaGate(mana,SettingNumber(s,"aoeMinMana",35,0,100),false),
                Affordable("Cone of Cold",usable,shortage),usable~=false,shortage~=true))
        end
        local direct=closeArea and Enabled(s,"frostCone") and WinterChillCone(s) and Ok("Cone of Cold") and SpellReady("Cone of Cold") and "Cone of Cold"
            or frozen and Enabled(s,"icelance") and Ok("Ice Lance") and "Ice Lance"
            or not moving and Ok("Frostbolt") and "Frostbolt"
        if direct and not (rangedArea and Enabled(s,"frostBlizzard") and Ok("Blizzard") and not closeArea)
            and Bool((SafeCall(AL.InRange,direct)))~=false then
            local usable,shortage=SpellUsability(direct)
            local eligible=CopyGates(burst,Affordable(direct,usable,shortage),usable~=false,shortage~=true)
            if direct=="Cone of Cold" then eligible=CopyGates(eligible,
                ManaGate(mana,SettingNumber(s,"aoeMinMana",35,0,100),false)) end
            if Enabled(s,"frostEureka") then Offer("Eureka!","Frost Burst",eligible) end
            if Enabled(s,"frostBerserking") then Offer("Berserking","Frost Burst",eligible) end
        elseif rangedArea and not moving and Enabled(s,"frostBlizzard") and Ok("Blizzard") then
            local usable,shortage=SpellUsability("Blizzard")
            if Enabled(s,"frostBerserking") then Offer("Berserking","Frost AoE Burst",CopyGates(burst,
                ManaGate(mana,SettingNumber(s,"aoeMinMana",35,0,100),false),
                Affordable("Blizzard",usable,shortage),usable~=false,shortage~=true)) end
        end
    end
    if inCombat and Enabled(s,"aoe") then
        local area=CopyGates(gates,ManaGate(mana,SettingNumber(s,"aoeMinMana",35,0,100),false))
        if closeArea then
            if Enabled(s,"frostCone") and WinterChillCone(s) then Offer("Cone of Cold","Frost close AoE / Winter's Chill",area) end
            if Enabled(s,"frostExplosion") then Offer("Arcane Explosion","Frost optional close AoE",area) end
        end
        if rangedArea and not moving and Enabled(s,"frostBlizzard") then Offer("Blizzard","Frost ranged ground AoE",area) end
    end
    if inCombat and frozen and Enabled(s,"icelance") then Offer("Ice Lance","Frost: confirmed frozen / Fingers of Frost",gates) end
    local missileCost,explicit=SpellManaCost("Arcane Missiles")
    local freeBarrage=explicit==true and missileCost==0 and (SpellManaCost("Frostbolt") or 0)>0
    if not moving and Enabled(s,"frostMissiles") and (ReadArcaneState().barrage>GetTime() or freeBarrage) then
        Offer("Arcane Missiles","Frost: confirmed Missile Barrage",gates)
    end
    if inCombat and moving and Enabled(s,"frostFireBlast") and Enabled(s,"fireblast") then
        Offer("Fire Blast","Frost moving instant",CopyGates(gates,
            ManaGate(mana,SettingNumber(s,"fireBlastMinMana",25,0,100),false)))
    end
    if not moving then
        for _,name in ipairs(NukeCandidates(s)) do
            if name~="Arcane Missiles" or Enabled(s,"frostMissiles") then
                Offer(name,"Frost learned-spell damage",gates,false,true)
            end
        end
        Wand(s,"Out of mana",nil,false)
    end
    AddAction(nil,moving and "Stop moving" or "Out of mana")
end

local function Offensive(s, inCombat, targetHP, mana, moving)
    if Enabled(s,"frost") then FrostOffensive(s,inCombat,targetHP,mana,moving);return end
    if Enabled(s,"fire") then FireOffensive(s,inCombat,targetHP,mana,moving);return end
    if Enabled(s,"frostfire") then FrostfireOffensive(s,inCombat,targetHP,mana,moving);return end
    if Enabled(s,"arcane") then ArcaneOffensive(s,inCombat,targetHP,mana,moving);return end
    WandThresholds(s, mana, targetHP, moving)
    local gates = DamageGates(s, mana, targetHP)
    local build = AL.DPS60 and AL.DPS60.Active()
        and AL.DPS60.Build("MAGE", s, "AUTO")
    local fireBuild = build == "FIRE" or build == "FROSTFIRE" or (not build or build == "AUTO") and Enabled(s, "primaryFire")
    if inCombat then
        if AL.burst then Offer("Berserking", "Burst", { HealthGate("target", targetHP,
            SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false) }) end
        local minimum = SettingNumber(s, "aoeMinEnemies", 3, 2, 8)
        local count = Enabled(s, "aoe") and EnemyCount(minimum)
        if count and count >= minimum then
            local aoeGates = {}
            for _, gate in ipairs(gates) do aoeGates[#aoeGates + 1] = gate end
            aoeGates[#aoeGates + 1] = ManaGate(mana, SettingNumber(s, "aoeMinMana", 35, 0, 100), false)
            if fireBuild and not moving then Offer("Flamestrike", "Fire AoE", aoeGates) end
            if UnitWithin("target", 10) == true then
                Offer("Cone of Cold", "Close AoE", aoeGates)
                Offer("Arcane Explosion", "Close AoE", aoeGates)
            end
            if not moving then Offer("Blizzard", "Ranged AoE", aoeGates) end
        end
        if not fireBuild and Enabled(s, "icelance") and TargetFrozen() then Offer("Ice Lance", "Frozen", gates) end
    end
    if AL.DPS60 and AL.DPS60.Active() then
        if (build == "FIRE" or build == "FROSTFIRE") and AL.DPS60.Proc("Hot Streak") then Offer("Pyroblast", "Hot Streak", gates) end
        if build == "ARCANE" and AL.DPS60.Proc("Missile Barrage") and not moving then Offer("Arcane Missiles", "Missile Barrage", gates) end
    end
    local clearcasting = AL.HasBuff("player", "Clearcasting")
    local arcaneBlastStacks
    if build == "ARCANE" then local _, _, stacks = AL.DPS60.Aura("Arcane Blast", false); arcaneBlastStacks = stacks end
    local allowFireBlast = build ~= "ARCANE" or moving or arcaneBlastStacks and arcaneBlastStacks >= 2
    if allowFireBlast and Enabled(s, "fireblast") and (inCombat or moving) and (moving or fireBuild or not clearcasting) then
        local fireGates = {}
        for _, gate in ipairs(gates) do fireGates[#fireGates + 1] = gate end
        fireGates[#fireGates + 1] = ManaGate(mana, SettingNumber(s, "fireBlastMinMana", 25, 0, 100), false)
        Offer("Fire Blast", moving and "Moving" or "On cooldown", fireGates)
    end
    if not moving then
        for _, name in ipairs(NukeCandidates(s)) do Offer(name, clearcasting and "Clearcast" or "Ranged damage", gates, false, true) end
        Wand(s, "Out of mana", nil, false)
    end
    AddAction(nil, moving and "Stop moving" or "Out of mana")
end

local mageDebug = {}

function M.NextSpell(s, inCombat, hostile)
    M.NormalizeBuild(s)
    lastRotation = { at = GetTime(), actions = {} }
    if Enabled(s,"frost") then FrostfireTalent("Fingers of Frost") end
    if Enabled(s,"frostfire") or Enabled(s,"fire") then FrostfireTalent("Improved Scorch") end
    local mana, moving = GateManaPercent(), PlayerMoving()
    local hp, targetHP = HealthPercent("player"), hostile and HealthPercent("target") or nil
    if not inCombat and hostile and not moving and not PlayerIsCastingOrChanneling() and Enabled(s,"frostBlast") then
        Offer("Frost Blast","optional quick slow opener",DamageGates(s,mana,targetHP))
    end
    if PlayerIsCastingOrChanneling() then AddAction(nil, "Casting")
    else
        if inCombat then Defense(s, hostile, hp, mana) end
        RecoverMana(s, mana, moving, inCombat, hostile)
        if not inCombat then Preparation(s) end
        if hostile then Offensive(s, inCombat, targetHP, mana, moving) end
    end
    AddAction(nil, not hostile and inCombat and "No target" or "Ready")
    local base = lastRotation.actions[#lastRotation.actions]
    lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
    mageDebug = { mana=mana, manaSource=lastManaSource, threshold=WandManaThreshold(s),
        blocked=mana ~= nil and WandEligible(s) and mana <= WandManaThreshold(s) or nil,
        candidate=base.spell, candidateReason=base.reason, final=base.spell, finalReason=base.reason }
    return base.spell, base.reason
end

function M.CanTrackSuggestedSpell(name)
    if not lastRotation or GetTime() - lastRotation.at > 0.5 or lastRotation.visualCandidate then return false end
    local visual = AL.rotationSecretVisual
    if visual and GetTime() - visual.at <= 0.5 then return false end
    if name ~= lastRotation.baseSpell or not Ok(name) then return false end
    for _, entry in ipairs(M.spells) do if entry[2] == name then return true end end
    return name == "Berserking"
end

function M.OnTargetChanged() lastRotation, AL.rotationSecretVisual = nil, nil end

function M.RefreshManaCache()
    EnsureTrackedMana(); RefreshManaRegen(); RefreshManaSensor()
end

function M.OnManaCastSent(name)
    castSentCount = castSentCount + 1
    local pct = LiveManaPercent()
    if pct ~= nil and EnsureTrackedMana() then
        trackedCostsKnown = true
        trackedMana = trackedManaMax * pct / 100
        trackedManaUpdatedAt = GetTime()
    end
    lastSentCastName, lastSentCastAt = name, GetTime()
    if name then cooldownSnapshots[name] = nil end
    if name == "Shoot" and LiveWandActive() then wandStopPendingUntil = GetTime() + 0.5 end
    return { cost = name and SpellManaCost(name), at=GetTime() }
end

function M.OnManaCastSucceeded(name, id, guid, sent)
    -- Triggered missiles and the charge aura can carry the cast's name.
    -- Only its castable ID may spend mana; readable SENT still identifies a
    -- success whose ID is protected. This prevents charging every missile.
    if (Enabled(AL.S(),"arcane") or Enabled(AL.S(),"frostfire") or Enabled(AL.S(),"fire") or Enabled(AL.S(),"frost")) and ARCANE_CASTS[name] and Number(id)~=nil
        and ArcaneCastName(id)~=name then return end
    castSucceededCount = castSucceededCount + 1
    lastSucceededCastName, lastSentCastName, lastSentCastAt = name, nil, 0
    if not name then return end
    if WAND_HANDOFF_SPELLS[name] or ArcaneHandoff(name) then cooldownSnapshots[name] = nil end
    if id == nil then castFallbackCount = castFallbackCount + 1 end
    local pct = LiveManaPercent()
    if pct ~= nil and EnsureTrackedMana() then
        trackedCostsKnown = true
        trackedMana = trackedManaMax * pct / 100
        trackedManaUpdatedAt, trackedSource = GetTime(), "successful-cast readable mana"
        trackedLastSpell, trackedLastCost = name, (sent and sent.mana and sent.mana.cost) or SpellManaCost(name) or 0
    else
        SpendTrackedMana(name, sent and sent.mana and sent.mana.cost)
    end
end

function M.OnCastResult(name, result)
    if result == "UNIT_SPELLCAST_SUCCEEDED" then
        if name == "Shoot" then
            wandPendingUntil = GetTime() + 0.5
            wandRecoveryUntil = GetTime() + 1.5
        end
        if name == "Conjure Water" or name == "Conjure Food" or name == "Conjure Mana Agate" then conjureLocks[name] = GetTime() + 1.5 end
    elseif result == "UNIT_SPELLCAST_FAILED" or result == "UNIT_SPELLCAST_FAILED_QUIET" or result == "UNIT_SPELLCAST_INTERRUPTED" then
        lastSentCastName, lastSentCastAt = nil, 0
        if name == "Shoot" then wandPendingUntil = 0 end
    end
end

-- Observe real casts independently of Core's name inference. Arcane Blast
-- grants its charge on successful cast even when damage misses. The buff
-- lasts eighteen seconds from its first application and survives other spells.
local arcanePending,arcaneFinished,arcaneProcSeen,arcaneLastSent={},{},{},nil
local function ArcaneGUID(value)
    return SafeValue(value) and type(value)=="string" and value:find("^Cast%-") and value or nil
end
local function AcceptArcaneCast(name,sent)
    local now=GetTime()
    arcaneRetry[name]=nil;arcaneAuraCache=nil
    if (ARCANE_DAMAGE[name] or POM_CASTS[name])
        and (sent and sent.clearSerial==fireState.clearSerial or not sent and now-fireState.clearChanged>0) then
        fireState.clearEnd,fireState.clearChanged,fireState.auraAt=0,now,nil
    end
    if name=="Arcane Blast" then
        if arcaneState.expires<=now then arcaneState.charges=0 end
        if arcaneState.charges==0 then arcaneState.expires=now+18 end
        arcaneState.charges=math.min(4,arcaneState.charges+1)
        arcaneChanged.charges=now
    end
    if name=="Arcane Missiles" then arcaneState.barrage=0;arcaneChanged.barrage=now end
    if name=="Pyroblast" and arcaneState.pom then ff.pomPyroAt=now end
    if POM_CASTS[name] then SpendPresence() end
    if name=="Presence of Mind" then
        arcaneState.pom=true;arcaneChanged.pom=now
        -- Its three-minute cooldown starts when the instant cast is spent.
    elseif ARCANE_COOLDOWNS[name] then StartArcaneCooldown(name) end
end
local arcaneTracker=CreateFrame("Frame")
for _,event in ipairs({"UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_FAILED_QUIET","UNIT_SPELLCAST_INTERRUPTED","UNIT_AURA",
    "PLAYER_DEAD","PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED","SPELLS_CHANGED",
    "PLAYER_TALENT_UPDATE","ACTIVE_TALENT_GROUP_CHANGED"}) do pcall(arcaneTracker.RegisterEvent,arcaneTracker,event) end
arcaneTracker:SetScript("OnEvent",function(_,event,unit,arg2,arg3,arg4)
    if AL.playerClass~="MAGE" then return end
    if event=="PLAYER_DEAD" or event=="PLAYER_ENTERING_WORLD" then
        arcaneState={charges=0,expires=0,barrage=0,pom=false};arcaneChanged={}
        arcaneAuraCache,arcaneAurasBlocked=nil,nil
        arcanePending,arcaneFinished,arcaneProcSeen,arcaneLastSent={},{},{},nil;arcaneRetry={}
        return
    end
    if event=="PLAYER_REGEN_ENABLED" or event=="SPELLS_CHANGED" or event=="PLAYER_TALENT_UPDATE"
        or event=="ACTIVE_TALENT_GROUP_CHANGED" then arcaneAuraCache,arcaneAurasBlocked=nil,nil;return end
    if not SafeValue(unit) or unit~="player" then return end
    if event=="UNIT_AURA" then arcaneAuraCache=nil;return end
    local now=GetTime()
    for guid,sent in pairs(arcanePending) do if now-sent.at>30 then arcanePending[guid]=nil end end
    for guid,at in pairs(arcaneFinished) do if now-at>900 then arcaneFinished[guid]=nil end end
    for guid,at in pairs(arcaneProcSeen) do if now-at>900 then arcaneProcSeen[guid]=nil end end
    local guid=ArcaneGUID(event=="UNIT_SPELLCAST_SENT" and arg3 or arg2)
    local id=Number(arg4) or Number(arg3)
    -- A positive public proc ID is evidence; attempted casts and probability
    -- are not. The aura ID itself is never a castable spell-list entry.
    if event=="UNIT_SPELLCAST_SUCCEEDED" and (id==400589 or id==44404) then
        if guid and arcaneProcSeen[guid] then return end
        if guid then arcaneProcSeen[guid]=now end
        arcaneState.barrage=now+15;arcaneChanged.barrage=now;arcaneAuraCache=nil;return
    end
    local name=ArcaneCastName(id)
    local readable=id~=nil
    if not readable and SafeValue(arg2) and type(arg2)=="string" then
        local raw=(AL.englishNames and AL.englishNames[arg2]) or arg2
        if ARCANE_CASTS[raw] or POM_CASTS[raw] then name,readable=raw,true end
    end
    if event=="UNIT_SPELLCAST_SENT" then
        if not readable and M.CanTrackSuggestedSpell and M.CanTrackSuggestedSpell(AL.lastSuggestion)
            and (ARCANE_CASTS[AL.lastSuggestion] or POM_CASTS[AL.lastSuggestion]) then name=AL.lastSuggestion end
        if Enabled(AL.S(),"fire") then ReadFireBuffs() end
        arcaneLastSent={name=name,at=now,guid=guid,clearSerial=fireState.clearSerial}
        if guid then arcanePending[guid]=arcaneLastSent end
        return
    end
    local sent=guid and arcanePending[guid] or not guid and arcaneLastSent
    if event~="UNIT_SPELLCAST_SUCCEEDED" and event~="UNIT_SPELLCAST_CHANNEL_START" then
        if sent and not sent.done then
            sent.failed=true
            if sent.name then arcaneRetry[sent.name]=now+0.5 end
        end
        if guid then arcaneFinished[guid]=now end
        return
    end
    if guid and arcaneFinished[guid] or sent and (sent.failed or sent.done) then return end
    if not readable and sent and now-sent.at<=15 then name=sent.name end
    if not name or sent and sent.name and sent.name~=name then return end
    if sent then sent.done=true end
    if guid then arcaneFinished[guid]=now end
    AcceptArcaneCast(name,sent)
end)

local function AcceptFrostfireCast(name,sent)
    local now=GetTime()
    ff.retry[name],ff.auraAt=nil,nil
    if name=="Ice Barrier" then frostState.barrierEnd,frostState.barrierChanged=now+60,now end
    if name=="Cold Snap" then
        for spell in pairs(FROST_RESETTABLE) do
            ff.ends[spell],ff.retry[spell],ff.changed[spell],cooldownSnapshots[spell]=0,nil,-math.huge,nil
        end
        frostState.resetAt=now
    end
    if name=="Combustion" then
        fireState.combustion,fireState.crits=true,0
        fireState.combustionChanged,fireState.at,fireState.auraAt=now,now,nil
        -- No cooldown starts until the buff is consumed or removed.
    end
    if name=="Pyroblast" then
        local usedPresence=sent and sent.pomBefore or arcaneState.pom or ff.pomPyroAt==now
        if not usedPresence then ff.heat,ff.heatEnd,ff.changed.heat=0,0,now end
        ff.pyroSpentAt=now
    elseif name=="Fire Blast" and FrostfireTalent("Heating Up")==1
        and (not sent or (sent.heatAuraSerial or 0)==(ff.heatAuraSerial or 0)) then
        if ff.heatEnd<=now then ff.heat=0 end
        ff.heat,ff.heatEnd,ff.changed.heat=math.min(3,ff.heat+1),now+20,now
        ff.auraAt=nil
    end
    if name=="Scorch" then
        ff.lastScorch=nil
        if (ff.scorchTryUntil or 0)<=now then ff.scorchTries=0 end
        ff.scorchTries,ff.scorchTryUntil=(ff.scorchTries or 0)+1,now+25
    end
    if name=="Scorch" and FrostfireTalent("Improved Scorch")==3
        and now-(ff.vulnEvidenceAt or -math.huge)>=0.3 then
        -- Confirmed casts are only an estimate of landed Scorches when the
        -- client protects auras/logs. Bound the build-up at five, then leave
        -- the Scorch phase until the 25-second refresh; readable state wins.
        ff.lastScorch={at=now,before=ff.vuln,expires=ff.vulnEnd}
        if ff.vulnEnd<=now then ff.vuln=0 end
        ff.vuln,ff.vulnEnd,ff.changed.vuln=math.min(5,ff.vuln+1),now+30,now
    end
    if ARCANE_DAMAGE[name] and ff.fof>0 and (not Enabled(AL.S(),"frost")
        or sent and sent.fofSerial==frostState.fofSerial
        or not sent and now-(ff.changed.fof or -math.huge)>0) then
        ff.fof,ff.changed.fof=math.max(0,ff.fof-1),now
    end
    if name=="Flamestrike" then ff.flamestrikeEnd=now+8 end
    local fallback=FROST_COOLDOWNS[name]
    if fallback then
        local ms=Number((SafeCall(C_Spell and C_Spell.GetSpellBaseCooldown or GetSpellBaseCooldown,LearnedID(name) or name)))
        if ms and ms>1500 and ms<=3600000 then fallback=ms/1000 end
        ff.ends[name],ff.changed[name]=NativeArcaneEnd(name) or now+fallback,now
    end
end
local frostfireTracker=CreateFrame("Frame")
for _,event in ipairs({"UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET","UNIT_SPELLCAST_INTERRUPTED","UNIT_AURA","SPELLS_CHANGED",
    "PLAYER_LOGIN","PLAYER_DEAD","PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED",
    "PLAYER_TALENT_UPDATE","ACTIVE_TALENT_GROUP_CHANGED","COMBAT_LOG_EVENT_UNFILTERED"}) do
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" or type(CombatLogGetCurrentEventInfo) == "function" then pcall(frostfireTracker.RegisterEvent,frostfireTracker,event) end
end
frostfireTracker:SetScript("OnEvent",function(_,event,unit,arg2,arg3,arg4)
    if AL.playerClass~="MAGE" then return end
    local now=GetTime()
    if event=="PLAYER_DEAD" or event=="PLAYER_ENTERING_WORLD" then
        if event=="PLAYER_DEAD" then FinishFireCombustion() end
        fireState.clearEnd,fireState.clearChanged,fireState.combustion=0,-math.huge,false
        fireState.combustionChanged,fireState.crits=-math.huge,0
        fireState.auraAt,fireState.blocked,fireState.procSeen=nil,nil,{}
        ff.heat,ff.heatEnd,ff.vuln,ff.vulnEnd,ff.fof,ff.fofEnd=0,0,0,0,0,0
        ff.changed,ff.retry,ff.pending,ff.finished,ff.seen={},{},{},{},{}
        ff.auraAt,ff.blocked,ff.lastSent,ff.lastScorch,ff.flamestrikeEnd,ff.pyroSpentAt=nil,nil,nil,nil,nil,nil
        ff.scorchTries,ff.scorchTryUntil,ff.vulnReadable=0,0,false
        ff.vulnEvidenceAt,ff.heatDoseStamp=nil,nil
        frostState.barrierEnd,frostState.barrierChanged,frostState.barrierBlocked=0,-math.huge,nil
        frostState.fofSerial,frostState.fofSignature,frostState.resetAt=0,nil,nil
        frostState.fofReadCount,frostState.fofReadEnd=nil,nil
        return
    end
    if event=="SPELLS_CHANGED" or event=="PLAYER_TALENT_UPDATE" or event=="ACTIVE_TALENT_GROUP_CHANGED" then
        ff.talents,ff.talentWarm={},nil
        ff.auraAt,ff.blocked=nil,nil
        fireState.auraAt,fireState.blocked=nil,nil
        if Bool((SafeCall(UnitAffectingCombat,"player")))==false then FrostfireTalent("Improved Scorch") end
        return
    end
    if event=="PLAYER_LOGIN" or event=="PLAYER_REGEN_ENABLED" then
        ff.auraAt,ff.blocked=nil,nil
        frostState.barrierBlocked=nil
        fireState.auraAt,fireState.blocked=nil,nil
        if not ff.talents["Improved Scorch"] then ff.talentWarm=nil end
        FrostfireTalent("Improved Scorch");return
    end
    if event=="COMBAT_LOG_EVENT_UNFILTERED" then
        if not (Enabled(AL.S(),"frostfire") or Enabled(AL.S(),"fire") or Enabled(AL.S(),"frost")) or type(CombatLogGetCurrentEventInfo)~="function" then return end
        local ok,stamp,kind,_,source,_,_,_,destination,_,_,_,id,_,_,amount,dose,_,_,_,_,critical=pcall(CombatLogGetCurrentEventInfo)
        local player=SafeCall(UnitGUID,"player")
        if not ok or not SafeValue(kind) or type(kind)~="string" or not SafeValue(source)
            or type(source)~="string" or not SafeValue(player) or type(player)~="string" or source~=player then return end
        id=Number(id);stamp=Number(stamp)
        if not id then return end
        if stamp then
            local destinationKey=SafeValue(destination) and type(destination)=="string" and destination or ""
            local key="log:"..tostring(stamp)..":"..kind..":"..tostring(id)..":"..destinationKey
                ..":"..tostring(Number(dose) or "")
            if ff.seen[key] then return end
            ff.seen[key]=now
        end
        if kind=="SPELL_MISSED" and ArcaneCastName(id)=="Scorch" and ff.lastScorch and now-ff.lastScorch.at<=3 then
            ff.vuln,ff.vulnEnd=ff.lastScorch.before,ff.lastScorch.expires
            ff.lastScorch=nil;ff.changed.vuln=now;return
        end
        if (kind=="SPELL_AURA_APPLIED" or kind=="SPELL_AURA_APPLIED_DOSE" or kind=="SPELL_AURA_REMOVED"
            or kind=="SPELL_AURA_REMOVED_DOSE")
            and SafeValue(destination) and destination==player then
            if ArcaneCastName(id)=="Ice Barrier" then
                frostState.barrierEnd=kind=="SPELL_AURA_REMOVED" and 0 or now+60
                frostState.barrierChanged=now
            end
            if id==12536 then
                fireState.clearEnd=kind=="SPELL_AURA_REMOVED" and 0 or now+15
                if kind~="SPELL_AURA_REMOVED" then fireState.clearSerial=fireState.clearSerial+1 end
                fireState.clearChanged,fireState.auraAt=now,nil
            elseif id==11129 or id==28682 then
                if kind=="SPELL_AURA_REMOVED" then FinishFireCombustion()
                else fireState.combustion,fireState.combustionChanged=true,now end
                fireState.auraAt=nil
            end
            local key=id==400625 and "heat" or id==22959 and "vuln" or id==400669 and "fof"
            if key then
                if key=="fof" and Enabled(AL.S(),"frost") then
                    if kind=="SPELL_AURA_REMOVED" then
                        ff.fof,ff.fofEnd,ff.changed.fof=0,0,now
                        frostState.fofSignature=nil
                    else
                        local stacks=Number(dose)
                        if kind=="SPELL_AURA_APPLIED" then
                            stacks=FrostfireTalent("Fingers of Frost") or 1
                            frostState.fofSerial=frostState.fofSerial+1
                        end
                        ObserveFrostFingers(stacks,now+15)
                    end
                    ff.auraAt=nil;return
                end
                local stacks=kind=="SPELL_AURA_REMOVED" and 0 or kind=="SPELL_AURA_APPLIED" and 1
                    or Number(dose)
                local cap=key=="heat" and 3 or key=="vuln" and 5 or 2
                if stacks and stacks>=0 and stacks<=cap then
                    ff[key],ff[key.."End"],ff.changed[key]=stacks,now+(key=="vuln" and 30 or key=="heat" and 20 or 15),now
                    if key=="heat" then ff.heatDoseStamp=stamp;ff.heatAuraSerial=(ff.heatAuraSerial or 0)+1 end
                    if key=="vuln" then ff.vulnEvidenceAt=now end
                    ff.auraAt=nil
                end
            end
            return
        end
        local name=ArcaneCastName(id)
        if kind=="SPELL_DAMAGE" and stamp and Bool(critical)==true and fireState.combustion
            and (name=="Fireball" or name=="Frostfire Bolt" or name=="Scorch" or name=="Fire Blast"
                or name=="Pyroblast" or name=="Flamestrike") then
            fireState.crits=fireState.crits+1
            if fireState.crits>=3 then FinishFireCombustion() end
        end
        if kind=="SPELL_DAMAGE" and Bool(critical)==true and stamp and ff.heatDoseStamp~=stamp and FrostfireTalent("Heating Up")==1
            and (name=="Frostfire Bolt" or name=="Fireball" or name=="Scorch" or name=="Fire Blast") then
            local key=tostring(stamp)..":"..tostring(id)
            if ff.seen[key] then return end
            ff.seen[key]=now
            if ff.heatEnd<=now then ff.heat=0 end
            ff.heat,ff.heatEnd,ff.changed.heat=math.min(3,ff.heat+1),now+20,now;ff.auraAt=nil
        end
        return
    end
    if not SafeValue(unit) or unit~="player" then return end
    if event=="UNIT_AURA" then
        ff.auraAt,ff.blocked=nil,nil;fireState.auraAt,fireState.blocked=nil,nil
        frostState.barrierBlocked=nil
        if Enabled(AL.S(),"frost") then FrostfireAuras() end
        return
    end
    if event=="UNIT_SPELLCAST_CHANNEL_START" and not Enabled(AL.S(),"frost") then return end
    for guid,sent in pairs(ff.pending) do if now-sent.at>30 then ff.pending[guid]=nil end end
    for guid,at in pairs(ff.finished) do if now-at>900 then ff.finished[guid]=nil end end
    for key,at in pairs(ff.seen) do if now-at>900 then ff.seen[key]=nil end end
    local guid=ArcaneGUID(event=="UNIT_SPELLCAST_SENT" and arg3 or arg2)
    local id=Number(arg4) or Number(arg3)
    if event=="UNIT_SPELLCAST_SUCCEEDED" and id==400669 and Enabled(AL.S(),"frost") then
        if guid and ff.seen[guid] then return end
        if guid then ff.seen[guid]=now end
        frostState.fofSerial=frostState.fofSerial+1
        ff.fof,ff.fofEnd,ff.changed.fof=math.min(2,math.max(1,FrostfireTalent("Fingers of Frost") or 1)),now+15,now
        ff.auraAt=nil;return
    end
    if event=="UNIT_SPELLCAST_SUCCEEDED" and id==12536 then
        fireState.procSeen=fireState.procSeen or {}
        for key,at in pairs(fireState.procSeen) do if now-at>900 then fireState.procSeen[key]=nil end end
        if guid and fireState.procSeen[guid] then return end
        if guid then fireState.procSeen[guid]=now end
        fireState.clearEnd,fireState.clearChanged,fireState.auraAt=now+15,now,nil
        fireState.clearSerial=fireState.clearSerial+1
        return
    end
    local name=ArcaneCastName(id)
    local readable=id~=nil
    if not readable and SafeValue(arg2) and type(arg2)=="string" then
        local raw=(AL.englishNames and AL.englishNames[arg2]) or arg2
        if ARCANE_CASTS[raw] then name,readable=raw,true end
    end
    if event=="UNIT_SPELLCAST_SENT" then
        if not readable and M.CanTrackSuggestedSpell and M.CanTrackSuggestedSpell(AL.lastSuggestion)
            and ARCANE_CASTS[AL.lastSuggestion] then name=AL.lastSuggestion end
        if Enabled(AL.S(),"frost") then FrostfireAuras() end
        ff.lastSent={name=name,at=now,guid=guid,fofSerial=frostState.fofSerial,
            pomBefore=ReadArcaneState().pom,heatAuraSerial=ff.heatAuraSerial or 0}
        if guid then ff.pending[guid]=ff.lastSent end
        return
    end
    local sent=guid and ff.pending[guid] or not guid and ff.lastSent
    if ff.finished[guid] or sent and (sent.done or sent.failed) then return end
    if event~="UNIT_SPELLCAST_SUCCEEDED" and event~="UNIT_SPELLCAST_CHANNEL_START" then
        if sent then sent.failed=true;if sent.name then ff.retry[sent.name]=now+0.5 end end
        if guid then ff.finished[guid]=now end
        return
    end
    if not readable and sent and now-sent.at<=15 then name=sent.name end
    if not name or sent and sent.name and name~=sent.name then return end
    if sent then sent.done=true end
    if guid then ff.finished[guid]=now end
    AcceptFrostfireCast(name,sent)
end)

local tracker = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_DEAD", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(tracker.RegisterEvent, tracker, event)
end
tracker:SetScript("OnEvent", function(_, event, unit, token)
    if event == "SPELL_UPDATE_COOLDOWN" then ObserveCooldowns()
    elseif event == "SPELLS_CHANGED" then cooldownSnapshots = {}
    elseif event == "PLAYER_STARTED_MOVING" then movementEventActive = true
    elseif event == "PLAYER_STOPPED_MOVING" then movementEventActive = false
    elseif event == "START_AUTOREPEAT_SPELL" then wandEventActive, wandPendingUntil = true, GetTime()+0.5
    elseif event == "STOP_AUTOREPEAT_SPELL" then wandEventActive, wandPendingUntil, wandStopPendingUntil = false, 0, 0
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
        trackedCostsKnown = true
        trackedMana, trackedManaMax, trackedManaUpdatedAt, trackedLastSpendAt = nil, nil, nil, nil
        trackedLastSpell, trackedLastCost, trackedSource = nil, 0, "uninitialized"
        eventManaPct, eventManaAt, eventManaSource = nil, nil, "unreadable"
        wandEventActive, wandPendingUntil, conjureLocks, curveFailures = false, 0, {}, {}
        movementEventActive, curveCapabilities, visibilityCurves = nil, {}, {}
        wandStopPendingUntil = 0
        wandRecoveryUntil = 0
        cooldownSnapshots = {}
        lastSentCastName, lastSentCastAt, lastRotation, AL.rotationSecretVisual = nil, 0, nil, nil
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        M.RefreshManaCache()
    elseif SafeValue(unit) and unit == "player" and (not SafeValue(token) or token == nil or token == "MANA") then
        RefreshManaSensor()
    end
end)

function M.GetUIState()
    local s = AL.S()
    return { nuke=PrimaryNuke(s), primaryFire=Enabled(s,"primaryFire"),
        mana=GateManaPercent(), manaSource=lastManaSource, wandThreshold=WandManaThreshold(s),
        moving=PlayerMoving(), enemyCount=Enabled(s,"aoe") and EnemyCount(SettingNumber(s,"aoeMinEnemies",3,2,8)) or nil,
        fireEnemyCount=Enabled(s,"primaryFire") and EnemyCount(8) or nil, wanding=PlayerIsWanding(),
        arcaneStacks=arcaneState.expires>GetTime() and arcaneState.charges or 0,
        arcaneBuffRemaining=math.max(0,arcaneState.expires-GetTime()),
        missileBarrageRemaining=math.max(0,arcaneState.barrage-GetTime()), presenceOfMind=arcaneState.pom,
        heatingUp=ff.heatEnd>GetTime() and ff.heat or 0,
        arcaneWrathID=LearnedID("Arcane Wrath"), frostBlastID=LearnedID("Frost Blast") }
end

function M.ManaGateState()
    local s = AL.S(); local mana = GateManaPercent()
    return { mana=mana, source=lastManaSource, threshold=WandManaThreshold(s), blocked=mageDebug.blocked,
        trackedPct=TrackedManaPercent(), trackedMana=trackedMana, trackedManaMax=trackedManaMax, trackedSource=trackedSource,
        lastSpell=trackedLastSpell, lastCost=trackedLastCost, eventManaPct=eventManaPct, eventManaSource=eventManaSource,
        eventManaAge=eventManaAt and GetTime()-eventManaAt, manaEventCount=manaEventCount,
        castSentCount=castSentCount, castSucceededCount=castSucceededCount, castFallbackCount=castFallbackCount,
        lastSentCastName=lastSentCastName, lastSucceededCastName=lastSucceededCastName,
        candidate=mageDebug.candidate, candidateReason=mageDebug.candidateReason, final=mageDebug.final, finalReason=mageDebug.finalReason }
end
function M.ManaPercent() return GateManaPercent(), lastManaSource, TrackedManaPercent() end
function M.DecisionDebugState() return mageDebug end

IntervalCurve = function(low, high)
	local factory = C_CurveUtil.CreateColorCurve
	if visibilityCurveFactory ~= factory then
		visibilityCurves, visibilityCurveFactory = {}, factory
	end
	local key = tostring(low) .. ":" .. tostring(high)
	if visibilityCurves[key] then return visibilityCurves[key] end
	local curve = factory()
	curve:SetType(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	if low > 1 or high <= 0 then
		curve:AddPoint(0, CreateColor(1, 1, 1, 0));curve:AddPoint(1, CreateColor(1, 1, 1, 0))
		visibilityCurves[key] = curve;return curve
	end
	curve:AddPoint(0, CreateColor(1, 1, 1, low == 0 and 1 or 0))
	if low > 0 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
	if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
	if low ~= 1 and high ~= 1 then curve:AddPoint(1, CreateColor(1, 1, 1, high > 1 and 1 or 0)) end
	visibilityCurves[key] = curve
	return curve
end

ReadVisualAlpha = function(mask)
    local curve = IntervalCurve(mask.low, mask.high)
    local color
    if mask.kind == "power" then color = UnitPowerPercent(mask.unit, mask.powerType, false, curve)
    else color = UnitHealthPercent(mask.unit, false, curve) end
    local _, _, _, alpha = color:GetRGBA()
    if SafeValue(alpha) and Number(alpha) == nil then error("Mage resource curve returned no display alpha") end
    return alpha
end

function M.SecretVisualPlan(spell, reason)
	local d = lastRotation
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
	d.visualPlan = plan
	return plan
end

function M.EvaluateVisualMasks(plan)
	local values = {}
	local ok = pcall(function()
		for key, mask in pairs(plan.masks) do
			local success, value = pcall(ReadVisualAlpha, mask)
			if not success then
				curveFailures[mask.kind .. ":" .. mask.unit .. ":" .. tostring(mask.powerType or "")] = {
					reader = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent,
					factory = C_CurveUtil and C_CurveUtil.CreateColorCurve }
				error("Mage resource curve unavailable")
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
                curveFailures[mask.kind .. ":" .. mask.unit .. ":" .. tostring(mask.powerType or "")] = {
                    reader = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent,
                    factory = C_CurveUtil and C_CurveUtil.CreateColorCurve }
                error("Mage resource alpha unavailable")
            end
        else node:SetAlpha(1) end
	end
end




AL.RegisterRotation("MAGE", M)
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
    root.RegisterRotation("MAGE", advanced)
end
