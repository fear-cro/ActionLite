local ADDON, AL = ...

-- ActionLITE Shaman v0.17.4: original Leveling plus optional talent builds.

-- Leveling keeps the finalized pre-simulation implementation in its own
-- scope. Talent builds use the separate implementation below. Both observe
-- real casts so switching rotations retains resource and spell history.
do
    local root = AL
    local leveling, advanced
    local function UsesLeveling(profile)
        profile = profile or (root.Profile and root.Profile("SHAMAN")) or (root.S and root.S())
        if advanced and type(profile) == "table" then
            return advanced.NormalizeBuild(profile) == "leveling"
        end
        return true
    end
    local function RotationScope(isLeveling)
        local scope = {
            RegisterRotation = function(token, module)
                assert(token == "SHAMAN", "Unexpected class rotation")
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
                    if root.playerClass == "SHAMAN" and UsesLeveling() == isLeveling then root[key] = value end
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
-- BEGIN ORIGINAL LEVELING IMPLEMENTATION (Shaman(1).lua)
local ADDON, AL = ...

-- WoW Forever Shaman Enhancement / Elemental leveling 1-30 - v0.14.6
-- Target: beta 1.60.1.69913.
-- Status: client validation required for costs, ranks and talents.
-- Protected values stay unknown and are never treated as zero.

local A = _G.Action

local M = {
	defaults = {
		shamanRole = "ENHANCEMENT",
		shield = true,
		weapon = true,
		weaponMode = "AUTO",
		totems = true,
		earthTotemMode = "AUTO",
		waterTotemMode = "AUTO",
		searing = true,
		interrupt = true,
		flameshock = true,
		earthshock = true,
		frostshock = true,
		stormstrike = true,
		lightningbolt = true,
		heal = true,
		stoneclaw = true,
		drink = true,
		aoe = false,
		firenova = true,
		magma = true,
		healHP = 35,
		healOutOfCombatHP = 70,
		healMinMana = 10,
		stoneclawHP = 25,
		drinkMana = 30,
		shockMinMana = 25,
		lightningBoltMinMana = 15,
		flameShockMinTargetHP = 35,
		frostShockTargetHP = 25,
		totemMinTargetHP = 45,
		aoeMinEnemies = 2,
		aoeMinMana = 30,
		burstMinTargetHP = 40,
	},
}

-- Rank-one IDs used for scans and icons. Their presence does not prove
-- Forever's learning level; the safeguards below remain
-- LIKELY until checked in the target build.
M.spells = {
	{ 2008, "Ancestral Spirit" },
	{ 556, "Astral Recall" },
	{ 526, "Cure Poison" },
	{ 8042, "Earth Shock" },
	{ 2484, "Earthbind Totem" },
	{ 6196, "Far Sight" },
	{ 1535, "Fire Nova Totem" },
	{ 8184, "Fire Resistance Totem" },
	{ 8050, "Flame Shock" },
	{ 8227, "Flametongue Totem" },
	{ 8024, "Flametongue Weapon" },
	{ 8181, "Frost Resistance Totem" },
	{ 8056, "Frost Shock" },
	{ 2645, "Ghost Wolf" },
	{ 8177, "Grounding Totem" },
	{ 5394, "Healing Stream Totem" },
	{ 331, "Healing Wave" },
	{ 8004, "Lesser Healing Wave" },
	{ 403, "Lightning Bolt" },
	{ 324, "Lightning Shield" },
	{ 8190, "Magma Totem" },
	{ 5675, "Mana Spring Totem" },
	{ 8166, "Poison Cleansing Totem" },
	{ 370, "Purge" },
	{ 8017, "Rockbiter Weapon" },
	{ 3599, "Searing Totem" },
	{ 5730, "Stoneclaw Totem" },
	{ 8071, "Stoneskin Totem" },
	{ 17364, "Stormstrike" },
	{ 8075, "Strength of Earth Totem" },
	{ 8143, "Tremor Totem" },
	{ 131, "Water Breathing" },
	{ 546, "Water Walking" },
	{ 8232, "Windfury Weapon" },
}

-- Historical levels retained only as references. They no longer drive
-- the rotation: Forever can change them. Spellbook scans and Core's
-- FUTURESPELL rejection determine which spells are actually available.
local REFERENCE_LEVELS = {
	["Lightning Bolt"] = 1,
	["Healing Wave"] = 1,
	["Rockbiter Weapon"] = 1,
	["Earth Shock"] = 4,
	["Stoneskin Totem"] = 4,
	["Earthbind Totem"] = 6,
	["Lightning Shield"] = 8,
	["Stoneclaw Totem"] = 8,
	["Flame Shock"] = 10,
	["Flametongue Weapon"] = 10,
	["Searing Totem"] = 10,
	["Strength of Earth Totem"] = 10,
	["Ancestral Spirit"] = 12,
	["Fire Nova Totem"] = 12,
	["Purge"] = 12,
	["Cure Poison"] = 16,
	["Tremor Totem"] = 18,
	["Frost Shock"] = 20,
	["Ghost Wolf"] = 20,
	["Healing Stream Totem"] = 20,
	["Lesser Healing Wave"] = 20,
	["Poison Cleansing Totem"] = 22,
	["Water Breathing"] = 22,
	["Fire Resistance Totem"] = 24,
	["Frost Resistance Totem"] = 24,
	["Far Sight"] = 26,
	["Magma Totem"] = 26,
	["Mana Spring Totem"] = 26,
	["Flametongue Totem"] = 28,
	["Water Walking"] = 28,
	["Astral Recall"] = 30,
	["Grounding Totem"] = 30,
	["Windfury Weapon"] = 30,
}
M.minLevels = REFERENCE_LEVELS

local function Ok(name)
	if type(AL.Ok) == "function" then return AL.Ok(name) and true or false end
	return AL.known and AL.known[name] and true or false
end

local SHOCKS = {
	["Earth Shock"] = true,
	["Flame Shock"] = true,
	["Frost Shock"] = true,
}
local WEAPON_ENCHANTS = {
	["Windfury Weapon"] = true,
	["Rockbiter Weapon"] = true,
	["Flametongue Weapon"] = true,
}
-- Temporary weapon-enchant IDs taken from the reference TBC Shaman profile.
-- Reference only: Forever IDs can differ. An unknown ID
-- does not prove the enchant is wrong; a confirmed cast takes priority.
local WEAPON_ENCHANT_IDS = {
	["Windfury Weapon"] = {
		[283] = true, [284] = true, [525] = true, [1669] = true,
		[2636] = true, [3785] = true,
	},
	["Flametongue Weapon"] = {
		[3] = true, [4] = true, [5] = true, [1665] = true,
		[1666] = true, [2634] = true, [3780] = true, [3781] = true,
	},
	["Rockbiter Weapon"] = {
		[1] = true, [6] = true, [29] = true, [503] = true, [504] = true,
		[683] = true, [1663] = true, [1664] = true, [2632] = true,
		[2633] = true,
	},
}
local TOTEM_GROUPS = {
	FIRE = { "Searing Totem", "Magma Totem", "Fire Nova Totem", "Fire Resistance Totem" },
	EARTH = { "Strength of Earth Totem", "Stoneskin Totem", "Stoneclaw Totem", "Earthbind Totem", "Tremor Totem" },
	WATER = { "Healing Stream Totem", "Mana Spring Totem", "Poison Cleansing Totem", "Frost Resistance Totem" },
}
local TOTEM_ELEMENT = {}
for element, names in pairs(TOTEM_GROUPS) do
	for _, name in ipairs(names) do TOTEM_ELEMENT[name] = element end
end

-- LIKELY fallback durations: GetTotemInfo always takes priority. These
-- deliberately conservative values prevent repeated suggestions when
-- Forever temporarily protects totem state.
local TOTEM_FALLBACK = {
	["Searing Totem"] = 30,
	["Magma Totem"] = 20,
	["Fire Nova Totem"] = 5,
	["Fire Resistance Totem"] = 120,
	["Strength of Earth Totem"] = 120,
	["Stoneskin Totem"] = 120,
	["Stoneclaw Totem"] = 15,
	["Earthbind Totem"] = 45,
	["Tremor Totem"] = 120,
	["Healing Stream Totem"] = 60,
	["Mana Spring Totem"] = 60,
	["Poison Cleansing Totem"] = 120,
	["Frost Resistance Totem"] = 120,
}

local trackedTotems, localCooldowns = {}, {}
local trackedWeapon, trackedWeaponUntil, trackedWeaponCastAt, trackedWeaponIdentity, trackedWeaponEnchantID
local trackedWeaponObservation = {}
local shockLockUntil, shockCastAt = 0, nil

-- Full rotation restored after the incorrect Lightning Bolt binding was confirmed.
-- Lightning Bolt stays direct; Attack is only a melee-range fallback.

-- Rockbiter: 60 minutes reported by the player (exact build to be confirmed).
-- The same LIKELY fallback duration for Flametongue and Windfury needs in-game validation.
-- An absence that was never observed cannot cancel a confirmed cast.
local WEAPON_ENCHANT_FALLBACK_DURATION = 60 * 60


AL.selfCastSpells = AL.selfCastSpells or {}
for _, name in ipairs({ "Lightning Shield", "Healing Wave", "Lesser Healing Wave", "Rockbiter Weapon",
    "Flametongue Weapon", "Windfury Weapon", "Blood Fury", "Berserking" }) do AL.selfCastSpells[name] = true end
for name in pairs(TOTEM_ELEMENT) do AL.selfCastSpells[name] = true end
-- Shared native gates keep opaque percentages in native display alpha only.
local lastRotation
local visibilityCurves, curveFailures, curveCapabilities = {}, {}, {}
local IntervalCurve, ReadVisualAlpha
local curveProbe
local visibilityCurveFactory
local movementEventActive
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
    local current, maximum = Number((SafeCall(UnitHealth, unit))), Number((SafeCall(UnitHealthMax, unit)))
    local hp = current and maximum and maximum > 0 and Percent(current / maximum * 100) or nil
    if hp ~= nil then return hp end
    hp = Percent((SafeCall(AL.HealthPercent, unit)))
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
    local player = A and A.Player
    if SafeValue(player) and type(player) == "table" then
        pct = Percent((SafeCall(player.ManaPercentage, player)))
        if pct ~= nil then return pct, "Action.Player.ManaPercentage" end
    end
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
    return SafeValue(name) and type(name) == "string"
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
    Accept((SafeCall(AL.EnemyCount, 8)))
    if A and A.MultiUnits then
        Accept((SafeCall(A.MultiUnits.GetByRangeInCombat, A.MultiUnits, 8, limit or 5)))
        Accept((SafeCall(A.MultiUnits.GetActiveEnemies, A.MultiUnits, 8)))
    end
    local seen, visible = {}, 0
    local function Count(unit)
        if not SafeValue(unit) or type(unit) ~= "string" then return end
        if Bool((SafeCall(UnitExists, unit))) ~= true or Bool((SafeCall(UnitCanAttack, "player", unit))) ~= true
            or Bool((SafeCall(UnitIsDeadOrGhost, unit))) ~= false or Bool((SafeCall(UnitAffectingCombat, unit))) ~= true then return end
        local guid = SafeCall(UnitGUID, unit)
        if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] or UnitWithin(unit, 8) ~= true then return end
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

local function Role(s)
    return SettingChoice(s, "shamanRole", { ENHANCEMENT=true, ELEMENTAL=true }, "ENHANCEMENT")
end

local function ReadableCooldown(name)
    local start, duration = SafeCall(AL.SpellCooldown, name)
    start, duration = Number(start), Number(duration)
    if start and duration and start >= 0 and duration >= 0 then
        return start == 0 or duration <= 1.5 or start + duration <= GetTime(), start + duration
    end
end

local function CooldownReady(name)
    if SHOCKS[name] then
        if shockCastAt and GetTime() - shockCastAt < 0.5 then return false end
        local ready = ReadableCooldown(name)
        if ready ~= nil then return ready end
        if GetTime() < shockLockUntil then return false end
    end
    local localCD = localCooldowns[name]
    if localCD then
        if GetTime() - localCD.at < 0.5 then return false end
        local ready = ReadableCooldown(name)
        if ready ~= nil then return ready end
        if GetTime() < localCD.ends then return false end
    end
    return Bool((SafeCall(AL.IsReady, name))) == true
end

local function MainHandIdentity()
    local guid = SafeCall(GetInventoryItemGUID, "player", 16)
    if SafeValue(guid) and type(guid) == "string" and guid ~= "" then return "GUID:" .. guid end
    local id = Number((SafeCall(GetInventoryItemID, "player", 16)))
    if id and id > 0 then return "ID:" .. id end
end

local function WeaponStatePlayer()
    local guid = SafeCall(UnitGUID, "player")
    if SafeValue(guid) and type(guid) == "string" and guid ~= "" then return guid end
end

local function ClearTrackedWeapon(clearSaved)
    trackedWeapon, trackedWeaponUntil, trackedWeaponCastAt, trackedWeaponIdentity, trackedWeaponEnchantID = nil, nil, nil, nil, nil
    trackedWeaponObservation = {}
    if clearSaved and AL.playerClass == "SHAMAN" then
        local player = WeaponStatePlayer()
        local saved = ActionLiteDB and ActionLiteDB.shamanWeaponEnchants
        if player and SafeValue(saved) and type(saved) == "table" then saved[player] = nil end
    end
