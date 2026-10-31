local ADDON, AL = ...

-- ActionLITE Paladin v0.15.0: original Leveling, optional talent builds and Holy Healing Rotation.

-- Leveling keeps the finalized pre-simulation implementation in its own
-- scope. Talent builds use the separate implementation below. Both observe
-- real casts so switching rotations retains resource and spell history.
do
    local root = AL
    local leveling, advanced
    local function UsesLeveling(profile)
        profile = profile or (root.Profile and root.Profile("PALADIN")) or (root.S and root.S())
        if advanced and type(profile) == "table" then
            return advanced.NormalizeBuild(profile) == "leveling"
        end
        return true
    end
    local function RotationScope(isLeveling)
        local scope = {
            RegisterRotation = function(token, module)
                assert(token == "PALADIN", "Unexpected class rotation")
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
                    if root.playerClass == "PALADIN" and UsesLeveling() == isLeveling then root[key] = value end
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
-- BEGIN ORIGINAL LEVELING IMPLEMENTATION (Paladin(5).lua)
local ADDON, AL = ...

-- WoW Forever Paladin Retribution / Protection leveling 1-30
-- ActionLITE Paladin v0.11.3
-- Target: beta 1.60.1.69913.
-- Status: LIKELY until costs, ranks and talents are directly validated.
-- Protected values are never treated as zero.

local A = _G.Action

local M = {
	defaults = {
		paladinRole = "DPS",
		buffs = true,
		blessingMode = "AUTO",
		auraMode = "AUTO",
		seal = "AUTO",
		judgement = true,
		holystrike = true,
		exorcism = true,
		hammer = true,
		emergency = true,
		drink = true,
		drinkMana = 30,
		judgementMinMana = 15,
		judgementMinTargetHP = 20,
		holyStrikeMinMana = 10,
		exorcismMinMana = 25,
		exorcismMinTargetHP = 25,
		aoe = false,
		consecration = true,
		aoeMinEnemies = 2,
		consecrationMinMana = 35,
		burstMinTargetHP = 40,
		oocHeal = true,
		oocHealHP = 80,
		flashHeal = true,
		flashHealHP = 55,
		holyHeal = true,
		holyHealHP = 35,
		healMinMana = 10,
		divineProtection = true,
		divineProtectionHP = 30,
		divineShield = true,
		divineShieldHP = 18,
		layOnHands = true,
		layOnHandsHP = 10,
		tankRighteousFury = true,
		tankConsecrationMinMana = 20,
		hsicon = false,
	},
}

-- Classic rank-one IDs used only as icon fallbacks. Holy
-- Strike is a Forever spell without a confirmed identifier: no ID 0 is
-- created or passed to the framework.
M.spells = {
	{ 1044, "Blessing of Freedom" },
	{ 19740, "Blessing of Might" },
	{ 1022, "Blessing of Protection" },
	{ 19742, "Blessing of Wisdom" },
	{ 19746, "Concentration Aura" },
	{ 26573, "Consecration" },
	{ 465, "Devotion Aura" },
	{ 498, "Divine Protection" },
	{ 642, "Divine Shield" },
	{ 879, "Exorcism" },
	{ 19750, "Flash of Light" },
	{ 853, "Hammer of Justice" },
	{ 635, "Holy Light" },
	{ nil, "Holy Strike" },
	{ 20271, "Judgement" },
	{ 633, "Lay on Hands" },
	{ 1152, "Purify" },
	{ 7328, "Redemption" },
	{ 7294, "Retribution Aura" },
	{ 25780, "Righteous Fury" },
	{ 20375, "Seal of Command" },
	{ 1311649, "Seal of Fury" },
	{ 20165, "Seal of Light" },
	{ 20154, "Seal of Righteousness" },
	{ 21082, "Seal of the Crusader" },
	{ 20166, "Seal of Wisdom" },
	{ 5502, "Sense Undead" },
	{ 2878, "Turn Undead" },
}

local HOLY_STRIKE_ICON = 133667
AL.IconOverrides = AL.IconOverrides or {}
AL.IconOverrides["Holy Strike"] = function()
	if AL.S().hsicon then return HOLY_STRIKE_ICON end
end

-- Classic class-spell levels used as safeguards. Talents
-- (Consecration, Seal of Command) and Holy Strike remain gated only by
-- Forever's spellbook, avoiding invented learning levels.
local MINLEVEL = {
	["Seal of Righteousness"] = 1,
	["Devotion Aura"] = 1,
	["Holy Light"] = 1,
	["Blessing of Might"] = 4,
	["Judgement"] = 4,
	["Seal of Fury"] = 10,
	["Divine Protection"] = 6,
	["Seal of the Crusader"] = 6,
	["Hammer of Justice"] = 8,
	["Purify"] = 8,
	["Lay on Hands"] = 10,
	["Blessing of Protection"] = 10,
	["Redemption"] = 12,
	["Blessing of Wisdom"] = 14,
	["Retribution Aura"] = 16,
	["Righteous Fury"] = 10,
	["Blessing of Freedom"] = 18,
	["Exorcism"] = 20,
	["Flash of Light"] = 20,
	["Concentration Aura"] = 22,
	["Seal of Light"] = 30,
	["Seal of Wisdom"] = 38,
	["Sense Undead"] = 22,
	["Turn Undead"] = 24,
}

local Ok, _, Known = AL.LevelGates(MINLEVEL)
M.minLevels = MINLEVEL

local SEALS = { "Seal of Fury", "Seal of Command", "Seal of Righteousness", "Seal of the Crusader", "Seal of Light", "Seal of Wisdom" }
local AURAS = { "Retribution Aura", "Devotion Aura", "Concentration Aura" }
local BLESSINGS = { "Blessing of Might", "Blessing of Wisdom" }


-- Protected health/mana control native display alpha; Lua never reads them.
local lastRotation
local visibilityCurves, curveFailures = {}, {}
local manaMaximumCache
local weaponSpeedCache
local nearbyAttackers = {}
local function SafeValue(value)
    return not (issecretvalue and issecretvalue(value))
end
local function Number(value)
    if not SafeValue(value) or type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then return nil end
    return value
end
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

-- Own the four seals and the two control cooldowns so this class update can
-- work with the existing Core, whose seal family predates Seal of Fury.
local sealNames = {}
for _, name in ipairs(SEALS) do sealNames[name] = true end
local furyCastIDs = { [1311649] = true, [1311656] = true, [20163] = true }
local sealState, sealCache, sealAurasBlocked
local sealDurations = {}
local baseSpellIDs = {}
for _, entry in ipairs(M.spells) do if entry[1] then baseSpellIDs[entry[2]] = entry[1] end end
local controlCooldowns = { ["Judgement"] = 10, ["Hammer of Justice"] = 60 }
local controlEnds, controlCastAt, controlDurations = {}, {}, {}
local pendingCasts, finishedCasts, lastSent = {}, {}, nil

local function TrackedNameFromID(id)
    id = Number(id)
    if not id then return nil end
    if furyCastIDs[id] or id == LearnedID("Seal of Fury") then return "Seal of Fury" end
    for name in pairs(sealNames) do
        if id == LearnedID(name) or id == baseSpellIDs[name] then return name end
    end
    for name in pairs(controlCooldowns) do
        if id == LearnedID(name) then return name end
    end
    local name = AL.castSpellNamesByID and AL.castSpellNamesByID[id]
        or SafeCall(AL.SpellName, id)
    if not SafeValue(name) or type(name) ~= "string" then return nil end
    name = (AL.englishNames and AL.englishNames[name]) or name
    if name == "Seal of Fury" then return nil end -- absorb/damage procs are not seal casts
    if name == "Judgement" and id ~= 20271 then return nil end
    if name == "Hammer of Justice" and id ~= 853 and id ~= 5588 and id ~= 5589 and id ~= 10308 then return nil end
    if sealNames[name] or controlCooldowns[name] then return name end
end

local function CastGUID(value)
    return SafeValue(value) and type(value) == "string" and value:find("^Cast%-") and value or nil
end

local function CastName(arg2, arg3, arg4)
    local id = Number(arg4) or Number(arg3)
    if id then return TrackedNameFromID(id), true end
    if SafeValue(arg2) and type(arg2) == "string" then
        local name = (AL.englishNames and AL.englishNames[arg2]) or arg2
        if sealNames[name] or controlCooldowns[name] then return name, true end
    end
    return nil, false
end

local function CooldownInfo(name)
    local info = SafeCall(C_Spell and C_Spell.GetSpellCooldown, LearnedID(name) or name)
    if SafeValue(info) and type(info) == "table" then return info end
end

local function CooldownEnd(info)
    if not info then return nil end
    local start, duration, rate = Number(info.startTime), Number(info.duration), Number(info.modRate)
    if SafeValue(info.modRate) and info.modRate == nil then rate = 1 end
    if start and start > 0 and duration and duration > 1.5 and rate and rate > 0 then
        return start + duration / rate, duration / rate
    end
end

local function ControlReady(name)
    local info = CooldownInfo(name)
    if info then
        local start, duration, rate = Number(info.startTime), Number(info.duration), Number(info.modRate)
        if SafeValue(info.modRate) and info.modRate == nil then rate = 1 end
        local ready
        if start and start >= 0 and duration and duration >= 0 and rate and rate > 0 then
            ready = start == 0 or duration <= 1.5 or start + duration / rate <= GetTime()
        elseif Bool(info.isActive) == false then ready = true
        elseif Bool(info.isActive) == true and Bool(info.isOnGCD) == false then ready = false end
        if ready ~= nil then
            if ready and controlCastAt[name] and GetTime() - controlCastAt[name] < 0.5
                and controlEnds[name] and controlEnds[name] > GetTime() then return false end
            return ready
        end
    end
    if controlEnds[name] then return controlEnds[name] <= GetTime() end
    return AL.IsReady(name)
end

local function SealAura()
    local now = GetTime()
    if sealCache and now - sealCache.at < 0.2 then return sealCache.name, sealCache.remaining, sealCache.complete end
    if sealAurasBlocked then return nil, nil, false end
    local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if type(reader) ~= "function" then return nil, nil, false end
    local complete = true
    for index = 1,40 do
        local ok, aura = pcall(reader, "player", index, "HELPFUL")
        if not ok or not SafeValue(aura) then sealAurasBlocked = true; return nil, nil, false end
        if aura == nil then
            sealCache = { at = now, complete = complete }
            return nil, nil, complete
        end
        if type(aura) ~= "table" then complete = false
        else
            local id, name = Number(aura.spellId), aura.name
            if SafeValue(name) and type(name) == "string" then name = (AL.englishNames and AL.englishNames[name]) or name
            elseif id then
                name = TrackedNameFromID(id)
                if not name then
                    local cached = AL.castSpellNamesByID and AL.castSpellNamesByID[id] or SafeCall(AL.SpellName, id)
                    if SafeValue(cached) and type(cached) == "string" then name = (AL.englishNames and AL.englishNames[cached]) or cached
                    else complete = false end
                end
            else name = nil; complete = false end
            if name == "Seal of Fury" and id and not furyCastIDs[id] and id ~= LearnedID(name) then name = nil end
            if SafeValue(name) and type(name) == "string" and sealNames[name] then
                local expires, duration = Number(aura.expirationTime), Number(aura.duration)
                local remaining = expires and expires > 0 and math.max(0, expires - now) or nil
                local fallback = duration and duration > 0 and duration <= 300 and duration or sealDurations[name] or 30
                sealDurations[name] = fallback
                if not sealState or sealState.name ~= name then
                    sealState = { name = name, expires = expires and expires > 0 and expires or now + fallback, duration = fallback }
                elseif expires and expires > 0 then sealState.expires = expires end
                sealState.duration = fallback
                if remaining == nil then remaining = math.max(0, sealState.expires - now) end
                sealCache = { at = now, name = name, remaining = remaining, complete = true }
                return name, remaining, true
            end
        end
    end
    return nil, nil, false
end

local function SealStatus()
    if sealState and sealState.castAt and GetTime() - sealState.castAt < 0.5 then
        return sealState.name, math.max(0, sealState.expires - GetTime())
    end
    local name, remaining, complete = SealAura()
    if complete then
        if not name then sealState = nil end
        return name, remaining
    end
    if sealState then
        if sealState.expires > GetTime() then return sealState.name, sealState.expires - GetTime() end
        return nil
    end
    for _, seal in ipairs(SEALS) do
        if Bool((SafeCall(AL.HasBuff, "player", seal))) == true then
            return seal, Number((SafeCall(AL.BuffRemaining, "player", seal)))
        end
    end
end

local spellTracker = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_AURA", "PLAYER_ENTERING_WORLD",
    "PLAYER_DEAD", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
    pcall(spellTracker.RegisterEvent, spellTracker, event)
end
spellTracker:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
    if AL.playerClass ~= "PALADIN" then return end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        sealState, sealCache, sealAurasBlocked = nil, nil, nil
        pendingCasts, finishedCasts, lastSent = {}, {}, nil
        for name, expires in pairs(controlEnds) do
            if expires <= GetTime() then controlEnds[name], controlCastAt[name] = nil, nil end
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then sealCache, sealAurasBlocked = nil, nil; return end
    if event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        controlDurations, sealDurations, sealCache = {}, {}, nil; return
    end
    if event == "UNIT_AURA" then
        if SafeValue(unit) and unit == "player" then
            sealCache = nil
            if not sealState or not sealState.castAt or GetTime() - sealState.castAt >= 0.5 then SealAura() end
        end
        return
    end
    if not SafeValue(unit) or unit ~= "player" then return end
    for guid, entry in pairs(pendingCasts) do if GetTime() - entry.at > 30 then pendingCasts[guid] = nil end end
    for guid, at in pairs(finishedCasts) do if GetTime() - at > 90 then finishedCasts[guid] = nil end end
    local guid = CastGUID(event == "UNIT_SPELLCAST_SENT" and arg3 or arg2)
    local name, readable = CastName(arg2, arg3, arg4)
    if event == "UNIT_SPELLCAST_SENT" then
        local suggestion = AL.lastSuggestion
        if not readable and SafeValue(suggestion) and type(suggestion) == "string"
            and (sealNames[suggestion] or controlCooldowns[suggestion])
            and M.CanTrackSuggestedSpell and M.CanTrackSuggestedSpell(suggestion) then name = suggestion end
        lastSent = { at = GetTime(), name = name, guid = guid }
        if guid then pendingCasts[guid] = lastSent end
        return
    end
    local sent = guid and pendingCasts[guid] or (not guid and lastSent)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
        if sent and not sent.done then sent.failed = true end
        if guid and not (sent and sent.done) then finishedCasts[guid] = GetTime() end
        return
    end
    if guid and finishedCasts[guid] or sent and (sent.failed or sent.done) then return end
    if not readable and sent and GetTime() - sent.at <= 5 then name = sent.name end
    if not name then return end
    if sent then sent.done = true end
    if guid then finishedCasts[guid] = GetTime() end
    if sealNames[name] then
        local duration = sealDurations[name] or 30
        local coreRemaining = Number((SafeCall(AL.BuffRemaining, "player", name)))
        if coreRemaining and coreRemaining > 0 and coreRemaining <= 300 then duration = coreRemaining end
        sealState = { name = name, castAt = GetTime(), expires = GetTime() + duration, duration = duration }
        sealCache = nil
    elseif controlCooldowns[name] then
        local expires, duration = CooldownEnd(CooldownInfo(name))
        if duration then controlDurations[name] = duration end
        controlCastAt[name] = GetTime()
        controlEnds[name] = expires or GetTime() + (controlDurations[name] or controlCooldowns[name])
    end
end)

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
    if failure and failure.reader == reader then return false end
    return C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function"
        and type(CreateColor) == "function" and type(reader) == "function"
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

