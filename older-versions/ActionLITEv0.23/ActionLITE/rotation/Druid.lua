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