end

local function SaveTrackedWeapon()
    if AL.playerClass ~= "SHAMAN" or not ActionLiteDB then return end
    local player = WeaponStatePlayer()
    if not player or not trackedWeaponIdentity or not trackedWeaponUntil then return end
    local saved = ActionLiteDB.shamanWeaponEnchants
    if not SafeValue(saved) or type(saved) ~= "table" then saved = {}; ActionLiteDB.shamanWeaponEnchants = saved end
    saved[player] = { name=trackedWeapon, weapon=trackedWeaponIdentity,
        expires=time()+math.max(0,trackedWeaponUntil-GetTime()) }
end

local function RestoreTrackedWeapon()
    if AL.playerClass ~= "SHAMAN" then return end
    local player, identity = WeaponStatePlayer(), MainHandIdentity()
    local saved = ActionLiteDB and ActionLiteDB.shamanWeaponEnchants
    local record = player and SafeValue(saved) and type(saved) == "table" and saved[player]
    if not SafeValue(record) or type(record) ~= "table" or not identity then return end
    local expires = Number(record.expires)
    local name = SafeValue(record.name) and type(record.name) == "string" and record.name or nil
    if not name or not WEAPON_ENCHANTS[name] or not expires or expires <= time()
        or not SafeValue(record.weapon) or record.weapon ~= identity then ClearTrackedWeapon(true); return end
    trackedWeapon, trackedWeaponUntil, trackedWeaponIdentity = name,
        GetTime()+math.min(expires-time(),WEAPON_ENCHANT_FALLBACK_DURATION), identity
    trackedWeaponCastAt, trackedWeaponEnchantID, trackedWeaponObservation = nil, nil, {}
end

local function TrackedWeaponActive(preferred)
    if trackedWeapon ~= preferred or not trackedWeaponUntil or GetTime() >= trackedWeaponUntil then return false end
    local identity = MainHandIdentity()
    if identity and trackedWeaponIdentity and identity ~= trackedWeaponIdentity then return false end
    return true
end

local function WeaponBuffName()
    local api = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local readable = type(api) == "function"
    local complete = false
    if readable then
        for index = 1, 40 do
            local ok, aura = pcall(api, "player", index, "HELPFUL")
            if not ok or not SafeValue(aura) then readable = false; break end
            if aura == nil then complete = true; break end
            if type(aura) ~= "table" then readable = false; break end
            local name = SafeValue(aura.name) and type(aura.name) == "string" and aura.name or nil
            name = name and ((AL.englishNames and AL.englishNames[name]) or name)
            if not name then
                local id = Number(aura.spellId)
                name = id and SafeCall(AL.SpellName, id)
                name = SafeValue(name) and type(name) == "string" and name or nil
                name = name and ((AL.englishNames and AL.englishNames[name]) or name)
            end
            if not name then readable = false; break end
            local expiration = Number(aura.expirationTime)
            if name and WEAPON_ENCHANTS[name] and (not expiration or expiration == 0 or expiration > GetTime()) then return name, true end
        end
    end
    -- A missing player aura does not prove a weapon enchant is missing.
    -- Use the core's tooltip/cast fallback only when native aura reads fail.
    if not readable then
        for name in pairs(WEAPON_ENCHANTS) do
            if Bool((SafeCall(AL.HasBuff, "player", name))) == true then return name end
        end
    end
    return nil, readable and complete
end

local function MainHandEnchantState(preferred)
    if type(GetInventoryItemID) == "function" then
        local id = Number((SafeCall(GetInventoryItemID, "player", 16)))
        if not id or id <= 0 then return nil end
    end
    local tracked = trackedWeapon and TrackedWeaponActive(trackedWeapon)
    if trackedWeapon and not tracked then ClearTrackedWeapon(true) end
    local recent = tracked and trackedWeaponCastAt and GetTime() - trackedWeaponCastAt < 2
    if recent then return trackedWeapon == preferred end
    local buff, buffsReadable = WeaponBuffName()
    if buff then
        if tracked and buff == trackedWeapon and buffsReadable then trackedWeaponObservation.buff = true end
        if tracked and buff ~= trackedWeapon then ClearTrackedWeapon(true) end
        return buff == preferred
    end
    if tracked and buffsReadable and trackedWeaponObservation.buff then
        ClearTrackedWeapon(true)
        return false -- a previously observed native weapon buff was removed
    end
    local have, expiration, _, id = SafeCall(GetWeaponEnchantInfo)
    have, expiration, id = Bool(have), Number(expiration), Number(id)
    if have == false then
        -- Forever can report no temporary enchant throughout a successful
        -- Rockbiter buff. Absence only disproves a cast after this session
        -- actually observed the enchant on the same weapon.
        if tracked and not trackedWeaponObservation.enchant then return trackedWeapon == preferred end
        ClearTrackedWeapon(true)
        return false
    elseif have == true then
        if tracked then
            -- Learn the post-cast client ID; historical IDs can differ on
            -- Forever. A later ID change means the enchant was replaced.
            if id and id > 0 and trackedWeaponEnchantID and id ~= trackedWeaponEnchantID then
                ClearTrackedWeapon(true)
            else
                trackedWeaponObservation.enchant = true
                if id and id > 0 then trackedWeaponEnchantID = id end
                -- A constant zero/small countdown immediately after success
                -- is not a verified expiration. Trust the refresh window
                -- only after a healthy countdown has been observed.
                if expiration and expiration > 2000 then trackedWeaponObservation.countdown = true end
                if expiration and expiration <= 600 and trackedWeaponObservation.countdown then
                    ClearTrackedWeapon(true); return false
                end
                return trackedWeapon == preferred
            end
        end
        if expiration and expiration > 0 and expiration <= 600 then return false end
        if id and id > 0 then
            for name, ids in pairs(WEAPON_ENCHANT_IDS) do
                if ids[id] then return name == preferred end
            end
        end
        return nil -- unknown IDs are not evidence of a wrong enchant
    end
    if tracked then return trackedWeapon == preferred end
end

local function PreferredWeapon(s, role)
    local mode = SettingChoice(s, "weaponMode", { AUTO=true, WINDFURY=true, ROCKBITER=true, FLAMETONGUE=true }, "AUTO")
    local name = ({ WINDFURY="Windfury Weapon", ROCKBITER="Rockbiter Weapon", FLAMETONGUE="Flametongue Weapon" })[mode]
    if name and Ok(name) then return name end
    local order = role == "ELEMENTAL" and { "Flametongue Weapon", "Rockbiter Weapon", "Windfury Weapon" }
        or { "Windfury Weapon", "Rockbiter Weapon", "Flametongue Weapon" }
    for _, spell in ipairs(order) do if Ok(spell) then return spell end end
end

local function TotemSnapshot()
    local active, readable, occupied, empty = {}, {}, {}, 0
    local slotElements = {}
    for element, slot in pairs({ FIRE=FIRE_TOTEM_SLOT, EARTH=EARTH_TOTEM_SLOT, WATER=WATER_TOTEM_SLOT }) do
        slot = Number(slot)
        if slot and slot >= 1 and slot <= 4 then slotElements[slot] = element end
    end
    for slot = 1, 4 do
        local have, name, start, duration = SafeCall(GetTotemInfo, slot)
        have = Bool(have)
        if SafeValue(name) and type(name) == "string" then name = (AL.englishNames and AL.englishNames[name]) or name
        else name = nil end
        local element = name and TOTEM_ELEMENT[name] or slotElements[slot]
        if have == false then
            empty = empty + 1
            if element then readable[element] = true end
        elseif have == true and element then
            readable[element], occupied[element] = true, true
            if name and TOTEM_ELEMENT[name] then active[name] = true
            else active["?" .. element] = true end
            start, duration = Number(start), Number(duration)
            if name and TOTEM_ELEMENT[name] and start and duration and duration > 0 then
                trackedTotems[element] = { name=name, at=trackedTotems[element] and trackedTotems[element].at or -math.huge,
                    expires=start + duration }
            elseif name and TOTEM_ELEMENT[name] and (not trackedTotems[element] or trackedTotems[element].name ~= name) then
                trackedTotems[element] = { name=name, at=-math.huge, expires=GetTime()+(TOTEM_FALLBACK[name] or 10) }
            end
        end
    end
    for element, record in pairs(trackedTotems) do
        local recent = GetTime() - record.at < 0.5
        if record.expires <= GetTime() or (not recent and (empty == 4 or (readable[element] and not occupied[element]))) then
            trackedTotems[element] = nil
        elseif not occupied[element] and (recent or not readable[element]) then active[record.name] = true end
    end
    return active
end

local function ActiveTotemFrom(element, snapshot)
    for _, name in ipairs(TOTEM_GROUPS[element]) do if snapshot[name] then return name end end
    if snapshot["?" .. element] then return "?" end
end

local function PreferredEarthTotem(s, role)
    local mode = SettingChoice(s, "earthTotemMode", { AUTO=true, STRENGTH=true, STONESKIN=true, OFF=true }, "AUTO")
    if mode == "OFF" then return end
    local desired = ({ STRENGTH="Strength of Earth Totem", STONESKIN="Stoneskin Totem" })[mode]
    if desired and Ok(desired) then return desired end
    local names = role == "ENHANCEMENT" and { "Strength of Earth Totem", "Stoneskin Totem" }
        or { "Stoneskin Totem", "Strength of Earth Totem" }
    for _, name in ipairs(names) do if Ok(name) then return name end end
end

local function PreferredWaterTotem(s, role)
    local mode = SettingChoice(s, "waterTotemMode", { AUTO=true, HEALING=true, MANA=true, OFF=true }, "AUTO")
    if mode == "OFF" then return end
    local desired = ({ HEALING="Healing Stream Totem", MANA="Mana Spring Totem" })[mode]
    if desired and Ok(desired) then return desired end
    local names = role == "ELEMENTAL" and { "Mana Spring Totem", "Healing Stream Totem" }
        or { "Healing Stream Totem", "Mana Spring Totem" }
    for _, name in ipairs(names) do if Ok(name) then return name end end
end

local function InMelee()
    if Ok("Stormstrike") then
        local range = Bool((SafeCall(AL.InRange, "Stormstrike")))
        if range ~= nil then return range end
    end
    if Bool((SafeCall(AL.InRange, "Attack"))) == true then return true end
    return Bool((SafeCall(AL.TargetInMelee))) == true
end

local function MeleeAttack(reason)
    if Bool(AL.known and AL.known.Attack) == true and Bool((SafeCall(AL.Allowed, "Attack"))) ~= false and InMelee() then
        AddAction("Attack", reason)
    else AddAction(nil, PlayerMoving() and "Stop moving" or reason) end
end

local function Offer(name, reason, gates, preparation, showRange)
    if not Ok(name) or not CooldownReady(name) then return false end
    local usable, shortage = SpellUsability(name)
    if usable == false or shortage == true then return false end
    if not showRange and Bool((SafeCall(AL.InRange, name))) == false then return false end
    local conditions = {}
    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
    local affordable = Affordable(name, usable, shortage)
    if preparation and ManaAmount() == nil and usable == true and shortage == false then affordable = true end
    conditions[#conditions + 1] = affordable
    return AddAction(name, reason, conditions)
end

local function Heal(s, hp, mana, inCombat, moving)
    if not Enabled(s, "heal") or moving then return end
    local key = inCombat and "healHP" or "healOutOfCombatHP"
    local gates = { HealthGate("player", hp, SettingNumber(s,key,M.defaults[key],5,95), true),
        ManaGate(mana, SettingNumber(s,"healMinMana",10,0,100), false) }
    if inCombat then Offer("Lesser Healing Wave", "Emergency heal", gates) end
    Offer("Healing Wave", inCombat and "Emergency heal" or "Heal up", gates)
end

local function Maintenance(s, role, inCombat, moving)
    if Enabled(s, "shield") and not AL.HasBuff("player", "Lightning Shield") then Offer("Lightning Shield", "Shield", nil, true) end
    if not inCombat and not moving and Enabled(s, "weapon") then
        local preferred = PreferredWeapon(s, role)
        if preferred and MainHandEnchantState(preferred) == false then Offer(preferred, "Weapon enchant", nil, true) end
    end
end

local function MaintainCombatTotems(s, role, targetHP, snapshot)
    if not Enabled(s, "totems") then return end
    local gates = { HealthGate("target", targetHP, SettingNumber(s,"totemMinTargetHP",45,0,100), false) }
    local earth, water = PreferredEarthTotem(s,role), PreferredWaterTotem(s,role)
    local activeEarth, activeWater = ActiveTotemFrom("EARTH",snapshot), ActiveTotemFrom("WATER",snapshot)
    if earth and not snapshot[earth] and (not activeEarth or activeEarth == "Strength of Earth Totem" or activeEarth == "Stoneskin Totem") then
        Offer(earth, "Earth totem", gates)
    end
    if water and not snapshot[water] and (not activeWater or activeWater == "Healing Stream Totem" or activeWater == "Mana Spring Totem") then
        Offer(water, "Water totem", gates)
    end
    if Enabled(s,"searing") and not ActiveTotemFrom("FIRE",snapshot) then Offer("Searing Totem", "Fire totem", gates) end
end

local function AoETotem(s, mana, count, snapshot, targetHP)
    if not Enabled(s,"aoe") or not count or count < SettingNumber(s,"aoeMinEnemies",2,2,5) then return end
    local gates = { ManaGate(mana, SettingNumber(s,"aoeMinMana",30,0,100), false),
        HealthGate("target", targetHP, SettingNumber(s,"totemMinTargetHP",45,0,100), false) }
    if Enabled(s,"firenova") and not snapshot["Fire Nova Totem"] and not snapshot["?FIRE"] then Offer("Fire Nova Totem", "AoE", gates) end
    if Enabled(s,"magma") and not snapshot["Magma Totem"] and not snapshot["Fire Nova Totem"] and not snapshot["?FIRE"] then
        Offer("Magma Totem", "AoE", gates)
    end
end

local function Burst(s, role, targetHP)
    if not AL.burst then return end
    if role == "ENHANCEMENT" and not InMelee() then return end
    if role == "ELEMENTAL" and Bool((SafeCall(AL.InRange,"Lightning Bolt"))) ~= true then return end
    local gates = { HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false) }
    if role == "ENHANCEMENT" then Offer("Blood Fury", "Burst", gates) end
    Offer("Berserking", "Burst", gates)