local function SpellCost(name, kind, fallback)
    local ok, result = pcall(function()
        local costs = SafeCall(C_Spell and C_Spell.GetSpellPowerCost, LearnedID(name) or name)
        if not SafeValue(costs) or type(costs) ~= "table" then return end
        for _, entry in pairs(costs) do
            if SafeValue(entry) and type(entry) == "table" and Number(entry.type) == kind then
                local cost = Number(entry.cost)
                if cost and cost >= 0 then return cost end
            end
        end
    end)
    return ok and result or fallback
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

local function ActiveFrom(list)
	for _, name in ipairs(list) do
		if AL.HasBuff("player", name) then return name end
	end
	return nil
end

local function ActiveSeal() return (SealStatus()) end
local function ActiveAura() return ActiveFrom(AURAS) end
local function ActiveBlessing() return ActiveFrom(BLESSINGS) end

local function Role(s)
	return SettingChoice(s, "paladinRole", { DPS = true, TANK = true }, "DPS")
end

local function PreferredBlessing(s, role)
	local mode = SettingChoice(s, "blessingMode", {
		AUTO = true, MIGHT = true, WISDOM = true,
	}, "AUTO")
	if mode == "MIGHT" and Ok("Blessing of Might") then return "Blessing of Might" end
	if mode == "WISDOM" and Ok("Blessing of Wisdom") then return "Blessing of Wisdom" end
	if role == "TANK" and Ok("Blessing of Wisdom") then return "Blessing of Wisdom" end
	if Ok("Blessing of Might") then return "Blessing of Might" end
	return Ok("Blessing of Wisdom") and "Blessing of Wisdom" or nil
end

local function PreferredAura(s, role)
	local mode = SettingChoice(s, "auraMode", {
		AUTO = true, RETRIBUTION = true, DEVOTION = true, CONCENTRATION = true,
	}, "AUTO")
	if mode == "RETRIBUTION" and Ok("Retribution Aura") then return "Retribution Aura" end
	if mode == "DEVOTION" and Ok("Devotion Aura") then return "Devotion Aura" end
	if mode == "CONCENTRATION" and Ok("Concentration Aura") then return "Concentration Aura" end
	if role == "TANK" and Ok("Devotion Aura") then return "Devotion Aura" end
	if Ok("Retribution Aura") then return "Retribution Aura" end
	return Ok("Devotion Aura") and "Devotion Aura" or nil
end

local function WeaponSpeed()
	local speed = Number((SafeCall(UnitAttackSpeed, "player")))
	if speed and speed > 0 then weaponSpeedCache = speed end
	return weaponSpeedCache
end

local function PreferredSeal(s, role)
	local mode = SettingChoice(s, "seal", {
		AUTO = true, COMMAND = true, RIGHTEOUSNESS = true, FURY = true, LIGHT = true, WISDOM = true,
	}, "AUTO")
	if mode == "FURY" and Ok("Seal of Fury") then return "Seal of Fury" end
	if mode == "COMMAND" and Ok("Seal of Command") then return "Seal of Command" end
	if mode == "RIGHTEOUSNESS" and Ok("Seal of Righteousness") then return "Seal of Righteousness" end
	if mode == "LIGHT" and Ok("Seal of Light") then return "Seal of Light" end
	if mode == "WISDOM" and Ok("Seal of Wisdom") then return "Seal of Wisdom" end
	if role == "TANK" and Ok("Seal of Fury") then return "Seal of Fury" end
	if role == "TANK" and Ok("Seal of Righteousness") then return "Seal of Righteousness" end
	local speed = WeaponSpeed()
	if speed and speed >= 3.8 and Ok("Seal of Command") then return "Seal of Command" end
	if Ok("Seal of Righteousness") then return "Seal of Righteousness" end
	return Ok("Seal of Command") and "Seal of Command" or nil
end

local function ManaMaximum()
    local value = Number((SafeCall(UnitPowerMax, "player", 0)))
    if value and value > 0 then manaMaximumCache = value end
    return manaMaximumCache
end

local function ManaAmount()
    local value = Number((SafeCall(UnitPower, "player", 0)))
    if value and value >= 0 then return value end
    local percentage = Percent((SafeCall(AL.ManaPercent)))
    local maximum = ManaMaximum()
    if percentage and maximum then return percentage * maximum / 100 end
end

local function ManaGate(value, threshold, below)
    if value ~= nil and math.abs(value - threshold) < 1e-7 then value = threshold end
    if value ~= nil then return below and value <= threshold or not below and value >= threshold end
    if not below and threshold <= 0 then return true end
    if not CurveAvailable("power", "player", 0) then return false end
    local cut = threshold / 100
    if below then cut = NextFloat32(cut) end
    return { axis = "mana", kind = "power", unit = "player", powerType = 0, cut = cut, below = below }
end

local function Affordable(name, usable, shortage)
    if shortage == true then return false end
    local cost = SpellCost(name, 0)
    if cost == nil then return usable ~= false end
    if cost <= 0 then return true end
    local amount = ManaAmount()
    if amount ~= nil then return amount >= cost end
    local maximum = ManaMaximum()
    if maximum and CurveAvailable("power", "player", 0) then
        if cost > maximum then return false end
        return { axis = "mana", kind = "power", unit = "player", powerType = 0, cut = cost / maximum, below = false }
    end
    -- If no resource curve is supported, a readable usability answer still
    -- permits ordinary spells; a user's percentage limit remains mandatory.
    return usable ~= false
end

local function ShieldEquipped()
	local itemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
	if not GetInventoryItemID or not itemInfoInstant then return nil end
	local okID, itemID = pcall(GetInventoryItemID, "player", 17)
	if not okID or not SafeValue(itemID) then return nil end
	if not itemID then return false end
	local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(itemInfoInstant, itemID)
	if not ok then return nil end
	if SafeValue(equipLoc) and equipLoc == "INVTYPE_SHIELD" then return true end
	if Number(classID) and Number(subclassID) then
		return classID == 4 and subclassID == 6
	end
	return nil
end

local function Ready(name)
    if controlCooldowns[name] then return Ok(name) and ControlReady(name) end
    return Ok(name) and AL.IsReady(name)
end

local function Offer(name, reason, gates, preparation)
    if not Ready(name) then return false end
    local usable, shortage = SpellUsability(name)
    if usable == false or shortage == true then return false end
    if not sealNames[name] then
        local inRange
        if controlCooldowns[name] then inRange = Bool((SafeCall(C_Spell and C_Spell.IsSpellInRange, LearnedID(name) or name, "target"))) end
        if inRange == nil then inRange = Bool((SafeCall(AL.InRange, name))) end
        if inRange == false then return false end
    end
    local conditions = {}
    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
    local affordable = Affordable(name, usable, shortage)
    -- A readable positive usability answer proves enough mana for a buff.
    -- Keep that public preparation decision identifiable when mana is secret.
    if preparation and ManaAmount() == nil and usable == true and shortage == false then affordable = true end
    conditions[#conditions + 1] = affordable
    return AddAction(name, reason, conditions)
end

local function PlayerIsCastingOrChanneling()
    for _, reader in pairs({ UnitCastingInfo, UnitChannelInfo }) do
        local value = SafeCall(reader, "player")
        if not SafeValue(value) or value ~= nil then return true end
    end
    local name = SafeCall(AL.CastingSpell)
    return SafeValue(name) and type(name) == "string"
end

local function UnitWithin(unit, yards)
    local squared, checked = SafeCall(UnitDistanceSquared, unit)
    squared = Number(squared)
    if squared and squared >= 0 and Bool(checked) ~= false then return squared <= yards * yards end
    local object = A and SafeCall(A.Unit, unit)
    if SafeValue(object) and (type(object) == "table" or type(object) == "userdata") then
        local range = Number((SafeCall(object.GetRange, object)))
        if range and range >= 0 then return range <= yards end
    end
    if yards >= 10 then
        local near = Bool((SafeCall(CheckInteractDistance, unit, 3)))
        if near ~= nil then return near end
    end
    -- A positive Holy Strike range is a conservative melee lower bound for
    -- the eight-yard ground effect; a negative melee range does not prove far.
    if Known("Holy Strike") then
        local range
        if unit == "target" then range = SafeCall(AL.InRange, "Holy Strike")
        else range = SafeCall(C_Spell and C_Spell.IsSpellInRange, LearnedID("Holy Strike") or "Holy Strike", unit) end
        if SafeValue(range) and (range == true or range == 1) then return true end
    end
end

local function InMelee()
    if Known("Holy Strike") then return Bool((SafeCall(AL.InRange, "Holy Strike"))) == true end
    return UnitWithin("target", 5) == true
end

local function UndeadOrDemon()
    local name, id = SafeCall(UnitCreatureType, "target")
    id = Number(id)
    -- Client creature-type IDs do not depend on the selected UI language.
    if id then return id == 3 or id == 6 end
    return SafeValue(name) and (name == "Undead" or name == "Demon")
end

local function EnemyCountMelee(limit)
    local framework
    local function Accept(value)
        value = Number(value)
        if value and value >= 0 and value <= 40 and value == math.floor(value) then framework = math.max(framework or 0, value) end
    end
    Accept((SafeCall(AL.EnemyCount, 8)))
    if A and A.MultiUnits then
        Accept((SafeCall(A.MultiUnits.GetByRangeInCombat, A.MultiUnits, 8, limit or 5)))
        Accept((SafeCall(A.MultiUnits.GetActiveEnemies, A.MultiUnits, 8)))
    end
    local seen, count = {}, 0
    local function Count(unit)
        if not SafeValue(unit) or type(unit) ~= "string" then return end
        if Bool((SafeCall(UnitExists, unit))) ~= true or Bool((SafeCall(UnitCanAttack, "player", unit))) ~= true
            or Bool((SafeCall(UnitIsDeadOrGhost, unit))) ~= false
            or Bool((SafeCall(UnitAffectingCombat, unit))) ~= true then return end
        local guid = SafeCall(UnitGUID, unit)
        if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] then return end
        if UnitWithin(unit, 8) ~= true then return end
        seen[guid], count = true, count + 1
    end
    Count("target")
    local plates = SafeCall(C_NamePlate and C_NamePlate.GetNamePlates)
    if SafeValue(plates) and type(plates) == "table" then
        for _, plate in pairs(plates) do
            if SafeValue(plate) and type(plate) == "table" then
                Count(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
            end
        end
    else
        for index = 1, 40 do Count("nameplate" .. index) end
    end
    for guid, expires in pairs(nearbyAttackers) do
        if expires <= GetTime() then nearbyAttackers[guid] = nil
        elseif not seen[guid] then seen[guid], count = true, count + 1 end
    end
    if count > 0 then framework = math.max(framework or 0, count) end
    return framework
end

local tracker = CreateFrame("Frame")
for _, event in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ENTERING_WORLD", "UNIT_INVENTORY_CHANGED" }) do
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" or type(CombatLogGetCurrentEventInfo) == "function" then pcall(tracker.RegisterEvent, tracker, event) end
end
tracker:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_INVENTORY_CHANGED" then
        if SafeValue(unit) and unit == "player" then weaponSpeedCache, lastRotation, AL.rotationSecretVisual = nil, nil, nil end
        return
    end
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then
        nearbyAttackers, lastRotation, AL.rotationSecretVisual = {}, nil, nil
        curveFailures, manaMaximumCache = {}, nil
        if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then weaponSpeedCache = nil end
        return
    end
    if type(CombatLogGetCurrentEventInfo) ~= "function" then return end
    local ok, _, sub, _, srcGUID, _, _, _, destGUID = pcall(CombatLogGetCurrentEventInfo)
    if not ok or not SafeValue(sub) or not SafeValue(srcGUID) or not SafeValue(destGUID) then return end
    if sub == "UNIT_DIED" then
        if type(destGUID) == "string" then nearbyAttackers[destGUID] = nil end
        return
    end
    local playerGUID = SafeCall(UnitGUID, "player")
    if SafeValue(playerGUID) and type(playerGUID) == "string" and destGUID == playerGUID
        and type(srcGUID) == "string" and srcGUID ~= playerGUID
        and (sub == "SWING_DAMAGE" or sub == "SWING_MISSED") then
        nearbyAttackers[srcGUID] = GetTime() + 4
    end
end)

local function ApplyPreparation(s, role, sealNeeded, inCombat)
    if not s.buffs then return end
    local seal = PreferredSeal(s, role)
    if sealNeeded and seal then
        local active, remaining = SealStatus()
        -- Three seconds leaves room to refresh before expiry. Keep the short
        -- precombat rule; idle preparation never renews an otherwise active seal.
        local refresh = inCombat and remaining ~= nil and remaining <= 3
        if active ~= seal or refresh then
            Offer(seal, refresh and "refresh seal" or "seal before judgement", nil, true)
        end
    end
    local blessing = PreferredBlessing(s, role)
    if blessing and ActiveBlessing() ~= blessing then Offer(blessing, "blessing", nil, true) end
    local aura = PreferredAura(s, role)
    if aura and ActiveAura() ~= aura then Offer(aura, "aura", nil, true) end
    if role == "TANK" and s.tankRighteousFury and not AL.HasBuff("player", "Righteous Fury") then
        Offer("Righteous Fury", "tank threat", nil, true)
    end
end

local function Emergency(s, role, hp, mana)
    if not s.emergency then return end
    if s.layOnHands then Offer("Lay on Hands", "critical emergency", {
        HealthGate("player", hp, SettingNumber(s, "layOnHandsHP", 10, 1, 50), true) }) end
    if role == "DPS" and s.divineShield and not AL.HasBuff("player", "Divine Shield") then
        Offer("Divine Shield", "immunity", {
            HealthGate("player", hp, SettingNumber(s, "divineShieldHP", 18, 5, 60), true) })
    end
    if s.divineProtection and not AL.HasBuff("player", "Divine Protection") then
        Offer("Divine Protection", "emergency", {
            HealthGate("player", hp, SettingNumber(s, "divineProtectionHP", 30, 5, 80), true) })
    end
    local manaGate = ManaGate(mana, SettingNumber(s, "healMinMana", 10, 0, 100), false)
    if s.holyHeal then Offer("Holy Light", "large heal", {
        HealthGate("player", hp, SettingNumber(s, "holyHealHP", 35, 5, 90), true), manaGate }) end
    if s.flashHeal then Offer("Flash of Light", "fast heal", {
        HealthGate("player", hp, SettingNumber(s, "flashHealHP", 55, 5, 95), true), manaGate }) end
end

