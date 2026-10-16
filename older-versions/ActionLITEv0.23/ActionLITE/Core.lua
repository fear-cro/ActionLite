local ADDON, AL = ...

AL.playerClass = select(2, UnitClass("player"))
local trackedComboClass = AL.playerClass == "ROGUE" or AL.playerClass == "DRUID"
local trackedRotationClass = trackedComboClass or AL.playerClass == "HUNTER" or AL.playerClass == "PALADIN" or AL.playerClass == "MAGE" or AL.playerClass == "SHAMAN"
local trackedCastClass = AL.playerClass == "WARLOCK" or trackedRotationClass
local preciseCooldownClass = AL.playerClass == "PALADIN" or AL.playerClass == "MAGE" or AL.playerClass == "SHAMAN"
AL.CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
AL.BABY_R, AL.BABY_G, AL.BABY_B = 0.54, 0.81, 0.94
AL.WHITE = "Interface\\Buttons\\WHITE8X8"

AL.defaults = {
	scale = 1, nobg = false,
	p_targeting = true, p_vehicle = true, p_mounted = true, p_ooc = false,
	p_loot = true, p_dead = true, p_targetdead = true, p_eating = true,
	noprint = false, norange = false,
}

AL.burst = false
-- global so the "/run ActionLite_Burst()" macro can reach it
function ActionLite_Burst()
	AL.burst = not AL.burst
	if AL.UpdateBurstText then AL.UpdateBurstText() end
end

-- spell queue: queued entries override the rotation on the icon until cast
AL.queue = {}
local QUEUE_TIMEOUT = 20