end

local function LightningBolt(s, mana, moving, reason)
    if Enabled(s,"lightningbolt") and not moving then
        Offer("Lightning Bolt", reason, { ManaGate(mana,SettingNumber(s,"lightningBoltMinMana",15,0,100),false) },false,true)
    end
end

local function Damage(s, role, mana, targetHP, moving)
    local shock = ManaGate(mana,SettingNumber(s,"shockMinMana",25,0,100),false)
    if Enabled(s,"flameshock") and not AL.HasDebuff("target","Flame Shock") then
        Offer("Flame Shock","Damage over time",{ shock,
            HealthGate("target",targetHP,SettingNumber(s,"flameShockMinTargetHP",35,0,100),false) })
    end
    if role == "ENHANCEMENT" and Enabled(s,"stormstrike") and InMelee() then Offer("Stormstrike","Melee priority") end
    if Enabled(s,"frostshock") then Offer("Frost Shock","Low-health slow",{shock,
        HealthGate("target",targetHP,SettingNumber(s,"frostShockTargetHP",25,0,100),true) }) end
    if Enabled(s,"earthshock") then Offer("Earth Shock","Nature damage",{shock}) end
    LightningBolt(s,mana,moving,role == "ELEMENTAL" and "Elemental filler" or "Leveling filler")
    MeleeAttack("Conserve mana")
end

function M.NextSpell(s, inCombat, hostile)
    lastRotation = { at=GetTime(), actions={} }
    local role, moving, mana = Role(s), PlayerMoving(), GateManaPercent()
    local hp, targetHP = HealthPercent("player"), hostile and HealthPercent("target") or nil
    if PlayerIsCastingOrChanneling() then AddAction(nil,"Casting")
    else
        if inCombat and hostile and Enabled(s,"interrupt") and Bool((SafeCall(AL.TargetCasting))) == true then
            Offer("Earth Shock","Interrupt")
        end
        Heal(s,hp,mana,inCombat,moving)
        if inCombat and hostile and Enabled(s,"stoneclaw") then
            local snapshot = TotemSnapshot()
            if not snapshot["Stoneclaw Totem"] and not snapshot["?EARTH"] then
                Offer("Stoneclaw Totem","Defensive totem",{ HealthGate("player",hp,SettingNumber(s,"stoneclawHP",25,5,80),true) })
            end
        end
        Maintenance(s,role,inCombat,moving)
        if hostile then
            local melee = InMelee()
            if not inCombat then
                if not melee then LightningBolt(s,mana,moving,"Ranged pull")
                else MaintainCombatTotems(s,role,targetHP,TotemSnapshot());MeleeAttack("Opener") end
            elseif role == "ENHANCEMENT" and not melee then
                LightningBolt(s,mana,moving,"Ranged combat");Damage(s,role,mana,targetHP,moving)
            else
                Burst(s,role,targetHP)
                local snapshot = TotemSnapshot()
                local count = Enabled(s,"aoe") and EnemyCount(SettingNumber(s,"aoeMinEnemies",2,2,5)) or nil
                AoETotem(s,mana,count,snapshot,targetHP)
                MaintainCombatTotems(s,role,targetHP,snapshot)
                Damage(s,role,mana,targetHP,moving)
            end
        end
    end
    AddAction(nil, inCombat and not hostile and "No target" or "Ready")
    local base = lastRotation.actions[#lastRotation.actions]
    lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
    return base.spell, base.reason
end

function M.CanTrackSuggestedSpell(name)
    if not lastRotation or GetTime()-lastRotation.at > 0.5 or lastRotation.visualCandidate then return false end
    local visual = AL.rotationSecretVisual
    if visual and GetTime()-visual.at <= 0.5 then return false end
    return name == lastRotation.baseSpell and Ok(name)
end

function M.OnTargetChanged() lastRotation, AL.rotationSecretVisual = nil, nil end

function M.OnCastResult(name, result)
    if result ~= "UNIT_SPELLCAST_SUCCEEDED" or not name then return end
    local now = GetTime()
    if SHOCKS[name] then
        local _, ending = ReadableCooldown(name)
        shockLockUntil, shockCastAt = ending and ending > now+1.5 and ending or now+6, now
    elseif name == "Fire Nova Totem" then
        local _, ending = ReadableCooldown(name)
        localCooldowns[name] = { at=now, ends=ending and ending > now+1.5 and ending or now+15 }
    end
    if WEAPON_ENCHANTS[name] then
        trackedWeapon, trackedWeaponUntil, trackedWeaponCastAt, trackedWeaponIdentity = name,
            now+WEAPON_ENCHANT_FALLBACK_DURATION, now, MainHandIdentity()
        trackedWeaponEnchantID = nil
        trackedWeaponObservation = {}
        SaveTrackedWeapon()
    end
    local element = TOTEM_ELEMENT[name]
    if element then trackedTotems[element] = { name=name, at=now, expires=now+(TOTEM_FALLBACK[name] or 10) } end
end

function M.GetUIState()
    local s = AL.S()
    local role, snapshot = Role(s), TotemSnapshot()
    local known = 0
    for _, entry in ipairs(M.spells) do if Bool(AL.known and AL.known[entry[2]]) == true then known=known+1 end end
    local preferred, weapon = PreferredWeapon(s,role)
    if preferred and MainHandEnchantState(preferred) == true then weapon=preferred end
    if not weapon and Bool((SafeCall(GetWeaponEnchantInfo))) == true then weapon="Enchanted" end
    return { role=role, level=Number((SafeCall(UnitLevel,"player"))), health=HealthPercent("player"), mana=GateManaPercent(),
        knownCount=known, lightningShield=Bool((SafeCall(AL.HasBuff,"player","Lightning Shield"))) == true,
        weaponEnchant=weapon, earthTotem=ActiveTotemFrom("EARTH",snapshot), waterTotem=ActiveTotemFrom("WATER",snapshot),
        fireTotem=ActiveTotemFrom("FIRE",snapshot), enemyCount=EnemyCount(SettingNumber(s,"aoeMinEnemies",2,2,5)),
        shockLocked=GetTime()<shockLockUntil }
end

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
    return { cost = name and SpellManaCost(name), at=GetTime() }
end

function M.OnManaCastSucceeded(name, id, guid, sent)
    castSucceededCount = castSucceededCount + 1
    lastSucceededCastName, lastSentCastName, lastSentCastAt = name, nil, 0
    if not name then return end
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


local tracker = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_DEAD", "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(tracker.RegisterEvent, tracker, event)
end
tracker:SetScript("OnEvent", function(_, event, unit, token)
    if event == "PLAYER_STARTED_MOVING" then movementEventActive = true
    elseif event == "PLAYER_STOPPED_MOVING" then movementEventActive = false
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
        trackedMana, trackedManaMax, trackedManaUpdatedAt, trackedLastSpendAt = nil, nil, nil, nil
        trackedCostsKnown, trackedSource = true, "uninitialized"
        trackedLastSpell, trackedLastCost, eventManaPct, eventManaAt = nil, 0, nil, nil
        ClearTrackedWeapon(event == "PLAYER_DEAD")
        if event == "PLAYER_ENTERING_WORLD" then RestoreTrackedWeapon() end
        trackedTotems, localCooldowns, curveFailures = {}, {}, {}
        movementEventActive, curveCapabilities, visibilityCurves = nil, {}, {}
        shockLockUntil, shockCastAt, lastRotation, AL.rotationSecretVisual = 0, nil, nil, nil
    elseif event == "PLAYER_LOGIN" then RestoreTrackedWeapon()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if Number(unit) == 16 then
            local identity = MainHandIdentity()
            if not identity or not trackedWeaponIdentity or identity ~= trackedWeaponIdentity then ClearTrackedWeapon(true) end
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then M.RefreshManaCache()
    elseif SafeValue(unit) and unit == "player" and (not SafeValue(token) or token == nil or token == "MANA") then RefreshManaSensor() end
end)
function M.ManaPercent() return GateManaPercent(), lastManaSource end
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
	if low > 0 and low <= 1 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
	if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
	if low ~= 1 and high ~= 1 then curve:AddPoint(1, CreateColor(1, 1, 1, low <= 1 and high > 1 and 1 or 0)) end
	visibilityCurves[key] = curve
	return curve
end

ReadVisualAlpha = function(mask)
    local curve = IntervalCurve(mask.low, mask.high)
    local color
    if mask.kind == "power" then color = UnitPowerPercent(mask.unit, mask.powerType, false, curve)
    else color = UnitHealthPercent(mask.unit, false, curve) end
    local _, _, _, alpha = color:GetRGBA()
    if SafeValue(alpha) and Number(alpha) == nil then error("Shaman resource curve returned no display alpha") end
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
                curveFailures[mask.kind .. ":" .. mask.unit .. ":" .. tostring(mask.powerType or "")] = {
                    reader = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent,
                    factory = C_CurveUtil and C_CurveUtil.CreateColorCurve }
                error("Shaman resource alpha unavailable")
            end
        else node:SetAlpha(1) end
	end
end





AL.RegisterRotation("SHAMAN", M)
-- END ORIGINAL LEVELING IMPLEMENTATION
    end)(ADDON, RotationScope(true))

    ;(function(...)
-- BEGIN OPTIONAL TALENT BUILD IMPLEMENTATION
local ADDON, AL = ...

-- WoW Forever Shaman Elemental 31/7/13 / Enhancement 18/33/0 - v0.17.4
-- Elemental reference: MythicSim 0025d73986ee, client 1.60.1.70338.
-- Reference Enhancement : Forever 1.60.1.70338, MythicSim 944a791060db.
-- Status: client validation required for costs, ranks and talents.
-- Protected values stay unknown and are never treated as zero.

local A = _G.Action

local M = {
	defaults = {
        leveling = true,
		shamanRole = "ENHANCEMENT",
		elemental = false, elementalMastery = true,
		elementalLavaBurst = true, elementalLavaBurstMana = 15,
		elementalChainLightning = true, elementalChainMana = 30, elementalChainClearcasting = true,
		elementalWaterShield = true, elementalRacials = true,
		enhancement = false,
		enhancementMaelstrom = true,
		enhancementRage = true,
		enhancementRacials = true,
		enhancementChainLightning = false,
		enhancementAirTotem = "AUTO",
		shield = true,
		weapon = true,
		weaponMode = "AUTO",
		totems = true,
		earthTotemMode = "AUTO",
		waterTotemMode = "AUTO",
		searing = true,
		interrupt = true,
		flameshock = true,
		earthshock = true,
		frostshock = true,
		stormstrike = true,
		lightningbolt = true,
		heal = true,
		stoneclaw = true,
		drink = true,
		aoe = false,
		firenova = true,
		magma = true,
		healHP = 35,
		healOutOfCombatHP = 70,
		healMinMana = 10,
		stoneclawHP = 25,
		drinkMana = 30,
		shockMinMana = 25,
		lightningBoltMinMana = 15,
		flameShockMinTargetHP = 35,
		frostShockTargetHP = 25,
		totemMinTargetHP = 45,
		aoeMinEnemies = 2,
		aoeMinMana = 30,
		burstMinTargetHP = 40,
	},
}

-- Rank-one IDs used for scans and icons. Their presence does not prove
-- Forever's learning level; the safeguards below remain
-- LIKELY until checked in the target build.
-- Exactly one rotation stays selected. Leveling is the default and the
-- fallback when a selected specialization is switched off or saved flags
-- conflict. A valid saved specialization takes priority during migration.
M.buildKeys = { "leveling", "elemental", "enhancement" }
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
    s = s or AL.Profile("SHAMAN")
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
	{ 20572, "Blood Fury" },
	{ 421, "Chain Lightning" },
	{ 2008, "Ancestral Spirit" },
	{ 556, "Astral Recall" },
	{ 526, "Cure Poison" },
	{ 8042, "Earth Shock" },
	{ 2484, "Earthbind Totem" },
	{ 6196, "Far Sight" },
	{ 1535, "Fire Nova Totem" },
	{ 408341, "Fire Nova" },
	{ 8184, "Fire Resistance Totem" },
	{ 8050, "Flame Shock" },
	{ 8227, "Flametongue Totem" },
	{ 8024, "Flametongue Weapon" },
	{ 8181, "Frost Resistance Totem" },
	{ 8056, "Frost Shock" },
	{ 2645, "Ghost Wolf" },
	{ 8835, "Grace of Air Totem" },
	{ 8177, "Grounding Totem" },
	{ 5394, "Healing Stream Totem" },
	{ 331, "Healing Wave" },
	{ 8004, "Lesser Healing Wave" },
	{ 408490, "Lava Burst" },
	{ 0, "Elemental Mastery" },
	{ 403, "Lightning Bolt" },
	{ 324, "Lightning Shield" },
	{ 8190, "Magma Totem" },
	{ 5675, "Mana Spring Totem" },
	{ 8166, "Poison Cleansing Totem" },
	{ 370, "Purge" },
	{ 425336, "Rage of the Farseer" },
	{ 8017, "Rockbiter Weapon" },
	{ 3599, "Searing Totem" },
	{ 5730, "Stoneclaw Totem" },
	{ 8071, "Stoneskin Totem" },
	{ 17364, "Stormstrike" },
	{ 8075, "Strength of Earth Totem" },
	{ 8143, "Tremor Totem" },
	{ 131, "Water Breathing" },
	{ 546, "Water Walking" },
	{ 408510, "Water Shield" },
	{ 8232, "Windfury Weapon" },
	{ 8512, "Windfury Totem" },
}

