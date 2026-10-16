local ADDON, AL = ...

-- WoW Forever Hunter leveling 1-30 - v0.9.4
-- Cible : beta 1.60.1.69913
-- Donnees : extraction client 1.60.1.69876 et rotation de reference Hunter.
-- Statut : LIKELY jusqu'a validation directe de chaque mecanique dans Forever.

local A = _G.Action

local M = {
	defaults = {
		aspect = true,
		mark = true,
		sting = true,
		scorpid = false,
		aimed = true,
		arcane = true,
		rapidfire = true,
		callpet = true,
		mendpet = true,
		mongoose = true,
		raptor = true,
		wingclip = true,
		disengage = true,
		concussive = true,
		survivalMelee = false,
		aoe = false,
		drink = true,
		petMendHP = 50,
		drinkMana = 30,
		markMinTargetHP = 45,
		stingMinTargetHP = 35,
		arcaneMinMana = 20,
		aoeMinEnemies = 2,
		burstMinTargetHP = 40,
	},
}

-- IDs de rang 1 utilises pour identifier les sorts et fournir leurs icones.
M.spells = {
	{ 19434, "Aimed Shot" },
	{ 3044, "Arcane Shot" },
	{ 5118, "Aspect of the Cheetah" },
	{ 13165, "Aspect of the Hawk" },
	{ 13163, "Aspect of the Monkey" },
	{ 75, "Auto Shot" },
	{ 1462, "Beast Lore" },
	{ 883, "Call Pet" },
	{ 5116, "Concussive Shot" },
	{ 781, "Disengage" },
	{ 20736, "Distracting Shot" },
	{ 6197, "Eagle Eye" },
	{ 1002, "Eyes of the Beast" },
	{ 6991, "Feed Pet" },
	{ 1499, "Freezing Trap" },
	{ 1130, "Hunter's Mark" },
	{ 13795, "Immolation Trap" },
	{ 136, "Mend Pet" },
	{ 1495, "Mongoose Bite" },
	{ 2643, "Multi-Shot" },
	{ 3045, "Rapid Fire" },
	{ 2973, "Raptor Strike" },
	{ 982, "Revive Pet" },
	{ 1513, "Scare Beast" },
	{ 3043, "Scorpid Sting" },
	{ 1978, "Serpent Sting" },
	{ 0, "Summon Hawk" }, -- ID Forever encore TODO ; detection par nom uniquement.
	{ 1515, "Tame Beast" },
	{ 2974, "Wing Clip" },
}

-- Le spellbook Forever peut exposer des sorts avant leur apprentissage reel.
local MINLEVEL = {
	["Auto Shot"] = 1,
	["Raptor Strike"] = 1,
	["Serpent Sting"] = 4,
	["Aspect of the Monkey"] = 4,
	["Arcane Shot"] = 6,
	["Hunter's Mark"] = 6,
	["Concussive Shot"] = 8,
	["Aspect of the Hawk"] = 10,
	["Call Pet"] = 10,
	["Tame Beast"] = 10,
	["Feed Pet"] = 10,
	["Summon Hawk"] = 10,
	["Revive Pet"] = 12,
	["Mend Pet"] = 12,
	["Wing Clip"] = 12,
	["Distracting Shot"] = 12,
	["Scare Beast"] = 14,
	["Mongoose Bite"] = 16,
	["Immolation Trap"] = 16,
	["Eagle Eye"] = 16,
	["Multi-Shot"] = 18,
	["Freezing Trap"] = 20,
	["Aimed Shot"] = 20,
	["Disengage"] = 20,
	["Aspect of the Cheetah"] = 20,
	["Eyes of the Beast"] = 20,
	["Scorpid Sting"] = 22,
	["Beast Lore"] = 24,
	["Rapid Fire"] = 26,
}

local Ok, _, Known = AL.LevelGates(MINLEVEL)
M.minLevels = MINLEVEL