local function Judgement(s, mana, targetHP, reason)
    if s.judgement and ActiveSeal() then
        Offer("Judgement", reason, {
            ManaGate(mana, SettingNumber(s, "judgementMinMana", 15, 0, 100), false),
            HealthGate("target", targetHP, SettingNumber(s, "judgementMinTargetHP", 20, 0, 100), false) })
    end
end

local function Consecration(s, role, mana)
    local minimum = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
    local enemies = s.aoe and s.consecration and EnemyCountMelee(minimum)
    if enemies and enemies >= minimum then
        local key = role == "TANK" and "tankConsecrationMinMana" or "consecrationMinMana"
        Offer("Consecration", tostring(enemies) .. " engaged enemies", {
            ManaGate(mana, SettingNumber(s, key, role == "TANK" and 20 or 35, 0, 100), false) })
    end
end

local function OffensivePriority(s, role, mana, targetHP)
    local targetCasting = Bool((SafeCall(AL.TargetCasting))) == true
    if s.hammer and not targetCasting then
        for _, reader in pairs({ UnitCastingInfo, UnitChannelInfo }) do
            local name, _, texture, start = SafeCall(reader, "target")
            if SafeValue(name) and type(name) == "string" and name ~= ""
                or Number(texture) ~= nil or Number(start) ~= nil
                or SafeValue(texture) and type(texture) == "string" and texture ~= "" then targetCasting = true; break end
        end
        if not targetCasting then
            for _, reader in pairs({ UnitCastingDuration, UnitChannelDuration }) do
                local duration = SafeCall(reader, "target")
                if SafeValue(duration) and (type(duration) == "table" or type(duration) == "userdata") then targetCasting = true; break end
            end
        end
    end
    if s.hammer and targetCasting then Offer("Hammer of Justice", "stop cast") end
    ApplyPreparation(s, role, true, true)
    Judgement(s, mana, targetHP, InMelee() and "on cooldown" or "ranged opener")
    Consecration(s, role, mana)
    if AL.burst then
        local gate = HealthGate("target", targetHP, SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false)
        Offer("Blood Fury", "burst", { gate })
        Offer("Berserking", "burst", { gate })
    end
    if s.holystrike then Offer("Holy Strike", role == "TANK" and "tank strike" or "on cooldown", {
        ManaGate(mana, SettingNumber(s, "holyStrikeMinMana", 10, 0, 100), false) }) end
    if s.exorcism and UndeadOrDemon() then Offer("Exorcism", "undead / demon", {
        ManaGate(mana, SettingNumber(s, "exorcismMinMana", 25, 0, 100), false),
        HealthGate("target", targetHP, SettingNumber(s, "exorcismMinTargetHP", 25, 0, 100), false) }) end
    AddAction(AL.Ok("Attack") and "Attack" or nil, "melee / conserve mana")
end

function M.NextSpell(s, inCombat, hostile)
    if not inCombat then curveFailures, manaMaximumCache = {}, nil end
    lastRotation = { at = GetTime(), actions = {} }
    local role = Role(s)
    local mana = Percent((SafeCall(AL.ManaPercent)))
    local hp = HealthPercent("player")
    local targetHP = hostile and HealthPercent("target") or nil
    if PlayerIsCastingOrChanneling() then AddAction(nil, "Casting")
    elseif not inCombat then
        if s.oocHeal then Offer("Holy Light", "out of combat heal", {
            HealthGate("player", hp, SettingNumber(s, "oocHealHP", 80, 5, 100), true, true),
            ManaGate(mana, SettingNumber(s, "healMinMana", 10, 0, 100), false) }) end
        local prePull = hostile and Ready("Judgement") and UnitWithin("target", 10) == true
        ApplyPreparation(s, role, prePull)
        if prePull then Judgement(s, mana, targetHP, "pull") end
        if hostile then AddAction(AL.Ok("Attack") and "Attack" or nil, role == "TANK" and "tank opener" or "opener") end
    else
        Emergency(s, role, hp, mana)
        if hostile then OffensivePriority(s, role, mana, targetHP)
        else
            ApplyPreparation(s, role, true, true)
            Consecration(s, role, mana)
        end
    end
    AddAction(nil, inCombat and not hostile and "No target" or "Ready")
    local base = lastRotation.actions[#lastRotation.actions]
    lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
    return base.spell, base.reason
end

function M.OnTargetChanged()
    lastRotation, AL.rotationSecretVisual = nil, nil
end

function M.CanTrackSuggestedSpell(name)
    if not lastRotation or GetTime() - lastRotation.at > 0.5 or lastRotation.visualCandidate then return false end
    local visual = AL.rotationSecretVisual
    if visual and GetTime() - visual.at <= 0.5 then return false end
    if name ~= lastRotation.baseSpell or not Ok(name) then return false end
    for _, entry in ipairs(M.spells) do if entry[2] == name then return true end end
    return name == "Berserking" or name == "Blood Fury"
end

function M.GetUIState()
    local profile, knownCount = AL.S(), 0
    for _, entry in ipairs(M.spells) do if Known(entry[2]) then knownCount = knownCount + 1 end end
    return { role = Role(profile), level = Number((SafeCall(UnitLevel, "player"))),
        mana = Percent((SafeCall(AL.ManaPercent))), knownCount = knownCount,
        seal = ActiveSeal(), aura = ActiveAura(), blessing = ActiveBlessing(),
        righteousFury = AL.HasBuff("player", "Righteous Fury"),
        enemyCount = EnemyCountMelee(SettingNumber(profile, "aoeMinEnemies", 2, 2, 5)), hasShield = ShieldEquipped() }
end

if AL.selfCastSpells then
    for _, list in ipairs({ SEALS, AURAS, BLESSINGS, { "Righteous Fury", "Consecration", "Holy Light", "Flash of Light",
        "Divine Protection", "Divine Shield", "Lay on Hands", "Berserking", "Blood Fury" } }) do
        for _, name in ipairs(list) do AL.selfCastSpells[name] = true end
    end
end
local function IntervalCurve(low, high)
	local key = tostring(low) .. ":" .. tostring(high)
	if visibilityCurves[key] then return visibilityCurves[key] end
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	curve:AddPoint(0, CreateColor(1, 1, 1, low == 0 and 1 or 0))
	if low > 0 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
	if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
	if low ~= 1 and high ~= 1 then curve:AddPoint(1, CreateColor(1, 1, 1, high > 1 and 1 or 0)) end
	visibilityCurves[key] = curve
	return curve
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
			local success, value = pcall(function()
				local curve = IntervalCurve(mask.low, mask.high)
				local color
				if mask.kind == "power" then color = UnitPowerPercent(mask.unit, mask.powerType, false, curve)
				else color = UnitHealthPercent(mask.unit, false, curve) end
				local _, _, _, alpha = color:GetRGBA()
				return alpha
			end)
			if not success then
				curveFailures[mask.kind .. ":" .. mask.unit .. ":" .. tostring(mask.powerType or "")] = {
					reader = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent }
				error("Paladin resource curve unavailable")
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
		if mask then node:SetAlpha(values[mask.key]) else node:SetAlpha(1) end
	end
end



AL.RegisterRotation("PALADIN", M)
-- END ORIGINAL LEVELING IMPLEMENTATION
    end)(ADDON, RotationScope(true))

    ;(function(...)
-- BEGIN OPTIONAL TALENT BUILD IMPLEMENTATION
local ADDON, AL = ...

-- WoW Forever Paladin Retribution / Protection leveling 1-60
-- ActionLITE Paladin v0.14.4 - Protection (8/33/10), Retribution and Shockadin
-- Reference: Forever 1.60.1.70338 / MythicSim b1137248e6b4.
-- Status: LIKELY until costs, ranks and talents are directly validated.
-- Protected values are never treated as zero.

local A = _G.Action

local M = {
	defaults = {
        leveling = true,
		paladinRole = "DPS",
		protection = false,
		shockadin = false,
		retribution = false,
		hammerOfTheRighteous = true,
		hammerOfTheRighteousMinMana = 10,
		holyWrath = true,
		holyWrathMinMana = 35,
		divineFavor = true,
		holyShock = true,
		holyShockMinMana = 10,
		hammerOfWrath = true,
		hammerOfWrathMinMana = 10,
		buffs = true,
		blessingMode = "AUTO",
		auraMode = "AUTO",
		seal = "AUTO",
		judgement = true,
		holystrike = true,
		exorcism = true,
		hammer = true,
		emergency = true,
		drink = true,
		drinkMana = 30,
		judgementMinMana = 15,
		judgementMinTargetHP = 20,
		holyStrikeMinMana = 10,
		exorcismMinMana = 25,
		exorcismMinTargetHP = 25,
		aoe = false,
		consecration = true,
		aoeMinEnemies = 2,
		consecrationMinMana = 35,
		burstMinTargetHP = 40,
		oocHeal = true,
		oocHealHP = 80,
		flashHeal = true,
		flashHealHP = 55,
		holyHeal = true,
		holyHealHP = 35,
		healMinMana = 10,
		divineProtection = true,
		divineProtectionHP = 30,
		divineShield = true,
		divineShieldHP = 18,
		layOnHands = true,
		layOnHandsHP = 10,
		tankRighteousFury = true,
		tankConsecrationMinMana = 20,
		holyShield = true,
		holyShieldMinMana = 10,
		swiftJudgement = true,
		templarsBulwark = true,
		templarsBulwarkHP = 35,
		hsicon = false,
		healingAura = "CONCENTRATION",
		healingOathOfLight = true,
	},
}

-- Rank-one IDs are icon/name fallbacks. The learned spellbook rank is used
-- for costs, range and cooldown reads.
-- Exactly one rotation stays selected. Leveling is the default and the
-- fallback when a selected specialization is switched off or saved flags
-- conflict. A valid saved specialization takes priority during migration.
M.buildKeys = { "leveling", "protection", "retribution", "shockadin" }
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
    local owner = s.paladinRoleBuild
    if issecretvalue and issecretvalue(owner) then owner = nil end
    local function IsTank(value)
        return not (issecretvalue and issecretvalue(value)) and value == "TANK"
    end
    if selected == "leveling" then
        if owner and owner ~= "leveling" then
            s.paladinRole = IsTank(s.levelingPaladinRole) and "TANK" or "DPS"
        else
            s.levelingPaladinRole = IsTank(s.paladinRole) and "TANK" or "DPS"
        end
    else
        if owner == "leveling" then
            s.levelingPaladinRole = IsTank(s.paladinRole) and "TANK" or "DPS"
        end
        s.paladinRole = selected == "protection" and "TANK" or "DPS"
    end
    s.paladinRoleBuild = selected
    s.paladinPreviousDPS = nil
    return selected
end
function M.SetBuild(key, enabled, s)
    if (issecretvalue and issecretvalue(enabled)) or type(enabled) ~= "boolean" then return end
    local valid = false
    for _, candidate in ipairs(M.buildKeys) do if candidate == key then valid = true; break end end
    if not valid then return end
    s = s or AL.Profile("PALADIN")
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
	{ 1044, "Blessing of Freedom" },
	{ 20217, "Blessing of Kings" },
	{ 19740, "Blessing of Might" },
	{ 1022, "Blessing of Protection" },
	{ 19742, "Blessing of Wisdom" },
	{ 25898, "Greater Blessing of Kings" },
	{ 19746, "Concentration Aura" },
	{ 26573, "Consecration" },
	{ 465, "Devotion Aura" },
	{ 498, "Divine Protection" },
	{ 642, "Divine Shield" },
	{ 879, "Exorcism" },
	{ 19750, "Flash of Light" },
	{ 853, "Hammer of Justice" },
	{ 635, "Holy Light" },
	{ 679, "Holy Strike" },
	{ 1311606, "Holy Shock" },
	{ 24275, "Hammer of Wrath" },
	{ 4987, "Cleanse" },
	{ 20216, "Divine Favor" },
	{ 1310911, "Light's Vigil" },
	{ 0, "Oath of Light" },
	{ 407632, "Hammer of the Righteous" },
	{ 2812, "Holy Wrath" },
	{ 20925, "Holy Shield" },
	{ 1310994, "Swift Judgement" },
	{ 0, "Salvation" },
	{ 0, "Mass Salvation" },
	{ 0, "Revoke" },
	{ 1311015, "Templar's Bulwark" },
	{ 20271, "Judgement" },
	{ 633, "Lay on Hands" },
	{ 1152, "Purify" },
	{ 7328, "Redemption" },
	{ 7294, "Retribution Aura" },
	{ 25780, "Righteous Fury" },
	{ 20375, "Seal of Command" },
	{ 1311649, "Seal of Fury" },
	{ 20165, "Seal of Light" },
	{ 20154, "Seal of Righteousness" },
	{ 21082, "Seal of the Crusader" },
	{ 20166, "Seal of Wisdom" },
	{ 5502, "Sense Undead" },
	{ 2878, "Turn Undead" },
}

local HOLY_STRIKE_ICON = 133667
AL.IconOverrides = AL.IconOverrides or {}
AL.IconOverrides["Holy Strike"] = function()
	if AL.S().hsicon then return HOLY_STRIKE_ICON end
end

-- Classic class-spell levels used as safeguards. Talents
-- (Seal of Command) remain gated by Forever's spellbook. Holy Strike and
-- higher-level attacks use levels from the current client.
local MINLEVEL = {
	["Seal of Righteousness"] = 1,
	["Devotion Aura"] = 1,
	["Holy Light"] = 1,
	["Blessing of Might"] = 4,
	["Blessing of Kings"] = 20,
	["Judgement"] = 4,
	["Holy Strike"] = 6,
	["Seal of Fury"] = 10,
	["Divine Protection"] = 6,
	["Seal of the Crusader"] = 6,
	["Hammer of Justice"] = 8,
	["Purify"] = 8,
	["Lay on Hands"] = 10,
	["Blessing of Protection"] = 10,
	["Redemption"] = 12,
	["Blessing of Wisdom"] = 14,
	["Retribution Aura"] = 16,
	["Righteous Fury"] = 10,
	["Blessing of Freedom"] = 18,
	["Exorcism"] = 20,
	["Flash of Light"] = 20,
	["Concentration Aura"] = 22,
	["Sense Undead"] = 22,
	["Turn Undead"] = 24,
	["Holy Shock"] = 30,
	["Seal of Light"] = 30,
	["Seal of Wisdom"] = 38,
	["Greater Blessing of Kings"] = 60,
	["Holy Shield"] = 40,
	["Swift Judgement"] = 25,
	["Templar's Bulwark"] = 30,
	["Hammer of the Righteous"] = 40,
	["Holy Wrath"] = 50,
	["Hammer of Wrath"] = 44,
	["Cleanse"] = 42,
}

local Ok, _, Known = AL.LevelGates(MINLEVEL)
M.minLevels = MINLEVEL

local SEALS = { "Seal of Fury", "Seal of Command", "Seal of Righteousness", "Seal of the Crusader", "Seal of Light", "Seal of Wisdom" }
local AURAS = { "Retribution Aura", "Devotion Aura", "Concentration Aura" }
local BLESSINGS = { "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Greater Blessing of Kings" }