-- Historical levels retained only as references. They no longer drive
-- the rotation: Forever can change them. Spellbook scans and Core's
-- FUTURESPELL rejection determine which spells are actually available.
local REFERENCE_LEVELS = {
	["Lightning Bolt"] = 1,
	["Healing Wave"] = 1,
	["Rockbiter Weapon"] = 1,
	["Earth Shock"] = 4,
	["Stoneskin Totem"] = 4,
	["Earthbind Totem"] = 6,
	["Lightning Shield"] = 8,
	["Stoneclaw Totem"] = 8,
	["Flame Shock"] = 10,
	["Flametongue Weapon"] = 10,
	["Searing Totem"] = 10,
	["Strength of Earth Totem"] = 10,
	["Ancestral Spirit"] = 12,
	["Fire Nova Totem"] = 12,
	["Purge"] = 12,
	["Cure Poison"] = 16,
	["Tremor Totem"] = 18,
	["Frost Shock"] = 20,
	["Ghost Wolf"] = 20,
	["Healing Stream Totem"] = 20,
	["Lesser Healing Wave"] = 20,
	["Poison Cleansing Totem"] = 22,
	["Water Breathing"] = 22,
	["Fire Resistance Totem"] = 24,
	["Frost Resistance Totem"] = 24,
	["Far Sight"] = 26,
	["Magma Totem"] = 26,
	["Mana Spring Totem"] = 26,
	["Flametongue Totem"] = 28,
	["Water Walking"] = 28,
	["Astral Recall"] = 30,
	["Grounding Totem"] = 30,
	["Windfury Weapon"] = 30,
}
M.minLevels = REFERENCE_LEVELS

local function Ok(name)
	if type(AL.Ok) == "function" then return AL.Ok(name) and true or false end
	return AL.known and AL.known[name] and true or false
end

local SHOCKS = {
	["Earth Shock"] = true,
	["Flame Shock"] = true,
	["Frost Shock"] = true,
}
local WEAPON_ENCHANTS = {
	["Windfury Weapon"] = true,
	["Rockbiter Weapon"] = true,
	["Flametongue Weapon"] = true,
}
-- Temporary weapon-enchant IDs taken from the reference TBC Shaman profile.
-- Reference only: Forever IDs can differ. An unknown ID
-- does not prove the enchant is wrong; a confirmed cast takes priority.
local WEAPON_ENCHANT_IDS = {
	["Windfury Weapon"] = {
		[283] = true, [284] = true, [525] = true, [1669] = true,
		[2636] = true, [3785] = true,
	},
	["Flametongue Weapon"] = {
		[3] = true, [4] = true, [5] = true, [1665] = true,
		[1666] = true, [2634] = true, [3780] = true, [3781] = true,
	},
	["Rockbiter Weapon"] = {
		[1] = true, [6] = true, [29] = true, [503] = true, [504] = true,
		[683] = true, [1663] = true, [1664] = true, [2632] = true,
		[2633] = true,
	},
}
local TOTEM_GROUPS = {
	FIRE = { "Searing Totem", "Magma Totem", "Fire Nova Totem", "Fire Resistance Totem" },
	EARTH = { "Strength of Earth Totem", "Stoneskin Totem", "Stoneclaw Totem", "Earthbind Totem", "Tremor Totem" },
	WATER = { "Healing Stream Totem", "Mana Spring Totem", "Poison Cleansing Totem", "Frost Resistance Totem" },
	AIR = { "Windfury Totem", "Grace of Air Totem", "Windwall Totem", "Nature Resistance Totem", "Tranquil Air Totem" },
}
local TOTEM_ELEMENT = {}
for element, names in pairs(TOTEM_GROUPS) do
	for _, name in ipairs(names) do TOTEM_ELEMENT[name] = element end
end

-- LIKELY fallback durations: GetTotemInfo always takes priority. These
-- deliberately conservative values prevent repeated suggestions when
-- Forever temporarily protects totem state.
local TOTEM_FALLBACK = {
	["Searing Totem"] = 30,
	["Magma Totem"] = 20,
	["Fire Nova Totem"] = 5,
	["Fire Resistance Totem"] = 120,
	["Strength of Earth Totem"] = 120,
	["Stoneskin Totem"] = 120,
	["Stoneclaw Totem"] = 15,
	["Earthbind Totem"] = 45,
	["Tremor Totem"] = 120,
	["Healing Stream Totem"] = 60,
	["Mana Spring Totem"] = 60,
	["Poison Cleansing Totem"] = 120,
	["Frost Resistance Totem"] = 120,
	["Windfury Totem"] = 300,
	["Grace of Air Totem"] = 300,
}

local trackedTotems, localCooldowns = {}, {}
local trackedWeapon, trackedWeaponUntil, trackedWeaponCastAt, trackedWeaponIdentity, trackedWeaponEnchantID
local trackedWeaponObservation = {}
local shockLockUntil, shockCastAt = 0, nil

-- Full rotation restored after the incorrect Lightning Bolt binding was confirmed.
-- Lightning Bolt stays direct; Attack is only a melee-range fallback.

-- Rockbiter: 60 minutes reported by the player (exact build to be confirmed).
-- The same LIKELY fallback duration for Flametongue and Windfury needs in-game validation.
-- An absence that was never observed cannot cancel a confirmed cast.
local WEAPON_ENCHANT_FALLBACK_DURATION = 60 * 60


AL.selfCastSpells = AL.selfCastSpells or {}
for _, name in ipairs({ "Lightning Shield", "Water Shield", "Healing Wave", "Lesser Healing Wave", "Rockbiter Weapon",
    "Flametongue Weapon", "Windfury Weapon", "Blood Fury", "Berserking", "Rage of the Farseer", "Fire Nova", "Elemental Mastery" }) do AL.selfCastSpells[name] = true end
for name in pairs(TOTEM_ELEMENT) do AL.selfCastSpells[name] = true end
-- Shared native gates keep opaque percentages in native display alpha only.
local lastRotation
local visibilityCurves, curveFailures, curveCapabilities = {}, {}, {}
local IntervalCurve, ReadVisualAlpha
local curveProbe
local visibilityCurveFactory
local movementEventActive
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
    local ok, a, b, c, d, e = pcall(reader, ...)
    if ok then return a, b, c, d, e end
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
    local current, maximum = Number((SafeCall(UnitHealth, unit))), Number((SafeCall(UnitHealthMax, unit)))
    local hp = current and maximum and maximum > 0 and Percent(current / maximum * 100) or nil
    if hp ~= nil then return hp end
    hp = Percent((SafeCall(AL.HealthPercent, unit)))
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
    local player = A and A.Player
    if SafeValue(player) and type(player) == "table" then
        pct = Percent((SafeCall(player.ManaPercentage, player)))
        if pct ~= nil then return pct, "Action.Player.ManaPercentage" end
    end
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
    return SafeValue(name) and type(name) == "string"
end

local function UnitWithin(unit, radius)
    local distance, checked = SafeCall(UnitDistanceSquared, unit)
    distance = Number(distance)
    if distance and distance >= 0 and Bool(checked) ~= false then return distance <= radius * radius end
    local object = A and SafeCall(A.Unit, unit)
    if SafeValue(object) and (type(object) == "table" or type(object) == "userdata") then
        local lower,upper=SafeCall(object.GetRange, object)
        if not SafeValue(upper) then return nil end
        local range
        if upper~=nil then range=Number(upper) else range=Number(lower) end
        if range and range >= 0 then return range <= radius end
    end
    if radius >= 10 then return Bool((SafeCall(CheckInteractDistance, unit, 3))) end
end

local function EnemyCount(limit, radius)
    radius = Number(radius) or 8
    local count
    local function Accept(value)
        value = Number(value)
        if value and value >= 0 and value <= 40 and value == math.floor(value) then count = math.max(count or 0, value) end
    end
    Accept((SafeCall(AL.EnemyCount, radius)))
    if A and A.MultiUnits then
        Accept((SafeCall(A.MultiUnits.GetByRangeInCombat, A.MultiUnits, radius, limit or 5)))
        Accept((SafeCall(A.MultiUnits.GetActiveEnemies, A.MultiUnits, radius)))
    end
    local seen, visible = {}, 0
    local function Count(unit)
        if not SafeValue(unit) or type(unit) ~= "string" then return end
        if Bool((SafeCall(UnitExists, unit))) ~= true or Bool((SafeCall(UnitCanAttack, "player", unit))) ~= true
            or Bool((SafeCall(UnitIsDeadOrGhost, unit))) ~= false or Bool((SafeCall(UnitAffectingCombat, unit))) ~= true then return end
        local guid = SafeCall(UnitGUID, unit)
        if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] or UnitWithin(unit, radius) ~= true then return end
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

local function Role(s)
    if Enabled(s, "elemental") then return "ELEMENTAL" end
    if Enabled(s, "enhancement") then return "ENHANCEMENT" end
    if AL.DPS60 and AL.DPS60.Active() then
        local build = AL.DPS60.Build("SHAMAN", s, s.shamanRole == "ELEMENTAL" and "ELEMENTAL" or "ENHANCEMENT")
        if build == "ELEMENTAL" then return "ELEMENTAL" end
        if build == "ENHANCEMENT" or build == "ELEHANCE" then return "ENHANCEMENT" end
    end
    return SettingChoice(s, "shamanRole", { ENHANCEMENT=true, ELEMENTAL=true }, "ENHANCEMENT")
end

local function Standalone(s) return Enabled(s,"elemental") or Enabled(s,"enhancement") end

-- Standalone 18/33/0 state. Only confirmed player casts create timers;
-- proc stacks and resets require readable client evidence.
local enh = { cooldowns={}, flames={}, talents={}, talentWarm=false, boltAt=-math.huge, completed={} }
local ENH_COOLDOWNS = { ["Elemental Mastery"]=180, ["Stormstrike"]=8, ["Fire Nova"]=10, ["Chain Lightning"]=6,
    ["Lava Burst"]=10, ["Water Shield"]=15,
    ["Rage of the Farseer"]=180, ["Blood Fury"]=120, ["Berserking"]=180 }

local function EnhancementTalent(name)
    if not enh.talentWarm then
        enh.talentWarm=true
        local localized={ ["Maelstrom Weapon"]=SafeCall(C_Spell and C_Spell.GetSpellName,408498),
            ["Improved Fire Nova"]=SafeCall(C_Spell and C_Spell.GetSpellName,16086),
            ["Call of Flame"]=SafeCall(C_Spell and C_Spell.GetSpellName,16038),
            ["Reverberation"]=SafeCall(C_Spell and C_Spell.GetSpellName,16040) }
        for tab=1,3 do for index=1,40 do
            local talent,_,_,_,rank=SafeCall(GetTalentInfo,tab,index,false,false)
            rank=Number(rank)
            if SafeValue(talent) and type(talent)=="string" and rank and rank>=0 then
                local canonical=(AL.englishNames and AL.englishNames[talent]) or talent
                for english,native in pairs(localized) do
                    if SafeValue(native) and type(native)=="string" and talent==native then canonical=english;break end
                end
                if canonical=="Trial By Fire" then canonical="Improved Fire Nova" end
                enh.talents[canonical]=rank
            end
        end end
    end
    return enh.talents[name]
end

