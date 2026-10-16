local ADDON, AL = ...

-- ActionLITE Druid v0.12.4: original Leveling plus optional talent builds.

-- Leveling keeps the finalized pre-simulation implementation in its own
-- scope. Talent builds use the separate implementation below. Both observe
-- real casts so switching rotations retains resource and spell history.
do
    local root = AL
    local leveling, advanced
    local function UsesLeveling(profile)
        profile = profile or (root.Profile and root.Profile("DRUID")) or (root.S and root.S())
        if advanced and type(profile) == "table" then
            return advanced.NormalizeBuild(profile) == "leveling"
        end
        return true
    end
    local function RotationScope(isLeveling)
        local scope = {
            RegisterRotation = function(token, module)
                assert(token == "DRUID", "Unexpected class rotation")
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
                    if root.playerClass == "DRUID" and UsesLeveling() == isLeveling then root[key] = value end
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
-- BEGIN ORIGINAL LEVELING IMPLEMENTATION (Druid(1).lua)
local ADDON, AL = ...

-- Feral leveling priority per the WoW Forever guide (levels 1-30):
-- caster stage -> Bear Form at 10 -> Cat Form at 20
local M = {
	defaults = {
		buffs = true, thorns = true, heal = true, rake = true, rip = true,
		enrage = true, aoe = false, drink = true, tigersfury = true, bash = true,
	},
}

M.spells = {
	{ 5211, "Bash" },
	{ 5487, "Bear Form" },
	{ 9634, "Dire Bear Form" },
	{ 768, "Cat Form" },
	{ 1082, "Claw" },
	{ 8946, "Cure Poison" },
	{ 1850, "Dash" },
	{ 99, "Demoralizing Roar" },
	{ 5229, "Enrage" },
	{ 339, "Entangling Roots" },
	{ 770, "Faerie Fire" },
	{ 22568, "Ferocious Bite" },
	{ 6795, "Growl" },
	{ 5185, "Healing Touch" },
	{ 2637, "Hibernate" },
	{ 1126, "Mark of the Wild" },
	{ 6807, "Maul" },
	{ 8921, "Moonfire" },
	{ 16689, "Nature's Grasp" },
	{ 5215, "Prowl" },
	{ 1822, "Rake" },
	{ 8936, "Regrowth" },
	{ 774, "Rejuvenation" },
	{ 2782, "Remove Curse" },
	{ 1079, "Rip" },
	{ 5221, "Shred" },
	{ 2908, "Soothe Animal" },
	{ 779, "Swipe" },
	{ 467, "Thorns" },
	{ 5217, "Tiger's Fury" },
	{ 5225, "Track Humanoids" },
	{ 5176, "Wrath" },
}

-- Health thresholds are inclusive; resource costs are minimum amounts.
-- These are the existing Druid rules, rather than another class's thresholds.
local RULES = {
    healRest = 60, healCaster = 50, healEmergency = 25, drinkMana = 30,
    rakeAboveHP = 40, ripAboveHP = 60, ripPoints = 4,
    biteLowHP = 40, biteLowPoints = 3, bitePoints = 5,
    enrageBelowRage = 20, swipeEnemies = 2,
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
local function SpellUsability(name)
    local usable, shortage = SafeCall(IsUsableSpell or (C_Spell and C_Spell.IsSpellUsable), LearnedID(name) or name)
    return Bool(usable), Bool(shortage)
end
local function Ready(name)
    return AL.Ok(name) and AL.IsReady(name)
end

local function Form()
    local index = Number((SafeCall(GetShapeshiftForm)))
    if index == 0 then return "caster" end
    if index and index > 0 then
        local _, _, _, spellID = SafeCall(GetShapeshiftFormInfo, index)
        spellID = Number(spellID)
        if spellID == 768 then return "cat" end
        if spellID == 5487 or spellID == 9634 then return "bear" end
    end
    local powerType = Number((SafeCall(UnitPowerType, "player")))
    if powerType == 3 then return "cat" end
    if powerType == 1 then return "bear" end
    -- A readable active form index is authoritative, including travel forms.
    if index and index > 0 then return "other" end
    if powerType == 0 then return "caster" end
    if AL.HasBuff("player", "Cat Form") then return "cat" end
    if AL.HasBuff("player", "Bear Form") or AL.HasBuff("player", "Dire Bear Form") then return "bear" end
    return "caster"
end
M.CurrentForm = Form

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

local function Power(kind)
    -- A shapeshifted Druid has several pools: energy/rage must never become mana.
    local amount = Number((SafeCall(UnitPower, "player", kind)))
    local currentType = Number((SafeCall(UnitPowerType, "player")))
    if amount == nil and currentType == kind then amount = Number((SafeCall(AL.Power, kind))) end
    return amount and amount >= 0 and amount or nil
end

local lastRotation, openerBlocked, lastSuccessfulCastAt
local visibilityCurves, curveFailures = {}, {}
local powerMaximumCache = {}

local function CurveAvailable(kind, unit, powerType)
    unit = unit or "target"
    local reader = kind == "power" and UnitPowerPercent or UnitHealthPercent
    local key = kind .. ":" .. unit .. ":" .. tostring(powerType or "")
    local failure = curveFailures[key]
    if failure and failure.reader == reader then return false end
    return C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function"
        and type(CreateColor) == "function" and type(reader) == "function"
end

local function PowerMaximum(kind)
    local value = Number((SafeCall(UnitPowerMax, "player", kind)))
    if value and value > 0 then powerMaximumCache[kind] = value end
    return powerMaximumCache[kind]
end

local function NextFloat32(value)
    if value <= 0 then return 2 ^ -149 end
    local exponent = math.floor(math.log(value) / math.log(2))
    local step = 2 ^ (exponent - 23)
    return (math.floor(value / step + 0.5) + 1) * step
end

local function HealthGate(unit, value, threshold, below, strict)
    if value ~= nil then
        if below then return strict and value < threshold or not strict and value <= threshold end
        return strict and value > threshold or not strict and value >= threshold
    end
    if not CurveAvailable("health", unit) then return false end
    local cut = threshold / 100
    if below and not strict or not below and strict then cut = NextFloat32(cut) end
    return { axis = unit .. "HP", kind = "health", unit = unit, cut = cut, below = below }
end

local function PowerGate(kind, amount, threshold, below, strict)
    if amount ~= nil then
        if below then return strict and amount < threshold or not strict and amount <= threshold end
        return amount >= threshold
    end
    local maximum = PowerMaximum(kind)
    if not maximum or not CurveAvailable("power", "player", kind) then return false end
    if not below and threshold <= 0 then return true end
    if not below and threshold > maximum then return false end
    local cut = threshold / maximum
    if below and not strict then cut = NextFloat32(cut) end
    return { axis = "power" .. kind, kind = "power", powerType = kind, unit = "player", cut = cut, below = below }
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

local function Offer(name, reason, gates, kind, fallbackCost, pool, shifting)
    if not Ready(name) then return false end
    local usable, shortage = SpellUsability(name)
    -- A false/false answer is a failed requirement, not a reason to pool.
    -- Keep the existing shift-out heal recommendation when form alone blocks usability.
    if usable == false and shortage ~= true and not shifting then return false end
    local conditions = {}
    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
    if kind ~= nil then
        local amount, cost = Power(kind), SpellCost(name, kind, fallbackCost)
        local gate
        if cost ~= nil then
            gate = PowerGate(kind, amount, cost, false)
            if amount == nil and (not PowerMaximum(kind) or not CurveAvailable("power", "player", kind)) then
                gate = usable ~= false
            end
        else
            gate = usable ~= false
        end
        if shortage == true then gate = false end
        conditions[#conditions + 1] = gate
    elseif usable == false then
        return false
    end
    local offered = AddAction(name, reason, conditions)
    if pool then AddAction(nil, "Pool " .. (kind == 1 and "rage" or "energy") .. " for " .. name, gates) end
    return offered
end

local function InMelee(name)
    return Bool((SafeCall(AL.InRange, name))) == true
end

local function ActiveEnemyCount()
    local action = _G.Action
    if action and action.MultiUnits then
        local units = action.MultiUnits
        local count = Number((SafeCall(units.GetActiveEnemies, units, 5)))
            or Number((SafeCall(units.GetByRangeInCombat, units, nil, RULES.swipeEnemies)))
        if count and count >= 0 then return count end
    end
    local seen, count = {}, 0
    local reference = LearnedID("Maul")
    local function Count(unit)
        if not SafeValue(unit) or type(unit) ~= "string" then return end
        if Bool((SafeCall(UnitExists, unit))) ~= true or Bool((SafeCall(UnitCanAttack, "player", unit))) ~= true
            or Bool((SafeCall(UnitIsDeadOrGhost, unit))) ~= false then return end
        if unit ~= "target" and Bool((SafeCall(UnitAffectingCombat, unit))) ~= true then return end
        local guid = SafeCall(UnitGUID, unit)
        if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] then return end
        local range = unit == "target" and SafeCall(AL.InRange, "Maul")
            or SafeCall(C_Spell and C_Spell.IsSpellInRange, reference or "Maul", unit)
        if not SafeValue(range) or (range ~= true and range ~= 1) then return end
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
    end
    return count > 0 and count or nil
end

function M.OnTargetChanged()
    openerBlocked, lastRotation, AL.rotationSecretVisual = false, nil, nil
end
function M.OnUIError(message)
    if not SafeValue(message) or type(message) ~= "string" then return end
    if (SPELL_FAILED_NOT_BEHIND and message == SPELL_FAILED_NOT_BEHIND)
        or (ERR_BADATTACKPOS and message == ERR_BADATTACKPOS) then openerBlocked = true end
end
function M.OnCastResult(name, event)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then lastSuccessfulCastAt = GetTime()
    elseif name == "Shred" then openerBlocked = true end
end
function M.CanTrackSuggestedSpell(name)
    if not lastRotation or GetTime() - lastRotation.at > 0.5 then return false end
    local visual = AL.rotationSecretVisual
    if visual and GetTime() - visual.at <= 0.5 then return false end
    if lastRotation.visualCandidate then return false end
    if name ~= lastRotation.baseSpell or not AL.Ok(name) then return false end
    for _, entry in ipairs(M.spells) do if entry[2] == name then return true end end
    return name == "Berserking" or name == "War Stomp"
end

local function RecoverStaleComboPoints(cp)
    if cp <= 0 or (lastSuccessfulCastAt and GetTime() - lastSuccessfulCastAt < 1.5) then return cp end
    if Number((SafeCall(GetComboPoints, "player", "target"))) ~= 0
        or Number((SafeCall(UnitPower, "player", 4))) ~= 0 then return cp end
    if not Ready("Rip") or not Ready("Ferocious Bite") or not Ready("Claw") then return cp end
    local rip, ripShortage = SpellUsability("Rip")
    local bite, biteShortage = SpellUsability("Ferocious Bite")
    local claw, clawShortage = SpellUsability("Claw")
    if rip == false and ripShortage == false and bite == false and biteShortage == false
        and claw == true and clawShortage == false and InMelee("Claw") and AL.ResetComboPoints then
        AL.ResetComboPoints()
        return 0
    end
    return cp
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
				error("Druid resource curve unavailable")
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

local function Heal(hp, threshold, shifting)
    if not AL.HasBuff("player", "Rejuvenation") then
        Offer("Rejuvenation", shifting and "heal (shift out)" or "heal", {
            HealthGate("player", hp, threshold, true) }, 0, nil, false, shifting)
    end
end

local function CatRotation(s, targetHP, inCombat)
    local cp = Number((SafeCall(AL.ComboPoints))) or 0
    if cp < 0 or cp > 5 or cp ~= math.floor(cp) then cp = 0 end
    cp = RecoverStaleComboPoints(cp)
    if not inCombat and AL.HasBuff("player", "Prowl") and not openerBlocked and InMelee("Shred") then
        Offer("Shred", "stealth opener", nil, 3, 60, true)
    end
    if s.tigersfury and not AL.HasBuff("player", "Tiger's Fury") then
        Offer("Tiger's Fury", "buff", nil, 3, 30)
    end
    if s.rake and not AL.HasDebuff("target", "Rake") then
        Offer("Rake", "dot", { HealthGate("target", targetHP, RULES.rakeAboveHP, false, true) }, 3, 40, true)
    end
    if s.rip and cp >= RULES.ripPoints and not AL.HasDebuff("target", "Rip") then
        Offer("Rip", cp .. " cp", { HealthGate("target", targetHP, RULES.ripAboveHP, false, true) }, 3, 30, true)
    end
    if cp >= RULES.biteLowPoints then
        local gates = cp < RULES.bitePoints and { HealthGate("target", targetHP, RULES.biteLowHP, true) } or nil
        Offer("Ferocious Bite", cp .. " cp", gates, 3, 35, true)
    end
    Offer("Claw", "builder", nil, 3, 40, true)
    AddAction(AL.Ok("Attack") and "Attack" or nil, "melee")
end

local function BearRotation(s)
    local rage = Power(1)
    if s.bash and Bool((SafeCall(AL.TargetCasting))) == true and InMelee("Bash") then
        Offer("Bash", "interrupt", nil, 1, 10)
    end
    if s.enrage and not AL.HasBuff("player", "Enrage") then
        Offer("Enrage", "rage", { PowerGate(1, rage, RULES.enrageBelowRage, true, true) })
    end
    if s.enrage and not AL.HasDebuff("target", "Demoralizing Roar") and InMelee("Maul") then
        Offer("Demoralizing Roar", "mitigation", nil, 1, 10)
    end
    local count = s.aoe and ActiveEnemyCount()
    if count and count >= RULES.swipeEnemies and InMelee("Maul") then Offer("Swipe", "aoe", nil, 1, 20) end
    local current = Bool((SafeCall(IsCurrentSpell, LearnedID("Maul") or "Maul")))
    if current ~= true then Offer("Maul", "rage dump", nil, 1, 15) end
    AddAction(AL.Ok("Attack") and "Attack" or nil, "melee")
end

local function CasterRotation(s, hp)
    if s.heal then Heal(hp, RULES.healCaster) end
    if not AL.HasDebuff("target", "Moonfire") then Offer("Moonfire", "dot", nil, 0) end
    Offer("Wrath", "filler", nil, 0)
    AddAction(AL.Ok("Attack") and "Attack" or nil, "melee / out of mana")
end

function M.NextSpell(s, inCombat, hostile)
    if not inCombat then curveFailures, powerMaximumCache = {}, {} end
    lastRotation = { at = GetTime(), actions = {} }
    local form, hp = Form(), HealthPercent("player")
    if not inCombat then
        if form == "caster" then
            if s.buffs and not AL.HasBuff("player", "Mark of the Wild") then Offer("Mark of the Wild", "buff", nil, 0) end
            if s.thorns and not AL.HasBuff("player", "Thorns") then Offer("Thorns", "buff", nil, 0) end
            if s.heal then
                Heal(hp, RULES.healRest)
                Offer("Healing Touch", "heal up", { HealthGate("player", hp, RULES.healRest, true) }, 0)
            end
            if s.drink then
                local manaPercent = Percent((SafeCall(AL.ManaPercent)))
                local gate
                if manaPercent ~= nil then gate = manaPercent <= RULES.drinkMana
                else
                    local maximum = PowerMaximum(0)
                    gate = maximum and PowerGate(0, Power(0), maximum * RULES.drinkMana / 100, true) or false
                end
                AddAction(nil, "Drink", { gate })
            end
        elseif s.heal then
            Heal(hp, RULES.healRest, true)
            Offer("Healing Touch", "heal up (shift out)", {
                HealthGate("player", hp, RULES.healRest, true) }, 0, nil, false, true)
        end
        if hostile then
            if form == "cat" then
                if not AL.HasBuff("player", "Prowl") then Offer("Prowl", "sneak in") end
                CatRotation(s, HealthPercent("target"), false)
            elseif form == "bear" then BearRotation(s)
            elseif form == "caster" then CasterRotation(s, hp) end
        end
    elseif hostile then
        if s.heal and form ~= "caster" then Heal(hp, RULES.healEmergency, true) end
        if AL.burst then
            Offer("Berserking", "burst")
            if InMelee(form == "cat" and "Claw" or "Maul") then Offer("War Stomp", "burst", nil, 0) end
        end
        if form == "cat" then CatRotation(s, HealthPercent("target"), true)
        elseif form == "bear" then BearRotation(s)
        elseif form == "caster" then CasterRotation(s, hp) end
    end
    AddAction(nil, inCombat and not hostile and "No target" or "Ready")
    local base = lastRotation.actions[#lastRotation.actions]
    lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
    return base.spell, base.reason
end

if AL.selfCastSpells then
    for _, name in ipairs({ "Mark of the Wild", "Thorns", "Rejuvenation", "Healing Touch", "Regrowth",
        "Bear Form", "Dire Bear Form", "Cat Form", "Prowl", "Enrage", "Tiger's Fury", "Dash", "Berserking" }) do
        AL.selfCastSpells[name] = true
    end
end

function M.BuildOptions(page, ui)
	local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h:SetPoint("TOP", 0, -30)
	h:SetText("Rotation hints (adapts to your form):")
	ui.SettingCheck(page, 70, -52, "Mark of the Wild upkeep", "buffs")
	ui.SettingCheck(page, 70, -78, "Thorns upkeep", "thorns")
	ui.SettingCheck(page, 70, -104, "Heal reminders", "heal")
	ui.SettingCheck(page, 70, -130, "Drink reminder", "drink")
	ui.SettingCheck(page, 70, -156, "Bash interrupt (bear)", "bash")
	ui.SettingCheck(page, 290, -52, "Rake (cat)", "rake")
	ui.SettingCheck(page, 290, -78, "Rip on tough mobs (cat)", "rip")
	ui.SettingCheck(page, 290, -104, "Tiger's Fury (cat)", "tigersfury")
	ui.SettingCheck(page, 290, -130, "Enrage + Demo Roar (bear)", "enrage")
	ui.SettingCheck(page, 290, -156, "AoE mode (Swipe)", "aoe")
end

AL.RegisterRotation("DRUID", M)
-- END ORIGINAL LEVELING IMPLEMENTATION
    end)(ADDON, RotationScope(true))

    ;(function(...)
-- BEGIN OPTIONAL TALENT BUILD IMPLEMENTATION
local ADDON, AL = ...

-- ActionLITE Druid 0.12.4: Feral Bear 0/41/10, Balance 41/0/10, Feral Cat 9/34/8.
-- Bear reference: MythicSim Forever b1137248e6b4 (1.60.1.70338).
-- Balance reference: MythicSim Forever 944a791060db (1.60.1.70338).
-- Feral leveling priority per the WoW Forever guide (levels 1-60):
-- caster stage -> Bear Form at 10 -> Cat Form at 20
local M = {
	defaults = {
        leveling = true,
        feralBear = false, bearAutoForm = true, bearPrimalBite = true,
        bearLacerate = true, bearLacerateFiller = true, bearLacerateStacks = 5,
        bearFaerieFire = true, bearDemoRoar = true, bearGrowl = true,
        bearCharge = true, bearChallengingRoar = true,
        bearBarkskin = true, bearBarkskinHP = 45,
        bearFrenzied = true, bearFrenziedHP = 35, bearFrenziedRage = 10,
        bearEnrageBelowRage = 20, bearEnrageMinHP = 75,
        bearMaul = true, bearMaulRage = 25, bearSwipe = true, bearAoeMinEnemies = 3,
        bearBerserk = true, bearElunesLight = true, bearBerserking = true,
        bearBurstMinTargetHP = 35,
		balance = false, balanceMoonkin = true, balanceInsectSwarm = true,
		balanceMoonfire = true, balanceStarfire = true, balanceWrath = true,
		balanceMinMana = 0, balanceDotMinTargetHP = 0,
		balanceInnervate = true, balanceInnervateMana = 10,
		balanceHurricane = true, balanceAoeMinEnemies = 3, balanceAoeMinMana = 35,
		balanceElunesLight = true, balanceBerserking = true,
		balanceBurstMinMana = 20, balanceBurstMinTargetHP = 35,
		feralCat = false, catFaerieFire = true, catShiftingPower = true,
		catShiftBelowEnergy = 40, catBite = true, catShred = false, catRavage = true,
		catProwl = true, catInnervate = true, catInnervateMana = 10,
		catBerserk = true, catElunesLight = true, catBurstMinTargetHP = 35,
		catBurstMinEnergy = 30, catHurricane = false, catAoeMinEnemies = 3,
		catAoeMinMana = 50,
		buffs = true, thorns = true, heal = true, rake = true, rip = true,
		enrage = true, aoe = false, drink = true, tigersfury = true, bash = true,
	},
}

-- Exactly one rotation stays selected. Leveling is the default and the
-- fallback when a selected specialization is switched off or saved flags
-- conflict. A valid saved specialization takes priority during migration.
M.buildKeys = { "leveling", "feralBear", "balance", "feralCat" }
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
    s.bearPreviousDPS = nil
    return selected
end
function M.SetBuild(key, enabled, s)
    if (issecretvalue and issecretvalue(enabled)) or type(enabled) ~= "boolean" then return end
    local valid = false
    for _, candidate in ipairs(M.buildKeys) do if candidate == key then valid = true; break end end
    if not valid then return end
    s = s or AL.Profile("DRUID")
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
	{ 417141, "Berserk" },
	{ 5211, "Bash" },
	{ 22812, "Barkskin" },
	{ 5487, "Bear Form" },
	{ 9634, "Dire Bear Form" },
	{ 768, "Cat Form" },
	{ 5209, "Challenging Roar" },
	{ 1082, "Claw" },
	{ 8946, "Cure Poison" },
	{ 1850, "Dash" },
	{ 99, "Demoralizing Roar" },
	{ 5229, "Enrage" },
	{ 1259799, "Elune's Light" },
	{ 339, "Entangling Roots" },
	{ 770, "Faerie Fire" },
	{ 1238122, "Feral Charge" },
	{ 22568, "Ferocious Bite" },
	{ 22842, "Frenzied Regeneration" },
	{ 6795, "Growl" },
	{ 5185, "Healing Touch" },
	{ 2637, "Hibernate" },
	{ 16914, "Hurricane" },
	{ 29166, "Innervate" },
	{ 5570, "Insect Swarm" },
	{ 414644, "Lacerate" },
	{ 1126, "Mark of the Wild" },
	{ 6807, "Maul" },
	{ 8921, "Moonfire" },
	{ 24858, "Moonkin Form" },
	{ 16689, "Nature's Grasp" },
	{ 5215, "Prowl" },
	{ 407995, "Primal Bite" },
	{ 1822, "Rake" },
	{ 6785, "Ravage" },
	{ 8936, "Regrowth" },
	{ 774, "Rejuvenation" },
	{ 2782, "Remove Curse" },
	{ 1079, "Rip" },
	{ 5221, "Shred" },
	{ 1322605, "Shifting Power" },
	{ 2908, "Soothe Animal" },
	{ 2912, "Starfire" },
	{ 779, "Swipe" },
	{ 467, "Thorns" },
	{ 5217, "Tiger's Fury" },
	{ 5225, "Track Humanoids" },
	{ 5176, "Wrath" },
}

-- Health thresholds are inclusive; resource costs are minimum amounts.
-- These are the existing Druid rules, rather than another class's thresholds.
local RULES = {
    healRest = 60, healCaster = 50, healEmergency = 25, drinkMana = 30,
    rakeAboveHP = 40, ripAboveHP = 60, ripPoints = 4,
    biteLowHP = 40, biteLowPoints = 3, bitePoints = 5,
    enrageBelowRage = 20, swipeEnemies = 2,
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
    local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(reader, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l end
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
local function Ready(name)
    if AL.DPS60 and AL.DPS60.Active() and AL.DPS60.Info(name) then return AL.DPS60.Ready(name) end
    return AL.Ok(name) and AL.IsReady(name)
end

local function Form()
    local index = Number((SafeCall(GetShapeshiftForm)))
    if index == 0 then return "caster" end
    if index and index > 0 then
        local _, _, _, spellID = SafeCall(GetShapeshiftFormInfo, index)
        spellID = Number(spellID)
        if spellID == 24858 then return "caster" end
        if spellID == 768 then return "cat" end
        if spellID == 5487 or spellID == 9634 then return "bear" end
    end
    local powerType = Number((SafeCall(UnitPowerType, "player")))
    if powerType == 3 then return "cat" end
    if powerType == 1 then return "bear" end
    -- A readable active form index is authoritative, including travel forms.
    if index and index > 0 then return "other" end
    if powerType == 0 then return "caster" end
    if AL.HasBuff("player", "Cat Form") then return "cat" end
    if AL.HasBuff("player", "Bear Form") or AL.HasBuff("player", "Dire Bear Form") then return "bear" end
    return "caster"
end
M.CurrentForm = Form

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

local function Power(kind)
    -- A shapeshifted Druid has several pools: energy/rage must never become mana.
    local amount = Number((SafeCall(UnitPower, "player", kind)))
    local currentType = Number((SafeCall(UnitPowerType, "player")))
    if amount == nil and currentType == kind then amount = Number((SafeCall(AL.Power, kind))) end
    return amount and amount >= 0 and amount or nil
end

local lastRotation, openerBlocked, lastSuccessfulCastAt
local visibilityCurves, curveFailures = {}, {}
local powerMaximumCache = {}

local function CurveAvailable(kind, unit, powerType)
    unit = unit or "target"
    local reader = kind == "power" and UnitPowerPercent or UnitHealthPercent
    local key = kind .. ":" .. unit .. ":" .. tostring(powerType or "")
    local failure = curveFailures[key]
    if failure and failure.reader == reader then return false end
    return C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function"
        and type(CreateColor) == "function" and type(reader) == "function"
end

local function PowerMaximum(kind)
    local value = Number((SafeCall(UnitPowerMax, "player", kind)))
    if value and value > 0 then powerMaximumCache[kind] = value end
    return powerMaximumCache[kind]
end

local function NextFloat32(value)
    if value <= 0 then return 2 ^ -149 end
    local exponent = math.floor(math.log(value) / math.log(2))
    local step = 2 ^ (exponent - 23)
    return (math.floor(value / step + 0.5) + 1) * step
end

local function HealthGate(unit, value, threshold, below, strict)
    if value ~= nil then
        if below then return strict and value < threshold or not strict and value <= threshold end
        return strict and value > threshold or not strict and value >= threshold
    end
    if not CurveAvailable("health", unit) then return false end
    local cut = threshold / 100
    if below and not strict or not below and strict then cut = NextFloat32(cut) end
    return { axis = unit .. "HP", kind = "health", unit = unit, cut = cut, below = below }
end

local function PowerGate(kind, amount, threshold, below, strict)
    if amount ~= nil then
        if below then return strict and amount < threshold or not strict and amount <= threshold end
        return amount >= threshold
    end
    local maximum = PowerMaximum(kind)
    if not maximum or not CurveAvailable("power", "player", kind) then return false end
    if not below and threshold <= 0 then return true end
    if not below and threshold > maximum then return false end
    local cut = threshold / maximum
    if below and not strict then cut = NextFloat32(cut) end
    return { axis = "power" .. kind, kind = "power", powerType = kind, unit = "player", cut = cut, below = below }
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

local function Offer(name, reason, gates, kind, fallbackCost, pool, shifting)
    if not Ready(name) then return false end
    local usable, shortage = SpellUsability(name)
    -- A false/false answer is a failed requirement, not a reason to pool.
    -- Keep the existing shift-out heal recommendation when form alone blocks usability.
    if usable == false and shortage ~= true and not shifting then return false end
    local conditions = {}
    for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
    if kind ~= nil then
        local amount, cost = Power(kind), SpellCost(name, kind, fallbackCost)
        local gate
        if cost ~= nil then
            gate = PowerGate(kind, amount, cost, false)
            if amount == nil and (not PowerMaximum(kind) or not CurveAvailable("power", "player", kind)) then
                gate = usable ~= false
            end
        else
            gate = usable ~= false
        end
        if shortage == true then gate = false end
        conditions[#conditions + 1] = gate
    elseif usable == false then
        return false
    end
    local offered = AddAction(name, reason, conditions)
    if pool then AddAction(nil, "Pool " .. (kind == 1 and "rage" or "energy") .. " for " .. name, gates) end
    return offered
end

local function InMelee(name)
    return Bool((SafeCall(AL.InRange, name))) == true
end

local function ActiveEnemyCount()
    local action = _G.Action
    if action and action.MultiUnits then
        local units = action.MultiUnits
        local count = Number((SafeCall(units.GetActiveEnemies, units, 5)))
            or Number((SafeCall(units.GetByRangeInCombat, units, nil, RULES.swipeEnemies)))
        if count and count >= 0 then return count end
    end
    local seen, count = {}, 0
    local reference = LearnedID("Maul")
    local function Count(unit)
        if not SafeValue(unit) or type(unit) ~= "string" then return end
        if Bool((SafeCall(UnitExists, unit))) ~= true or Bool((SafeCall(UnitCanAttack, "player", unit))) ~= true
            or Bool((SafeCall(UnitIsDeadOrGhost, unit))) ~= false then return end
        if unit ~= "target" and Bool((SafeCall(UnitAffectingCombat, unit))) ~= true then return end
        local guid = SafeCall(UnitGUID, unit)
        if not SafeValue(guid) or type(guid) ~= "string" or seen[guid] then return end
        local range = unit == "target" and SafeCall(AL.InRange, "Maul")
            or SafeCall(C_Spell and C_Spell.IsSpellInRange, reference or "Maul", unit)
        if not SafeValue(range) or (range ~= true and range ~= 1) then return end
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
    end
    return count > 0 and count or nil
end

function M.OnTargetChanged()
    openerBlocked, lastRotation, AL.rotationSecretVisual = false, nil, nil
end
function M.OnUIError(message)
    if not SafeValue(message) or type(message) ~= "string" then return end
    if (SPELL_FAILED_NOT_BEHIND and message == SPELL_FAILED_NOT_BEHIND)
        or (ERR_BADATTACKPOS and message == ERR_BADATTACKPOS) then openerBlocked = true end
end
function M.OnCastResult(name, event)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then lastSuccessfulCastAt = GetTime()
    elseif name == "Shred" then openerBlocked = true end
end
function M.CanTrackSuggestedSpell(name)
    if not lastRotation or GetTime() - lastRotation.at > 0.5 then return false end
    local visual = AL.rotationSecretVisual
    if visual and GetTime() - visual.at <= 0.5 then return false end
    if lastRotation.visualCandidate then return false end
    if name ~= lastRotation.baseSpell or not AL.Ok(name) then return false end
    for _, entry in ipairs(M.spells) do if entry[2] == name then return true end end
    return name == "Berserking" or name == "War Stomp"
end

local function RecoverStaleComboPoints(cp)
    if cp <= 0 or (lastSuccessfulCastAt and GetTime() - lastSuccessfulCastAt < 1.5) then return cp end
    if Number((SafeCall(GetComboPoints, "player", "target"))) ~= 0
        or Number((SafeCall(UnitPower, "player", 4))) ~= 0 then return cp end
    if not Ready("Rip") or not Ready("Ferocious Bite") or not Ready("Claw") then return cp end
    local rip, ripShortage = SpellUsability("Rip")
    local bite, biteShortage = SpellUsability("Ferocious Bite")
    local claw, clawShortage = SpellUsability("Claw")
    if rip == false and ripShortage == false and bite == false and biteShortage == false
        and claw == true and clawShortage == false and InMelee("Claw") and AL.ResetComboPoints then
        AL.ResetComboPoints()
        return 0
    end
    return cp
end

local function IntervalCurve(low, high)
	local key = tostring(low) .. ":" .. tostring(high)
	if visibilityCurves[key] then return visibilityCurves[key] end
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	-- Inclusive 100% comparisons use the next float above one. Intervals
	-- beyond the percentage domain must stay invisible at a full resource bar.
	if low > 1 or high <= 0 then
		curve:AddPoint(0, CreateColor(1, 1, 1, 0))
		curve:AddPoint(1, CreateColor(1, 1, 1, 0))
		visibilityCurves[key] = curve
		return curve
	end
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
				error("Druid resource curve unavailable")
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

local function Heal(hp, threshold, shifting)
    if not AL.HasBuff("player", "Rejuvenation") then
        Offer("Rejuvenation", shifting and "heal (shift out)" or "heal", {
            HealthGate("player", hp, threshold, true) }, 0, nil, false, shifting)
    end
end

local function CatRotation(s, targetHP, inCombat)
    local cp = Number((SafeCall(AL.ComboPoints))) or 0
    if cp < 0 or cp > 5 or cp ~= math.floor(cp) then cp = 0 end
    cp = RecoverStaleComboPoints(cp)
    if not inCombat and AL.HasBuff("player", "Prowl") and not openerBlocked and InMelee("Shred") then
        Offer("Shred", "stealth opener", nil, 3, 60, true)
    end
    if s.tigersfury and not AL.HasBuff("player", "Tiger's Fury") then
        Offer("Tiger's Fury", "buff", nil, 3, 30)
    end
    if s.rake and not AL.HasDebuff("target", "Rake") then
        Offer("Rake", "dot", { HealthGate("target", targetHP, RULES.rakeAboveHP, false, true) }, 3, 40, true)
    end
    if s.rip and cp >= RULES.ripPoints and not AL.HasDebuff("target", "Rip") then
        Offer("Rip", cp .. " cp", { HealthGate("target", targetHP, RULES.ripAboveHP, false, true) }, 3, 30, true)
    end
    if cp >= RULES.biteLowPoints then
        local gates = cp < RULES.bitePoints and { HealthGate("target", targetHP, RULES.biteLowHP, true) } or nil
        Offer("Ferocious Bite", cp .. " cp", gates, 3, 35, true)
    end
    if AL.DPS60 and AL.DPS60.Active() and AL.DPS60.Known("Shifting Power") then
        Offer("Shifting Power", "recover energy", { PowerGate(3, Power(3), 40, true, true) }, 0)
    end
    Offer("Claw", "builder", nil, 3, 40, true)
    AddAction(AL.Ok("Attack") and "Attack" or nil, "melee")
end

local function BearRotation(s)
    local rage = Power(1)
    if s.bash and Bool((SafeCall(AL.TargetCasting))) == true and InMelee("Bash") then
        Offer("Bash", "interrupt", nil, 1, 10)
    end
    if s.enrage and not AL.HasBuff("player", "Enrage") then
        Offer("Enrage", "rage", { PowerGate(1, rage, RULES.enrageBelowRage, true, true) })
    end
    if s.enrage and not AL.HasDebuff("target", "Demoralizing Roar") and InMelee("Maul") then
        Offer("Demoralizing Roar", "mitigation", nil, 1, 10)
    end
    local count = s.aoe and ActiveEnemyCount()
    if count and count >= RULES.swipeEnemies and InMelee("Maul") then Offer("Swipe", "aoe", nil, 1, 20) end
    local current = Bool((SafeCall(IsCurrentSpell, LearnedID("Maul") or "Maul")))
    if current ~= true then Offer("Maul", "rage dump", nil, 1, 15) end
    AddAction(AL.Ok("Attack") and "Attack" or nil, "melee")
end

local function CasterRotation(s, hp)
    if s.heal then Heal(hp, RULES.healCaster) end
    if not AL.HasDebuff("target", "Moonfire") then Offer("Moonfire", "dot", nil, 0) end
    if AL.DPS60 and AL.DPS60.Active() then
        if AL.DPS60.Missing("Insect Swarm", true) then Offer("Insect Swarm", "Balance DoT", nil, 0) end
        local enemies = s.aoe and ActiveEnemyCount()
        if enemies and enemies >= RULES.swipeEnemies then Offer("Hurricane", "Balance AoE", nil, 0) end
        local eclipse, _, stacks = AL.DPS60.Aura("Eclipse", false)
        if eclipse == true and stacks and stacks >= 1 then Offer("Starfire", "Eclipse", nil, 0) end
        Offer("Wrath", "Balance filler", nil, 0)
        Offer("Starfire", "learned Balance fallback", nil, 0)
    else Offer("Wrath", "filler", nil, 0) end
    AddAction(AL.Ok("Attack") and "Attack" or nil, "melee / out of mana")
end

-- The selected Cat build is self-contained and does not depend on DPS60.lua.
local CAT_LEVELS={['Cat Form']=20,Claw=20,Rip=20,Prowl=20,Shred=20,["Tiger's Fury"]=24,
 Moonfire=4,Rejuvenation=4,Thorns=6,
 Rake=24,Ravage=32,['Ferocious Bite']=32,['Faerie Fire']=18,['Shifting Power']=20,
 Berserk=40,Innervate=40,Hurricane=40,['Elune\'s Light']=1}
local CatKnown,_,CatLearned=AL.LevelGates(CAT_LEVELS)
local catCDBase={Berserk=180,["Elune's Light"]=180,['Shifting Power']=16,Innervate=360,Prowl=10}
local catBuffDuration={Berserk=15,["Elune's Light"]=15,Innervate=20,Prowl=math.huge,
 ['Mark of the Wild']=1800,Thorns=600,Rejuvenation=12,["Tiger's Fury"]=6}
local catDotDuration={Rake=9,Rip=12,['Faerie Fire']=40}
local catRankIDs={}
local function CatRanks(name,ids)for _,id in ipairs(ids)do catRankIDs[id]=name end end
CatRanks('Claw',{1082,3029,5201,9849,9850});CatRanks('Shred',{5221,6800,8992,9829,9830})
CatRanks('Rake',{1822,1823,1824,9904});CatRanks('Rip',{1079,9492,9493,9752,9894,9896})
CatRanks('Ravage',{6785,6787,9866,9867});CatRanks('Ferocious Bite',{22568,22827,22828,22829,31018})
CatRanks('Faerie Fire',{770,778,9749,9907});CatRanks('Prowl',{5215,6783,9913})
CatRanks("Tiger's Fury",{5217,6793,9845,9846});CatRanks('Hurricane',{16914,17401,17402})
for _,row in ipairs(M.spells)do if not catRankIDs[row[1]] then catRankIDs[row[1]]=row[2] end end
local catBuilders={Claw=true,Rake=true,Shred=true,Ravage=true}
local catFinishers={Rip=true,['Ferocious Bite']=true}
local catCDEnds,catCastAt,catBuffs,catDots,catRetry={},{},{},{},{}
local catPending,catCompleted,catLastSent={},{},nil
local catEpoch,catCombo,catComboAt,catSpentAt=0,0,-math.huge,-math.huge
local catLastCombo,catAuraCache,catAuraBlocked=nil,{},{}
local catTalents
local catCosts,catCostWarm={},false
local function CatSetting(s,key,default,low,high)
 local v=SafeValue(s[key]) and Number(tonumber(s[key])) or nil
 return math.max(low,math.min(high,math.floor((v or default)+0.5)))
end
local function CatID(name)
 local id=LearnedID(name);if id then return id end
 for _,row in ipairs(M.spells)do if row[2]==name and row[1]>0 then return row[1] end end
end
local function CatCastName(id)
 id=Number(id);if not id then return end
 if catRankIDs[id] then return catRankIDs[id] end
 for _,row in ipairs(M.spells)do if LearnedID(row[2])==id then return row[2] end end
end
local function CatTarget()local id=SafeCall(UnitGUID,'target');return SafeValue(id) and type(id)=='string' and id or catEpoch end
local function CatTalentRank(name)
 if not catTalents then
  catTalents={}
  for index=1,40 do
   local talent,_,_,_,rank
   local ok
   if type(GetTalentInfo)=='function' then ok,talent,_,_,_,rank=pcall(GetTalentInfo,2,index,false,false)end
   if ok and SafeValue(talent) and type(talent)=='string' and Number(rank) then
    catTalents[(AL.englishNames and AL.englishNames[talent]) or talent]=rank
   end
  end
 end
 return catTalents[name]
end
local function CatCooldownEnd(name)
 local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,CatID(name) or name)
 if not SafeValue(info) or type(info)~='table' then return end
 local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate)
 if SafeValue(info.modRate) and info.modRate==nil then rate=1 end
 if start and start>0 and duration and duration>1.5 and rate and rate>0 then return start+duration/rate end
end
local function CatReady(name)
 if not CatKnown(name) or catRetry[name] and catRetry[name]>GetTime() then return false end
 if not catCDBase[name] then return AL.IsReady(name) end
 local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,CatID(name) or name)
 if SafeValue(info) and type(info)=='table' then
  if Bool(info.isEnabled)==false then return false end
  local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate)
  if SafeValue(info.modRate) and info.modRate==nil then rate=1 end
  local ready
  if start and start>=0 and duration and duration>=0 and rate and rate>0 then ready=start==0 or duration<=1.5 or start+duration/rate<=GetTime()
  elseif Bool(info.isActive)==false then ready=true
  elseif Bool(info.isActive)==true and Bool(info.isOnGCD)==false then ready=false end
  if ready~=nil then
   if ready and catCastAt[name] and GetTime()-catCastAt[name]<0.5 and catCDEnds[name] and catCDEnds[name]>GetTime() then return false end
   return ready
  end
 end
 return not catCDEnds[name] or catCDEnds[name]<=GetTime()
end
local function CatAura(unit,name,own)
 local now=GetTime();local cache=catAuraCache[unit]
 if not cache or now-cache.at>=0.2 then
  cache={at=now,entries={},complete=false};catAuraCache[unit]=cache
  local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not catAuraBlocked[unit] and type(reader)=='function' then
   local complete=true
   for i=1,40 do
    local ok,aura=pcall(reader,unit,i,unit=='target' and 'HARMFUL' or 'HELPFUL')
    if not ok or not SafeValue(aura) then catAuraBlocked[unit]=true;break end
    if aura==nil then cache.complete=complete;break end
    if type(aura)=='table' then
     local id,label=Number(aura.spellId),SafeValue(aura.name) and type(aura.name)=='string' and aura.name
     if label then label=(AL.englishNames and AL.englishNames[label]) or label end
     local mine=Bool(aura.isFromPlayerOrPlayerPet)
     if mine==nil and SafeValue(aura.sourceUnit) and type(aura.sourceUnit)=='string' then mine=aura.sourceUnit=='player' or aura.sourceUnit=='pet' end
     if id or label then cache.entries[#cache.entries+1]={id=id,name=label,mine=mine,expires=Number(aura.expirationTime)}else complete=false end
    else complete=false end
   end
  end
 end
 local unknown=false
 for _,aura in ipairs(cache.entries)do
  if aura.name==name or aura.id and (aura.id==CatID(name) or catRankIDs[aura.id]==name or name=='Clearcasting' and aura.id==16870) then
   if not own or aura.mine==true then return true,aura.expires end
   if aura.mine==nil then unknown=true end
  end
 end
 if not unknown and cache.complete then return false end
end
local function CatBuff(name)
 local state=catBuffs[name];local now=GetTime()
 if state and now-state.at<0.5 then return state.expires>now end
 local active,expires=CatAura('player',name)
 if active~=nil then
  if not active then catBuffs[name]=nil;return false end
  if expires and expires>0 then catBuffs[name]={at=now,expires=expires}end
  return true
 end
 if state then return state.expires>now end
 return Bool((SafeCall(AL.HasBuff,'player',name)))==true
end
local function CatDotLeft(name)
 local state=catDots[name];local now=GetTime()
 if state and state.target==CatTarget() and now-state.at<0.5 then return math.max(0,state.expires-now)end
 local active,expires=CatAura('target',name,name~='Faerie Fire')
 if active==false then return 0 end
 if active then
  if expires and expires>0 then return math.max(0,expires-now)end
  if state and state.target==CatTarget() then return math.max(0,state.expires-now)end
  return math.huge
 end
 if state and state.target==CatTarget() then return math.max(0,state.expires-now)end
 if name=='Faerie Fire' and Bool((SafeCall(AL.HasDebuff,'target',name)))==true then return math.huge end
 return 0
end
local function CatComboPoints()
 local now=GetTime();local raw=Number((SafeCall(GetComboPoints,'player','target')))
 local typed=Number((SafeCall(UnitPower,'player',4)))
 if raw and (raw<0 or raw>5 or raw~=math.floor(raw))then raw=nil end
 if typed and (typed<0 or typed>5 or typed~=math.floor(typed))then typed=nil end
 local native=math.max(raw or 0,typed or 0)
 if native>0 and now-catSpentAt>=0.5 then catCombo=native;return native end
 if now-catSpentAt<0.5 then return catCombo end
 local cp=catCombo
 if cp>0 and now-catComboAt>=1.5 and raw==0 and typed==0 then
  local rip,rs=SpellUsability('Rip');local bite,bs=SpellUsability('Ferocious Bite');local claw,cs=SpellUsability('Claw')
  if CatReady('Rip') and CatReady('Ferocious Bite') and CatReady('Claw') and rip==false and rs==false
   and bite==false and bs==false and claw==true and cs==false then
   catCombo=0;if AL.ResetComboPoints then AL.ResetComboPoints()end;return 0
  end
 end
 return math.max(0,math.min(5,cp))
end
-- Keep the HUD and rotation on the same confirmed-cast fallback. The older
-- shared tracker does not know Ravage or guaranteed Blood Frenzy points.
local priorComboPoints=AL.ComboPoints
AL.ComboPoints=function()
 if AL.playerClass=='DRUID'and AL.S().feralCat==true then return CatComboPoints()end
 return priorComboPoints()
end
local function CatGUID(v)return SafeValue(v) and type(v)=='string' and v:find('^Cast%-') and v or nil end
local catTracker=CreateFrame('Frame')
for _,event in ipairs({'UNIT_SPELLCAST_SENT','UNIT_SPELLCAST_SUCCEEDED','UNIT_SPELLCAST_FAILED','UNIT_SPELLCAST_FAILED_QUIET',
 'UNIT_SPELLCAST_INTERRUPTED','PLAYER_TARGET_CHANGED','PLAYER_ENTERING_WORLD','PLAYER_DEAD','UNIT_AURA',
 'PLAYER_REGEN_ENABLED','SPELLS_CHANGED','PLAYER_TALENT_UPDATE','COMBAT_LOG_EVENT_UNFILTERED'})do pcall(catTracker.RegisterEvent,catTracker,event)end
catTracker:SetScript('OnEvent',function(_,event,unit,a2,a3,a4)
 if AL.playerClass~='DRUID' then return end
 if event=='PLAYER_TARGET_CHANGED' then catEpoch=catEpoch+1;catCombo,catComboAt=0,-math.huge;catDots={};catAuraCache.target=nil;catAuraBlocked.target=nil;return end
 if event=='PLAYER_DEAD' or event=='PLAYER_ENTERING_WORLD' then
  catPending,catCompleted,catLastSent,catRetry={},{},nil,{};catCombo,catComboAt,catSpentAt=0,-math.huge,-math.huge
  catDots,catAuraCache,catAuraBlocked={},{},{};catLastCombo=nil
  if event=='PLAYER_DEAD' then catBuffs={}end;return
 end
 if event=='SPELLS_CHANGED' or event=='PLAYER_TALENT_UPDATE' or event=='PLAYER_REGEN_ENABLED' then
  catTalents=nil;catCostWarm=false
  if event~='PLAYER_REGEN_ENABLED'then catCosts={}end
  catAuraCache,catAuraBlocked={},{};return
 end
 if event=='UNIT_AURA' then if SafeValue(unit) and type(unit)=='string' then catAuraCache[unit]=nil end;return end
 if event=='COMBAT_LOG_EVENT_UNFILTERED' then
  local _,subevent,_,source,_,_,_,dest,_,_,_,id=SafeCall(CombatLogGetCurrentEventInfo)
  local playerGUID=SafeCall(UnitGUID,'player')
  if SafeValue(subevent) and subevent=='SPELL_MISSED' and SafeValue(source) and SafeValue(playerGUID)
   and source==playerGUID and SafeValue(dest) and dest==CatTarget() then
   local name=CatCastName(id)
   if catLastCombo and name==catLastCombo.name and GetTime()-catLastCombo.at<=1 then catCombo=catLastCombo.before;catLastCombo=nil end
   if name=='Rake' or name=='Rip' or name=='Faerie Fire' then catDots[name]=nil end
  end
  return
 end
 if not SafeValue(unit) or unit~='player' then return end
 for guid,at in pairs(catCompleted)do if GetTime()-at>900 then catCompleted[guid]=nil end end
 for guid,sent in pairs(catPending)do if GetTime()-sent.at>30 then catPending[guid]=nil end end
 local guid=CatGUID(event=='UNIT_SPELLCAST_SENT' and a3 or a2)
 local id=Number(a4) or Number(a3);local name=CatCastName(id);local readable=id~=nil
 if event=='UNIT_SPELLCAST_SENT' then
  if not readable and M.CanTrackSuggestedSpell(AL.lastSuggestion) then name=AL.lastSuggestion end
  local target=CatTarget();local label=SafeValue(a2) and type(a2)=='string' and a2
  local targetName,realm=SafeCall(UnitName,'target')
  if label and label~='' and SafeValue(targetName) and type(targetName)=='string' then
   local fullName=SafeValue(realm) and type(realm)=='string' and realm~='' and targetName..'-'..realm or targetName
   if label~=targetName and label~=fullName then target=nil end
  end
  catLastSent={name=name,at=GetTime(),guid=guid,target=target,combo=CatComboPoints()}
  if guid then catPending[guid]=catLastSent end;return
 end
 local sent=guid and catPending[guid] or not guid and catLastSent
 if event~='UNIT_SPELLCAST_SUCCEEDED' then
  if sent and not sent.done then
   sent.failed=true;if sent.name then catRetry[sent.name]=GetTime()+1 end
   if sent.name=='Ravage' or sent.name=='Shred' then openerBlocked=true end
  end
  if guid and not(sent and sent.done)then catCompleted[guid]=GetTime()end;return
 end
 if guid and catCompleted[guid] or sent and(sent.done or sent.failed)then return end
 if not readable and sent and GetTime()-sent.at<=5 then name=sent.name end
 if not name or sent and sent.name and name~=sent.name then return end
 if sent then sent.done=true end;if guid then catCompleted[guid]=GetTime()end
 local now=GetTime();catRetry[name]=nil
 if catCDBase[name] then
  local cooldown=catCDBase[name]
  if name=='Shifting Power' then local rank=CatTalentRank('Improved Shifting Power');if rank then cooldown=16-4*math.max(0,math.min(2,rank))end end
  catCastAt[name]=now;catCDEnds[name]=CatCooldownEnd(name) or now+cooldown
 end
 if catBuffDuration[name]then catBuffs[name]={at=now,expires=now+catBuffDuration[name]};catAuraCache.player=nil end
 if catBuilders[name] or catFinishers[name] or name=='Faerie Fire' or name=='Hurricane' then catBuffs.Prowl={at=now,expires=now};catAuraCache.player=nil end
 if sent and sent.target~=CatTarget()then
  if catDotDuration[name]and not catDots[name]then catDots[name]={at=now-1,expires=now,target=CatTarget()}end
  return
 end
 if catBuilders[name]then
  local before=sent and sent.combo or catCombo
  local rank=CatTalentRank('Blood Frenzy');local gain=CatBuff('Berserk') and rank==2 and 2 or 1
  catLastCombo={name=name,before=before,at=now};catCombo,catComboAt=math.min(5,before+gain),now
 elseif catFinishers[name]then catLastCombo={name=name,before=sent and sent.combo or catCombo,at=now};catCombo,catComboAt,catSpentAt=0,now,now end
 if catDotDuration[name]then catDots[name]={at=now,expires=now+catDotDuration[name],target=CatTarget()};catAuraCache.target=nil end
end)
local function CatCost(name,kind,fallback)
 local identifier=CatID(name)or name;local key=tostring(identifier)..':'..kind
 local cached=catCosts[key]
 local result=SafeCall(C_Spell and C_Spell.GetSpellPowerCost,identifier)
 if SafeValue(result) and type(result)=='table' then
  local total,found=0,false
  for _,entry in ipairs(result)do
   if not SafeValue(entry) or type(entry)~='table'then return cached or fallback end
   if Number(entry.type)==kind then
    local aura=Number(entry.requiredAuraID);local active=true
    if not SafeValue(entry.requiredAuraID)then return cached or fallback end
    if aura and aura>0 then active=Bool(entry.hasRequiredAura);if active==nil then return cached or fallback end end
    if active then local cost=Number(entry.cost);if not cost or cost<0 then return cached or fallback end;found=true;total=total+cost end
   end
  end
  if found then
   -- Keep a positive learned-rank cost if a temporary free cast later hides
   -- its tooltip. A zero-cost proc must not make every following cast free.
   if total>0 then catCosts[key]=total end
   return total
  end
 end
 return cached or fallback
end
local function CatPercentGate(kind,threshold,below,strict)
 if not below and threshold<=0 then return true end
 local maximum=PowerMaximum(kind);if not maximum then return false end
 return PowerGate(kind,Power(kind),maximum*threshold/100,below,strict)
end
local function CatOffer(name,reason,gates,kind,fallback,shifting)
 if not name or not CatReady(name)then return false end
 if name=='Faerie Fire'and Bool((SafeCall(AL.InRange,name)))==false then return false end
 local usable,shortage=SpellUsability(name)
 if shortage==true or usable==false and not shifting then return false end
 local conditions={};for _,gate in ipairs(gates or {})do conditions[#conditions+1]=gate end
 if kind then
  local cost=CatCost(name,kind,fallback)
  if kind==3 and CatBuff('Clearcasting')then cost=0 end
  if cost then
   local amount=Power(kind);local gate=PowerGate(kind,amount,cost,false)
   if amount==nil and(not PowerMaximum(kind)or not CurveAvailable('power','player',kind))then gate=usable==true and shortage~=true end
   conditions[#conditions+1]=gate
  elseif usable~=true then return false end
 end
 return AddAction(name,reason,conditions)
end
local function CatTTD()
 local action=_G.Action;local obj=action and SafeCall(action.Unit,'target')
 if SafeValue(obj) and(type(obj)=='table'or type(obj)=='userdata')then local v=Number((SafeCall(obj.TimeToDie,obj)));if v and v>0 and v<3600 then return v end end
 local v=Number((SafeCall(AL.TargetTTD)));if v and v>0 and v<3600 then return v end
end
local function CatStationary()local speed=Number((SafeCall(GetUnitSpeed,'player')));return speed~=nil and speed==0 end
local function CatWithinArea(unit)
 local squared,checked=SafeCall(UnitDistanceSquared,unit);squared=Number(squared)
 if squared and squared>=0 and Bool(checked)~=false then return squared<=900 end
 local action=_G.Action;local object=action and SafeCall(action.Unit,unit)
 if SafeValue(object)and(type(object)=='table'or type(object)=='userdata')then
  local low,high=SafeCall(object.GetRange,object)
  if SafeValue(high)then
   low,high=Number(low),Number(high)
   local upper=low and high and math.max(low,high)or high or low
   if upper and upper>=0 then return upper<=30 end
  end
 end
 local near=Bool((SafeCall(CheckInteractDistance,unit,3)));if near==true then return true end
 if CatLearned('Claw')then return Bool((SafeCall(C_Spell and C_Spell.IsSpellInRange,CatID('Claw')or 'Claw',unit)))==true end
 return false
end
local function CatEnemies()
 local action=_G.Action;local count=Number((SafeCall(AL.EnemyCount,30)))
 if action and action.MultiUnits then local n=Number((SafeCall(action.MultiUnits.GetByRangeInCombat,action.MultiUnits,30,5)));if n then count=math.max(count or 0,n)end end
 if count and(count<0 or count>40 or count~=math.floor(count))then count=nil end
 local found,seen=0,{}
 for i=0,40 do
  local unit=i==0 and 'target' or 'nameplate'..i
  if Bool((SafeCall(UnitExists,unit)))==true and Bool((SafeCall(UnitCanAttack,'player',unit)))==true
   and Bool((SafeCall(UnitIsDeadOrGhost,unit)))==false and Bool((SafeCall(UnitAffectingCombat,unit)))==true then
   local guid=SafeCall(UnitGUID,unit)
   if CatWithinArea(unit)and SafeValue(guid) and type(guid)=='string' and not seen[guid]then found=found+1;seen[guid]=true end
  end
 end
 return math.max(count or 0,found)
end
local function CatBuildRotation(s,inCombat,hostile)
 if not inCombat then
  curveFailures,powerMaximumCache={},{}
  CatTalentRank('Improved Shifting Power')
  if not catCostWarm then for _,row in ipairs(M.spells)do CatCost(row[2],0);CatCost(row[2],3)end;catCostWarm=true end
 end
 lastRotation={at=GetTime(),actions={}}
 local form,hp=Form(),HealthPercent('player')
 local cast=SafeCall(UnitCastingInfo,'player');local channel=SafeCall(UnitChannelInfo,'player')
 local tracked=SafeCall(AL.CastingSpell)
 if not SafeValue(tracked)or tracked~=nil and tracked~=''then return nil,'Casting / channeling'end
 if not SafeValue(cast) or not SafeValue(channel)or cast~=nil and cast~=''or channel~=nil and channel~=''then return nil,'Casting / channeling'end
 for _,reader in pairs({UnitCastingDuration,UnitChannelDuration})do local value=SafeCall(reader,'player');if not SafeValue(value)or type(value)=='table'or type(value)=='userdata'then return nil,'Casting / channeling'end end
 if form=='other'then AddAction(nil,'Travel form')
 else
  if not inCombat then
   if form=='caster'then
    if s.buffs and not CatBuff('Mark of the Wild')then CatOffer('Mark of the Wild','buff',nil,0)end
    if s.thorns and not CatBuff('Thorns')then CatOffer('Thorns','buff',nil,0)end
   end
   if s.heal then
    if not CatBuff('Rejuvenation')then CatOffer('Rejuvenation','heal', {HealthGate('player',hp,RULES.healRest,true)},0,nil,form~='caster')end
    CatOffer('Healing Touch','heal up',{HealthGate('player',hp,RULES.healRest,true)},0,nil,form~='caster')
   end
   if s.drink and form=='caster'then AddAction(nil,'Drink',{CatPercentGate(0,RULES.drinkMana,true)})end
  elseif s.heal then
   local threshold=form=='caster'and RULES.healCaster or RULES.healEmergency
   if not CatBuff('Rejuvenation')then CatOffer('Rejuvenation','emergency heal',{HealthGate('player',hp,threshold,true)},0,nil,form~='caster')end
  end
  if hostile then
   local manaLow=CatPercentGate(0,CatSetting(s,'catInnervateMana',10,0,100),true)
   local ttd=CatTTD()
   if inCombat and s.catInnervate and not CatBuff('Innervate')and(not ttd or ttd>=20)then
    CatOffer('Innervate','self mana recovery',{manaLow,PowerGate(3,Power(3),30,true)},0,nil,form~='caster')
   end
   -- AoE branch: Cat has no Swipe. Optional Hurricane deliberately leaves
   -- form and retains mana for the return to Cat; it never starts a tank loop.
   if inCombat and s.aoe and s.catHurricane and CatStationary()and CatEnemies()>=CatSetting(s,'catAoeMinEnemies',3,2,5)then
    local hurricane,shift=CatCost('Hurricane',0),CatCost('Cat Form',0)
    if hurricane and shift then
     CatOffer('Hurricane','AoE: optional caster channel',{
      CatPercentGate(0,CatSetting(s,'catAoeMinMana',50,0,100),false),PowerGate(0,Power(0),hurricane+shift,false)},0,nil,form~='caster')
    end
   end
   if form~='cat'and CatKnown('Cat Form')then
    CatOffer('Cat Form','Feral Cat form',nil,0)
    if form=='caster'then
     if not AL.HasDebuff('target','Moonfire')then CatOffer('Moonfire','caster fallback while recovering mana',nil,0)end
     CatOffer('Wrath','caster fallback while recovering mana',nil,0)
     AddAction(AL.Ok('Attack')and'Attack'or nil,'melee / mana recovery')
    elseif form=='bear'then BearRotation(s)end
   elseif form=='cat'then
    local energy,maximum=Power(3),PowerMaximum(3)
    if s.catShiftingPower and maximum then
     local helm=Number((SafeCall(GetInventoryItemID,'player',1)));local gain=helm and helm~=8345 and 40 or 60
     CatOffer('Shifting Power','recover energy without leaving Cat',{
      PowerGate(3,energy,CatSetting(s,'catShiftBelowEnergy',40,0,100),true,true),PowerGate(3,energy,maximum-gain,true)},0)
    end
    if inCombat and AL.burst and InMelee('Claw')then
     local hpGate=CatSetting(s,'catBurstMinTargetHP',35,0,100)
     local gates={hpGate<=0 or HealthGate('target',HealthPercent('target'),hpGate,false),PowerGate(3,energy,CatSetting(s,'catBurstMinEnergy',30,0,100),false)}
     if s.catBerserk and not CatBuff('Berserk')then CatOffer('Berserk','Burst: Feral builders',gates)end
     if s.catElunesLight and not CatBuff('Berserk')and not CatBuff("Elune's Light")then CatOffer("Elune's Light",'Burst: racial critical chance',gates)end
    end
    local prowl=CatBuff('Prowl')or Bool((SafeCall(IsStealthed)))==true
    if not inCombat and s.catProwl and not prowl then CatOffer('Prowl','stealth preparation')end
    if prowl and not openerBlocked and s.catRavage and InMelee('Ravage')then CatOffer('Ravage','learned stealth opener',nil,3,60)end
    if s.catFaerieFire and not prowl and CatDotLeft('Faerie Fire')<=1 then CatOffer('Faerie Fire','maintain own armor reduction',nil,0)end
    if s.tigersfury and not CatLearned('Shifting Power')and not CatBuff("Tiger's Fury")then CatOffer("Tiger's Fury",'learned early Cat buff',nil,3,30)end
    local cp=CatComboPoints()
    if s.rake and CatDotLeft('Rake')<=0 and InMelee('Rake')then CatOffer('Rake','maintain Rake',nil,3,40)end
    local ripLeft=CatDotLeft('Rip')
    if s.rip and cp>=5 and ripLeft<=0 and(not ttd or ttd>=10)and InMelee('Rip')then CatOffer('Rip','five combo points',nil,3,30)end
    local ripUsable,ripShortage=SpellUsability('Rip')
    local ripUnavailable=s.rip==false or not CatKnown('Rip')or ttd and ttd<10 or ripUsable==false and ripShortage==false
    if s.catBite and cp>=5 and not CatBuff('Clearcasting')and(ripLeft>5 or ripUnavailable)and InMelee('Ferocious Bite')then
     CatOffer('Ferocious Bite','five combo points / Rip protected',nil,3,35)
    end
    if s.catShred and not openerBlocked and InMelee('Shred')then CatOffer('Shred','rear-position builder',nil,3,60)end
    if InMelee('Claw')then CatOffer('Claw','builder / front fallback',nil,3,40)end
    AddAction(AL.Ok('Attack')and 'Attack'or nil,'melee / energy recovery')
   elseif form=='caster'then
    if not AL.HasDebuff('target','Moonfire')then CatOffer('Moonfire','learned caster leveling DoT',nil,0)end
    CatOffer('Wrath','learned caster leveling filler',nil,0)
    AddAction(AL.Ok('Attack')and'Attack'or nil,'melee / mana recovery')
   elseif form=='bear'then BearRotation(s)end
  end
 end
 AddAction(nil,inCombat and not hostile and'No target'or'Ready')
 local base=lastRotation.actions[#lastRotation.actions];lastRotation.baseSpell,lastRotation.baseReason=base.spell,base.reason
 return base.spell,base.reason
end

-- Balance owns its charges, DoTs and cooldowns; it does not require DPS60.lua.
local BALANCE_LEVELS={Wrath=1,Moonfire=4,Starfire=20,['Insect Swarm']=20,
 ['Moonkin Form']=40,Innervate=40,Hurricane=40,Rejuvenation=4,Thorns=6}
local BalanceKnown,_,BalanceLearned=AL.LevelGates(BALANCE_LEVELS)
local balanceRanks={}
for _,row in ipairs(M.spells)do balanceRanks[row[1]]=row[2]end
for name,ids in pairs({Wrath={5176,5177,5178,5179,5180,6780,8905,9912},
 Starfire={2912,8949,8950,8951,9875,9876,25298},
 Moonfire={8921,8924,8925,8926,8927,8928,8929,9833,9834,9835},
 ['Insect Swarm']={5570,24974,24975,24976,24977},Hurricane={16914,17401,17402},
 Berserking={20554,26297}})do for _,id in ipairs(ids)do balanceRanks[id]=name end end
local balanceCDBase={Innervate=360,["Elune's Light"]=180,Berserking=180}
local balanceCDEnds,balanceCastAt,balanceRetry={},{},{}
local balancePending,balanceDone,balanceLastSent={},{},nil
local balanceDots,balanceAuraCache,balanceAuraBlocked={},{},{}
local balanceTalents,balanceWarm,balanceFormAt=nil,false,-math.huge
local balanceFormKnown=false
local balanceEpoch=0
local balanceEclipse={charges=0,expires=0,at=-math.huge}
local balanceNativeEclipse
local function BalanceTalent(name)
 if not balanceTalents then
  balanceTalents={}
  for index=1,40 do
   local talent,_,_,_,rank=SafeCall(GetTalentInfo,1,index,false,false)
   if SafeValue(talent)and type(talent)=='string'and Number(rank)then
    balanceTalents[(AL.englishNames and AL.englishNames[talent])or talent]=rank
    for english,id in pairs({Eclipse=408248,["Nature's Splendor"]=1223083,['Improved Starfire']=16850})do
     local localized=SafeCall(C_Spell and C_Spell.GetSpellName,id)
     if SafeValue(localized)and type(localized)=='string'and localized==talent then balanceTalents[english]=rank end
    end
   end
  end
 end
 if balanceTalents[name]==nil and(name=='Eclipse'or name=="Nature's Splendor")then
  local id=name=='Eclipse'and 408248 or 1223083
  local localized=SafeCall(C_Spell and C_Spell.GetSpellName,id)
  local known=Bool((SafeCall(IsPlayerSpell,id)))==true or Bool((SafeCall(IsSpellKnown,id)))==true
   or Bool((SafeCall(C_SpellBook and C_SpellBook.IsSpellKnown,id,Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player)))==true
   or AL.known[name]==true or SafeValue(localized)and type(localized)=='string'and AL.known[localized]==true
  if known then balanceTalents[name]=1 end -- Presence proves learned, not its maximum rank.
 end
 return balanceTalents[name]
end
local function BalanceTarget()
 local guid=SafeCall(UnitGUID,'target')
 return SafeValue(guid)and type(guid)=='string'and guid or balanceEpoch
end
local function BalanceName(id)
 id=Number(id);if not id then return end
 if balanceRanks[id]then return balanceRanks[id]end
 for _,row in ipairs(M.spells)do if LearnedID(row[2])==id then return row[2]end end
end
local function BalanceAura(unit,name,own)
 local now=GetTime();local cache=balanceAuraCache[unit]
 if not cache or now-cache.at>=0.2 then
  cache={at=now,auras={},complete=false};balanceAuraCache[unit]=cache
  local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not balanceAuraBlocked[unit]and type(reader)=='function'then
   local complete=true
   for index=1,40 do
    local ok,aura=pcall(reader,unit,index,unit=='target'and'HARMFUL'or'HELPFUL')
    if not ok or not SafeValue(aura)then balanceAuraBlocked[unit]=true;break end
    if aura==nil then cache.complete=complete;break end
    if type(aura)=='table'then
     local id,label=Number(aura.spellId),SafeValue(aura.name)and type(aura.name)=='string'and aura.name
     if label then label=(AL.englishNames and AL.englishNames[label])or label end
     local mine=Bool(aura.isFromPlayerOrPlayerPet)
     if mine==nil and SafeValue(aura.sourceUnit)and type(aura.sourceUnit)=='string'then mine=aura.sourceUnit=='player'or aura.sourceUnit=='pet'end
     if id or label then cache.auras[#cache.auras+1]={id=id,name=label,mine=mine,
      expires=Number(aura.expirationTime),duration=Number(aura.duration),
      count=Number(aura.applications),instance=Number(aura.auraInstanceID)}else complete=false end
    else complete=false end
   end
  end
 end
 local unknown=false
 for _,aura in ipairs(cache.auras)do
  if aura.name==name or aura.id and(balanceRanks[aura.id]==name or name=='Eclipse'and aura.id==408255)then
   if not own or aura.mine==true then return true,aura end
   if aura.mine==nil then unknown=true end
  end
 end
 if not unknown and cache.complete then return false end
end
local function BalanceCharges()
 local now=GetTime();local state=balanceEclipse
 if state.expires<=now then state.charges=0 end
 local active,aura=BalanceAura('player','Eclipse')
 if active==false and now-state.at>=0.5 then
  state.charges,state.expires=0,now;balanceNativeEclipse=nil
 elseif active and now-state.at>=0.5 then
  local count=aura.count and math.max(0,math.min(4,math.floor(aura.count)))or 1
  if count==0 then count=1 end -- Positive presence proves one, never four hidden charges.
  local expires=aura.expires and aura.expires>0 and aura.expires or nil
  local old=balanceNativeEclipse
  local fresh=not old or old.count~=count or old.expires~=expires or old.instance~=aura.instance
  if fresh then
   local increased=not old or count>old.count and not expires and not old.expires
    or expires and old.expires and expires>old.expires+0.05
    or aura.instance and old.instance and aura.instance~=old.instance
   if not expires or expires>=state.expires-0.05 or state.expires<=now then
    if increased and(not expires or expires>now)then
     state.charges,state.expires=count,expires or now+15
    elseif state.charges>count then state.charges=count end
    if expires and expires>now and state.charges>0 then state.expires=expires end
   end
   balanceNativeEclipse={count=count,expires=expires,instance=aura.instance}
  end
 end
 return state.expires>now and state.charges or 0
end
local function BalanceDotLeft(name)
 local now=GetTime();local state=balanceDots[name]
 if state and state.target==BalanceTarget()and now-state.at<0.5 then return math.max(0,state.expires-now)end
 local active,aura=BalanceAura('target',name,true)
 if active==false then return 0 end
 if active then
  if aura.expires and aura.expires>0 then return math.max(0,aura.expires-now)end
  return state and state.target==BalanceTarget()and math.max(0,state.expires-now)or math.huge
 end
 if state and state.target==BalanceTarget()then return math.max(0,state.expires-now)end
 return 0
end
local function BalanceReady(name)
 if not BalanceKnown(name)or(balanceRetry[name]or 0)>GetTime()then return false end
 local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,CatID(name)or name)
 if SafeValue(info)and type(info)=='table'and Bool(info.isEnabled)==false then return false end
 if not balanceCDBase[name]then return AL.IsReady(name)end
 if SafeValue(info)and type(info)=='table'then
  if Bool(info.isEnabled)==false then return false end
  local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate)
  if SafeValue(info.modRate)and info.modRate==nil then rate=1 end
  local ready
  if start and start>=0 and duration and duration>=0 and rate and rate>0 then
   if start>0 and duration>0 and duration<=1.5 and(balanceCDEnds[name]or 0)>GetTime()then return false end
   ready=start==0 or duration<=1.5 or start+duration/rate<=GetTime()
  elseif Bool(info.isActive)==false then ready=true
  elseif Bool(info.isActive)==true and Bool(info.isOnGCD)==false then ready=false end
  if ready~=nil then
   if ready and balanceCastAt[name]and GetTime()-balanceCastAt[name]<0.5 and(balanceCDEnds[name]or 0)>GetTime()then return false end
   if ready and balanceCDEnds[name]then balanceCDEnds[name]=GetTime()end
   return ready
  end
 end
 return not balanceCDEnds[name]or balanceCDEnds[name]<=GetTime()
end
local function BalanceGates(gates,...)
 local result={};for _,gate in ipairs(gates or {})do result[#result+1]=gate end
 for i=1,select('#',...)do result[#result+1]=select(i,...)end
 return result
end
local function BalanceOffer(name,reason,gates,shifting)
 if not BalanceReady(name)then return false end
 if Bool((SafeCall(AL.InRange,name)))==false then return false end
 local usable,shortage=SpellUsability(name)
 if shortage==true or usable==false and not shifting then return false end
 local cost=CatCost(name,0);local gate
 if cost then
  gate=PowerGate(0,Power(0),cost,false)
  if Power(0)==nil and(not PowerMaximum(0)or not CurveAvailable('power','player',0))then gate=usable==true end
 else gate=usable==true end
 return AddAction(name,reason,BalanceGates(gates,gate))
end
local function BalanceMoving()
 local speed=Number((SafeCall(GetUnitSpeed,'player')))
 if speed~=nil then return speed>0 end
 local player=_G.Action and _G.Action.Player
 if type(player)=='table'then return Bool((SafeCall(player.IsMoving,player)))==true end
 return false
end
local function BalanceMoonkin()
 local index=Number((SafeCall(GetShapeshiftForm)))
 if index and index>=0 then
  if index>0 then local _,_,_,id=SafeCall(GetShapeshiftFormInfo,index)
   if Number(id)then balanceFormKnown=id==24858;return balanceFormKnown end
  elseif GetTime()-balanceFormAt>=0.5 then balanceFormKnown=false;return false end
 end
 if GetTime()-balanceFormAt<0.5 then return true end
 local active=BalanceAura('player','Moonkin Form')
 if active~=nil then balanceFormKnown=active;return active end
 return balanceFormKnown or Bool((SafeCall(AL.HasBuff,'player','Moonkin Form')))==true
end
local function BalanceEnemies()
 local count=0;local units=_G.Action and _G.Action.MultiUnits
 local native=units and Number((SafeCall(units.GetByRangeInCombat,units,30,5)))
 if native and native>=0 and native<=40 and native==math.floor(native)then count=native end
 local seen,visible={},0
 local function Count(unit)
  if not SafeValue(unit)or type(unit)~='string'then return end
  if Bool((SafeCall(UnitExists,unit)))~=true or Bool((SafeCall(UnitCanAttack,'player',unit)))~=true
   or Bool((SafeCall(UnitIsDeadOrGhost,unit)))~=false or Bool((SafeCall(UnitAffectingCombat,unit)))~=true then return end
  local guid=SafeCall(UnitGUID,unit)
  if not SafeValue(guid)or type(guid)~='string'or seen[guid]then return end
  local inRange=unit=='target'and Bool((SafeCall(AL.InRange,'Wrath')))
   or Bool((SafeCall(C_Spell and C_Spell.IsSpellInRange,CatID('Wrath')or'Wrath',unit)))
  if inRange~=true then return end
  seen[guid],visible=true,visible+1
 end
 Count('target')
 local plates=SafeCall(C_NamePlate and C_NamePlate.GetNamePlates)
 if SafeValue(plates)and type(plates)=='table'then for _,plate in pairs(plates)do
  if SafeValue(plate)and type(plate)=='table'then Count(plate.namePlateUnitToken or(plate.UnitFrame and plate.UnitFrame.unit))end
 end end
 return math.max(count,visible)
end
local function BalanceStarfireTime(charges)
 local info=SafeCall(C_Spell and C_Spell.GetSpellInfo,CatID('Starfire')or'Starfire')
 local value=SafeValue(info)and type(info)=='table'and Number(info.castTime)
 if value and value>0 then return value/1000 end
 local rank=BalanceTalent('Improved Starfire')or 0
 local eclipse=charges>0 and BalanceTalent('Eclipse')or 0
 return math.max(1,3.5-math.min(5,rank)*0.1-(({[1]=0.17,[2]=0.33,[3]=0.5})[eclipse or 0]or 0))
end
local balanceTracker=CreateFrame('Frame')
for _,event in ipairs({'UNIT_SPELLCAST_SENT','UNIT_SPELLCAST_SUCCEEDED','UNIT_SPELLCAST_FAILED',
 'UNIT_SPELLCAST_FAILED_QUIET','UNIT_SPELLCAST_INTERRUPTED','UNIT_AURA','PLAYER_TARGET_CHANGED',
 'PLAYER_ENTERING_WORLD','PLAYER_DEAD','SPELLS_CHANGED','PLAYER_TALENT_UPDATE','PLAYER_REGEN_ENABLED',
 'UPDATE_SHAPESHIFT_FORM','COMBAT_LOG_EVENT_UNFILTERED'})do pcall(balanceTracker.RegisterEvent,balanceTracker,event)end
balanceTracker:SetScript('OnEvent',function(_,event,unit,a2,a3,a4)
 if AL.playerClass~='DRUID'then return end
 if event=='PLAYER_TARGET_CHANGED'then
  balanceEpoch=balanceEpoch+1;balanceDots={};balanceAuraCache.target=nil;balanceAuraBlocked.target=nil;return
 end
 if event=='PLAYER_DEAD'or event=='PLAYER_ENTERING_WORLD'then
  balancePending,balanceDone,balanceLastSent,balanceRetry={},{},nil,{}
  balanceDots,balanceAuraCache,balanceAuraBlocked={},{},{}
  balanceEclipse={charges=0,expires=0,at=-math.huge};balanceNativeEclipse=nil;balanceFormAt=-math.huge;balanceFormKnown=false;return
 end
 if event=='SPELLS_CHANGED'or event=='PLAYER_TALENT_UPDATE'or event=='PLAYER_REGEN_ENABLED'then
  balanceTalents=nil;balanceWarm=false;balanceAuraCache,balanceAuraBlocked={},{}
  if event=='PLAYER_TALENT_UPDATE'then balanceEclipse={charges=0,expires=0,at=-math.huge};balanceNativeEclipse=nil end
  return
 end
 if event=='UNIT_AURA'then if SafeValue(unit)and type(unit)=='string'then balanceAuraCache[unit]=nil end;return end
 if event=='UPDATE_SHAPESHIFT_FORM'then balanceAuraCache.player=nil;BalanceMoonkin();return end
 if event=='COMBAT_LOG_EVENT_UNFILTERED'then
  local _,subevent,_,source,_,_,_,dest,_,_,_,id=SafeCall(CombatLogGetCurrentEventInfo)
  local player=SafeCall(UnitGUID,'player');local name=BalanceName(id)
  local state=name and balanceDots[name]
  if SafeValue(subevent)and subevent=='SPELL_MISSED'and SafeValue(source)and SafeValue(player)
   and type(player)=='string'and source==player and SafeValue(dest)and dest==BalanceTarget()
   and state and GetTime()-state.at<=1.5 then balanceDots[name]=nil;balanceAuraCache.target=nil end
  return
 end
 if not SafeValue(unit)or unit~='player'then return end
 local now=GetTime()
 for guid,at in pairs(balanceDone)do if now-at>900 then balanceDone[guid]=nil end end
 for guid,sent in pairs(balancePending)do if now-sent.at>30 then balancePending[guid]=nil end end
 local guid=CatGUID(event=='UNIT_SPELLCAST_SENT'and a3 or a2)
 local id=Number(a4)or Number(a3);local name=BalanceName(id)
 if event=='UNIT_SPELLCAST_SENT'then
  if not id and M.CanTrackSuggestedSpell(AL.lastSuggestion)then name=AL.lastSuggestion end
  local target=BalanceTarget();local label=SafeValue(a2)and type(a2)=='string'and a2
  local targetName,realm=SafeCall(UnitName,'target')
  if label and label~=''and SafeValue(targetName)and type(targetName)=='string'then
   local full=SafeValue(realm)and type(realm)=='string'and realm~=''and targetName..'-'..realm or targetName
   if label~=targetName and label~=full then target=nil end
  end
  balanceLastSent={name=name,id=id,at=now,guid=guid,target=target}
  if guid then balancePending[guid]=balanceLastSent end;return
 end
 local sent=guid and balancePending[guid]or not guid and balanceLastSent
 if event~='UNIT_SPELLCAST_SUCCEEDED'then
  if sent and not sent.done then sent.failed=true;if sent.name then balanceRetry[sent.name]=now+0.5 end end
  if guid then balanceDone[guid]=now end;return
 end
 if guid and balanceDone[guid]or sent and(sent.failed or sent.done)then return end
 if not name and not id and sent and now-sent.at<=15 then name=sent.name end
 if not name then return end
 if sent then sent.done=true end;if guid then balanceDone[guid]=now end
 if balanceCDBase[name]then
  local ends=CatCooldownEnd(name)
  balanceCDEnds[name],balanceCastAt[name]=ends or now+balanceCDBase[name],now
 end
 balanceRetry[name]=nil
 if name=='Moonkin Form'then balanceFormAt=now;balanceFormKnown=true
 elseif name=='Cat Form'or name=='Bear Form'or name=='Dire Bear Form'then balanceFormKnown=false end
 if name=='Wrath'and(BalanceTalent('Eclipse')or 0)>0 then
  local charges=BalanceCharges();balanceEclipse={charges=math.min(4,charges+2),expires=now+15,at=now}
 elseif name=='Starfire'then
  local charges=BalanceCharges();balanceEclipse.charges=math.max(0,charges-1);balanceEclipse.at=now
 end
 if(name=='Moonfire'or name=='Insect Swarm')and(not sent or sent.target==BalanceTarget())then
  local extra=(BalanceTalent("Nature's Splendor")or 0)>0 and(name=='Moonfire'and 3 or 2)or 0
  local rankID=id or sent and sent.id or LearnedID(name)
  local duration=name=='Moonfire'and rankID==8921 and 9 or 12
  balanceDots[name]={at=now,expires=now+duration+extra,target=BalanceTarget()};balanceAuraCache.target=nil
 end
end)
local function BalanceBuildRotation(s,inCombat,hostile)
 if not inCombat then
  curveFailures,powerMaximumCache={},{}
  BalanceTalent('Eclipse')
  if not balanceWarm then for _,row in ipairs(M.spells)do CatCost(row[2],0)end;balanceWarm=true end
 end
 lastRotation={at=GetTime(),actions={}}
 local form,hp,moving=Form(),HealthPercent('player'),BalanceMoving()
 local moonkin=BalanceMoonkin()
 local cast,channel=SafeCall(UnitCastingInfo,'player'),SafeCall(UnitChannelInfo,'player')
 local tracked=SafeCall(AL.CastingSpell)
 local casting=not SafeValue(tracked)or tracked~=nil and tracked~=''
  or not SafeValue(cast)or not SafeValue(channel)or cast~=nil and cast~=''or channel~=nil and channel~=''
 for _,reader in pairs({UnitCastingDuration,UnitChannelDuration})do local value=SafeCall(reader,'player')
  if not SafeValue(value)or type(value)=='table'or type(value)=='userdata'then casting=true end
 end
 if casting then AddAction(nil,'Casting / channeling')
 elseif form=='other'and not moonkin then AddAction(nil,'Travel form')
 else
  if not inCombat then
   if form=='caster'then
    if s.buffs and not CatBuff('Mark of the Wild')then BalanceOffer('Mark of the Wild','buff')end
    if s.thorns and not CatBuff('Thorns')then BalanceOffer('Thorns','buff')end
   end
   if s.heal then
    if not CatBuff('Rejuvenation')then BalanceOffer('Rejuvenation','heal',{
     HealthGate('player',hp,RULES.healRest,true)},moonkin or form~='caster')end
    if not moving then BalanceOffer('Healing Touch','heal up',{
     HealthGate('player',hp,RULES.healRest,true)},moonkin or form~='caster')end
   end
   if s.drink and form=='caster'then AddAction(nil,'Drink',{CatPercentGate(0,RULES.drinkMana,true)})end
  elseif s.heal and not CatBuff('Rejuvenation')then
   BalanceOffer('Rejuvenation','emergency heal',{HealthGate('player',hp,
    (moonkin or form~='caster')and RULES.healEmergency or RULES.healCaster,true)},moonkin or form~='caster')
  end
  if hostile then
   local ttd=CatTTD()
   if inCombat and s.balanceInnervate and not CatBuff('Innervate')and(not ttd or ttd>20)then
    BalanceOffer('Innervate','self mana recovery',{
     CatPercentGate(0,CatSetting(s,'balanceInnervateMana',10,0,100),true)})
   end
   if s.balanceMoonkin and not moonkin then BalanceOffer('Moonkin Form','Balance form')end
   if form=='caster'or moonkin then
    local charges=BalanceCharges();local castTime=BalanceStarfireTime(charges)
    local mana=CatPercentGate(0,CatSetting(s,'balanceMinMana',0,0,100),false)
    local dotMinimum=CatSetting(s,'balanceDotMinTargetHP',0,0,100)
    local dotGates={mana,dotMinimum<=0 or HealthGate('target',HealthPercent('target'),dotMinimum,false)}
    local insectLeft,moonLeft=BalanceDotLeft('Insect Swarm'),BalanceDotLeft('Moonfire')
    local insect=s.balanceInsectSwarm and(not ttd or ttd>10)
    local moon=s.balanceMoonfire and(not ttd or ttd>6)
    -- Burst only accompanies a usable learned damage opportunity. Per-spell
    -- affordability stays in each row so an opaque primary cannot hide a cheaper one.
    if inCombat and AL.burst then
     local burstHP=CatSetting(s,'balanceBurstMinTargetHP',35,0,100)
     local burstGates={CatPercentGate(0,CatSetting(s,'balanceBurstMinMana',20,0,100),false),
      burstHP<=0 or HealthGate('target',HealthPercent('target'),burstHP,false),mana}
     for _,entry in ipairs({{'Starfire',s.balanceStarfire and not moving},
      {'Wrath',s.balanceWrath and not moving},{'Insect Swarm',insect and insectLeft<=0},
      {'Moonfire',moon and moonLeft<=0}})do
      local name=entry[1]
      if entry[2]and BalanceReady(name)and Bool((SafeCall(AL.InRange,name)))~=false then
       local usable,shortage=SpellUsability(name);local cost=CatCost(name,0)
       if usable~=false and shortage~=true then
        local affordable
        if cost~=nil then affordable=PowerGate(0,Power(0),cost,false)else affordable=usable==true end
        local gates=BalanceGates(burstGates,affordable)
        if name=='Moonfire'or name=='Insect Swarm'then gates=BalanceGates(gates,dotGates[2])end
        if s.balanceElunesLight and not CatBuff("Elune's Light")then BalanceOffer("Elune's Light",'Burst: racial critical chance',gates)end
        if s.balanceBerserking and not CatBuff('Berserking')then BalanceOffer('Berserking','Burst: learned racial haste',gates)end
       end
      end
     end
    end
    local minimum=CatSetting(s,'balanceAoeMinEnemies',3,2,5)
    local enemies=inCombat and s.aoe and s.balanceHurricane and not moving and BalanceEnemies()or 0
    local aoeGates={mana,CatPercentGate(0,CatSetting(s,'balanceAoeMinMana',35,0,100),false)}
    if not inCombat and not moving then
     if s.balanceStarfire then BalanceOffer('Starfire','Balance ranged opener',{mana})end
     if s.balanceWrath then BalanceOffer('Wrath','learned ranged opener',{mana})end
    end
    if enemies>=math.max(4,minimum)then BalanceOffer('Hurricane','AoE: large engaged pack',aoeGates)end
    if insect and insectLeft<=0 then BalanceOffer('Insect Swarm','maintain own Insect Swarm',dotGates)end
    if moon and moonLeft<=0 then BalanceOffer('Moonfire','maintain own Moonfire',dotGates)end
    if not moving then
     if s.balanceWrath and ttd and ttd<castTime then BalanceOffer('Wrath','short remaining lifetime', {mana})end
     if s.balanceWrath and charges<=2 and((BalanceTalent('Eclipse')or 0)>0 or charges>0)
      and(insect and insectLeft>0 and insectLeft<castTime or moon and moonLeft>0 and moonLeft<castTime)then
      BalanceOffer('Wrath','bank Eclipse before DoT renewal',dotGates)
     end
     if enemies>=minimum then BalanceOffer('Hurricane','AoE: engaged enemies',aoeGates)end
     if s.balanceStarfire and(charges>0 or BalanceTalent('Eclipse')==0 or not s.balanceWrath
      or not BalanceLearned('Wrath'))then BalanceOffer('Starfire','spend Eclipse / learned fallback',{mana})end
     if s.balanceWrath then BalanceOffer('Wrath','build Eclipse / learned filler',{mana})end
     if s.balanceStarfire then BalanceOffer('Starfire','learned affordable fallback',{mana})end
    end
   end
  end
 end
 AddAction(nil,inCombat and not hostile and'No target'or'Ready / mana recovery')
 local base=lastRotation.actions[#lastRotation.actions];lastRotation.baseSpell,lastRotation.baseReason=base.spell,base.reason
 return base.spell,base.reason
end

-- Feral Bear 0/41/10. This state is private to the selected Tank build.
local B={cd={},castAt={},durations={},retry={},buffs={},dots={},pending={},done={},epoch=0,
 formAt=-math.huge,maulAt=-math.huge,maulWindow=2.8}
B.levels={['Bear Form']=10,['Dire Bear Form']=40,Maul=10,Growl=10,Enrage=12,Bash=14,
 ['Demoralizing Roar']=10,Swipe=16,['Faerie Fire']=18,['Feral Charge']=20,
 ['Primal Bite']=25,['Challenging Roar']=28,['Frenzied Regeneration']=36,
 Berserk=40,Lacerate=42,Barkskin=44,Rejuvenation=4,Thorns=6}
B.ok,B.levelReady,B.learned=AL.LevelGates(B.levels)
B.base={['Primal Bite']=6,Growl=8,Bash=60,Enrage=60,['Feral Charge']=15,
 ['Challenging Roar']=600,['Frenzied Regeneration']=180,Barkskin=60,
 Berserk=180,["Elune's Light"]=180,Berserking=180}
B.buffDuration={Barkskin=15,['Frenzied Regeneration']=10,Enrage=10,Berserk=15,
 ["Elune's Light"]=15,Berserking=10,Rejuvenation=12,['Mark of the Wild']=1800,Thorns=600}
B.dotDuration={Lacerate=15,['Demoralizing Roar']=30,['Faerie Fire']=40}
B.ranks={}
for name,ids in pairs({['Primal Bite']={407995,1238069,1238070,1238073},
 Lacerate={414644,1235826,1235827},Maul={6807,6808,6809,8972,9745,9880,9881},
 Swipe={779,780,769,9754,9908},Bash={5211,6798,8983},['Demoralizing Roar']={99,1735,9490,9747,9898},
 ['Faerie Fire']={770,778,9749,9907},['Bear Form']={5487},['Dire Bear Form']={9634},Growl={6795},
 ['Feral Charge']={1238122},['Challenging Roar']={5209},['Frenzied Regeneration']={22842},
 Barkskin={22812},Enrage={5229},Berserk={417141},["Elune's Light"]={1259799},Berserking={20554,26297},
 Rejuvenation={774,1058,1430,2090,2091,3627,8910,9839,9840,9841,25299},
 ['Mark of the Wild']={1126,5232,6756,5234,8907,9884,9885},Thorns={467,782,1075,8914,9756,9910}})do
 for _,id in ipairs(ids)do B.ranks[id]=name;balanceRanks[id]=name end
end
B.bounds={bearBarkskinHP={45,0,100},bearFrenziedHP={35,0,100},bearFrenziedRage={10,0,100},
 bearEnrageBelowRage={20,0,100},bearEnrageMinHP={75,0,100},bearMaulRage={25,0,100},
 bearLacerateStacks={5,1,5},bearAoeMinEnemies={3,2,5},bearBurstMinTargetHP={35,0,100}}
function M.BearSetting(s,key)
 local limits=B.bounds[key]
 if limits then return CatSetting(s,key,limits[1],limits[2],limits[3])end
end
function B.minRage(rage,threshold)
 return threshold<=0 or PowerGate(1,rage,threshold,false)
end
function B.form()
 local form=Form()
 local index=Number((SafeCall(GetShapeshiftForm)))
 local kind=Number((SafeCall(UnitPowerType,'player')))
 local id
 if index and index>0 then local _,_,_,value=SafeCall(GetShapeshiftFormInfo,index);id=Number(value)end
 if id and id~=5487 and id~=9634 then
  B.confirmedForm=false;return id==768 and'cat'or id==24858 and'caster'or'other'
 end
 if index==0 or kind==0 or kind==3 then
  if GetTime()-B.formAt>=0.5 then B.confirmedForm=false end
  return form
 end
 if form=='bear'then B.confirmedForm=true;return form end
 if B.confirmedForm and kind==nil then return'bear'end
 return form
end
function M.SelectBuild(key, enabled, s)
 return M.SetBuild(key, enabled, s)
end
function B.name(id)
 id=Number(id);if not id then return end
 if B.ranks[id]then return B.ranks[id]end
 -- Only the actual learned cast ID can supplement the explicit rank list.
 for _,entry in ipairs(M.spells)do
  if(B.base[entry[2]]or B.buffDuration[entry[2]]or B.dotDuration[entry[2]]or entry[2]=='Maul')
   and LearnedID(entry[2])==id then return entry[2]end
 end
end
function B.target()local guid=SafeCall(UnitGUID,'target');return SafeValue(guid)and type(guid)=='string'and guid or B.epoch end
function B.buff(name)
 local state,now=B.buffs[name],GetTime()
 if state and now-state.at<0.5 then return state.expires>now end
 local active,aura=BalanceAura('player',name)
 if active~=nil then
  if not active then B.buffs[name]=nil;return false end
  if aura.expires and aura.expires>0 then B.buffs[name]={at=now,expires=aura.expires}end
  return true
 end
 if state then return state.expires>now end
 return Bool((SafeCall(AL.HasBuff,'player',name)))==true
end
function B.dot(name)
 local state,now=B.dots[name],GetTime()
 if state and state.target~=B.target()then state=nil end
 if state and now-state.at<0.5 then return math.max(0,state.expires-now),state.stacks end
 local active,aura=BalanceAura('target',name,name=='Lacerate')
 if active==false then B.dots[name]=nil;return 0,0 end
 if active then
  local count=aura.count and aura.count>0 and math.min(5,math.floor(aura.count))or state and state.stacks or 1
  local expires=aura.expires and aura.expires>0 and aura.expires or state and state.expires
  if expires then B.dots[name]={target=B.target(),at=now,expires=expires,stacks=count};return math.max(0,expires-now),count end
  return math.huge,count
 end
 if state then return math.max(0,state.expires-now),state.expires>now and state.stacks or 0 end
 return 0,0
end
function B.talent(name)
 local rank=CatTalentRank(name)
 if rank~=nil then return rank end
 local id=({Ferocity=16934,['Shredding Attacks']=16968,['Brutal Impact']=16940})[name]
 local localized=id and SafeCall(C_Spell and C_Spell.GetSpellName,id)
 if SafeValue(localized)and type(localized)=='string'then return CatTalentRank(localized)end
end
function B.fallback(name)
 if B.durations[name]then return B.durations[name]end
 if name=='Bash'then
  local rank=B.talent('Brutal Impact')
  if rank and rank>=0 and rank<=2 then return 60-15*rank end
 end
 return B.base[name]
end
function B.ready(name)
 if not B.ok(name)or B.retry[name]and B.retry[name]>GetTime()then return false end
 local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,CatID(name)or name)
 if SafeValue(info)and type(info)=='table'then
  if Bool(info.isEnabled)==false then return false end
  local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate)
  if SafeValue(info.modRate)and info.modRate==nil then rate=1 end
  local ready
  if start and start>=0 and duration and duration>=0 and rate and rate>0 then
   ready=start==0 or duration<=1.5 or start+duration/rate<=GetTime()
  elseif Bool(info.isActive)==false then ready=true
  elseif Bool(info.isActive)==true and Bool(info.isOnGCD)==false then ready=false end
  if ready~=nil then
   if ready and B.castAt[name]and GetTime()-B.castAt[name]<0.5 and B.cd[name]and B.cd[name]>GetTime()then return false end
   if start and start>0 and duration and duration>1.5 and rate and rate>0 then
    B.durations[name]=duration/rate;B.cd[name]=start+duration/rate
   end
   -- Berserk resets Primal Bite's spell cooldown, not the global cooldown.
   if name=='Primal Bite'and B.buff('Berserk')then return true end
   return ready
  end
 end
 if name=='Primal Bite'and B.buff('Berserk')then return true end
 if B.base[name]then return not B.cd[name]or B.cd[name]<=GetTime()end
 return AL.IsReady(name)
end
function B.cost(name,kind,base)
 local fallback=base
 if kind==1 and base then
  local rank=B.talent(name=='Lacerate'and'Shredding Attacks'or'Ferocity')
  if rank and rank>=0 and rank<=(name=='Lacerate'and 3 or 5)and(name=='Lacerate'or name=='Maul'or name=='Swipe'or name=='Primal Bite')then fallback=math.max(0,base-rank)end
 end
 return CatCost(name,kind,fallback)
end
function B.offer(name,reason,gates,kind,base,shifting)
 if not B.ready(name)then return false end
 local usable,shortage=SpellUsability(name)
 if shortage==true or usable==false and not shifting then return false end
 local conditions={};for _,gate in ipairs(gates or {})do conditions[#conditions+1]=gate end
 if kind then
  local amount,cost=Power(kind),B.cost(name,kind,base)
  if cost then
   local gate=PowerGate(kind,amount,cost,false)
   if amount==nil and(not PowerMaximum(kind)or not CurveAvailable('power','player',kind))then gate=usable==true end
   conditions[#conditions+1]=gate
  elseif usable~=true then return false end
 end
 return AddAction(name,reason,conditions)
end
function B.melee(unit)
 unit=unit or'target'
 local value=SafeCall(C_Spell and C_Spell.IsSpellInRange,LearnedID('Maul')or'Maul',unit)
 if SafeValue(value)and(value==true or value==1)then return true end
 if SafeValue(value)and(value==false or value==0)then return false end
 if unit=='target'then local v=Bool((SafeCall(AL.InRange,'Maul')));if v~=nil then return v end end
 local squared,checked=SafeCall(UnitDistanceSquared,unit);squared=Number(squared)
 if squared and squared>=0 and Bool(checked)~=false then return squared<=25 end
 local action=_G.Action;local object=action and SafeCall(action.Unit,unit)
 if SafeValue(object)and(type(object)=='table'or type(object)=='userdata')then
  local low,high=SafeCall(object.GetRange,object)
  if SafeValue(high)then
   low,high=Number(low),Number(high)
   local upper=low and high and math.max(low,high)or high
   if upper and upper>=0 then return upper<=5 end
  end
 end
 return false
end
function B.needsTaunt(unit)
 unit=(unit or'target')..'target'
 if Bool((SafeCall(UnitExists,unit)))~=true then return false end
 if Bool((SafeCall(UnitIsUnit,unit,'player')))~=false then return false end
 return Bool((SafeCall(UnitIsFriend,'player',unit)))==true
end
function B.enemies()
 local seen,count,loose={},0,0
 for index=0,40 do
  local unit=index==0 and'target'or'nameplate'..index
  if Bool((SafeCall(UnitExists,unit)))==true and Bool((SafeCall(UnitCanAttack,'player',unit)))==true
   and Bool((SafeCall(UnitIsDeadOrGhost,unit)))==false and Bool((SafeCall(UnitAffectingCombat,unit)))==true and B.melee(unit)then
   local guid=SafeCall(UnitGUID,unit)
   if SafeValue(guid)and type(guid)=='string'and not seen[guid]then
    seen[guid]=true;count=count+1;if B.needsTaunt(unit)then loose=loose+1 end
   end
  end
 end
 return count,loose
end
function B.maulQueued()
 local readable=false
 for _,reader in pairs({IsCurrentSpell,C_Spell and C_Spell.IsCurrentSpell})do
  local value=SafeCall(reader,LearnedID('Maul')or'Maul')
  if Bool(value)==true then return true end
  if Bool(value)==false then readable=true end
 end
 local age=GetTime()-B.maulAt
 if age<0.3 then return true end
 if readable then B.maulAt=-math.huge;return false end
 return age<B.maulWindow
end
local bearTracker=CreateFrame('Frame')
for _,event in ipairs({'UNIT_SPELLCAST_SENT','UNIT_SPELLCAST_SUCCEEDED','UNIT_SPELLCAST_FAILED',
 'UNIT_SPELLCAST_FAILED_QUIET','UNIT_SPELLCAST_INTERRUPTED','PLAYER_TARGET_CHANGED','PLAYER_ENTERING_WORLD',
 'PLAYER_DEAD','SPELLS_CHANGED','PLAYER_TALENT_UPDATE','PLAYER_REGEN_ENABLED','COMBAT_LOG_EVENT_UNFILTERED'})do
 pcall(bearTracker.RegisterEvent,bearTracker,event)
end
bearTracker:SetScript('OnEvent',function(_,event,unit,a2,a3,a4)
 if AL.playerClass~='DRUID'then return end
 local now=GetTime()
 if event=='PLAYER_TARGET_CHANGED'then B.epoch=B.epoch+1;B.dots={};return end
 if event=='PLAYER_ENTERING_WORLD'or event=='PLAYER_DEAD'then
  B.pending,B.done,B.lastSent,B.retry={},{},nil,{};B.dots={};B.formAt=-math.huge;B.maulAt=-math.huge
  B.confirmedForm=false
  if event=='PLAYER_DEAD'then B.buffs={}end;return
 end
 if event=='SPELLS_CHANGED'or event=='PLAYER_TALENT_UPDATE'then B.durations={};return end
 if event=='PLAYER_REGEN_ENABLED'then return end
 if event=='COMBAT_LOG_EVENT_UNFILTERED'then
  local _,subevent,_,source,_,_,_,dest,_,_,_,id=SafeCall(CombatLogGetCurrentEventInfo)
  local player=SafeCall(UnitGUID,'player');local name=B.name(id)
  if SafeValue(source)and SafeValue(player)and source==player and SafeValue(dest)and dest==B.target()
   and SafeValue(subevent)and B.dotDuration[name]and(subevent=='SPELL_MISSED'or subevent=='SPELL_AURA_REMOVED')then
   B.dots[name]=nil;balanceAuraCache.target=nil
  end
  return
 end
 if not SafeValue(unit)or unit~='player'then return end
 for guid,entry in pairs(B.pending)do if now-entry.at>10 then B.pending[guid]=nil end end
 for guid,at in pairs(B.done)do if now-at>30 then B.done[guid]=nil end end
 local sentEvent=event=='UNIT_SPELLCAST_SENT'
 local guid=CatGUID(sentEvent and a3 or a2)
 local id=Number(sentEvent and a4 or a3)or(not sentEvent and Number(a4))
 local name=B.name(id)
 if not sentEvent and event=='UNIT_SPELLCAST_SUCCEEDED'and id
  and({[768]=true,[783]=true,[1066]=true,[24858]=true,[33943]=true,[40120]=true})[id]then B.confirmedForm=false end
 if sentEvent then
  if not name and not id and not(lastRotation and lastRotation.visualCandidate)then
   local suggestion=AL.lastSuggestion
   if SafeValue(suggestion)and type(suggestion)=='string'and M.CanTrackSuggestedSpell(suggestion)then
    for _,label in pairs(B.ranks)do if label==suggestion then name=suggestion;break end end
   end
  end
  local target=B.target();local targetName,realm=SafeCall(UnitName,'target')
  if SafeValue(a2)and type(a2)=='string'and a2~=''and SafeValue(targetName)and type(targetName)=='string'then
   local full=SafeValue(realm)and type(realm)=='string'and realm~=''and targetName..'-'..realm or targetName
   if a2~=targetName and a2~=full then target=nil end
  end
  local entry={name=name,at=now,guid=guid,target=target}
  if name=='Lacerate'then local _,stacks=B.dot(name);entry.stacks=stacks end
  B.lastSent=entry;if guid then B.pending[guid]=entry end
  if name=='Maul'then B.maulAt=now end
  return
 end
 local sent=guid and B.pending[guid]or not guid and B.lastSent
 if event~='UNIT_SPELLCAST_SUCCEEDED'then
  if sent and not sent.done then
   sent.failed=true;if sent.name then B.retry[sent.name]=now+1 end
   if sent.name=='Maul'then B.maulAt=-math.huge end
  end
  if guid and not(sent and sent.done)then B.done[guid]=now end;return
 end
 if guid and B.done[guid]or sent and(sent.done or sent.failed)then return end
 if not id and sent and now-sent.at<=5 then name=sent.name end
 if not name or sent and sent.name and sent.name~=name then return end
 if sent then sent.done=true end;if guid then B.done[guid]=now end
 B.retry[name]=nil
 if name=='Primal Bite'and B.buff('Berserk')then B.castAt[name]=now;B.cd[name]=now
 elseif B.base[name]then
  local fallback=B.fallback(name);B.castAt[name]=now
  local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,CatID(name)or name)
  if SafeValue(info)and type(info)=='table'then
   local start,duration,rate=Number(info.startTime),Number(info.duration),Number(info.modRate)
   if SafeValue(info.modRate)and info.modRate==nil then rate=1 end
   if start and start>0 and duration and duration>1.5 and rate and rate>0 then
    B.durations[name]=duration/rate;B.cd[name]=start+duration/rate
   else B.cd[name]=now+fallback end
  else B.cd[name]=now+fallback end
 end
 if B.buffDuration[name]then B.buffs[name]={at=now,expires=now+B.buffDuration[name]};balanceAuraCache.player=nil end
 if name=='Bear Form'or name=='Dire Bear Form'then B.formAt=now;B.confirmedForm=true end
 if name=='Maul'then B.maulAt=now end
 if B.dotDuration[name]and sent and sent.target==B.target()then
  local stacks=sent.stacks or 0
  B.dots[name]={at=now,target=B.target(),expires=now+B.dotDuration[name],stacks=name=='Lacerate'and math.min(5,(stacks or 0)+1)or 1}
  balanceAuraCache.target=nil
 end
end)
function B.rotation(s,inCombat,hostile)
 if not inCombat then
  curveFailures,powerMaximumCache={},{}
  B.talent('Ferocity');B.talent('Shredding Attacks');B.talent('Brutal Impact')
  local speed=Number((SafeCall(UnitAttackSpeed,'player')));if speed and speed>0 and speed<10 then B.maulWindow=speed+0.3 end
  for _,entry in ipairs(M.spells)do if B.ranks[entry[1]]then B.cost(entry[2],0);B.cost(entry[2],1)end end
 end
 local cast,channel,tracked=SafeCall(UnitCastingInfo,'player'),SafeCall(UnitChannelInfo,'player'),SafeCall(AL.CastingSpell)
 if not SafeValue(cast)or not SafeValue(channel)or not SafeValue(tracked)
  or cast~=nil and cast~=''or channel~=nil and channel~=''or tracked~=nil and tracked~=''then return nil,'Casting / channeling'end
 for _,reader in pairs({UnitCastingDuration,UnitChannelDuration})do
  local value=SafeCall(reader,'player');if not SafeValue(value)or type(value)=='table'or type(value)=='userdata'then return nil,'Casting / channeling'end
 end
 lastRotation={at=GetTime(),actions={}}
 local form,hp,rage=B.form(),HealthPercent('player'),Power(1)
 if inCombat and s.bearBarkskin and not B.buff('Barkskin')then
  B.offer('Barkskin','tank emergency mitigation',{HealthGate('player',hp,M.BearSetting(s,'bearBarkskinHP'),true)})
 end
 if form=='other'then AddAction(nil,'Travel form')
 else
  if not inCombat then
   if form=='caster'then
    if s.buffs and not B.buff('Mark of the Wild')then B.offer('Mark of the Wild','own buff',nil,0)end
    if s.thorns and not B.buff('Thorns')then B.offer('Thorns','own physical reflection',nil,0)end
   end
   if s.heal then
    if not B.buff('Rejuvenation')then B.offer('Rejuvenation','rest heal',{HealthGate('player',hp,RULES.healRest,true)},0,nil,form~='caster')end
    B.offer('Healing Touch','rest heal',{HealthGate('player',hp,RULES.healRest,true)},0,nil,form~='caster')
   end
  end
  if inCombat and form=='bear'then
   if s.bearFrenzied and not B.buff('Frenzied Regeneration')then
    B.offer('Frenzied Regeneration','tank self-heal without leaving Bear',{
     HealthGate('player',hp,M.BearSetting(s,'bearFrenziedHP'),true),B.minRage(rage,M.BearSetting(s,'bearFrenziedRage'))},1,0)
   end
  end
  if hostile then
   local shift=B.learned('Dire Bear Form')and'Dire Bear Form'or'Bear Form'
   if form~='bear'and s.bearAutoForm and B.learned(shift)then
    if GetTime()-B.formAt<0.5 then AddAction(nil,'Bear Form settling')else B.offer(shift,'Tank Bear form',nil,0)end
   end
   if form=='bear'then
    local melee=B.melee()
    if s.bearGrowl and B.needsTaunt()and InMelee('Growl')then B.offer('Growl','recover ally aggro',nil,1,0)end
    if s.bearCharge and not melee and Bool((SafeCall(C_Spell and C_Spell.IsSpellInRange,CatID('Feral Charge')or'Feral Charge','target')))==true then
     B.offer('Feral Charge','verified Bear gap closer',nil,1,5)
    end
    local enemies,loose=B.enemies()
    local aoe=inCombat and s.aoe==true and enemies>=M.BearSetting(s,'bearAoeMinEnemies')
    if s.bearChallengingRoar and aoe and loose>=3 then B.offer('Challenging Roar','recover 3+ allies\' attackers',nil,1,15)end
    if melee then
     if s.bash and Bool((SafeCall(AL.TargetCasting)))==true then B.offer('Bash','Bear stun interrupt',nil,1,10)end
     if inCombat and B.buff('Frenzied Regeneration')then
      AddAction(AL.Ok('Attack')and'Attack'or nil,'preserve Rage for Frenzied Regeneration',{
       HealthGate('player',hp,M.BearSetting(s,'bearFrenziedHP'),true)})
     end
    end
    if inCombat and s.enrage and not B.buff('Enrage')then
     B.offer('Enrage','safe Bear Rage generation',{PowerGate(1,rage,M.BearSetting(s,'bearEnrageBelowRage'),true,true),
      M.BearSetting(s,'bearEnrageMinHP')<=0 or HealthGate('player',hp,M.BearSetting(s,'bearEnrageMinHP'),false)})
    end
    if s.bearFaerieFire and B.dot('Faerie Fire')<=2 and Bool((SafeCall(AL.InRange,'Faerie Fire')))~=false then
     B.offer('Faerie Fire','maintain own armor reduction',nil,0)
    end
    if melee then
     if s.bearDemoRoar and B.dot('Demoralizing Roar')<=2 then B.offer('Demoralizing Roar','physical mitigation',nil,1,10)end
     if inCombat and AL.burst then
      local threshold=M.BearSetting(s,'bearBurstMinTargetHP')
      local gates={threshold<=0 or HealthGate('target',HealthPercent('target'),threshold,false)}
      -- Berserk makes Primal Bite cleave. Its activation and empowered
      -- attack therefore require the selected, confirmed AoE branch.
      if aoe and s.bearBerserk and not B.buff('Berserk')then B.offer('Berserk','Burst: Bear AoE Primal Bite',gates)end
      if s.bearElunesLight and not B.buff("Elune's Light")then B.offer("Elune's Light",'Burst: racial critical chance',gates)end
      if s.bearBerserking and not B.buff('Berserking')then B.offer('Berserking','Burst: learned racial attack speed',gates,1,5)end
     end
     local left,stacks=B.dot('Lacerate')
     if s.bearLacerate and stacks>0 and left<=4.5 then B.offer('Lacerate','protect expiring own bleed stacks',nil,1,15)end
     if s.bearPrimalBite and(not B.buff('Berserk')or aoe)then B.offer('Primal Bite','Tank primary strike',nil,1,20)end
     if s.bearSwipe and aoe then B.offer('Swipe','Tank AoE',nil,1,20)end
     if s.bearLacerate and stacks<M.BearSetting(s,'bearLacerateStacks')then B.offer('Lacerate','build own bleed stacks',nil,1,15)end
     if s.bearMaul and not B.maulQueued()then B.offer('Maul','queued Bear Rage dump',{
      B.minRage(rage,M.BearSetting(s,'bearMaulRage'))},1,15)end
     if s.bearLacerate and s.bearLacerateFiller then B.offer('Lacerate','Bear damage / threat filler',nil,1,15)end
    end
    AddAction(AL.Ok('Attack')and'Attack'or nil,melee and'Bear melee / Rage recovery'or'move to melee')
   elseif form=='caster'then
    -- Preserve early leveling and mana-recovery damage without forcing a
    -- caster heal or an offensive form change while actually tanking.
    if not inCombat then CasterRotation(s,hp)
    else
     if not B.buff('Rejuvenation')and s.heal then B.offer('Rejuvenation','caster self-heal',{HealthGate('player',hp,RULES.healCaster,true)},0)end
     if Bool((SafeCall(AL.HasDebuff,'target','Moonfire')))~=true then B.offer('Moonfire','learned caster fallback',nil,0)end
     B.offer('Wrath','learned caster fallback',nil,0)
     AddAction(AL.Ok('Attack')and'Attack'or nil,'mana recovery / early leveling')
    end
   else AddAction(AL.Ok('Attack')and'Attack'or nil,'waiting for Bear form / mana')end
  end
 end
 AddAction(nil,inCombat and not hostile and'No target'or'Ready')
 local base=lastRotation.actions[#lastRotation.actions];lastRotation.baseSpell,lastRotation.baseReason=base.spell,base.reason
 return base.spell,base.reason
end


local function NextLeveling(s, inCombat, hostile)
    if not inCombat then curveFailures, powerMaximumCache = {}, {} end
    lastRotation = { at = GetTime(), actions = {} }
    local form, hp = Form(), HealthPercent("player")
    if not inCombat then
        if form == "caster" then
            if s.buffs and not AL.HasBuff("player", "Mark of the Wild") then Offer("Mark of the Wild", "buff", nil, 0) end
            if s.thorns and not AL.HasBuff("player", "Thorns") then Offer("Thorns", "buff", nil, 0) end
            if s.heal then
                Heal(hp, RULES.healRest)
                Offer("Healing Touch", "heal up", { HealthGate("player", hp, RULES.healRest, true) }, 0)
            end
            if s.drink then
                local manaPercent = Percent((SafeCall(AL.ManaPercent)))
                local gate
                if manaPercent ~= nil then gate = manaPercent <= RULES.drinkMana
                else
                    local maximum = PowerMaximum(0)
                    gate = maximum and PowerGate(0, Power(0), maximum * RULES.drinkMana / 100, true) or false
                end
                AddAction(nil, "Drink", { gate })
            end
        elseif s.heal then
            Heal(hp, RULES.healRest, true)
            Offer("Healing Touch", "heal up (shift out)", {
                HealthGate("player", hp, RULES.healRest, true) }, 0, nil, false, true)
        end
        if hostile then
            if AL.DPS60 and AL.DPS60.Active() and hostile and form ~= "bear" then
                local build = AL.DPS60.Build("DRUID", s, form == "cat" and "FERAL" or "BALANCE")
                if build == "FERAL" and form ~= "cat" then Offer("Cat Form", "Feral DPS form", nil, 0)
                elseif build == "BALANCE" and AL.DPS60.Missing("Moonkin Form", false) then Offer("Moonkin Form", "Balance DPS form", nil, 0) end
                if build == "BALANCE" and form == "cat" and not AL.DPS60.Known("Moonkin Form") then form = "caster" end
            end
            if form == "cat" then
                if not AL.HasBuff("player", "Prowl") then Offer("Prowl", "sneak in") end
                CatRotation(s, HealthPercent("target"), false)
            elseif form == "bear" then BearRotation(s)
            elseif form == "caster" then CasterRotation(s, hp) end
        end
    elseif hostile then
        if s.heal and form ~= "caster" then Heal(hp, RULES.healEmergency, true) end
        if AL.DPS60 and AL.DPS60.Active() and hostile and form ~= "bear" then
            local build = AL.DPS60.Build("DRUID", s, form == "cat" and "FERAL" or "BALANCE")
            if build == "FERAL" and form ~= "cat" then Offer("Cat Form", "Feral DPS form", nil, 0)
            elseif build == "BALANCE" and AL.DPS60.Missing("Moonkin Form", false) then Offer("Moonkin Form", "Balance DPS form", nil, 0) end
            if build == "BALANCE" and form == "cat" and not AL.DPS60.Known("Moonkin Form") then form = "caster" end
        end
        if AL.burst then
            Offer("Berserking", "burst")
            if InMelee(form == "cat" and "Claw" or "Maul") then Offer("War Stomp", "burst", nil, 0) end
        end
        if form == "cat" then CatRotation(s, HealthPercent("target"), true)
        elseif form == "bear" then BearRotation(s)
        elseif form == "caster" then CasterRotation(s, hp) end
    end
    AddAction(nil, inCombat and not hostile and "No target" or "Ready")
    local base = lastRotation.actions[#lastRotation.actions]
    lastRotation.baseSpell, lastRotation.baseReason = base.spell, base.reason
    return base.spell, base.reason
end

function M.NextSpell(s,inCombat,hostile)
    M.NormalizeBuild(s)
    if s.feralBear==true then return B.rotation(s,inCombat,hostile) end
    if s.balance==true then return BalanceBuildRotation(s,inCombat,hostile) end
    if s.feralCat==true then return CatBuildRotation(s,inCombat,hostile) end
    return NextLeveling(s,inCombat,hostile)
end

if AL.selfCastSpells then
    for _, name in ipairs({ "Mark of the Wild", "Thorns", "Rejuvenation", "Healing Touch", "Regrowth",
        "Bear Form", "Dire Bear Form", "Cat Form", "Moonkin Form", "Prowl", "Enrage", "Tiger's Fury", "Dash", "Berserking", "Shifting Power", "Berserk", "Elune's Light", "Innervate", "Barkskin", "Frenzied Regeneration", "Challenging Roar" }) do
        AL.selfCastSpells[name] = true
    end
end

function M.BuildOptions(page, ui)
	local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h:SetPoint("TOP", 0, -30)
	h:SetText("Rotation hints (adapts to your form):")
	ui.SettingCheck(page, 70, -52, "Mark of the Wild upkeep", "buffs")
	ui.SettingCheck(page, 70, -78, "Thorns upkeep", "thorns")
	ui.SettingCheck(page, 70, -104, "Heal reminders", "heal")
	ui.SettingCheck(page, 70, -130, "Drink reminder", "drink")
	ui.SettingCheck(page, 70, -156, "Bash interrupt (bear)", "bash")
	ui.SettingCheck(page, 290, -52, "Rake (cat)", "rake")
	ui.SettingCheck(page, 290, -78, "Rip on tough mobs (cat)", "rip")
	ui.SettingCheck(page, 290, -104, "Tiger's Fury (cat)", "tigersfury")
	ui.SettingCheck(page, 290, -130, "Enrage + Demo Roar (bear)", "enrage")
	ui.SettingCheck(page, 290, -156, "AoE mode (Swipe)", "aoe")
end

-- A Leveling-to-talent handoff is a fresh resource-curve decision.
-- The original Leveling cache is independent and remains untouched.
function M.OnRotationActivated()
    curveFailures, powerMaximumCache = {}, {}
end

AL.RegisterRotation("DRUID", M)
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
    root.RegisterRotation("DRUID", advanced)
end