-- Protected health/mana control native display alpha; Lua never reads them.
local lastRotation
local visibilityCurves, curveFailures = {}, {}
local manaMaximumCache
local weaponSpeedCache
local nearbyAttackers = {}
local function SafeValue(value)
    return not (issecretvalue and issecretvalue(value))
end
local function Number(value)
    if not SafeValue(value) or type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then return nil end
    return value
end
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

-- Own seals and the build cooldowns so this class update can
-- work with the existing Core, whose seal family predates Seal of Fury.
local sealNames = {}
for _, name in ipairs(SEALS) do sealNames[name] = true end
local furyCastIDs = { [1311649] = true, [1311656] = true, [20163] = true,
    [20419] = true, [20421] = true, [20422] = true, [20423] = true }
local sealState, sealCache, sealAurasBlocked
local sealDurations = {}
local holyStrikeCastIDs = { [679]=true, [678]=true, [1866]=true, [680]=true,
    [2495]=true, [5569]=true, [10332]=true, [10333]=true }
local baseSpellIDs = {}
for _, entry in ipairs(M.spells) do if entry[1] then baseSpellIDs[entry[2]] = entry[1] end end
local controlCooldowns = { ["Judgement"] = 10, ["Hammer of Justice"] = 60,
    ["Holy Shock"] = 10, ["Hammer of Wrath"] = 6, ["Consecration"] = 8,
    ["Divine Favor"] = 120, ["Holy Strike"] = 10,
    ["Hammer of the Righteous"] = 6, ["Holy Wrath"] = 60,
    ["Holy Shield"] = 10, ["Swift Judgement"] = 60,
    ["Templar's Bulwark"] = 300, ["Righteous Fury"] = 0 }
local tankBuffDurations = { ["Holy Shield"] = 10, ["Templar's Bulwark"] = 8,
    ["Righteous Fury"] = 1800, ["Forbearance"] = 60 }
local tankBuffIDs = { [20925] = "Holy Shield", [20927] = "Holy Shield", [20928] = "Holy Shield",
    [1311015] = "Templar's Bulwark", [25780] = "Righteous Fury",
    [25771] = "Forbearance" }
local tankBuffState, tankAuraCache, tankAurasBlocked = {}, nil, nil
local forbearanceConsumers = { ["Divine Protection"] = true, ["Divine Shield"] = true, ["Blessing of Protection"] = true }
local forbearanceCastIDs = { [498] = "Divine Protection", [5573] = "Divine Protection",
    [642] = "Divine Shield", [1020] = "Divine Shield",
    [1022] = "Blessing of Protection", [5599] = "Blessing of Protection", [10278] = "Blessing of Protection" }
local holyShockCastIDs = { [1311606]=true, [20473]=true, [20929]=true, [20930]=true }
local wrathCastIDs = { [24275]=true, [24274]=true, [24239]=true }
local favorConsumers = { ["Holy Shock"] = true, ["Holy Light"] = true, ["Flash of Light"] = true }
local favorHealIDs = {
    [635]="Holy Light", [639]="Holy Light", [647]="Holy Light", [1026]="Holy Light",
    [1042]="Holy Light", [3472]="Holy Light", [10328]="Holy Light", [10329]="Holy Light", [25292]="Holy Light",
    [19750]="Flash of Light", [19939]="Flash of Light", [19940]="Flash of Light",
    [19941]="Flash of Light", [19942]="Flash of Light", [19943]="Flash of Light",
}
local favorActive, favorChangedAt, favorAuraAt, favorAurasBlocked
local controlEnds, controlCastAt, controlDurations = {}, {}, {}
local controlRetryAfter = {}
local pendingCasts, finishedCasts, lastSent = {}, {}, nil

local function TrackedNameFromID(id)
    id = Number(id)
    if not id then return nil end
    if forbearanceCastIDs[id] then return forbearanceCastIDs[id] end
    for name in pairs(forbearanceConsumers) do if id == LearnedID(name) then return name end end
    if furyCastIDs[id] or id == LearnedID("Seal of Fury") then return "Seal of Fury" end
    for name in pairs(sealNames) do
        if id == LearnedID(name) or id == baseSpellIDs[name] then return name end
    end
    for name in pairs(controlCooldowns) do
        if id == LearnedID(name) or id == baseSpellIDs[name] then return name end
    end
    if holyShockCastIDs[id] then return "Holy Shock" end
    if wrathCastIDs[id] then return "Hammer of Wrath" end
    if holyStrikeCastIDs[id] then return "Holy Strike" end
    if id == 20925 or id == 20927 or id == 20928 then return "Holy Shield" end
    if id == 10318 then return "Holy Wrath" end
    if favorHealIDs[id] then return favorHealIDs[id] end
    for name in pairs(favorConsumers) do if id == LearnedID(name) then return name end end
    local name = AL.castSpellNamesByID and AL.castSpellNamesByID[id]
        or SafeCall(AL.SpellName, id)
    if not SafeValue(name) or type(name) ~= "string" then return nil end
    name = (AL.englishNames and AL.englishNames[name]) or name
    if name == "Seal of Fury" then return nil end -- absorb/damage procs are not seal casts
    if name == "Judgement" and id ~= 20271 then return nil end
    if name == "Hammer of Justice" and id ~= 853 and id ~= 5588 and id ~= 5589 and id ~= 10308 then return nil end
    if name == "Holy Shock" and not holyShockCastIDs[id] then return nil end
    if name == "Hammer of Wrath" and not wrathCastIDs[id] then return nil end
    if name == "Divine Favor" and id ~= 20216 then return nil end
    if name == "Holy Strike" and not holyStrikeCastIDs[id] then return nil end
    if name == "Hammer of the Righteous" and id ~= 407632 then return nil end
    if name == "Holy Wrath" and id ~= 2812 and id ~= 10318 then return nil end
    if name == "Holy Shield" and id ~= 20925 and id ~= 20927 and id ~= 20928 then return nil end
    if name == "Swift Judgement" and id ~= 1310994 then return nil end
    if name == "Templar's Bulwark" and id ~= 1311015 then return nil end
    if name == "Righteous Fury" and id ~= 25780 then return nil end
    if sealNames[name] or controlCooldowns[name] then return name end
end

local function CastGUID(value)
    return SafeValue(value) and type(value) == "string" and value:find("^Cast%-") and value or nil
end

local function CastName(arg2, arg3, arg4)
    local id = Number(arg4) or Number(arg3)
    if id then return TrackedNameFromID(id), true end
    if SafeValue(arg2) and type(arg2) == "string" then
        local name = (AL.englishNames and AL.englishNames[arg2]) or arg2
        if sealNames[name] or controlCooldowns[name] or favorConsumers[name] or forbearanceConsumers[name] then return name, true end
    end
    return nil, false
end

local function CooldownInfo(name)
    local info = SafeCall(C_Spell and C_Spell.GetSpellCooldown, LearnedID(name) or name)
    if SafeValue(info) and type(info) == "table" then return info end
end

local function CooldownEnd(info)
    if not info then return nil end
    local start, duration, rate = Number(info.startTime), Number(info.duration), Number(info.modRate)
    if SafeValue(info.modRate) and info.modRate == nil then rate = 1 end
    if start and start > 0 and duration and duration > 1.5 and rate and rate > 0 then
        return start + duration / rate, duration / rate
    end
end

local function ControlReady(name)
    if controlRetryAfter[name] and controlRetryAfter[name] > GetTime() then return false end
    local info = CooldownInfo(name)
    if info and Bool(info.isEnabled) == false then return false end
    if info then
        local start, duration, rate = Number(info.startTime), Number(info.duration), Number(info.modRate)
        if SafeValue(info.modRate) and info.modRate == nil then rate = 1 end
        local ready
        if start and start >= 0 and duration and duration >= 0 and rate and rate > 0 then
            ready = start == 0 or duration <= 1.5 or start + duration / rate <= GetTime()
        elseif Bool(info.isActive) == false then ready = true
        elseif Bool(info.isActive) == true and Bool(info.isOnGCD) == false then ready = false end
        if ready ~= nil then
            if ready and controlCastAt[name] and GetTime() - controlCastAt[name] < 0.5
                and controlEnds[name] and controlEnds[name] > GetTime() then return false end
            return ready
        end
    end
    if controlEnds[name] then return controlEnds[name] <= GetTime() end
    return AL.IsReady(name)
end

-- These talent buffs are not in the older Core's self-buff table. Prefer a
-- complete readable aura scan; otherwise retain only confirmed own casts.
local function TankBuff(name)
    local now = GetTime()
    local state = tankBuffState[name]
    if state and state.castAt and now - state.castAt < 0.5 then
        return state.expires > now, math.max(0, state.expires - now)
    end
    if not tankAurasBlocked and (not tankAuraCache or now - tankAuraCache.at >= 0.2) then
        local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
        if type(reader) == "function" then
            local observed, complete = {}, true
            for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                local ended = false
                for index = 1, 40 do
                    local ok, aura = pcall(reader, "player", index, filter)
                    if not ok or not SafeValue(aura) then tankAurasBlocked = true; complete = false; break end
                    if aura == nil then ended = true; break end
                    if type(aura) ~= "table" then complete = false; break end
                    local id, label = Number(aura.spellId), aura.name
                    if SafeValue(label) and type(label) == "string" then label = (AL.englishNames and AL.englishNames[label]) or label
                    else label = nil end
                    local key = id and tankBuffIDs[id] or label and tankBuffDurations[label] and label
                    if not id and not label then complete = false end
                    if key then
                        local expires = Number(aura.expirationTime)
                        observed[key] = { active = not expires or expires <= 0 or expires > now,
                            remaining = expires and expires > 0 and math.max(0, expires - now) or nil }
                    end
                end
                if not ended then complete = false end
                if tankAurasBlocked then break end
            end
            tankAuraCache = { at = now, complete = complete, buffs = observed }
        end
    end
    local cached = tankAuraCache
    if cached and now - cached.at < 0.2 then
        local aura = cached.buffs[name]
        if aura then return aura.active, aura.remaining end
        if cached.complete then tankBuffState[name] = nil; return false end
    end
    if state and state.expires > now then return true, state.expires - now end
    if name == "Righteous Fury" then return Bool((SafeCall(AL.HasBuff, "player", name))) == true end
    return false
end

local function SealAura()
    local now = GetTime()
    if sealCache and now - sealCache.at < 0.2 then return sealCache.name, sealCache.remaining, sealCache.complete end
    if sealAurasBlocked then return nil, nil, false end
    local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if type(reader) ~= "function" then return nil, nil, false end
    local complete = true
    for index = 1,40 do
        local ok, aura = pcall(reader, "player", index, "HELPFUL")
        if not ok or not SafeValue(aura) then sealAurasBlocked = true; return nil, nil, false end
        if aura == nil then
            sealCache = { at = now, complete = complete }
            return nil, nil, complete
        end
        if type(aura) ~= "table" then complete = false
        else
            local id, name = Number(aura.spellId), aura.name
            if SafeValue(name) and type(name) == "string" then name = (AL.englishNames and AL.englishNames[name]) or name
            elseif id then
                name = TrackedNameFromID(id)
                if not name then
                    local cached = AL.castSpellNamesByID and AL.castSpellNamesByID[id] or SafeCall(AL.SpellName, id)
                    if SafeValue(cached) and type(cached) == "string" then name = (AL.englishNames and AL.englishNames[cached]) or cached
                    else complete = false end
                end
            else name = nil; complete = false end
            if name == "Seal of Fury" and id and not furyCastIDs[id] and id ~= LearnedID(name) then name = nil end
            if SafeValue(name) and type(name) == "string" and sealNames[name] then
                local expires, duration = Number(aura.expirationTime), Number(aura.duration)
                local remaining = expires and expires > 0 and math.max(0, expires - now) or nil
                local fallback = duration and duration > 0 and duration <= 300 and duration or sealDurations[name] or 30
                sealDurations[name] = fallback
                if not sealState or sealState.name ~= name then
                    sealState = { name = name, expires = expires and expires > 0 and expires or now + fallback, duration = fallback }
                elseif expires and expires > 0 then sealState.expires = expires end
                sealState.duration = fallback
                if remaining == nil then remaining = math.max(0, sealState.expires - now) end
                sealCache = { at = now, name = name, remaining = remaining, complete = true }
                return name, remaining, true
            end
        end
    end
    return nil, nil, false
end

local function SealStatus()
    if sealState and sealState.castAt and GetTime() - sealState.castAt < 0.5 then
        return sealState.name, math.max(0, sealState.expires - GetTime())
    end
    local name, remaining, complete = SealAura()
    if complete then
        if not name then sealState = nil end
        return name, remaining
    end
    if sealState then
        if sealState.expires > GetTime() then return sealState.name, sealState.expires - GetTime() end
        return nil
    end
    for _, seal in ipairs(SEALS) do
        if Bool((SafeCall(AL.HasBuff, "player", seal))) == true then
            return seal, Number((SafeCall(AL.BuffRemaining, "player", seal)))
        end
    end
end

-- Divine Favor lasts until Holy Shock or a heal consumes it. Observe readable
-- auras when possible; otherwise keep only confirmed activation/consumption.
local function DivineFavorActive()
    local now = GetTime()
    if favorChangedAt and now - favorChangedAt < 0.5 then return favorActive == true end
    if favorAuraAt and now - favorAuraAt < 0.2 then return favorActive == true end
    favorAuraAt = now
    local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not favorAurasBlocked and type(reader) == "function" then
        local complete = true
        for index = 1,40 do
            local ok, aura = pcall(reader, "player", index, "HELPFUL")
            if not ok or not SafeValue(aura) then favorAurasBlocked = true; break end
            if aura == nil then
                if complete then favorActive = false end
                return favorActive == true
            end
            if type(aura) ~= "table" then complete = false
            else
                local id, name = Number(aura.spellId), aura.name
                if SafeValue(name) and type(name) == "string" then name = (AL.englishNames and AL.englishNames[name]) or name
                else name = nil end
                if id == 20216 or id ~= nil and id == LearnedID("Divine Favor") or name == "Divine Favor" then
                    favorActive = true; return true
                end
                if not id and not name then complete = false end
            end
        end
    end
    if favorActive == nil and Bool((SafeCall(AL.HasBuff, "player", "Divine Favor"))) == true then favorActive = true end
    return favorActive == true
end

local spellTracker = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_AURA", "PLAYER_ENTERING_WORLD",
    "PLAYER_DEAD", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
    pcall(spellTracker.RegisterEvent, spellTracker, event)