function M.FlameShockDuration()
    local rank=EnhancementTalent("Call of Flame") or 0
    return 12+3*math.max(0,math.min(3,rank))
end

local function ElementalMasteryActive()
    local now=GetTime()
    if enh.masteryAt and now-enh.masteryAt<0.5 then return (enh.masteryUntil or 0)>now end
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if type(reader)=="function" then
        local native=SafeCall(C_Spell and C_Spell.GetSpellName,LearnedID("Elemental Mastery") or "Elemental Mastery")
        for i=1,40 do
            local ok,aura=pcall(reader,"player",i,"HELPFUL")
            if not ok or not SafeValue(aura) then break end
            if aura==nil then enh.masteryUntil=0;return false end
            if type(aura)~="table" then break end
            local name=SafeValue(aura.name) and type(aura.name)=="string" and aura.name or nil
            if name=="Elemental Mastery" or name and SafeValue(native) and name==native then
                local ending=Number(aura.expirationTime)
                return not ending or ending==0 or ending>now
            end
        end
    end
    return (enh.masteryUntil or 0)>now
end

local function EnhancementReady(name)
    local record=enh.cooldowns[name]
    if SHOCKS[name] then record=enh.cooldowns.shock end
    if record and GetTime()-record.at<0.5 then return false end
    if name=="Chain Lightning" and Enabled(AL.S(),"elemental") and ElementalMasteryActive() then return true end
    local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,LearnedID(name) or name)
    if SafeValue(info) and type(info)=="table" then
        if Bool(info.isEnabled)==false then return false end
        local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate) or 1
        if start and duration and start>=0 and duration>=0 and rate>0 then
            local ending=(start==0 or duration<=1.5) and 0 or start+duration/rate
            if Enabled(AL.S(),"elemental") then
                enh.cooldowns[SHOCKS[name] and "shock" or name]=ending>GetTime()
                    and {at=record and record.at or -math.huge,ends=ending} or nil
            end
            return ending<=GetTime()
        end
        -- A readable inactive cooldown is also evidence of a real reset.
        if Bool(info.isActive)==false then return true end
    end
    if record then return record.ends<=GetTime() end
    if ENH_COOLDOWNS[name] or SHOCKS[name] then return true end
    return Bool((SafeCall(AL.IsReady,name)))==true
end

local function ReadableCooldown(name)
    local start, duration = SafeCall(AL.SpellCooldown, name)
    start, duration = Number(start), Number(duration)
    if start and duration and start >= 0 and duration >= 0 then
        return start == 0 or duration <= 1.5 or start + duration <= GetTime(), start + duration
    end
end

local function CooldownReady(name)
    if SHOCKS[name] then
        if shockCastAt and GetTime() - shockCastAt < 0.5 then return false end
        local ready = ReadableCooldown(name)
        if ready ~= nil then return ready end
        if GetTime() < shockLockUntil then return false end
    end
    local localCD = localCooldowns[name]
    if localCD then
        if GetTime() - localCD.at < 0.5 then return false end
        local ready = ReadableCooldown(name)
        if ready ~= nil then return ready end
        if GetTime() < localCD.ends then return false end
    end
    return Bool((SafeCall(AL.IsReady, name))) == true
end

local function MainHandIdentity()
    local guid = SafeCall(GetInventoryItemGUID, "player", 16)
    if SafeValue(guid) and type(guid) == "string" and guid ~= "" then return "GUID:" .. guid end
    local id = Number((SafeCall(GetInventoryItemID, "player", 16)))
    if id and id > 0 then return "ID:" .. id end
end

local function WeaponStatePlayer()
    local guid = SafeCall(UnitGUID, "player")
    if SafeValue(guid) and type(guid) == "string" and guid ~= "" then return guid end
end

local function ClearTrackedWeapon(clearSaved)
    trackedWeapon, trackedWeaponUntil, trackedWeaponCastAt, trackedWeaponIdentity, trackedWeaponEnchantID = nil, nil, nil, nil, nil
    trackedWeaponObservation = {}
    if clearSaved and AL.playerClass == "SHAMAN" then
        local player = WeaponStatePlayer()
        local saved = ActionLiteDB and ActionLiteDB.shamanWeaponEnchants
        if player and SafeValue(saved) and type(saved) == "table" then saved[player] = nil end
    end
end

local function SaveTrackedWeapon()
    if AL.playerClass ~= "SHAMAN" or not ActionLiteDB then return end
    local player = WeaponStatePlayer()
    if not player or not trackedWeaponIdentity or not trackedWeaponUntil then return end
    local saved = ActionLiteDB.shamanWeaponEnchants
    if not SafeValue(saved) or type(saved) ~= "table" then saved = {}; ActionLiteDB.shamanWeaponEnchants = saved end
    saved[player] = { name=trackedWeapon, weapon=trackedWeaponIdentity,
        expires=time()+math.max(0,trackedWeaponUntil-GetTime()) }
end

local function RestoreTrackedWeapon()
    if AL.playerClass ~= "SHAMAN" then return end
    local player, identity = WeaponStatePlayer(), MainHandIdentity()
    local saved = ActionLiteDB and ActionLiteDB.shamanWeaponEnchants
    local record = player and SafeValue(saved) and type(saved) == "table" and saved[player]
    if not SafeValue(record) or type(record) ~= "table" or not identity then return end
    local expires = Number(record.expires)
    local name = SafeValue(record.name) and type(record.name) == "string" and record.name or nil
    if not name or not WEAPON_ENCHANTS[name] or not expires or expires <= time()
        or not SafeValue(record.weapon) or record.weapon ~= identity then ClearTrackedWeapon(true); return end
    trackedWeapon, trackedWeaponUntil, trackedWeaponIdentity = name,
        GetTime()+math.min(expires-time(),WEAPON_ENCHANT_FALLBACK_DURATION), identity
    trackedWeaponCastAt, trackedWeaponEnchantID, trackedWeaponObservation = nil, nil, {}
end

local function TrackedWeaponActive(preferred)
    if trackedWeapon ~= preferred or not trackedWeaponUntil or GetTime() >= trackedWeaponUntil then return false end
    local identity = MainHandIdentity()
    if identity and trackedWeaponIdentity and identity ~= trackedWeaponIdentity then return false end
    return true
end

local function WeaponBuffName()
    local api = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local readable = type(api) == "function"
    local complete = false
    if readable then
        for index = 1, 40 do
            local ok, aura = pcall(api, "player", index, "HELPFUL")
            if not ok or not SafeValue(aura) then readable = false; break end
            if aura == nil then complete = true; break end
            if type(aura) ~= "table" then readable = false; break end
            local name = SafeValue(aura.name) and type(aura.name) == "string" and aura.name or nil
            name = name and ((AL.englishNames and AL.englishNames[name]) or name)
            if not name then
                local id = Number(aura.spellId)
                name = id and SafeCall(AL.SpellName, id)
                name = SafeValue(name) and type(name) == "string" and name or nil
                name = name and ((AL.englishNames and AL.englishNames[name]) or name)
            end
            if not name then readable = false; break end
            local expiration = Number(aura.expirationTime)
            if name and WEAPON_ENCHANTS[name] and (not expiration or expiration == 0 or expiration > GetTime()) then return name, true end
        end
    end
    -- A missing player aura does not prove a weapon enchant is missing.
    -- Use the core's tooltip/cast fallback only when native aura reads fail.
    if not readable then
        for name in pairs(WEAPON_ENCHANTS) do
            if Bool((SafeCall(AL.HasBuff, "player", name))) == true then return name end
        end
    end
    return nil, readable and complete
end

local function MainHandEnchantState(preferred)
    if type(GetInventoryItemID) == "function" then
        local id = Number((SafeCall(GetInventoryItemID, "player", 16)))
        if not id or id <= 0 then return nil end
    end
    local tracked = trackedWeapon and TrackedWeaponActive(trackedWeapon)
    if trackedWeapon and not tracked then ClearTrackedWeapon(true) end
    local recent = tracked and trackedWeaponCastAt and GetTime() - trackedWeaponCastAt < 2
    if recent then return trackedWeapon == preferred end
    local buff, buffsReadable = WeaponBuffName()
    if buff then
        if tracked and buff == trackedWeapon and buffsReadable then trackedWeaponObservation.buff = true end
        if tracked and buff ~= trackedWeapon then ClearTrackedWeapon(true) end
        return buff == preferred
    end
    if tracked and buffsReadable and trackedWeaponObservation.buff then
        ClearTrackedWeapon(true)
        return false -- a previously observed native weapon buff was removed
    end
    local have, expiration, _, id = SafeCall(GetWeaponEnchantInfo)
    have, expiration, id = Bool(have), Number(expiration), Number(id)
    if have == false then
        -- Forever can report no temporary enchant throughout a successful
        -- Rockbiter buff. Absence only disproves a cast after this session
        -- actually observed the enchant on the same weapon.
        if tracked and not trackedWeaponObservation.enchant then return trackedWeapon == preferred end
        ClearTrackedWeapon(true)
        return false
    elseif have == true then
        if tracked then
            -- Learn the post-cast client ID; historical IDs can differ on
            -- Forever. A later ID change means the enchant was replaced.
            if id and id > 0 and trackedWeaponEnchantID and id ~= trackedWeaponEnchantID then
                ClearTrackedWeapon(true)
            else
                trackedWeaponObservation.enchant = true
                if id and id > 0 then trackedWeaponEnchantID = id end
                -- A constant zero/small countdown immediately after success
                -- is not a verified expiration. Trust the refresh window
                -- only after a healthy countdown has been observed.
                if expiration and expiration > 2000 then trackedWeaponObservation.countdown = true end
                if expiration and expiration <= 600 and trackedWeaponObservation.countdown then
                    ClearTrackedWeapon(true); return false
                end
                return trackedWeapon == preferred
            end
        end
        if expiration and expiration > 0 and expiration <= 600 then return false end
        if id and id > 0 then
            for name, ids in pairs(WEAPON_ENCHANT_IDS) do
                if ids[id] then return name == preferred end
            end
        end
        return nil -- unknown IDs are not evidence of a wrong enchant
    end
    if tracked then return trackedWeapon == preferred end
end

local function PreferredWeapon(s, role)
    local mode = SettingChoice(s, "weaponMode", { AUTO=true, WINDFURY=true, ROCKBITER=true, FLAMETONGUE=true }, "AUTO")
    if mode == "AUTO" and Enabled(s,"enhancement") and Ok("Rockbiter Weapon") then return "Rockbiter Weapon" end
    if mode == "AUTO" and not Standalone(s) and AL.DPS60 and AL.DPS60.Active()
        and AL.DPS60.Build("SHAMAN", s, "AUTO") == "ELEHANCE" and Ok("Rockbiter Weapon") then return "Rockbiter Weapon" end
    local name = ({ WINDFURY="Windfury Weapon", ROCKBITER="Rockbiter Weapon", FLAMETONGUE="Flametongue Weapon" })[mode]
    if name and Ok(name) then return name end
    local order = role == "ELEMENTAL" and { "Flametongue Weapon", "Rockbiter Weapon", "Windfury Weapon" }
        or { "Windfury Weapon", "Rockbiter Weapon", "Flametongue Weapon" }
    for _, spell in ipairs(order) do if Ok(spell) then return spell end end
end

local function TotemSnapshot()
    local active, readable, occupied, empty = {}, {}, {}, 0
    local slotElements = {}
    for element, slot in pairs({ FIRE=FIRE_TOTEM_SLOT, EARTH=EARTH_TOTEM_SLOT, WATER=WATER_TOTEM_SLOT, AIR=AIR_TOTEM_SLOT }) do
        slot = Number(slot)
        if slot and slot >= 1 and slot <= 4 then slotElements[slot] = element end
    end
    for slot = 1, 4 do
        local have, name, start, duration = SafeCall(GetTotemInfo, slot)
        have = Bool(have)
        if SafeValue(name) and type(name) == "string" then name = (AL.englishNames and AL.englishNames[name]) or name
        else name = nil end
        local element = name and TOTEM_ELEMENT[name] or slotElements[slot]
        if have == false then
            empty = empty + 1
            if element then readable[element] = true end
        elseif have == true and element then
            readable[element], occupied[element] = true, true
            if name and TOTEM_ELEMENT[name] then active[name] = true
            else active["?" .. element] = true end
            start, duration = Number(start), Number(duration)
            if name and TOTEM_ELEMENT[name] and start and duration and duration > 0 then
                trackedTotems[element] = { name=name, at=trackedTotems[element] and trackedTotems[element].at or -math.huge,
                    expires=start + duration }
            elseif name and TOTEM_ELEMENT[name] and (not trackedTotems[element] or trackedTotems[element].name ~= name) then
                trackedTotems[element] = { name=name, at=-math.huge, expires=GetTime()+(TOTEM_FALLBACK[name] or 10) }
            end
        end
    end
    for element, record in pairs(trackedTotems) do
        local recent = GetTime() - record.at < 0.5
        if record.expires <= GetTime() or (not recent and (empty == 4 or (readable[element] and not occupied[element]))) then
            trackedTotems[element] = nil
        elseif not occupied[element] and (recent or not readable[element]) then active[record.name] = true end
    end
    return active
