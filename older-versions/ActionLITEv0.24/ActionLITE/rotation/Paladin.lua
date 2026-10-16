local ADDON, AL = ...

-- WoW Forever Paladin Retribution / Protection leveling 1-30
-- ActionLITE Paladin v0.11.3
-- Cible : beta 1.60.1.69913
-- Statut : LIKELY jusqu'a validation directe des couts, rangs et talents.
-- Les valeurs protegees ne sont jamais assimilees a zero.

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

-- IDs de rang 1 classiques utilises uniquement comme repli d'icone. Holy
-- Strike est un sort Forever sans identifiant confirme : aucun ID 0 n'est
-- cree ou transmis au framework.
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
	{ 0, "Salvation", resolveLearned = true },
	{ 0, "Mass Salvation", resolveLearned = true },
	{ 0, "Revoke", resolveLearned = true },
	{ 1152, "Purify" },
	{ 7328, "Redemption" },
	{ 7294, "Retribution Aura" },
	{ 25780, "Righteous Fury" },
	{ 20375, "Seal of Command" },
	{ 1311649, "Seal of Fury" },
	{ 20154, "Seal of Righteousness" },
	{ 21082, "Seal of the Crusader" },
	{ 5502, "Sense Undead" },
	{ 2878, "Turn Undead" },
}

local HOLY_STRIKE_ICON = 133667
AL.IconOverrides = AL.IconOverrides or {}
AL.IconOverrides["Holy Strike"] = function()
	if AL.S().hsicon then return HOLY_STRIKE_ICON end
end

-- Niveaux de sorts de classe classiques servant de garde-fous. Les talents
-- (Consecration, Seal of Command) et Holy Strike restent gates uniquement par
-- le spellbook Forever afin de ne pas inventer leur niveau d'acquisition.
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
	["Righteous Fury"] = 16,
	["Blessing of Freedom"] = 18,
	["Exorcism"] = 20,
	["Flash of Light"] = 20,
	["Concentration Aura"] = 22,
	["Sense Undead"] = 22,
	["Turn Undead"] = 24,
}

local Ok, _, Known = AL.LevelGates(MINLEVEL)
M.minLevels = MINLEVEL

local SEALS = { "Seal of Fury", "Seal of Command", "Seal of Righteousness", "Seal of the Crusader" }
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
		AUTO = true, COMMAND = true, RIGHTEOUSNESS = true, FURY = true,
	}, "AUTO")
	if mode == "FURY" and Ok("Seal of Fury") then return "Seal of Fury" end
	if mode == "COMMAND" and Ok("Seal of Command") then return "Seal of Command" end
	if mode == "RIGHTEOUSNESS" and Ok("Seal of Righteousness") then return "Seal of Righteousness" end
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
    pcall(tracker.RegisterEvent, tracker, event)
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
        if s.drink then AddAction(nil, "Drink", { ManaGate(mana, SettingNumber(s, "drinkMana", 30, 0, 80), true) }) end
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