end
spellTracker:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
    if AL.playerClass ~= "PALADIN" then return end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        sealState, sealCache, sealAurasBlocked = nil, nil, nil
        favorAuraAt, favorAurasBlocked = nil, nil
        if event == "PLAYER_DEAD" then favorActive, favorChangedAt = false, GetTime() end
        pendingCasts, finishedCasts, lastSent = {}, {}, nil
        tankAuraCache, tankAurasBlocked = nil, nil
        if event == "PLAYER_DEAD" then tankBuffState = {} end
        controlRetryAfter = {}
        for name, expires in pairs(controlEnds) do
            if expires <= GetTime() then controlEnds[name], controlCastAt[name] = nil, nil end
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        sealCache, sealAurasBlocked, favorAuraAt, favorAurasBlocked = nil, nil, nil, nil
        tankAuraCache, tankAurasBlocked = nil, nil; return
    end
    if event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        controlDurations, sealDurations, sealCache = {}, {}, nil
        tankAuraCache, tankAurasBlocked = nil, nil
        return
    end
    if event == "UNIT_AURA" then
        if SafeValue(unit) and unit == "player" then
            sealCache = nil
            favorAuraAt = nil
            tankAuraCache = nil
            if not sealState or not sealState.castAt or GetTime() - sealState.castAt >= 0.5 then SealAura() end
        end
        return
    end
    if not SafeValue(unit) or unit ~= "player" then return end
    for guid, entry in pairs(pendingCasts) do if GetTime() - entry.at > 30 then pendingCasts[guid] = nil end end
    for guid, at in pairs(finishedCasts) do if GetTime() - at > 90 then finishedCasts[guid] = nil end end
    local guid = CastGUID(event == "UNIT_SPELLCAST_SENT" and arg3 or arg2)
    local name, readable = CastName(arg2, arg3, arg4)
    if event == "UNIT_SPELLCAST_SENT" then
        local suggestion = AL.lastSuggestion
        if not readable and SafeValue(suggestion) and type(suggestion) == "string"
            and (sealNames[suggestion] or controlCooldowns[suggestion] or favorConsumers[suggestion] or forbearanceConsumers[suggestion])
            and M.CanTrackSuggestedSpell and M.CanTrackSuggestedSpell(suggestion) then name = suggestion end
        lastSent = { at = GetTime(), name = name, guid = guid }
        if guid then pendingCasts[guid] = lastSent end
        return
    end
    local sent = guid and pendingCasts[guid] or (not guid and lastSent)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
        if sent and not sent.done then
            sent.failed = true
            if controlCooldowns[sent.name] then
                controlRetryAfter[sent.name] = GetTime() + 1
            end
        end
        if guid and not (sent and sent.done) then finishedCasts[guid] = GetTime() end
        return
    end
    if guid and finishedCasts[guid] or sent and (sent.failed or sent.done) then return end
    if not readable and sent and GetTime() - sent.at <= 5 then name = sent.name end
    if not name then return end
    if sent and sent.name and sent.name ~= name then return end
    if sent then sent.done = true end
    if guid then finishedCasts[guid] = GetTime() end
    if tankBuffDurations[name] then
        tankBuffState[name] = { castAt = GetTime(), expires = GetTime() + tankBuffDurations[name] }
        tankAuraCache = nil
    end
    if name == "Templar's Bulwark" then
        tankBuffState.Forbearance = { castAt = GetTime(), expires = GetTime() + 60 }
    elseif name == "Divine Protection" or name == "Divine Shield" or name == "Blessing of Protection" then
        tankBuffState.Forbearance = { castAt = GetTime(), expires = GetTime() + 60 }
        tankAuraCache = nil
    end
    if name == "Divine Favor" or favorConsumers[name] then
        favorActive, favorChangedAt, favorAuraAt = name == "Divine Favor", GetTime(), nil
    end
    if sealNames[name] then
        local duration = sealDurations[name] or 30
        local coreRemaining = Number((SafeCall(AL.BuffRemaining, "player", name)))
        if coreRemaining and coreRemaining > 0 and coreRemaining <= 300 then duration = coreRemaining end
        sealState = { name = name, castAt = GetTime(), expires = GetTime() + duration, duration = duration }
        sealCache = nil
    elseif controlCooldowns[name] then
        local expires, duration = CooldownEnd(CooldownInfo(name))
        if duration then controlDurations[name] = duration end
        controlCastAt[name] = GetTime()
        controlEnds[name] = expires or GetTime() + (controlDurations[name] or controlCooldowns[name])
        controlRetryAfter[name] = nil
        -- The client shares cooldown category 2404 between these strikes.
        -- A protected cooldown must not suggest the other strike early.
        if name == "Holy Strike" or name == "Hammer of the Righteous" then
            local other = name == "Holy Strike" and "Hammer of the Righteous" or "Holy Strike"
            controlCastAt[other], controlEnds[other] = GetTime(), controlEnds[name]
        end
    end
end)

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
    if failure and failure.reader == reader then return false end
    return C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function"
        and type(CreateColor) == "function" and type(reader) == "function"
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

local function SpellCost(name, kind, fallback)
    local ok, result = pcall(function()
        local costs = SafeCall(C_Spell and C_Spell.GetSpellPowerCost, LearnedID(name) or name)
        if not SafeValue(costs) or type(costs) ~= "table" then return end
        for _, entry in pairs(costs) do
            if SafeValue(entry) and type(entry) == "table" and Number(entry.type) == kind then
                local cost = Number(entry.cost)
                if cost and cost >= 0 then return cost end
            end
        end
    end)
    return ok and result or fallback
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

local function ActiveFrom(list)
	for _, name in ipairs(list) do
		if AL.HasBuff("player", name) then return name end
	end
	return nil
end

local function ActiveSeal() return (SealStatus()) end
local function ActiveAura() return ActiveFrom(AURAS) end
local function ActiveBlessing() return ActiveFrom(BLESSINGS) end

local function Role(s)
	if Bool(s.protection) == true then return "TANK" end
	return SettingChoice(s, "paladinRole", { DPS = true, TANK = true }, "DPS")
end

-- Role and build controls share the same exclusive checkbox transition.
function M.SelectBuild(s, key, enabled)
    return M.SetBuild(key, enabled, s)
end
local function Shockadin(s, role)
    return role == "DPS" and SafeValue(s.shockadin) and s.shockadin == true
        and not (SafeValue(s.retribution) and s.retribution == true)
end
local function Retribution(s, role)
    return role == "DPS" and SafeValue(s.retribution) and s.retribution == true
end

local function PreferredBlessing(s, role)
	local mode = SettingChoice(s, "blessingMode", {
		AUTO = true, MIGHT = true, WISDOM = true,
	}, "AUTO")
	if mode == "MIGHT" and Ok("Blessing of Might") then return "Blessing of Might" end
	if mode == "WISDOM" and Ok("Blessing of Wisdom") then return "Blessing of Wisdom" end
	if role == "TANK" and Ok("Blessing of Wisdom") then return "Blessing of Wisdom" end
	if Ok("Blessing of Might") then return "Blessing of Might" end
	return Ok("Blessing of Wisdom") and "Blessing of Wisdom" or nil
end

local function PreferredAura(s, role)
	local mode = SettingChoice(s, "auraMode", {
		AUTO = true, RETRIBUTION = true, DEVOTION = true, CONCENTRATION = true,
	}, "AUTO")
	if mode == "RETRIBUTION" and Ok("Retribution Aura") then return "Retribution Aura" end
	if mode == "DEVOTION" and Ok("Devotion Aura") then return "Devotion Aura" end
	if mode == "CONCENTRATION" and Ok("Concentration Aura") then return "Concentration Aura" end
	if role == "TANK" and Ok("Devotion Aura") then return "Devotion Aura" end
	if Ok("Retribution Aura") then return "Retribution Aura" end
	return Ok("Devotion Aura") and "Devotion Aura" or nil
end

local function WeaponSpeed()
	local speed = Number((SafeCall(UnitAttackSpeed, "player")))
	if speed and speed > 0 then weaponSpeedCache = speed end
	return weaponSpeedCache
end

local function PreferredSeal(s, role)
	local mode = SettingChoice(s, "seal", {
		AUTO = true, COMMAND = true, RIGHTEOUSNESS = true, FURY = true, LIGHT = true, WISDOM = true,
	}, "AUTO")
	if mode == "AUTO" and Shockadin(s, role) and Ok("Seal of Righteousness") then return "Seal of Righteousness" end
	if mode == "FURY" and Ok("Seal of Fury") then return "Seal of Fury" end
	if mode == "COMMAND" and Ok("Seal of Command") then return "Seal of Command" end
	if mode == "RIGHTEOUSNESS" and Ok("Seal of Righteousness") then return "Seal of Righteousness" end
	if mode == "LIGHT" and Ok("Seal of Light") then return "Seal of Light" end
	if mode == "WISDOM" and Ok("Seal of Wisdom") then return "Seal of Wisdom" end
	if role == "TANK" and Ok("Seal of Fury") then return "Seal of Fury" end
	if role == "TANK" and Ok("Seal of Righteousness") then return "Seal of Righteousness" end
	local speed = WeaponSpeed()
	if speed and speed >= 3.8 and Ok("Seal of Command") then return "Seal of Command" end
	if Ok("Seal of Righteousness") then return "Seal of Righteousness" end
	return Ok("Seal of Command") and "Seal of Command" or nil
end

local function ManaMaximum()
    local value = Number((SafeCall(UnitPowerMax, "player", 0)))
    if value and value > 0 then manaMaximumCache = value end
    return manaMaximumCache
end

local function ManaAmount()
    local value = Number((SafeCall(UnitPower, "player", 0)))
    if value and value >= 0 then return value end
    local percentage = Percent((SafeCall(AL.ManaPercent)))
    local maximum = ManaMaximum()
    if percentage and maximum then return percentage * maximum / 100 end
end

local function ManaGate(value, threshold, below)
    if value ~= nil and math.abs(value - threshold) < 1e-7 then value = threshold end
    if value ~= nil then return below and value <= threshold or not below and value >= threshold end
    if not below and threshold <= 0 then return true end
    if not CurveAvailable("power", "player", 0) then return false end
    local cut = threshold / 100
    if below then cut = NextFloat32(cut) end
    return { axis = "mana", kind = "power", unit = "player", powerType = 0, cut = cut, below = below }
end

local function Affordable(name, usable, shortage)
    if shortage == true then return false end
    local cost = SpellCost(name, 0)
    if cost == nil then return usable ~= false end
    if cost <= 0 then return true end
    local amount = ManaAmount()
    if amount ~= nil then return amount >= cost end
    local maximum = ManaMaximum()
    if maximum and CurveAvailable("power", "player", 0) then
        if cost > maximum then return false end
        return { axis = "mana", kind = "power", unit = "player", powerType = 0, cut = cost / maximum, below = false }
    end
    -- If no resource curve is supported, a readable usability answer still
    -- permits ordinary spells; a user's percentage limit remains mandatory.
    return usable ~= false
end

local function ShieldEquipped()
	local itemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
	if not GetInventoryItemID or not itemInfoInstant then return nil end
	local okID, itemID = pcall(GetInventoryItemID, "player", 17)
	if not okID or not SafeValue(itemID) then return nil end
	if not itemID then return false end
	local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(itemInfoInstant, itemID)
	if not ok then return nil end
	if SafeValue(equipLoc) and equipLoc == "INVTYPE_SHIELD" then return true end
	if Number(classID) and Number(subclassID) then
		return classID == 4 and subclassID == 6
	end
	return nil
end

local function Ready(name)
    if controlCooldowns[name] then return Ok(name) and ControlReady(name) end
    return Ok(name) and AL.IsReady(name)
end

local function Offer(name, reason, gates, preparation)
    if not Ready(name) then return false end
    local usable, shortage = SpellUsability(name)
    if usable == false or shortage == true then return false end
    if not sealNames[name] and not tankBuffDurations[name]
        and name ~= "Consecration" and name ~= "Divine Favor" and name ~= "Holy Wrath" then
        local inRange
        if controlCooldowns[name] then inRange = Bool((SafeCall(C_Spell and C_Spell.IsSpellInRange, LearnedID(name) or name, "target"))) end
        if inRange == nil then inRange = Bool((SafeCall(AL.InRange, name))) end
        if inRange == false then return false end
    end
    local conditions = {}
    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
    local affordable = Affordable(name, usable, shortage)
    -- A readable positive usability answer proves enough mana for a buff.
    -- Keep that public preparation decision identifiable when mana is secret.
    if preparation and ManaAmount() == nil and usable == true and shortage == false then affordable = true end
    conditions[#conditions + 1] = affordable
    return AddAction(name, reason, conditions)
end

local function PlayerIsCastingOrChanneling()
    for _, reader in pairs({ UnitCastingInfo, UnitChannelInfo }) do
        local value = SafeCall(reader, "player")
        if not SafeValue(value) or value ~= nil then return true end
    end
    local name = SafeCall(AL.CastingSpell)
    return SafeValue(name) and type(name) == "string"
end
local function PlayerMoving()
    local moving = A and A.Player and Bool((SafeCall(A.Player.IsMoving, A.Player)))
    if moving ~= nil then return moving end
    local speed = Number((SafeCall(GetUnitSpeed, "player")))
    return speed ~= nil and speed > 0
end

local function SpellCastTimeMS(name)
    local reference = LearnedID(name) or name
    local info = SafeCall(C_Spell and C_Spell.GetSpellInfo, reference)
    if SafeValue(info) and type(info) == "table" then
        local milliseconds = Number(info.castTime)
        if milliseconds ~= nil then return milliseconds end
    end
    local _, _, _, milliseconds = SafeCall(GetSpellInfo, reference)
    return Number(milliseconds)
end

local function UnitWithin(unit, yards)
    local squared, checked = SafeCall(UnitDistanceSquared, unit)
    squared = Number(squared)
    if squared and squared >= 0 and Bool(checked) ~= false then return squared <= yards * yards end
    local object = A and SafeCall(A.Unit, unit)
    if SafeValue(object) and (type(object) == "table" or type(object) == "userdata") then
        local range = Number((SafeCall(object.GetRange, object)))
        if range and range >= 0 then return range <= yards end
    end
    if yards >= 10 then
        local near = Bool((SafeCall(CheckInteractDistance, unit, 3)))
        if near == true then return true end
        if yards <= 10 and near ~= nil then return near end
    end
    -- A positive Holy Strike range is a conservative melee lower bound for
    -- the eight-yard ground effect; a negative melee range does not prove far.
    if Known("Holy Strike") then
        local range
        if unit == "target" then range = SafeCall(AL.InRange, "Holy Strike")
        else range = SafeCall(C_Spell and C_Spell.IsSpellInRange, LearnedID("Holy Strike") or "Holy Strike", unit) end
        if SafeValue(range) and (range == true or range == 1) then return true end
    end
end

local function InMelee()
    if Known("Holy Strike") then
        local near = Bool((SafeCall(AL.InRange, "Holy Strike")))
        if near ~= nil then return near end
    end
    return UnitWithin("target", 5) == true
end

local function UndeadOrDemon()
    local name, id = SafeCall(UnitCreatureType, "target")
    id = Number(id)
    -- Client creature-type IDs do not depend on the selected UI language.
    if id then return id == 3 or id == 6 end
    return SafeValue(name) and (name == "Undead" or name == "Demon")
end

local function EnemyCountMelee(limit)
    local framework
    local function Accept(value)
        value = Number(value)
        if value and value >= 0 and value <= 40 and value == math.floor(value) then framework = math.max(framework or 0, value) end
    end
    Accept((SafeCall(AL.EnemyCount, 8)))
    if A and A.MultiUnits then
        Accept((SafeCall(A.MultiUnits.GetByRangeInCombat, A.MultiUnits, 8, limit or 5)))
        Accept((SafeCall(A.MultiUnits.GetActiveEnemies, A.MultiUnits, 8)))
    end
    local seen, count = {}, 0
    local function Count(unit)
        if not SafeValue(unit) or type(unit) ~= "string" then return end
        if Bool((SafeCall(UnitExists, unit))) ~= true or Bool((SafeCall(UnitCanAttack, "player", unit))) ~= true
            or Bool((SafeCall(UnitIsDeadOrGhost, unit))) ~= false
            or Bool((SafeCall(UnitAffectingCombat, unit))) ~= true then return end
        local guid = SafeCall(UnitGUID, unit)
        if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] then return end
        if UnitWithin(unit, 8) ~= true then return end
        seen[guid], count = true, count + 1
    end
    Count("target")
    local plates = SafeCall(C_NamePlate and C_NamePlate.GetNamePlates)
    if SafeValue(plates) and type(plates) == "table" then
        for _, plate in pairs(plates) do
            if SafeValue(plate) and type(plate) == "table" then
                Count(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
            end
        end
    else
        for index = 1, 40 do Count("nameplate" .. index) end
    end
    for guid, expires in pairs(nearbyAttackers) do
        if expires <= GetTime() then nearbyAttackers[guid] = nil
        elseif not seen[guid] then seen[guid], count = true, count + 1 end
    end
    if count > 0 then framework = math.max(framework or 0, count) end
    return framework
end

local tracker = CreateFrame("Frame")
for _, event in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ENTERING_WORLD", "UNIT_INVENTORY_CHANGED" }) do
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" or type(CombatLogGetCurrentEventInfo) == "function" then pcall(tracker.RegisterEvent, tracker, event) end
end
tracker:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_INVENTORY_CHANGED" then
        if SafeValue(unit) and unit == "player" then weaponSpeedCache, lastRotation, AL.rotationSecretVisual = nil, nil, nil end
        return
    end
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then
        nearbyAttackers, lastRotation, AL.rotationSecretVisual = {}, nil, nil
        curveFailures, manaMaximumCache = {}, nil
        if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then weaponSpeedCache = nil end
        return
    end
    if type(CombatLogGetCurrentEventInfo) ~= "function" then return end
    local ok, _, sub, _, srcGUID, _, _, _, destGUID = pcall(CombatLogGetCurrentEventInfo)
    if not ok or not SafeValue(sub) or not SafeValue(srcGUID) or not SafeValue(destGUID) then return end
    if sub == "UNIT_DIED" then
        if type(destGUID) == "string" then nearbyAttackers[destGUID] = nil end
        return
    end
    local playerGUID = SafeCall(UnitGUID, "player")
    if SafeValue(playerGUID) and type(playerGUID) == "string" and destGUID == playerGUID
        and type(srcGUID) == "string" and srcGUID ~= playerGUID
        and (sub == "SWING_DAMAGE" or sub == "SWING_MISSED") then
        nearbyAttackers[srcGUID] = GetTime() + 4
    end
end)