end

local function ActiveTotemFrom(element, snapshot)
    for _, name in ipairs(TOTEM_GROUPS[element]) do if snapshot[name] then return name end end
    if snapshot["?" .. element] then return "?" end
end

local function PreferredEarthTotem(s, role)
    local mode = SettingChoice(s, "earthTotemMode", { AUTO=true, STRENGTH=true, STONESKIN=true, OFF=true }, "AUTO")
    if mode == "OFF" then return end
    local desired = ({ STRENGTH="Strength of Earth Totem", STONESKIN="Stoneskin Totem" })[mode]
    if desired and Ok(desired) then return desired end
    local names = role == "ENHANCEMENT" and { "Strength of Earth Totem", "Stoneskin Totem" }
        or { "Stoneskin Totem", "Strength of Earth Totem" }
    for _, name in ipairs(names) do if Ok(name) then return name end end
end

local function PreferredWaterTotem(s, role)
    local mode = SettingChoice(s, "waterTotemMode", { AUTO=true, HEALING=true, MANA=true, OFF=true }, "AUTO")
    if mode == "OFF" then return end
    local desired = ({ HEALING="Healing Stream Totem", MANA="Mana Spring Totem" })[mode]
    if desired and Ok(desired) then return desired end
    local names = role == "ELEMENTAL" and { "Mana Spring Totem", "Healing Stream Totem" }
        or { "Healing Stream Totem", "Mana Spring Totem" }
    for _, name in ipairs(names) do if Ok(name) then return name end end
end

local function InMelee()
    if Ok("Stormstrike") then
        local range = Bool((SafeCall(AL.InRange, "Stormstrike")))
        if range ~= nil then return range end
    end
    if Bool((SafeCall(AL.InRange, "Attack"))) == true then return true end
    return Bool((SafeCall(AL.TargetInMelee))) == true
end

local function MeleeAttack(reason)
    if Bool(AL.known and AL.known.Attack) == true and Bool((SafeCall(AL.Allowed, "Attack"))) ~= false and InMelee() then
        AddAction("Attack", reason)
    else AddAction(nil, PlayerMoving() and "Stop moving" or reason) end
end

local function Offer(name, reason, gates, preparation, showRange)
    if not Standalone(AL.S()) and AL.DPS60 and AL.DPS60.Active() and AL.DPS60.Info(name) and not AL.DPS60.Ready(name) then return false end
    if not Ok(name) then return false end
    if Standalone(AL.S()) then
        if not EnhancementReady(name) then return false end
    elseif not CooldownReady(name) then return false end
    local usable, shortage = SpellUsability(name)
    if usable == false or shortage == true then return false end
    if not showRange and Bool((SafeCall(AL.InRange, name))) == false then return false end
    local conditions = {}
    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
    local affordable = Affordable(name, usable, shortage)
    if preparation and ManaAmount() == nil and usable == true and shortage == false then affordable = true end
    conditions[#conditions + 1] = affordable
    return AddAction(name, reason, conditions)
end

local function Heal(s, hp, mana, inCombat, moving)
    if not Enabled(s, "heal") or moving then return end
    local key = inCombat and "healHP" or "healOutOfCombatHP"
    local gates = { HealthGate("player", hp, SettingNumber(s,key,M.defaults[key],5,95), true),
        ManaGate(mana, SettingNumber(s,"healMinMana",10,0,100), false) }
    if inCombat then Offer("Lesser Healing Wave", "Emergency heal", gates) end
    Offer("Healing Wave", inCombat and "Emergency heal" or "Heal up", gates)
end

local function ElementalShieldActive(name)
    local record, now = enh.shield, GetTime()
    if record and now-record.at<0.5 then return record.name==name end
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not enh.shieldBlocked and type(reader)=="function" then
        for index=1,40 do
            local ok,aura=pcall(reader,"player",index,"HELPFUL")
            if not ok or not SafeValue(aura) then enh.shieldBlocked=true;break end
            if aura==nil then
                if record and record.name==name then enh.shield=nil end
                return false
            end
            if type(aura)~="table" then break end
            local id=Number(aura.spellId)
            local auraName=SafeValue(aura.name) and type(aura.name)=="string" and aura.name
            auraName=auraName and ((AL.englishNames and AL.englishNames[auraName]) or auraName)
            if id==LearnedID(name) or auraName==name then
                local expires=Number(aura.expirationTime)
                return not expires or expires==0 or expires>now
            end
        end
    end
    if record then return record.name==name and record.expires>now end
    return Bool((SafeCall(AL.HasBuff,"player",name)))==true
end

local function Maintenance(s, role, inCombat, moving)
    if Enabled(s, "shield") then
        local high = not Standalone(s) and AL.DPS60 and AL.DPS60.Active()
        local shield = Enabled(s,"elemental") and Enabled(s,"elementalWaterShield") and Ok("Water Shield") and "Water Shield"
            or high and role == "ELEMENTAL" and AL.DPS60.Known("Water Shield") and "Water Shield" or "Lightning Shield"
        local missing
        if Enabled(s,"elemental") then missing=not ElementalShieldActive(shield)
        else missing=high and AL.DPS60.Missing(shield, false) or not high and not AL.HasBuff("player",shield) end
        if missing then Offer(shield, "Shield", nil, true) end
    end
    if not inCombat and not moving and Enabled(s, "weapon") then
        local preferred = PreferredWeapon(s, role)
        if preferred and MainHandEnchantState(preferred) == false then Offer(preferred, "Weapon enchant", nil, true) end
    end
end

local function MaintainCombatTotems(s, role, targetHP, snapshot)
    if not Enabled(s, "totems") then return end
    local gates = { HealthGate("target", targetHP, SettingNumber(s,"totemMinTargetHP",45,0,100), false) }
    local earth, water = PreferredEarthTotem(s,role), PreferredWaterTotem(s,role)
    local activeEarth, activeWater = ActiveTotemFrom("EARTH",snapshot), ActiveTotemFrom("WATER",snapshot)
    if earth and not snapshot[earth] and (not activeEarth or activeEarth == "Strength of Earth Totem" or activeEarth == "Stoneskin Totem") then
        Offer(earth, "Earth totem", gates)
    end
    if water and not snapshot[water] and (not activeWater or activeWater == "Healing Stream Totem" or activeWater == "Mana Spring Totem") then
        Offer(water, "Water totem", gates)
    end
    if role == "ENHANCEMENT" and AL.DPS60 and AL.DPS60.Active() then
        local air = AL.DPS60.Known("Grace of Air Totem") and "Grace of Air Totem"
            or AL.DPS60.Known("Windfury Totem") and "Windfury Totem"
        local activeAir = ActiveTotemFrom("AIR", snapshot)
        if air and not snapshot[air] and (not activeAir or activeAir == "Windfury Totem" or activeAir == "Grace of Air Totem") then
            Offer(air, "Air totem", gates)
        end
    end
    if Enabled(s,"searing") and not ActiveTotemFrom("FIRE",snapshot) then Offer("Searing Totem", "Fire totem", gates) end
end

local function AoETotem(s, mana, count, snapshot, targetHP)
    if not Enabled(s,"aoe") or not count or count < SettingNumber(s,"aoeMinEnemies",2,2,5) then return end
    local gates = { ManaGate(mana, SettingNumber(s,"aoeMinMana",30,0,100), false),
        HealthGate("target", targetHP, SettingNumber(s,"totemMinTargetHP",45,0,100), false) }
    if AL.DPS60 and AL.DPS60.Active() then
        if Enabled(s,"firenova") then Offer("Fire Nova", "AoE Fire Nova", gates) end
        if not PlayerMoving() then Offer("Chain Lightning", "AoE chain", gates) end
    end
    if Enabled(s,"firenova") and not snapshot["Fire Nova Totem"] and not snapshot["?FIRE"] then Offer("Fire Nova Totem", "AoE", gates) end
    if Enabled(s,"magma") and not snapshot["Magma Totem"] and not snapshot["Fire Nova Totem"] and not snapshot["?FIRE"] then
        Offer("Magma Totem", "AoE", gates)
    end
end

local function Burst(s, role, targetHP)
    if not AL.burst then return end
    if role == "ENHANCEMENT" and not InMelee() then return end
    if role == "ELEMENTAL" and Bool((SafeCall(AL.InRange,"Lightning Bolt"))) ~= true then return end
    local gates = { HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false) }
    if role == "ENHANCEMENT" then Offer("Blood Fury", "Burst", gates) end
    Offer("Berserking", "Burst", gates)
end

local function LightningBolt(s, mana, moving, reason)
    if Enabled(s,"lightningbolt") and not moving then
        Offer("Lightning Bolt", reason, { ManaGate(mana,SettingNumber(s,"lightningBoltMinMana",15,0,100),false) },false,true)
    end
end

local function Damage(s, role, mana, targetHP, moving)
    local shock = ManaGate(mana,SettingNumber(s,"shockMinMana",25,0,100),false)
    if Enabled(s,"flameshock") and not AL.HasDebuff("target","Flame Shock") then
        Offer("Flame Shock","Damage over time",{ shock,
            HealthGate("target",targetHP,SettingNumber(s,"flameShockMinTargetHP",35,0,100),false) })
    end
    if role == "ENHANCEMENT" and Enabled(s,"stormstrike") and InMelee() then Offer("Stormstrike","Melee priority") end
    if AL.DPS60 and AL.DPS60.Active() then
        if Enabled(s,"lightningbolt") and AL.DPS60.Proc("Maelstrom Weapon", 5) then
            Offer("Lightning Bolt", "Maelstrom Weapon", { ManaGate(mana,SettingNumber(s,"lightningBoltMinMana",15,0,100),false) })
        end
        if role == "ELEMENTAL" and not moving then Offer("Lava Burst", "learned damage", { ManaGate(mana,SettingNumber(s,"lightningBoltMinMana",15,0,100),false) }) end
    end
    if Enabled(s,"frostshock") then Offer("Frost Shock","Low-health slow",{shock,
        HealthGate("target",targetHP,SettingNumber(s,"frostShockTargetHP",25,0,100),true) }) end
    if Enabled(s,"earthshock") then Offer("Earth Shock","Nature damage",{shock}) end
    local allowHardcast = true
    if role == "ENHANCEMENT" and InMelee() and AL.DPS60 and AL.DPS60.Active() then
        allowHardcast = false
        if AL.DPS60.Build("SHAMAN", s, "ENHANCEMENT") == "ELEHANCE" and not moving and A and A.Player then
            local remains = Number((SafeCall(A.Player.GetSwing, A.Player, 1)))
            local ref = AL.rangeSpellRefs and AL.rangeSpellRefs["Lightning Bolt"]
            local info = SafeCall(C_Spell and C_Spell.GetSpellInfo, ref and ref.id or 403)
            local castMS = SafeValue(info) and type(info) == "table" and Number(info.castTime)
            -- Never guess a weave window from protected swing/cast-time data.
            allowHardcast = remains ~= nil and castMS ~= nil and remains > castMS / 1000 + 0.15
        end
    end
    if allowHardcast then LightningBolt(s,mana,moving,role == "ELEMENTAL" and "Elemental filler" or "Leveling filler") end
    MeleeAttack("Conserve mana")
end

local function EnhancementInstantBolt()
    if GetTime()-enh.boltAt<0.5 then return false end
    local info=SafeCall(C_Spell and C_Spell.GetSpellInfo,LearnedID("Lightning Bolt") or "Lightning Bolt")
    if SafeValue(info) and type(info)=="table" and Number(info.castTime)==0 then return true end
    local rank=EnhancementTalent("Maelstrom Weapon")
    if rank~=5 then return false end
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if enh.procBlocked or type(reader)~="function" then return false end
    for index=1,40 do
        local ok,aura=pcall(reader,"player",index,"HELPFUL")
        if not ok or not SafeValue(aura) then enh.procBlocked=true;return false end
        if aura==nil then return false end
        if type(aura)~="table" then return false end
        local id=Number(aura.spellId)
        local name=SafeValue(aura.name) and type(aura.name)=="string" and aura.name
        name=name and ((AL.englishNames and AL.englishNames[name]) or name)
        if id==408505 or name=="Maelstrom Weapon" then
            local stacks,expires=Number(aura.applications),Number(aura.expirationTime)
            return stacks~=nil and stacks>=5 and (not expires or expires==0 or expires>GetTime())
        end
    end
    return false
end

local function EnhancementFlameActive()
    local guid=SafeCall(UnitGUID,"target")
    if not SafeValue(guid) or type(guid)~="string" then return false end
    local record=enh.flames[guid]
    if record and record.expires<=GetTime() then enh.flames[guid]=nil;record=nil end
    if record and GetTime()-record.at<0.6 then return true end
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not enh.flameBlocked and type(reader)=="function" then
        for index=1,40 do
            local ok,aura=pcall(reader,"target",index,"HARMFUL")
            if not ok or not SafeValue(aura) then enh.flameBlocked=true;break end
            if aura==nil then enh.flames[guid]=nil;return false end
            if type(aura)~="table" then break end
            local id=Number(aura.spellId)
            local name=SafeValue(aura.name) and type(aura.name)=="string" and aura.name
            name=name and ((AL.englishNames and AL.englishNames[name]) or name)
            local source=SafeValue(aura.sourceUnit) and aura.sourceUnit
            local own=source=="player" or Bool(aura.isFromPlayerOrPlayerPet)==true
                or (SafeValue(source) and type(source)=="string" and Bool((SafeCall(UnitIsUnit,source,"player")))==true)
            if own and (name=="Flame Shock" or id==LearnedID("Flame Shock")) then
                local expires=Number(aura.expirationTime)
                return not expires or expires==0 or expires>GetTime()
            end
        end
    end
    return record~=nil
