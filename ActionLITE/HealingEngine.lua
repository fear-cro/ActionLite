local ADDON, AL = ...

-- ============================================================================
-- ActionLITE HealingEngine
-- ----------------------------------------------------------------------------
-- WoW Forever protects party health in combat. The engine never reads or
-- compares protected health values in Lua. Instead, it asks the client to
-- evaluate a ColorCurve and passes the resulting protected alpha directly to
-- matching recommendation and target-pixel layers.
--
-- Shared selected-ally and healer-damage rules work without a class provider.
-- Class rotations add automatic healing priorities by exposing
-- HealingEnginePlan(profile, context). See Documentation/Rotation-Development.md.
-- ============================================================================

local Engine = {
	VERSION = "1.1.0",
	SUPPORTED_CLASSES = { DRUID = true, PALADIN = true, PRIEST = true, SHAMAN = true },
	providers = {},
	curves = {},
	rows = {},
	state = {},
}
AL.HealingEngine = Engine

local ROLE_PRIORITY = { NONE = 1, DAMAGER = 2, HEALER = 3, TANK = 4 }
local ACTIVE_SLOTS = { 3, 6 }
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DAMAGE_MANA_THRESHOLD = 80
local DPS_THRESHOLD_OFFSET = 10

-- These are safe base rules, not the final class healing priorities. A class
-- provider can replace the selected-ally spell with manual/strongest and will
-- later supply the routine and emergency requests used by protected health.
local MANUAL_HEALS = {
	DRUID = { "Healing Touch", "Regrowth" },
	PALADIN = { "Holy Light", "Flash of Light" },
	PRIEST = { "Greater Heal", "Heal", "Lesser Heal" },
	SHAMAN = { "Healing Wave", "Lesser Healing Wave" },
}

-- A grouped healer conserves mana while watching the party. Wand users use
-- Shoot; other healers only apply periodic damage at high mana. Consecration
-- is the Paladin's available periodic-damage equivalent.
local DAMAGE_SPELLS = {
	DRUID = { "Insect Swarm", "Moonfire" },
	PALADIN = { "Consecration" },
	PRIEST = { "Shadow Word: Pain" },
	SHAMAN = { "Flame Shock" },
}
local TARGET_DEBUFFS = {
	["Insect Swarm"] = true,
	["Moonfire"] = true,
	["Shadow Word: Pain"] = true,
	["Flame Shock"] = true,
}

local function IsSecret(value)
	if type(issecretvalue) ~= "function" then return false end
	local ok, secret = pcall(issecretvalue, value)
	return not ok or secret == true
end

local function PublicNumber(value)
	if IsSecret(value) or type(value) ~= "number" or value ~= value
		or value == math.huge or value == -math.huge then return nil end
	return value
end

local function PublicBoolean(value)
	if IsSecret(value) then return nil end
	if value == true or value == 1 then return true end
	if value == false or value == 0 then return false end
	return nil
end

local function SafeBoolean(func, ...)
	if type(func) ~= "function" then return nil end
	local ok, value = pcall(func, ...)
	if not ok then return nil end
	return PublicBoolean(value)
end

local function UnitExistsPublic(unit)
	return SafeBoolean(UnitExists, unit) == true
end

function Engine:IsGrouped()
	if type(IsInGroup) == "function" then
		local grouped = SafeBoolean(IsInGroup)
		if grouped == true then return true end
	end
	if type(GetNumGroupMembers) == "function" then
		local ok, count = pcall(GetNumGroupMembers)
		count = ok and PublicNumber(count) or nil
		if count and count > 0 then return true end
	end
	-- Follower dungeons can expose party unit tokens even when a group count is
	-- unavailable during the transition into the instance.
	for index = 1, 4 do
		if UnitExistsPublic("party" .. index) then return true end
	end
	for index = 1, 40 do
		if UnitExistsPublic("raid" .. index) then return true end
	end
	return false
end

local function ClampPercent(value, fallback)
	value = PublicNumber(value) or fallback
	return math.max(0, math.min(100, math.floor(value + 0.5)))
end

function Engine:NormalizeProfile(profile)
	if type(profile) ~= "table" then return profile end
	if profile.healingEngine == nil then profile.healingEngine = false end
	profile.healingInitiateHP = ClampPercent(profile.healingInitiateHP, 80)
	profile.healingEmergencyHP = ClampPercent(profile.healingEmergencyHP, 30)
	return profile
end

function Engine:GetSettings(profile)
	profile = self:NormalizeProfile(profile or (AL.S and AL.S()) or {})
	local initiate = ClampPercent(profile.healingInitiateHP, 80)
	local emergency = math.min(initiate, ClampPercent(profile.healingEmergencyHP, 30))
	local configured = profile.healingEngine == true
	local grouped = configured and self:IsGrouped() or false
	return {
		configured = configured,
		grouped = grouped,
		enabled = configured and grouped,
		initiate = initiate,
		emergency = emergency,
	}