local function ApplyPreparation(s, role, sealNeeded, inCombat)
    if not s.buffs then return end
    if role == "TANK" and s.tankRighteousFury and not TankBuff("Righteous Fury") then
        Offer("Righteous Fury", "tank threat", nil, true)
    end
    local seal = PreferredSeal(s, role)
    if sealNeeded and seal then
        local active, remaining = SealStatus()
        -- Three seconds leaves room to refresh before expiry. Keep the short
        -- precombat rule; idle preparation never renews an otherwise active seal.
        local refresh = inCombat and remaining ~= nil and remaining <= 3
        if active ~= seal or refresh then
            Offer(seal, refresh and "refresh seal" or "seal before judgement", nil, true)
        end
    end
    local blessing = PreferredBlessing(s, role)
    if blessing and ActiveBlessing() ~= blessing then Offer(blessing, "blessing", nil, true) end
    local aura = PreferredAura(s, role)
    if aura and ActiveAura() ~= aura then Offer(aura, "aura", nil, true) end
end

local function Emergency(s, role, hp, mana)
    if not s.emergency then return end
    if s.layOnHands then Offer("Lay on Hands", "critical emergency", {
        HealthGate("player", hp, SettingNumber(s, "layOnHandsHP", 10, 1, 50), true) }) end
    if role == "TANK" and s.templarsBulwark and not TankBuff("Forbearance") and not TankBuff("Templar's Bulwark") then
        Offer("Templar's Bulwark", "tank absorb", {
            HealthGate("player", hp, SettingNumber(s, "templarsBulwarkHP", 35, 5, 80), true) })
    end
    if role == "DPS" and s.divineShield and not AL.HasBuff("player", "Divine Shield") then
        Offer("Divine Shield", "immunity", {
            HealthGate("player", hp, SettingNumber(s, "divineShieldHP", 18, 5, 60), true) })
    end
    if role ~= "TANK" and s.divineProtection and not AL.HasBuff("player", "Divine Protection") then
        Offer("Divine Protection", "emergency", {
            HealthGate("player", hp, SettingNumber(s, "divineProtectionHP", 30, 5, 80), true) })
    end
    local manaGate = ManaGate(mana, SettingNumber(s, "healMinMana", 10, 0, 100), false)
    if s.holyHeal then Offer("Holy Light", "large heal", {
        HealthGate("player", hp, SettingNumber(s, "holyHealHP", 35, 5, 90), true), manaGate }) end
    if s.flashHeal then Offer("Flash of Light", "fast heal", {
        HealthGate("player", hp, SettingNumber(s, "flashHealHP", 55, 5, 95), true), manaGate }) end
end

local function Judgement(s, mana, targetHP, reason)
    if s.judgement and ActiveSeal() then
        Offer("Judgement", reason, {
            ManaGate(mana, SettingNumber(s, "judgementMinMana", 15, 0, 100), false),
            HealthGate("target", targetHP, SettingNumber(s, "judgementMinTargetHP", 20, 0, 100), false) })
    end
end

local function Consecration(s, role, mana)
    local minimum = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
    local enemies = s.aoe and s.consecration and EnemyCountMelee(minimum)
    if enemies and enemies >= minimum then
        local key = role == "TANK" and "tankConsecrationMinMana" or "consecrationMinMana"
        Offer("Consecration", tostring(enemies) .. " engaged enemies", {
            ManaGate(mana, SettingNumber(s, key, role == "TANK" and 20 or 35, 0, 100), false) })
    end
end

local function TankHolyShield(s, role, mana, nearby)
    if role ~= "TANK" or not s.holyShield or not nearby or ShieldEquipped() ~= true then return end
    local active, remaining = TankBuff("Holy Shield")
    if active and (remaining == nil or remaining > 0.5) then return end
    Offer("Holy Shield", "tank block protection", {
        ManaGate(mana, SettingNumber(s, "holyShieldMinMana", 10, 0, 100), false) })
end

local function TankBurst(s, role, mana, targetHP)
    if role ~= "TANK" or not AL.burst or not s.swiftJudgement or not s.judgement
        or not ActiveSeal() then return end
    local range = Bool((SafeCall(C_Spell and C_Spell.IsSpellInRange,
        LearnedID("Swift Judgement") or "Swift Judgement", "target")))
    if range == nil then range = Bool((SafeCall(AL.InRange, "Swift Judgement"))) end
    if range == false or range ~= true and UnitWithin("target", 10) ~= true then return end
    Offer("Swift Judgement", "Burst: independent seal Judgement", {
        HealthGate("target", targetHP, SettingNumber(s, "judgementMinTargetHP", 20, 0, 100), false),
        HealthGate("target", targetHP, SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false) })
end

local function RetributionAoEStrike(s, role, mana)
    if (not Retribution(s, role) and role ~= "TANK") or not s.aoe or not s.hammerOfTheRighteous or not InMelee() then return end
    local minimum = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
    local enemies = EnemyCountMelee(minimum)
    if enemies and enemies >= minimum then
        Offer("Hammer of the Righteous", tostring(enemies) .. " engaged enemies", {
            ManaGate(mana, SettingNumber(s, "hammerOfTheRighteousMinMana", 10, 0, 100), false) })
    end
end

local function RetributionHolyWrath(s, role, mana)
    if (not Retribution(s, role) and role ~= "TANK") or not s.aoe or not s.holyWrath or PlayerMoving()
        or not UndeadOrDemon() or UnitWithin("target", 20) ~= true then return end
    local minimum = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
    local enemies = EnemyCountMelee(minimum)
    if enemies and enemies >= minimum then
        Offer("Holy Wrath", tostring(enemies) .. " engaged enemies (undead / demon)", {
            ManaGate(mana, SettingNumber(s, "holyWrathMinMana", 35, 0, 100), false) })
    end
end

local function ShockadinBurst(s, role, mana, targetHP)
    if not AL.burst or not Shockadin(s, role) or not s.divineFavor or not s.holyShock then return end
    local manaGate = ManaGate(mana, SettingNumber(s, "holyShockMinMana", 10, 0, 100), false)
    if DivineFavorActive() then
        Offer("Holy Shock", "consume Divine Favor", { manaGate })
        return
    end
    -- Never activate a guaranteed critical spell without an eligible Holy
    -- Shock to follow it, including range, slider and actual mana-cost checks.
    if not Ready("Holy Shock") then return end
    local usable, shortage = SpellUsability("Holy Shock")
    if usable == false or shortage == true then return end
    local range = Bool((SafeCall(C_Spell and C_Spell.IsSpellInRange, LearnedID("Holy Shock") or "Holy Shock", "target")))
    if range == nil then range = Bool((SafeCall(AL.InRange, "Holy Shock"))) end
    if range == false then return end
    Offer("Divine Favor", "Burst: prepare Holy Shock", {
        manaGate, Affordable("Holy Shock", usable, shortage),
        HealthGate("target", targetHP, SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false) })
end

local function OffensivePriority(s, role, mana, targetHP)
    local targetCasting = Bool((SafeCall(AL.TargetCasting))) == true
    if s.hammer and not targetCasting then
        for _, reader in pairs({ UnitCastingInfo, UnitChannelInfo }) do
            local name, _, texture, start = SafeCall(reader, "target")
            if SafeValue(name) and type(name) == "string" and name ~= ""
                or Number(texture) ~= nil or Number(start) ~= nil
                or SafeValue(texture) and type(texture) == "string" and texture ~= "" then targetCasting = true; break end
        end
        if not targetCasting then
            for _, reader in pairs({ UnitCastingDuration, UnitChannelDuration }) do
                local duration = SafeCall(reader, "target")
                if SafeValue(duration) and (type(duration) == "table" or type(duration) == "userdata") then targetCasting = true; break end
            end
        end
    end
    if s.hammer and targetCasting then Offer("Hammer of Justice", "stop cast") end
    ApplyPreparation(s, role, true, true)
    TankHolyShield(s, role, mana, InMelee())
    TankBurst(s, role, mana, targetHP)
    ShockadinBurst(s, role, mana, targetHP)
    Judgement(s, mana, targetHP, InMelee() and "on cooldown" or "ranged opener")
    Consecration(s, role, mana)
    local hammerCastTime = SpellCastTimeMS("Hammer of Wrath")
    local hammerCanMove = hammerCastTime ~= nil and hammerCastTime <= 0
    if (Shockadin(s, role) or Retribution(s, role) or role == "TANK") and s.hammerOfWrath
        and (not PlayerMoving() or hammerCanMove) then
        Offer("Hammer of Wrath", "execute", {
            ManaGate(mana, SettingNumber(s, "hammerOfWrathMinMana", 10, 0, 100), false),
            HealthGate("target", targetHP, 20, true) })
    end
    if AL.burst then
        local gate = HealthGate("target", targetHP, SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false)
        Offer("Blood Fury", "burst", { gate })
        Offer("Berserking", "burst", { gate })
    end
    RetributionAoEStrike(s, role, mana)
    if s.holystrike then Offer("Holy Strike", role == "TANK" and "tank strike" or "on cooldown", {
        ManaGate(mana, SettingNumber(s, "holyStrikeMinMana", 10, 0, 100), false) }) end
    if s.exorcism and UndeadOrDemon() then Offer("Exorcism", "undead / demon", {
        ManaGate(mana, SettingNumber(s, "exorcismMinMana", 25, 0, 100), false),
        HealthGate("target", targetHP, SettingNumber(s, "exorcismMinTargetHP", 25, 0, 100), false) }) end
    RetributionHolyWrath(s, role, mana)
    if Shockadin(s, role) and s.holyShock then
        Offer("Holy Shock", "learned ranged damage", {
            ManaGate(mana, SettingNumber(s, "holyShockMinMana", 10, 0, 100), false) })
    end
    AddAction(AL.Ok("Attack") and "Attack" or nil, "melee / conserve mana")
end