end

local function EnhancementAir(s)
    local mode=SettingChoice(s,"enhancementAirTotem",{AUTO=true,WINDFURY=true,GRACE=true,OFF=true},"AUTO")
    if mode=="OFF" then return end
    local preferred=mode=="GRACE" and "Grace of Air Totem" or mode=="WINDFURY" and "Windfury Totem"
    if mode=="AUTO" then
        local weapon=PreferredWeapon(s,"ENHANCEMENT")
        -- An observed weapon enchant takes precedence over the preference.
        if MainHandEnchantState("Windfury Weapon")==true then weapon="Windfury Weapon" end
        preferred=weapon=="Windfury Weapon" and "Grace of Air Totem" or "Windfury Totem"
    end
    if Ok(preferred) then return preferred end
    -- Windfury Totem cannot add to an active Windfury Weapon enchant.
    if preferred=="Grace of Air Totem" and MainHandEnchantState("Windfury Weapon")==true then return end
    if Ok("Grace of Air Totem") then return "Grace of Air Totem" end
end

local function EnhancementTotems(s,targetHP,snapshot)
    if not Enabled(s,"totems") then return end
    local gates={HealthGate("target",targetHP,SettingNumber(s,"totemMinTargetHP",45,0,100),false)}
    local earth=PreferredEarthTotem(s,"ENHANCEMENT")
    local water=PreferredWaterTotem(s,"ELEMENTAL") -- AUTO: own Mana Spring, then Healing Stream.
    local air=EnhancementAir(s)
    for _,choice in ipairs({{earth,"EARTH"},{air,"AIR"},{water,"WATER"}}) do
        local name,element=choice[1],choice[2]
        local active=ActiveTotemFrom(element,snapshot)
        local replace=active==nil or element=="EARTH" and (active=="Strength of Earth Totem" or active=="Stoneskin Totem")
            or element=="AIR" and (active=="Windfury Totem" or active=="Grace of Air Totem")
            or element=="WATER" and (active=="Mana Spring Totem" or active=="Healing Stream Totem")
        if name and not snapshot[name] and replace then Offer(name,element.." totem",gates) end
    end
end

local function EnhancementBurst(s,targetHP)
    if Bool(AL.burst)~=true then return end
    local gates={HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false)}
    if Enabled(s,"enhancementRacials") then Offer("Blood Fury","Enhancement Burst",gates) end
    if Enabled(s,"enhancementRage") then Offer("Rage of the Farseer","Enhancement Burst",gates) end
    if Enabled(s,"enhancementRacials") then Offer("Berserking","Enhancement Burst",gates) end
end

local function EnhancementAoE(s,mana,count,snapshot,moving,instant)
    if not Enabled(s,"aoe") or not count or count<SettingNumber(s,"aoeMinEnemies",2,2,5) then return end
    local gate=ManaGate(mana,SettingNumber(s,"aoeMinMana",30,0,100),false)
    if Enabled(s,"firenova") and UnitWithin("target",8)==true then Offer("Fire Nova","Enhancement AoE",{gate}) end
    if Enabled(s,"lightningbolt") and Enabled(s,"enhancementMaelstrom") and instant then
        Offer("Lightning Bolt","Maelstrom Weapon",{gate,ManaGate(mana,SettingNumber(s,"lightningBoltMinMana",15,0,100),false)})
    end
    if Enabled(s,"totems") and Enabled(s,"magma") and not snapshot["Magma Totem"] and not snapshot["?FIRE"] then
        Offer("Magma Totem","Enhancement AoE",{gate,HealthGate("target",HealthPercent("target"),SettingNumber(s,"totemMinTargetHP",45,0,100),false)})
    end
    -- Forever's Maelstrom affects Lightning Bolt only. Chain Lightning is an
    -- explicit opt-in hard cast and never gains an assumed instant proc.
    if Enabled(s,"enhancementChainLightning") and not moving then Offer("Chain Lightning","Enhancement AoE hard cast",{gate}) end
end

local function EnhancementDamage(s,inCombat,mana,targetHP,moving,melee)
    if not inCombat or not melee then
        LightningBolt(s,mana,moving,inCombat and "Ranged combat" or "Ranged pull")
        if not inCombat then return end
    end
    local shock=ManaGate(mana,SettingNumber(s,"shockMinMana",25,0,100),false)
    if melee then
        local snapshot=TotemSnapshot()
        EnhancementTotems(s,targetHP,snapshot)
        EnhancementBurst(s,targetHP)
        if Enabled(s,"stormstrike") then Offer("Stormstrike","Enhancement Stormstrike") end
        local instant=Enabled(s,"lightningbolt") and Enabled(s,"enhancementMaelstrom") and EnhancementInstantBolt()
        local count=Enabled(s,"aoe") and EnemyCount(SettingNumber(s,"aoeMinEnemies",2,2,5)) or nil
        EnhancementAoE(s,mana,count,snapshot,moving,instant)
        if instant then Offer("Lightning Bolt","Maelstrom Weapon",{ManaGate(mana,SettingNumber(s,"lightningBoltMinMana",15,0,100),false)}) end
        if Enabled(s,"totems") and Enabled(s,"searing") and not ActiveTotemFrom("FIRE",snapshot) then
            Offer("Searing Totem","Fire totem",{HealthGate("target",targetHP,SettingNumber(s,"totemMinTargetHP",45,0,100),false)})
        end
    end
    if Enabled(s,"flameshock") and not EnhancementFlameActive() then
        Offer("Flame Shock","Enhancement damage over time",{shock,HealthGate("target",targetHP,SettingNumber(s,"flameShockMinTargetHP",35,0,100),false)})
    end
    if Enabled(s,"earthshock") then Offer("Earth Shock","Enhancement Nature damage",{shock}) end
    if Enabled(s,"frostshock") then Offer("Frost Shock","Low-health slow",{shock,
        HealthGate("target",targetHP,SettingNumber(s,"frostShockTargetHP",25,0,100),true)}) end
    MeleeAttack("Conserve mana")
end

local function ElementalChainProc()
    if not Ok("Chain Lightning") or not EnhancementReady("Chain Lightning") then return false end
    -- Elemental Focus makes one spell free in this Forever build. Require
    -- current readable evidence; a missing/empty cost table is not zero.
    if enh.clearConsumeAt and GetTime()-enh.clearConsumeAt<0.5 then return false end
    local costs=SafeCall(C_Spell and C_Spell.GetSpellPowerCost,LearnedID("Chain Lightning") or "Chain Lightning")
    if SafeValue(costs) and type(costs)=="table" then
        for _,cost in ipairs(costs) do
            if SafeValue(cost) and type(cost)=="table" and Number(cost.type)==0 and Number(cost.cost)==0 then return true end
        end
    end
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if enh.clearBlocked or type(reader)~="function" then return false end
    for index=1,40 do
        local ok,aura=pcall(reader,"player",index,"HELPFUL")
        if not ok or not SafeValue(aura) then enh.clearBlocked=true;return false end
        if aura==nil then return false end
        if type(aura)~="table" then return false end
        local name=SafeValue(aura.name) and type(aura.name)=="string" and aura.name
        name=name and ((AL.englishNames and AL.englishNames[name]) or name)
        if Number(aura.spellId)==16246 or name=="Clearcasting" then
            local expires=Number(aura.expirationTime)
            return not expires or expires==0 or expires>GetTime()
        end
    end
    return false
end

local function ElementalDamage(s,inCombat,mana,targetHP,moving)
    -- This ranged build remains a caster in melee. Out of combat the
    -- existing shield/enchant/heal preparation runs before a Bolt pull.
    if not inCombat then
        LightningBolt(s,mana,moving,"Elemental pull")
        if moving and Enabled(s,"flameshock") and not EnhancementFlameActive() then
            Offer("Flame Shock","Elemental moving pull",{ManaGate(mana,SettingNumber(s,"shockMinMana",25,0,100),false),
                HealthGate("target",targetHP,SettingNumber(s,"flameShockMinTargetHP",35,0,100),false)})
        end
        return
    end
    local snapshot=TotemSnapshot()
    local minimum=SettingNumber(s,"aoeMinEnemies",2,2,5)
    local closeCount=Enabled(s,"aoe") and EnemyCount(minimum) or nil
    local closeAoE=closeCount and closeCount>=minimum and UnitWithin("target",8)==true
    local rangedCount=Enabled(s,"aoe") and Enabled(s,"elementalChainLightning") and EnemyCount(minimum,36) or nil
    local aoeMana=ManaGate(mana,SettingNumber(s,"aoeMinMana",30,0,100),false)
    local totemHP=HealthGate("target",targetHP,SettingNumber(s,"totemMinTargetHP",45,0,100),false)
    if Enabled(s,"totems") then
        local earth,water=PreferredEarthTotem(s,"ELEMENTAL"),PreferredWaterTotem(s,"ELEMENTAL")
        for _,choice in ipairs({{earth,"EARTH"},{water,"WATER"}}) do
            local name,element=choice[1],choice[2]
            local active=ActiveTotemFrom(element,snapshot)
            local replace=not active or element=="EARTH" and (active=="Strength of Earth Totem" or active=="Stoneskin Totem")
                or element=="WATER" and (active=="Mana Spring Totem" or active=="Healing Stream Totem")
            if name and not snapshot[name] and replace then Offer(name,"Elemental "..element.." totem",{totemHP}) end
        end
        -- Fire area totems require actual close combat; ranged enemy counts
        -- used for Chain Lightning cannot enable a player-centred area spell.
        if closeAoE and Enabled(s,"magma") and Ok("Magma Totem") then
            if not snapshot["Magma Totem"] and not snapshot["?FIRE"] then Offer("Magma Totem","Elemental AoE totem",{aoeMana,totemHP}) end
        elseif Enabled(s,"searing") and not ActiveTotemFrom("FIRE",snapshot) and UnitWithin("target",20)==true then
            Offer("Searing Totem","Elemental fire totem",{totemHP})
        end
    end
    if Bool(AL.burst)==true and Enabled(s,"elementalMastery") and not moving and not ElementalMasteryActive()
        and (Ok("Lightning Bolt") or Ok("Lava Burst"))
        and (Bool((SafeCall(AL.InRange,"Lightning Bolt")))==true or Bool((SafeCall(AL.InRange,"Lava Burst")))==true) then
        Offer("Elemental Mastery","Elemental Burst",{
            HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false),
            ManaGate(mana,SettingNumber(s,"lightningBoltMinMana",15,0,100),false)})
    end
    if Bool(AL.burst)==true and Enabled(s,"elementalRacials")
        and (Bool((SafeCall(AL.InRange,"Lightning Bolt")))==true or Bool((SafeCall(AL.InRange,"Lava Burst")))==true) then
        local gates={HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false)}
        Offer("Blood Fury","Elemental Burst racial",gates)
        Offer("Berserking","Elemental Burst racial",gates)
    end
    if Enabled(s,"flameshock") and not EnhancementFlameActive() then
        Offer("Flame Shock","Elemental damage over time",{ManaGate(mana,SettingNumber(s,"shockMinMana",25,0,100),false),
            HealthGate("target",targetHP,SettingNumber(s,"flameShockMinTargetHP",35,0,100),false)})
    end
    if Enabled(s,"elementalLavaBurst") and not moving then
        Offer("Lava Burst","Elemental Lava Burst",{ManaGate(mana,SettingNumber(s,"elementalLavaBurstMana",15,0,100),false)})
    end
    if closeAoE and Enabled(s,"firenova") then Offer("Fire Nova","Elemental AoE nova",{aoeMana}) end
    if rangedCount and rangedCount>=minimum and not moving
        and (not Enabled(s,"elementalChainClearcasting") or ElementalMasteryActive() or ElementalChainProc()) then
        Offer("Chain Lightning","Elemental ranged AoE",{aoeMana,ManaGate(mana,SettingNumber(s,"elementalChainMana",30,0,100),false)})
    end
    LightningBolt(s,mana,moving,"Elemental filler")
    -- Ordinary Earth/Frost Shocks are movement or unavailable-cast fallbacks;
    -- they do not replace a ready stationary Bolt on every shared shock CD.
    local shock={ManaGate(mana,SettingNumber(s,"shockMinMana",25,0,100),false)}
    if Enabled(s,"earthshock") then Offer("Earth Shock","Elemental instant fallback",shock) end
    if Enabled(s,"frostshock") then
        Offer("Frost Shock","Elemental low-health slow",{shock[1],HealthGate("target",targetHP,SettingNumber(s,"frostShockTargetHP",25,0,100),true)})
    end
    MeleeAttack("Conserve mana")
