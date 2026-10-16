local ADDON, AL = ...

-- ActionLITE Rogue v0.16.3: original Leveling plus optional talent builds.

-- Leveling keeps the finalized pre-simulation implementation in its own
-- scope. Talent builds use the separate implementation below. Both observe
-- real casts so switching rotations retains resource and spell history.
do
    local root = AL
    local leveling, advanced
    local function UsesLeveling(profile)
        profile = profile or (root.Profile and root.Profile("ROGUE")) or (root.S and root.S())
        if advanced and type(profile) == "table" then
            return advanced.NormalizeBuild(profile) == "leveling"
        end
        return true
    end
    local function RotationScope(isLeveling)
        local scope = {
            RegisterRotation = function(token, module)
                assert(token == "ROGUE", "Unexpected class rotation")
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
                    if root.playerClass == "ROGUE" and UsesLeveling() == isLeveling then root[key] = value end
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
-- BEGIN ORIGINAL LEVELING IMPLEMENTATION (Rogue(7).lua)
local ADDON, AL = ...

-- WoW Forever Rogue Combat leveling 1-30
-- Cible : beta 1.60.1.69913
-- Les valeurs protegees ne sont jamais assimilees a zero.

local A = _G.Action

local M = {
	defaults = {
		stealth = true,
		openerMode = "BACKSTAB",
		builderMode = "SINISTER",
		riposte = true,
		kick = true,
		kidney = true,
		gouge = true,
		evasion = true,
		vanish = false,
		snd = true,
		rupture = false,
		expose = false,
		bladeFlurry = true,
		aoe = false,
		sinisterMinEnergy = 45,
		backstabMinEnergy = 60,
		ruptureMinCP = 4,
		exposeMinCP = 4,
		kidneyMinCP = 3,
		gougeHP = 50,
		evasionHP = 35,
		vanishHP = 20,
		aoeMinEnemies = 2,
		burstMinTargetHP = 40,
	},
}

-- IDs de rang 1 pour le scan, les icones et le menu Sorts.
M.spells = {
	{ 8676, "Ambush" },
	{ 53, "Backstab" },
	{ 13877, "Blade Flurry" },
	{ 1833, "Cheap Shot" },
	{ 1725, "Distract" },
	{ 5277, "Evasion" },
	{ 2098, "Eviscerate" },
	{ 8647, "Expose Armor" },
	{ 1966, "Feint" },
	{ 703, "Garrote" },
	{ 1776, "Gouge" },
	{ 1766, "Kick" },
	{ 408, "Kidney Shot" },
	{ 921, "Pick Pocket" },
	{ 14251, "Riposte" },
	{ 1943, "Rupture" },
	{ 6770, "Sap" },
	{ 1752, "Sinister Strike" },
	{ 5171, "Slice and Dice" },
	{ 2983, "Sprint" },
	{ 1784, "Stealth" },
	{ 1856, "Vanish" },
}

-- Sorts de classe verifies par niveau. Les talents Riposte et Blade Flurry
-- restent volontairement gates uniquement par AL.known : leur niveau depend
-- de l'investissement en talents et ne doit pas etre invente en dur.
local MINLEVEL = {
	["Sinister Strike"] = 1,
	["Eviscerate"] = 1,
	["Stealth"] = 2,
	["Pick Pocket"] = 4,
	["Backstab"] = 4,
	["Gouge"] = 6,
	["Evasion"] = 8,
	["Sap"] = 10,
	["Sprint"] = 10,
	["Slice and Dice"] = 10,
	["Kick"] = 12,
	["Garrote"] = 14,
	["Expose Armor"] = 14,
	["Feint"] = 16,
	["Ambush"] = 18,
	["Rupture"] = 20,
	["Vanish"] = 22,
	["Distract"] = 22,
	["Cheap Shot"] = 26,
	["Kidney Shot"] = 30,
}

local Ok, OkReady = AL.LevelGates(MINLEVEL)
M.minLevels = MINLEVEL

local function SafeValue(value)
	return not (issecretvalue and issecretvalue(value))
end

local function SafeCall(reader, ...)
	if type(reader) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(reader, ...)
	if ok then return a, b, c, d end
end

local function ReadableNumber(value)
	if not SafeValue(value) or type(value) ~= "number" then return nil end
	if value ~= value or value == math.huge or value == -math.huge then return nil end
	return value
end

local function SettingNumber(s, key, defaultValue, minValue, maxValue)
	local value = tonumber(s and s[key])
	if value == nil then value = defaultValue end
	value = math.floor(value + 0.5)
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

local function SettingChoice(s, key, allowed, defaultValue)
	local value = s and s[key]
	return allowed[value] and value or defaultValue
end

local function ReadyUsable(name)
	return Ok(name) and AL.IsReady(name) and AL.SpellUsable(name)
end

-- Check the learned rank by ID, and keep an energy shortage separate from
-- other requirements (notably missing combo points). Unknown is not false.
local function SpellUsability(name)
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	local identifier = ref and ReadableNumber(ref.id) or name
	local reader = IsUsableSpell or (C_Spell and C_Spell.IsSpellUsable)
	local usable, insufficient = SafeCall(reader, identifier)
	if not SafeValue(usable) or type(usable) ~= "boolean" then usable = nil end
	if not SafeValue(insufficient) or type(insufficient) ~= "boolean" then insufficient = nil end
	return usable, insufficient, identifier
end

-- Proc-only abilities need a stricter usability check. Core deliberately
-- treats protected usability as permissive for normal rotational spells, but
-- doing that for Riposte would suggest it permanently. Prefer the readable
-- API and fall back to the combat-log parry window below when it is protected.
local function ReadableSpellUsable(name)
	local reader = IsUsableSpell or (C_Spell and C_Spell.IsSpellUsable)
	if type(reader) ~= "function" then return nil end
	local ok, usable = pcall(reader, name)
	if not ok or not SafeValue(usable) then return nil end
	return usable and true or false
end

-- Usability can distinguish missing resources from other failed requirements.
-- A true answer does not establish that we are behind the enemy.
local function ReadablePositionalUsable(name)
	local reader = IsUsableSpell or (C_Spell and C_Spell.IsSpellUsable)
	if type(reader) ~= "function" then return nil end
	local ok, usable, insufficientPower = pcall(reader, name)
	if not ok or not SafeValue(usable) then return nil end
	if usable then return true end
	if not SafeValue(insufficientPower) then return nil end
	return insufficientPower and true or false
end

local riposteUntil = 0
local function RiposteProcActive()
	local readable = ReadableSpellUsable("Riposte")
	if readable ~= nil then return readable end
	return GetTime and GetTime() < riposteUntil
end

-- Forever may hide IsUsableSpell in combat. A parried incoming swing/spell
-- opens Riposte for five seconds, so the combat log provides a conservative
-- fallback without turning an unknown usability value into a permanent proc.
if AL.playerClass == "ROGUE" and CreateFrame and CombatLogGetCurrentEventInfo then
	local procFrame = CreateFrame("Frame")
	if procFrame.RegisterEvent and procFrame.SetScript then
		procFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		procFrame:SetScript("OnEvent", function()
			local ok, _, subEvent, _, _, _, _, _, destGUID, _, _, _, swingMiss, _, _, spellMiss =
				pcall(CombatLogGetCurrentEventInfo)
			if not ok or not SafeValue(subEvent) or not SafeValue(destGUID) then return end
			if not UnitGUID or destGUID ~= UnitGUID("player") then return end
			local missType = subEvent == "SWING_MISSED" and swingMiss
				or (subEvent == "SPELL_MISSED" and spellMiss)
			if SafeValue(missType) and missType == "PARRY" then
				riposteUntil = (GetTime and GetTime() or 0) + 5
			end
		end)
	end
end

local function MainHandIsDagger()
	local itemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
	if not GetInventoryItemID or not itemInfoInstant then return nil end
	local okItem, itemID = pcall(GetInventoryItemID, "player", 16)
	if not okItem or not SafeValue(itemID) or not itemID then return false end
	local okInfo, _, _, _, _, _, classID, subclassID = pcall(itemInfoInstant, itemID)
	if not okInfo or not SafeValue(classID) or not SafeValue(subclassID) then return nil end
	local daggerID = Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Dagger or 15
	return classID == 2 and subclassID == daggerID
end

-- The interact check is approximately ten yards, not melee range. It is only
-- used outside combat to prepare Stealth; attacks require their own spell range.
local function WithinStealthRange()
	local near = SafeCall(CheckInteractDistance, "target", 3)
	if SafeValue(near) and (near == true or near == 1) then return true end
	local melee = SafeCall(AL.InRange, "Sinister Strike")
	return SafeValue(melee) and melee == true
end

-- Spell range is authoritative. An unknown spell range must not turn the
-- ten-yard Stealth check into a claim that Backstab is in melee range.
local function InMeleeRange(spell)
	if AL.InRange then
		local ok, inRange = pcall(AL.InRange, spell or "Sinister Strike")
		if ok and SafeValue(inRange) and inRange ~= nil then return inRange == true end
	end
	return false
end

local function ConfirmedHostileTarget()
	if type(UnitExists) ~= "function" or type(UnitCanAttack) ~= "function" then return false end
	local okExists, exists = pcall(UnitExists, "target")
	local okAttack, attack = pcall(UnitCanAttack, "player", "target")
	if not okExists or not okAttack or not SafeValue(exists) or not SafeValue(attack) then return false end
	return exists and attack and true or false
end

local function ValidPercent(value)
	value = ReadableNumber(value)
	return value and value >= 0 and value <= 100 and value or nil
end

local function BarPercent(bar)
	if not bar then return nil end
	local value = ReadableNumber((SafeCall(bar.GetValue, bar)))
	local minimum, maximum = SafeCall(bar.GetMinMaxValues, bar)
	minimum, maximum = ReadableNumber(minimum), ReadableNumber(maximum)
	if value == nil or minimum == nil or maximum == nil or maximum <= minimum then return nil end
	if value < minimum or value > maximum then return nil end
	-- A dormant target bar can remain at 1/1, including with no target.
	-- That default cannot establish that the live target has full health.
	if minimum == 0 and maximum == 1 and value == 1 then return nil end
	return (value - minimum) / (maximum - minimum) * 100
end

local function TextPercent(fontString)
	if not fontString then return nil end
	local text = SafeCall(fontString.GetText, fontString)
	if not SafeValue(text) or type(text) ~= "string" then return nil end
	text = text:gsub(",", "")
	local pct = tonumber(text:match("(%d+%.?%d*)%s*%%"))
	if pct then return ValidPercent(pct) end
	local current, maximum = text:match("(%d+)%s*/%s*(%d+)")
	current, maximum = tonumber(current), tonumber(maximum)
	if current and maximum and maximum > 0 and current <= maximum then return current / maximum * 100 end
end

local function TargetHealthBars()
	local bars, seen = {}, {}
	local function Add(path, bar, owner)
		if not bar or not SafeValue(bar) or seen[bar] then return end
		seen[bar] = true
		bars[#bars + 1] = { path = path, bar = bar, owner = owner }
	end
	local frame = _G.TargetFrame
	local content = frame and frame.TargetFrameContent
	local main = content and content.TargetFrameContentMain
	local area = main and main.HealthBarsContainer
	-- Prefer the active legacy frame references; the retail-shaped container
	-- can exist in Forever without being the bar that is actually updated.
	Add("TargetFrame.healthbar", frame and frame.healthbar, frame)
	Add("TargetFrameHealthBar", _G.TargetFrameHealthBar, frame)
	Add("TargetFrame.HealthBarsContainer.HealthBar", area and area.HealthBar, frame)
	Add("TargetFrameContentMain.HealthBar", main and main.HealthBar, frame)
	local plate = SafeCall(C_NamePlate and C_NamePlate.GetNamePlateForUnit, "target")
	if plate and SafeValue(plate) then
		local unitFrame = plate.UnitFrame
		local container = unitFrame and unitFrame.HealthBarsContainer
		Add("TargetNamePlate.UnitFrame.healthBar", unitFrame and unitFrame.healthBar, unitFrame)
		Add("TargetNamePlate.UnitFrame.HealthBar", unitFrame and unitFrame.HealthBar, unitFrame)
		Add("TargetNamePlate.HealthBarsContainer.HealthBar", container and container.HealthBar, unitFrame)
	end
	return bars
end

local function CurrentTargetBar(entry)
	local shown = SafeCall(entry.bar.IsShown, entry.bar)
	if not SafeValue(shown) or shown == false then return false, "hidden/protected visibility" end
	local unit = entry.bar.unit
	if SafeValue(unit) and unit == nil and entry.owner then unit = entry.owner.unit end
	if not SafeValue(unit) then return false, "protected unit binding" end
	if type(unit) == "string" and unit ~= "target" then
		local same = SafeCall(UnitIsUnit, unit, "target")
		if not SafeValue(same) or same ~= true then return false, "different unit" end
	end
	return true, "target frame"
end

local function HealthPercent(unit)
	local exists = SafeCall(UnitExists, unit)
	if not SafeValue(exists) or exists ~= true then return nil, "no readable unit" end
	local hp = ValidPercent((SafeCall(AL.HealthPercent, unit)))
	if hp ~= nil then return hp, "UnitHealth" end
	local curve = CurveConstants and CurveConstants.ScaleTo100
	local normalized = ReadableNumber((SafeCall(UnitHealthPercent, unit, false, curve)))
	if normalized ~= nil then
		-- With ScaleTo100, 1 is one percent. Without a curve, the helper returns
		-- a fraction; do not confuse those two contracts at low target health.
		if not curve then normalized = normalized * 100 end
		hp = ValidPercent(normalized)
		if hp ~= nil then return hp, "UnitHealthPercent" end
	end
	if A and type(A.Unit) == "function" then
		local object = SafeCall(A.Unit, unit)
		if object then
			hp = ValidPercent((SafeCall(object.HealthPercent, object)))
			if hp ~= nil then return hp, "Action health" end
		end
	end
	if unit == "target" then
		local bars = TargetHealthBars()
		-- A visible percentage label is more useful than a default filled bar.
		local frame = _G.TargetFrame
		local frameShown = frame and SafeCall(frame.IsShown, frame)
		if SafeValue(frameShown) and frameShown ~= false then
			hp = TextPercent(_G.TargetFrameHealthBarText)
			if hp ~= nil then return hp, "TargetFrameHealthBarText" end
		end
		for _, entry in ipairs(bars) do
			if CurrentTargetBar(entry) then
				hp = TextPercent(entry.bar.TextString) or TextPercent(entry.bar.RightText)
				if hp ~= nil then return hp, entry.path .. " text" end
			end
		end
		for _, entry in ipairs(bars) do
			if CurrentTargetBar(entry) then
				hp = BarPercent(entry.bar)
				if hp ~= nil then return hp, entry.path end
			end
		end
	end
	return nil, "protected/unavailable"
end

local function TargetClassification()
	local value = SafeCall(UnitClassification, "target")
	if SafeValue(value) and type(value) == "string" then return value end
end

local function EvisceratePoints()
	local classification = TargetClassification()
	if classification == "normal" or classification == "minus" or classification == "trivial" then return 1 end
	-- Rare, elite, rareelite and worldboss require five. Unknown classification
	-- stays conservative rather than assuming that a hidden target is normal.
	return 5
end

local openerBlocked = false
local lastSuccessfulCastAt
local lastRotation
local AddAction, FinishDecision, EnergyGate, EnergyCost

function M.OnTargetChanged()
	openerBlocked = false
	lastRotation, AL.rogueSecretVisual = nil, nil
end

function M.OnUIError(message)
	if not SafeValue(message) or type(message) ~= "string" then return end
	if (SPELL_FAILED_NOT_BEHIND and message == SPELL_FAILED_NOT_BEHIND)
		or (ERR_BADATTACKPOS and message == ERR_BADATTACKPOS)
	then
		openerBlocked = true
	end
end

function M.OnCastResult(name, event)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		lastSuccessfulCastAt = GetTime()
		if name == "Backstab" then openerBlocked = false end
	end
end

local function RecoverStaleComboPoints(cp)
	if cp <= 0 then return cp end
	-- Forever's readable zero alone is unreliable. Require two independently
	-- unusable finishers with readable non-energy failures and a usable builder.
	local native = ReadableNumber((SafeCall(GetComboPoints, "player", "target")))
	local typed = ReadableNumber((SafeCall(UnitPower, "player", 4)))
	if native ~= 0 or typed ~= 0 then return cp end
	if lastSuccessfulCastAt and GetTime() - lastSuccessfulCastAt < 1.5 then
		return cp
	end
	if not Ok("Slice and Dice") or not Ok("Eviscerate")
		or not AL.IsReady("Slice and Dice") or not AL.IsReady("Eviscerate")
		or AL.HasBuff("player", "Slice and Dice") then
		return cp
	end
	local sndUsable, sndShortage = SpellUsability("Slice and Dice")
	local eviUsable, eviShortage = SpellUsability("Eviscerate")
	if sndUsable ~= false or sndShortage ~= false or eviUsable ~= false or eviShortage ~= false then
		return cp
	end
	local builderUsable, builderShortage = SpellUsability("Sinister Strike")
	if not Ok("Sinister Strike") or builderUsable ~= true or builderShortage ~= false
		or not InMeleeRange("Sinister Strike") then
		return cp
	end
	if type(AL.ResetComboPoints) ~= "function" then return cp end
	AL.ResetComboPoints()
	return 0
end

function M.CanTrackSuggestedSpell(name)
	if not Ok(name) then return false end
	-- A secret-health visual has two possible displayed actions. Never assume
	-- that a hidden cast ID was the underlying builder rather than Eviscerate.
	local visual = AL.rogueSecretVisual
	if visual and GetTime() - visual.at <= 0.5 and (name == visual.baseSpell or (visual.spells and visual.spells[name]) or name == visual.spell) then return false end
	for _, entry in ipairs(M.spells) do if entry[2] == name then return true end end
	return false
end

local function ActiveEnemyCount(limit)
	if A and A.MultiUnits then
		if A.MultiUnits.GetActiveEnemies then
			local count = ReadableNumber((SafeCall(A.MultiUnits.GetActiveEnemies, A.MultiUnits, 5)))
			if count and count >= 0 then return count, "Action melee enemy count" end
		end
		if A.MultiUnits.GetByRangeInCombat then
			local count = ReadableNumber((SafeCall(A.MultiUnits.GetByRangeInCombat, A.MultiUnits, nil, limit or 5)))
			if count and count >= 0 then return count, "Action range enemy count" end
		end
	end
	-- Count only distinct hostile units with readable melee range. A hidden
	-- count cannot satisfy a user-selected minimum of two or more enemies.
	local seen, count = {}, 0
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs["Sinister Strike"]
	local function Count(unit)
		if not SafeValue(unit) or type(unit) ~= "string" then return end
		local exists = SafeCall(UnitExists, unit)
		local hostile = SafeCall(UnitCanAttack, "player", unit)
		local dead = SafeCall(UnitIsDeadOrGhost, unit)
		if not SafeValue(exists) or exists ~= true or not SafeValue(hostile) or hostile ~= true
			or not SafeValue(dead) or dead ~= false then return end
		local guid = SafeCall(UnitGUID, unit)
		if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] then return end
		local fighting = SafeCall(UnitAffectingCombat, unit)
		if unit ~= "target" and (not SafeValue(fighting) or fighting ~= true) then return end
		local inRange
		if unit == "target" then inRange = SafeCall(AL.InRange, "Sinister Strike")
		elseif ref and C_Spell then inRange = SafeCall(C_Spell.IsSpellInRange, ref.id, unit) end
		if not SafeValue(inRange) or (inRange ~= true and inRange ~= 1) then return end
		seen[guid], count = true, count + 1
	end
	Count("target")
	local plates = C_NamePlate and SafeCall(C_NamePlate.GetNamePlates)
	if SafeValue(plates) and type(plates) == "table" then
		for _, plate in pairs(plates) do
			if SafeValue(plate) and type(plate) == "table" then
				Count(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
			end
		end
	end
	if count > 0 then return count, "confirmed visible melee enemies (lower bound)" end
	return nil, "enemy count unavailable"
end

local function TryOpener(name, s)
	if not Ok(name) or not InMeleeRange(name) then return nil end
	if openerBlocked and (name == "Backstab" or name == "Ambush" or name == "Garrote") then return nil end
	if name == "Backstab" or name == "Ambush" then
		if MainHandIsDagger() == false or openerBlocked then return nil end
	end
	if name == "Backstab" or name == "Ambush" or name == "Garrote" then
		if ReadablePositionalUsable(name) == false then return nil end
	elseif not AL.SpellUsable(name) then
		return nil
	end
	local minimum = name == "Backstab" and SettingNumber(s, "backstabMinEnergy", 60, 20, 100)
		or (name == "Cheap Shot" and 40 or (name == "Garrote" and 50 or 60))
	local energy = ReadableNumber(AL.Power(3))
	minimum = math.max(minimum, EnergyCost(name, name == "Cheap Shot" and 40 or (name == "Garrote" and 50 or 60)))
	if energy and energy < minimum then
		AddAction(nil, "Pool energy for " .. name); return FinishDecision()
	end
	if not AddAction(name, "stealth opener", { EnergyGate(energy, minimum, name) }) then return nil end
	AddAction(nil, "Pool energy for " .. name)
	return FinishDecision()
end

local function StealthOpener(s)
	if not AL.HasBuff("player", "Stealth") then return nil end
	local mode = SettingChoice(s, "openerMode", {
		AUTO = true, BACKSTAB = true, CHEAP_SHOT = true, AMBUSH = true, GARROTE = true,
	}, "BACKSTAB")

	local orders = {
		AUTO = { "Backstab", "Ambush", "Cheap Shot", "Garrote" },
		BACKSTAB = { "Backstab", "Cheap Shot", "Garrote", "Ambush" },
		CHEAP_SHOT = { "Cheap Shot", "Ambush", "Garrote" },
		AMBUSH = { "Ambush", "Cheap Shot", "Garrote" },
		GARROTE = { "Garrote", "Cheap Shot", "Ambush" },
	}
	for _, name in ipairs(orders[mode]) do
		local spell, poolReason = TryOpener(name, s)
		if spell then return spell, "stealth opener" end
		if poolReason then return nil, poolReason end
	end
	return nil
end

local function Builder(s)
	-- No reliable behind-target signal is supplied. A saved BACKSTAB builder
	-- preference must not trap combat at the front of the target.
	if Ok("Sinister Strike") then
		return "Sinister Strike", SettingNumber(s, "sinisterMinEnergy", 45, 20, 100)
	end
	return nil
end

-- Protected values are evaluated by the client for display only. All rows
-- below describe public threshold intervals, never measured/guessed HP or
-- energy. Native parent-frame alpha combines their independent masks; Lua
-- does not inspect, compare, multiply, or stringify protected alpha values.
local visibilityCurves, curveFailures = {}, {}
local energyMaximumCache
local function CurveAvailable(kind, unit)
	local reader = UnitHealthPercent
	if kind == "energy" then reader = UnitPowerPercent; unit = "player" end
	unit = unit or "target"
	local failure = curveFailures[kind .. ":" .. unit]
	if failure and failure.reader == reader then return false end
	return C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function"
		and type(CreateColor) == "function"
		and type(reader) == "function"
end

local function NextFloat32(value)
	if value <= 0 then return 2 ^ -149 end
	local exponent = math.floor(math.log(value) / math.log(2))
	local step = 2 ^ (exponent - 23)
	return (math.floor(value / step + 0.5) + 1) * step
end

local function HealthGate(unit, value, threshold, below)
	if value ~= nil then return below and value <= threshold or not below and value >= threshold end
	if below and threshold >= 100 or not below and threshold <= 0 then return true end
	if not CurveAvailable("health", unit) then return false end
	return { axis = unit == "player" and "playerHP" or "targetHP", kind = "health", unit = unit,
		cut = below and NextFloat32(threshold / 100) or threshold / 100, below = below,
		threshold = threshold }
end

EnergyCost = function(spell, fallback)
	local reader = C_Spell and C_Spell.GetSpellPowerCost
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[spell]
	if type(reader) == "function" then
		local ok, cost = pcall(function()
			local costs = reader(ref and ref.id or spell)
			if not SafeValue(costs) or type(costs) ~= "table" then return end
			for _, entry in pairs(costs) do
				if SafeValue(entry) and type(entry) == "table" then
					local power = ReadableNumber(entry.type)
					local amount = ReadableNumber(entry.cost)
					if power == 3 and amount and amount >= 0 then return amount end
				end
			end
		end)
		if ok and cost ~= nil then return cost end
	end
	return fallback
end

EnergyGate = function(energy, minimum, spell)
	local usable = SpellUsability(spell)
	if usable == false or (usable == nil and not AL.SpellUsable(spell)) then return false end
	if energy ~= nil then return energy >= minimum end
	local maximum = lastRotation.energyMaximum
	if maximum and maximum > 0 and CurveAvailable("energy") then
		if minimum <= 0 then return true end
		if minimum > maximum then return false end
		return { axis = "energy", kind = "energy", unit = "player", cut = minimum / maximum,
			below = false, threshold = minimum }
	end
	return usable == true or AL.SpellUsable(spell)
end

local function FinisherAvailable(spell)
	local usable, insufficient = SpellUsability(spell)
	return AL.IsReady(spell) and (usable ~= false or insufficient == true)
end

AddAction = function(spell, reason, gates)
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

FinishDecision = function()
	local actions = lastRotation.actions
	local base = actions[#actions]
	if not base or #base.conditions > 0 then
		AddAction(nil, "Ready")
		base = actions[#actions]
	end
	lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
	return base.spell, base.reason
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
				axis = { key = c.axis, kind = c.kind, unit = c.unit, cuts = { 0, 2 }, seen = { [0] = true, [2] = true } }
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
				local mask = { key = key, kind = axis.kind, unit = axis.unit, low = low, high = high }
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
				if mask.kind == "energy" then color = UnitPowerPercent(mask.unit, 3, false, curve)
				else color = UnitHealthPercent(mask.unit, false, curve) end
				local _, _, _, alpha = color:GetRGBA()
				return alpha
			end)
			if not success then
				curveFailures[mask.kind .. ":" .. mask.unit] = {
					reader = mask.kind == "energy" and UnitPowerPercent or UnitHealthPercent }
				error("Rogue resource curve unavailable")
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

-- Compatibility helpers for the already validated Eviscerate health display.
function M.ApplySecretHealthVisibility(widget, below, r, g, b)
	local cut = NextFloat32(0.5)
	local mask = { key = "compat", kind = "health", unit = "target", low = below and 0 or cut, high = below and cut or 2 }
	local values, err = M.EvaluateVisualMasks({ masks = { compat = mask } })
	if not values then return false, err end
	if r ~= nil then widget:SetVertexColor(r, g, b, values.compat) else widget:SetAlpha(values.compat) end
	return true
end

function M.SecretFinisherVisualState(spell, reason)
	local plan = M.SecretVisualPlan(spell, reason)
	if plan and plan.spells.Eviscerate then return "Eviscerate", 50, "Protected target HP; client evaluates <=50%" end
end

function M.NextSpell(s, inCombat, hostile)
	-- A blocked energy curve must not repeatedly suppress a working Evasion
	-- health curve. Disable only the failed unit/API until combat ends.
	if not inCombat then curveFailures, energyMaximumCache = {}, nil end
	local targetHP
	if hostile then targetHP = HealthPercent("target") end
	lastRotation = { at = GetTime(), actions = {} }

	local maximum = ReadableNumber((SafeCall(UnitPowerMax, "player", 3)))
	if maximum and maximum > 0 then energyMaximumCache = maximum end
	lastRotation.energyMaximum = energyMaximumCache

	if not inCombat then
		if hostile then
			local opener, reason = StealthOpener(s)
			if opener or reason then return opener, reason end
			if s.stealth and OkReady("Stealth") and not AL.HasBuff("player", "Stealth") and WithinStealthRange() then
				return "Stealth", "opener setup"
			end
			if not InMeleeRange("Sinister Strike") then return nil, "Approach target" end
			local builder, minimum = Builder(s)
			if builder then
				minimum = math.max(minimum, EnergyCost(builder, 45))
				AddAction(builder, openerBlocked and "positional opener fallback" or "opener", { EnergyGate(ReadableNumber(AL.Power(3)), minimum, builder) })
				AddAction(nil, "Pool energy")
				return FinishDecision()
			end
			return AL.known["Attack"] and "Attack", "opener"
		end
		return nil, "Ready"
	end
	if not hostile then return nil, "No target" end

	local cp = RecoverStaleComboPoints(ReadableNumber(AL.ComboPoints()) or 0)
	local energy = ReadableNumber(AL.Power(3))
	local playerHP = HealthPercent("player")

	if s.vanish and ReadyUsable("Vanish") then
		AddAction("Vanish", "emergency escape", { HealthGate("player", playerHP, SettingNumber(s, "vanishHP", 20, 5, 80), true) })
	end
	local targetCasting = AL.TargetCasting()
	if targetCasting and s.kick and ReadyUsable("Kick") then
		AddAction("Kick", "interrupt"); return FinishDecision()
	end
	if targetCasting and s.kidney and cp >= SettingNumber(s, "kidneyMinCP", 3, 1, 5) and ReadyUsable("Kidney Shot") then
		AddAction("Kidney Shot", "interrupt fallback"); return FinishDecision()
	end
	if s.gouge and ReadyUsable("Gouge") and InMeleeRange("Gouge") and not AL.HasDebuff("target", "Gouge") then
		AddAction("Gouge", "stall and recover", {
			HealthGate("player", playerHP, SettingNumber(s, "gougeHP", 50, 5, 95), true),
			EnergyGate(energy, EnergyCost("Gouge", 45), "Gouge") })
	end
	if s.evasion and ReadyUsable("Evasion") and not AL.HasBuff("player", "Evasion") then
		AddAction("Evasion", "emergency", { HealthGate("player", playerHP, SettingNumber(s, "evasionHP", 35, 5, 90), true) })
	end
	if s.riposte and Ok("Riposte") and AL.IsReady("Riposte") and RiposteProcActive() then
		AddAction("Riposte", "parry proc"); return FinishDecision()
	end

	local aoeMin = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
	local enemyCount
	if s.aoe then enemyCount = ActiveEnemyCount(aoeMin) end
	local aoeActive = s.aoe and enemyCount ~= nil and enemyCount >= aoeMin
	local burstGate = HealthGate("target", targetHP, SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false)
	local meleeTarget = ConfirmedHostileTarget() and InMeleeRange("Sinister Strike")
	if s.bladeFlurry and (AL.burst or aoeActive) and meleeTarget and ReadyUsable("Blade Flurry") and not AL.HasBuff("player", "Blade Flurry") then
		AddAction("Blade Flurry", aoeActive and "aoe" or "burst", { burstGate, EnergyGate(energy, EnergyCost("Blade Flurry", 25), "Blade Flurry") })
	end
	if AL.burst and meleeTarget then
		if ReadyUsable("Blood Fury") then AddAction("Blood Fury", "burst", { burstGate }) end
		if ReadyUsable("Berserking") then AddAction("Berserking", "burst", { burstGate }) end
	end
	if s.snd and cp == 1 and not AL.HasBuff("player", "Slice and Dice") and Ok("Slice and Dice")
		and FinisherAvailable("Slice and Dice") then
		AddAction("Slice and Dice", "maintain buff at exactly 1 cp", { EnergyGate(energy, EnergyCost("Slice and Dice", 25), "Slice and Dice") })
		AddAction(nil, "Pool energy for Slice and Dice"); return FinishDecision()
	end

	local finishCP = EvisceratePoints()
	local eviscerateAllowed = Ok("Eviscerate")
	local finishGate = HealthGate("target", targetHP, 50, true)
	if eviscerateAllowed and cp >= finishCP then
		if FinisherAvailable("Eviscerate") then
			AddAction("Eviscerate", tostring(cp) .. " cp at/below 50% target health", {
				finishGate, EnergyGate(energy, EnergyCost("Eviscerate", 35), "Eviscerate") })
			AddAction(nil, "Pool energy for Eviscerate", { finishGate })
		end
	end
	if not eviscerateAllowed and s.rupture and cp >= SettingNumber(s, "ruptureMinCP", 4, 1, 5)
		and not AL.HasDebuff("target", "Rupture") and Ok("Rupture") and FinisherAvailable("Rupture") then
		AddAction("Rupture", tostring(cp) .. " cp", { finishGate, EnergyGate(energy, EnergyCost("Rupture", 25), "Rupture") })
		AddAction(nil, "Pool energy for Rupture", { finishGate })
	end
	if not eviscerateAllowed and s.expose and cp >= SettingNumber(s, "exposeMinCP", 4, 1, 5)
		and not AL.HasDebuff("target", "Expose Armor") and Ok("Expose Armor") and FinisherAvailable("Expose Armor") then
		AddAction("Expose Armor", tostring(cp) .. " cp", { finishGate, EnergyGate(energy, EnergyCost("Expose Armor", 25), "Expose Armor") })
		AddAction(nil, "Pool energy for Expose Armor", { finishGate })
	end
	if cp >= 5 and targetHP == nil and eviscerateAllowed and not CurveAvailable("health") then
		AddAction(nil, "Target health unavailable"); return FinishDecision()
	end
	local builder, minimumEnergy = Builder(s)
	if builder then
		minimumEnergy = math.max(minimumEnergy, EnergyCost(builder, 45))
		AddAction(builder, "builder", { EnergyGate(energy, minimumEnergy, builder) })
		AddAction(nil, "Pool energy")
	else AddAction(AL.known["Attack"] and "Attack" or nil, "melee") end
	return FinishDecision()
end

function M.GetUIState()
	local profile = AL.S()
	local knownCount = 0
	for _, entry in ipairs(M.spells) do
		if AL.known[entry[2]] then knownCount = knownCount + 1 end
	end
	return {
		level = UnitLevel and UnitLevel("player") or nil,
		energy = AL.Power(3),
		combo = AL.ComboPoints(),
		stealthed = AL.HasBuff("player", "Stealth"),
		knownCount = knownCount,
		enemyCount = ActiveEnemyCount(SettingNumber(profile, "aoeMinEnemies", 2, 2, 5)),
		mainHandDagger = MainHandIsDagger(),
		targetHealth = HealthPercent("target"),
		evisceratePoints = EvisceratePoints(),
	}
end

AL.RegisterRotation("ROGUE", M)
-- END ORIGINAL LEVELING IMPLEMENTATION
    end)(ADDON, RotationScope(true))

    ;(function(...)
-- BEGIN OPTIONAL TALENT BUILD IMPLEMENTATION
local ADDON, AL = ...

-- ActionLITE Rogue 0.16.3: Assassination 38/11/2, Subtlety, Combat and leveling 1-60.
-- Combat reference: MythicSim Forever 0025d73986ee (1.60.1.70338).
-- Les valeurs protegees ne sont jamais assimilees a zero.

local A = _G.Action

local M = {
	defaults = {
        leveling = true,
		assassination = false,
		assassinationMutilate = true, assassinationMutilateEnergy = 0,
		assassinationEviscerateCP = 4,
		assassinationColdBlood = true, assassinationRacials = true,
		subtlety = false,
		subtletyHemorrhage = true, subtletyHemorrhageEnergy = 0,
		subtletyGhostlyStrike = true, subtletyAmbush = true,
		subtletyRupture = true, subtletyRuptureCP = 3, subtletyRuptureHP = 50,
		subtletyEviscerateCP = 4,
		subtletyPremeditation = true, subtletyVanish = false,
		subtletyPreparation = true, subtletyRacials = true,
		combat = false,
		combatAdrenalineRush = true,
		combatAdrenalineEnergy = 60,
		combatRacials = true,
		stealth = true,
		openerMode = "BACKSTAB",
		builderMode = "SINISTER",
		riposte = true,
		kick = true,
		kidney = true,
		gouge = true,
		evasion = true,
		vanish = false,
		snd = true,
		rupture = false,
		expose = false,
		bladeFlurry = true,
		aoe = false,
		sinisterMinEnergy = 45,
		backstabMinEnergy = 60,
		ruptureMinCP = 4,
		exposeMinCP = 4,
		kidneyMinCP = 3,
		gougeHP = 50,
		evasionHP = 35,
		vanishHP = 20,
		aoeMinEnemies = 2,
		burstMinTargetHP = 40,
	},
}

-- IDs de rang 1 pour le scan, les icones et le menu Sorts.
-- Exactly one rotation stays selected. Leveling is the default and the
-- fallback when a selected specialization is switched off or saved flags
-- conflict. A valid saved specialization takes priority during migration.
M.buildKeys = { "leveling", "assassination", "subtlety", "combat" }
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
    s = s or AL.Profile("ROGUE")
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
	{ 13750, "Adrenaline Rush" },
	{ 8676, "Ambush" },
	{ 53, "Backstab" },
	{ 20554, "Berserking" },
	{ 13877, "Blade Flurry" },
	{ 20572, "Blood Fury" },
	{ 1833, "Cheap Shot" },
	{ 14177, "Cold Blood" },
	{ 1725, "Distract" },
	{ 5277, "Evasion" },
	{ 2098, "Eviscerate" },
	{ 8647, "Expose Armor" },
	{ 1966, "Feint" },
	{ 703, "Garrote" },
	{ 1776, "Gouge" },
	{ 14278, "Ghostly Strike" },
	{ 16511, "Hemorrhage" },
	{ 1766, "Kick" },
	{ 408, "Kidney Shot" },
	{ 1310707, "Mutilate" },
	{ 921, "Pick Pocket" },
	{ 14183, "Premeditation" },
	{ 14185, "Preparation" },
	{ 14251, "Riposte" },
	{ 1943, "Rupture" },
	{ 6770, "Sap" },
	{ 1752, "Sinister Strike" },
	{ 5171, "Slice and Dice" },
	{ 2983, "Sprint" },
	{ 1784, "Stealth" },
	{ 1856, "Vanish" },
	{ 1310703, "Venom" },
}

-- Sorts de classe verifies par niveau. Les talents Riposte et Blade Flurry
-- restent volontairement gates uniquement par AL.known : leur niveau depend
-- de l'investissement en talents et ne doit pas etre invente en dur.
local MINLEVEL = {
	["Sinister Strike"] = 1,
	["Eviscerate"] = 1,
	["Stealth"] = 2,
	["Pick Pocket"] = 4,
	["Backstab"] = 4,
	["Gouge"] = 6,
	["Evasion"] = 8,
	["Sap"] = 10,
	["Sprint"] = 10,
	["Slice and Dice"] = 10,
	["Kick"] = 12,
	["Garrote"] = 14,
	["Expose Armor"] = 14,
	["Feint"] = 16,
	["Ambush"] = 18,
	["Rupture"] = 20,
	["Vanish"] = 22,
	["Distract"] = 22,
	["Cheap Shot"] = 26,
	["Kidney Shot"] = 30,
}

local Ok, OkReady = AL.LevelGates(MINLEVEL)
M.minLevels = MINLEVEL

local function SafeValue(value)
	return not (issecretvalue and issecretvalue(value))
end

local function SafeCall(reader, ...)
	if type(reader) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g = pcall(reader, ...)
	if ok then return a, b, c, d, e, f, g end
end

local function ReadableNumber(value)
	if not SafeValue(value) or type(value) ~= "number" then return nil end
	if value ~= value or value == math.huge or value == -math.huge then return nil end
	return value
end

local function SettingNumber(s, key, defaultValue, minValue, maxValue)
	local value = tonumber(s and s[key])
	if value == nil then value = defaultValue end
	value = math.floor(value + 0.5)
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

local function SettingChoice(s, key, allowed, defaultValue)
	local value = s and s[key]
	return allowed[value] and value or defaultValue
end

local SubReady, SubCastResult, SubTargetChanged, SubAura, RoguePoints, SubtletyRotation, AssassinationRotation
local subReset = {}
local function ReadyUsable(name)
	if SubReady and (AL.S().subtlety == true or AL.S().assassination == true or subReset[name]) then
		return Ok(name) and SubReady(name) and AL.SpellUsable(name)
	end
	return Ok(name) and AL.IsReady(name) and AL.SpellUsable(name)
end

-- Check the learned rank by ID, and keep an energy shortage separate from
-- other requirements (notably missing combo points). Unknown is not false.
local function SpellUsability(name)
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	local identifier = ref and ReadableNumber(ref.id) or name
	local reader = IsUsableSpell or (C_Spell and C_Spell.IsSpellUsable)
	local usable, insufficient = SafeCall(reader, identifier)
	if not SafeValue(usable) or type(usable) ~= "boolean" then usable = nil end
	if not SafeValue(insufficient) or type(insufficient) ~= "boolean" then insufficient = nil end
	return usable, insufficient, identifier
end

-- Proc-only abilities need a stricter usability check. Core deliberately
-- treats protected usability as permissive for normal rotational spells, but
-- doing that for Riposte would suggest it permanently. Prefer the readable
-- API and fall back to the combat-log parry window below when it is protected.
local function ReadableSpellUsable(name)
	local reader = IsUsableSpell or (C_Spell and C_Spell.IsSpellUsable)
	if type(reader) ~= "function" then return nil end
	local ok, usable = pcall(reader, name)
	if not ok or not SafeValue(usable) then return nil end
	return usable and true or false
end

-- Usability can distinguish missing resources from other failed requirements.
-- A true answer does not establish that we are behind the enemy.
local function ReadablePositionalUsable(name)
	local reader = IsUsableSpell or (C_Spell and C_Spell.IsSpellUsable)
	if type(reader) ~= "function" then return nil end
	local ok, usable, insufficientPower = pcall(reader, name)
	if not ok or not SafeValue(usable) then return nil end
	if usable then return true end
	if not SafeValue(insufficientPower) then return nil end
	return insufficientPower and true or false
end

local riposteUntil = 0
local function RiposteProcActive()
	local readable = ReadableSpellUsable("Riposte")
	if readable ~= nil then return readable end
	return GetTime and GetTime() < riposteUntil
end

-- Forever may hide IsUsableSpell in combat. A parried incoming swing/spell
-- opens Riposte for five seconds, so the combat log provides a conservative
-- fallback without turning an unknown usability value into a permanent proc.
if AL.playerClass == "ROGUE" and CreateFrame and CombatLogGetCurrentEventInfo then
	local procFrame = CreateFrame("Frame")
	if procFrame.RegisterEvent and procFrame.SetScript then
		procFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		procFrame:SetScript("OnEvent", function()
			local ok, _, subEvent, _, _, _, _, _, destGUID, _, _, _, swingMiss, _, _, spellMiss =
				pcall(CombatLogGetCurrentEventInfo)
			if not ok or not SafeValue(subEvent) or not SafeValue(destGUID) then return end
			if not UnitGUID or destGUID ~= UnitGUID("player") then return end
			local missType = subEvent == "SWING_MISSED" and swingMiss
				or (subEvent == "SPELL_MISSED" and spellMiss)
			if SafeValue(missType) and missType == "PARRY" then
				riposteUntil = (GetTime and GetTime() or 0) + 5
			end
		end)
	end
end

local function WeaponIsDagger(slot)
	local itemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
	if not GetInventoryItemID or not itemInfoInstant then return nil end
	local okItem, itemID = pcall(GetInventoryItemID, "player", slot)
	if not okItem or not SafeValue(itemID) or not itemID then return false end
	local okInfo, _, _, _, _, _, classID, subclassID = pcall(itemInfoInstant, itemID)
	if not okInfo or not SafeValue(classID) or not SafeValue(subclassID) then return nil end
	local daggerID = Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Dagger or 15
	return classID == 2 and subclassID == daggerID
end

local function MainHandIsDagger() return WeaponIsDagger(16) end
local function TwoDaggers() return MainHandIsDagger() == true and WeaponIsDagger(17) == true end

-- The interact check is approximately ten yards, not melee range. It is only
-- used outside combat to prepare Stealth; attacks require their own spell range.
local function WithinStealthRange()
	local near = SafeCall(CheckInteractDistance, "target", 3)
	if SafeValue(near) and (near == true or near == 1) then return true end
	local melee = SafeCall(AL.InRange, "Sinister Strike")
	return SafeValue(melee) and melee == true
end

-- Spell range is authoritative. An unknown spell range must not turn the
-- ten-yard Stealth check into a claim that Backstab is in melee range.
local function InMeleeRange(spell)
	if AL.InRange then
		local ok, inRange = pcall(AL.InRange, spell or "Sinister Strike")
		if ok and SafeValue(inRange) and inRange ~= nil then return inRange == true end
	end
	return false
end

local function ConfirmedHostileTarget()
	if type(UnitExists) ~= "function" or type(UnitCanAttack) ~= "function" then return false end
	local okExists, exists = pcall(UnitExists, "target")
	local okAttack, attack = pcall(UnitCanAttack, "player", "target")
	if not okExists or not okAttack or not SafeValue(exists) or not SafeValue(attack) then return false end
	return exists and attack and true or false
end

local function ValidPercent(value)
	value = ReadableNumber(value)
	return value and value >= 0 and value <= 100 and value or nil
end

local function BarPercent(bar)
	if not bar then return nil end
	local value = ReadableNumber((SafeCall(bar.GetValue, bar)))
	local minimum, maximum = SafeCall(bar.GetMinMaxValues, bar)
	minimum, maximum = ReadableNumber(minimum), ReadableNumber(maximum)
	if value == nil or minimum == nil or maximum == nil or maximum <= minimum then return nil end
	if value < minimum or value > maximum then return nil end
	-- A dormant target bar can remain at 1/1, including with no target.
	-- That default cannot establish that the live target has full health.
	if minimum == 0 and maximum == 1 and value == 1 then return nil end
	return (value - minimum) / (maximum - minimum) * 100
end

local function TextPercent(fontString)
	if not fontString then return nil end
	local text = SafeCall(fontString.GetText, fontString)
	if not SafeValue(text) or type(text) ~= "string" then return nil end
	text = text:gsub(",", "")
	local pct = tonumber(text:match("(%d+%.?%d*)%s*%%"))
	if pct then return ValidPercent(pct) end
	local current, maximum = text:match("(%d+)%s*/%s*(%d+)")
	current, maximum = tonumber(current), tonumber(maximum)
	if current and maximum and maximum > 0 and current <= maximum then return current / maximum * 100 end
end

local function TargetHealthBars()
	local bars, seen = {}, {}
	local function Add(path, bar, owner)
		if not bar or not SafeValue(bar) or seen[bar] then return end
		seen[bar] = true
		bars[#bars + 1] = { path = path, bar = bar, owner = owner }
	end
	local frame = _G.TargetFrame
	local content = frame and frame.TargetFrameContent
	local main = content and content.TargetFrameContentMain
	local area = main and main.HealthBarsContainer
	-- Prefer the active legacy frame references; the retail-shaped container
	-- can exist in Forever without being the bar that is actually updated.
	Add("TargetFrame.healthbar", frame and frame.healthbar, frame)
	Add("TargetFrameHealthBar", _G.TargetFrameHealthBar, frame)
	Add("TargetFrame.HealthBarsContainer.HealthBar", area and area.HealthBar, frame)
	Add("TargetFrameContentMain.HealthBar", main and main.HealthBar, frame)
	local plate = SafeCall(C_NamePlate and C_NamePlate.GetNamePlateForUnit, "target")
	if plate and SafeValue(plate) then
		local unitFrame = plate.UnitFrame
		local container = unitFrame and unitFrame.HealthBarsContainer
		Add("TargetNamePlate.UnitFrame.healthBar", unitFrame and unitFrame.healthBar, unitFrame)
		Add("TargetNamePlate.UnitFrame.HealthBar", unitFrame and unitFrame.HealthBar, unitFrame)
		Add("TargetNamePlate.HealthBarsContainer.HealthBar", container and container.HealthBar, unitFrame)
	end
	return bars
end

local function CurrentTargetBar(entry)
	local shown = SafeCall(entry.bar.IsShown, entry.bar)
	if not SafeValue(shown) or shown == false then return false, "hidden/protected visibility" end
	local unit = entry.bar.unit
	if SafeValue(unit) and unit == nil and entry.owner then unit = entry.owner.unit end
	if not SafeValue(unit) then return false, "protected unit binding" end
	if type(unit) == "string" and unit ~= "target" then
		local same = SafeCall(UnitIsUnit, unit, "target")
		if not SafeValue(same) or same ~= true then return false, "different unit" end
	end
	return true, "target frame"
end

local function HealthPercent(unit)
	local exists = SafeCall(UnitExists, unit)
	if not SafeValue(exists) or exists ~= true then return nil, "no readable unit" end
	local hp = ValidPercent((SafeCall(AL.HealthPercent, unit)))
	if hp ~= nil then return hp, "UnitHealth" end
	local curve = CurveConstants and CurveConstants.ScaleTo100
	local normalized = ReadableNumber((SafeCall(UnitHealthPercent, unit, false, curve)))
	if normalized ~= nil then
		-- With ScaleTo100, 1 is one percent. Without a curve, the helper returns
		-- a fraction; do not confuse those two contracts at low target health.
		if not curve then normalized = normalized * 100 end
		hp = ValidPercent(normalized)
		if hp ~= nil then return hp, "UnitHealthPercent" end
	end
	if A and type(A.Unit) == "function" then
		local object = SafeCall(A.Unit, unit)
		if object then
			hp = ValidPercent((SafeCall(object.HealthPercent, object)))
			if hp ~= nil then return hp, "Action health" end
		end
	end
	if unit == "target" then
		local bars = TargetHealthBars()
		-- A visible percentage label is more useful than a default filled bar.
		local frame = _G.TargetFrame
		local frameShown = frame and SafeCall(frame.IsShown, frame)
		if SafeValue(frameShown) and frameShown ~= false then
			hp = TextPercent(_G.TargetFrameHealthBarText)
			if hp ~= nil then return hp, "TargetFrameHealthBarText" end
		end
		for _, entry in ipairs(bars) do
			if CurrentTargetBar(entry) then
				hp = TextPercent(entry.bar.TextString) or TextPercent(entry.bar.RightText)
				if hp ~= nil then return hp, entry.path .. " text" end
			end
		end
		for _, entry in ipairs(bars) do
			if CurrentTargetBar(entry) then
				hp = BarPercent(entry.bar)
				if hp ~= nil then return hp, entry.path end
			end
		end
	end
	return nil, "protected/unavailable"
end

local function TargetClassification()
	local value = SafeCall(UnitClassification, "target")
	if SafeValue(value) and type(value) == "string" then return value end
end

local function EvisceratePoints()
	local classification = TargetClassification()
	if classification == "normal" or classification == "minus" or classification == "trivial" then return 1 end
	-- Rare, elite, rareelite and worldboss require five. Unknown classification
	-- stays conservative rather than assuming that a hidden target is normal.
	return 5
end

local openerBlocked = false
local lastSuccessfulCastAt
local lastRotation
local AddAction, FinishDecision, EnergyGate, EnergyCost, CombatCastResult

function M.OnTargetChanged()
	if SubTargetChanged then SubTargetChanged() end
	openerBlocked = false
	lastRotation, AL.rogueSecretVisual = nil, nil
end

function M.OnUIError(message)
	if not SafeValue(message) or type(message) ~= "string" then return end
	if (SPELL_FAILED_NOT_BEHIND and message == SPELL_FAILED_NOT_BEHIND)
		or (ERR_BADATTACKPOS and message == ERR_BADATTACKPOS)
	then
		openerBlocked = true
	end
end

function M.OnCastResult(name, event, sent)
	if CombatCastResult then CombatCastResult(name, event) end
	if SubCastResult then SubCastResult(name, event, sent) end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		lastSuccessfulCastAt = GetTime()
		if name == "Backstab" then openerBlocked = false end
	end
end

local function RecoverStaleComboPoints(cp)
	if cp <= 0 then return cp end
	-- Forever's readable zero alone is unreliable. Require two independently
	-- unusable finishers with readable non-energy failures and a usable builder.
	local native = ReadableNumber((SafeCall(GetComboPoints, "player", "target")))
	local typed = ReadableNumber((SafeCall(UnitPower, "player", 4)))
	if native ~= 0 or typed ~= 0 then return cp end
	if lastSuccessfulCastAt and GetTime() - lastSuccessfulCastAt < 1.5 then
		return cp
	end
	if not Ok("Slice and Dice") or not Ok("Eviscerate")
		or not AL.IsReady("Slice and Dice") or not AL.IsReady("Eviscerate")
		or AL.HasBuff("player", "Slice and Dice") then
		return cp
	end
	local sndUsable, sndShortage = SpellUsability("Slice and Dice")
	local eviUsable, eviShortage = SpellUsability("Eviscerate")
	if sndUsable ~= false or sndShortage ~= false or eviUsable ~= false or eviShortage ~= false then
		return cp
	end
	local builderUsable, builderShortage = SpellUsability("Sinister Strike")
	if not Ok("Sinister Strike") or builderUsable ~= true or builderShortage ~= false
		or not InMeleeRange("Sinister Strike") then
		return cp
	end
	if type(AL.ResetComboPoints) ~= "function" then return cp end
	AL.ResetComboPoints()
	if SubTargetChanged then SubTargetChanged(true) end
	return 0
end

function M.CanTrackSuggestedSpell(name)
	if not Ok(name) then return false end
	-- A secret-health visual has two possible displayed actions. Never assume
	-- that a hidden cast ID was the underlying builder rather than Eviscerate.
	local visual = AL.rogueSecretVisual
	if visual and GetTime() - visual.at <= 0.5 and (name == visual.baseSpell or (visual.spells and visual.spells[name]) or name == visual.spell) then return false end
	for _, entry in ipairs(M.spells) do if entry[2] == name then return true end end
	return false
end

local function ActiveEnemyCount(limit, engagedOnly)
	if A and A.MultiUnits then
		if A.MultiUnits.GetActiveEnemies then
			local count = ReadableNumber((SafeCall(A.MultiUnits.GetActiveEnemies, A.MultiUnits, 5)))
			if count and count >= 0 and count <= 40 and count == math.floor(count) then return count, "Action melee enemy count" end
		end
		if A.MultiUnits.GetByRangeInCombat then
			local count = ReadableNumber((SafeCall(A.MultiUnits.GetByRangeInCombat, A.MultiUnits, 5, limit or 5)))
			if count and count >= 0 and count <= 40 and count == math.floor(count) then return count, "Action range enemy count" end
		end
	end
	-- Count only distinct hostile units with readable melee range. A hidden
	-- count cannot satisfy a user-selected minimum of two or more enemies.
	local seen, count = {}, 0
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs["Sinister Strike"]
	local function Count(unit)
		if not SafeValue(unit) or type(unit) ~= "string" then return end
		local exists = SafeCall(UnitExists, unit)
		local hostile = SafeCall(UnitCanAttack, "player", unit)
		local dead = SafeCall(UnitIsDeadOrGhost, unit)
		if not SafeValue(exists) or exists ~= true or not SafeValue(hostile) or hostile ~= true
			or not SafeValue(dead) or dead ~= false then return end
		local guid = SafeCall(UnitGUID, unit)
		if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] then return end
		local fighting = SafeCall(UnitAffectingCombat, unit)
		if (engagedOnly or unit ~= "target") and (not SafeValue(fighting) or fighting ~= true) then return end
		local inRange
		if unit == "target" then inRange = SafeCall(AL.InRange, "Sinister Strike")
		elseif ref and C_Spell then inRange = SafeCall(C_Spell.IsSpellInRange, ref.id, unit) end
		if not SafeValue(inRange) or (inRange ~= true and inRange ~= 1) then return end
		seen[guid], count = true, count + 1
	end
	Count("target")
	local plates = C_NamePlate and SafeCall(C_NamePlate.GetNamePlates)
	if SafeValue(plates) and type(plates) == "table" then
		for _, plate in pairs(plates) do
			if SafeValue(plate) and type(plate) == "table" then
				Count(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
			end
		end
	end
	if count > 0 then return count, "confirmed visible melee enemies (lower bound)" end
	return nil, "enemy count unavailable"
end

local function TryOpener(name, s)
	if not Ok(name) or not InMeleeRange(name) then return nil end
	if openerBlocked and (name == "Backstab" or name == "Ambush" or name == "Garrote") then return nil end
	if name == "Backstab" or name == "Ambush" then
		if MainHandIsDagger() == false or openerBlocked then return nil end
	end
	if name == "Backstab" or name == "Ambush" or name == "Garrote" then
		if ReadablePositionalUsable(name) == false then return nil end
	elseif not AL.SpellUsable(name) then
		return nil
	end
	local minimum = name == "Backstab" and SettingNumber(s, "backstabMinEnergy", 60, 20, 100)
		or (name == "Cheap Shot" and 40 or (name == "Garrote" and 50 or 60))
	local energy = ReadableNumber(AL.Power(3))
	minimum = math.max(minimum, EnergyCost(name, name == "Cheap Shot" and 40 or (name == "Garrote" and 50 or 60)))
	if energy and energy < minimum then
		AddAction(nil, "Pool energy for " .. name); return FinishDecision()
	end
	if not AddAction(name, "stealth opener", { EnergyGate(energy, minimum, name) }) then return nil end
	AddAction(nil, "Pool energy for " .. name)
	return FinishDecision()
end

local function StealthOpener(s)
	if not AL.HasBuff("player", "Stealth") then return nil end
	local mode = SettingChoice(s, "openerMode", {
		AUTO = true, BACKSTAB = true, CHEAP_SHOT = true, AMBUSH = true, GARROTE = true,
	}, "BACKSTAB")

	local orders = {
		AUTO = { "Backstab", "Ambush", "Cheap Shot", "Garrote" },
		BACKSTAB = { "Backstab", "Cheap Shot", "Garrote", "Ambush" },
		CHEAP_SHOT = { "Cheap Shot", "Ambush", "Garrote" },
		AMBUSH = { "Ambush", "Cheap Shot", "Garrote" },
		GARROTE = { "Garrote", "Cheap Shot", "Ambush" },
	}
	for _, name in ipairs(orders[mode]) do
		local spell, poolReason = TryOpener(name, s)
		if spell then return spell, "stealth opener" end
		if poolReason then return nil, poolReason end
	end
	return nil
end

local function Builder(s)
    if s.combat ~= true and s.subtlety ~= true and s.assassination ~= true and AL.DPS60 and AL.DPS60.Active() then
        local automatic = AL.known["Mutilate"] and "ASSASSINATION" or AL.known["Hemorrhage"] and "SUBTLETY" or "COMBAT"
        local build = AL.DPS60.Build("ROGUE", s, automatic)
        local name = build == "ASSASSINATION" and "Mutilate" or build == "SUBTLETY" and "Hemorrhage"
        if name and Ok(name) and AL.DPS60.Ready(name) and InMeleeRange(name) then
            local usable, shortage = SpellUsability(name)
            if usable ~= false and shortage ~= true then return name, EnergyCost(name, name == "Mutilate" and 60 or 35) end
        end
    end
	-- No reliable behind-target signal is supplied. A saved BACKSTAB builder
	-- preference must not trap combat at the front of the target.
	if Ok("Sinister Strike") then
		return "Sinister Strike", SettingNumber(s, "sinisterMinEnergy", 45, 20, 100)
	end
	return nil
end

-- Protected values are evaluated by the client for display only. All rows
-- below describe public threshold intervals, never measured/guessed HP or
-- energy. Native parent-frame alpha combines their independent masks; Lua
-- does not inspect, compare, multiply, or stringify protected alpha values.
local visibilityCurves, curveFailures = {}, {}
local energyMaximumCache
local function CurveAvailable(kind, unit)
	local reader = UnitHealthPercent
	if kind == "energy" then reader = UnitPowerPercent; unit = "player" end
	unit = unit or "target"
	local failure = curveFailures[kind .. ":" .. unit]
	if failure and failure.reader == reader then return false end
	return C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function"
		and type(CreateColor) == "function"
		and type(reader) == "function"
end

local function NextFloat32(value)
	if value <= 0 then return 2 ^ -149 end
	local exponent = math.floor(math.log(value) / math.log(2))
	local step = 2 ^ (exponent - 23)
	return (math.floor(value / step + 0.5) + 1) * step
end

local function HealthGate(unit, value, threshold, below)
	if value ~= nil then return below and value <= threshold or not below and value >= threshold end
	if below and threshold >= 100 or not below and threshold <= 0 then return true end
	if not CurveAvailable("health", unit) then return false end
	return { axis = unit == "player" and "playerHP" or "targetHP", kind = "health", unit = unit,
		cut = below and NextFloat32(threshold / 100) or threshold / 100, below = below,
		threshold = threshold }
end

EnergyCost = function(spell, fallback)
	local reader = C_Spell and C_Spell.GetSpellPowerCost
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[spell]
	if type(reader) == "function" then
		local ok, cost = pcall(function()
			local costs = reader(ref and ref.id or spell)
			if not SafeValue(costs) or type(costs) ~= "table" then return end
			for _, entry in pairs(costs) do
				if SafeValue(entry) and type(entry) == "table" then
					local power = ReadableNumber(entry.type)
					local amount = ReadableNumber(entry.cost)
					if power == 3 and amount and amount >= 0 then return amount end
				end
			end
		end)
		if ok and cost ~= nil then return cost end
	end
	return fallback
end

EnergyGate = function(energy, minimum, spell)
	local usable = SpellUsability(spell)
	if usable == false or (usable == nil and not AL.SpellUsable(spell)) then return false end
	if energy ~= nil then return energy >= minimum end
	local maximum = lastRotation.energyMaximum
	if maximum and maximum > 0 and CurveAvailable("energy") then
		if minimum <= 0 then return true end
		if minimum > maximum then return false end
		return { axis = "energy", kind = "energy", unit = "player", cut = minimum / maximum,
			below = false, threshold = minimum }
	end
	return usable == true or AL.SpellUsable(spell)
end

local function FinisherAvailable(spell)
	local usable, insufficient = SpellUsability(spell)
	return AL.IsReady(spell) and (usable ~= false or insufficient == true)
end

-- Class-local cooldowns keep this build compatible with the existing Core.
-- A readable cooldown for the learned rank wins; hidden data uses only our
-- own successful casts. Talent spells are gated by learning, not a guessed level.
local combatCooldowns = { ["Adrenaline Rush"] = 300, ["Blade Flurry"] = 120,
	["Blood Fury"] = 120, ["Berserking"] = 180, ["Cold Blood"] = 180,
	["Ghostly Strike"] = 20, ["Premeditation"] = 120, ["Preparation"] = 600, ["Vanish"] = 300, ["Stealth"] = 10 }
local combatDurations = { ["Adrenaline Rush"] = 15, ["Blade Flurry"] = 15,
	["Blood Fury"] = 15, ["Berserking"] = 10, ["Ghostly Strike"] = 7, ["Vanish"] = 10,
	["Cold Blood"] = math.huge }
local combatEnds, combatCastAt, combatBuffEnds, combatRetry = {}, {}, {}, {}
local combatIDs = {}
for _, entry in ipairs(M.spells) do combatIDs[entry[2]] = entry[1] end

local function CombatID(name)
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	return ref and ReadableNumber(ref.id) or combatIDs[name] or name
end

local function CombatCooldown(name)
	local reader = C_Spell and C_Spell.GetSpellCooldown
	if type(reader) == "function" then
		local info = SafeCall(reader, CombatID(name))
		if SafeValue(info) and type(info) == "table" then
			if SafeValue(info.isEnabled) and info.isEnabled == false then return false end
			local start, duration = ReadableNumber(info.startTime), ReadableNumber(info.duration)
			local rate = ReadableNumber(info.modRate) or 1
			if start and duration and start >= 0 and duration >= 0 and rate > 0 then
				return true, (start == 0 or duration <= 1.5) and 0 or start + duration / rate
			end
		end
	end
	local start, duration = SafeCall(GetSpellCooldown, CombatID(name))
	start, duration = ReadableNumber(start), ReadableNumber(duration)
	if start and duration and start >= 0 and duration >= 0 then
		return true, (start == 0 or duration <= 1.5) and 0 or start + duration
	end
end

local function CombatReady(name)
	if not Ok(name) then return false end
	local now = GetTime()
	if (combatRetry[name] or 0) > now then return false end
	-- Ignore a stale zero/GCD immediately following a successful cast.
	if combatCastAt[name] and now - combatCastAt[name] < 1 then return false end
	local enabled, expires = CombatCooldown(name)
	if enabled == false then return false end
	if expires ~= nil then
		combatEnds[name] = expires
		return expires <= now
	end
	return (combatEnds[name] or 0) <= now
end

local function CombatBuff(name)
	if combatCastAt[name] and GetTime() - combatCastAt[name] < 0.5 then return true end
	if name == "Cold Blood" and SubAura then
		local active = SubAura("player", name)
		if active ~= nil then
			if not active then combatBuffEnds[name] = nil end
			return active
		end
		return (combatBuffEnds[name] or 0) > GetTime()
	end
	local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if type(reader) == "function" then
		local readable = true
		for index = 1, 40 do
			local ok, aura = pcall(reader, "player", index, "HELPFUL")
			if not ok or not SafeValue(aura) then readable = false; break end
			if aura == nil then return false end
			if type(aura) ~= "table" then readable = false; break end
			local id, auraName = ReadableNumber(aura.spellId), aura.name
			if not SafeValue(auraName) or not id and type(auraName) ~= "string" then readable = false; break end
			local english = type(auraName) == "string" and ((AL.englishNames and AL.englishNames[auraName]) or auraName)
			if id == CombatID(name) or english == name then return true end
		end
		if readable then return false end
	end
	return (combatBuffEnds[name] or 0) > GetTime() or AL.HasBuff("player", name)
end

CombatCastResult = function(name, event)
	if not name or not combatCooldowns[name] then return end
	local now = GetTime()
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		combatCastAt[name] = now
		local _, expires = CombatCooldown(name)
		combatEnds[name] = expires and expires > now and expires or now + combatCooldowns[name]
		combatBuffEnds[name] = combatDurations[name] and now + combatDurations[name] or nil
		combatRetry[name] = nil
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
		or event == "UNIT_SPELLCAST_INTERRUPTED" then
		combatRetry[name] = now + 0.5
	end
end

local function CombatLowEnergy(energy, threshold)
	if energy ~= nil then return energy <= threshold end
	local maximum = lastRotation.energyMaximum
	if maximum and maximum > 0 and CurveAvailable("energy") then
		if threshold >= maximum then return true end
		return { axis = "energy", kind = "energy", unit = "player", below = true,
			cut = NextFloat32(threshold / maximum), threshold = threshold }
	end
	-- No readable energy or native display gate: defer this cooldown, keep attacking.
	return false
end

local function CombatRotation(s, cp, energy, targetHP)
	if not ConfirmedHostileTarget() or not InMeleeRange("Sinister Strike") then
		AddAction(nil, "Approach target"); return FinishDecision()
	end
	-- A first point establishes Slice and Dice. If an opener/proc grants more
	-- points, still repair a missing buff; never refresh it while it is active.
	local maintainSnd = false
	if s.snd and cp >= 1 and not AL.HasBuff("player", "Slice and Dice") and Ok("Slice and Dice")
		and FinisherAvailable("Slice and Dice") then
		AddAction("Slice and Dice", "Combat: establish missing player buff", {
			EnergyGate(energy, EnergyCost("Slice and Dice", 25), "Slice and Dice") })
		maintainSnd = true
	end

	-- AoE is independent of Burst and its target-health slider. Blade Flurry
	-- is the build's cleave; it requires the AoE toggle and confirmed melee enemies.
	if s.aoe and s.bladeFlurry then
		local minimum = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
		local count = ActiveEnemyCount(minimum, true)
		if count and count >= minimum and CombatReady("Blade Flurry") and not CombatBuff("Blade Flurry") then
			AddAction("Blade Flurry", "Combat AoE: confirmed melee enemies", {
				EnergyGate(energy, EnergyCost("Blade Flurry", 25), "Blade Flurry") })
		end
	end

	if AL.burst then
		local healthGate = HealthGate("target", targetHP, SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false)
		if s.combatAdrenalineRush and CombatReady("Adrenaline Rush") and not CombatBuff("Adrenaline Rush") then
			AddAction("Adrenaline Rush", "Combat burst: low energy", { healthGate,
				CombatLowEnergy(energy, SettingNumber(s, "combatAdrenalineEnergy", 60, 0, 100)),
				EnergyGate(energy, EnergyCost("Adrenaline Rush", 0), "Adrenaline Rush") })
		end
		if s.combatRacials then
			for _, name in ipairs({ "Blood Fury", "Berserking" }) do
				if CombatReady(name) and not CombatBuff(name) then
					AddAction(name, "Combat burst: racial", { healthGate,
						EnergyGate(energy, EnergyCost(name, 0), name) })
				end
			end
		end
	end
	if maintainSnd then
		-- An unaffordable buff may use Burst's energy-regeneration cooldown
		-- first; otherwise reserve its energy instead of buying another builder.
		AddAction(nil, "Pool energy for Slice and Dice"); return FinishDecision()
	end

	-- Five-point finishers prevent combo-point waste above the leveling execute
	-- threshold. Preserve the normal-target <=50% one-point execute fallback.
	local execute = cp >= EvisceratePoints() and HealthGate("target", targetHP, 50, true)
	local finish = cp >= 5 or execute
	local finishers = {}
	if Ok("Eviscerate") then finishers[1] = "Eviscerate"
	else
		if s.rupture and cp >= SettingNumber(s, "ruptureMinCP", 4, 1, 5)
			and not AL.HasDebuff("target", "Rupture") and Ok("Rupture") then finishers[#finishers + 1] = "Rupture" end
		if s.expose and cp >= SettingNumber(s, "exposeMinCP", 4, 1, 5)
			and not AL.HasDebuff("target", "Expose Armor") and Ok("Expose Armor") then finishers[#finishers + 1] = "Expose Armor" end
	end
	for _, finisher in ipairs(finishers) do
		if finish and FinisherAvailable(finisher) then
			AddAction(finisher, "Combat: combo-point finisher", { finish,
				EnergyGate(energy, EnergyCost(finisher, finisher == "Eviscerate" and 35 or 25), finisher) })
			AddAction(nil, "Pool energy for " .. finisher, { finish })
		end
	end
	-- At five points an unaffordable or disabled finisher must not select a
	-- builder that cannot add points. Interrupts and defensives were checked first.
	if cp >= 5 then
		AddAction(nil, "Combat: waiting for an enabled finisher"); return FinishDecision()
	end
	local builder, minimum = Builder(s)
	if builder then
		minimum = math.max(minimum, EnergyCost(builder, 45))
		AddAction(builder, "Combat: Sinister Strike builder", { EnergyGate(energy, minimum, builder) })
		AddAction(nil, "Pool energy")
	else AddAction(AL.known["Attack"] and "Attack" or nil, "melee") end
	return FinishDecision()
end

AddAction = function(spell, reason, gates)
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

FinishDecision = function()
	local actions = lastRotation.actions
	local base = actions[#actions]
	if not base or #base.conditions > 0 then
		AddAction(nil, "Ready")
		base = actions[#actions]
	end
	lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
	return base.spell, base.reason
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
				axis = { key = c.axis, kind = c.kind, unit = c.unit, cuts = { 0, 2 }, seen = { [0] = true, [2] = true } }
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
				local mask = { key = key, kind = axis.kind, unit = axis.unit, low = low, high = high }
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
				if mask.kind == "energy" then color = UnitPowerPercent(mask.unit, 3, false, curve)
				else color = UnitHealthPercent(mask.unit, false, curve) end
				local _, _, _, alpha = color:GetRGBA()
				return alpha
			end)
			if not success then
				curveFailures[mask.kind .. ":" .. mask.unit] = {
					reader = mask.kind == "energy" and UnitPowerPercent or UnitHealthPercent }
				error("Rogue resource curve unavailable")
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

-- Compatibility helpers for the already validated Eviscerate health display.
function M.ApplySecretHealthVisibility(widget, below, r, g, b)
	local cut = NextFloat32(0.5)
	local mask = { key = "compat", kind = "health", unit = "target", low = below and 0 or cut, high = below and cut or 2 }
	local values, err = M.EvaluateVisualMasks({ masks = { compat = mask } })
	if not values then return false, err end
	if r ~= nil then widget:SetVertexColor(r, g, b, values.compat) else widget:SetAlpha(values.compat) end
	return true
end

function M.SecretFinisherVisualState(spell, reason)
	local plan = M.SecretVisualPlan(spell, reason)
	if plan and plan.spells.Eviscerate then return "Eviscerate", 50, "Protected target HP; client evaluates <=50%" end
end

-- Subtlety adds target-bound points and aura timers without replacing Core.
-- In particular, the existing Core does not count Premeditation/Initiative
-- and uses a fixed Rupture duration. Native readable data remains preferred.
local subCombo, subSpentAt, subBefore, subPremedUntil, subPremedOnly
local subEpoch, subDots, subSnd, subLast, subPending = 0, {}, nil, nil, {}
local subTalents, subAuraCache, subAuraBlocked = nil, {}, {}
local subStealth, subStealthAt
local subBuilders = { ["Sinister Strike"] = 1, Backstab = 1, Gouge = 1, Ambush = 1,
	Garrote = 1, ["Cheap Shot"] = 2, Riposte = 1, Hemorrhage = 1, ["Ghostly Strike"] = 1 }
subBuilders.Mutilate = 2
local subFinishers = { Eviscerate = true, ["Slice and Dice"] = true, Rupture = true,
	["Kidney Shot"] = true, ["Expose Armor"] = true, Venom = true }
local subResetSpells = { "Vanish", "Premeditation", "Ghostly Strike", "Stealth", "Sprint",
	"Evasion", "Gouge", "Kick", "Kidney Shot", "Riposte", "Blade Flurry", "Adrenaline Rush", "Cold Blood" }

local function SubGUID(unit)
	local guid = SafeCall(UnitGUID, unit)
	if SafeValue(guid) and type(guid) == "string" then return guid end
end

local function SubTalent(name)
	if not subTalents then
		subTalents = {}
		for tab = 1, 3 do for index = 1, 40 do
			local talent, _, _, _, rank = SafeCall(GetTalentInfo, tab, index, false, false)
			if SafeValue(talent) and type(talent) == "string" and ReadableNumber(rank) then
				local english = (AL.englishNames and AL.englishNames[talent]) or talent
				subTalents[english] = rank
				for key, id in pairs({ Initiative = 13976, ["Improved Slice and Dice"] = 14165,
					Elusiveness = 13981, Camouflage = 13975, ["Seal Fate"] = 14186 }) do
					local localized = SafeCall(C_Spell and C_Spell.GetSpellName, id)
					if SafeValue(localized) and localized == talent then subTalents[key] = rank end
				end
			end
		end end
	end
	return subTalents[name]
end

SubAura = function(unit, name)
	local key, now = unit .. ":" .. name, GetTime()
	local cached = subAuraCache[key]
	if cached and now - cached.at < 0.1 then return cached.active, cached.expires end
	local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	local function Read()
		if type(reader) ~= "function" or subAuraBlocked[unit] == reader then return end
		for index = 1, 40 do
			local ok, aura = pcall(reader, unit, index, unit == "player" and "HELPFUL" or "HARMFUL")
			if not ok or not SafeValue(aura) then subAuraBlocked[unit] = reader; return end
			if aura == nil then return false end
			if type(aura) ~= "table" then return end
			local id, auraName = ReadableNumber(aura.spellId), aura.name
			if not SafeValue(auraName) or not id and type(auraName) ~= "string" then return end
			local english = type(auraName) == "string" and ((AL.englishNames and AL.englishNames[auraName]) or auraName)
			if id == CombatID(name) or english == name then
				local own = aura.isFromPlayerOrPlayerPet
				local source = aura.sourceUnit
				if unit == "player" or SafeValue(own) and own == true
					or SafeValue(source) and (source == "player" or source == "pet") then
					return true, ReadableNumber(aura.expirationTime)
				end
				if not SafeValue(own) or not SafeValue(source) or own == nil and source == nil then return end
			end
		end
	end
	local active, expires = Read()
	subAuraCache[key] = { at = now, active = active, expires = expires }
	return active, expires
end

local function SubDot(name)
	local own = subDots[name]
	if own and GetTime() - own.at < 0.5 then return own.expires > GetTime() end
	local active, expires = SubAura("target", name)
	if active ~= nil then
		if active and expires and expires > GetTime() then subDots[name] = { at = GetTime(), expires = expires } end
		if not active then subDots[name] = nil end
		return active
	end
	if own then return own.expires > GetTime() end
	return AL.HasDebuff("target", name)
end

local function SubSndActive()
	if subSnd and GetTime() - subSnd.at < 0.5 then return true end
	local active, expires = SubAura("player", "Slice and Dice")
	if active ~= nil then
		if active and expires and expires > GetTime() then subSnd = { at = GetTime(), expires = expires } end
		if not active then subSnd = nil end
		return active
	end
	if subSnd then return subSnd.expires > GetTime() end
	return AL.HasBuff("player", "Slice and Dice")
end

local function SubSndDuration(points)
	local text = SafeCall(C_Spell and C_Spell.GetSpellDescription or GetSpellDescription, CombatID("Slice and Dice"))
	if SafeValue(text) and type(text) == "string" then
		local value = tonumber(text:lower():match(points .. "%s+points?%s*:%s*(%d+%.?%d*)%s+sec"))
		if value and value > 0 and value <= 120 then return value end
	end
	local rank = SubTalent("Improved Slice and Dice")
	return (6 + 3 * points) * (1 + 0.15 * math.max(0, math.min(3, rank or 0)))
end

RoguePoints = function()
	local raw = ReadableNumber(AL.ComboPoints()) or 0
	if subPremedOnly and subPremedUntil and GetTime() >= subPremedUntil then
		local native = ReadableNumber((SafeCall(GetComboPoints, "player", "target")))
		local typed = ReadableNumber((SafeCall(UnitPower, "player", 4)))
		if native and native > 0 or typed and typed > 0 then subCombo = math.max(native or 0, typed or 0)
		else subCombo = 0; raw = 0; if AL.ResetComboPoints then AL.ResetComboPoints() end end
		subPremedUntil, subPremedOnly = nil, nil
	end
	local trackedBuild = AL.S().subtlety == true or AL.S().assassination == true
	if subCombo == nil and trackedBuild then subCombo = raw end
	if subCombo == nil then return raw end
	if trackedBuild then
		local primary = ReadableNumber((SafeCall(GetComboPoints, "player", "target")))
		local typed = ReadableNumber((SafeCall(UnitPower, "player", 4)))
		local native = primary and primary > 0 and primary or typed and typed > 0 and typed
		local lagging = subLast and GetTime() - subLast.at < 0.5 and native == subLast.before
		if subLast and subLast.sealFate and GetTime() - subLast.at < 0.5
			and native == math.min(5, subLast.before + (subBuilders[subLast.name] or 0)) then lagging = true end
		if native and native <= 5 and native == math.floor(native)
			and not lagging and not (subSpentAt and GetTime() - subSpentAt < 0.5 and native == subBefore) then subCombo = native end
		return math.min(5, subCombo)
	end
	if subSpentAt and GetTime() - subSpentAt < 0.5 and raw == subBefore then return subCombo end
	subCombo = math.max(subCombo, raw)
	return math.min(5, subCombo)
end

SubTargetChanged = function(comboOnly)
	subCombo, subLast, subSpentAt, subBefore, subPremedUntil, subPremedOnly = nil, nil, nil, nil, nil, nil
	if not comboOnly then subEpoch = subEpoch + 1; subDots = {}; subAuraCache = {} end
end

SubReady = function(name)
	if not Ok(name) or (combatRetry[name] or 0) > GetTime() then return false end
	local resetAt = subReset[name]
	if resetAt then
		-- A confirmed Preparation has reset this spell even if Core still has
		-- its old inferred timer, or a native cooldown update arrives late.
		if GetTime() - resetAt < 0.5 then return true end
		local enabled, expires = CombatCooldown(name)
		if enabled == false then return false end
		if expires ~= nil then return expires <= GetTime() end
		return true
	end
	if combatCooldowns[name] then return CombatReady(name) end
	return AL.IsReady(name)
end

SubCastResult = function(name, event, sent)
	if not name then return end
	local snapshot = sent and sent.castGUID and subPending[sent.castGUID]
	if sent and sent.castGUID then subPending[sent.castGUID] = nil end
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		if (name == "Ambush" or name == "Mutilate") and (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED") then
			combatRetry[name] = GetTime() + 0.5
		end
		return
	end
	local now = GetTime()
	subReset[name] = nil
	-- The current Forever Mutilate hits can retain Cold Blood. Ordinary
	-- consuming attacks clear our fallback; readable aura data still wins.
	if name == "Sinister Strike" or name == "Backstab" or name == "Ambush" or name == "Eviscerate" then combatBuffEnds["Cold Blood"] = nil end
	if name == "Stealth" or name == "Vanish" then subStealth, subStealthAt = true, now
	elseif subBuilders[name] or subFinishers[name] and name ~= "Slice and Dice" then subStealth, subStealthAt = false, now end
	if name == "Vanish" or name == "Stealth" then
		local _, nativeEnd = CombatCooldown(name)
		if not nativeEnd or nativeEnd <= now then
			local rank = SubTalent(name == "Vanish" and "Elusiveness" or "Camouflage")
			if rank then
				local reduction = name == "Vanish" and 45 * math.max(0, math.min(2, rank))
					or rank > 0 and 1 + math.min(5, rank) or 0
				combatEnds[name] = now + math.max(0, combatCooldowns[name] - reduction)
			end
		end
	end
	if name == "Preparation" then
		for _, affected in ipairs(subResetSpells) do
			subReset[affected], combatEnds[affected], combatCastAt[affected], combatRetry[affected] = now, 0, nil, nil
		end
	end
	local before = snapshot and snapshot.points or math.max(subCombo or 0, sent and ReadableNumber(sent.comboBefore) or 0)
	before = math.max(0, math.min(5, before))
	if name == "Slice and Dice" then
		subSnd = { at = now, expires = now + SubSndDuration(math.max(1, before)) }
		subAuraCache["player:Slice and Dice"] = nil
	end
	local currentTarget = SubGUID("target")
	local matching = snapshot and snapshot.epoch == subEpoch and (not snapshot.foreign or name == "Slice and Dice" or name == "Venom")
		or not snapshot and currentTarget ~= nil and (not sent or sent.targetGUID == currentTarget)
	if not matching then return end
	local oldDot = subDots[name]
	if name == "Rupture" or name == "Hemorrhage" then
		subDots[name] = { at = now, expires = now + (name == "Rupture" and 6 + 2 * math.max(1, before) or 15) }
		subAuraCache["target:" .. name] = nil
	end
	local points = subBuilders[name] or (name == "Premeditation" and 2)
	local active = AL.S().subtlety == true or AL.S().assassination == true or subCombo ~= nil or name == "Premeditation"
	if active and (points or subFinishers[name]) then
		if (name == "Ambush" or name == "Garrote") and SubTalent("Initiative") == 3 then points = points + 1 end
		subLast = { name = name, before = before, at = now, epoch = subEpoch, dotBefore = oldDot }
		if points then
			subCombo = math.min(5, before + points)
			if name == "Premeditation" then subPremedUntil, subPremedOnly = now + 20, before == 0
			else subPremedOnly = false end
		else
			subBefore, subSpentAt, subCombo, subPremedOnly, subPremedUntil = before, now, 0, nil, nil
		end
	end
end

if AL.playerClass == "ROGUE" and CreateFrame then
	local stateFrame = CreateFrame("Frame")
	for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_AURA", "PLAYER_DEAD", "SPELLS_CHANGED",
		"PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_REGEN_ENABLED", "COMBAT_LOG_EVENT_UNFILTERED" }) do
		pcall(stateFrame.RegisterEvent, stateFrame, event)
	end
	stateFrame:SetScript("OnEvent", function(_, event, unit, target, guid)
		if event == "UNIT_SPELLCAST_SENT" then
			if not SafeValue(unit) or unit ~= "player" or not SafeValue(guid) or type(guid) ~= "string" then return end
			for key, value in pairs(subPending) do if GetTime() - value.at > 30 then subPending[key] = nil end end
			local targetName, realm = SafeCall(UnitName, "target")
			local foreign = false
			if SafeValue(target) and type(target) == "string" and target ~= ""
				and SafeValue(targetName) and type(targetName) == "string" then
				local full = SafeValue(realm) and type(realm) == "string" and realm ~= "" and targetName .. "-" .. realm or targetName
				foreign = target ~= targetName and target ~= full
			end
			subPending[guid] = { points = RoguePoints(), epoch = subEpoch, at = GetTime(), foreign = foreign }
		elseif event == "UNIT_AURA" then subAuraCache = {}
		elseif event == "PLAYER_DEAD" then subSnd = nil; subStealth = false; combatBuffEnds["Cold Blood"] = nil; subAuraBlocked = {}; SubTargetChanged()
		elseif event == "PLAYER_REGEN_ENABLED" then subAuraBlocked, subAuraCache = {}, {}
		elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED" then subTalents = nil
		elseif event == "COMBAT_LOG_EVENT_UNFILTERED" and CombatLogGetCurrentEventInfo then
			local ok, _, kind, _, source, _, _, _, dest, _, _, _, id, name, _, missType,
				_, _, _, _, _, critical = pcall(CombatLogGetCurrentEventInfo)
			local playerGUID, targetGUID = SubGUID("player"), SubGUID("target")
			if not ok or not playerGUID or not targetGUID or not SafeValue(kind)
				or not SafeValue(source) or source ~= playerGUID or not SafeValue(dest) or dest ~= targetGUID then return end
			-- At rank five a readable builder crit guarantees one Seal Fate point.
			-- Both Mutilate hands share its 0.5 second proc window; never count two.
			-- Protected crits and probabilistic lower ranks do not invent points.
			if kind == "SPELL_DAMAGE" and AL.S().assassination == true and subLast
				and subLast.epoch == subEpoch and GetTime() - subLast.at < 0.5
				and not subLast.sealFate and subBuilders[subLast.name]
				and SafeValue(critical) and critical == true and SubTalent("Seal Fate") == 5 then
				local english = SafeValue(name) and type(name) == "string" and ((AL.englishNames and AL.englishNames[name]) or name)
				if english == subLast.name or ReadableNumber(id) and id == CombatID(subLast.name) then
					subLast.sealFate = true
					subCombo = math.max(subCombo or 0, math.min(5, subLast.before + subBuilders[subLast.name] + 1))
				end
				return
			end
			if kind ~= "SPELL_MISSED" then return end
			if not SafeValue(missType) or type(missType) ~= "string" or missType == "ABSORB" or missType == "BLOCK" then return end
			if not SafeValue(name) or type(name) ~= "string" then name = nil end
			if ReadableNumber(id) then for spell in pairs(subBuilders) do if CombatID(spell) == id then name = spell end end
				if CombatID("Rupture") == id then name = "Rupture" end end
			name = name and ((AL.englishNames and AL.englishNames[name]) or name)
			if subLast and subLast.name == name and subLast.epoch == subEpoch and GetTime() - subLast.at < 3 then
				subCombo = subLast.before
				if name == "Rupture" or name == "Hemorrhage" then subDots[name] = subLast.dotBefore; subAuraCache["target:" .. name] = nil end
				subLast, subSpentAt = nil, nil
			end
		end
	end)
end

local function SubOffer(name, reason, energy, cost, gates)
	if not SubReady(name) then return false end
	local conditions = {}
	for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
	conditions[#conditions + 1] = EnergyGate(energy, EnergyCost(name, cost or 0), name)
	return AddAction(name, reason, conditions)
end

SubtletyRotation = function(s, inCombat, hostile, cp, energy, targetHP)
	if not hostile or not ConfirmedHostileTarget() then AddAction(nil, inCombat and "No target" or "Ready"); return FinishDecision() end
	local melee = InMeleeRange("Sinister Strike") or InMeleeRange("Hemorrhage")
	local stealth = SafeCall(IsStealthed)
	if not SafeValue(stealth) or type(stealth) ~= "boolean" then
		stealth = SubAura("player", "Stealth")
		if stealth == nil then stealth = subStealth end
		if stealth == nil then stealth = AL.HasBuff("player", "Stealth") end
	end
	if subStealth == true and subStealthAt and GetTime() - subStealthAt < 0.5 then stealth = true end
	if not inCombat and s.stealth and not stealth and WithinStealthRange() and SubReady("Stealth") then
		AddAction("Stealth", "Subtlety: opener setup"); return FinishDecision()
	end
	if not melee then AddAction(nil, "Approach target"); return FinishDecision() end
	local burstGate = HealthGate("target", targetHP, SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false)
	if stealth then
		if AL.burst and s.subtletyPremeditation and cp <= 3 then SubOffer("Premeditation", "Subtlety Burst: stealth combo points", energy, 0, { burstGate }) end
		if s.subtletyAmbush and cp < 5 and not openerBlocked and MainHandIsDagger() == true and InMeleeRange("Ambush")
			and ReadablePositionalUsable("Ambush") ~= false then
			SubOffer("Ambush", "Subtlety: stealth opener", energy, 60)
		end
		-- An opener rejected for position falls through to Hemorrhage/Sinister;
		-- it is never selected as the ordinary in-combat builder.
	end
	if not inCombat then
		if s.subtletyHemorrhage and Ok("Hemorrhage") then
			local minimum = math.max(SettingNumber(s, "subtletyHemorrhageEnergy", 0, 0, 100), EnergyCost("Hemorrhage", 35))
			AddAction("Hemorrhage", "Subtlety: learned opener", { EnergyGate(energy, minimum, "Hemorrhage") })
		end
		local builder, minimum = Builder(s)
		if builder then AddAction(builder, "Subtlety: leveling opener", { EnergyGate(energy, math.max(minimum, EnergyCost(builder, 45)), builder) }) end
		AddAction(nil, "Pool energy"); return FinishDecision()
	end
	local snd = SubSndActive()
	local maintainSnd = s.snd and cp >= 1 and not snd and Ok("Slice and Dice") and FinisherAvailable("Slice and Dice")
	if maintainSnd then SubOffer("Slice and Dice", "Subtlety: missing player buff", energy, 25) end

	-- AoE branch: the reference has no area attack. A learned Blade Flurry
	-- remains available for another talent arrangement, only with AoE On.
	if s.aoe and s.bladeFlurry then
		local minimum = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
		local count = ActiveEnemyCount(minimum, true)
		if count and count >= minimum and SubReady("Blade Flurry") and not CombatBuff("Blade Flurry") then SubOffer("Blade Flurry", "Subtlety AoE: learned cleave", energy, 25) end
	end
	if AL.burst then
		if s.subtletyRacials then for _, name in ipairs({ "Blood Fury", "Berserking" }) do
			if SubReady(name) and not CombatBuff(name) then SubOffer(name, "Subtlety Burst: racial", energy, 0, { burstGate }) end
		end end
		local setup = s.subtletyVanish and not stealth and not openerBlocked and cp <= 1 and snd
			and (s.subtletyPremeditation and Ok("Premeditation") or s.subtletyAmbush and MainHandIsDagger() == true and Ok("Ambush"))
		if energy == nil and (not lastRotation.energyMaximum or not CurveAvailable("energy")) then setup = false end
		if setup then
			local gates = { burstGate, EnergyGate(energy, 60, "Vanish") }
			local enabled, vanishEnd = CombatCooldown("Vanish")
			local usedVanish = enabled ~= false and (vanishEnd ~= nil and vanishEnd > GetTime()
				or vanishEnd == nil and (combatEnds.Vanish or 0) > GetTime())
			if s.subtletyPreparation and Ok("Vanish") and usedVanish and not SubReady("Vanish") then
				SubOffer("Preparation", "Subtlety Burst: reset used Vanish", energy, 0, gates)
			end
			if s.subtletyPremeditation and SubReady("Premeditation") or s.subtletyAmbush and MainHandIsDagger() == true and Ok("Ambush") then
				SubOffer("Vanish", "Subtlety Burst: optional stealth reset", energy, 0, gates)
			end
		end
	end
	if maintainSnd then AddAction(nil, "Pool energy for Slice and Dice"); return FinishDecision() end
	local finishPoints = EvisceratePoints() == 1 and SettingNumber(s, "subtletyEviscerateCP", 4, 1, 5) or 5
	if cp >= EvisceratePoints() and Ok("Eviscerate") and FinisherAvailable("Eviscerate") then
		local execute = HealthGate("target", targetHP, 50, true)
		SubOffer("Eviscerate", "Subtlety: low-health execute", energy, 35, { execute })
		AddAction(nil, "Pool energy for Eviscerate", { execute })
	end
	local remaining
	if A and A.Unit then
		local unit = SafeCall(A.Unit, "target")
		if SafeValue(unit) and type(unit) == "table" then remaining = ReadableNumber((SafeCall(unit.TimeToDie, unit))) end
	end
	if s.subtletyRupture and (not remaining or remaining <= 0 or remaining > 8)
		and cp >= SettingNumber(s, "subtletyRuptureCP", 3, 1, 5) and not SubDot("Rupture")
		and Ok("Rupture") and FinisherAvailable("Rupture") then
		local healthGate = HealthGate("target", targetHP, SettingNumber(s, "subtletyRuptureHP", 50, 0, 100), false)
		SubOffer("Rupture", "Subtlety: maintain own bleed", energy, 25, { healthGate })
		AddAction(nil, "Pool energy for Rupture", { healthGate })
	end
	if cp >= finishPoints and Ok("Eviscerate") and FinisherAvailable("Eviscerate") then
		SubOffer("Eviscerate", "Subtlety: damage finisher", energy, 35)
		AddAction(nil, "Pool energy for Eviscerate"); return FinishDecision()
	end
	if not Ok("Eviscerate") and s.expose and cp >= SettingNumber(s, "exposeMinCP", 4, 1, 5)
		and Ok("Expose Armor") and FinisherAvailable("Expose Armor") and not AL.HasDebuff("target", "Expose Armor") then
		SubOffer("Expose Armor", "Subtlety: enabled finisher fallback", energy, 25)
		AddAction(nil, "Pool energy for Expose Armor"); return FinishDecision()
	end
	if cp >= 5 then AddAction(nil, "Subtlety: waiting for an enabled finisher"); return FinishDecision() end
	if s.subtletyGhostlyStrike and SubDot("Hemorrhage") then SubOffer("Ghostly Strike", "Subtlety: learned builder cooldown", energy, 40) end
	if s.subtletyHemorrhage and Ok("Hemorrhage") then
		local minimum = math.max(SettingNumber(s, "subtletyHemorrhageEnergy", 0, 0, 100), EnergyCost("Hemorrhage", 35))
		AddAction("Hemorrhage", "Subtlety: Hemorrhage builder", { EnergyGate(energy, minimum, "Hemorrhage") })
	end
	local builder, minimum = Builder(s)
	if builder then AddAction(builder, "Subtlety: learned Sinister Strike fallback", { EnergyGate(energy, math.max(minimum, EnergyCost(builder, 45)), builder) }) end
	AddAction(nil, "Pool energy"); return FinishDecision()
end

-- Poison-free Assassination: the reference's Venom buff only increases
-- consumable poisons, so it remains available in Spells/manual queue rather
-- than spending points automatically. Mutilate itself does not need poison.
AssassinationRotation = function(s, inCombat, hostile, cp, energy, targetHP)
	if not hostile or not ConfirmedHostileTarget() then AddAction(nil, inCombat and "No target" or "Ready"); return FinishDecision() end
	if not inCombat then
		local opener, reason = StealthOpener(s)
		if opener or reason then return opener, reason end
		if s.stealth and SubReady("Stealth") and not AL.HasBuff("player", "Stealth") and WithinStealthRange() then
			AddAction("Stealth", "Assassination: opener setup"); return FinishDecision()
		end
	end
	if not InMeleeRange("Mutilate") and not InMeleeRange("Sinister Strike") then
		AddAction(nil, "Approach target"); return FinishDecision()
	end
	if inCombat then
		local snd = SubSndActive()
		if s.snd and cp >= 1 and not snd and Ok("Slice and Dice") and FinisherAvailable("Slice and Dice") then
			SubOffer("Slice and Dice", "Assassination: missing player buff", energy, 25)
			AddAction(nil, "Pool energy for Slice and Dice"); return FinishDecision()
		end
		-- AoE: this 38/11/2 preset has no area spell. A different talent
		-- arrangement may use learned Blade Flurry, only with AoE On.
		if s.aoe and s.bladeFlurry then
			local minimum = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
			local count = ActiveEnemyCount(minimum, true)
			if count and count >= minimum and SubReady("Blade Flurry") and not CombatBuff("Blade Flurry") then
				SubOffer("Blade Flurry", "Assassination AoE: learned cleave", energy, 25)
			end
		end
		if AL.burst then
			local healthGate = HealthGate("target", targetHP, SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false)
			if s.assassinationColdBlood and (snd or not s.snd or not Ok("Slice and Dice"))
				and SubReady("Cold Blood") and not CombatBuff("Cold Blood") then
				SubOffer("Cold Blood", "Assassination Burst: critical strike cooldown", energy, 0, { healthGate })
			end
			if s.assassinationRacials then for _, name in ipairs({ "Blood Fury", "Berserking" }) do
				if SubReady(name) and not CombatBuff(name) then SubOffer(name, "Assassination Burst: racial", energy, 0, { healthGate }) end
			end end
		end
		local required = EvisceratePoints() == 1 and SettingNumber(s, "assassinationEviscerateCP", 4, 1, 5) or 5
		if cp >= EvisceratePoints() and Ok("Eviscerate") and FinisherAvailable("Eviscerate") then
			local execute = HealthGate("target", targetHP, 50, true)
			SubOffer("Eviscerate", "Assassination: low-health execute", energy, 35, { execute })
			AddAction(nil, "Pool energy for Eviscerate", { execute })
		end
		if cp >= required and Ok("Eviscerate") and FinisherAvailable("Eviscerate") then
			SubOffer("Eviscerate", "Assassination: damage finisher", energy, 35)
			AddAction(nil, "Pool energy for Eviscerate"); return FinishDecision()
		end
		if not Ok("Eviscerate") then
			for _, row in ipairs({ { "Rupture", "rupture", "ruptureMinCP" }, { "Expose Armor", "expose", "exposeMinCP" } }) do
				local name = row[1]
				if s[row[2]] and cp >= SettingNumber(s, row[3], 4, 1, 5) and Ok(name)
					and FinisherAvailable(name) and not SubDot(name) then
					SubOffer(name, "Assassination: enabled finisher fallback", energy, 25)
					AddAction(nil, "Pool energy for " .. name); return FinishDecision()
				end
			end
		end
		if cp >= 5 then AddAction(nil, "Assassination: waiting for an enabled finisher"); return FinishDecision() end
	end
	if s.assassinationMutilate and Ok("Mutilate") and SubReady("Mutilate") and TwoDaggers() and InMeleeRange("Mutilate") then
		local usable, shortage = SpellUsability("Mutilate")
		if usable ~= false or shortage == true then
			local minimum = math.max(SettingNumber(s, "assassinationMutilateEnergy", 0, 0, 100), EnergyCost("Mutilate", 60))
			AddAction("Mutilate", "Assassination: two-point builder", { EnergyGate(energy, minimum, "Mutilate") })
			AddAction(nil, "Pool energy for Mutilate"); return FinishDecision()
		end
	end
	local builder, minimum = Builder(s)
	if builder and InMeleeRange(builder) then
		AddAction(builder, "Assassination: learned Sinister Strike fallback", { EnergyGate(energy, math.max(minimum, EnergyCost(builder, 45)), builder) })
	end
	AddAction(nil, "Pool energy"); return FinishDecision()
end

function M.NextSpell(s, inCombat, hostile)
    M.NormalizeBuild(s)
	-- A blocked energy curve must not repeatedly suppress a working Evasion
	-- health curve. Disable only the failed unit/API until combat ends.
	if not inCombat then
		curveFailures, energyMaximumCache = {}, nil
		subAuraBlocked = {}
		if s.subtlety == true then SubTalent("Initiative") end
		if s.assassination == true then SubTalent("Seal Fate") end
		-- Carry readable pre-combat cooldowns into combat when the API becomes protected.
		for name in pairs(combatCooldowns) do
			if Ok(name) and (not combatCastAt[name] or GetTime() - combatCastAt[name] >= 1) then
				local _, expires = CombatCooldown(name)
				if expires ~= nil then combatEnds[name] = expires end
			end
		end
	end
	local targetHP
	if hostile then targetHP = HealthPercent("target") end
	lastRotation = { at = GetTime(), actions = {} }

	local maximum = ReadableNumber((SafeCall(UnitPowerMax, "player", 3)))
	if maximum and maximum > 0 then energyMaximumCache = maximum end
	lastRotation.energyMaximum = energyMaximumCache
	if s.assassination == true and not inCombat then return AssassinationRotation(s, false, hostile, RoguePoints(), ReadableNumber(AL.Power(3)), targetHP) end
	if s.subtlety == true and not inCombat then return SubtletyRotation(s, false, hostile, RoguePoints(), ReadableNumber(AL.Power(3)), targetHP) end

	if not inCombat then
		if hostile then
			local opener, reason = StealthOpener(s)
			if opener or reason then return opener, reason end
			if s.stealth and OkReady("Stealth") and not AL.HasBuff("player", "Stealth") and WithinStealthRange() then
				return "Stealth", "opener setup"
			end
			if not InMeleeRange("Sinister Strike") then return nil, "Approach target" end
			local builder, minimum = Builder(s)
			if builder then
				minimum = math.max(minimum, EnergyCost(builder, 45))
				AddAction(builder, openerBlocked and "positional opener fallback" or "opener", { EnergyGate(ReadableNumber(AL.Power(3)), minimum, builder) })
				AddAction(nil, "Pool energy")
				return FinishDecision()
			end
			return AL.known["Attack"] and "Attack", "opener"
		end
		return nil, "Ready"
	end
	if not hostile then return nil, "No target" end

	local cp = RecoverStaleComboPoints(RoguePoints())
	local energy = ReadableNumber(AL.Power(3))
	local playerHP = HealthPercent("player")

	if s.vanish and ReadyUsable("Vanish") then
		AddAction("Vanish", "emergency escape", { HealthGate("player", playerHP, SettingNumber(s, "vanishHP", 20, 5, 80), true) })
	end
	local targetCasting = AL.TargetCasting()
	if targetCasting and s.kick and ReadyUsable("Kick") then
		AddAction("Kick", "interrupt"); return FinishDecision()
	end
	if targetCasting and s.kidney and cp >= SettingNumber(s, "kidneyMinCP", 3, 1, 5) and ReadyUsable("Kidney Shot") then
		AddAction("Kidney Shot", "interrupt fallback"); return FinishDecision()
	end
	if s.gouge and ReadyUsable("Gouge") and InMeleeRange("Gouge") and not AL.HasDebuff("target", "Gouge") then
		AddAction("Gouge", "stall and recover", {
			HealthGate("player", playerHP, SettingNumber(s, "gougeHP", 50, 5, 95), true),
			EnergyGate(energy, EnergyCost("Gouge", 45), "Gouge") })
	end
	if s.evasion and ReadyUsable("Evasion") and not AL.HasBuff("player", "Evasion") then
		AddAction("Evasion", "emergency", { HealthGate("player", playerHP, SettingNumber(s, "evasionHP", 35, 5, 90), true) })
	end
	if s.riposte and Ok("Riposte") and (s.subtlety == true and SubReady("Riposte") or s.subtlety ~= true and AL.IsReady("Riposte")) and RiposteProcActive() then
		AddAction("Riposte", "parry proc"); return FinishDecision()
	end
	if s.assassination == true then return AssassinationRotation(s, true, hostile, cp, energy, targetHP) end
	if s.subtlety == true then return SubtletyRotation(s, true, hostile, cp, energy, targetHP) end
	if s.combat == true then return CombatRotation(s, cp, energy, targetHP) end

	local aoeMin = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
	local enemyCount
	if s.aoe then enemyCount = ActiveEnemyCount(aoeMin) end
	local aoeActive = s.aoe and enemyCount ~= nil and enemyCount >= aoeMin
	local burstGate = HealthGate("target", targetHP, SettingNumber(s, "burstMinTargetHP", 40, 0, 100), false)
	local meleeTarget = ConfirmedHostileTarget() and InMeleeRange("Sinister Strike")
	if s.bladeFlurry and aoeActive and meleeTarget and ReadyUsable("Blade Flurry") and not AL.HasBuff("player", "Blade Flurry") then
		AddAction("Blade Flurry", aoeActive and "aoe" or "burst", { burstGate, EnergyGate(energy, EnergyCost("Blade Flurry", 25), "Blade Flurry") })
	end
	if AL.burst and meleeTarget then
		if ReadyUsable("Blood Fury") then AddAction("Blood Fury", "burst", { burstGate }) end
		if ReadyUsable("Berserking") then AddAction("Berserking", "burst", { burstGate }) end
	end
	if s.snd and (cp == 1 or AL.DPS60 and AL.DPS60.Active() and cp >= 1) and not AL.HasBuff("player", "Slice and Dice") and Ok("Slice and Dice")
		and FinisherAvailable("Slice and Dice") then
		AddAction("Slice and Dice", "maintain buff at exactly 1 cp", { EnergyGate(energy, EnergyCost("Slice and Dice", 25), "Slice and Dice") })
		AddAction(nil, "Pool energy for Slice and Dice"); return FinishDecision()
	end

    if AL.DPS60 and AL.DPS60.Active() then
        local automatic = AL.known["Mutilate"] and "ASSASSINATION" or AL.known["Hemorrhage"] and "SUBTLETY" or "COMBAT"
        local build = AL.DPS60.Build("ROGUE", s, automatic)
        local required = build == "ASSASSINATION" and EvisceratePoints() == 1 and 4 or 5
        if cp >= required and Ok("Eviscerate") and FinisherAvailable("Eviscerate") then
            AddAction("Eviscerate", tostring(cp) .. " cp - " .. build, { EnergyGate(energy, EnergyCost("Eviscerate", 35), "Eviscerate") })
            AddAction(nil, "Pool energy for Eviscerate"); return FinishDecision()
        end
        if build == "SUBTLETY" and cp < 5 and AL.DPS60.Ready("Ghostly Strike") and InMeleeRange("Ghostly Strike") then
            local usable, shortage = SpellUsability("Ghostly Strike")
            if usable ~= false and shortage ~= true then AddAction("Ghostly Strike", "Subtlety builder", { EnergyGate(energy, EnergyCost("Ghostly Strike", 40), "Ghostly Strike") }) end
        end
    end
	local finishCP = EvisceratePoints()
	local eviscerateAllowed = Ok("Eviscerate")
	local finishGate = HealthGate("target", targetHP, 50, true)
	if eviscerateAllowed and cp >= finishCP then
		if FinisherAvailable("Eviscerate") then
			AddAction("Eviscerate", tostring(cp) .. " cp at/below 50% target health", {
				finishGate, EnergyGate(energy, EnergyCost("Eviscerate", 35), "Eviscerate") })
			AddAction(nil, "Pool energy for Eviscerate", { finishGate })
		end
	end
	if not eviscerateAllowed and s.rupture and cp >= SettingNumber(s, "ruptureMinCP", 4, 1, 5)
		and not AL.HasDebuff("target", "Rupture") and Ok("Rupture") and FinisherAvailable("Rupture") then
		AddAction("Rupture", tostring(cp) .. " cp", { finishGate, EnergyGate(energy, EnergyCost("Rupture", 25), "Rupture") })
		AddAction(nil, "Pool energy for Rupture", { finishGate })
	end
	if not eviscerateAllowed and s.expose and cp >= SettingNumber(s, "exposeMinCP", 4, 1, 5)
		and not AL.HasDebuff("target", "Expose Armor") and Ok("Expose Armor") and FinisherAvailable("Expose Armor") then
		AddAction("Expose Armor", tostring(cp) .. " cp", { finishGate, EnergyGate(energy, EnergyCost("Expose Armor", 25), "Expose Armor") })
		AddAction(nil, "Pool energy for Expose Armor", { finishGate })
	end
	if cp >= 5 and targetHP == nil and eviscerateAllowed and not CurveAvailable("health") then
		AddAction(nil, "Target health unavailable"); return FinishDecision()
	end
	local builder, minimumEnergy = Builder(s)
	if builder then
		minimumEnergy = math.max(minimumEnergy, EnergyCost(builder, 45))
		AddAction(builder, "builder", { EnergyGate(energy, minimumEnergy, builder) })
		AddAction(nil, "Pool energy")
	else AddAction(AL.known["Attack"] and "Attack" or nil, "melee") end
	return FinishDecision()
end

function M.GetUIState()
	local profile = AL.S()
	local knownCount = 0
	for _, entry in ipairs(M.spells) do
		if AL.known[entry[2]] then knownCount = knownCount + 1 end
	end
	return {
		level = UnitLevel and UnitLevel("player") or nil,
		energy = AL.Power(3),
		combo = RoguePoints(),
		stealthed = AL.HasBuff("player", "Stealth"),
		knownCount = knownCount,
		enemyCount = ActiveEnemyCount(SettingNumber(profile, "aoeMinEnemies", 2, 2, 5)),
		mainHandDagger = MainHandIsDagger(),
		targetHealth = HealthPercent("target"),
		evisceratePoints = EvisceratePoints(),
	}
end

for _, name in ipairs({ "Adrenaline Rush", "Blade Flurry", "Blood Fury", "Berserking", "Cold Blood", "Venom", "Preparation", "Slice and Dice", "Evasion", "Vanish", "Stealth" }) do
	AL.selfCastSpells = AL.selfCastSpells or {}
	AL.selfCastSpells[name] = true
end
AL.RegisterRotation("ROGUE", M)
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
    root.RegisterRotation("ROGUE", advanced)
end