-- Readable percentages use Lua comparisons. Protected percentages are passed
-- through native curves to the existing icon/mini-icon/key/glow display.
local lastRotation
local visibilityCurves, curveFailures = {}, {}
local manaMaximumCache
local mendPetLockUntil, petCallLockUntil, sharedShotUntil = 0, 0, 0
local aimedMultiUntil, movementEventActive = 0, nil
local mongooseUntil, autoShotPendingUntil = 0, 0
local petEpoch = 0
local autoShotEventActive = false
local lastTargetSwapTime = 0
local survivalSpec = false
local closeTargetFeedback, lastAutoShotAttempt
local CLOSE_TARGET_FEEDBACK_SECONDS = 8

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

local function Ready(name)
    if (name == "Arcane Shot" or name == "Summon Hawk") and GetTime() < sharedShotUntil then return false end
    if (name == "Aimed Shot" or name == "Multi-Shot") and aimedMultiUntil > 0 then
        if GetTime() < aimedMultiUntil then return false end
        local start, duration = SafeCall(AL.SpellCooldown, name)
        -- The core's old Multi-Shot fallback is ten seconds. Our observed
        -- shared cooldown owns the fallback when live cooldowns are protected.
        if Number(start) == nil or Number(duration) == nil then return Ok(name) end
    end
    return Ok(name) and AL.IsReady(name)
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

