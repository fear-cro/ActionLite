local ADDON, AL = ...

-- WoW Forever Mage leveling 1-30 - v0.15.6
-- Cible : beta 1.60.1.69913.
-- Les IDs et niveaux classiques servent uniquement de reperes LIKELY ; le
-- grimoire du client reste l'autorite. La portee exacte du rang appris pilote
-- la couleur rouge/normale ; elle ne remplace pas le nuke par une attaque melee.

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

-- IDs de rang 1 classiques utilises pour l'identification et les icones.
-- Ice Lance est conserve uniquement si Forever le place reellement dans le
-- grimoire ; son ID TBC n'est pas considere comme une preuve Forever.
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

-- Niveaux d'apprentissage classiques. Les talents et sorts non confirmes sur
-- Forever sont volontairement absents de cette table et gates par le livre.
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

-- Objets conjures classiques, du rang le plus bas au plus eleve. Un compteur
-- de sacs protege renvoie nil et ne provoque jamais une conjuration en boucle.
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

local WAND_HANDOFF_SPELLS = { ["Fire Blast"]=true, ["Frost Nova"]=true }

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
            if GetTime() < wandStopPendingUntil then return AddAction(nil, "Stopping wand", conditions) end
            return AddAction("Shoot", "Stop wand for " .. name, conditions)
        end
        -- Shoot recovery may be absent from the spell's cooldown data. Use a
        -- 1.5 s fallback after an accepted shot before offering an instant.
        if recovery or GetTime() < wandRecoveryUntil then return AddAction(nil, "Global cooldown", conditions) end
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
    return SafeValue(name) and type(name) == "string"
end

LiveWandActive = function()
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
    if moving then return AddAction(nil, "Stop moving to wand", gates) end
    if PlayerIsWanding() then return AddAction(nil, "Wand active", gates) end
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
    if not inCombat and Enabled(s, "drink") then
        AddAction(nil, "Drink", { ManaGate(mana, SettingNumber(s, "drinkMana", 35, 0, 80), true) })
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
