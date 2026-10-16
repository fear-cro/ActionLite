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