local function Offer(name, reason, gates, procOnly)
    if not Ready(name) then return false end
    local usable, shortage = SpellUsability(name)
    if usable == false or shortage == true then return false end
    if procOnly and usable ~= true and GetTime() >= mongooseUntil then return false end
    if Bool((SafeCall(AL.InRange, name))) == false then return false end
    local conditions = {}
    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
    conditions[#conditions + 1] = Affordable(name, usable, shortage)
    return AddAction(name, reason, conditions)
end

local function PetState()
    local exists = Bool((SafeCall(UnitExists, "pet")))
    if exists == false then return false, false, "MISSING" end
    if exists ~= true then return false, false, "UNKNOWN" end
    local dead = Bool((SafeCall(UnitIsDeadOrGhost, "pet")))
    if dead == nil then return false, false, "UNKNOWN" end
    return not dead, dead, dead and "DEAD" or "ACTIVE"
end

local function TargetTargetsPlayer()
    return Bool((SafeCall(UnitIsUnit, "targettarget", "player"))) == true
end

local function BestAspect(reason)
    Offer("Aspect of the Hawk", reason)
    Offer("Aspect of the Monkey", reason)
end

local function AnyAspectActive()
    return AL.HasBuff("player", "Aspect of the Hawk") or AL.HasBuff("player", "Aspect of the Monkey")
        or AL.HasBuff("player", "Aspect of the Cheetah")
end

local function CombatAspectNeeded()
    return AL.HasBuff("player", "Aspect of the Cheetah") or not AnyAspectActive()
end

local RANGED_ATTACKS = { "Aimed Shot", "Arcane Shot", "Serpent Sting", "Scorpid Sting", "Concussive Shot", "Multi-Shot" }

local function AutoShotInRange()
    if Known("Auto Shot") then return Bool((SafeCall(AL.InRange, "Auto Shot"))) end
end

local function RangedInRange()
    -- Auto Shot establishes the ordinary ranged band. A Sting usable closer
    -- to the target must not prevent melee fallback when Auto Shot is too close.
    local range = AutoShotInRange()
    if range ~= nil then return range end
    for _, name in ipairs(RANGED_ATTACKS) do
        if Known(name) and Bool((SafeCall(AL.InRange, name))) == true then return true end
    end
    return false
end

local function TargetDistance()
    local squared, checked = SafeCall(UnitDistanceSquared, "target")
    squared = Number(squared)
    if squared and squared >= 0 and Bool(checked) == true then
        local distance = math.sqrt(squared)
        return distance, distance
    end
    local unit = A and SafeCall(A.Unit, "target")
    if SafeValue(unit) and (type(unit) == "table" or type(unit) == "userdata") then
        local first, second = SafeCall(unit.GetRange, unit)
        local distance, other = Number(first), Number(second)
        if not SafeValue(second) then return end
        local minimum = distance
        if distance and other and other >= 0 then
            distance, minimum = math.max(distance, other), math.min(distance, other)
        end
        if distance and distance > 0 then return distance, minimum end
    end
end

local function TargetGUID()
    local guid = SafeCall(UnitGUID, "target")
    if SafeValue(guid) and type(guid) == "string" then return guid end
end

local function CloseTargetFeedback()
    local feedback = closeTargetFeedback
    if not feedback then return false end
    local _, minimum = TargetDistance()
    if GetTime() - feedback.at >= CLOSE_TARGET_FEEDBACK_SECONDS
        or TargetGUID() ~= feedback.targetGUID or minimum and minimum > 5 then
        closeTargetFeedback = nil
        return false
    end
    local range = AutoShotInRange()
    if range == false then feedback.wasOutOfRange = true end
    if range == true and (feedback.rangeAtError ~= true or feedback.wasOutOfRange) then
        closeTargetFeedback = nil
        return false
    end
    return true
end

local function InMelee()
    -- Instant melee attacks provide a range check independent of Raptor's
    -- next-swing queue, which can be accepted before the target reaches melee.
    for _, name in ipairs({ "Wing Clip", "Mongoose Bite" }) do
        if Known(name) and Bool((SafeCall(AL.InRange, name))) == true then return true end
    end
    local distance, minimum = TargetDistance()
    if distance and distance <= 5 then return true end
    if minimum and minimum > 5 then return false end
    -- A positive Raptor queue/range flag needs a paired close check or an
    -- explicitly exposed melee range before it can establish close distance.
    if Known("Raptor Strike") then
        local id = LearnedID("Raptor Strike") or "Raptor Strike"
        local raptorRange = Bool((SafeCall(AL.InRange, "Raptor Strike")))
        -- Low-level Hunters have neither Wing Clip nor Mongoose Bite. Raptor
        -- need not expose min/max metadata: pair its positive check with an
        -- out-of-range Auto Shot and the close interact band. Neither the
        -- queue flag nor the broad interact check alone selects melee.
        if distance == nil and raptorRange == true and AutoShotInRange() == false
            and Bool((SafeCall(CheckInteractDistance, "target", 3))) == true then return true end
        local hasRange = Bool((SafeCall(C_Spell and C_Spell.SpellHasRange or SpellHasRange, id)))
        local info = SafeCall(C_Spell and C_Spell.GetSpellInfo, id)
        local maximum = SafeValue(info) and type(info) == "table" and Number(info.maxRange)
        if hasRange == true and maximum and maximum > 0 and maximum <= 5 then
            return raptorRange == true
        end
    end
    return false
end

local function RefreshSurvivalSpec()
    survivalSpec = false
    local reader = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
    local index = Number((SafeCall(reader)))
    if index and index >= 1 and index <= 3 then
        local infoReader = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo
        local id = Number((SafeCall(infoReader, index, false, false)))
        if id == 255 then survivalSpec = true; return end
        if id == 253 or id == 254 then return end
    end
    -- Classic talent builds have no explicit selected specialization. Only a
    -- unique, positive highest point count identifies the third Hunter tree.
    local points = {}
    for tab = 1, 3 do
        points[tab] = SafeCall(function()
            local modern = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
            if type(modern) == "function" then
                local spent = SafeCall(function()
                    local _, _, _, _, _, _, amount = modern(tab, false, false)
                    return Number(amount)
                end)
                if spent ~= nil then return spent end
            end
            if type(GetTalentTabInfo) == "function" then
                local first, _, third, _, fifth = GetTalentTabInfo(tab, false, false)
                if SafeValue(first) and type(first) == "string" then return Number(third) end
                if Number(first) then return Number(fifth) end
            end
        end)
        if not points[tab] or points[tab] < 0 then return end
    end
    survivalSpec = points[3] > 0 and points[3] > points[1] and points[3] > points[2]
end

local function PreferMelee(s)
    return survivalSpec or Bool(s and s.survivalMelee) == true
end

local function UseMelee(s)
    -- Client feedback can disambiguate an active Auto Shot whose range read
    -- is unavailable or still says true after the target has closed in.
    if CloseTargetFeedback() then return true end
    return InMelee() and (PreferMelee(s) or not RangedInRange())
end

local function ActiveEnemyCount(limit)
    local count
    if A and A.MultiUnits then
        local units = A.MultiUnits
        local first = Number((SafeCall(units.GetActiveEnemies, units, 5)))
        local second = Number((SafeCall(units.GetByRangeInCombat, units, nil, limit or 5)))
        for _, value in pairs({ first, second }) do
            if value >= 0 and value <= 40 and value == math.floor(value) then count = math.max(count or 0, value) end
        end
    end
    -- When the framework count is absent or smaller, confirm ranged enemies
    -- from visible, hostile units using the learned Auto Shot range.
    local seen, visible = {}, 0
    local function Count(unit)
        if not SafeValue(unit) or type(unit) ~= "string" then return end
        if Bool((SafeCall(UnitExists, unit))) ~= true or Bool((SafeCall(UnitCanAttack, "player", unit))) ~= true
            or Bool((SafeCall(UnitIsDeadOrGhost, unit))) ~= false then return end
        if unit ~= "target" and Bool((SafeCall(UnitAffectingCombat, unit))) ~= true then return end
        local guid = SafeCall(UnitGUID, unit)
        if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] then return end
        local range
        if unit == "target" then range = SafeCall(AL.InRange, "Auto Shot")
        else range = SafeCall(C_Spell and C_Spell.IsSpellInRange, LearnedID("Auto Shot") or "Auto Shot", unit) end
        if not SafeValue(range) or (range ~= true and range ~= 1) then return end
        seen[guid], visible = true, visible + 1
    end
    Count("target")
    local plates = SafeCall(C_NamePlate and C_NamePlate.GetNamePlates)
    if SafeValue(plates) and type(plates) == "table" then
        for _, plate in pairs(plates) do
            if SafeValue(plate) and type(plate) == "table" then
                Count(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
            end
        end
    end
    if visible > 0 then count = math.max(count or 0, visible) end
    return count
end

local function ActionPlayer()
    return A and type(A.Player) == "table" and A.Player or nil
end

local function PlayerMoving()
    local speed = Number((SafeCall(GetUnitSpeed, "player")))
    if speed ~= nil then return speed > 0 end
    local player = ActionPlayer()
    if player then
        local value = SafeCall(player.IsMoving, player)
        local moving = Bool(value)
        if moving ~= nil then return moving end
        local numeric = Number(value)
        if numeric ~= nil then return numeric > 0 end
    end
    -- Protected speed is unknown. Use movement events when public readers
    -- cannot answer, so a protected value does not block all Aimed Shots.
    return movementEventActive == true
end

local function PlayerIsCastingOrChanneling()
    local player = ActionPlayer()
    if player then
        for _, reader in pairs({ player.IsCasting, player.IsChanneling }) do
            local value = SafeCall(reader, player)
            if not SafeValue(value) or value then return true end
        end
    end
    for _, reader in pairs({ UnitCastingInfo, UnitChannelInfo }) do
        local name = SafeCall(reader, "player")
        if not SafeValue(name) or name ~= nil then return true end
    end
    local name = SafeCall(AL.CastingSpell)
    return type(name) == "string" and SafeValue(name)
end

local function PlayerIsShooting()
    if autoShotEventActive or GetTime() < autoShotPendingUntil then return true end
    local player = ActionPlayer()
    if player and Bool((SafeCall(player.IsShooting, player))) == true then return true end
    local id = LearnedID("Auto Shot") or 75
    return Bool((SafeCall(IsAutoRepeatSpell, id))) == true or Bool((SafeCall(IsCurrentSpell, id))) == true
end

local function EnsureAutoShot()
    if not Ready("Auto Shot") or Bool((SafeCall(AL.InRange, "Auto Shot"))) == false
        or PlayerIsCastingOrChanneling() or PlayerIsShooting() then return false end
    local player = ActionPlayer()
    local timer = player and Number((SafeCall(player.GetSwingShoot, player)))
    return timer == nil or timer <= 0 or GetTime() - lastTargetSwapTime <= 0.75
end

local function Mend(s, petUp, reason)
    if s.mendpet and petUp and GetTime() >= mendPetLockUntil then
        Offer("Mend Pet", reason, { HealthGate("pet", HealthPercent("pet"),
            SettingNumber(s, "petMendHP", 50, 20, 95), true) })
    end
end

local function Mark(s, targetHP, reason)
    if s.mark and not AL.HasDebuff("target", "Hunter's Mark") then
        Offer("Hunter's Mark", reason, { HealthGate("target", targetHP,
            SettingNumber(s, "markMinTargetHP", 45, 0, 100), false) })
    end
end

local function MeleeRotation(s, petUp)
    if s.mongoose then Offer("Mongoose Bite", "melee proc", nil, true) end
    if s.disengage and petUp and TargetTargetsPlayer() then Offer("Disengage", "return threat to pet") end
    if s.wingclip and TargetTargetsPlayer() and not AL.HasDebuff("target", "Wing Clip") then
        Offer("Wing Clip", "create distance")
    end
    if s.raptor and Bool((SafeCall(IsCurrentSpell, LearnedID("Raptor Strike") or "Raptor Strike"))) ~= true then
        Offer("Raptor Strike", "melee strike")
    end
    AddAction(AL.Ok("Attack") and "Attack" or nil, "melee")
end

function M.OnTargetChanged()
    lastRotation, AL.rotationSecretVisual = nil, nil
    lastTargetSwapTime = GetTime()
    closeTargetFeedback, lastAutoShotAttempt = nil, nil
end

function M.OnCastSent(name, sent)
    sent.hunterPetEpoch = petEpoch
    if name == "Auto Shot" then
        autoShotPendingUntil = GetTime() + 1
        lastAutoShotAttempt = { at = GetTime(), targetGUID = TargetGUID() }
    end
end

function M.OnUIError(message)
    if not SafeValue(message) or type(message) ~= "string" then return end
    local localized = _G.SPELL_FAILED_TOO_CLOSE
    local matches = SafeValue(localized) and type(localized) == "string" and message == localized
    if not matches and message ~= "Target too close" then return end
    local guid = TargetGUID()
    if not guid or Bool((SafeCall(UnitCanAttack, "player", "target"))) ~= true
        or Bool((SafeCall(UnitIsDeadOrGhost, "target"))) ~= false then return end
    local attempt = lastAutoShotAttempt
    if not PlayerIsShooting() and not (attempt and attempt.targetGUID == guid
        and GetTime() - attempt.at <= 1) then return end
    local range = AutoShotInRange()
    closeTargetFeedback = { at = GetTime(), targetGUID = guid, rangeAtError = range,
        wasOutOfRange = range == false }
    autoShotPendingUntil = 0
end

function M.OnCastResult(name, event, sent)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
        if name == "Mend Pet" then mendPetLockUntil = 0 end
        if name == "Auto Shot" then autoShotPendingUntil = 0 end
        return
    end
    if name == "Mend Pet" and (not sent or sent.hunterPetEpoch == petEpoch) then mendPetLockUntil = GetTime() + 10 end
    if name == "Call Pet" or name == "Revive Pet" then petCallLockUntil = GetTime() + 2 end
    if name == "Auto Shot" then
        autoShotPendingUntil = GetTime() + 1
        if not sent or sent.targetGUID == TargetGUID() then closeTargetFeedback = nil end
    end
    if name == "Mongoose Bite" then mongooseUntil = 0 end
    if name == "Aimed Shot" or name == "Multi-Shot" then
        -- Forever pairs Aimed Shot with Multi-Shot, separate from Arcane/Hawk.
        local ms = Number((SafeCall(C_Spell and C_Spell.GetSpellBaseCooldown or GetSpellBaseCooldown, LearnedID(name) or name)))
        local duration = ms and ms > 1500 and ms < 60000 and ms / 1000 or 6
        aimedMultiUntil = GetTime() + duration
    end
    if name == "Arcane Shot" or name == "Summon Hawk" then
        -- The supplied Forever guide specifies the shared six-second recharge.
        local ms = Number((SafeCall(C_Spell and C_Spell.GetSpellBaseCooldown or GetSpellBaseCooldown, LearnedID(name) or name)))
        local duration = ms and ms > 1500 and ms < 60000 and ms / 1000 or 6
        sharedShotUntil = GetTime() + duration
    end
end

function M.CanTrackSuggestedSpell(name)
    if not lastRotation or GetTime() - lastRotation.at > 0.5 or lastRotation.visualCandidate then return false end
    local visual = AL.rotationSecretVisual
    if visual and GetTime() - visual.at <= 0.5 then return false end
    if name ~= lastRotation.baseSpell or not Ok(name) then return false end
    for _, entry in ipairs(M.spells) do if entry[2] == name then return true end end
end

RefreshSurvivalSpec()
local tracker = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ENTERING_WORLD", "START_AUTOREPEAT_SPELL",
    "STOP_AUTOREPEAT_SPELL", "UNIT_PET", "UNIT_SPELLCAST_CHANNEL_STOP", "COMBAT_LOG_EVENT_UNFILTERED",
    "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_REGEN_ENABLED", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" }) do
    pcall(tracker.RegisterEvent, tracker, event)
end
tracker:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED" and SafeValue(unit) and unit == "player" then RefreshSurvivalSpec()
    elseif event == "PLAYER_STARTED_MOVING" then movementEventActive = true
    elseif event == "PLAYER_STOPPED_MOVING" then movementEventActive = false
    elseif event == "START_AUTOREPEAT_SPELL" then autoShotEventActive, autoShotPendingUntil = true, 0
    elseif event == "STOP_AUTOREPEAT_SPELL" then autoShotEventActive, autoShotPendingUntil = false, 0
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
        mendPetLockUntil, petCallLockUntil, sharedShotUntil, mongooseUntil, autoShotPendingUntil = 0, 0, 0, 0, 0
        aimedMultiUntil, movementEventActive = 0, nil
        autoShotEventActive, lastRotation, AL.rotationSecretVisual = false, nil, nil
        closeTargetFeedback, lastAutoShotAttempt = nil, nil
        curveFailures, manaMaximumCache = {}, nil
        RefreshSurvivalSpec()
    elseif event == "PLAYER_REGEN_ENABLED" then
        closeTargetFeedback, lastAutoShotAttempt = nil, nil
    elseif event == "UNIT_PET" and SafeValue(unit) and unit == "player" then
        petEpoch, mendPetLockUntil, petCallLockUntil = petEpoch + 1, 0, 0
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" and SafeValue(unit) and unit == "player" then
        mendPetLockUntil = 0
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local ok, _, sub, _, _, _, _, _, destGUID, _, _, _, miss, _, _, spellMiss = pcall(function()
            if type(CombatLogGetCurrentEventInfo) == "function" then return CombatLogGetCurrentEventInfo() end
        end)
        local playerGUID = SafeCall(UnitGUID, "player")
        if ok and SafeValue(sub) and SafeValue(destGUID) and SafeValue(playerGUID)
            and type(playerGUID) == "string" and destGUID == playerGUID then
            local kind = sub == "SWING_MISSED" and miss or (sub == "SPELL_MISSED" or sub == "RANGE_MISSED") and spellMiss
            if SafeValue(kind) and kind == "DODGE" then mongooseUntil = GetTime() + 5 end
        end
    end
end)

