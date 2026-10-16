local ADDON, AL = ...

-- ActionLITE Hunter v0.13.3: original Leveling plus optional talent builds.

-- Leveling keeps the finalized pre-simulation implementation in its own
-- scope. Talent builds use the separate implementation below. Both observe
-- real casts so switching rotations retains resource and spell history.
do
    local root = AL
    local leveling, advanced
    local function UsesLeveling(profile)
        profile = profile or (root.Profile and root.Profile("HUNTER")) or (root.S and root.S())
        if advanced and type(profile) == "table" then
            return advanced.NormalizeBuild(profile) == "leveling"
        end
        return true
    end
    local function RotationScope(isLeveling)
        local scope = {
            RegisterRotation = function(token, module)
                assert(token == "HUNTER", "Unexpected class rotation")
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
                    if root.playerClass == "HUNTER" and UsesLeveling() == isLeveling then root[key] = value end
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
-- BEGIN ORIGINAL LEVELING IMPLEMENTATION (Hunter(3).lua)
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
-- END ORIGINAL LEVELING IMPLEMENTATION
    end)(ADDON, RotationScope(true))

    ;(function(...)
-- BEGIN OPTIONAL TALENT BUILD IMPLEMENTATION
local ADDON, AL = ...

-- WoW Forever Hunter leveling 1-60 - v0.13.3
-- Beast Mastery 31/20/0, Marksmanship 5/31/15 and Survival 5/11/35.
-- Reference: MythicSim Forever 944a791060db (1.60.1.70338).
-- Validate the learned-spell rotation in the live Forever client.

local A = _G.Action

local M = {
	defaults = {
        leveling = true,
		beastMastery = false,
		beastStingMinMana = 30, beastHawkMinMana = 0,
		beastBurstMinMana = 35, beastAoEMinMana = 35, beastVolleyMinEnemies = 4,
		bestialWrath = true, intimidation = false,
		beastBerserking = true, beastElune = true,
		aspect = true,
		marksmanship = false,
		marksmanshipNoPet = true,
		trueshot = true,
		sniper = true,
		sniperMinMana = 30,
		marksmanshipStingMinMana = 30,
		survival = false,
		survivalNoPet = true,
		striderKick = true,
		summonHawk = true,
		immolationTrap = true,
		explosiveTrap = true,
		volley = false,
		bloodFury = true,
		survivalWingFiller = true,
		survivalMinMana = 0,
		trapMinMana = 20,
		trapMinTargetHP = 25,
		volleyMinMana = 35,
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
-- Exactly one rotation stays selected. Leveling is the default and the
-- fallback when a selected specialization is switched off or saved flags
-- conflict. A valid saved specialization takes priority during migration.
M.buildKeys = { "leveling", "beastMastery", "marksmanship", "survival" }
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
    s = s or AL.Profile("HUNTER")
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
	{ 19434, "Aimed Shot" },
	{ 3044, "Arcane Shot" },
	{ 5118, "Aspect of the Cheetah" },
	{ 13165, "Aspect of the Hawk" },
	{ 13163, "Aspect of the Monkey" },
	{ 13161, "Aspect of the Beast" },
	{ 20572, "Blood Fury" },
	{ 75, "Auto Shot" },
	{ 1462, "Beast Lore" },
	{ 19574, "Bestial Wrath" },
	{ 20554, "Berserking" },
	{ 883, "Call Pet" },
	{ 5116, "Concussive Shot" },
	{ 781, "Disengage" },
	{ 2641, "Dismiss Pet" },
	{ 20736, "Distracting Shot" },
	{ 6197, "Eagle Eye" },
	{ 1259799, "Elune's Light" },
	{ 1002, "Eyes of the Beast" },
	{ 6991, "Feed Pet" },
	{ 1499, "Freezing Trap" },
	{ 1130, "Hunter's Mark" },
	{ 13795, "Immolation Trap" },
	{ 13813, "Explosive Trap" },
	{ 19577, "Intimidation" },
	{ 136, "Mend Pet" },
	{ 1495, "Mongoose Bite" },
	{ 2643, "Multi-Shot" },
	{ 3045, "Rapid Fire" },
	{ 2973, "Raptor Strike" },
	{ 982, "Revive Pet" },
	{ 1513, "Scare Beast" },
	{ 3043, "Scorpid Sting" },
	{ 1978, "Serpent Sting" },
	{ 1310687, "Sniper Shot" },
	{ 1293241, "Summon Hawk" },
	{ 1317257, "Strider Kick" },
	{ 1510, "Volley" },
	{ 1515, "Tame Beast" },
	{ 1299346, "Trueshot Aura" },
	{ 2974, "Wing Clip" },
}

-- Le spellbook Forever peut exposer des sorts avant leur apprentissage reel.
local MINLEVEL = {
	["Bestial Wrath"] = 40,
	["Intimidation"] = 30,
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
	["Summon Hawk"] = 25,
	["Trueshot Aura"] = 25,
	["Sniper Shot"] = 40,
	["Dismiss Pet"] = 10,
	["Aspect of the Beast"] = 30,
	["Strider Kick"] = 30,
	["Explosive Trap"] = 34,
	["Volley"] = 40,
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
local mendPetLockUntil, petCallLockUntil = 0, 0
local movementEventActive
local mongooseUntil, autoShotPendingUntil = 0, 0
local petEpoch = 0
local autoShotEventActive = false
local lastTargetSwapTime = 0
local survivalSpec = false
local closeTargetFeedback, lastAutoShotAttempt
local CLOSE_TARGET_FEEDBACK_SECONDS = 8
local controlEnds, controlCastAt, controlRetry = {}, {}, {}
local raptorPendingUntil, dismissPendingUntil, raptorPendingGUID = 0, 0, nil
local aspectState, aspectChangedAt, aspectCache, aspectAurasBlocked
local loneWolfKnown, loneWolfChecked
local hunterTalentRanks
local trueshotExpires, trueshotChangedAt, trueshotCache, trueshotAurasBlocked = 0, nil, nil, nil
local controlBase = { ["Raptor Strike"]=6, ["Mongoose Bite"]=5, ["Strider Kick"]=8,
    ["Immolation Trap"]=30, ["Explosive Trap"]=30, ["Rapid Fire"]=300, ["Blood Fury"]=120,
    ["Arcane Shot"]=6, ["Summon Hawk"]=6, ["Aimed Shot"]=6, ["Multi-Shot"]=6,
    ["Sniper Shot"]=15, ["Bestial Wrath"]=120, ["Intimidation"]=60,
    ["Berserking"]=180, ["Elune's Light"]=180 }
local cooldownPairs = { ["Arcane Shot"]="Summon Hawk", ["Summon Hawk"]="Arcane Shot",
    ["Aimed Shot"]="Multi-Shot", ["Multi-Shot"]="Aimed Shot",
    ["Immolation Trap"]="Explosive Trap", ["Explosive Trap"]="Immolation Trap" }
local aspectNames = { ["Aspect of the Hawk"]=true, ["Aspect of the Beast"]=true,
    ["Aspect of the Monkey"]=true, ["Aspect of the Cheetah"]=true }
local castIDs = {
    ["Bestial Wrath"]={19574}, ["Intimidation"]={19577},
    ["Berserking"]={20554,26297}, ["Elune's Light"]={1259799},
    ["Raptor Strike"]={2973,14260,14261,14262,14263,14264,14265,14266},
    ["Mongoose Bite"]={1495,14269,14270,14271}, ["Strider Kick"]={1317257},
    ["Immolation Trap"]={13795,14302,14303,14304,14305},
    ["Explosive Trap"]={13813,14316,14317}, ["Rapid Fire"]={3045}, ["Blood Fury"]={20572},
    ["Aspect of the Beast"]={13161,1299445,1299446,1299447},
    ["Aspect of the Hawk"]={13165,14318,14319,14320,14321,14322,25296},
    ["Aspect of the Monkey"]={13163}, ["Aspect of the Cheetah"]={5118}, ["Dismiss Pet"]={2641},
    ["Arcane Shot"]={3044,14281,14282,14283,14284,14285,14286,14287},
    ["Summon Hawk"]={1293241,1293525,1293526,1293527},
    ["Aimed Shot"]={19434,20900,20901,20902,20903,20904},
    ["Multi-Shot"]={2643,14288,14289,14290},
    ["Sniper Shot"]={1310687,1310785,1310786},
    ["Trueshot Aura"]={1299346,1299348,19506,20905,20906},
}

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
local function BeastMastery(s) return s and Bool(s.beastMastery) == true end
local function Marksmanship(s) return s and Bool(s.marksmanship) == true and not BeastMastery(s) end
-- UI clicks are exclusive. If an old/imported profile has both flags, the
-- explicit ranged build wins without overwriting the saved Survival options.
local function Survival(s) return s and Bool(s.survival) == true and not Marksmanship(s) and not BeastMastery(s) end
local function ReferenceBuild(s) return BeastMastery(s) or Marksmanship(s) or Survival(s) end
local function NoPet(s)
    if BeastMastery(s) then return false end
    local enabled = Marksmanship(s) and Bool(s.marksmanshipNoPet)==true
        or Survival(s) and Bool(s.survivalNoPet)==true
    if not enabled then return false end
    if not loneWolfChecked or Bool((SafeCall(UnitAffectingCombat,"player")))~=true then
        local readable,learned=false,false
        for _,reader in pairs({IsPlayerSpell,IsSpellKnown,C_SpellBook and C_SpellBook.IsSpellKnown}) do
            local value=Bool((SafeCall(reader,415370)))
            if value~=nil then readable=true end
            if value==true then learned=true;break end
        end
        if AL.known and AL.known["Lone Wolf"] then learned,readable=true,true end
        if readable then loneWolfKnown=learned end
        loneWolfChecked=true
    end
    return loneWolfKnown==true
end
local function Controlled(name)
    return controlBase[name] and (ReferenceBuild(AL.S()) or name == "Strider Kick" or name == "Sniper Shot"
        or cooldownPairs[name]~=nil or name == "Blood Fury")
end

-- A reference checkbox never grants talents. Native cooldowns win; when they
-- are protected, only a readable actual talent rank may shorten a cast timer.
local function HunterTalentRank(name)
    if hunterTalentRanks then return hunterTalentRanks[name] end
    hunterTalentRanks = {}
    if type(GetTalentInfo)~="function" then return nil end
    for index=1,40 do
        local ok,talent,_,_,_,rank=pcall(GetTalentInfo,2,index,false,false)
        rank=Number(rank)
        if ok and SafeValue(talent) and type(talent)=="string" and rank and rank>=0 and rank<=5 then
            hunterTalentRanks[talent]=rank
            local english=AL.englishNames and AL.englishNames[talent]
            if english then hunterTalentRanks[english]=rank end
        end
    end
    for english,id in pairs({["Rapid Killing"]=415405,["Improved Arcane Shot"]=19454}) do
        local localized=SafeCall(C_Spell and C_Spell.GetSpellName,id)
        if SafeValue(localized) and type(localized)=="string" and hunterTalentRanks[localized]~=nil then
            hunterTalentRanks[english]=hunterTalentRanks[localized]
        end
    end
    return hunterTalentRanks[name]
end
local function ControlDuration(name,base)
    if name=="Rapid Fire" then
        local rank=HunterTalentRank("Rapid Killing")
        if rank and rank<=2 then return math.max(0,base-60*rank) end
    elseif name=="Arcane Shot" then
        local rank=HunterTalentRank("Improved Arcane Shot")
        if rank and rank<=5 then return math.max(0,base-0.3*rank) end
    end
    return base
end
local function NativeCooldown(name)
    local info = SafeCall(C_Spell and C_Spell.GetSpellCooldown, LearnedID(name) or name)
    if SafeValue(info) and type(info) == "table" then return info end
end
local function CooldownEnd(info)
    if not info then return nil end
    local start, duration, rate = Number(info.startTime), Number(info.duration), Number(info.modRate)
    if SafeValue(info.modRate) and info.modRate == nil then rate = 1 end
    if start and start > 0 and duration and duration > 1.5 and rate and rate > 0 then return start + duration / rate end
end
local function SetControlEnd(name, expires)
    controlEnds[name], controlCastAt[name] = expires, GetTime()
    local other=cooldownPairs[name]
    if other then
        controlEnds[other], controlCastAt[other] = expires, GetTime()
    end
end
local function ControlReady(name)
    if (controlRetry[name] or 0) > GetTime() then return false end
    local info = NativeCooldown(name)
    if info then
        if Bool(info.isEnabled) == false then return false end
        local start, duration, rate = Number(info.startTime), Number(info.duration), Number(info.modRate)
        if SafeValue(info.modRate) and info.modRate == nil then rate = 1 end
        local ready
        if start and start >= 0 and duration and duration >= 0 and rate and rate > 0 then
            if BeastMastery(AL.S()) and start>0 and duration>0 and duration<=1.5
                and (controlEnds[name] or 0)>GetTime() then return false end
            ready = start == 0 or duration <= 1.5 or start + duration / rate <= GetTime()
        elseif Bool(info.isActive) == false then ready = true
        elseif Bool(info.isActive) == true and Bool(info.isOnGCD) == false then ready = false end
        if ready ~= nil then
            if ready and controlCastAt[name] and GetTime()-controlCastAt[name] < 0.5
                and (controlEnds[name] or 0) > GetTime() then return false end
            if ready and controlEnds[name] then
                controlEnds[name] = GetTime()
                local other=cooldownPairs[name]
                if other then controlEnds[other]=GetTime() end
            end
            return ready
        end
    end
    if controlEnds[name] then return controlEnds[name] <= GetTime() end
    -- The generic tracker can see a guardian hit or trap trigger with the
    -- cast's name. Only this controller's castable IDs may start its timer.
    return true
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
    if name=="Trueshot Aura" and (controlRetry[name] or 0)>GetTime() then return false end
    if Controlled(name) then return Ok(name) and ControlReady(name) end
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
    if name ~= "Immolation Trap" and name ~= "Explosive Trap" and name ~= "Trueshot Aura"
        and Bool((SafeCall(AL.InRange, name))) == false then return false end
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

local function CastNameFromID(id)
    id = Number(id)
    if not id then return nil end
    for name, ids in pairs(castIDs) do
        if id == LearnedID(name) then return name end
        for _, actual in ipairs(ids) do if id == actual then return name end end
    end
end
local function ActiveAspect()
    local now = GetTime()
    if aspectChangedAt and now-aspectChangedAt < 0.5 then return aspectState end
    if aspectCache and now-aspectCache.at < 0.2 then return aspectCache.name end
    local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not aspectAurasBlocked and type(reader) == "function" then
        local complete = true
        for index=1,40 do
            local ok, aura = pcall(reader,"player",index,"HELPFUL")
            if not ok or not SafeValue(aura) then aspectAurasBlocked = true; break end
            if aura == nil then
                if complete then aspectState = nil; aspectCache={at=now}; return nil end
                break
            end
            if type(aura) ~= "table" then complete = false
            else
                local id, name = Number(aura.spellId), aura.name
                if SafeValue(name) and type(name)=="string" then name=(AL.englishNames and AL.englishNames[name]) or name
                else name=CastNameFromID(id) end
                if name and aspectNames[name] then aspectState=name;aspectCache={at=now,name=name};return name end
                if not id and not name then complete=false end
            end
        end
    end
    if aspectState then return aspectState end
    for name in pairs(aspectNames) do if Bool((SafeCall(AL.HasBuff,"player",name)))==true then return name end end
end
local function TrueshotActive()
    local now=GetTime()
    if trueshotChangedAt and now-trueshotChangedAt<0.5 then return trueshotExpires>now end
    if trueshotCache and now-trueshotCache.at<0.2 then return trueshotCache.active end
    local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not trueshotAurasBlocked and type(reader)=="function" then
        local complete=true
        for index=1,40 do
            local ok,aura=pcall(reader,"player",index,"HELPFUL")
            if not ok or not SafeValue(aura) then trueshotAurasBlocked=true;break end
            if aura==nil then
                if complete then trueshotExpires=0;trueshotCache={at=now,active=false};return false end
                break
            end
            if type(aura)~="table" then complete=false
            else
                local id,name=Number(aura.spellId),aura.name
                if SafeValue(name) and type(name)=="string" then name=(AL.englishNames and AL.englishNames[name]) or name
                else name=CastNameFromID(id) end
                if name=="Trueshot Aura" then
                    local expires=Number(aura.expirationTime)
                    if expires and expires>0 then trueshotExpires=expires
                    elseif trueshotExpires<=now then trueshotExpires=now+1800 end
                    local active=trueshotExpires>now
                    trueshotCache={at=now,active=active};return active
                end
                if not id and not name then complete=false end
            end
        end
    end
    return trueshotExpires>now
end
local function MaintainTrueshot(s)
    if (Marksmanship(s) or BeastMastery(s)) and s.trueshot and not TrueshotActive() then Offer("Trueshot Aura","self buff") end
end
local function BestAspect(reason, s)
    s=s or AL.S()
    if Survival(s) and Ok("Aspect of the Beast") then Offer("Aspect of the Beast",reason); return end
    Offer("Aspect of the Hawk",reason)
    Offer("Aspect of the Monkey",reason)
end
local function AnyAspectActive(s)
    if Marksmanship(s or AL.S()) or BeastMastery(s or AL.S()) then
        local active=ActiveAspect()
        if Ok("Aspect of the Hawk") then return active=="Aspect of the Hawk" end
        return active=="Aspect of the Monkey"
    end
    if Survival(s or AL.S()) then
        local active=ActiveAspect()
        if Ok("Aspect of the Beast") then return active=="Aspect of the Beast" end
        return active=="Aspect of the Hawk" or active=="Aspect of the Monkey" or active=="Aspect of the Cheetah"
    end
    if aspectState == "Aspect of the Beast" then return false end
    return AL.HasBuff("player","Aspect of the Hawk") or AL.HasBuff("player","Aspect of the Monkey")
        or AL.HasBuff("player","Aspect of the Cheetah")
end
local function CombatAspectNeeded(s)
    if Marksmanship(s) or BeastMastery(s) then return not AnyAspectActive(s) end
    if Survival(s) then return ActiveAspect()=="Aspect of the Cheetah" or not AnyAspectActive(s) end
    return AL.HasBuff("player","Aspect of the Cheetah") or not AnyAspectActive(s)
end

local RANGED_ATTACKS = { "Aimed Shot", "Sniper Shot", "Arcane Shot", "Serpent Sting", "Scorpid Sting", "Concussive Shot", "Multi-Shot" }

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
    if Marksmanship(s) or BeastMastery(s) then return false end
    return Survival(s) or survivalSpec or Bool(s and s.survivalMelee) == true
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
        local beast=BeastMastery(AL.S())
        local first = not beast and Number((SafeCall(units.GetActiveEnemies, units, 5))) or nil
        local second = Number((SafeCall(units.GetByRangeInCombat, units, beast and 35 or nil, limit or 5)))
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
        if (unit ~= "target" or BeastMastery(AL.S())) and Bool((SafeCall(UnitAffectingCombat, unit))) ~= true then return end
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
    if not NoPet(s) and s.mendpet and petUp and GetTime() >= mendPetLockUntil then
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

local function MeleeEnemyCount(limit)
    local count
    local function Accept(value)
        value=Number(value)
        if value and value>=0 and value<=40 and value==math.floor(value) then count=math.max(count or 0,value) end
    end
    if A and A.MultiUnits then
        Accept((SafeCall(A.MultiUnits.GetByRangeInCombat,A.MultiUnits,5,limit or 5)))
    end
    local seen, visible={},0
    local function Count(unit)
        if not SafeValue(unit) or type(unit)~="string" then return end
        if Bool((SafeCall(UnitExists,unit)))~=true or Bool((SafeCall(UnitCanAttack,"player",unit)))~=true
            or Bool((SafeCall(UnitIsDeadOrGhost,unit)))~=false
            or Bool((SafeCall(UnitAffectingCombat,unit)))~=true then return end
        local guid=SafeCall(UnitGUID,unit)
        if not SafeValue(guid) or type(guid)~="string" or seen[guid] then return end
        local near=unit=="target" and InMelee() or false
        if not near then
            local squared,checked=SafeCall(UnitDistanceSquared,unit)
            squared=Number(squared)
            if squared and squared>=0 and Bool(checked)==true then near=squared<=25
            else
                for _,name in ipairs({"Strider Kick","Wing Clip","Mongoose Bite"}) do
                    if Known(name) and Bool((SafeCall(C_Spell and C_Spell.IsSpellInRange,LearnedID(name) or name,unit)))==true then near=true;break end
                end
            end
        end
        if near then seen[guid]=true;visible=visible+1 end
    end
    Count("target")
    local plates=SafeCall(C_NamePlate and C_NamePlate.GetNamePlates)
    if SafeValue(plates) and type(plates)=="table" then
        for _,plate in pairs(plates) do if SafeValue(plate) and type(plate)=="table" then
            Count(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
        end end
    end
    if visible>0 then count=math.max(count or 0,visible) end
    return count
end
local function SurvivalBurst(s,targetHP)
    if not Survival(s) or not AL.burst or not (InMelee() or RangedInRange()) then return end
    local gate=HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false)
    -- Forever Rapid Fire accelerates both melee and ranged attacks.
    if s.rapidfire and not AL.HasBuff("player","Rapid Fire") then Offer("Rapid Fire","Survival Burst",{gate}) end
    if s.bloodFury then Offer("Blood Fury","Survival Burst",{gate}) end
end
local function RaptorQueued()
    return Bool((SafeCall(IsCurrentSpell,LearnedID("Raptor Strike") or "Raptor Strike")))==true
        or GetTime()<raptorPendingUntil
end
local function BuilderBusy(name)
    if not Ok(name) then return true end
    if name=="Raptor Strike" and (RaptorQueued() or (controlEnds[name] or 0)-GetTime()>0.5) then return true end
    local expires=CooldownEnd(NativeCooldown(name)) or controlEnds[name]
    return expires~=nil and expires-GetTime()>0.5
end
local function SurvivalMelee(s,mana,targetHP,petUp)
    Mark(s,targetHP,"mark for Expose Prey")
    SurvivalBurst(s,targetHP)
    local gate=ManaGate(mana,SettingNumber(s,"survivalMinMana",0,0,100),false)
    -- Queue the next swing once, then leave the GCD for the other attacks.
    if s.raptor and not RaptorQueued() then Offer("Raptor Strike","queue melee strike",{gate}) end
    if s.mongoose then Offer("Mongoose Bite","Expose Prey / dodge proc",{gate},true) end
    if s.summonHawk then Offer("Summon Hawk","learned guardian",{gate}) end
    if s.striderKick then Offer("Strider Kick","on cooldown",{gate}) end
    if not NoPet(s) and s.disengage and petUp and TargetTargetsPlayer() then Offer("Disengage","return threat to pet") end
    local minimum=SettingNumber(s,"aoeMinEnemies",2,2,5)
    local count=s.aoe and s.explosiveTrap and MeleeEnemyCount(minimum)
    local trapGates={ManaGate(mana,SettingNumber(s,"trapMinMana",20,0,100),false),
        HealthGate("target",targetHP,SettingNumber(s,"trapMinTargetHP",25,0,100),false)}
    if count and count>=minimum then Offer("Explosive Trap",tostring(count).." engaged melee enemies",trapGates) end
    if s.immolationTrap then Offer("Immolation Trap","melee trap",trapGates) end
    if s.wingclip and s.survivalWingFiller and (not s.raptor or BuilderBusy("Raptor Strike"))
        and (not s.striderKick or BuilderBusy("Strider Kick")) then
        Offer("Wing Clip","optional melee filler",{gate})
    elseif s.wingclip and TargetTargetsPlayer() and not AL.HasDebuff("target","Wing Clip") then
        Offer("Wing Clip","create distance",{gate})
    end
    AddAction(AL.Ok("Attack") and "Attack" or nil,"Survival melee / conserve mana")
end
local function MeleeRotation(s, petUp, mana, targetHP, inCombat)
    if inCombat and Survival(s) and InMelee() then SurvivalMelee(s,mana,targetHP,petUp);return end
    if s.mongoose then Offer("Mongoose Bite", "melee proc", nil, true) end
    if s.disengage and petUp and TargetTargetsPlayer() then Offer("Disengage", "return threat to pet") end
    if s.wingclip and TargetTargetsPlayer() and not AL.HasDebuff("target", "Wing Clip") then
        Offer("Wing Clip", "create distance")
    end
    if s.raptor and not (ReferenceBuild(s) and RaptorQueued())
        and Bool((SafeCall(IsCurrentSpell, LearnedID("Raptor Strike") or "Raptor Strike"))) ~= true then
        Offer("Raptor Strike", "melee strike")
    end
    AddAction(AL.Ok("Attack") and "Attack" or nil, "melee")
end

local function ShotWindow(s,seconds,moving)
    if moving or not s.aimed or not Ok("Aimed Shot") then return true end
    local usable,shortage=SpellUsability("Aimed Shot")
    if usable==false or shortage==true or Bool((SafeCall(AL.InRange,"Aimed Shot")))==false then return true end
    local info=NativeCooldown("Aimed Shot")
    if info and Bool(info.isEnabled)==false then return true end
    local expires=CooldownEnd(info) or controlEnds["Aimed Shot"]
    if expires and expires>GetTime() then return expires-GetTime()>=seconds end
    -- A readable active cooldown with protected timing must still release
    -- fillers. Do not leave a full-mana Hunter waiting only on Auto Shot.
    return not ControlReady("Aimed Shot")
end
local function MarksmanshipRanged(s,mana,targetHP)
    local moving=PlayerMoving()
    Mark(s,targetHP,"mark")
    if AL.burst and RangedInRange() then
        local gate=HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false)
        -- Prefer Rapid Fire just before the next stationary Aimed Shot.
        if s.rapidfire and not moving and not AL.HasBuff("player","Rapid Fire")
            and (not s.aimed or not Ok("Aimed Shot") or not ShotWindow(s,0.5,false)) then
            Offer("Rapid Fire","Marksmanship Burst",{gate})
        end
        if s.bloodFury then Offer("Blood Fury","Marksmanship Burst",{gate}) end
    end
    if s.concussive and TargetTargetsPlayer() then Offer("Concussive Shot","keep distance") end
    -- Multi-Shot shares Aimed's timer, but is an area attack and belongs only
    -- to AoE On. Never spend that timer on Multi-Shot against one target.
    local minimum=SettingNumber(s,"aoeMinEnemies",2,2,5)
    local count=s.aoe and ActiveEnemyCount(minimum)
    if count and count>=minimum and not moving then
        Offer("Multi-Shot","Marksmanship AoE")
        if s.volley then Offer("Volley","ranged ground AoE",{
            ManaGate(mana,SettingNumber(s,"volleyMinMana",35,0,100),false)}) end
    end
    if s.aimed and not moving then Offer("Aimed Shot","Marksmanship primary shot") end
    -- The reference has no Summon Hawk point. Preserve its checkbox for
    -- characters that actually learn it, without granting the talent.
    if s.summonHawk then Offer("Summon Hawk","learned guardian",{HealthGate("target",targetHP,40,false)}) end
    if ShotWindow(s,0.5,moving) and not AL.HasDebuff("target","Serpent Sting")
        and not AL.HasDebuff("target","Scorpid Sting") then
        local gates={HealthGate("target",targetHP,SettingNumber(s,"stingMinTargetHP",35,0,100),false),
            ManaGate(mana,SettingNumber(s,"marksmanshipStingMinMana",30,0,100),false)}
        if s.scorpid and Ok("Scorpid Sting") then Offer("Scorpid Sting","Marksmanship Sting",gates)
        elseif s.sting then Offer("Serpent Sting","Marksmanship damage over time",gates) end
    end
    if s.sniper and not moving and ShotWindow(s,1,false) then Offer("Sniper Shot","Marksmanship filler",{
        ManaGate(mana,SettingNumber(s,"sniperMinMana",30,0,100),false)}) end
    if s.arcane and ShotWindow(s,2,moving) then Offer("Arcane Shot","Marksmanship instant filler",{
        ManaGate(mana,SettingNumber(s,"arcaneMinMana",20,0,80),false)}) end
    if EnsureAutoShot() then Offer("Auto Shot","start auto shot") end
end

local function BeastGates(gates,...)
    local result={}
    for _,gate in ipairs(gates or {}) do result[#result+1]=gate end
    for index=1,select("#",...) do result[#result+1]=select(index,...) end
    return result
end
local function BeastPetEngaged()
    if Bool((SafeCall(UnitAffectingCombat,"pet")))~=true then return false end
    local same=Bool((SafeCall(UnitIsUnit,"pettarget","target")))
    if same~=nil then return same end
    local a,b=SafeCall(UnitGUID,"pettarget"),SafeCall(UnitGUID,"target")
    return SafeValue(a) and SafeValue(b) and type(a)=="string" and type(b)=="string" and a==b
end
local function BeastWindow(s,moving)
    -- A ready primary was already offered first. If its real mana/range gate
    -- hides it, release affordable fillers rather than waiting on Auto Shot.
    return ControlReady("Aimed Shot") or ShotWindow(s,0.5,moving)
end
local function BeastBurst(s,mana,targetHP,petUp)
    if not BeastMastery(s) or not AL.burst then return end
    local gates={ManaGate(mana,SettingNumber(s,"beastBurstMinMana",35,0,100),false),
        HealthGate("target",targetHP,SettingNumber(s,"burstMinTargetHP",40,0,100),false)}
    if petUp and BeastPetEngaged() then
        for _,entry in ipairs({{"bestialWrath","Bestial Wrath"},{"intimidation","Intimidation"}}) do
            if s[entry[1]] and Bool((SafeCall(C_Spell and C_Spell.IsSpellInRange,
                LearnedID(entry[2]) or entry[2],"pet")))~=false then
                Offer(entry[2],"Beast Mastery pet Burst",gates)
            end
        end
    end
    local moving=PlayerMoving()
    for _,entry in ipairs({{"aimed","Aimed Shot"},{"summonHawk","Summon Hawk"},{"arcane","Arcane Shot"}}) do
        local candidate=entry[2]
        if s[entry[1]] and (candidate~="Aimed Shot" or not moving)
            and (candidate=="Aimed Shot" or BeastWindow(s,moving))
            and Ok(candidate) and ControlReady(candidate)
            and Bool((SafeCall(AL.InRange,candidate)))~=false then
            local usable,shortage=SpellUsability(candidate)
            local eligible=BeastGates(gates,Affordable(candidate,usable,shortage),usable~=false,shortage~=true)
            if candidate=="Summon Hawk" then eligible=BeastGates(eligible,
                ManaGate(mana,SettingNumber(s,"beastHawkMinMana",0,0,100),false))
            elseif candidate=="Arcane Shot" then eligible=BeastGates(eligible,
                ManaGate(mana,SettingNumber(s,"arcaneMinMana",20,0,80),false)) end
            if candidate=="Aimed Shot" and s.rapidfire and not AL.HasBuff("player","Rapid Fire") then
                Offer("Rapid Fire","Beast Mastery Burst before Aimed Shot",eligible)
            end
            if s.beastElune then Offer("Elune's Light","Beast Mastery Burst",eligible) end
            if s.beastBerserking then Offer("Berserking","Beast Mastery Burst",eligible) end
            if s.bloodFury then Offer("Blood Fury","Beast Mastery Burst",eligible) end
        end
    end
end
local function BeastRanged(s,mana,targetHP)
    local moving=PlayerMoving()
    if s.concussive and TargetTargetsPlayer() then Offer("Concussive Shot","keep distance") end
    local minimum=SettingNumber(s,"aoeMinEnemies",2,2,5)
    local count=s.aoe and ActiveEnemyCount(5)
    if count and count>=minimum and not moving then
        local gates={ManaGate(mana,SettingNumber(s,"beastAoEMinMana",35,0,100),false)}
        if s.volley and count>=math.max(minimum,SettingNumber(s,"beastVolleyMinEnemies",4,2,5)) then
            Offer("Volley","Beast Mastery ranged ground AoE",BeastGates(gates,
                ManaGate(mana,SettingNumber(s,"volleyMinMana",35,0,100),false)))
        end
        Offer("Multi-Shot","Beast Mastery AoE",gates)
    end
    if s.aimed and not moving then Offer("Aimed Shot","Beast Mastery primary shot") end
    if BeastWindow(s,moving) then
        if not AL.HasDebuff("target","Serpent Sting") and not AL.HasDebuff("target","Scorpid Sting") then
            local gates={HealthGate("target",targetHP,SettingNumber(s,"stingMinTargetHP",35,0,100),false),
                ManaGate(mana,SettingNumber(s,"beastStingMinMana",30,0,100),false)}
            if s.scorpid and Ok("Scorpid Sting") then Offer("Scorpid Sting","Beast Mastery utility Sting",gates)
            elseif s.sting then Offer("Serpent Sting","Beast Mastery damage over time",gates) end
        end
        if s.summonHawk then Offer("Summon Hawk","Beast Mastery learned guardian",{
            ManaGate(mana,SettingNumber(s,"beastHawkMinMana",0,0,100),false)}) end
        -- Shares Hawk's cooldown. Hawk keeps priority when learned/enabled;
        -- Arcane Shot remains available while leveling or if Hawk is unusable.
        if s.arcane then Offer("Arcane Shot","Beast Mastery learned instant fallback",{
            ManaGate(mana,SettingNumber(s,"arcaneMinMana",20,0,80),false)}) end
    end
    if EnsureAutoShot() then Offer("Auto Shot","start auto shot") end
end

function M.OnTargetChanged()
    lastRotation, AL.rotationSecretVisual = nil, nil
    lastTargetSwapTime = GetTime()
    closeTargetFeedback, lastAutoShotAttempt = nil, nil
    raptorPendingUntil, raptorPendingGUID = 0, nil
end

function M.OnCastSent(name, sent)
    sent.hunterPetEpoch = petEpoch
    if name == "Auto Shot" then
        autoShotPendingUntil = GetTime() + 1
        lastAutoShotAttempt = { at = GetTime(), targetGUID = TargetGUID() }
    end
    if name == "Raptor Strike" and ReferenceBuild(AL.S()) then
        raptorPendingUntil = GetTime()+3
        raptorPendingGUID = sent and SafeValue(sent.castGUID) and sent.castGUID or nil
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
end

function M.CanTrackSuggestedSpell(name)
    if not lastRotation or GetTime() - lastRotation.at > 0.5 or lastRotation.visualCandidate then return false end
    local visual = AL.rotationSecretVisual
    if visual and GetTime() - visual.at <= 0.5 then return false end
    if name ~= lastRotation.baseSpell or not Ok(name) then return false end
    for _, entry in ipairs(M.spells) do if entry[2] == name then return true end end
end

RefreshSurvivalSpec()
-- Own the new spells without requiring a shared Core update. Only castable
-- rank IDs may start timers; trap damage, guardian hits and aspect procs may not.
local ownPending, ownFinished, ownLastSent = {}, {}, nil
local function OwnCastGUID(value)
    return SafeValue(value) and type(value)=="string" and value:find("^Cast%-") and value or nil
end
local ownTracker=CreateFrame("Frame")
for _,event in ipairs({"UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET","UNIT_SPELLCAST_INTERRUPTED","UNIT_AURA","PLAYER_DEAD",
    "PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED","SPELLS_CHANGED","PLAYER_TALENT_UPDATE",
    "ACTIVE_TALENT_GROUP_CHANGED","PLAYER_SPECIALIZATION_CHANGED"}) do
    pcall(ownTracker.RegisterEvent,ownTracker,event)
end
ownTracker:SetScript("OnEvent",function(_,event,unit,arg2,arg3,arg4)
    if AL.playerClass~="HUNTER" then return end
    if event=="PLAYER_DEAD" or event=="PLAYER_ENTERING_WORLD" then
        aspectState,aspectChangedAt,aspectCache,aspectAurasBlocked=nil,nil,nil,nil
        raptorPendingUntil,dismissPendingUntil,raptorPendingGUID=0,0,nil
        ownPending,ownFinished,ownLastSent={},{},nil
        controlRetry={}
        trueshotExpires,trueshotChangedAt,trueshotCache,trueshotAurasBlocked=0,nil,nil,nil
        hunterTalentRanks=nil
        if not ReferenceBuild(AL.S()) then controlEnds,controlCastAt={},{} end
        return
    end
    if event=="PLAYER_SPECIALIZATION_CHANGED" and (not SafeValue(unit) or unit~="player") then return end
    if event=="PLAYER_REGEN_ENABLED" or event=="SPELLS_CHANGED" or event=="PLAYER_TALENT_UPDATE"
        or event=="ACTIVE_TALENT_GROUP_CHANGED" or event=="PLAYER_SPECIALIZATION_CHANGED" then
        aspectCache,aspectAurasBlocked,loneWolfChecked=nil,nil,nil
        trueshotCache,trueshotAurasBlocked,hunterTalentRanks=nil,nil,nil;return
    end
    if not SafeValue(unit) or unit~="player" then return end
    if event=="UNIT_AURA" then aspectCache,trueshotCache=nil,nil;return end
    for guid,sent in pairs(ownPending) do if GetTime()-sent.at>30 then ownPending[guid]=nil end end
    for guid,at in pairs(ownFinished) do if GetTime()-at>900 then ownFinished[guid]=nil end end
    local guid=OwnCastGUID(event=="UNIT_SPELLCAST_SENT" and arg3 or arg2)
    local id=Number(arg4) or Number(arg3)
    local name=CastNameFromID(id)
    local readable=id~=nil
    if not readable and SafeValue(arg2) and type(arg2)=="string" then
        local raw=(AL.englishNames and AL.englishNames[arg2]) or arg2
        if castIDs[raw] then name,readable=raw,true end
    end
    if event=="UNIT_SPELLCAST_SENT" then
        if not readable and M.CanTrackSuggestedSpell and M.CanTrackSuggestedSpell(AL.lastSuggestion)
            and castIDs[AL.lastSuggestion] then name=AL.lastSuggestion end
        ownLastSent={name=name,id=id,at=GetTime(),guid=guid}
        if guid then ownPending[guid]=ownLastSent end
        if name=="Raptor Strike" and ReferenceBuild(AL.S()) then raptorPendingUntil,raptorPendingGUID=GetTime()+3,guid end
        return
    end
    local sent=guid and ownPending[guid] or not guid and ownLastSent
    if event~="UNIT_SPELLCAST_SUCCEEDED" then
        if sent and not sent.done then
            sent.failed=true
            if sent.name and (Controlled(sent.name) or sent.name=="Trueshot Aura") and sent.name~="Aimed Shot" and sent.name~="Multi-Shot"
                and sent.name~="Arcane Shot" and sent.name~="Summon Hawk" then
                controlRetry[sent.name]=GetTime()+0.5
            end
            if sent.name=="Raptor Strike" and (not raptorPendingGUID or guid==raptorPendingGUID) then
                raptorPendingUntil,raptorPendingGUID=0,nil
            end
        end
        if guid then ownFinished[guid]=GetTime() end
        return
    end
    if guid and ownFinished[guid] or sent and (sent.failed or sent.done) then return end
    if not readable and sent and GetTime()-sent.at<=5 then name=sent.name end
    if not name or sent and sent.name and sent.name~=name then return end
    if sent then sent.done=true end
    if guid then ownFinished[guid]=GetTime() end
    if aspectNames[name] then aspectState,aspectChangedAt,aspectCache=name,GetTime(),nil end
    if name=="Trueshot Aura" then
        trueshotExpires,trueshotChangedAt,trueshotCache=GetTime()+1800,GetTime(),nil
        controlRetry[name]=nil
    end
    if name=="Dismiss Pet" then dismissPendingUntil=GetTime()+2 end
    if name=="Raptor Strike" then raptorPendingUntil,raptorPendingGUID=0,nil end
    if controlBase[name] and Controlled(name) then
        local expires=CooldownEnd(NativeCooldown(name))
        local ms=Number((SafeCall(C_Spell and C_Spell.GetSpellBaseCooldown or GetSpellBaseCooldown,LearnedID(name) or name)))
        local duration=ms and ms>1500 and ms<=3600000 and ms/1000 or controlBase[name]
        SetControlEnd(name,expires or GetTime()+ControlDuration(name,duration))
        controlRetry[name]=nil
    end
end)
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
        mendPetLockUntil, petCallLockUntil, mongooseUntil, autoShotPendingUntil = 0, 0, 0, 0
        movementEventActive = nil
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
    M.NormalizeBuild(s)
    if not inCombat then curveFailures, manaMaximumCache = {}, nil end
    lastRotation = { at = GetTime(), actions = {} }
    local petUp, petDead, petStatus = PetState()
    local manaPercent = Percent((SafeCall(AL.ManaPercent)))
    local targetHP = hostile and HealthPercent("target") or nil
    if PlayerIsCastingOrChanneling() then
        AddAction(nil, "Casting")
    elseif not inCombat then
        if s.aspect and not AnyAspectActive(s) then BestAspect("aspect",s) end
        MaintainTrueshot(s)
        if NoPet(s) and petUp and GetTime()>=dismissPendingUntil and not PlayerMoving() then
            Offer("Dismiss Pet","Lone Wolf: no pet")
        end
        if not NoPet(s) and s.callpet and GetTime() >= petCallLockUntil then
            if petDead and (not BeastMastery(s) or not PlayerMoving()) then Offer("Revive Pet", "pet dead")
            elseif petStatus == "MISSING" then Offer("Call Pet", "pet missing") end
        end
        Mend(s, petUp, "heal pet")
        if s.drink then AddAction(nil, "Drink", { ManaGate(manaPercent, SettingNumber(s, "drinkMana", 30, 0, 80), true) }) end
        if hostile then
            Mark(s, targetHP, petUp and "mark and send pet" or "mark")
            if UseMelee(s) then MeleeRotation(s, petUp, manaPercent, targetHP, false)
            elseif BeastMastery(s) and s.aimed and not PlayerMoving() then
                Offer("Aimed Shot","Beast Mastery opener")
                if EnsureAutoShot() then Offer("Auto Shot","opener") end
            elseif EnsureAutoShot() then Offer("Auto Shot", "opener") end
        end
    else
        Mend(s, petUp, "pet low")
        if hostile then
            if s.aspect and CombatAspectNeeded(s) then BestAspect("combat aspect",s) end
            MaintainTrueshot(s)
            if BeastMastery(s) then
                Mark(s,targetHP,"mark")
                BeastBurst(s,manaPercent,targetHP,petUp)
            end
            -- Ranged attacks win overlapping range checks by default. Close
            -- client feedback can release a stalled ranged state to melee.
            if UseMelee(s) then MeleeRotation(s, petUp, manaPercent, targetHP, true)
            elseif BeastMastery(s) then BeastRanged(s,manaPercent,targetHP)
            elseif Marksmanship(s) then MarksmanshipRanged(s,manaPercent,targetHP)
            else
                Mark(s, targetHP, "mark")
                SurvivalBurst(s,targetHP)
                if not Survival(s) and AL.burst and s.rapidfire and not AL.HasBuff("player", "Rapid Fire") then
                    Offer("Rapid Fire", "burst", { HealthGate("target", targetHP,
                        SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false) })
                end
                if s.concussive and TargetTargetsPlayer() then Offer("Concussive Shot", "keep distance") end
                local minimum = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
                local count = s.aoe and ActiveEnemyCount(minimum)
                if count and count >= minimum then
                    Offer("Multi-Shot", "aoe")
                    if Survival(s) and s.volley and not PlayerMoving() then
                        Offer("Volley","ranged ground AoE",{ManaGate(manaPercent,SettingNumber(s,"volleyMinMana",35,0,100),false)})
                    end
                end
                local stingGate = HealthGate("target", targetHP, SettingNumber(s, "stingMinTargetHP", 35, 0, 100), false)
                if not AL.HasDebuff("target", "Serpent Sting") and not AL.HasDebuff("target", "Scorpid Sting") then
                    local preferScorpid = s.scorpid and Ok("Scorpid Sting")
                    if preferScorpid then Offer("Scorpid Sting", "weaken attacks", { stingGate })
                    elseif s.sting then Offer("Serpent Sting", "damage over time", { stingGate }) end
                end
                if s.aimed and not PlayerMoving() then Offer("Aimed Shot", "aimed shot") end
                if s.summonHawk then Offer("Summon Hawk", "hawk", { HealthGate("target", targetHP, 40, false) }) end
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
        "Aspect of the Beast", "Trueshot Aura", "Call Pet", "Revive Pet", "Mend Pet", "Rapid Fire", "Blood Fury", "Dismiss Pet",
        "Bestial Wrath", "Intimidation", "Berserking", "Elune's Light" }) do AL.selfCastSpells[name] = true end
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
    root.RegisterRotation("HUNTER", advanced)
end