-- toggles: queuing an already-queued spell removes it instead
function ActionLite_Queue(spell)
	if type(spell) ~= "string" or spell == "" then return end
	local say = not AL.S().noprint
	for i, q in ipairs(AL.queue) do
		if q.spell == spell then
			table.remove(AL.queue, i)
			if say then
				print(("|cff89cff0[ActionLITE]|r |cff888888queue[|r|cffff2020-|r|cff888888]|r |cff888888->|r |cffffcc00%s|r |cff888888unqueued|r"):format(spell))
			end
			return
		end
	end
	AL.queue[#AL.queue + 1] = { spell = spell, at = GetTime() }
	if say then
		print(("|cff89cff0[ActionLITE]|r |cff888888queue[|r|cff1ae61a%d|r|cff888888]|r |cff888888->|r |cffffcc00%s|r"):format(#AL.queue, spell))
	end
end

function AL.PruneQueue()
	local now = GetTime()
	local i = 1
	while AL.queue[i] do
		if now - AL.queue[i].at > QUEUE_TIMEOUT then
			table.remove(AL.queue, i)
		else
			i = i + 1
		end
	end
end

function AL.PopQueue(castName)
	for i, q in ipairs(AL.queue) do
		if q.spell == castName then
			table.remove(AL.queue, i)
			return
		end
	end
end

-- Class rotations live in rotation\<Class>.lua and register themselves here
AL.rotations = {}
function AL.RegisterRotation(token, module)
	AL.rotations[token] = module
end

-- Class-specific menu pages live in <Class>_UI.lua. Keeping this registry
-- separate lets an interface evolve without touching the combat rotation.
AL.classUIs = {}
AL.classUIVersions = {}
function AL.RegisterClassUI(token, builder, version)
	if type(token) ~= "string" or type(builder) ~= "function" then return end
	AL.classUIs[token] = builder
	if type(version) == "string" and version ~= "" then
		AL.classUIVersions[token] = version
	end
end

function AL.FillDefaults(p, token)
	for k, v in pairs(AL.defaults) do
		if p[k] == nil then p[k] = v end
	end
	local mod = AL.rotations[token]
	if mod and mod.defaults then
		for k, v in pairs(mod.defaults) do
			if p[k] == nil then p[k] = v end
		end
	end
	p.spells = p.spells or {}
	p.version = p.version or "1.0"
end

function AL.Profile(token)
	local db = ActionLiteDB
	if not db or not db.profiles then return AL.defaults end
	token = token or AL.playerClass
	local p = db.profiles[token]
	if not p then
		p = {}
		AL.FillDefaults(p, token)
		db.profiles[token] = p
	end
	return p
end

-- engine always runs on the player's own class profile
function AL.S() return AL.Profile(AL.playerClass) end
-- the menu edits whichever profile is selected in the dropdown
function AL.ES()
	local db = ActionLiteDB
	return AL.Profile(db and db.activeProfile)
end

function AL.Say(text)
	if not AL.S().noprint then print("|cff89cff0ActionLITE|r: " .. text) end
end

local function ClassIconTag(token)
	local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
	if not c then return "" end
	return ("|TInterface\\TargetingFrame\\UI-Classes-Circles:14:14:0:0:256:256:%d:%d:%d:%d|t "):format(
		c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

local function ClassColorHex(token)
	local cc = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[token]
	return cc and (cc.colorStr or string.format("ff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)) or "ffffffff"
end

function AL.Announce()
	if AL.S().noprint then return end
	local token = AL.playerClass
	local label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
	local addonVersion
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		addonVersion = C_AddOns.GetAddOnMetadata("ActionLITE", "Version")
	elseif GetAddOnMetadata then
		addonVersion = GetAddOnMetadata("ActionLITE", "Version")
	end
	print("|cff89cff0Action|r|cff1ae61aLITE|r |cff888888v" .. (addonVersion or "1.0") .. "|r loaded.")
	local classText = ClassIconTag(token) .. "|c" .. ClassColorHex(token) .. label .. "|r"
	if AL.rotations[token] then
		print("   " .. classText .. " |cff1ae61arotation active|r |cff888888(profile v" .. (AL.S().version or "1.0") .. ")|r")
	else
		print("   " .. classText .. " |cffff7700no rotation module yet|r")
	end
	print("   |cffffcc00/action|r to open the menu, or right-click the icon.")
end

local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
function AL.SetClassIcon(tex, token)
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
	if coords then
		tex:SetTexture(CLASS_ICONS)
		tex:SetTexCoord(unpack(coords))
	else
		tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

function AL.Allowed(name, prof)
	local sp = (prof or AL.S()).spells
	return not sp or sp[name] ~= false
end

-- API compat: 1.60 client may ship either the classic globals or the C_Spell namespace
function AL.SpellName(spell)
	if GetSpellInfo then return (GetSpellInfo(spell)) end
	return C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
end

function AL.SpellTexture(spell)
	if GetSpellTexture then return GetSpellTexture(spell) end
	return C_Spell.GetSpellTexture(spell)
end

-- Interchangeable icons offered per spell in the Spells tab
AL.UNIVERSAL_ICONS = { 133667, 133663, 133658, 133653, 133650, 133648, 133646, 133643, 133639, 133632 }

-- Melee auto-attack has no proper spell texture; every class shows a sword
AL.IconOverrides = AL.IconOverrides or {}
AL.IconOverrides["Attack"] = function() return 135274 end -- INV_Sword_04
AL.IconOverrides["Auto Shot"] = function() return 132317 end

-- Per-spell icon choice (profile.icons), then rotation-module overrides
function AL.IconFor(spell, prof)
	local p = prof or AL.S()
	local id = p.icons and p.icons[spell]
	if id then return id end
	local ov = AL.IconOverrides and AL.IconOverrides[spell]
	if ov then return ov() end
end

function AL.SpellCooldown(spell)
	-- Learned ranks for the tracked cooldown classes are cached before combat; an English name can resolve the
	-- wrong rank or fail on a localized client even while this ID is readable.
	if preciseCooldownClass then
		local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[spell]
		local id = ref and ref.id
		if type(id) == "number" and not (issecretvalue and issecretvalue(id)) then spell = id end
	end
	if GetSpellCooldown then
		local ok, s, d = pcall(GetSpellCooldown, spell)
		if ok then return s, d end
		return nil
	end
	local ok, c = pcall(C_Spell.GetSpellCooldown, spell)
	if preciseCooldownClass and (not ok or (issecretvalue and issecretvalue(c)) or type(c) ~= "table") then return nil end
	if ok and c then return c.startTime, c.duration end
end

-- blocked/secret usability reads count as usable; a real "no mana" still gates
function AL.SpellUsable(spell)
	local ok, usable, insufficient
	if IsUsableSpell then
		ok, usable, insufficient = pcall(IsUsableSpell, spell)
	else
		ok, usable, insufficient = pcall(C_Spell.IsSpellUsable, spell)
	end
	if not ok then return true end
	if issecretvalue and issecretvalue(usable) then return true end
	if (issecretvalue and issecretvalue(insufficient)) or type(insufficient) ~= "boolean" then insufficient = nil end
	return usable and true or false, insufficient
end

function AL.HealthPercent(unit)
	local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
	if issecretvalue and (issecretvalue(hp) or issecretvalue(hpMax)) then return nil end
	if type(hp) ~= "number" or type(hpMax) ~= "number" or hpMax == 0 then return nil end
	return hp / hpMax * 100
end

-- nil when the client hides bag data, otherwise total across the given item ids
function AL.ItemCount(ids)
	if not GetItemCount then return nil end
	local total = 0
	for _, id in ipairs(ids) do
		local ok, c = pcall(GetItemCount, id)
		if ok and type(c) == "number" and not (issecretvalue and issecretvalue(c)) then
			total = total + c
		end
	end
	return total
end

function AL.TargetCasting()
	if not UnitExists("target") then return false end
	if UnitCastingInfo then
		local ok, name = pcall(UnitCastingInfo, "target")
		if ok and name and not (issecretvalue and issecretvalue(name)) then return true end
	end
	if UnitChannelInfo then
		local ok, name = pcall(UnitChannelInfo, "target")
		if ok and name and not (issecretvalue and issecretvalue(name)) then return true end
	end
	return false
end

function AL.TargetHasAnyDebuff(names)
	for _, n in ipairs(names) do
		if AL.HasDebuff("target", n) then return true end
	end
	return false
end

function AL.WandEquipped()
	return GetInventoryItemID("player", 18) ~= nil
end

function AL.Ok(name)
	return AL.known[name] and AL.Allowed(name)
end

-- Spellbook scans can list spells before they're trainable; classes gate by level too
function AL.LevelGates(minLevels)
	local function lvlOk(spell)
		local lvl = UnitLevel and UnitLevel("player")
		if issecretvalue and issecretvalue(lvl) then lvl = nil end
		if type(lvl) ~= "number" or lvl <= 0 then return true end
		return lvl >= (minLevels[spell] or 1)
	end
	local function ok(spell) return AL.Ok(spell) and lvlOk(spell) end
	local function okReady(spell) return AL.OkReady(spell) and lvlOk(spell) end
	local function known(spell) return AL.known[spell] and lvlOk(spell) end
	return ok, okReady, known
end

function AL.OkReady(name)
	return AL.Ok(name) and AL.IsReady(name)
end

-- ptype: 1 = rage, 3 = energy
-- Forever peut rendre UnitPower(player, type) secret alors que la lecture de
-- la ressource principale sans type reste exploitable. On essaie donc les
-- sources connues sans jamais effectuer de calcul sur une valeur secrete.
local function SafePowerCall(reader, ...)
	if type(reader) ~= "function" then return nil end
	local ok, value = pcall(reader, ...)
	if not ok or (issecretvalue and issecretvalue(value)) then return nil end
	if type(value) ~= "number" then return nil end
	return value
end

local function NormalizePower(value, minimum, maximum)
	if type(value) ~= "number" or type(minimum) ~= "number" or type(maximum) ~= "number" then
		return nil
	end
	if maximum <= minimum or value < minimum or value > maximum then return nil end
	local percent = (value - minimum) / (maximum - minimum) * 100
	return math.floor(percent + 0.5)
end

local function PowerFromStatusBar(bar)
	if not bar then return nil end
	local value = SafePowerCall(bar.GetValue, bar)
	if value == nil or type(bar.GetMinMaxValues) ~= "function" then return nil end

	local ok, minimum, maximum = pcall(bar.GetMinMaxValues, bar)
	if not ok or (issecretvalue and (issecretvalue(minimum) or issecretvalue(maximum))) then
		return nil
	end
	return NormalizePower(value, minimum, maximum)
end

local function PowerFromFontString(fontString, knownMaximum)
	if not fontString or type(fontString.GetText) ~= "function" then return nil end
	local ok, value = pcall(fontString.GetText, fontString)
	if not ok or (issecretvalue and issecretvalue(value)) or type(value) ~= "string" then
		return nil
	end

	local current, maximum = string.match(value, "(%d+)%s*/%s*(%d+)")
	current, maximum = tonumber(current), tonumber(maximum)
	if current and maximum then return NormalizePower(current, 0, maximum) end

	current = tonumber(string.match(value, "^%s*(%d+)%s*$"))
	if current and knownMaximum then return NormalizePower(current, 0, knownMaximum) end
	if current and current >= 0 and current <= 100 then return current end
	return nil
end

-- Forever peut masquer UnitPower tout en laissant la barre du joueur se mettre
-- a jour. Lire cette barre est un repli d'affichage, jamais une estimation.
local function RageFromPlayerFrame()
	local bar = _G.PlayerFrameManaBar
	local value = PowerFromStatusBar(bar)
	if value ~= nil then return value end

	local frame = _G.PlayerFrame
	local content = frame and frame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local area = main and main.ManaBarArea
	local nestedBar = area and area.ManaBar
	value = PowerFromStatusBar(nestedBar)
	if value ~= nil then return value end

	value = PowerFromFontString(_G.PlayerFrameManaBarText)
	if value ~= nil then return value end

	local maximum = PowerFromFontString(_G.PlayerFrameManaBarTextRight)
	value = PowerFromFontString(_G.PlayerFrameManaBarTextLeft, maximum)
	if value ~= nil then return value end

	return PowerFromFontString((nestedBar or bar) and (nestedBar or bar).TextString)
end

function AL.Power(ptype)
	local currentType = SafePowerCall(UnitPowerType, "player")

	-- Methode utilisee par Action.Unit(player):Power().
	if ptype == nil or currentType == nil or currentType == ptype then
		local value = SafePowerCall(UnitPower, "player")
		if value ~= nil then return value end
	end

	local value = SafePowerCall(UnitPower, "player", ptype)
	if value ~= nil then return value end

	-- Dernier essai via le cache Action lorsqu'il est disponible.
	local A = _G.Action
	if A and A.Unit then
		local ok, unit = pcall(A.Unit, "player")
		if ok and unit and unit.Power then
			value = SafePowerCall(unit.Power, unit)
			if value ~= nil then return value end
		end
	end

	-- Sur Warrior, la barre d'interface peut rester lisible lorsque UnitPower
	-- devient secret en combat.
	if ptype == 1 and AL.playerClass == "WARRIOR" then
		value = RageFromPlayerFrame()
		if value ~= nil then return value end
	end

	-- La rage revient a zero hors combat sur Forever. En combat, nil reste
	-- volontairement inconnu afin de ne pas autoriser une depense a tort.
	if ptype == 1 and UnitAffectingCombat then
		local ok, inCombat = pcall(UnitAffectingCombat, "player")
		if ok and not (issecretvalue and issecretvalue(inCombat)) and inCombat == false then
			return 0
		end
	end

	return nil
end

-- Combo points read as secret in combat: infer from landed builders/finishers
local CP_BUILDERS = {
	["Sinister Strike"] = 1, ["Backstab"] = 1, ["Gouge"] = 1, ["Ambush"] = 1,
	["Garrote"] = 1, ["Cheap Shot"] = 2, ["Riposte"] = 1,
	["Claw"] = 1, ["Rake"] = 1, ["Shred"] = 1,
}
local CP_FINISHERS = {
	["Eviscerate"] = true, ["Slice and Dice"] = true, ["Rupture"] = true,
	["Kidney Shot"] = true, ["Expose Armor"] = true,
	["Ferocious Bite"] = true, ["Rip"] = true,
}
local inferredCp = 0
local pendingComboCast
local rogueComboChangedAt, rogueComboBefore = -math.huge, nil

function AL.TrackComboCast(name)
	local before = inferredCp
	if trackedComboClass then
		if CP_FINISHERS[name] then
			rogueComboChangedAt, rogueComboBefore = GetTime(), before
		elseif CP_BUILDERS[name] then
			rogueComboChangedAt, rogueComboBefore = -math.huge, nil
		end
	end
	if CP_BUILDERS[name] then
		pendingComboCast = { name = name, before = before, at = GetTime() }
		inferredCp = math.min(5, inferredCp + CP_BUILDERS[name])
	elseif CP_FINISHERS[name] then
		pendingComboCast = { name = name, before = before, at = GetTime() }
		inferredCp = 0
		return before
	end
end

-- UNIT_SPELLCAST_SUCCEEDED signifie que le bouton a ete accepte, pas que
-- l'attaque a touche. Le journal de combat arrive ensuite avec SPELL_MISSED :
-- on restaure alors exactement l'etat precedant le builder ou le finisher.
function AL.RestoreComboPointsOnMiss(name)
	local pending = pendingComboCast
	if not pending or pending.name ~= name or GetTime() - pending.at > 3 then return false end
	inferredCp = pending.before
	pendingComboCast = nil
	return true
end

function AL.ResetComboPoints()
	rogueComboChangedAt, rogueComboBefore = -math.huge, nil
	inferredCp = 0
	pendingComboCast = nil
end

function AL.ComboPoints()
	if trackedComboClass then
		local function Valid(value)
			return type(value) == "number" and value >= 0 and value <= 5 and value == math.floor(value) and value or nil
		end
		local primary = Valid(SafePowerCall(GetComboPoints, "player", "target"))
		local typed = Valid(SafePowerCall(UnitPower, "player", 4))
		local value = primary and primary > 0 and primary or (typed and typed > 0 and typed or primary or typed)
		-- A consumed point display can briefly retain its pre-finisher value.
		if value == rogueComboBefore and GetTime() - rogueComboChangedAt < 0.5 then return inferredCp end
		if value and value > 0 then inferredCp = value; return value end
		-- Forever can return a readable zero even while points exist.
		return inferredCp
	end
	local v
	if GetComboPoints then
		local ok, r = pcall(GetComboPoints, "player", "target")
		v = ok and r or nil
	end
	if v == nil then v = UnitPower("player", 4) end
	if (issecretvalue and issecretvalue(v)) or type(v) ~= "number" then
		return inferredCp
	end
	if v > 0 then
		inferredCp = v
		return v
	end
	-- this client reports 0 even with points up; trust the cast counter then
	return math.max(v, inferredCp)
end

function AL.CreatureType(unit)
	local ok, t = pcall(UnitCreatureType, unit)
	if not ok then return nil end
	if issecretvalue and issecretvalue(t) then return nil end
	if type(t) ~= "string" then return nil end
	return t
end

-- 1.60 can protect UnitPower/UnitPowerMax in combat. Prefer the direct API
-- when readable, then fall back to the visible player power bar. This is a
-- display read, not an estimate: if neither source is readable, return nil.
function AL.ManaPercent()
	local mana = SafePowerCall(UnitPower, "player", 0)
	local manaMax = SafePowerCall(UnitPowerMax, "player", 0)

	if type(mana) == "number" and type(manaMax) == "number" and manaMax > 0 then
		return mana / manaMax * 100
	end

	-- Warlocks use the player mana bar, so the same status-bar reader used as
	-- the Warrior power fallback gives us a real percentage when the API is
	-- secretized but the on-screen bar remains readable.
	local percent = RageFromPlayerFrame()
	if percent ~= nil then return percent end

	return nil
end

-- Diagnostics for Priest tracked-mana fallback. Values remain nil when Forever
-- protects them; callers must not treat nil as zero or full mana.
function AL.ManaDebugSources()
	local primary = SafePowerCall(UnitPower, "player")
	local primaryMax = SafePowerCall(UnitPowerMax, "player")
	local typed = SafePowerCall(UnitPower, "player", 0)
	local typedMax = SafePowerCall(UnitPowerMax, "player", 0)
	local frame = RageFromPlayerFrame()
	return {
		primary = primary, primaryMax = primaryMax,
		typed = typed, typedMax = typedMax,
		power = nil, frame = frame,
		cachedMax = typedMax or primaryMax,
		source = typed and "typed" or (primary and "primary" or (frame and "frame" or "unreadable")),
	}
end

-- Les rotations marquent leurs sorts lances sur soi : une cible ennemie
-- selectionnee ne doit jamais colorer un soin ou un buff personnel en rouge.
AL.selfCastSpells = AL.selfCastSpells or {}

-- true = in range, false = out of range, nil = unknown/no target
function AL.InRange(spell)
	if AL.selfCastSpells and AL.selfCastSpells[spell] then return true end
	if not UnitExists("target") then return nil end
	local function Normalize(ok, value)
		if not ok or (issecretvalue and issecretvalue(value)) then return nil end
		if value == true or value == 1 then return true end
		if value == false or value == 0 then return false end
		return nil
	end
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[spell]
	local id = ref and ref.id or type(spell) == "number" and spell
	if id and C_Spell and type(C_Spell.IsSpellInRange) == "function" then
		local result = Normalize(pcall(C_Spell.IsSpellInRange, id, "target"))
		if result ~= nil then return result end
	end
	if type(IsSpellInRange) == "function" then
		-- L'ancienne signature numerique attend un INDEX du grimoire, pas un SpellID.
		if ref and ref.index then
			local result = Normalize(pcall(IsSpellInRange, ref.index, BOOKTYPE_SPELL or "spell", "target"))
			if result ~= nil then return result end
		end
		local name = spell
		if type(name) == "number" then
			local ok, value = pcall(AL.SpellName, name)
			name = ok and value or nil
		end
		if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
			local result = Normalize(pcall(IsSpellInRange, name, "target"))
			if result ~= nil then return result end
		end
	end
	if C_Spell and type(C_Spell.IsSpellInRange) == "function" and not id then
		return Normalize(pcall(C_Spell.IsSpellInRange, spell, "target"))
	end
	return nil
end

local function BookItemName(i)
	if GetSpellBookItemName then return GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell") end
	return C_SpellBook.GetSpellBookItemName(i, Enum.SpellBookSpellBank.Player)
end

-- Reference exacte du rang appris pour la portee. L'ancienne API attend un
-- index de grimoire tandis que C_Spell attend un SpellID : conserver les deux
-- evite de confondre l'ID classique d'un rang avec l'objet reel de Forever.
local function BookItemSpellID(i)
	if GetSpellBookItemInfo then
		local _, spellID = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
		if type(spellID) == "number" and not (issecretvalue and issecretvalue(spellID)) then
			return spellID
		end
		return nil
	end
	if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
		local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
		local spellID = type(info) == "table" and (info.spellID or info.actionID) or nil
		if type(spellID) == "number" and not (issecretvalue and issecretvalue(spellID)) then
			return spellID
		end
	end
end

AL.targetDebuffs = {}
local targetDebuffs = AL.targetDebuffs

-- Target auras are never read (1.60 blocks/secretizes them). Debuffs are
-- inferred from our own successful casts and expire on conservative timers.
local DEBUFF_DURATIONS = {
	["Rend"] = 9, ["Sunder Armor"] = 30, ["Demoralizing Shout"] = 30,
	["Hunter's Mark"] = 120, ["Serpent Sting"] = 15, ["Scorpid Sting"] = 20, ["Wing Clip"] = 10,
	["Shadow Word: Pain"] = 18, ["Devouring Plague"] = 24,
	["Vampiric Embrace"] = 60, ["Holy Fire"] = 10,
	["Immolate"] = 15, ["Corruption"] = 12, ["Curse of Agony"] = 24, ["Bane of Agony"] = 24,
	["Siphon Life"] = 30, ["Fear"] = 10,
	["Curse of the Elements"] = 300, ["Curse of Weakness"] = 120,
	["Curse of Recklessness"] = 120, ["Curse of Tongues"] = 30,
	["Moonfire"] = 9, ["Rake"] = 9, ["Rip"] = 12, ["Demoralizing Roar"] = 30,
	["Flame Shock"] = 12, ["Frost Shock"] = 8,
	["Frost Nova"] = 8, ["Frostbolt"] = 5, ["Cone of Cold"] = 8,
	["Gouge"] = 4, ["Expose Armor"] = 30, ["Rupture"] = 10,
	["Garrote"] = 18,
}

-- 1.60 blocks aura reads, so player buffs are inferred entirely from our own
-- successful casts with conservative vanilla durations.
local BUFF_GROUPS = {
	-- casting one member replaces the others
	{ "Seal of Command", "Seal of Righteousness", "Seal of the Crusader" },
	{ "Devotion Aura", "Retribution Aura", "Concentration Aura" },
	{ "Blessing of Might", "Blessing of Wisdom", "Blessing of Protection", "Blessing of Freedom" },
	{ "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah" },
	{ "Frost Armor", "Ice Armor", "Mage Armor" },
	{ "Demon Skin", "Demon Armor" },
	{ "Bear Form", "Dire Bear Form", "Cat Form", "Aquatic Form", "Travel Form" },
}
local groupOf = {}
for _, group in ipairs(BUFF_GROUPS) do
	for _, member in ipairs(group) do groupOf[member] = group end
end

local SELF_BUFF_DURATIONS = {
	["Seal of Command"] = 30, ["Seal of Righteousness"] = 30, ["Seal of the Crusader"] = 30,
	["Blessing of Might"] = 300, ["Blessing of Wisdom"] = 300,
	["Blessing of Protection"] = 10, ["Blessing of Freedom"] = 10,
	["Devotion Aura"] = 3600, ["Retribution Aura"] = 3600, ["Concentration Aura"] = 3600,
	["Righteous Fury"] = 1800, ["Divine Protection"] = 8, ["Divine Shield"] = 12,
	["Aspect of the Hawk"] = 3600, ["Aspect of the Monkey"] = 3600, ["Aspect of the Cheetah"] = 3600,
	["Rapid Fire"] = 15,
	["Arcane Intellect"] = 1800, ["Frost Armor"] = 1800, ["Ice Armor"] = 1800, ["Mage Armor"] = 1800,
	["Ice Block"] = 10, ["Mana Shield"] = 60, ["Berserking"] = 10,
	["Mark of the Wild"] = 1800, ["Thorns"] = 600, ["Rejuvenation"] = 12, ["Tiger's Fury"] = 6,
	["Bear Form"] = 3600, ["Dire Bear Form"] = 3600, ["Prowl"] = 3600, ["Enrage"] = 10, ["Cat Form"] = 3600, ["Aquatic Form"] = 3600, ["Travel Form"] = 3600,
	["Power Word: Fortitude"] = 1800, ["Inner Fire"] = 600, ["Renew"] = 15, ["Power Word: Shield"] = 30,
	["Stealth"] = 3600, ["Evasion"] = 15, ["Blade Flurry"] = 15, ["Slice and Dice"] = 12,
	["Lightning Shield"] = 600, ["Demon Skin"] = 1800, ["Demon Armor"] = 1800,
	["Battle Shout"] = 120,
	["Food"] = 25, ["Drink"] = 25,
}
-- Buff lands under a different name than the cast. Vanish grants the Stealth
-- state too; its short fallback is only used when Forever hides the aura.
local CAST_BUFF_ALIASES = {
	["Strength of Earth Totem"] = { "Strength of Earth", 120 },
	["Vanish"] = { "Stealth", 10 },
}

-- Successful hostile actions break inferred Stealth immediately. The actual
-- aura/tooltip remains authoritative whenever Forever exposes it.
local STEALTH_BREAKERS = {
	["Ambush"] = true,
	["Cheap Shot"] = true,
	["Garrote"] = true,
	["Backstab"] = true,
	["Sinister Strike"] = true,
}

local selfBuffs = {}
local rogueBuffGrace, rogueSliceDurations = {}, {}
local PALADIN_SEALS = {
	["Seal of Command"] = true, ["Seal of Righteousness"] = true, ["Seal of the Crusader"] = true,
}
local paladinSealAuras, paladinSealAurasValid, paladinSealDurations = {}, false, {}

local function PaladinSealInFlight()
	if AL.playerClass ~= "PALADIN" then return false end
	for name in pairs(PALADIN_SEALS) do
		if rogueBuffGrace[name] and rogueBuffGrace[name] > GetTime() then return true end
	end
	return false
end

-- Read real expiration when available. Aura names alone do not tell us how
-- much of a seal's lifetime has already elapsed before combat starts.
local function ReadPaladinSealAuras()
	local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if type(reader) ~= "function" then return nil end
	local function Public(value)
		return not (issecretvalue and issecretvalue(value))
	end
	local function Finite(value)
		return Public(value) and type(value) == "number" and value == value
			and value > -math.huge and value < math.huge
	end
	local ok, names, expirations = pcall(function()
		local found, expires = {}, {}
		for index = 1, 40 do
			local aura = reader("player", index, "HELPFUL")
			if not Public(aura) then return nil end
			if aura == nil then return found, expires end
			if type(aura) ~= "table" then return nil end
			local name, id = aura.name, aura.spellId
			if Public(name) and type(name) == "string" then
				name = (AL.englishNames and AL.englishNames[name]) or name
			elseif Finite(id) then
				local cached = AL.castSpellNamesByID and AL.castSpellNamesByID[id]
				name = cached and ((AL.englishNames and AL.englishNames[cached]) or cached)
				if not name then
					for seal in pairs(PALADIN_SEALS) do
						local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[seal]
						if ref and Public(ref.id) and ref.id == id then name = seal; break end
					end
				end
			else
				return nil -- an unidentified protected aura cannot prove absence
			end
			if not name then return nil end
			if name and PALADIN_SEALS[name] then
				found[name] = true
				local expiration, duration = aura.expirationTime, aura.duration
				if Finite(expiration) and expiration > 0 then expires[name] = time() + expiration - GetTime() end
				if Finite(duration) and duration > 0 and duration <= 300 then paladinSealDurations[name] = duration end
			end
		end
		return found, expires
	end)
	if ok then return names, expirations end
end

local function RefreshPaladinSealAuras()
	if AL.playerClass ~= "PALADIN" or PaladinSealInFlight() then return end
	local names, expirations = ReadPaladinSealAuras()
	paladinSealAuras, paladinSealAurasValid = names or {}, names ~= nil
	if not names then return end
	for name in pairs(PALADIN_SEALS) do
		if names[name] then
			selfBuffs[name] = expirations[name] or selfBuffs[name]
				or time() + (paladinSealDurations[name] or SELF_BUFF_DURATIONS[name])
		else
			selfBuffs[name] = nil
		end
	end
end

local function RefreshRogueSliceDurations()
	if AL.playerClass ~= "ROGUE" then return end
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs["Slice and Dice"]
	local reader = C_Spell and C_Spell.GetSpellDescription or GetSpellDescription
	if type(reader) ~= "function" or not ref then return end
	local ok, text = pcall(reader, ref.id or "Slice and Dice")
	if not ok or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
	for points = 1, 5 do
		local pattern = points .. "%s+points?%s*:%s*(%d+%.?%d*)%s+sec"
		local duration = tonumber(text:match(pattern))
		if duration and duration > 0 and duration <= 120 then rogueSliceDurations[points] = duration end
	end
end

-- Preserve the actual readable expiration when player auras are available.
local function RogueBuffExpiration(name)
	if AL.playerClass ~= "ROGUE" then return nil end
	local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if type(reader) ~= "function" then return nil end
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	for index = 1, 40 do
		local ok, aura = pcall(reader, "player", index, "HELPFUL")
		if not ok or (issecretvalue and issecretvalue(aura)) then return nil, false end
		if aura == nil then return nil, true end
		if type(aura) ~= "table" then return nil, false end
		local auraName, id, expiration = aura.name, aura.spellId, aura.expirationTime
		if issecretvalue and (issecretvalue(auraName) or issecretvalue(id) or issecretvalue(expiration)) then return nil, false end
		local english = AL.englishNames and AL.englishNames[auraName] or auraName
		if english == name or (ref and ref.id and id == ref.id) then
			if type(expiration) == "number" and expiration > GetTime() and expiration < math.huge then
				return time() + expiration - GetTime(), true
			end
			return nil, true
		end
	end
	return nil, true
end

local function RogueBuffInFlight(name)
	return trackedRotationClass and rogueBuffGrace[name] and rogueBuffGrace[name] > GetTime()
end

-- Cooldowns are inferred from casts too: blocked/secret cooldown reads in
-- combat made IsReady return false, so Holy Strike/Judgement never fired.
local SPELL_COOLDOWNS = {
	["Holy Strike"] = 6, ["Judgement"] = 10, ["Hammer of Justice"] = 60, ["Exorcism"] = 15,
	["Consecration"] = 8, ["Divine Protection"] = 300, ["Divine Shield"] = 300,
	["Blessing of Protection"] = 300, ["Blessing of Freedom"] = 25, ["Lay on Hands"] = 3600,
	["Arcane Shot"] = 6, ["Multi-Shot"] = 10, ["Raptor Strike"] = 6, ["Rapid Fire"] = 300, ["Disengage"] = 5,
	["Fire Blast"] = 8, ["Frost Nova"] = 25, ["Cone of Cold"] = 10, ["Counterspell"] = 30,
	["Ice Block"] = 300, ["Evocation"] = 480, ["Conjure Mana Agate"] = 30,
	["Mind Blast"] = 8, ["Holy Fire"] = 10, ["Devouring Plague"] = 180,
	["Psychic Scream"] = 30, ["Silence"] = 45, ["Desperate Prayer"] = 600, ["Fade"] = 30,
	["Gouge"] = 10, ["Kick"] = 10, ["Evasion"] = 300, ["Blade Flurry"] = 120, ["Stealth"] = 10,
	["Vanish"] = 300, ["Riposte"] = 6,
	["Charge"] = 15, ["Bloodrage"] = 60, ["Bash"] = 60, ["Enrage"] = 600, ["Tiger's Fury"] = 1,
	["Overpower"] = 5, ["Revenge"] = 5, ["Thunder Clap"] = 4,
	["Mongoose Bite"] = 5, ["Concussive Shot"] = 12, ["Summon Hawk"] = 6,
	["Stormstrike"] = 20,
	["Blood Fury"] = 120, ["Berserking"] = 180, ["War Stomp"] = 120,
}
local cdExpires = {}
local preciseCooldowns = {}

-- Inferred buffs use epoch time() and persist in ActionLiteDB, so a /reload
-- or relog doesn't forget active auras and suggest re-buffing.
function AL.RestoreSelfBuffs()
	local db = ActionLiteDB
	if not db then return end
	if db.selfBuffs and db.selfBuffs ~= selfBuffs then
		local now = time()
		for name, exp in pairs(db.selfBuffs) do
			if type(exp) == "number" and exp > now then selfBuffs[name] = exp end
		end
	end
	db.selfBuffs = selfBuffs
end

-- UnitBuff returns blocked/secret data, but a hidden tooltip still renders the
-- buff name into its font string, which stays readable. Scan that first.
local scanTip = CreateFrame("GameTooltip", "ActionLiteScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

local function SetAuraTip(unit, i, harmful)
	if harmful then
		if scanTip.SetUnitDebuff then return pcall(scanTip.SetUnitDebuff, scanTip, unit, i) end
		return pcall(scanTip.SetUnitAura, scanTip, unit, i, "HARMFUL")
	end
	if scanTip.SetUnitBuff then return pcall(scanTip.SetUnitBuff, scanTip, unit, i) end
	return pcall(scanTip.SetUnitAura, scanTip, unit, i, "HELPFUL")
end

-- Rebuilds `out` with the unit's aura names; false when the client blocked the read.
local function SweepAuras(unit, harmful, out)
	wipe(out)
	for i = 1, 40 do
		scanTip:SetOwner(UIParent, "ANCHOR_NONE")
		scanTip:ClearLines()
		if not SetAuraTip(unit, i, harmful) then return false end
		local fs = _G["ActionLiteScanTipTextLeft1"]
		local ok, text = pcall(function() return fs and fs:GetText() end)
		if not ok or (text ~= nil and issecretvalue and issecretvalue(text)) then return false end
		if not text or text == "" then break end -- end of the aura list
		if trackedRotationClass then text = (AL.englishNames and AL.englishNames[text]) or text end
		out[text] = true
	end
	return true
end

-- Snapshots rebuilt on UNIT_AURA / target change (and a 1s safety tick);
-- the valid flags drop to false whenever the client blocked the last sweep.
local tooltipBuffs, tooltipValid = {}, false
local tooltipDebuffs, debuffValid = {}, false
local tooltipPlayerDebuffs, playerDebuffValid = {}, false
local playerDebuffs = {}

local function SweepBuffs()
	tooltipValid = SweepAuras("player", false, tooltipBuffs)
	RefreshPaladinSealAuras()
	if not tooltipValid then
		if AL.playerClass == "ROGUE" then
			local expiration, readable = RogueBuffExpiration("Slice and Dice")
			if readable and (expiration or not RogueBuffInFlight("Slice and Dice")) then
				selfBuffs["Slice and Dice"] = expiration
			end
		end
		return
	end
	-- Mirror the real buff list into the fallback timers: combat blocks reads,
	-- so the countdown starts from the last readable snapshot (combat entry).
	local now = time()
	for name in pairs(tooltipBuffs) do
		if AL.playerClass == "ROGUE" and name == "Slice and Dice" then
			selfBuffs[name] = RogueBuffExpiration(name) or (selfBuffs[name] and selfBuffs[name] > now and selfBuffs[name])
				or now + (rogueSliceDurations[1] or 9)
		elseif AL.playerClass == "PALADIN" and PALADIN_SEALS[name] then
			-- A repeated name-only snapshot must not extend a short seal. Its
			-- successful cast or a real aura expiration owns the countdown.
			if not paladinSealAurasValid and not PaladinSealInFlight() then
				selfBuffs[name] = selfBuffs[name] or now + (paladinSealDurations[name] or SELF_BUFF_DURATIONS[name])
			end
		else
			selfBuffs[name] = now + (SELF_BUFF_DURATIONS[name] or 300)
		end
	end
	for name in pairs(selfBuffs) do
		if not tooltipBuffs[name] and not RogueBuffInFlight(name)
			and not (AL.playerClass == "PALADIN" and PALADIN_SEALS[name] and paladinSealAurasValid) then selfBuffs[name] = nil end
	end
end
AL.SweepBuffs = SweepBuffs

local function SweepTargetDebuffs()
	if UnitExists("target") then
		debuffValid = SweepAuras("target", true, tooltipDebuffs)
	else
		wipe(tooltipDebuffs)
		debuffValid = true
	end
end

local function SweepPlayerDebuffs()
	playerDebuffValid = SweepAuras("player", true, tooltipPlayerDebuffs)
	if not playerDebuffValid then return end
	-- A readable snapshot is authoritative. Keep only real player debuffs.
	for name in pairs(playerDebuffs) do
		if not tooltipPlayerDebuffs[name] then playerDebuffs[name] = nil end
	end
	for name in pairs(tooltipPlayerDebuffs) do
		playerDebuffs[name] = playerDebuffs[name] or { source = "AURA" }
	end
end

function AL.HasBuff(unit, name)
	if unit ~= "player" then return false end
	if RogueBuffInFlight(name) and selfBuffs[name] and selfBuffs[name] > time() then return true end
	if AL.playerClass == "PALADIN" and PALADIN_SEALS[name] then
		if PaladinSealInFlight() then return selfBuffs[name] ~= nil and selfBuffs[name] > time() end
		if paladinSealAurasValid then return paladinSealAuras[name] == true end
	end
	if tooltipValid then return tooltipBuffs[name] == true end
	-- tooltip sweep blocked: fall back to cast-inferred timers
	local exp = selfBuffs[name]
	return exp ~= nil and exp > time()
end

-- nil means a present buff has no known countdown; zero means missing/expired.
function AL.BuffRemaining(unit, name)
	if not AL.HasBuff(unit, name) then return 0 end
	local expiration = selfBuffs[name]
	if expiration then return math.max(0, expiration - time()) end
end

-- /al buffs: ground truth on what each detection layer sees right now
function AL.DumpBuffs()
	print("|cff89cff0[ActionLITE]|r tooltip APIs: SetUnitBuff=" .. tostring(scanTip.SetUnitBuff ~= nil) .. " SetUnitAura=" .. tostring(scanTip.SetUnitAura ~= nil))
	SweepBuffs()
	local names = {}
	for n in pairs(tooltipBuffs) do names[#names + 1] = n end
	print("|cff89cff0[ActionLITE]|r sweep valid=" .. tostring(tooltipValid) .. " buffs: " .. (#names > 0 and table.concat(names, ", ") or "(none)"))
	local now, inf = time(), {}
	for n, exp in pairs(selfBuffs) do inf[#inf + 1] = n .. " (" .. math.floor(exp - now) .. "s)" end
	print("|cff89cff0[ActionLITE]|r inferred: " .. (#inf > 0 and table.concat(inf, ", ") or "(none)"))
	print("|cff89cff0[ActionLITE]|r combo points: " .. tostring(AL.ComboPoints()) .. " (cast-inferred " .. tostring(inferredCp) .. ")")
end

local debuffFrame = CreateFrame("Frame")
debuffFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
debuffFrame:RegisterEvent("PLAYER_DEAD")
debuffFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
if not pcall(debuffFrame.RegisterUnitEvent, debuffFrame, "UNIT_SPELLCAST_SUCCEEDED", "player") then
	pcall(debuffFrame.RegisterEvent, debuffFrame, "UNIT_SPELLCAST_SUCCEEDED")
end
if not pcall(debuffFrame.RegisterUnitEvent, debuffFrame, "UNIT_SPELLCAST_SENT", "player") then
	pcall(debuffFrame.RegisterEvent, debuffFrame, "UNIT_SPELLCAST_SENT")
end
if not pcall(debuffFrame.RegisterUnitEvent, debuffFrame, "UNIT_SPELLCAST_FAILED", "player") then
	pcall(debuffFrame.RegisterEvent, debuffFrame, "UNIT_SPELLCAST_FAILED")
end
if not pcall(debuffFrame.RegisterUnitEvent, debuffFrame, "UNIT_SPELLCAST_INTERRUPTED", "player") then
	pcall(debuffFrame.RegisterEvent, debuffFrame, "UNIT_SPELLCAST_INTERRUPTED")
end
if trackedCastClass then
	for _, event in ipairs({ "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_DELAYED" }) do
		if not pcall(debuffFrame.RegisterUnitEvent, debuffFrame, event, "player") then
			pcall(debuffFrame.RegisterEvent, debuffFrame, event)
		end
	end
end
if not pcall(debuffFrame.RegisterUnitEvent, debuffFrame, "UNIT_AURA", "player", "target") then
	pcall(debuffFrame.RegisterEvent, debuffFrame, "UNIT_AURA")
end
pcall(debuffFrame.RegisterEvent, debuffFrame, "COMBAT_LOG_EVENT_UNFILTERED")
pcall(debuffFrame.RegisterEvent, debuffFrame, "UI_ERROR_MESSAGE")

-- best-effort spell-name extraction across client arg layouts and secret values
local function LegacyCastName(arg2, arg3, arg4)
	for _, a in ipairs({ arg4, arg3 }) do
		if type(a) == "number" and not (issecretvalue and issecretvalue(a)) then
			local ok, n = pcall(AL.SpellName, a)
			if ok and type(n) == "string" and not (issecretvalue and issecretvalue(n)) then return n end
		end
	end
	if type(arg2) == "string" and not (issecretvalue and issecretvalue(arg2)) and not arg2:find("^Cast%-") then
		return arg2
	end
end

local legacyLastSent

-- Resolve readable cast IDs from the learned spellbook first. GetSpellName
-- can be unavailable in combat even while the spellbook's saved ID/name is safe.
local function CastSpellName(id)
	if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then return nil end
	local cached = AL.castSpellNamesByID and AL.castSpellNamesByID[id]
	if cached then return (AL.englishNames and AL.englishNames[cached]) or cached end
	for name, ref in pairs(AL.rangeSpellRefs or {}) do
		local learnedID = ref.id
		if type(learnedID) == "number" and not (issecretvalue and issecretvalue(learnedID))
			and learnedID == id
		then
			return (AL.englishNames and AL.englishNames[name]) or name
		end
	end
	local ok, name = pcall(AL.SpellName, id)
	if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
		return name
	end
end

-- Modern SENT: (player, targetName, castGUID, spellID).
-- Modern SUCCEEDED: (player, castGUID, spellID).
-- A legacy spell-name payload is accepted only if it is a known/tracked spell;
-- the modern targetName must never become lastSent.name.
local function CastName(arg2, arg3, arg4)
	local name = CastSpellName(arg4) or CastSpellName(arg3)
	if name then return name end
	if type(arg2) ~= "string" or (issecretvalue and issecretvalue(arg2)) then return nil end
	local english = (AL.englishNames and AL.englishNames[arg2]) or arg2
	if (AL.known and AL.known[english]) or DEBUFF_DURATIONS[english]
		or SELF_BUFF_DURATIONS[english] or SPELL_COOLDOWNS[english]
	then
		return english
	end
end

local function EnglishCastName(...)
	local name = CastName(...)
	return name and ((AL.englishNames and AL.englishNames[name]) or name)
end

local UTILITY_CURSES = {
	["Curse of Weakness"] = true, ["Curse of Recklessness"] = true,
	["Curse of the Elements"] = true, ["Curse of Tongues"] = true,
}

local function ReadCastGUID(value)
	if type(value) == "string" and not (issecretvalue and issecretvalue(value))
		and value:find("^Cast%-")
	then
		return value
	end
end

local function CastTargetGUID()
	if type(UnitGUID) ~= "function" then return nil end
	local ok, guid = pcall(UnitGUID, "target")
	if ok and type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then
		return guid
	end
end

local function HasReadableCastID(arg3, arg4)
	return (type(arg3) == "number" and not (issecretvalue and issecretvalue(arg3)))
		or (type(arg4) == "number" and not (issecretvalue and issecretvalue(arg4)))
end

-- Identite LIKELY si les IDs sont secrets : memoriser uniquement une
-- suggestion autorisee par la rotation Warlock sur SENT (DoT ou mana).
-- SUCCEEDED doit confirmer ce meme lancement avant de creer un timer.
local function SuggestedWarlockSpell()
	if AL.playerClass ~= "WARLOCK" then return nil end
	local name = AL.lastSuggestion
	if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return nil end
	local rotation = AL.rotations and AL.rotations.WARLOCK
	if not rotation then return nil end
	local s = AL.S()
	if UTILITY_CURSES[name] then
		if rotation.SelectedCurse and rotation.SelectedCurse(s) == name then return name end
	elseif rotation.CanTrackSuggestedSpell and rotation.CanTrackSuggestedSpell(name, s) then
		return name
	end
end

local function WarlockManaHook(method, ...)
	local mod = (AL.playerClass == "WARLOCK" or AL.playerClass == "MAGE" or AL.playerClass == "SHAMAN") and AL.rotations and AL.rotations[AL.playerClass]
	if not mod or type(mod[method]) ~= "function" then return nil end
	local ok, result = pcall(mod[method], ...)
	if ok then return result end
end

local function ReadCastSpellID(arg3, arg4)
	if type(arg4) == "number" and not (issecretvalue and issecretvalue(arg4)) and arg4 > 0 then return arg4 end
	if type(arg3) == "number" and not (issecretvalue and issecretvalue(arg3)) and arg3 > 0 then return arg3 end
end

local function ComboRotationHook(method, ...)
	local mod = trackedRotationClass and AL.rotations and AL.rotations[AL.playerClass]
	if not mod or type(mod[method]) ~= "function" then return nil end
	local ok, result = pcall(mod[method], ...)
	if ok then return result end
end

local function SuggestedTrackedSpell()
	if AL.playerClass == "WARLOCK" then return SuggestedWarlockSpell() end
	local name = AL.lastSuggestion
	if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return nil end
	if ComboRotationHook("CanTrackSuggestedSpell", name) then return name end
end

local completedComboCasts = {}
local function FinishComboCast(guid)
	if not trackedRotationClass then return false end
	local now = GetTime()
	for saved, at in pairs(completedComboCasts) do
		if now - at >= 60 then completedComboCasts[saved] = nil end
	end
	if not guid then return false end
	if completedComboCasts[guid] then return true end
	completedComboCasts[guid] = now
	return false
end

local CAST_PENDING_WINDOW = 15
local targetEpoch = 0

local function CastMatches(sent, succeededGUID)
	if not sent or GetTime() - sent.t >= CAST_PENDING_WINDOW then return false end
	local guid = ReadCastGUID(succeededGUID)
	if sent.castGUID and guid and sent.castGUID ~= guid then return false end
	-- Sans GUID lisible aux deux bouts, limiter la supposition a cinq secondes.
	if (not sent.castGUID or not guid) and GetTime() - sent.t >= 5 then return false end
	return true
end

local function SentMatches(sent, succeededGUID)
	if not CastMatches(sent, succeededGUID) then return false end
	if sent.targetEpoch ~= targetEpoch then return false end
	local target = CastTargetGUID()
	if sent.targetGUID and target and sent.targetGUID ~= target then return false end
	return true
end

-- Sort en cours d'incantation du joueur, connu par UNIT_SPELLCAST_START meme si UnitCastingInfo est secret.
local casting
local function CastEnds()
	if type(UnitCastingInfo) ~= "function" then return nil end
	local ok, _, _, _, _, endMs = pcall(UnitCastingInfo, "player")
	if ok and type(endMs) == "number" and not (issecretvalue and issecretvalue(endMs)) then return endMs / 1000 end
end

-- name, secondsLeft of the player's current cast-time spell, or nil
function AL.CastingSpell()
	if not casting then return nil end
	local left = casting.ends - GetTime()
	if left < -0.3 then casting = nil return nil end
	return casting.name, math.max(0, left)
end

local lastSent
local pendingCasts = {}

-- Un sort peut etre mis en file pendant qu'un autre finit son incantation.
-- Garder leur contexte par GUID au lieu d'ecraser le lancement precedent.
local function PrunePendingCasts()
	local now = GetTime()
	for guid, sent in pairs(pendingCasts) do
		if now - sent.t >= CAST_PENDING_WINDOW then pendingCasts[guid] = nil end
	end
	if lastSent and now - lastSent.t >= CAST_PENDING_WINDOW then lastSent = nil end
end

local function ReadPlayerCastName()
	if type(UnitCastingInfo) ~= "function" then return nil end
	local ok, name = pcall(UnitCastingInfo, "player")
	if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
		return (AL.englishNames and AL.englishNames[name]) or name
	end
end

local function SentForCast(value)
	PrunePendingCasts()
	local guid = ReadCastGUID(value)
	if guid then
		if pendingCasts[guid] then return pendingCasts[guid] end
		if lastSent and not lastSent.castGUID then return lastSent end
		return nil
	end
	return lastSent
end

local function ForgetSent(sent)
	if not sent then return end
	if sent.castGUID then pendingCasts[sent.castGUID] = nil end
	if lastSent == sent then lastSent = nil end
end

local function ClearCastingFor(value)
	local guid = ReadCastGUID(value)
	if not casting or not guid or not casting.castGUID or casting.castGUID == guid then
		casting = nil
	end
end

debuffFrame:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
	if event == "UI_ERROR_MESSAGE" then
		-- old clients pass (message), new ones (messageType, message)
		local msg = type(arg2) == "string" and arg2 or (type(unit) == "string" and unit or nil)
		ComboRotationHook("OnUIError", msg)
		if msg and not (issecretvalue and issecretvalue(msg))
			and ERR_SPELL_UNLEARNED and msg == ERR_SPELL_UNLEARNED
			and AL.lastSuggestion and AL.known[AL.lastSuggestion] then
			AL.unlearned[AL.lastSuggestion] = true
			AL.known[AL.lastSuggestion] = nil
			AL.Say("|cffffcc00" .. AL.lastSuggestion .. "|r isn't trained yet - hiding it until you learn it")
			if AL.Log then AL.Log("cast", "warn", "hidden until learned: " .. AL.lastSuggestion, "client answered ERR_SPELL_UNLEARNED") end
		end
		return
	end
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if not CombatLogGetCurrentEventInfo then return end
		local ok, _, sub, _, srcGUID, _, _, _, destGUID, _, _, _, _, spellName, _, missType = pcall(CombatLogGetCurrentEventInfo)
		if not ok then return end
		if issecretvalue and (issecretvalue(sub) or issecretvalue(srcGUID) or issecretvalue(spellName) or issecretvalue(missType)) then return end
		if sub ~= "SPELL_MISSED" or type(spellName) ~= "string" then return end
		if AL.playerClass == "DRUID" or AL.playerClass == "HUNTER" or AL.playerClass == "SHAMAN" then spellName = (AL.englishNames and AL.englishNames[spellName]) or spellName end
		if srcGUID ~= UnitGUID("player") then return end
		-- ABSORB/BLOCK stop the damage but the aura still lands
		if missType == "ABSORB" or missType == "BLOCK" then return end
		local tguid = UnitGUID("target")
		if tguid and not (issecretvalue and issecretvalue(destGUID)) and destGUID ~= tguid then return end
		local restored = AL.RestoreComboPointsOnMiss(spellName)
		if AL.Log then
			AL.Log("combat", "info", "miss: " .. spellName .. " (" .. tostring(missType) .. ")", {
				comboRestored = restored, comboNow = inferredCp, debuffTimerCleared = targetDebuffs[spellName] ~= nil,
			})
		end
		if targetDebuffs[spellName] then
			targetDebuffs[spellName] = nil
			if ActionLiteDB and ActionLiteDB.debug then
				pcall(print, "|cff89cff0AL miss|r " .. spellName .. " (" .. tostring(missType) .. ") - will reapply")
			end
		end
		return
	end
	if event == "PLAYER_TARGET_CHANGED" then
		ComboRotationHook("OnTargetChanged")
		if trackedCastClass then
			targetEpoch = targetEpoch + 1
			PrunePendingCasts()
		end
		wipe(targetDebuffs)
		SweepTargetDebuffs()
		-- combo points are per-target in vanilla
		AL.ResetComboPoints()
		return
	end
	if event == "UNIT_AURA" then
		if unit == "target" then
			SweepTargetDebuffs()
		elseif unit == "player" then
			SweepBuffs()
			SweepPlayerDebuffs()
		else
			SweepBuffs()
		end
		return
	end
	if event == "PLAYER_DEAD" then
		ComboRotationHook("OnTargetChanged")
		wipe(rogueBuffGrace)
		if AL.playerClass == "PALADIN" then
			paladinSealAuras, paladinSealAurasValid = {}, false
			for name in pairs(PALADIN_SEALS) do tooltipBuffs[name] = nil end
		end
		if trackedCastClass then
			lastSent, casting = nil, nil
			wipe(pendingCasts)
		end
		wipe(selfBuffs)
		wipe(playerDebuffs)
		wipe(tooltipPlayerDebuffs)
		AL.ResetComboPoints()
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		WarlockManaHook("RefreshManaCache")
		-- last-chance snapshot before combat blocks reads
		SweepBuffs()
		SweepPlayerDebuffs()
		-- combat breaks stealth and interrupts eating/drinking
		selfBuffs["Stealth"] = nil
		rogueBuffGrace["Stealth"] = nil
		selfBuffs["Food"] = nil
		selfBuffs["Drink"] = nil
		return
	end
	if (issecretvalue and issecretvalue(unit)) or unit ~= "player" then return end
	local name, sent, matches, inferred
	if trackedCastClass then
		if event == "UNIT_SPELLCAST_SENT" then
			local name = EnglishCastName(arg2, arg3, arg4)
			local inferred = false
			if not name and not HasReadableCastID(arg3, arg4) then
				name = SuggestedTrackedSpell()
				inferred = name ~= nil
			end
			PrunePendingCasts()
			lastSent = {
				name = name, t = GetTime(), castGUID = ReadCastGUID(arg3),
				spellID = ReadCastSpellID(arg3, arg4),
				targetGUID = CastTargetGUID(), targetEpoch = targetEpoch, inferred = inferred,
			}
			if trackedComboClass then
				lastSent.comboBefore = AL.ComboPoints()
				if name == "Slice and Dice" then RefreshRogueSliceDurations() end
			end
			if AL.playerClass == "HUNTER" then ComboRotationHook("OnCastSent", name, lastSent) end
			lastSent.mana = WarlockManaHook("OnManaCastSent", name, lastSent.spellID)
			if lastSent and lastSent.castGUID then pendingCasts[lastSent.castGUID] = lastSent end
			return
		end
		if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
			local sent, guid = SentForCast(arg2), ReadCastGUID(arg2)
			local actual = EnglishCastName(arg2, arg3, arg4) or ReadPlayerCastName()
			local n = actual or (sent and sent.name)
				or (casting and (not guid or casting.castGUID == guid) and casting.name)
			-- Une identite lisible corrige la supposition memorisee sur SENT.
			if sent and actual then sent.name, sent.inferred = actual, false end
			-- LIKELY: 3 s when the end time is secret; STOP/SUCCEEDED clear it sooner
			if n then casting = { name = n, castGUID = guid, ends = CastEnds() or GetTime() + 3 } end
			return
		end
		if event == "UNIT_SPELLCAST_STOP" then
			ClearCastingFor(arg2)
			return
		end
		-- a failed attempt (out of range etc.) must not be blamed for a later success
		if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
			or event == "UNIT_SPELLCAST_INTERRUPTED"
		then
			local sent = SentForCast(arg2)
			FinishComboCast(ReadCastGUID(arg2))
			ComboRotationHook("OnCastResult", EnglishCastName(arg2, arg3, arg4) or (sent and sent.name), event, sent)
			ForgetSent(sent)
			ClearCastingFor(arg2)
			return
		end
		if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
		if FinishComboCast(ReadCastGUID(arg2)) then return end
		ClearCastingFor(arg2)
		name = EnglishCastName(arg2, arg3, arg4)
		sent, inferred = SentForCast(arg2), false
		matches = SentMatches(sent, arg2)
		local castMatches = CastMatches(sent, arg2)
		-- A readable identity wins over the saved recommendation. Do not infer an
		-- unrelated readable spell ID or a different cast GUID. Target timers below
		-- also require the target to match; player mana does not depend on the target.
		if not name and castMatches and (not sent.inferred or not HasReadableCastID(arg3, arg4)) then
			name, inferred = sent.name, sent.inferred
		end
		-- Mana belongs to the player even when the target changed during the cast.
		-- Target debuff timers below still require the original target to match.
		WarlockManaHook("OnManaCastSucceeded", name, ReadCastSpellID(arg3, arg4),
			ReadCastGUID(arg2), castMatches and sent or nil)
		ComboRotationHook("OnCastResult", name, event, castMatches and sent or nil)
		ForgetSent(sent)
	else
		if event == "UNIT_SPELLCAST_SENT" then
			local n = LegacyCastName(arg2, arg3, arg4)
			if n then legacyLastSent = { name = n, t = GetTime() } end
			return
		end
		-- a failed attempt (out of range etc.) must not be blamed for a later success
		if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
			legacyLastSent = nil
			return
		end
		name = LegacyCastName(arg2, arg3, arg4)
		-- SUCCEEDED payload unreadable (secret spellID): trust the last SENT name once
		if not name and legacyLastSent and GetTime() - legacyLastSent.t < 5 then name = legacyLastSent.name end
		legacyLastSent = nil
	end
	if ActionLiteDB and ActionLiteDB.debug then
		pcall(print, "|cff89cff0AL cast|r name=" .. tostring(name) .. " arg2=" .. tostring(arg2) .. " arg3=" .. tostring(arg3))
	end
	if not name then return end
	AL.PopQueue(name)
	local spentCombo
	if trackedComboClass and sent and not matches then
		-- An old-target builder cannot grant points on the new target. A
		-- self buff can still use the points saved before that old cast.
		spentCombo = CP_FINISHERS[name] and sent.comboBefore or nil
	else
		spentCombo = AL.TrackComboCast(name)
	end
	local cd = SPELL_COOLDOWNS[name]
	-- LIKELY Forever fallback: the player reported Holy Strike roughly four
	-- seconds early with the old six-second timer. Readable cooldowns win.
	if AL.playerClass == "PALADIN" and name == "Holy Strike" then cd = 10 end
	if cd then
		cdExpires[name] = time() + cd
		if preciseCooldownClass then
			preciseCooldowns[name] = { ends = GetTime() + cd, epoch = cdExpires[name] }
		end
	end
	local buffName, sdur = name, SELF_BUFF_DURATIONS[name]
	if AL.playerClass == "PALADIN" and PALADIN_SEALS[name] then sdur = paladinSealDurations[name] or sdur end
	local alias = CAST_BUFF_ALIASES[name]
	if alias then buffName, sdur = alias[1], alias[2] end
	-- Repli LIKELY lorsque Forever protege les auras : les durees classiques
	-- varient avec les points depenses. Un tooltip lisible reste prioritaire.
	if name == "Slice and Dice" and AL.playerClass == "ROGUE" then
		local points = math.max(1, math.min(5, spentCombo or 1))
		sdur = rogueSliceDurations[points] or (6 + 3 * points)
	elseif name == "Slice and Dice" and spentCombo and spentCombo > 0 then
		sdur = 6 + 3 * spentCombo
	end
	-- NOTE: on WoW Forever, Judgement does NOT consume the seal - don't clear it
	if sdur then
		local group = groupOf[buffName]
		if group then for _, m in ipairs(group) do selfBuffs[m] = nil end end
		selfBuffs[buffName] = time() + sdur
		if AL.playerClass == "PALADIN" and PALADIN_SEALS[buffName] then
			paladinSealAuras = { [buffName] = true }
		end
		if AL.playerClass == "DRUID" or AL.playerClass == "HUNTER" or AL.playerClass == "PALADIN" or AL.playerClass == "MAGE" or AL.playerClass == "SHAMAN" or (AL.playerClass == "ROGUE" and (buffName == "Slice and Dice" or buffName == "Stealth")) then
			rogueBuffGrace[buffName] = GetTime() + 0.5
			if buffName == "Slice and Dice" then selfBuffs[buffName] = RogueBuffExpiration(buffName) or selfBuffs[buffName] end
		end
	end
	if name == "Power Word: Shield" then
		playerDebuffs["Weakened Soul"] = { expires = GetTime() + 15, source = "CAST" }
	end
	if AL.playerClass == "DRUID" and (name == "Claw" or name == "Rake" or name == "Shred") then
		selfBuffs["Prowl"], tooltipBuffs["Prowl"], rogueBuffGrace["Prowl"] = nil, nil, nil
	end
	if STEALTH_BREAKERS[name] then
		selfBuffs["Stealth"] = nil
		tooltipBuffs["Stealth"] = nil
	end
	local dur = DEBUFF_DURATIONS[name]
	if name == "Rupture" and spentCombo and spentCombo > 0 then
		dur = 6 + 2 * spentCombo
	end
	if dur and UnitExists("target") and (not trackedCastClass or not sent or matches) then
		if AL.playerClass == "WARLOCK" and UTILITY_CURSES[name] then
			for curse in pairs(UTILITY_CURSES) do targetDebuffs[curse] = nil end
		end
		if AL.playerClass == "HUNTER" and (name == "Serpent Sting" or name == "Scorpid Sting") then
			targetDebuffs["Serpent Sting"], targetDebuffs["Scorpid Sting"] = nil, nil
		end
		targetDebuffs[name] = { stacks = 1, source = inferred and "CAST_INFERRED" or "CAST", expires = GetTime() + dur }
		if AL.playerClass == "DRUID" or AL.playerClass == "HUNTER" or AL.playerClass == "MAGE" or AL.playerClass == "SHAMAN" then targetDebuffs[name].appliedAt = GetTime() end
		if trackedCastClass then targetDebuffs[name].targetGUID = CastTargetGUID() end
	end
	if AL.Log then
		AL.Log("cast", "debug", "inferred from " .. name, {
			cooldown = cd, selfBuff = sdur and buffName, selfBuffSeconds = sdur,
			debuffSeconds = dur, comboNow = inferredCp, comboSpent = spentCombo,
		})
	end
end)

local sweepTick, snapTick = 0, 0
debuffFrame:SetScript("OnUpdate", function(_, dt)
	-- snapshot aggressively: the last readable sweep is what combat runs on
	snapTick = snapTick + dt
	if snapTick >= 0.1 then
		snapTick = 0
		SweepBuffs()
		SweepPlayerDebuffs()
		SweepTargetDebuffs()
	end
	sweepTick = sweepTick + dt
	if sweepTick < 1 then return end
	sweepTick = 0
	if trackedCastClass then PrunePendingCasts() end
	local now = GetTime()
	for name, d in pairs(targetDebuffs) do
		if d.expires and d.expires <= now then targetDebuffs[name] = nil end
	end
	for name, d in pairs(playerDebuffs) do
		if type(d) == "table" and d.expires and d.expires <= now then playerDebuffs[name] = nil end
	end
	local nowEpoch = time()
	for name, exp in pairs(selfBuffs) do
		if exp <= nowEpoch then selfBuffs[name] = nil end
	end
	for name, exp in pairs(cdExpires) do
		local precise = preciseCooldownClass and preciseCooldowns[name]
		if exp <= nowEpoch and not (precise and precise.epoch == exp and precise.ends > now) then
			cdExpires[name], preciseCooldowns[name] = nil, nil
		end
	end
end)

function AL.HasDebuff(unit, name)
	if unit ~= "target" then return false end
	local recent = (AL.playerClass == "DRUID" or AL.playerClass == "HUNTER" or AL.playerClass == "MAGE" or AL.playerClass == "SHAMAN") and targetDebuffs[name]
	if recent and recent.appliedAt and GetTime() - recent.appliedAt < 0.5 then return true end
	if debuffValid then return tooltipDebuffs[name] == true end
	-- tooltip sweep blocked: fall back to cast-inferred debuff timers
	if trackedCastClass then
		local d = targetDebuffs[name]
		return d ~= nil and (not d.expires or d.expires > GetTime())
	end
	return targetDebuffs[name] ~= nil
end

-- Live references for the debug console; callers must only read them.
function AL.DebugState()
	return {
		tooltipValid = tooltipValid, tooltipBuffs = tooltipBuffs, selfBuffs = selfBuffs,
		playerDebuffValid = playerDebuffValid, tooltipPlayerDebuffs = tooltipPlayerDebuffs, playerDebuffs = playerDebuffs,
		debuffValid = debuffValid, tooltipDebuffs = tooltipDebuffs, targetDebuffs = targetDebuffs,
		cdExpires = cdExpires, inferredCp = inferredCp,
	}
end

-- Diagnostics-only arbitrary-unit aura visibility probe used by Debug.lua.
function AL.DebugUnitAuraState(unit)
	local result = {
		unit = unit, exists = false,
		tooltipValid = false, tooltipBuffs = {},
		unitBuffAvailable = type(UnitBuff) == "function", unitBuffReadable = nil, unitBuffSecret = false, unitBuffs = {},
		cUnitAurasAvailable = C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" or false,
		cUnitAurasReadable = nil, cUnitAurasSecret = false, cUnitAurasBuffs = {},
	}
	if type(unit) ~= "string" or unit == "" then result.error = "invalid unit" return result end
	local okExists, exists = pcall(UnitExists, unit)
	if not okExists then result.error = "UnitExists error" return result end
	if issecretvalue and issecretvalue(exists) then result.existsSecret = true return result end
	result.exists = exists and true or false
	if not result.exists then return result end

	local tip = {}
	local okTip, valid = pcall(SweepAuras, unit, false, tip)
	if okTip then
		result.tooltipValid = valid and true or false
		if valid then for name in pairs(tip) do result.tooltipBuffs[name] = true end end
	else
		result.tooltipError = tostring(valid)
	end

	if result.unitBuffAvailable then
		result.unitBuffReadable = true
		for i = 1, 40 do
			local ok, name = pcall(UnitBuff, unit, i)
			if not ok then result.unitBuffReadable = false; result.unitBuffError = tostring(name); break end
			if name ~= nil and issecretvalue and issecretvalue(name) then result.unitBuffReadable = false; result.unitBuffSecret = true; break end
			if not name or name == "" then break end
			result.unitBuffs[name] = true
		end
	end

	if result.cUnitAurasAvailable then
		result.cUnitAurasReadable = true
		for i = 1, 40 do
			local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
			if not ok then result.cUnitAurasReadable = false; result.cUnitAurasError = tostring(data); break end
			if data == nil then break end
			if issecretvalue and issecretvalue(data) then result.cUnitAurasReadable = false; result.cUnitAurasSecret = true; break end
			local name = type(data) == "table" and data.name or nil
			if name ~= nil and issecretvalue and issecretvalue(name) then result.cUnitAurasReadable = false; result.cUnitAurasSecret = true; break end
			if type(name) == "string" and name ~= "" then result.cUnitAurasBuffs[name] = true end
		end
	end
	return result
end

function AL.IsReady(spell)
	local start, duration = AL.SpellCooldown(spell)
	if preciseCooldownClass then
		local function Finite(value)
			return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
				and value == value and value > -math.huge and value < math.huge
		end
		if Finite(start) and Finite(duration) and start >= 0 and duration >= 0 then
			return start == 0 or duration <= 1.5 or start + duration <= GetTime()
		end
		local expiration = cdExpires[spell]
		local precise = preciseCooldowns[spell]
		if precise and precise.epoch == expiration then return precise.ends <= GetTime() end
		return not expiration or expiration <= time()
	end
	if start and not (issecretvalue and (issecretvalue(start) or issecretvalue(duration))) then
		-- duration <= 1.5 is just the GCD
		return start == 0 or duration <= 1.5 or (start + duration - GetTime()) <= 0.2
	end
	-- blocked/secret cooldown read: fall back to cast-inferred timers
	local exp = cdExpires[spell]
	return not exp or exp - time() <= 0.2
end

-- Spellbook scan: casting by name always uses the highest known rank.
-- Gaps happen (secret/hidden slots), so keep scanning past empty entries
-- instead of stopping at the first one - that silently lost every later spell.
AL.known = {}
-- spells the client listed in the book but rejected with "not learned" on cast
AL.unlearned = {}
-- Highest learned rank by spell name, rebuilt with the spellbook. Display.lua
-- uses it to render red out of range and normal color once the cast is in range.
AL.rangeSpellRefs = AL.rangeSpellRefs or {}
if trackedCastClass then
	AL.castSpellNamesByID, AL.localNames, AL.englishNames = {}, {}, {}
end

-- The book lists spells before they're trainable; those slots report FUTURESPELL
local function BookItemIsFuture(i)
	if GetSpellBookItemInfo then
		local kind = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
		return kind == "FUTURESPELL"
	end
	if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
		local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
		return info and Enum.SpellBookItemType and info.itemType == Enum.SpellBookItemType.FutureSpell
	end
	return false
end

-- untrained spellbook entries, read by Trainer.lua
AL.futureSpells = {}

function AL.ScanSpellbook()
	wipe(AL.known)
	wipe(AL.rangeSpellRefs)
	wipe(AL.futureSpells)
	if trackedCastClass then wipe(AL.castSpellNamesByID) end
	local i, misses = 1, 0
	while misses < 40 and i <= 2048 do
		local ok, name = pcall(BookItemName, i)
		if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" then
			local okF, future = pcall(BookItemIsFuture, i)
			if okF and future == true then
				local okID, spellID = pcall(BookItemSpellID, i)
				AL.futureSpells[#AL.futureSpells + 1] = { name = name, index = i, id = okID and spellID or nil }
			elseif not AL.unlearned[name] then
				AL.known[name] = true
				local okID, spellID = pcall(BookItemSpellID, i)
				if trackedCastClass and okID and type(spellID) == "number"
					and not (issecretvalue and issecretvalue(spellID)) then
					AL.castSpellNamesByID[spellID] = name
				end
				local legacyIndex = type(GetSpellBookItemName) == "function" and i or nil
				if legacyIndex or (okID and spellID) then
					AL.rangeSpellRefs[name] = {
						id = okID and spellID or nil,
						index = legacyIndex,
					}
				end
			end
			misses = 0
		else
			misses = misses + 1
		end
		i = i + 1
	end
	if trackedCastClass then
		-- non-English clients list localized names; map them back through the rotation's IDs
		wipe(AL.localNames)
		wipe(AL.englishNames)
		local mod = AL.rotations[AL.playerClass]
		for _, entry in ipairs(mod and mod.spells or {}) do
			local id, english = entry[1], entry[2]
			if type(id) == "number" and type(english) == "string" and not AL.known[english] then
				local ok, loc = pcall(AL.SpellName, id)
				if ok and type(loc) == "string" and not (issecretvalue and issecretvalue(loc)) and AL.known[loc] then
					AL.known[english] = true
					AL.rangeSpellRefs[english] = AL.rangeSpellRefs[loc]
					AL.localNames[english], AL.englishNames[loc] = loc, english
				end
			end
			-- Les IDs de base declares par la rotation servent de repli pour un
			-- sort confirme appris, sans remplacer une identite lue dans le livre.
			if type(id) == "number" and id > 0 and AL.known[english] and not AL.castSpellNamesByID[id] then
				AL.castSpellNamesByID[id] = english
			end
		end
		WarlockManaHook("RefreshManaCache")
		RefreshRogueSliceDurations()
	end
end

function AL.TargetInMelee()
	local ok, r = pcall(CheckInteractDistance, "target", 3)
	return ok and r
end

-- Any active player channel is normally a deliberate wait state. Drain Soul
-- gets a short visual grace period so the recommendation remains on Drain Soul
-- for the first second of the channel, then changes to the no-action/pooling
-- icon for the remainder.
local channelSeenAt = nil
local channelSeenName = nil
local DRAIN_SOUL_CHANNEL_GRACE = 1.0

function AL.PlayerChanneling()
	if type(UnitChannelInfo) ~= "function" then
		channelSeenAt, channelSeenName = nil, nil
		return false, nil, false
	end

	local ok, name = pcall(UnitChannelInfo, "player")
	if not ok then
		channelSeenAt, channelSeenName = nil, nil
		return false, nil, false
	end

	local active = false
	local readableName = nil

	if issecretvalue and issecretvalue(name) then
		-- Secretized name still proves that a channel exists. If Drain Soul was
		-- the last recommendation, use that only to identify this grace window.
		active = true
		if AL.lastSuggestion == "Drain Soul" then readableName = "Drain Soul" end
	elseif type(name) == "string" and name ~= "" then
		active = true
		readableName = name
	end

	if not active then
		channelSeenAt, channelSeenName = nil, nil
		return false, nil, false
	end

	local now = GetTime and GetTime() or 0
	local effectiveName = readableName or channelSeenName

	-- New channel: start its timer once. Do not restart it every display tick.
	if channelSeenAt == nil or (readableName and channelSeenName ~= readableName) then
		channelSeenAt = now
		channelSeenName = readableName
	elseif readableName and not channelSeenName then
		channelSeenName = readableName
	end

	effectiveName = readableName or channelSeenName

	if effectiveName == "Drain Soul"
		and type(now) == "number"
		and type(channelSeenAt) == "number"
		and (now - channelSeenAt) < DRAIN_SOUL_CHANNEL_GRACE
	then
		return true, "Drain Soul", true
	end

	return true, effectiveName, false
end

function AL.Paused(s)
	if s.p_dead and UnitIsDeadOrGhost("player") then return true end
	if s.p_mounted and IsMounted and IsMounted() then return true end
	if s.p_targeting and SpellIsTargeting and SpellIsTargeting() then return true end
	if s.p_vehicle and UnitInVehicle then
		local ok, v = pcall(UnitInVehicle, "player")
		if ok and v then return true end
	end
	if s.p_loot and LootFrame and LootFrame:IsShown() then return true end
	if s.p_eating and (AL.HasBuff("player", "Food") or AL.HasBuff("player", "Drink")) then return true end
	if s.p_ooc and not UnitAffectingCombat("player") then return true end
	return false
end

-- Returns spell name, reason
function AL.NextSpell()
	local s = AL.S()
	if AL.Paused(s) then return nil, "Ready" end

	-- Pool/no-action while a player channel is active. Drain Soul gets a
	-- one-second grace window: keep its icon/glow visible for that first second,
	-- then switch to the existing pooling icon until the channel ends.
	local channeling, channelName, channelGrace = AL.PlayerChanneling()
	if channeling then
		if channelGrace and channelName == "Drain Soul" then
			return "Drain Soul", "channel start"
		end
		return nil, "Channeling"
	end

	AL.PruneQueue()
	while AL.queue[1] do
		local q = AL.queue[1].spell
		if AL.known[q] then
			local extra = #AL.queue > 1 and (" (+" .. (#AL.queue - 1) .. ")") or ""
			return q, "queued" .. extra
		end
		table.remove(AL.queue, 1)
	end
	local mod = AL.rotations[AL.playerClass]
	if not mod or not mod.NextSpell then return nil, "Ready" end
	local inCombat = UnitAffectingCombat("player")
	local hostile = UnitExists("target") and UnitCanAttack("player", "target")
		and not (s.p_targetdead and UnitIsDeadOrGhost("target"))
	return mod.NextSpell(s, inCombat, hostile)
end