function M.NextSpell(s, inCombat, hostile)
    if not inCombat then curveFailures, manaMaximumCache = {}, nil end
    lastRotation = { at = GetTime(), actions = {} }
    local petUp, petDead, petStatus = PetState()
    local manaPercent = Percent((SafeCall(AL.ManaPercent)))
    local targetHP = hostile and HealthPercent("target") or nil
    if PlayerIsCastingOrChanneling() then
        AddAction(nil, "Casting")
    elseif not inCombat then
        if s.aspect and not AnyAspectActive() then BestAspect("aspect") end
        if s.callpet and GetTime() >= petCallLockUntil then
            if petDead then Offer("Revive Pet", "pet dead")
            elseif petStatus == "MISSING" then Offer("Call Pet", "pet missing") end
        end
        Mend(s, petUp, "heal pet")
        if s.drink then AddAction(nil, "Drink", { ManaGate(manaPercent, SettingNumber(s, "drinkMana", 30, 0, 80), true) }) end
        if hostile then
            Mark(s, targetHP, petUp and "mark and send pet" or "mark")
            if UseMelee(s) then MeleeRotation(s, petUp)
            elseif EnsureAutoShot() then Offer("Auto Shot", "opener") end
        end
    else
        Mend(s, petUp, "pet low")
        if hostile then
            if s.aspect and CombatAspectNeeded() then BestAspect("combat aspect") end
            -- Ranged attacks win overlapping range checks by default. Close
            -- client feedback can release a stalled ranged state to melee.
            if UseMelee(s) then MeleeRotation(s, petUp)
            else
                Mark(s, targetHP, "mark")
                if AL.burst and s.rapidfire and not AL.HasBuff("player", "Rapid Fire") then
                    Offer("Rapid Fire", "burst", { HealthGate("target", targetHP,
                        SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false) })
                end
                if s.concussive and TargetTargetsPlayer() then Offer("Concussive Shot", "keep distance") end
                local minimum = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
                local count = s.aoe and ActiveEnemyCount(minimum)
                if count and count >= minimum then Offer("Multi-Shot", "aoe") end
                local stingGate = HealthGate("target", targetHP, SettingNumber(s, "stingMinTargetHP", 35, 0, 100), false)
                if not AL.HasDebuff("target", "Serpent Sting") and not AL.HasDebuff("target", "Scorpid Sting") then
                    local preferScorpid = s.scorpid and Ok("Scorpid Sting")
                    if preferScorpid then Offer("Scorpid Sting", "weaken attacks", { stingGate })
                    elseif s.sting then Offer("Serpent Sting", "damage over time", { stingGate }) end
                end
                if s.aimed and not PlayerMoving() then Offer("Aimed Shot", "aimed shot") end
                Offer("Summon Hawk", "hawk", { HealthGate("target", targetHP, 40, false) })
                if s.arcane then Offer("Arcane Shot", "ranged filler", {
                    ManaGate(manaPercent, SettingNumber(s, "arcaneMinMana", 20, 0, 80), false) }) end
                if EnsureAutoShot() then Offer("Auto Shot", "start auto shot") end
            end
        end
    end
    AddAction(nil, not hostile and inCombat and "No target" or inCombat and "auto shot active" or "Ready")
    local base = lastRotation.actions[#lastRotation.actions]
    lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
    return base.spell, base.reason
end

function M.GetUIState()
    local petUp, _, status = PetState()
    local knownCount = 0
    for _, entry in ipairs(M.spells) do if Known(entry[2]) then knownCount = knownCount + 1 end end
    local unit = A and SafeCall(A.Unit, "target")
    local ttd
    if SafeValue(unit) and (type(unit) == "table" or type(unit) == "userdata") then
        ttd = Number((SafeCall(unit.TimeToDie, unit)))
        if ttd and (ttd <= 0 or ttd >= 500) then ttd = nil end
    end
    return { level = Number((SafeCall(UnitLevel, "player"))), mana = Percent((SafeCall(AL.ManaPercent))),
        petHP = petUp and HealthPercent("pet") or nil, petState = status, knownCount = knownCount,
        enemyCount = ActiveEnemyCount(SettingNumber(AL.S(), "aoeMinEnemies", 2, 2, 5)), targetTTD = ttd }
end

if AL.selfCastSpells then
    for _, name in ipairs({ "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah",
        "Call Pet", "Revive Pet", "Mend Pet", "Rapid Fire" }) do AL.selfCastSpells[name] = true end
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
				error("Hunter resource curve unavailable")
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


AL.RegisterRotation("HUNTER", M)