end

function Engine:IsEnabled(profile)
	local settings = self:GetSettings(profile)
	return self.SUPPORTED_CLASSES[AL.playerClass] == true and settings.enabled
end

function Engine:RegisterProvider(classToken, provider)
	if self.SUPPORTED_CLASSES[classToken] and type(provider) == "function" then
		self.providers[classToken] = provider
		return true
	end
	return false
end

local function RaidRosterVisible()
	for index = 1, 40 do
		if UnitExistsPublic("raid" .. index) then return true end
	end
	return false
end

local function RosterUnits()
	local units = {}
	if RaidRosterVisible() then
		for index = 1, 40 do units[#units + 1] = "raid" .. index end
	else
		-- A five-player follower dungeon exposes its followers as party1-party4.
		-- Player is explicit because party unit tokens never include the player.
		for index = 4, 1, -1 do units[#units + 1] = "party" .. index end
		units[#units + 1] = "player"
	end
	return units
end

function Engine:ManualTargetUnit()
	if not UnitExistsPublic("target") then return nil end
	local assist = SafeBoolean(UnitCanAssist, "player", "target")
	local friend = SafeBoolean(UnitIsFriend, "player", "target")
	if assist ~= true and friend ~= true then return nil end
	if type(UnitIsUnit) ~= "function" then return nil end
	for _, unit in ipairs(RosterUnits()) do
		if UnitExistsPublic(unit) and SafeBoolean(UnitIsUnit, "target", unit) == true then
			return unit
		end
	end
	return nil
end

function Engine:HostileTarget()
	if not UnitExistsPublic("target") then return false end
	if SafeBoolean(UnitCanAttack, "player", "target") ~= true then return false end
	return SafeBoolean(UnitIsDeadOrGhost, "target") == false
end

function Engine:EnemyCombatTarget()
	return SafeBoolean(UnitAffectingCombat, "player") == true and self:HostileTarget()
end

function Engine:TargetClassification()
	if not self:HostileTarget() or type(UnitClassification) ~= "function" then return nil end
	local ok, classification = pcall(UnitClassification, "target")
	if not ok or IsSecret(classification) or type(classification) ~= "string" then return nil end
	return classification
end

local function UnitRole(unit)
	if type(UnitGroupRolesAssigned) ~= "function" then return "NONE" end
	local ok, role = pcall(UnitGroupRolesAssigned, unit)
	if not ok or IsSecret(role) or type(role) ~= "string" or not ROLE_PRIORITY[role] then return "NONE" end
	return role
end

local function UnitOrdinal(unit)
	if unit == "player" then return 0 end
	return tonumber(unit:match("(%d+)$")) or 99
end

local function ResolveSpellReference(spell)
	if type(spell) == "number" and not IsSecret(spell) then return spell end
	if type(spell) ~= "string" or IsSecret(spell) then return nil end
	local reference = AL.rangeSpellRefs and AL.rangeSpellRefs[spell]
	local id = reference and reference.id
	if PublicNumber(id) then return id end
	return spell
end

local function SpellRange(spell, unit)
	local reference = ResolveSpellReference(spell)
	if reference and C_Spell and type(C_Spell.IsSpellInRange) == "function" then
		local ok, value = pcall(C_Spell.IsSpellInRange, reference, unit)
		if ok then
			local result = PublicBoolean(value)
			if result ~= nil then return result end
		end
	end
	-- The legacy API accepts spell names on compatible Classic clients. A nil
	-- result means unknown and must not be converted into out of range.
	if type(spell) == "string" and type(IsSpellInRange) == "function" then
		local ok, value = pcall(IsSpellInRange, spell, unit)
		if ok then return PublicBoolean(value) end
	end
	return nil
end

function Engine:IsUnitEligible(unit, spell, request)
	if type(unit) ~= "string" or not AL.HealingTargetColors
		or not AL.HealingTargetColors[unit] or not UnitExistsPublic(unit) then return false end

	if unit ~= "player" then
		local assist = SafeBoolean(UnitCanAssist, "player", unit)
		local friend = SafeBoolean(UnitIsFriend, "player", unit)
		if assist == false or friend == false or (assist == nil and friend == nil) then return false end
	end
	if SafeBoolean(UnitIsDeadOrGhost, unit) == true then return false end
	if SafeBoolean(UnitIsConnected, unit) == false then return false end
	if SafeBoolean(UnitIsVisible, unit) == false then return false end

	local role = UnitRole(unit)
	if request and type(request.roles) == "table" and request.roles[role] ~= true then return false end
	if request and request.includePlayer == false and unit == "player" then return false end
	if request and type(request.unit) == "string" and request.unit ~= unit then return false end
	if request and type(request.unitFilter) == "function" then
		local ok, allowed = pcall(request.unitFilter, unit, role)
		if not ok or PublicBoolean(allowed) ~= true then return false end
	end
	if SpellRange(spell, unit) == false then return false end
	return true, role
end

function Engine:BuildRoster(spell, request)
	local roster = {}
	for _, unit in ipairs(RosterUnits()) do
		local eligible, role = self:IsUnitEligible(unit, spell, request)
		if eligible then
			local roleValue = ROLE_PRIORITY[role] or ROLE_PRIORITY.NONE
			roster[#roster + 1] = {
				unit = unit,
				role = role,
				-- Higher role priority and earlier roster positions are drawn last,
				-- so their opaque layer wins when several units share a health band.
				priority = roleValue * 1000 + (100 - UnitOrdinal(unit)),
			}
		end
	end
	table.sort(roster, function(left, right)
		if left.priority == right.priority then return left.unit > right.unit end
		return left.priority < right.priority
	end)
	return roster
end

local function ThresholdCut(percent)
	if percent >= 100 then return 1 end
	if AL.ResourceThresholdCut then return math.min(1, AL.ResourceThresholdCut(percent, true)) end
	return percent / 100
end

function Engine:HealthCurve(lowPercent, highPercent)
	lowPercent = ClampPercent(lowPercent, 0)
	highPercent = math.max(lowPercent, ClampPercent(highPercent, 100))
	local key = tostring(lowPercent) .. ":" .. tostring(highPercent)
	if self.curves[key] then return self.curves[key] end
	local factory = C_CurveUtil and C_CurveUtil.CreateColorCurve
	if type(factory) ~= "function" or type(CreateColor) ~= "function" then return nil end
	local ok, curve = pcall(factory)
	if not ok or not curve then return nil end
	pcall(curve.SetType, curve, Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	local low = lowPercent / 100
	local highCut = ThresholdCut(highPercent)
	if not pcall(curve.AddPoint, curve, 0, CreateColor(1, 1, 1, lowPercent == 0 and 1 or 0)) then return nil end
	if lowPercent > 0 and not pcall(curve.AddPoint, curve, low, CreateColor(1, 1, 1, 1)) then return nil end
	if highPercent < 100 then
		if not pcall(curve.AddPoint, curve, highCut, CreateColor(1, 1, 1, 0)) then return nil end
		if highCut < 1 and not pcall(curve.AddPoint, curve, 1, CreateColor(1, 1, 1, 0)) then return nil end
	else
		if not pcall(curve.AddPoint, curve, 1, CreateColor(1, 1, 1, 1)) then return nil end
	end
	self.curves[key] = curve
	return curve
end

local function ColorAlpha(color)
	if IsSecret(color) then return false end
	if color == nil or type(color.GetRGBA) ~= "function" then return false end
	local ok, _, _, _, alpha = pcall(color.GetRGBA, color)
	if not ok then return false end
	if IsSecret(alpha) then return true, alpha end
	if PublicNumber(alpha) then return true, alpha end
	return false
end

function Engine:PredictedHealthAlpha(unit, lowPercent, highPercent)
	local curve = self:HealthCurve(lowPercent, highPercent)
	if not curve then return false, nil, "ColorCurve unavailable" end

	if type(UnitHealthPercent) == "function" then
		local ok, color = pcall(UnitHealthPercent, unit, true, curve)
		if ok then
			local available, alpha = ColorAlpha(color)
			if available then return true, alpha end
		end
	end

	-- Forever 1.60.1 also exposes the Midnight heal-prediction calculator.
	-- This is a fallback for clients where UnitHealthPercent rejects a curve.
	if type(CreateUnitHealPredictionCalculator) == "function"
		and type(UnitGetDetailedHealPrediction) == "function" then
		local okCalculator, calculator = pcall(CreateUnitHealPredictionCalculator)
		if okCalculator and calculator then
			local okFill = pcall(UnitGetDetailedHealPrediction, unit, "player", calculator)
			if okFill and type(calculator.EvaluateCurrentHealthPercent) == "function" then
				local okColor, color = pcall(calculator.EvaluateCurrentHealthPercent, calculator, curve)
				if okColor then
					local available, alpha = ColorAlpha(color)
					if available then return true, alpha end
				end
			end
		end
	end
	return false, nil, "Predicted health mask unavailable"
end

local function RequestAvailable(spell, profile)
	if type(spell) ~= "string" or spell == "" or IsSecret(spell) then return false end
	if AL.known and not AL.known[spell] then return false end
	if AL.Allowed and not AL.Allowed(spell, profile) then return false end
	if AL.IsReady and not AL.IsReady(spell) then return false end
	if AL.SpellUsable then
		local usable = AL.SpellUsable(spell)
		if usable == false then return false end
	end
	return true
end

local function NormalizeRequest(value, category, threshold, profile)
	if type(value) == "string" then value = { spell = value } end
	if type(value) ~= "table" or value.enabled == false then return nil end
	local spell = value.spell
	if type(spell) ~= "string" or spell == "" or IsSecret(spell) then return nil end
	if value.requireKnown ~= false and AL.known and not AL.known[spell] then return nil end
	if AL.Allowed and not AL.Allowed(spell, profile) then return nil end
	if value.requireReady ~= false and AL.IsReady and not AL.IsReady(spell) then return nil end
	if value.requireUsable ~= false and AL.SpellUsable then
		local usable = AL.SpellUsable(spell)
		if usable == false then return nil end
	end
	local reason = "HealingEngine " .. tostring(category or "request")
	return {
		category = category,
		spell = spell,
		reason = type(value.reason) == "string" and value.reason or reason,
		threshold = ClampPercent(value.threshold, threshold),
		includePlayer = value.includePlayer,
		roles = value.roles,
		unit = value.unit,
		unitFilter = value.unitFilter,
		visibility = value.visibility,
	}
end

-- A category may contain one request or an ordered list. Later requests are
-- drawn later and therefore win when more than one protected condition is
-- opaque. The singular form remains compatible with the original provider
-- contract.
local function NormalizeRequests(value, category, threshold, profile)
	local requests = {}
	if type(value) == "string" or (type(value) == "table" and value.spell ~= nil) then
		local request = NormalizeRequest(value, category, threshold, profile)
		if request then requests[1] = request end
		return requests
	end
	if type(value) ~= "table" then return requests end
	for _, item in ipairs(value) do
		local request = NormalizeRequest(item, category, threshold, profile)
		if request then requests[#requests + 1] = request end
	end
	return requests
end

function Engine:EffectiveThreshold(percent, role)
	percent = ClampPercent(percent, 0)
	if role == "DAMAGER" then percent = percent - DPS_THRESHOLD_OFFSET end
	return math.max(0, percent)
end

function Engine:WandAvailable(profile)
	if type(AL.WandEquipped) ~= "function" or not AL.WandEquipped() then return false end
	if AL.known and not AL.known["Shoot"] then return false end
	return not AL.Allowed or AL.Allowed("Shoot", profile)
end

function Engine:StrongestBaseHeal(profile)
	for _, spell in ipairs(MANUAL_HEALS[AL.playerClass] or {}) do
		if RequestAvailable(spell, profile) then
			return {
				spell = spell,
				reason = "Healing Rotation: selected ally distress heal",
			}
		end
	end
end

function Engine:DamageRequest(profile, context)
	if not self:EnemyCombatTarget() or self:WandAvailable(profile) then return nil end
	local rotation = AL.rotations and AL.rotations[AL.playerClass]
	if rotation and type(rotation.HealingEngineDamagePlan) == "function" then
		local ok, value = pcall(rotation.HealingEngineDamagePlan, profile, context)
		if not ok then
			local message = type(value) == "string" and not IsSecret(value)
				and value or "Protected healing damage provider failure"
			if message ~= self.lastDamageProviderError and AL.Debug and AL.Debug.CaptureError then
				self.lastDamageProviderError = message
				AL.Debug.CaptureError("HealingEngine damage provider: " .. message, "healing engine")
			end
			return nil
		end
		-- false explicitly suppresses the generic class fallback. nil keeps it.
		if value == false then return nil end
		if value ~= nil then
			local request = NormalizeRequest(value, "damage", DAMAGE_MANA_THRESHOLD, profile)
			if request and SpellRange(request.spell, "target") ~= false then return request end
			return nil
		end
	end
	for _, spell in ipairs(DAMAGE_SPELLS[AL.playerClass] or {}) do
		if RequestAvailable(spell, profile) and SpellRange(spell, "target") ~= false then
			local present = false
			if TARGET_DEBUFFS[spell] and type(AL.HasDebuff) == "function" then
				local ok, result = pcall(AL.HasDebuff, "target", spell)
				present = ok and result == true
			end
			if not present then
				return {
					category = "damage",
					spell = spell,
					reason = "Healing Rotation: periodic damage above 80% mana",
					threshold = DAMAGE_MANA_THRESHOLD,
				}
			end
		end
	end
end

-- Called by Core before the class rotation. The third return value tells Core
-- that the Healing Rotation owns this tick even when the correct result is to
-- wait. Wand.lua still wraps the returned Shoot recommendation, preserving its
-- shot and recovery timing.
function Engine:BaseSuggestion(profile)
	local settings = self:GetSettings(profile)
	if not self.SUPPORTED_CLASSES[AL.playerClass] or not settings.enabled then
		return nil, nil, false
	end
	local manualUnit = self:ManualTargetUnit()
	if manualUnit then
		return nil, "Healing Rotation: selected ally", true
	end
	if self:EnemyCombatTarget() then
		if self:WandAvailable(profile) then
			return "Shoot", "Healing Rotation: wand damage", true
		end
		return nil, "Healing Rotation: high-mana periodic damage", true
	end
	return nil, "Healing Rotation: monitoring group", true
end

function Engine:ProviderFor(classToken)
	local provider = self.providers[classToken]
	if type(provider) == "function" then return provider, "registered" end
	local rotation = AL.rotations and AL.rotations[classToken]
	if rotation and type(rotation.HealingEnginePlan) == "function" then
		return rotation.HealingEnginePlan, "rotation"
	end
	return nil
end

function Engine:BuildPlan(baseSpell, baseReason)
	local profile = AL.S and AL.S() or {}
	local settings = self:GetSettings(profile)
	if not self.SUPPORTED_CLASSES[AL.playerClass] or not settings.configured then return nil, settings end
	if not settings.grouped then return nil, settings, "Solo bypass: leveling rotation active" end
	local casting = AL.CastingSpell and AL.CastingSpell()
	local channeling = AL.PlayerChanneling and AL.PlayerChanneling()
	if casting or channeling then return nil, settings, "Player cast in progress" end
	local manualUnit = self:ManualTargetUnit()
	local inCombat = SafeBoolean(UnitAffectingCombat, "player") == true
	local hostileTarget = self:HostileTarget()
	local provider, source = self:ProviderFor(AL.playerClass)
	local context = {
		engine = self,
		settings = settings,
		manualTarget = manualUnit,
		grouped = true,
		inCombat = inCombat,
		hostileTarget = hostileTarget,
		enemyCombat = inCombat and hostileTarget,
		targetClassification = self:TargetClassification(),
		damageManaThreshold = DAMAGE_MANA_THRESHOLD,
		dpsThresholdOffset = DPS_THRESHOLD_OFFSET,
		baseSpell = baseSpell,
		baseReason = baseReason,
		known = AL.known,
		IsReady = AL.IsReady,
		IsUsable = AL.SpellUsable,
		Allowed = function(spell) return not AL.Allowed or AL.Allowed(spell, profile) end,
	}
	local supplied, providerStatus
	if provider then
		local ok, result = pcall(provider, profile, context)
		supplied = ok and result or nil
		if not ok then
			providerStatus = type(result) == "string" and not IsSecret(result)
				and result or "Protected healing provider failure"
		end
	end
	if providerStatus then
		local message = providerStatus
		if message ~= self.lastProviderError and AL.Debug and AL.Debug.CaptureError then
			self.lastProviderError = message
			AL.Debug.CaptureError("HealingEngine provider: " .. message, "healing engine")
		end
	end
	if type(supplied) ~= "table" then supplied = {} end
	local plan = { source = source or "base-rules", rows = {}, settings = settings,
		manualTarget = manualUnit }

	-- A deliberately selected party/raid member is an explicit distress signal.
	-- It bypasses health thresholds and every damage row until the user returns
	-- to an enemy or clears the target.
	if manualUnit then
		local manualOwned = supplied.manual ~= nil
		local manualValue = supplied.manual
		if not manualOwned then manualValue = supplied.strongest end
		if manualValue == nil and not manualOwned then
			local aliases = NormalizeRequests(supplied.emergency, "manual", 100, profile)
			manualValue = aliases[#aliases]
		end
		local manual
		if supplied.manual ~= false then
			manual = NormalizeRequest(manualValue, "manual", 100, profile)
		end
		if not manual and not manualOwned then
			manual = NormalizeRequest(self:StrongestBaseHeal(profile), "manual", 100, profile)
		end
		if manual then
			-- The user's explicit target overrides role/include filters intended for
			-- automatic roster selection.
			manual.roles, manual.includePlayer, manual.unitFilter = nil, nil, nil
			manual.unit = manualUnit
			local eligible, role = self:IsUnitEligible(manualUnit, manual.spell, manual)
			if eligible then
				local visibility = manual.visibility == "health" and "health" or "always"
				plan.rows[1] = {
					unit = manualUnit, role = role, spell = manual.spell,
					reason = manual.reason, category = "manual", threshold = manual.threshold,
					baseThreshold = manual.threshold, low = 0, high = manual.threshold,
					band = "selected-ally", priority = math.huge, visibility = visibility,
				}
				return plan, settings
			end
		end
		local fallback = not manualOwned
			and NormalizeRequest(self:StrongestBaseHeal(profile), "manual", 100, profile) or nil
		if fallback then
			local eligible, role = self:IsUnitEligible(manualUnit, fallback.spell, fallback)
			if eligible then
				plan.rows[1] = {
					unit = manualUnit, role = role, spell = fallback.spell,
					reason = fallback.reason, category = "manual", threshold = 100,
					low = 0, high = 100, band = "selected-ally", priority = math.huge,
					visibility = "always",
				}
				return plan, settings
			end
		end
		return nil, settings, "Selected ally; no available direct heal"
	end

	local damage = self:DamageRequest(profile, context)
	if damage then
		plan.rows[#plan.rows + 1] = {
			spell = damage.spell, reason = damage.reason, category = "damage",
			threshold = damage.threshold or DAMAGE_MANA_THRESHOLD,
			baseThreshold = damage.threshold or DAMAGE_MANA_THRESHOLD,
			low = damage.threshold or DAMAGE_MANA_THRESHOLD,
			high = 100, band = "high-mana-damage", priority = 0,
			visibility = "mana-above",
		}
	end
	local routineValue = supplied.routine
	if routineValue == nil then routineValue = supplied.lowCost end
	if routineValue == nil then routineValue = supplied.hot end
	local requests = {
		maintenance = NormalizeRequests(supplied.maintenance, "maintenance", 100, profile),
		routine = NormalizeRequests(routineValue, "routine", settings.initiate, profile),
		emergency = NormalizeRequests(supplied.emergency, "emergency", settings.emergency, profile),
		followup = NormalizeRequests(supplied.followup, "followup", 100, profile),
	}
	local function AddRow(request, member, low, high, band, visibility, threshold)
		if visibility == "health" and (not high or high <= 0 or high <= (low or 0)) then return end
		plan.rows[#plan.rows + 1] = {
			unit = member.unit,
			role = member.role,
			spell = request.spell,
			reason = request.reason,
			category = request.category,
			threshold = threshold or request.threshold,
			baseThreshold = request.threshold,
			low = low or 0,
			high = high or 100,
			band = band,
			priority = member.priority,
			visibility = visibility,
		}
	end
	local function AddStatic(request, band)
		local visibility = request.visibility == "health" and "health" or "always"
		for _, member in ipairs(self:BuildRoster(request.spell, request)) do
			local threshold = self:EffectiveThreshold(request.threshold, member.role)
			AddRow(request, member, 0, visibility == "health" and threshold or 100,
				band, visibility, threshold)
		end
	end
	for _, request in ipairs(requests.maintenance) do AddStatic(request, "maintenance") end

	local function OrderedCandidates(list)
		local candidates = {}
		for requestIndex, request in ipairs(list) do
			for _, member in ipairs(self:BuildRoster(request.spell, request)) do
				candidates[#candidates + 1] = {
					request = request, requestIndex = requestIndex, member = member,
				}
			end
		end
		table.sort(candidates, function(left, right)
			if left.member.priority ~= right.member.priority then
				return left.member.priority < right.member.priority
			end
			return left.requestIndex < right.requestIndex
		end)
		return candidates
	end
	local function AddRoutineBand(list, urgent)
		for _, candidate in ipairs(OrderedCandidates(list)) do
			local request, member = candidate.request, candidate.member
			local high = self:EffectiveThreshold(request.threshold, member.role)
			local floor = self:EffectiveThreshold(math.min(settings.emergency, request.threshold), member.role)
			local midpoint = math.floor((floor + high) / 2 + 0.5)
			if urgent then
				AddRow(request, member, 0, midpoint, "urgent", "health", high)
			else
				AddRow(request, member, midpoint, high, "routine", "health", high)
			end
		end
	end
	local function AddEmergencyBand(list, critical)
		for _, candidate in ipairs(OrderedCandidates(list)) do
			local request, member = candidate.request, candidate.member
			local high = self:EffectiveThreshold(request.threshold, member.role)
			local midpoint = math.floor(high / 2 + 0.5)
			if critical then
				AddRow(request, member, 0, midpoint, "critical", "health", high)
			else
				AddRow(request, member, midpoint, high, "emergency", "health", high)
			end
		end
	end
	-- Health is secret, so exact Lua sorting is impossible. Two bands per
	-- category put a substantially lower-health unit above a higher-health unit;
	-- deterministic role/roster priority resolves ties inside each band.
	AddRoutineBand(requests.routine, false)
	AddRoutineBand(requests.routine, true)
	AddEmergencyBand(requests.emergency, false)
	AddEmergencyBand(requests.emergency, true)
	for _, request in ipairs(requests.followup) do AddStatic(request, "followup") end
	local status
	if #plan.rows == 0 then
		status = providerStatus or (provider and "No eligible healing units" or "Waiting for class healing provider")
	end
	return #plan.rows > 0 and plan or nil, settings, status
end

function Engine:ManaAboveAlpha(percent)
	local readable
	if type(AL.ManaPercent) == "function" then
		local ok, value = pcall(AL.ManaPercent)
		readable = ok and PublicNumber(value) or nil
	end
	if readable then return true, readable > percent and 1 or 0 end
	if type(AL.ResourceIntervalAlpha) ~= "function" then
		return false, nil, "Protected mana mask unavailable"
	end
	local low = AL.ResourceThresholdCut and AL.ResourceThresholdCut(percent, true) or (percent / 100)
	local ok, alpha = AL.ResourceIntervalAlpha("power", "player", 0, low, 2)
	if ok then return true, alpha end
	return false, nil, "Protected mana mask unavailable"
end

function Engine:DecisionAlpha(decision)
	if decision.visibility == "always" then return true, 1 end
	if decision.visibility == "mana-above" then
		return self:ManaAboveAlpha(decision.threshold or DAMAGE_MANA_THRESHOLD)
	end
	return self:PredictedHealthAlpha(decision.unit, decision.low, decision.high)
end

local function CreateLayerFrame(parent, level)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints(parent)
	frame:SetFrameLevel(level)
	frame:EnableMouse(false)
	frame:SetAlpha(0)
	frame:Show()
	return frame
end

function Engine:CreateVisualRow(index)
	local display = self.display
	if not display or not display.main or not display.slots then return nil end
	local row = { slots = {}, index = index }
	row.main = CreateLayerFrame(display.main, (display.main:GetFrameLevel() or 1) + 20 + index)
	row.main.block = row.main:CreateTexture(nil, "BACKGROUND")
	row.main.block:SetAllPoints(row.main)
	row.main.block:SetColorTexture(0.03, 0.04, 0.06, 1)
	row.main.icon = row.main:CreateTexture(nil, "OVERLAY")
	row.main.icon:SetAllPoints(row.main)
	row.main.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.main.key = row.main:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	row.main.key:SetPoint("TOPRIGHT", row.main, "TOPRIGHT", -1, -2)
	row.main.key:SetJustifyH("RIGHT")
	row.main.key:SetWidth(42)
	pcall(row.main.key.SetWordWrap, row.main.key, false)
	row.main.key:SetTextColor(1, 1, 1, 1)

	for _, slotIndex in ipairs(ACTIVE_SLOTS) do
		local slot = display.slots[slotIndex]
		local layer = CreateLayerFrame(slot, (slot:GetFrameLevel() or 100) + 20 + index)
		layer.block = layer:CreateTexture(nil, "BACKGROUND")
		layer.block:SetAllPoints(layer)
		layer.block:SetColorTexture(0, 0, 0, 1)
		layer.icon = layer:CreateTexture(nil, "OVERLAY")
		layer.icon:SetAllPoints(layer)
		row.slots[slotIndex] = layer
	end

	local target = AL.HealingTargetPixel
	if target then
		row.target = CreateLayerFrame(target, (target:GetFrameLevel() or 101) + 20 + index)
		row.target.texture = row.target:CreateTexture(nil, "OVERLAY")
		row.target.texture:SetAllPoints(row.target)
		row.target.texture:SetColorTexture(AL.GetUniversalColor(0))
	end
	self.rows[index] = row
	return row
end

function Engine:VisualRow(index)
	return self.rows[index] or self:CreateVisualRow(index)
end

local function SetFrameAlpha(frame, alpha)
	if not frame then return true end
	return pcall(frame.SetAlpha, frame, alpha)
end

function Engine:ClearVisuals()
	if self.visualsCleared then
		if AL.SetHealingTargetPixel then AL.SetHealingTargetPixel("none") end
		self.state.activeRows = 0
		return
	end
	for _, row in ipairs(self.rows) do
		SetFrameAlpha(row.main, 0)
		for _, slot in pairs(row.slots) do SetFrameAlpha(slot, 0) end
		SetFrameAlpha(row.target, 0)
		row.decision = nil
	end
	if AL.SetHealingTargetPixel then AL.SetHealingTargetPixel("none") end
	self.state.activeRows = 0
	self.visualsCleared = true
end

function Engine:BindDisplay(display)
	if type(display) ~= "table" or not display.main or type(display.slots) ~= "table" then return false end
	self.display = display
	self.visualsCleared = false
	self:ClearVisuals()
	return true
end

function Engine:ApplyDecision(row, decision, alpha, index)
	if not row or not decision then return false end
	local display = self.display
	local texture = AL.IconFor and AL.IconFor(decision.spell)
		or AL.SpellTexture and AL.SpellTexture(decision.spell) or UNKNOWN_ICON
	local setTexture = display and display.setTexture
	if type(setTexture) == "function" then setTexture(row.main.icon, texture)
	else row.main.icon:SetTexture(texture) end
	local key = not (ActionLiteDB and ActionLiteDB.keybindHidden) and AL.KeybindFor
		and AL.KeybindFor(decision.spell) or nil
	row.main.key:SetText(key or "")
	row.main.key:SetShown(key ~= nil and key ~= false)

	-- Healing Rotation output is always emitted on A[3]. A[6] is reserved for
	-- passive UniversalN Unit1 assignments and is masked while a heal is active.
	local desired = 3
	for _, slotIndex in ipairs(ACTIVE_SLOTS) do
		local slot = row.slots[slotIndex]
		local shownTexture = slotIndex == desired and texture or nil
		if type(setTexture) == "function" then setTexture(slot.icon, shownTexture)
		else slot.icon:SetTexture(shownTexture) end
	end

	if decision.unit and row.target and row.target.texture then
		local colorIndex = AL.HealingTargetColors and AL.HealingTargetColors[decision.unit] or 0
		row.target.texture:SetColorTexture(AL.GetUniversalColor(colorIndex))
	elseif row.target and row.target.texture then
		row.target.texture:SetColorTexture(AL.GetUniversalColor(0))
	end

	local level = index or row.index
	row.main:SetFrameLevel((display.main:GetFrameLevel() or 1) + 20 + level)
	for slotIndex, slot in pairs(row.slots) do
		slot:SetFrameLevel((display.slots[slotIndex]:GetFrameLevel() or 100) + 20 + level)
	end
	if row.target then
		row.target:SetFrameLevel((AL.HealingTargetPixel:GetFrameLevel() or 101) + 20 + level)
	end

	local applied = SetFrameAlpha(row.main, alpha)
	for _, slot in pairs(row.slots) do applied = SetFrameAlpha(slot, alpha) and applied end
	applied = SetFrameAlpha(row.target, decision.unit and alpha or 0) and applied
	self.visualsCleared = false
	row.decision = {
		unit = decision.unit, role = decision.role, spell = decision.spell,
		category = decision.category, threshold = decision.threshold,
		baseThreshold = decision.baseThreshold,
		band = decision.band, low = decision.low, high = decision.high,
		visibility = decision.visibility,
	}
	return applied
end

function Engine:Update(baseSpell, baseReason)
	self:ClearVisuals()
	local plan, settings, status = self:BuildPlan(baseSpell, baseReason)
	self.state = {
		version = self.VERSION,
		supported = self.SUPPORTED_CLASSES[AL.playerClass] == true,
		configured = settings and settings.configured or false,
		grouped = settings and settings.grouped or false,
		enabled = settings and settings.enabled or false,
		initiate = settings and settings.initiate or 80,
		emergency = settings and settings.emergency or 30,
		dpsThresholdOffset = DPS_THRESHOLD_OFFSET,
		provider = plan and plan.source or nil,
		manualTarget = plan and plan.manualTarget or nil,
		status = status,
		activeRows = 0,
		rows = {},
		at = GetTime and GetTime() or 0,
	}
	if not plan or not self.display then return false end

	for index, decision in ipairs(plan.rows) do
		local row = self:VisualRow(index)
		local available, alpha, errorMessage = self:DecisionAlpha(decision)
		if available and self:ApplyDecision(row, decision, alpha, index) then
			self.state.activeRows = self.state.activeRows + 1
			self.state.rows[#self.state.rows + 1] = row.decision
		elseif errorMessage and errorMessage ~= self.lastMaskError then
			self.lastMaskError = errorMessage
			if AL.Debug and AL.Debug.CaptureError then
				AL.Debug.CaptureError("HealingEngine mask: " .. errorMessage, "healing engine")
			end
		end
	end
	return self.state.activeRows > 0
end

function Engine:DebugState()
	local result = {
		version = self.VERSION,
		supportedClasses = { "DRUID", "PALADIN", "PRIEST", "SHAMAN" },
		class = AL.playerClass,
		pixel = { x = AL.ProtocolPixelLayout and AL.ProtocolPixelLayout.x or 163,
			y = AL.ProtocolPixelLayout and AL.ProtocolPixelLayout.healing or 0 },
	}
	for key, value in pairs(self.state or {}) do result[key] = value end
	return result
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION",
	"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function()
	-- The display driver performs the next protected-mask evaluation. Clearing
	-- immediately prevents a departed unit's color from persisting between ticks.
	Engine:ClearVisuals()
end)