end

function M.NextSpell(s, inCombat, hostile)
    M.NormalizeBuild(s)
    lastRotation = { at=GetTime(), actions={} }
    if not inCombat and Enabled(s,"elemental") then
        for _,name in ipairs({"Lava Burst","Water Shield","Blood Fury","Berserking"}) do
            if Ok(name) then EnhancementReady(name) end
        end
    end
    local role, moving, mana = Role(s), PlayerMoving(), GateManaPercent()
    local hp, targetHP = HealthPercent("player"), hostile and HealthPercent("target") or nil
    if PlayerIsCastingOrChanneling() then AddAction(nil,"Casting")
    else
        if inCombat and hostile and Enabled(s,"interrupt") and Bool((SafeCall(AL.TargetCasting))) == true then
            Offer("Earth Shock","Interrupt")
        end
        Heal(s,hp,mana,inCombat,moving)
        if inCombat and hostile and Enabled(s,"stoneclaw") then
            local snapshot = TotemSnapshot()
            if not snapshot["Stoneclaw Totem"] and not snapshot["?EARTH"] then
                Offer("Stoneclaw Totem","Defensive totem",{ HealthGate("player",hp,SettingNumber(s,"stoneclawHP",25,5,80),true) })
            end
        end
        Maintenance(s,role,inCombat,moving)
        if hostile then
            local melee = InMelee()
            if Enabled(s,"elemental") then
                ElementalDamage(s,inCombat,mana,targetHP,moving)
            elseif Enabled(s,"enhancement") then
                if not inCombat and melee then
                    EnhancementTotems(s,targetHP,TotemSnapshot());MeleeAttack("Opener")
                else EnhancementDamage(s,inCombat,mana,targetHP,moving,melee) end
            elseif not inCombat then
                if not melee then LightningBolt(s,mana,moving,"Ranged pull")
                else MaintainCombatTotems(s,role,targetHP,TotemSnapshot());MeleeAttack("Opener") end
            elseif role == "ENHANCEMENT" and not melee then
                LightningBolt(s,mana,moving,"Ranged combat");Damage(s,role,mana,targetHP,moving)
            else
                Burst(s,role,targetHP)
                local snapshot = TotemSnapshot()
                local count = Enabled(s,"aoe") and EnemyCount(SettingNumber(s,"aoeMinEnemies",2,2,5)) or nil
                AoETotem(s,mana,count,snapshot,targetHP)
                MaintainCombatTotems(s,role,targetHP,snapshot)
                Damage(s,role,mana,targetHP,moving)
            end
        end
    end
    AddAction(nil, inCombat and not hostile and "No target" or "Ready")
    local base = lastRotation.actions[#lastRotation.actions]
    lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
    return base.spell, base.reason
end

function M.CanTrackSuggestedSpell(name)
    if not lastRotation or GetTime()-lastRotation.at > 0.5 or lastRotation.visualCandidate then return false end
    local visual = AL.rotationSecretVisual
    if visual and GetTime()-visual.at <= 0.5 then return false end
    return name == lastRotation.baseSpell and Ok(name)
end

function M.OnTargetChanged()
    lastRotation, AL.rotationSecretVisual, enh.flameBlocked = nil, nil, nil
end

function M.OnCastResult(name, result, sent)
    if result ~= "UNIT_SPELLCAST_SUCCEEDED" or not name then return end
    local now = GetTime()
    if enh.duplicateAt==now and enh.duplicateName==name then return end
    local duration=ENH_COOLDOWNS[name]
    if name=="Elemental Mastery" then
        enh.masteryAt,enh.masteryUntil=now,now+15
        enh.cooldowns["Chain Lightning"]=nil
    elseif name=="Chain Lightning" and Enabled(AL.S(),"elemental") and ElementalMasteryActive() then duration=0 end
    if name=="Fire Nova" then duration=10-2*math.min(2,EnhancementTalent("Improved Fire Nova") or 0) end
    if SHOCKS[name] then duration=6-0.2*math.min(5,EnhancementTalent("Reverberation") or 0) end
    if duration then enh.cooldowns[SHOCKS[name] and "shock" or name]={at=now,ends=now+duration} end
    if name=="Lightning Bolt" then enh.boltAt=now end
    if name=="Lightning Bolt" or name=="Lava Burst" or name=="Chain Lightning" or name=="Fire Nova" or SHOCKS[name] then enh.clearConsumeAt=now end
    if name=="Water Shield" or name=="Lightning Shield" then enh.shield={name=name,at=now,expires=now+600} end
    if name=="Flame Shock" and sent and SafeValue(sent.targetGUID) and type(sent.targetGUID)=="string" then
        for guid,record in pairs(enh.flames) do if record.expires<=now then enh.flames[guid]=nil end end
        enh.flames[sent.targetGUID]={at=now,expires=now+M.FlameShockDuration()}
    end
    if SHOCKS[name] then
        local _, ending = ReadableCooldown(name)
        shockLockUntil, shockCastAt = ending and ending > now+1.5 and ending or now+6, now
    elseif name == "Fire Nova Totem" then
        local _, ending = ReadableCooldown(name)
        localCooldowns[name] = { at=now, ends=ending and ending > now+1.5 and ending or now+15 }
    end
    if WEAPON_ENCHANTS[name] then
        trackedWeapon, trackedWeaponUntil, trackedWeaponCastAt, trackedWeaponIdentity = name,
            now+WEAPON_ENCHANT_FALLBACK_DURATION, now, MainHandIdentity()
        trackedWeaponEnchantID = nil
        trackedWeaponObservation = {}
        SaveTrackedWeapon()
    end
    local element = TOTEM_ELEMENT[name]
    if element then
        local duration=TOTEM_FALLBACK[name] or 10
        if Standalone(AL.S()) then
            if name=="Searing Totem" then
                duration=({[3599]=30,[6363]=35,[6364]=40,[6365]=45,[10437]=50,[10438]=55})[LearnedID(name)] or 30
            elseif name=="Strength of Earth Totem" or name=="Stoneskin Totem" or name=="Mana Spring Totem" or name=="Healing Stream Totem" then duration=300 end
        end
        trackedTotems[element] = { name=name, at=now, expires=now+duration }
    end
end

function M.GetUIState()
    local s = AL.S()
    local role, snapshot = Role(s), TotemSnapshot()
    local known = 0
    for _, entry in ipairs(M.spells) do if Bool(AL.known and AL.known[entry[2]]) == true then known=known+1 end end
    local preferred, weapon = PreferredWeapon(s,role)
    if preferred and MainHandEnchantState(preferred) == true then weapon=preferred end
    if not weapon and Bool((SafeCall(GetWeaponEnchantInfo))) == true then weapon="Enchanted" end
    local shield=Enabled(s,"elemental") and Enabled(s,"elementalWaterShield") and Ok("Water Shield") and "Water Shield" or "Lightning Shield"
    local shieldActive
    if Enabled(s,"elemental") then shieldActive=ElementalShieldActive(shield)
    else shieldActive=Bool((SafeCall(AL.HasBuff,"player",shield)))==true end
    return { role=role, enhancement=Enabled(s,"enhancement"), elemental=Enabled(s,"elemental"), shieldName=shield,
        shieldActive=shieldActive,
        level=Number((SafeCall(UnitLevel,"player"))), health=HealthPercent("player"), mana=GateManaPercent(),
        knownCount=known, lightningShield=Bool((SafeCall(AL.HasBuff,"player","Lightning Shield"))) == true,
        weaponEnchant=weapon, earthTotem=ActiveTotemFrom("EARTH",snapshot), waterTotem=ActiveTotemFrom("WATER",snapshot),
        fireTotem=ActiveTotemFrom("FIRE",snapshot), enemyCount=EnemyCount(SettingNumber(s,"aoeMinEnemies",2,2,5),Enabled(s,"elemental") and 36 or 8),
        shockLocked=GetTime()<shockLockUntil,
        elementalMasteryConfirmedUntil=enh.masteryUntil,
        callOfFlameRank=enh.talents["Call of Flame"],
        elementalMasteryID=LearnedID("Elemental Mastery") }
end

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
    return { cost = name and SpellManaCost(name), at=GetTime() }
end

function M.OnManaCastSucceeded(name, id, guid, sent)
    enh.duplicateAt,enh.duplicateName=nil,nil
    if Standalone(AL.S()) then
        local bookName=Number(id) and AL.castSpellNamesByID and AL.castSpellNamesByID[id]
        bookName=SafeValue(bookName) and type(bookName)=="string" and ((AL.englishNames and AL.englishNames[bookName]) or bookName)
        -- Damage/proc siblings may share a display name with the castable
        -- spell. They neither spend mana again nor start its cooldown.
        if not name or not AL.known or not AL.known[name]
            or (Number(id) and id~=LearnedID(name) and bookName~=name) then
            enh.duplicateAt,enh.duplicateName=GetTime(),name
            return
        end
    end
    if Standalone(AL.S()) and SafeValue(guid) and type(guid)=="string" then
        local now=GetTime()
        for key,at in pairs(enh.completed) do if now-at>300 then enh.completed[key]=nil end end
        if enh.completed[guid] then enh.duplicateAt,enh.duplicateName=now,name;return end
        enh.completed[guid]=now
    end
    castSucceededCount = castSucceededCount + 1
    lastSucceededCastName, lastSentCastName, lastSentCastAt = name, nil, 0
    if not name then return end
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


local tracker = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_AURA", "SPELLS_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_DEAD", "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(tracker.RegisterEvent, tracker, event)
end
tracker:SetScript("OnEvent", function(_, event, unit, token)
    if event=="SPELLS_CHANGED" or event=="CHARACTER_POINTS_CHANGED" or event=="PLAYER_TALENT_UPDATE" then
        enh.talentWarm,enh.talents,enh.procBlocked=nil,{},nil
    elseif event=="UNIT_AURA" then
        if SafeValue(unit) and unit=="player" then enh.procBlocked=nil;enh.clearBlocked=nil end
        if SafeValue(unit) and unit=="target" then enh.flameBlocked=nil end
    elseif event == "PLAYER_STARTED_MOVING" then movementEventActive = true
    elseif event == "PLAYER_STOPPED_MOVING" then movementEventActive = false
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
        enh.shield,enh.shieldBlocked=nil,nil
        enh.masteryAt,enh.masteryUntil=nil,0
        enh.clearBlocked,enh.clearConsumeAt=nil,nil
        enh.flames,enh.procBlocked,enh.flameBlocked,enh.boltAt={},nil,nil,-math.huge
        enh.talentWarm,enh.talents=nil,{}
        trackedMana, trackedManaMax, trackedManaUpdatedAt, trackedLastSpendAt = nil, nil, nil, nil
        trackedCostsKnown, trackedSource = true, "uninitialized"
        trackedLastSpell, trackedLastCost, eventManaPct, eventManaAt = nil, 0, nil, nil
        ClearTrackedWeapon(event == "PLAYER_DEAD")
        if event == "PLAYER_ENTERING_WORLD" then RestoreTrackedWeapon() end
        trackedTotems, localCooldowns, curveFailures = {}, {}, {}
        movementEventActive, curveCapabilities, visibilityCurves = nil, {}, {}
        shockLockUntil, shockCastAt, lastRotation, AL.rotationSecretVisual = 0, nil, nil, nil
    elseif event == "PLAYER_LOGIN" then RestoreTrackedWeapon()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if Number(unit) == 16 then
            local identity = MainHandIdentity()
            if not identity or not trackedWeaponIdentity or identity ~= trackedWeaponIdentity then ClearTrackedWeapon(true) end
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then enh.shieldBlocked,enh.clearBlocked=nil,nil;M.RefreshManaCache()
    elseif SafeValue(unit) and unit == "player" and (not SafeValue(token) or token == nil or token == "MANA") then RefreshManaSensor() end
end)
function M.ManaPercent() return GateManaPercent(), lastManaSource end
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
	if low > 0 and low <= 1 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
	if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
	if low ~= 1 and high ~= 1 then curve:AddPoint(1, CreateColor(1, 1, 1, low <= 1 and high > 1 and 1 or 0)) end
	visibilityCurves[key] = curve
	return curve
end

ReadVisualAlpha = function(mask)
    local curve = IntervalCurve(mask.low, mask.high)
    local color
    if mask.kind == "power" then color = UnitPowerPercent(mask.unit, mask.powerType, false, curve)
    else color = UnitHealthPercent(mask.unit, false, curve) end
    local _, _, _, alpha = color:GetRGBA()
    if SafeValue(alpha) and Number(alpha) == nil then error("Shaman resource curve returned no display alpha") end
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
                curveFailures[mask.kind .. ":" .. mask.unit .. ":" .. tostring(mask.powerType or "")] = {
                    reader = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent,
                    factory = C_CurveUtil and C_CurveUtil.CreateColorCurve }
                error("Shaman resource alpha unavailable")
            end
        else node:SetAlpha(1) end
	end
end





AL.RegisterRotation("SHAMAN", M)
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
    root.RegisterRotation("SHAMAN", advanced)
end