function M.NextSpell(s, inCombat, hostile)
    M.NormalizeBuild(s)
    if not inCombat then curveFailures, manaMaximumCache = {}, nil end
    lastRotation = { at = GetTime(), actions = {} }
    local role = Role(s)
    local mana = Percent((SafeCall(AL.ManaPercent)))
    local hp = HealthPercent("player")
    local targetHP = hostile and HealthPercent("target") or nil
    if PlayerIsCastingOrChanneling() then AddAction(nil, "Casting")
    elseif not inCombat then
        if s.oocHeal then Offer("Holy Light", "out of combat heal", {
            HealthGate("player", hp, SettingNumber(s, "oocHealHP", 80, 5, 100), true, true),
            ManaGate(mana, SettingNumber(s, "healMinMana", 10, 0, 100), false) }) end
        local prePull = hostile and Ready("Judgement") and UnitWithin("target", 10) == true
        ApplyPreparation(s, role, prePull)
        TankHolyShield(s, role, mana, prePull)
        if prePull then Judgement(s, mana, targetHP, "pull") end
        if hostile then AddAction(AL.Ok("Attack") and "Attack" or nil, role == "TANK" and "tank opener" or "opener") end
    else
        Emergency(s, role, hp, mana)
        if hostile then OffensivePriority(s, role, mana, targetHP)
        else
            ApplyPreparation(s, role, true, true)
            local enemies = EnemyCountMelee(1)
            TankHolyShield(s, role, mana, enemies and enemies > 0)
            Consecration(s, role, mana)
        end
    end
    AddAction(nil, inCombat and not hostile and "No target" or "Ready")
    local base = lastRotation.actions[#lastRotation.actions]
    lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
    return base.spell, base.reason
end

function M.OnTargetChanged()
    lastRotation, AL.rotationSecretVisual = nil, nil
end

function M.CanTrackSuggestedSpell(name)
    if not lastRotation or GetTime() - lastRotation.at > 0.5 or lastRotation.visualCandidate then return false end
    local visual = AL.rotationSecretVisual
    if visual and GetTime() - visual.at <= 0.5 then return false end
    if name ~= lastRotation.baseSpell or not Ok(name) then return false end
    for _, entry in ipairs(M.spells) do if entry[2] == name then return true end end
    return name == "Berserking" or name == "Blood Fury"
end

function M.GetUIState()
    local profile, knownCount = AL.S(), 0
    for _, entry in ipairs(M.spells) do if Known(entry[2]) then knownCount = knownCount + 1 end end
    return { role = Role(profile), level = Number((SafeCall(UnitLevel, "player"))),
        mana = Percent((SafeCall(AL.ManaPercent))), knownCount = knownCount,
        shockadin = Shockadin(profile, Role(profile)),
        retribution = Retribution(profile, Role(profile)),
        protection = Role(profile) == "TANK",
        seal = ActiveSeal(), aura = ActiveAura(), blessing = ActiveBlessing(),
        righteousFury = TankBuff("Righteous Fury"),
        enemyCount = EnemyCountMelee(SettingNumber(profile, "aoeMinEnemies", 2, 2, 5)), hasShield = ShieldEquipped() }
end

if AL.selfCastSpells then
    for _, list in ipairs({ SEALS, AURAS, BLESSINGS, { "Righteous Fury", "Consecration", "Holy Light", "Flash of Light",
        "Divine Protection", "Divine Shield", "Lay on Hands", "Berserking", "Blood Fury", "Divine Favor", "Cleanse", "Holy Wrath",
        "Holy Shield", "Templar's Bulwark" } }) do
        for _, name in ipairs(list) do AL.selfCastSpells[name] = true end
    end
end
local function IntervalCurve(low, high)
	local key = tostring(low) .. ":" .. tostring(high)
	if visibilityCurves[key] then return visibilityCurves[key] end
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	curve:AddPoint(0, CreateColor(1, 1, 1, low == 0 and 1 or 0))
	if low > 0 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
	if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
	if low ~= 1 and high ~= 1 then curve:AddPoint(1, CreateColor(1, 1, 1, high > 1 and 1 or 0)) end
	visibilityCurves[key] = curve
	return curve
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
			local success, value = pcall(function()
				local curve = IntervalCurve(mask.low, mask.high)
				local color
				if mask.kind == "power" then color = UnitPowerPercent(mask.unit, mask.powerType, false, curve)
				else color = UnitHealthPercent(mask.unit, false, curve) end
				local _, _, _, alpha = color:GetRGBA()
				return alpha
			end)
			if not success then
				curveFailures[mask.kind .. ":" .. mask.unit .. ":" .. tostring(mask.powerType or "")] = {
					reader = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent }
				error("Paladin resource curve unavailable")
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
		if mask then node:SetAlpha(values[mask.key]) else node:SetAlpha(1) end
	end
end



AL.RegisterRotation("PALADIN", M)
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

    -- =====================================================================
    -- Holy Paladin Healing Rotation provider
    -- ---------------------------------------------------------------------
    -- Party health remains protected in combat. This provider supplies only
    -- public spell, aura and confirmed-cast timers; HealingEngine owns every
    -- health/mana mask and the Action-compatible focus pixel.
    -- =====================================================================
    local paladinHealing = {
        effects = {}, applied = {}, cooldowns = {}, favorActive = false,
        favorChangedAt = 0, infusionUntil = 0, infusionChangedAt = 0,
        vigil = nil, oath = nil, lastHeal = nil,
        lastBlessing = nil, lastJudgement = nil,
    }
    local PL_SEALS = {
        "Seal of Fury", "Seal of Command", "Seal of Righteousness",
        "Seal of the Crusader", "Seal of Light", "Seal of Wisdom",
    }
    local PL_AURAS = { "Retribution Aura", "Devotion Aura", "Concentration Aura" }
    local PL_AURA_BY_SETTING = {
        RETRIBUTION = "Retribution Aura", DEVOTION = "Devotion Aura",
        CONCENTRATION = "Concentration Aura",
    }
    local PL_SEAL_BY_SETTING = {
        COMMAND = "Seal of Command", RIGHTEOUSNESS = "Seal of Righteousness",
        FURY = "Seal of Fury", LIGHT = "Seal of Light", WISDOM = "Seal of Wisdom",
    }
    local PL_AURA_IDS = {
        ["Divine Favor"] = { [20216] = true },
        ["Infusion of Light"] = { [426065] = true },
        ["Blessing of Kings"] = { [20217] = true, [25898] = true },
        ["Greater Blessing of Kings"] = { [20217] = true, [25898] = true },
        ["Light's Vigil"] = { [1310911] = true, [1311590] = true, [1311595] = true },
    }

    local function PLNow()
        local ok, value = pcall(GetTime)
        return ok and type(value) == "number" and value or 0
    end
    local function PLSecret(value)
        if type(issecretvalue) ~= "function" then return false end
        local ok, secret = pcall(issecretvalue, value)
        return not ok or secret == true
    end
    local function PLNumber(value)
        if PLSecret(value) or type(value) ~= "number" or value ~= value
            or value == math.huge or value == -math.huge then return nil end
        return value
    end
    local function PLBool(func, ...)
        if type(func) ~= "function" then return nil end
        local ok, value = pcall(func, ...)
        if not ok or PLSecret(value) then return nil end
        if value == true or value == 1 then return true end
        if value == false or value == 0 then return false end
    end
    local function PLExists(unit)
        return PLBool(UnitExists, unit) == true
    end
    local function PLKnown(spell)
        return not root.known or root.known[spell] == true
    end
    local function PLPermitted(spell, profile, ignoreUsable)
        if type(spell) ~= "string" or spell == "" or not PLKnown(spell) then return false end
        if root.Allowed then
            local ok, allowed = pcall(root.Allowed, spell, profile)
            if not ok or PLSecret(allowed) or allowed == false then return false end
        end
        if not ignoreUsable and root.SpellUsable then
            local ok, usable = pcall(root.SpellUsable, spell)
            if not ok or PLSecret(usable) or usable == false then return false end
        end
        return true
    end
    local function PLCooldownReady(spell)
        local expiration = paladinHealing.cooldowns[spell]
        return type(expiration) ~= "number" or expiration <= PLNow()
    end
    local function PLAvailable(spell, profile, ignoreRootReady, ignoreUsable)
        if not PLPermitted(spell, profile, ignoreUsable) or not PLCooldownReady(spell) then return false end
        if not ignoreRootReady and root.IsReady then
            local ok, ready = pcall(root.IsReady, spell)
            if not ok or PLSecret(ready) or ready == false then return false end
        end
        return true
    end
    local function PLPreferred(profile, spells, ignoreRootReady, ignoreUsable)
        for _, spell in ipairs(spells) do
            if PLAvailable(spell, profile, ignoreRootReady, ignoreUsable) then return spell end
        end
    end
    local function PLRosterUnits()
        local units, raid = {}, false
        for index = 1, 40 do
            if PLExists("raid" .. index) then raid = true; break end
        end
        if raid then
            for index = 1, 40 do
                local unit = "raid" .. index
                if PLExists(unit) then units[#units + 1] = unit end
            end
        else
            for index = 1, 4 do
                local unit = "party" .. index
                if PLExists(unit) then units[#units + 1] = unit end
            end
            units[#units + 1] = "player"
        end
        return units
    end
    local function PLGroupUnitFor(source)
        if not PLExists(source) or type(UnitIsUnit) ~= "function" then return nil end
        local assist = PLBool(UnitCanAssist, "player", source)
        local friend = PLBool(UnitIsFriend, "player", source)
        if assist ~= true and friend ~= true then return nil end
        for _, unit in ipairs(PLRosterUnits()) do
            if PLBool(UnitIsUnit, source, unit) == true then return unit end
        end
    end
    local function PLHealingUnit()
        return PLGroupUnitFor("target") or PLGroupUnitFor("focus")
    end
    local function PLUnitKey(unit)
        if type(unit) ~= "string" then return nil end
        if type(UnitGUID) == "function" then
            local ok, guid = pcall(UnitGUID, unit)
            if ok and not PLSecret(guid) and type(guid) == "string" and guid ~= "" then
                return guid
            end
        end
        return unit
    end
    local function PLUnitForKey(key)
        if type(key) ~= "string" then return nil end
        for _, unit in ipairs(PLRosterUnits()) do
            if PLUnitKey(unit) == key then return unit end
        end
    end
    local function PLSameUnit(left, right)
        if not left or not right then return false end
        if type(UnitIsUnit) == "function" and PLBool(UnitIsUnit, left, right) == true then return true end
        return PLUnitKey(left) == PLUnitKey(right)
    end
    local function PLEffectActive(unit, spell)
        local key = PLUnitKey(unit)
        local effects = key and paladinHealing.effects[key]
        local expiration = effects and effects[spell]
        if type(expiration) == "number" and expiration > PLNow() then return true end
        if effects then effects[spell] = nil end
        if key and paladinHealing.applied[key] then paladinHealing.applied[key][spell] = nil end
        return false
    end
    local function PLSetEffect(unit, spell, duration)
        local key = PLUnitKey(unit)
        if not key or type(duration) ~= "number" then return end
        paladinHealing.effects[key] = paladinHealing.effects[key] or {}
        paladinHealing.applied[key] = paladinHealing.applied[key] or {}
        paladinHealing.effects[key][spell] = PLNow() + duration
        paladinHealing.applied[key][spell] = PLNow()
    end
    local function PLClearEffects(unit, spells)
        local key = PLUnitKey(unit)
        local effects = key and paladinHealing.effects[key]
        if not effects then return end
        local applied = paladinHealing.applied[key]
        for _, spell in ipairs(spells) do
            effects[spell] = nil
            if applied then applied[spell] = nil end
        end
    end
    local function PLAuraState(unit, spell, ids)
        local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
        if type(reader) ~= "function" then return nil end
        for index = 1, 40 do
            local ok, aura = pcall(reader, unit, index, "HELPFUL")
            if not ok or PLSecret(aura) then return nil end
            if aura == nil then return false end
            if type(aura) ~= "table" then return nil end
            local id = PLNumber(aura.spellId)
            local name = not PLSecret(aura.name) and type(aura.name) == "string" and aura.name or nil
            if name then name = (root.englishNames and root.englishNames[name]) or name end
            local learned = root.rangeSpellRefs and root.rangeSpellRefs[spell]
            local learnedID = learned and PLNumber(learned.id)
            if name == spell or ids and id and ids[id] or learnedID and id == learnedID then
                return true, PLNumber(aura.expirationTime)
            end
        end
        return nil
    end
    local function PLTrackedAura(unit, spell, duration, ids)
        local present, expiration = PLAuraState(unit, spell, ids)
        if present == true then
            local seconds = expiration and math.max(0.1, expiration - PLNow()) or duration
            PLSetEffect(unit, spell, seconds)
            return true
        end
        if present == false then
            local key = PLUnitKey(unit)
            local effects = key and paladinHealing.effects[key]
            local applied = key and paladinHealing.applied[key]
            if applied and type(applied[spell]) == "number"
                and PLNow() - applied[spell] < 0.75 then
                return effects and type(effects[spell]) == "number"
                    and effects[spell] > PLNow() or false
            end
            if effects then effects[spell] = nil end
            if applied then applied[spell] = nil end
            return false
        end
        return PLEffectActive(unit, spell)
    end
    local function PLChoice(profile, key, allowed, fallback)
        if type(profile) ~= "table" then return fallback end
        local value = profile[key]
        if PLSecret(value) or type(value) ~= "string" or not allowed[value] then return fallback end
        return value
    end
    local function PLSelectedAura(profile)
        local setting = PLChoice(profile, "healingAura", {
            CONCENTRATION = true, DEVOTION = true, RETRIBUTION = true,
        }, "CONCENTRATION")
        local selected = PL_AURA_BY_SETTING[setting]
        if selected and PLKnown(selected) then return selected end
        for _, spell in ipairs({ "Concentration Aura", "Devotion Aura", "Retribution Aura" }) do
            if PLKnown(spell) then return spell end
        end
    end
    local function PLSelectedSeal(profile)
        local setting = PLChoice(profile, "seal", {
            AUTO = true, COMMAND = true, RIGHTEOUSNESS = true,
            FURY = true, LIGHT = true, WISDOM = true,
        }, "AUTO")
        local selected = PL_SEAL_BY_SETTING[setting]
        if selected and PLKnown(selected) then return selected end
        for _, spell in ipairs({ "Seal of Wisdom", "Seal of Light", "Seal of Righteousness", "Seal of Command" }) do
            if PLKnown(spell) then return spell end
        end
    end
    local function PLPlayerAuraActive(spell, duration, ids)
        return PLTrackedAura("player", spell, duration, ids or PL_AURA_IDS[spell])
    end
    local function PLKingsActive(unit)
        local normal = PLAuraState(unit, "Blessing of Kings", PL_AURA_IDS["Blessing of Kings"])
        if normal == true then
            PLSetEffect(unit, "Blessing of Kings", 3600)
            return true
        elseif normal == false then
            local key = PLUnitKey(unit)
            local applied = key and paladinHealing.applied[key]
            if applied and ((applied["Blessing of Kings"] or 0) > PLNow() - 0.75
                or (applied["Greater Blessing of Kings"] or 0) > PLNow() - 0.75) then
                return true
            end
            PLClearEffects(unit, { "Blessing of Kings", "Greater Blessing of Kings" })
            return false
        end
        return PLEffectActive(unit, "Blessing of Kings")
            or PLEffectActive(unit, "Greater Blessing of Kings")
    end
    local function PLInfusionActive()
        local present, expiration = PLAuraState("player", "Infusion of Light", PL_AURA_IDS["Infusion of Light"])
        if present == true then
            paladinHealing.infusionUntil = expiration and math.max(PLNow() + 0.1, expiration) or PLNow() + 15
        elseif present == false then
            if PLNow() - paladinHealing.infusionChangedAt >= 0.75 then
                paladinHealing.infusionUntil = 0
            end
        end
        return paladinHealing.infusionUntil > PLNow()
    end
    local function PLFavorActive()
        local present = PLAuraState("player", "Divine Favor", PL_AURA_IDS["Divine Favor"])
        if present == true then paladinHealing.favorActive = true
        elseif present == false and PLNow() - paladinHealing.favorChangedAt >= 0.75 then
            paladinHealing.favorActive = false
        end
        return paladinHealing.favorActive == true
    end
    local function PLUnitClass(unit)
        if type(UnitClass) ~= "function" then return nil end
        local ok, _, class = pcall(UnitClass, unit)
        if not ok or PLSecret(class) or type(class) ~= "string" then return nil end
        return class
    end
    local function PLRole(unit)
        if type(UnitGroupRolesAssigned) ~= "function" then return "NONE" end
        local ok, role = pcall(UnitGroupRolesAssigned, unit)
        if not ok or PLSecret(role) or type(role) ~= "string" then return "NONE" end
        return role
    end
    local function PLTankUnit()
        for _, unit in ipairs(PLRosterUnits()) do
            if PLRole(unit) == "TANK" then return unit end
        end
    end
    local function PLAdjustedThreshold(context, unit, base)
        if PLRole(unit) == "DAMAGER" then base = base - (context.dpsThresholdOffset or 10) end
        return math.max(0, base)
    end
    local function PLSubgroup(unit)
        if unit == "player" or unit:match("^party%d+$") then return "party" end
        local index = tonumber(unit:match("^raid(%d+)$"))
        return index and ("raid" .. math.floor((index - 1) / 5 + 1)) or nil
    end
    local function PLEligiblePairUnit(unit)
        if not PLExists(unit) then return false end
        if PLBool(UnitIsDeadOrGhost, unit) == true then return false end
        if unit ~= "player" then
            local assist = PLBool(UnitCanAssist, "player", unit)
            local friend = PLBool(UnitIsFriend, "player", unit)
            if assist == false or friend == false or (assist == nil and friend == nil) then return false end
        end
        return true
    end
    local function PLVigilUnit()
        local record = paladinHealing.vigil
        if not record or record.expires <= PLNow() then paladinHealing.vigil = nil; return nil end
        return PLUnitForKey(record.key) or record.unit
    end
    local function PLManualSpell(profile)
        return PLPreferred(profile, { "Holy Light", "Holy Shock", "Flash of Light" }, true)
    end

    function advanced.HealingEngineCastSucceeded(spell)
        if type(spell) ~= "string" or PLSecret(spell) then return end
        local profile = root.S and root.S() or {}
        if type(profile) ~= "table" or PLSecret(profile.healingEngine)
            or profile.healingEngine ~= true then return end
        local now, unit = PLNow(), PLHealingUnit()
        if spell == "Oath of Light" then
            unit = unit or PLTankUnit()
            if unit then
                for _, member in ipairs(PLRosterUnits()) do
                    PLClearEffects(member, { "Oath of Light" })
                end
                PLSetEffect(unit, spell, 300)
                paladinHealing.oath = { unit = unit, key = PLUnitKey(unit), expires = now + 300 }
            end
        elseif spell == "Blessing of Kings" or spell == "Greater Blessing of Kings" then
            unit = unit or "player"
            if spell == "Greater Blessing of Kings" then
                local class = PLUnitClass(unit)
                for _, member in ipairs(PLRosterUnits()) do
                    if not class or PLUnitClass(member) == class then
                        PLSetEffect(member, spell, 3600)
                    end
                end
            else
                PLSetEffect(unit, spell, 3600)
            end
            paladinHealing.lastBlessing = { spell = spell, unit = unit, at = now }
        elseif PL_AURA_BY_SETTING.RETRIBUTION == spell
            or PL_AURA_BY_SETTING.DEVOTION == spell
            or PL_AURA_BY_SETTING.CONCENTRATION == spell then
            PLClearEffects("player", PL_AURAS)
            PLSetEffect("player", spell, 3600)
        else
            local isSeal = false
            for _, seal in ipairs(PL_SEALS) do
                if seal == spell then isSeal = true; break end
            end
            if isSeal then
                PLClearEffects("player", PL_SEALS)
                PLSetEffect("player", spell, 30)
            end
        end
        if spell == "Divine Favor" then
            paladinHealing.favorActive = true
            paladinHealing.favorChangedAt = now
            paladinHealing.cooldowns[spell] = now + 120
        elseif spell == "Light's Vigil" then
            unit = unit or "player"
            paladinHealing.vigil = { unit = unit, key = PLUnitKey(unit), expires = now + 30 }
            paladinHealing.cooldowns[spell] = now + 6
        elseif spell == "Holy Shock" then
            local marked = PLVigilUnit()
            if marked and unit and PLSameUnit(marked, unit) then
                paladinHealing.vigil = nil
            else
                paladinHealing.cooldowns[spell] = now + 10
            end
            paladinHealing.lastHeal = { spell = spell, unit = unit, at = now }
        elseif spell == "Holy Light" or spell == "Flash of Light" then
            paladinHealing.lastHeal = { spell = spell, unit = unit, at = now }
        elseif spell == "Judgement" then
            paladinHealing.cooldowns[spell] = now + 10
            paladinHealing.lastJudgement = { at = now, seal = PLSelectedSeal(profile) }
        end
        if spell == "Holy Shock" or spell == "Holy Light" or spell == "Flash of Light" then
            paladinHealing.favorActive = false
            paladinHealing.favorChangedAt = now
        end
        if spell == "Holy Light" then paladinHealing.infusionUntil = 0 end
    end

    function advanced.HealingEngineDamagePlan(profile, context)
        if type(profile) ~= "table" or type(context) ~= "table" or not context.enemyCombat then return false end
        if not PLSecret(profile.judgement) and profile.judgement == false then return false end
        local seal = PLSelectedSeal(profile)
        if not seal or not PLPlayerAuraActive(seal, 30) then return false end
        if not PLAvailable("Judgement", profile, false) then return false end
        return {
            spell = "Judgement", reason = "Holy: judge with maintained " .. seal,
            requireReady = false,
        }
    end

    local function PLAppendVigilRequests(critical, profile, context)
        if not PLKnown("Holy Shock") or not PLPermitted("Holy Shock", profile) then return end
        local marked = PLVigilUnit()
        if marked and PLEligiblePairUnit(marked) then
            local subgroup = PLSubgroup(marked)
            for _, secondary in ipairs(PLRosterUnits()) do
                if secondary ~= marked and PLEligiblePairUnit(secondary)
                    and PLSubgroup(secondary) == subgroup then
                    critical[#critical + 1] = {
                        spell = "Holy Shock", reason = "Holy: trigger tracked Light's Vigil",
                        unit = marked, requireReady = false,
                        threshold = context.settings.emergency, visibility = "health",
                        secondaryHealthUnit = secondary,
                        secondaryHealthThreshold = PLAdjustedThreshold(
                            context, secondary, context.settings.emergency),
                    }
                end
            end
            return
        end
        if not PLAvailable("Light's Vigil", profile, true) then return end
        local units = PLRosterUnits()
        for left = 1, #units - 1 do
            local primary = units[left]
            if PLEligiblePairUnit(primary) then
                for right = left + 1, #units do
                    local secondary = units[right]
                    if PLEligiblePairUnit(secondary)
                        and PLSubgroup(primary) == PLSubgroup(secondary) then
                        critical[#critical + 1] = {
                            spell = "Light's Vigil", reason = "Holy: emergency party recovery setup",
                            unit = primary, requireReady = false,
                            threshold = context.settings.emergency, visibility = "health",
                            secondaryHealthUnit = secondary,
                            secondaryHealthThreshold = PLAdjustedThreshold(
                                context, secondary, context.settings.emergency),
                            manaAbove = 50,
                        }
                    end
                end
            end
        end
    end

    function advanced.HealingEnginePlan(profile, context)
        if type(profile) ~= "table" or type(context) ~= "table"
            or PLSecret(profile.healingEngine) or profile.healingEngine ~= true then return nil end
        local now = PLNow()
        if paladinHealing.infusionUntil <= now then paladinHealing.infusionUntil = 0 end
        if paladinHealing.vigil and paladinHealing.vigil.expires <= now then paladinHealing.vigil = nil end
        if paladinHealing.oath and paladinHealing.oath.expires <= now then paladinHealing.oath = nil end

        local manual
        if context.manualTarget then
            local spell = PLManualSpell(profile)
            manual = spell and {
                spell = spell, reason = "Holy: selected ally distress heal",
                requireReady = false,
            } or false
        end

        local maintenance = {}
        if not context.mp5Locked then
            local aura = PLSelectedAura(profile)
            if aura and PLAvailable(aura, profile, true)
                and not PLPlayerAuraActive(aura, 3600) then
                maintenance[#maintenance + 1] = {
                    spell = aura, reason = "Holy: maintain selected healing aura",
                    unit = "player", rangeUnit = "player", visibility = "always",
                    requireReady = false,
                }
            end
            local blessing
            if PLAvailable("Greater Blessing of Kings", profile, true) then
                blessing = "Greater Blessing of Kings"
            elseif PLAvailable("Blessing of Kings", profile, true) then
                blessing = "Blessing of Kings"
            end
            if blessing then
                maintenance[#maintenance + 1] = {
                    spell = blessing, reason = "Holy: maintain " .. blessing,
                    visibility = "always", requireReady = false,
                    unitFilter = function(unit) return not PLKingsActive(unit) end,
                }
            end
            local oathEnabled = not PLSecret(profile.healingOathOfLight)
                and profile.healingOathOfLight ~= false
            local tank = oathEnabled and PLTankUnit() or nil
            if tank and PLAvailable("Oath of Light", profile, true)
                and not PLTrackedAura(tank, "Oath of Light", 300) then
                maintenance[#maintenance + 1] = {
                    spell = "Oath of Light", reason = "Holy: maintain Oath of Light on tank",
                    unit = tank, visibility = "always", requireReady = false,
                }
            end
            if context.enemyCombat then
                local seal = PLSelectedSeal(profile)
                if seal and PLAvailable(seal, profile, true)
                    and not PLPlayerAuraActive(seal, 30) then
                    maintenance[#maintenance + 1] = {
                        spell = seal, reason = "Holy: prepare selected seal for Judgement",
                        unit = "player", rangeUnit = "player", visibility = "always",
                        requireReady = false,
                    }
                end
            end
        end
        if not context.inCombat then
            return { manual = manual == nil and false or manual, maintenance = maintenance }
        end

        local routine = {}
        if PLAvailable("Flash of Light", profile, true) then
            routine[#routine + 1] = {
                spell = "Flash of Light", reason = "Holy: efficient small heal",
                requireReady = false,
            }
        end
        -- HealingEngine draws later requests above earlier requests inside the
        -- same health band, so the confirmed proc wins over the filler.
        if PLInfusionActive() and PLAvailable("Holy Light", profile, true) then
            routine[#routine + 1] = {
                spell = "Holy Light", reason = "Holy: consume confirmed Infusion of Light",
                requireReady = false,
            }
        end

        local emergency = {}
        if PLAvailable("Holy Light", profile, true) then
            emergency[1] = {
                spell = "Holy Light", reason = "Holy: emergency large heal",
                requireReady = false, threshold = context.settings.emergency,
            }
        end

        local critical = {}
        local consumer
        if PLAvailable("Holy Shock", profile, true) then consumer = "Holy Shock"
        elseif PLAvailable("Holy Light", profile, true) then consumer = "Holy Light" end
        if PLFavorActive() and consumer then
            critical[#critical + 1] = {
                spell = consumer, reason = "Holy: consume Divine Favor with " .. consumer,
                requireReady = false, visibility = "health",
                threshold = context.settings.emergency,
            }
        elseif consumer and PLAvailable("Divine Favor", profile, true) then
            critical[#critical + 1] = {
                spell = "Divine Favor", reason = "Holy: emergency guaranteed critical heal",
                rangeUnit = "player", requireReady = false, visibility = "health",
                threshold = context.settings.emergency,
            }
        elseif PLAvailable("Holy Shock", profile, true) then
            critical[#critical + 1] = {
                spell = "Holy Shock", reason = "Holy: emergency instant heal",
                requireReady = false, visibility = "health",
                threshold = context.settings.emergency,
            }
        elseif PLAvailable("Holy Light", profile, true) then
            critical[#critical + 1] = {
                spell = "Holy Light", reason = "Holy: emergency Holy Light",
                requireReady = false, visibility = "health",
                threshold = context.settings.emergency,
            }
        end
        -- These two-health-gate rows are drawn last. They override the
        -- single-target emergency only while both group members need care.
        PLAppendVigilRequests(critical, profile, context)
        return {
            manual = manual,
            maintenance = maintenance,
            routine = routine,
            emergency = emergency,
            critical = critical,
        }
    end

    function advanced.HealingState()
        local now, effects, cooldowns = PLNow(), {}, {}
        for unit, spells in pairs(paladinHealing.effects) do
            effects[unit] = {}
            for spell, expiration in pairs(spells) do
                effects[unit][spell] = math.max(0, expiration - now)
            end
        end
        for _, spell in ipairs({ "Holy Shock", "Divine Favor", "Light's Vigil", "Judgement" }) do
            cooldowns[spell] = math.max(0, (paladinHealing.cooldowns[spell] or 0) - now)
        end
        local engine = root.HealingEngine
        local profile = root.S and root.S() or {}
        return {
            provider = "Holy Paladin",
            aura = PLSelectedAura(profile), seal = PLSelectedSeal(profile),
            divineFavor = PLFavorActive(), infusion = PLInfusionActive(),
            infusionSeconds = math.max(0, paladinHealing.infusionUntil - now),
            vigilUnit = PLVigilUnit(),
            vigilSeconds = paladinHealing.vigil and math.max(0, paladinHealing.vigil.expires - now) or 0,
            oathUnit = paladinHealing.oath and (PLUnitForKey(paladinHealing.oath.key)
                or paladinHealing.oath.unit) or nil,
            oathSeconds = paladinHealing.oath and math.max(0, paladinHealing.oath.expires - now) or 0,
            cooldowns = cooldowns, effects = effects,
            mp5LockSeconds = engine and engine.FiveSecondRuleRemaining
                and engine:FiveSecondRuleRemaining() or 0,
            lastHeal = paladinHealing.lastHeal,
            lastBlessing = paladinHealing.lastBlessing,
            lastJudgement = paladinHealing.lastJudgement,
        }
    end

    -- Infusion of Light is only inferred from an observed critical heal. If
    -- combat-log or aura data is unavailable, Holy Light remains emergency-only
    -- rather than guessing that the proc exists.
    local paladinHealingEvents = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "COMBAT_LOG_EVENT_UNFILTERED" }) do
        if event ~= "COMBAT_LOG_EVENT_UNFILTERED" or type(CombatLogGetCurrentEventInfo) == "function" then
            pcall(paladinHealingEvents.RegisterEvent, paladinHealingEvents, event)
        end
    end
    paladinHealingEvents:SetScript("OnEvent", function(_, event)
        if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then
            paladinHealing.effects = {}
            paladinHealing.applied = {}
            paladinHealing.vigil = nil
            paladinHealing.oath = nil
            paladinHealing.favorActive = false
            paladinHealing.favorChangedAt = 0
            paladinHealing.infusionUntil = 0
            paladinHealing.infusionChangedAt = 0
            return
        end
        if type(CombatLogGetCurrentEventInfo) ~= "function" then return end
        local ok, data = pcall(function() return { CombatLogGetCurrentEventInfo() } end)
        if not ok or type(data) ~= "table" then return end
        local subevent, sourceGUID = data[2], data[4]
        if PLSecret(subevent) or subevent ~= "SPELL_HEAL" or PLSecret(sourceGUID) then return end
        local playerGUID = type(UnitGUID) == "function" and select(2, pcall(UnitGUID, "player")) or nil
        if PLSecret(playerGUID) or type(playerGUID) ~= "string" or sourceGUID ~= playerGUID then return end
        local spellID, spellName, critical = PLNumber(data[12]), data[13], data[18]
        if PLSecret(spellName) then spellName = nil end
        if type(spellName) == "string" then
            spellName = (root.englishNames and root.englishNames[spellName]) or spellName
        end
        local eligible = spellName == "Holy Shock" or spellName == "Flash of Light"
            or spellID == 1311606 or spellID == 20473 or spellID == 20929 or spellID == 20930
            or spellID == 19750 or spellID == 19939 or spellID == 19940
            or spellID == 19941 or spellID == 19942 or spellID == 19943
        if eligible and not PLSecret(critical) and critical == true then
            paladinHealing.infusionUntil = PLNow() + 15
            paladinHealing.infusionChangedAt = PLNow()
        end
    end)

    root.RegisterRotation("PALADIN", advanced)
end
