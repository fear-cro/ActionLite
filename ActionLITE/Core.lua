local ADDON, AL = ...
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
AL.buildId = "1.1.6-20261105"

AL.playerClass = select(2, UnitClass("player"))
local trackedComboClass = AL.playerClass == "ROGUE" or AL.playerClass == "DRUID"
local trackedRotationClass = trackedComboClass or AL.playerClass == "HUNTER" or AL.playerClass == "PALADIN" or AL.playerClass == "MAGE" or AL.playerClass == "SHAMAN"
local trackedCastClass = AL.playerClass == "WARLOCK" or trackedRotationClass
local preciseCooldownClass = AL.playerClass == "PALADIN" or AL.playerClass == "MAGE" or AL.playerClass == "SHAMAN" or AL.playerClass == "PRIEST"
AL.CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
AL.BABY_R, AL.BABY_G, AL.BABY_B = 0.38, 0.67, 0.96
AL.WHITE = "Interface\\Buttons\\WHITE8X8"

AL.defaults = {
	scale = 1, nobg = false,
	p_targeting = true, p_vehicle = true, p_mounted = true, p_ooc = false,
	p_loot = true, p_dead = true, p_targetdead = true, p_eating = true,
	noprint = false, norange = false,
	healingEngine = false, healingInitiateHP = 80, healingEmergencyHP = 30,
}

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- The public role selector is shared by the class menu, the HUD buttons and
-- the HealingEngine.  Keep one saved boolean true so old code and debug
-- reports can inspect the choice without parsing a display label.
local ROLE_MODE_SUPPORT = {
	DRUID   = { DPS = true, HEAL = true, TANK = true },
	PALADIN = { DPS = true, HEAL = true, TANK = true },
	PRIEST  = { DPS = true, HEAL = true },
	SHAMAN  = { DPS = true, HEAL = true },
	WARRIOR = { DPS = true, TANK = true },
	HUNTER  = { DPS = true }, ROGUE = { DPS = true },
	MAGE    = { DPS = true }, WARLOCK = { DPS = true },
}

local function PublicRoleMode(value)
	if issecretvalue and issecretvalue(value) then return nil end
	if type(value) ~= "string" then return nil end
	value = value:upper()
	if value == "HEALS" or value == "HEALER" then value = "HEAL" end
	if value == "DAMAGER" then value = "DPS" end
	if value == "DPS" or value == "HEAL" or value == "TANK" then return value end
end

function AL.RoleModeSupported(token, mode)
	token = type(token) == "string" and token:upper() or AL.playerClass
	mode = PublicRoleMode(mode)
	return mode ~= nil and ROLE_MODE_SUPPORT[token] and ROLE_MODE_SUPPORT[token][mode] == true or false
end

local function LegacyRoleMode(profile, token)
	if type(profile) ~= "table" then return nil end
	if profile.healingEngine == true and AL.RoleModeSupported(token, "HEAL") then return "HEAL" end
	if token == "PALADIN" then
		local value = profile.levelingPaladinRole or profile.paladinRole
		if not (issecretvalue and issecretvalue(value)) and value == "TANK" then return "TANK" end
	elseif token == "WARRIOR" then
		local value = profile.levelingWarriorRole or profile.warriorRole
		if not (issecretvalue and issecretvalue(value)) and value == "TANK" then return "TANK" end
	end
end

local function SyncLegacyRole(profile, token, mode)
	-- HEAL is the sole owner of the old HealingEngine gate.  This avoids a
	-- selected Heal mode whose provider is silently disabled, or DPS/Tank mode
	-- unexpectedly emitting friendly focus pixels from an old saved setting.
	profile.healingEngine = mode == "HEAL"
	if token == "PALADIN" then
		local legacy = mode == "TANK" and "TANK" or "DPS"
		profile.paladinRole = legacy
		profile.levelingPaladinRole = legacy
		profile.paladinRoleBuild = "leveling"
	elseif token == "WARRIOR" then
		local legacy = mode == "TANK" and "TANK" or "DPS"
		profile.warriorRole = legacy
		profile.levelingWarriorRole = legacy
		profile.warriorRoleBuild = "leveling"
	end
end

local function ApplyRoleMode(profile, token, mode, userInitiated)
	if type(profile) ~= "table" or not AL.RoleModeSupported(token, mode) then return nil end
	mode = PublicRoleMode(mode)
	profile.roleDPS = mode == "DPS"
	profile.roleHeals = mode == "HEAL"
	profile.roleTank = mode == "TANK"
	profile.rotationMode = mode
	if userInitiated ~= nil then profile.roleSelectionManual = userInitiated == true end
	SyncLegacyRole(profile, token, mode)
	return mode
end

function AL.GetRotationMode(profile, token)
	token = type(token) == "string" and token:upper() or AL.playerClass
	if type(profile) ~= "table" then
		profile = type(AL.Profile) == "function" and AL.Profile(token) or AL.defaults
	end
	if type(profile) ~= "table" then return "DPS" end

	local selected
	if not (issecretvalue and issecretvalue(profile.roleTank)) and profile.roleTank == true
		and AL.RoleModeSupported(token, "TANK") then selected = "TANK" end
	if not selected and not (issecretvalue and issecretvalue(profile.roleHeals)) and profile.roleHeals == true
		and AL.RoleModeSupported(token, "HEAL") then selected = "HEAL" end
	if not selected and not (issecretvalue and issecretvalue(profile.roleDPS)) and profile.roleDPS == true then
		selected = "DPS"
	end
	if not selected then
		-- One-time migration preserves an explicitly enabled legacy HealingEngine
		-- or Leveling Tank role.  Fresh and ambiguous profiles default to DPS.
		selected = LegacyRoleMode(profile, token) or "DPS"
		if profile.roleSelectionManual == nil then
			profile.roleSelectionManual = selected ~= "DPS"
		end
	end
	return ApplyRoleMode(profile, token, selected, nil) or "DPS"
end

function AL.SetRotationMode(mode, userInitiated, profile, token)
	token = type(token) == "string" and token:upper() or AL.playerClass
	mode = PublicRoleMode(mode)
	if not mode or not AL.RoleModeSupported(token, mode) then return nil end
	if type(profile) ~= "table" then
		profile = type(AL.Profile) == "function" and AL.Profile(token) or AL.defaults
	end
	local selected = ApplyRoleMode(profile, token, mode, userInitiated == true)
	if selected and AL.UI and type(AL.UI.Repaint) == "function" then AL.UI.Repaint() end
	if selected and type(AL.ApplyToggles) == "function" then AL.ApplyToggles() end
	return selected
end

local function PublicAssignedRole()
	if type(UnitGroupRolesAssigned) ~= "function" then return nil end
	local ok, role = pcall(UnitGroupRolesAssigned, "player")
	if not ok or (issecretvalue and issecretvalue(role)) or type(role) ~= "string" then return nil end
	if role == "HEALER" then return "HEAL" end
	if role == "TANK" or role == "DAMAGER" or role == "NONE" then return role == "DAMAGER" and "DPS" or role end
end

local function PublicNonRaidGroup()
	if type(IsInRaid) == "function" then
		local raid = AL.SafeBoolean and AL.SafeBoolean(IsInRaid)
		if raid == true then return false end
		if raid == nil then return nil end
	end
	local grouped = type(IsInGroup) == "function" and AL.SafeBoolean and AL.SafeBoolean(IsInGroup) or nil
	local count
	if type(GetNumGroupMembers) == "function" then
		local ok, value = pcall(GetNumGroupMembers)
		if ok and not (issecretvalue and issecretvalue(value)) and type(value) == "number" then count = value end
	end
	if grouped == false or count == 0 then return false end
	if grouped == true or count and count >= 2 and count <= 5 then return true end
	return nil
end

function AL.RefreshAutomaticRotationMode(profile, token)
	token = type(token) == "string" and token:upper() or AL.playerClass
	if type(profile) ~= "table" then
		profile = type(AL.Profile) == "function" and AL.Profile(token) or nil
	end
	if type(profile) ~= "table" then return nil end
	if profile.roleSelectionManual == true then return AL.GetRotationMode(profile, token) end
	local previous = PublicRoleMode(profile.rotationMode)
	local function ApplyAutomatic(mode)
		local selected = ApplyRoleMode(profile, token, mode, false)
		if selected and selected ~= previous then
			if AL.UI and type(AL.UI.Repaint) == "function" then AL.UI.Repaint() end
			if type(AL.ApplyToggles) == "function" then AL.ApplyToggles() end
		end
		return selected
	end
	local grouped = PublicNonRaidGroup()
	if grouped == nil then return AL.GetRotationMode(profile, token) end
	if grouped == false then return ApplyAutomatic("DPS") end
	local assigned = PublicAssignedRole()
	if assigned == nil then return AL.GetRotationMode(profile, token) end
	if assigned == "HEAL" and AL.RoleModeSupported(token, "HEAL") then
		return ApplyAutomatic("HEAL")
	end
	if assigned == "TANK" and AL.RoleModeSupported(token, "TANK") then
		return ApplyAutomatic("TANK")
	end
	return ApplyAutomatic("DPS")
end

-- Compatibility aliases retained for modules developed against the first
-- role-mode draft.  New code should use the RotationMode names above.
AL.GetRotationRole = AL.GetRotationMode
AL.SetRotationRole = AL.SetRotationMode
AL.SupportsRotationRole = function(mode, token) return AL.RoleModeSupported(token, mode) end

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- Forever can return secret booleans from otherwise ordinary unit APIs while
-- combat execution is tainted.  All shared state checks normalize those values
-- to nil so callers can fail closed without attempting a Lua boolean test.
function AL.SafeBoolean(func, ...)
	if type(func) ~= "function" then return nil end
	local ok, value = pcall(func, ...)
	if not ok or (issecretvalue and issecretvalue(value)) then return nil end
	if value == true or value == 1 then return true end
	if value == false or value == 0 then return false end
	return nil
end

AL.burst = false
-- global so the "/run ActionLite_Burst()" macro can reach it
function ActionLite_Burst()
	AL.burst = not AL.burst
	if AL.ApplyToggles then AL.ApplyToggles() end
end

-- spell queue: queued entries override the rotation on the icon until cast
AL.queue = {}
local QUEUE_TIMEOUT = 20

-- toggles: queuing an already-queued spell removes it instead
function ActionLite_Queue(spell)
	if type(spell) ~= "string" or spell == "" then return end
	if issecretvalue and issecretvalue(spell) then return end
	spell = (AL.englishNames and AL.englishNames[spell]) or spell
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
	if issecretvalue and issecretvalue(castName) then return end
	castName = (AL.englishNames and AL.englishNames[castName]) or castName
	for i, q in ipairs(AL.queue) do
		if q.spell == castName then
			table.remove(AL.queue, i)
			return
		end
	end
end

-- Class rotations live in rotation\<Class>.lua and register themselves here
AL.rotations = {}
-- Corrected default artwork is shared by menu controls and recommendation
-- displays. Saved Universal assignments still take priority during combat.
AL.SpellTextureOverrides = {
	DRUID = { ["Lifebloom"] = 134206 },
	PALADIN = {
		["Blessing of Kings"] = 135995,
		["Greater Blessing of Kings"] = 135995,
		-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
		-- Blessing of Light was removed; only live Paladin blessings retain overrides.
		["Blessing of Might"] = 135906,
		["Blessing of Wisdom"] = 135970,
	},
	PRIEST = {
		["Devouring Plague"] = 136123,
		["Power Word: Fortitude"] = 135987,
		["Vampiric Touch"] = 135978,
	},
	ROGUE = { ["Mutilate"] = 132304 },
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Keep the corrected native artwork on the renamed live utility spell.
	SHAMAN = { ["Totemic Call"] = 310733 },
	WARLOCK = { ["Curse of the Elements"] = 136130 },
	WARRIOR = { ["Raging Blow"] = 132215, ["Victory Rush"] = 132342 },
}
local fixedTextures, fixedTexturesByID = {}, {}
for _, spells in pairs(AL.SpellTextureOverrides) do
	for name, texture in pairs(spells) do fixedTextures[name] = texture end
end

function AL.RegisterRotation(token, module)
	AL.rotations[token] = module
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Retire saved level-60 selections as soon as the final class module is
	-- registered. Rotation event frames cannot observe an old spec flag before
	-- the first UI paint or recommendation tick. Brand-new profiles still use
	-- the module defaults when the database is initialized later.
	local saved = type(ActionLiteDB) == "table" and type(ActionLiteDB.profiles) == "table"
		and ActionLiteDB.profiles[token] or nil
	if type(saved) == "table" and type(AL.GetRotationMode) == "function" then
		AL.GetRotationMode(saved, token)
	end
	if type(saved) == "table" and type(module.NormalizeBuild) == "function" then
		pcall(module.NormalizeBuild, saved)
	end
	-- Keep listed spells available for artwork selection and manual queues.
	-- Zero is an unresolved reference: ScanSpellbook replaces it only after
	-- the live book confirms a learned spell, never with an invented spell ID.
	local entries = module.spells
	if type(entries) ~= "table" then return end
	for name, texture in pairs(AL.SpellTextureOverrides[token] or {}) do
		local found
		for _, entry in ipairs(entries) do
			if entry[2] == name then
				found = true
				if type(entry[1]) == "number" and entry[1] > 0 then fixedTexturesByID[entry[1]] = texture end
				break
			end
		end
		if not found then entries[#entries + 1] = { 0, name } end
	end
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
	if AL.HealingEngine and AL.HealingEngine.NormalizeProfile then
		AL.HealingEngine:NormalizeProfile(p)
	end
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Migrate legacy Healing/Tank settings once, then keep the three public role
	-- checkboxes mutually exclusive for every profile, including inactive ones.
	if type(AL.GetRotationMode) == "function" then AL.GetRotationMode(p, token) end
	p.spells = p.spells or {}
	p.version = p.version or "1.0"
	if AL.NormalizeIconAssignments then AL.NormalizeIconAssignments(p) end
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

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- Automatic role selection runs only for the live class.  A readable non-raid
-- group role can choose Heal/Tank until the user clicks a role explicitly;
-- leaving that auto-selected group returns to DPS.
local roleModeEvents = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM" }) do
	pcall(roleModeEvents.RegisterEvent, roleModeEvents, event)
end
roleModeEvents:SetScript("OnEvent", function()
	if type(AL.RefreshAutomaticRotationMode) ~= "function" then return end
	local profile = AL.Profile(AL.playerClass)
	AL.RefreshAutomaticRotationMode(profile, AL.playerClass)
end)

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

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- A cast request which the client accepts but never starts or completes can
-- otherwise pin the rotation on one unreadable/broken action icon forever.
-- A rejected spell stays skipped for the remainder of the fight with that
-- enemy. Readable target GUIDs keep the scope on that enemy; protected target
-- identity safely falls back to the current combat.
local SPELL_ATTEMPT_TIMEOUT = 2
local SPELL_WARNING_SECONDS = 5
local spellAttemptBlacklist = {}
local spellAttemptPending
local spellReadabilityWarning
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
-- SENT cannot report a pixel the reader never clicked. The Display driver
-- supplies the final, unambiguous A[3]/A[6] spell once per redraw.
local spellDisplayPending
local spellDisplayStatus
local spellDisplayQuietUntil = 0
local UNWATCHED_ACTIONS = {
	["Attack"] = true, ["Auto Shot"] = true, ["Shoot"] = true,
	["Heroic Strike"] = true, ["Cleave"] = true, ["Maul"] = true,
	["Raptor Strike"] = true,
	-- These are macro/item actions, not spells with UNIT_SPELLCAST_SENT.
	["Apply Main-Hand Poison"] = true, ["Apply Off-Hand Poison"] = true,
}

local function PublicSpellName(value)
	if (issecretvalue and issecretvalue(value))
		or type(value) ~= "string" or value == "" then return nil end
	return (AL.englishNames and AL.englishNames[value]) or value
end

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
local function BlacklistTargetGUID()
	if type(UnitGUID) ~= "function" then return nil end
	local ok, guid = pcall(UnitGUID, "target")
	if not ok or (issecretvalue and issecretvalue(guid))
		or type(guid) ~= "string" or guid == "" then return nil end
	return guid
end

local function BlacklistCombatState()
	return AL.SafeBoolean(UnitAffectingCombat, "player")
end

local function BlacklistEntryActive(entry)
	if type(entry) == "number" then
		return entry > (GetTime and GetTime() or 0)
	end
	if type(entry) ~= "table" then return false end
	local now = GetTime and GetTime() or 0
	if type(entry.expires) == "number" and entry.expires <= now then
		entry.expires = nil
	end
	local targetGUID = BlacklistTargetGUID()
	if targetGUID and type(entry.targets) == "table" and entry.targets[targetGUID] then
		return true
	end
	local combat = BlacklistCombatState()
	if entry.combatFallback and combat ~= false then return true end
	-- If this fight began with a readable enemy but its GUID becomes protected,
	-- keep the safe skip until combat ends rather than retrying the broken icon.
	if not targetGUID and combat ~= false and type(entry.targets) == "table"
		and next(entry.targets) ~= nil then return true end
	return type(entry.expires) == "number" and entry.expires > now
end

function AL.IsSpellBlacklisted(spell)
	spell = PublicSpellName(spell)
	if not spell then return false end
	local entry = spellAttemptBlacklist[spell]
	if entry == nil then return false end
	if not BlacklistEntryActive(entry) then
		local hasStoredTarget = type(entry) == "table" and type(entry.targets) == "table"
			and next(entry.targets) ~= nil
		-- Keep per-enemy records while combat is active so switching away and back
		-- to the same enemy does not make the failed spell eligible again.
		if not hasStoredTarget or BlacklistCombatState() == false then
			spellAttemptBlacklist[spell] = nil
		end
		return false
	end
	if type(entry) == "number" and entry <= (GetTime and GetTime() or 0) then
		spellAttemptBlacklist[spell] = nil
		return false
	end
	return true
end

function AL.BlacklistSpell(spell, seconds, reason, capturedScope)
	spell = PublicSpellName(spell)
	if not spell then return false end
	local now = GetTime and GetTime() or 0
	local duration = type(seconds) == "number" and math.max(1, seconds) or nil
	local entry = spellAttemptBlacklist[spell]
	if type(entry) ~= "table" then entry = { targets = {} } end
	entry.targets = type(entry.targets) == "table" and entry.targets or {}
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Freeze encounter ownership when UNIT_SPELLCAST_SENT arrives. A target swap
	-- during the two-second watchdog window must not move the blacklist to the
	-- newly selected enemy or broaden it to the whole combat.
	local hasCapturedScope = type(capturedScope) == "table"
		and capturedScope.captured == true
	local targetGUID, combat, combatFallback
	if hasCapturedScope then
		targetGUID = capturedScope.targetGUID
		combat = capturedScope.combat
		combatFallback = capturedScope.combatFallback == true
	else
		targetGUID = BlacklistTargetGUID()
		combat = BlacklistCombatState()
		combatFallback = combat ~= false
	end
	if targetGUID then
		entry.targets[targetGUID] = true
		entry.expires = nil
	elseif combatFallback then
		-- Protected target identity cannot be compared in Lua. Scope the skip to
		-- this combat and clear it on PLAYER_REGEN_ENABLED.
		entry.combatFallback = true
	else
		entry.expires = now + (duration or 30)
	end
	spellAttemptBlacklist[spell] = entry
	spellReadabilityWarning = {
		spell = spell,
		text = spell .. " blacklisted",
		expires = now + SPELL_WARNING_SECONDS,
	}
	if AL.Log then
		AL.Log("cast", "warn", spellReadabilityWarning.text, {
			blacklistScope = targetGUID and "selected enemy"
				or (combatFallback and "current combat" or tostring(duration or 30) .. " seconds"),
			reason = reason or "cast did not start within two seconds",
		})
	end
	return true
end

function AL.ClearSpellBlacklist(spell)
	spell = PublicSpellName(spell)
	if spell then
		spellAttemptBlacklist[spell] = nil
		if spellAttemptPending and spellAttemptPending.spell == spell then spellAttemptPending = nil end
		if spellDisplayPending and spellDisplayPending.spell == spell then spellDisplayPending = nil end
		return
	end
	for name in pairs(spellAttemptBlacklist) do spellAttemptBlacklist[name] = nil end
	spellAttemptPending, spellDisplayPending, spellDisplayStatus, spellReadabilityWarning = nil, nil, nil, nil
	spellDisplayQuietUntil = 0
end

function AL.GetSpellReadabilityWarning()
	local warning = spellReadabilityWarning
	local now = GetTime and GetTime() or 0
	if not warning or type(warning.expires) ~= "number" or warning.expires <= now then
		spellReadabilityWarning = nil
		return nil
	end
	return warning.text, warning.spell, warning.expires - now
end

function AL.SpellBlacklistState()
	local active, now = {}, GetTime and GetTime() or 0
	for spell, entry in pairs(spellAttemptBlacklist) do
		if AL.IsSpellBlacklisted(spell) then
			if type(entry) == "table" and entry.combatFallback then
				active[spell] = "combat"
			elseif type(entry) == "table" and type(entry.targets) == "table"
				and next(entry.targets) ~= nil then
				active[spell] = "selected enemy"
			elseif type(entry) == "table" and type(entry.expires) == "number" then
				active[spell] = math.max(0, entry.expires - now)
			elseif type(entry) == "number" then
				active[spell] = math.max(0, entry - now)
			end
		end
	end
	return {
		pending = spellAttemptPending and {
			spell = spellAttemptPending.spell,
			age = now - spellAttemptPending.at,
			castGUID = spellAttemptPending.castGUID,
			targetGUID = spellAttemptPending.scope and spellAttemptPending.scope.targetGUID,
			combatFallback = spellAttemptPending.scope
				and spellAttemptPending.scope.combatFallback or false,
		} or nil,
		displayPending = spellDisplayPending and {
			spell = spellDisplayPending.spell,
			age = now - spellDisplayPending.at,
			slot = spellDisplayPending.slot,
			targetGUID = spellDisplayPending.scope.targetGUID,
			combatFallback = spellDisplayPending.scope.combatFallback,
		} or nil,
		display = spellDisplayStatus,
		blacklisted = active,
		warning = spellReadabilityWarning and spellReadabilityWarning.text or nil,
	}
end

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
-- The display watchdog only judges a visible, immediately castable action
-- against an engaged enemy. A protected/conditional visual, cooldown, range,
-- insufficient resources, a cast/channel, or any observed spellcast event
-- resets it instead of silently punishing a legitimate wait state.
local function SpellDisplayWatchable(spell)
	if not spell or UNWATCHED_ACTIONS[spell] then return false, "non-spell or auto-repeat action" end
	if AL.IsSpellBlacklisted(spell) then return false, "already blacklisted" end
	if AL.SafeBoolean(UnitAffectingCombat, "player") ~= true
		or AL.SafeBoolean(UnitExists, "target") ~= true
		or AL.SafeBoolean(UnitCanAttack, "player", "target") ~= true then
		return false, "combat or hostile target unconfirmed"
	end
	if type(AL.CastingSpell) == "function" then
		local ok, name = pcall(AL.CastingSpell)
		if not ok or (issecretvalue and issecretvalue(name)) or name then return false, "casting" end
	end
	if type(UnitCastingInfo) == "function" then
		local ok, name = pcall(UnitCastingInfo, "player")
		if not ok or (issecretvalue and issecretvalue(name)) or name then return false, "casting or cast protected" end
	end
	if type(AL.PlayerChanneling) == "function" then
		local ok, active = pcall(AL.PlayerChanneling)
		if not ok or (issecretvalue and issecretvalue(active)) or active then return false, "channeling" end
	end
	local okReady, ready = pcall(AL.IsReady, spell)
	if not okReady or (issecretvalue and issecretvalue(ready)) or ready ~= true then return false, "cooldown unready" end
	local okUsable, usable, insufficient = pcall(AL.SpellUsable, spell)
	if not okUsable or (issecretvalue and (issecretvalue(usable) or issecretvalue(insufficient)))
		or usable ~= true or insufficient == true then return false, "spell unusable or insufficient resources" end
	local okRange, inRange = pcall(AL.InRange, spell)
	-- A protected/unknown range is not proof that this icon was actionable.
	if not okRange or (issecretvalue and issecretvalue(inRange)) or inRange ~= true then
		local outOfRange = okRange and not (issecretvalue and issecretvalue(inRange)) and inRange == false
		return false, outOfRange and "out of range" or "range unconfirmed"
	end
	return true
end

function AL.ObserveDisplayedSpell(spell, slot)
	-- Only the final driven pixel can prove what a reader was meant to see.
	if slot ~= "A3" and slot ~= "A6" then spell = nil end
	spell = PublicSpellName(spell)
	local now = GetTime and GetTime() or 0
	local watchable, reason = SpellDisplayWatchable(spell)
	if not spell then reason = "no unambiguous A[3]/A[6] spell" end
	if now < spellDisplayQuietUntil then reason = "recent cast event" end
	spellDisplayStatus = { spell = spell, slot = slot, at = now, status = reason or "watching" }
	if not spell or now < spellDisplayQuietUntil or not watchable then
		spellDisplayPending = nil
		return
	end
	local guid = BlacklistTargetGUID()
	local pending = spellDisplayPending
	if pending and (pending.spell ~= spell or pending.slot ~= slot
		or pending.scope.targetGUID ~= guid) then
		spellDisplayPending, pending = nil, nil
	end
	if not pending then
		spellDisplayPending = {
			spell = spell, slot = slot, at = now,
			scope = {
				captured = true, targetGUID = guid, combat = true,
				combatFallback = guid == nil,
			},
		}
		return
	end
	if now - pending.at < SPELL_ATTEMPT_TIMEOUT then return end
	spellDisplayPending = nil
	spellDisplayStatus.status = "blacklisted after no cast event"
	AL.BlacklistSpell(spell, nil,
		"Visible " .. slot .. " recommendation had no UNIT_SPELLCAST_SENT for two seconds",
		pending.scope)
end

local function BeginSpellAttempt(spell, castGUID)
	spell = PublicSpellName(spell)
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Auto-repeat toggles commonly emit a redundant SENT/FAILED_QUIET while
	-- already active. On-next-swing attacks can also remain queued for longer
	-- than two seconds by design. Their dedicated timing modules own retry
	-- protection, so neither case is evidence of an unreadable icon.
	if not spell or UNWATCHED_ACTIONS[spell] then return end
	local now = GetTime and GetTime() or 0
	-- Repeated failed key presses must not keep moving the two-second deadline.
	if spellAttemptPending and spellAttemptPending.spell == spell
		and now - spellAttemptPending.at < SPELL_ATTEMPT_TIMEOUT then return end
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Capture the selected enemy and combat visibility with the attempt. Reading
	-- either one later would incorrectly attribute a failed opener after a target
	-- switch during the watchdog delay.
	local targetGUID = BlacklistTargetGUID()
	local combat = BlacklistCombatState()
	spellAttemptPending = {
		spell = spell,
		at = now,
		castGUID = castGUID,
		scope = {
			captured = true,
			targetGUID = targetGUID,
			combat = combat,
			combatFallback = not targetGUID and combat ~= false,
		},
	}
end

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- A terminal failure proves that the client read and rejected the spell. It is
-- therefore not the missing START/SUCCEEDED condition this watchdog detects.
-- Clear only the matching attempt so an ordinary GCD, range, movement, or
-- resource error cannot blacklist a valid learned spell for the whole fight.
local function RejectSpellAttempt(spell, castGUID)
	spell = PublicSpellName(spell)
	local pending = spellAttemptPending
	if not pending then return end
	if castGUID and pending.castGUID and castGUID ~= pending.castGUID then return end
	if spell and spell ~= pending.spell then return end
	spellAttemptPending = nil
end

local function AcceptSpellAttempt(spell, castGUID)
	spell = PublicSpellName(spell)
	-- Once blacklisted, the spell remains skipped for this enemy until combat
	-- ends. A later manual cast does not silently hide the visible problem state.
	local pending = spellAttemptPending
	if not pending then return end
	if castGUID and pending.castGUID and castGUID ~= pending.castGUID then return end
	if spell and spell ~= pending.spell then return end
	spellAttemptPending = nil
end

function AL.PruneSpellAttempts()
	local pending = spellAttemptPending
	if not pending then return end
	local now = GetTime and GetTime() or 0
	if now - pending.at < SPELL_ATTEMPT_TIMEOUT then return end
	spellAttemptPending = nil
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- A readable selected enemy owns the blacklist until that fight ends. When
	-- neither combat nor a readable target can provide an encounter boundary,
	-- retain the short outside-combat recovery window as a safe fallback.
	local duration = pending.scope and pending.scope.combat == false and 30 or nil
	AL.BlacklistSpell(pending.spell, duration,
		"UNIT_SPELLCAST_SENT had no START, CHANNEL_START, or SUCCEEDED result",
		pending.scope)
end

function AL.Allowed(name, prof)
	if AL.IsSpellBlacklisted(name) then return false end
	local sp = (prof or AL.S()).spells
	return not sp or sp[name] ~= false
end

-- API compat: 1.60 client may ship either the classic globals or the C_Spell namespace
function AL.SpellName(spell)
	if type(GetSpellInfo) == "function" then
		local ok, name = pcall(GetSpellInfo, spell)
		if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" then return name end
	end
	if C_Spell and type(C_Spell.GetSpellName) == "function" then
		local ok, name = pcall(C_Spell.GetSpellName, spell)
		if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" then return name end
	end
	if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
		local ok, info = pcall(C_Spell.GetSpellInfo, spell)
		if ok and type(info) == "table" and not (issecretvalue and issecretvalue(info)) then
			local name = info.name
			if type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" then return name end
		end
	end
end

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
-- Rotation/profile keys remain English; spell APIs and the action-bar scanner
-- need the live learned-rank ID (or the client's localized name).  The ID is
-- never guessed from a rank-one catalog entry: the spellbook owns it.
function AL.LocalName(spell)
	if type(spell) ~= "string" or (issecretvalue and issecretvalue(spell)) then return nil end
	return AL.localNames and AL.localNames[spell] or spell
end

function AL.SpellIdentifier(spell)
	if type(spell) ~= "string" or (issecretvalue and issecretvalue(spell)) then return spell end
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[spell]
	local id = ref and ref.id
	if type(id) == "number" and not (issecretvalue and issecretvalue(id)) and id > 0 then return id end
	return AL.LocalName(spell)
end

function AL.SpellTexture(spell)
	if not (issecretvalue and issecretvalue(spell)) then
		local name = spell
		if type(spell) == "number" then
			if fixedTexturesByID[spell] then return fixedTexturesByID[spell] end
			name = AL.castSpellNamesByID and AL.castSpellNamesByID[spell]
		end
		if name and AL.englishNames then name = AL.englishNames[name] or name end
		local fixed = name and fixedTextures[name]
		if fixed then return fixed end
	end
	local identifier = AL.SpellIdentifier(spell)
	if type(GetSpellTexture) == "function" then
		local ok, texture = pcall(GetSpellTexture, identifier)
		if ok and not (issecretvalue and issecretvalue(texture)) and texture then return texture end
	end
	if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
		local ok, texture = pcall(C_Spell.GetSpellTexture, identifier)
		if ok and not (issecretvalue and issecretvalue(texture)) and texture then return texture end
	end
end

-- Keep the original Universal numbers stable; 8 and 9 are no longer supported.
AL.UNIVERSAL_ICONS = { [1] = 133667, [2] = 133663, [3] = 133658, [4] = 133653,
	[5] = 133650, [6] = 133648, [7] = 133646, [10] = 133632 }
AL.UNIVERSAL_CHOICES = {}
local universalTextures = {}
for _, slot in ipairs({ 3, 6 }) do
	for _, number in ipairs({ 1, 2, 3, 4, 5, 6, 7, 10 }) do
		local texture = AL.UNIVERSAL_ICONS[number]
		universalTextures[texture] = true
		AL.UNIVERSAL_CHOICES[#AL.UNIVERSAL_CHOICES + 1] = {
			number = number, texture = texture, slot = slot,
			label = slot == 6 and ("Universal%d Unit1"):format(number) or nil,
		}
	end
end

-- Both sets use the same artwork. Store their destination separately so an
-- original spell or Universal assignment can never be mistaken for Unit1.
function AL.SlotFor(spell, prof)
	local p = prof or AL.S()
	local texture = p.icons and p.icons[spell]
	local destination = p.iconTargets and p.iconTargets[spell]
	-- ActionLITE 1.0.25 originally stored mini2 as 2. Treat it as A[6]
	-- immediately, even before the profile normalizer persists the migration.
	if texture and universalTextures[texture] and (destination == 6 or destination == 2) then return 6 end
	return 3
end

-- Compatibility for integrations that still ask for the former mini number.
-- No legacy mini frames are created; these values map directly to A[3]/A[6].
function AL.MiniFor(spell, prof)
	return AL.SlotFor(spell, prof) == 6 and 2 or 1
end

function AL.IconChoice(spell, prof)
	local p = prof or AL.S()
	local texture = p.icons and p.icons[spell]
	local slot = AL.SlotFor(spell, p)
	for _, choice in ipairs(AL.UNIVERSAL_CHOICES) do
		if choice.texture == texture and choice.slot == slot then return choice end
	end
end

-- Reserve each Universal choice once per class profile and A slot.
-- Disabled and unlearned spells keep their assignments until explicitly changed.
function AL.IconChoiceOwner(spell, choice, prof)
	if not choice then return end
	local p = prof or AL.S()
	local owner
	for other, texture in pairs(p.icons or {}) do
		if other ~= spell and texture == choice.texture and AL.SlotFor(other, p) == choice.slot
			and (not owner or other < owner) then owner = other end
	end
	return owner
end

function AL.SetIconChoice(spell, choice, prof)
	local p = prof or AL.S()
	local owner = AL.IconChoiceOwner(spell, choice, p)
	if owner then return false, owner end
	p.icons = p.icons or {}
	p.iconTargets = p.iconTargets or {}
	p.icons[spell] = choice and choice.texture or nil
	p.iconTargets[spell] = choice and choice.slot == 6 and 6 or nil
	return true
end

function AL.NormalizeIconAssignments(p)
	if type(p.icons) ~= "table" then return end
	for spell, texture in pairs(p.icons) do
		if texture == 133643 or texture == 133639 then
			p.icons[spell] = nil
			if type(p.iconTargets) == "table" then p.iconTargets[spell] = nil end
		end
	end
	if type(p.iconTargets) == "table" then
		for spell, destination in pairs(p.iconTargets) do
			if not universalTextures[p.icons[spell]] then
				p.iconTargets[spell] = nil
			elseif destination == 2 then
				p.iconTargets[spell] = 6
			elseif destination ~= 6 then
				p.iconTargets[spell] = nil
			end
		end
	end
end

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
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
	-- Every class must use the learned rank or localized name, including
	-- leveling Hunters, Druids, Rogues, Warlocks and Warriors.
	spell = AL.SpellIdentifier(spell)
	if GetSpellCooldown then
		local ok, s, d = pcall(GetSpellCooldown, spell)
		-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
		-- A successful API call may still contain secret fields. Never return
		-- protected numbers to a caller which will compare or add them.
		if ok and not (issecretvalue and (issecretvalue(s) or issecretvalue(d)))
			and type(s) == "number" and type(d) == "number" then return s, d end
		-- Some clients expose the global but only the modern API can read it.
		-- Fall through rather than abandoning the cooldown query.
	end
	local reader = C_Spell and C_Spell.GetSpellCooldown
	if type(reader) ~= "function" then return nil end
	local ok, c = pcall(reader, spell)
	if not ok or (issecretvalue and issecretvalue(c)) or type(c) ~= "table" then return nil end
	local start, duration = c.startTime, c.duration
	if (issecretvalue and (issecretvalue(start) or issecretvalue(duration)))
		or type(start) ~= "number" or type(duration) ~= "number" then return nil end
	return start, duration
end

-- blocked/secret usability reads count as usable; a real "no mana" still gates
function AL.SpellUsable(spell)
	local ok, usable, insufficient
	spell = AL.SpellIdentifier(spell)
	local reader = IsUsableSpell
	if type(reader) == "function" then ok, usable, insufficient = pcall(reader, spell) end
	if not ok or (not (issecretvalue and issecretvalue(usable)) and type(usable) ~= "boolean") then
		reader = C_Spell and C_Spell.IsSpellUsable
		if type(reader) ~= "function" then return true end
		ok, usable, insufficient = pcall(reader, spell)
	end
	if not ok then return true end
	if issecretvalue and issecretvalue(usable) then return true end
	if (issecretvalue and issecretvalue(insufficient)) or type(insufficient) ~= "boolean" then insufficient = nil end
	return usable == true, insufficient
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
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Do not branch on UnitExists here: Forever may return a secret boolean in
	-- combat.  The protected casting calls below already fail closed when there
	-- is no readable target cast.
	if UnitCastingInfo then
		local ok, name = pcall(UnitCastingInfo, "target")
		if ok and not (issecretvalue and issecretvalue(name))
			and type(name) == "string" and name ~= "" then return true end
	end
	if UnitChannelInfo then
		local ok, name = pcall(UnitChannelInfo, "target")
		if ok and not (issecretvalue and issecretvalue(name))
			and type(name) == "string" and name ~= "" then return true end
	end
	return false
end

function AL.TargetHasAnyDebuff(names)
	for _, n in ipairs(names) do
		if AL.HasDebuff("target", n) then return true end
	end
	return false
end

local wandEquippedCache
function AL.WandEquipped()
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	local ok, itemID = pcall(GetInventoryItemID, "player", 18)
	if ok and not (issecretvalue and issecretvalue(itemID)) then
		wandEquippedCache = type(itemID) == "number" and itemID > 0
	end
	return wandEquippedCache == true
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
-- Forever can protect UnitPower(player, type) while leaving the
-- untyped primary-resource read usable. Try the
-- known sources without ever calculating with a secret value.
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

-- Forever can hide UnitPower while still allowing the player's bar to
-- update. Reading that bar is a display fallback, never an estimate.
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

	-- Method used by Action.Unit(player):Power().
	if ptype == nil or currentType == nil or currentType == ptype then
		local value = SafePowerCall(UnitPower, "player")
		if value ~= nil then return value end
	end

	local value = SafePowerCall(UnitPower, "player", ptype)
	if value ~= nil then return value end

	-- Last attempt through Action's cache when available.
	local A = _G.Action
	if A and A.Unit then
		local ok, unit = pcall(A.Unit, "player")
		if ok and unit and unit.Power then
			value = SafePowerCall(unit.Power, unit)
			if value ~= nil then return value end
		end
	end

	-- For Warrior, the UI bar can stay readable when UnitPower
	-- becomes secret in combat.
	if ptype == 1 and AL.playerClass == "WARRIOR" then
		value = RageFromPlayerFrame()
		if value ~= nil then return value end
	end

	-- Rage returns to zero outside combat on Forever. In combat, nil
	-- deliberately means unknown, so spending is not incorrectly authorized.
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
	["Mutilate"] = 2, ["Hemorrhage"] = 1, ["Ghostly Strike"] = 1,
	["Claw"] = 1, ["Rake"] = 1, ["Shred"] = 1,
}
local CP_FINISHERS = {
	["Eviscerate"] = true, ["Slice and Dice"] = true, ["Rupture"] = true,
	["Kidney Shot"] = true, ["Expose Armor"] = true,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Death Mark"] = true,
	["Ferocious Bite"] = true, ["Rip"] = true,
}
local inferredCp = 0
local pendingComboCast
local rogueComboChangedAt, rogueComboBefore = -math.huge, nil

function AL.TrackComboCast(name)
	local before = inferredCp
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Shank only grants combo points through Boot Knife. The Rogue module
	-- returns a value only for the guaranteed max-rank proc; lower ranks remain
	-- native-readable rather than inventing a probabilistic point gain.
	local points = CP_BUILDERS[name]
	if not points and AL.playerClass == "ROGUE" then
		local mod = AL.rotations and AL.rotations.ROGUE
		local ok, generated = pcall(function() return mod and mod.ComboPointsGenerated and mod.ComboPointsGenerated(name) end)
		if ok and type(generated) == "number" and generated > 0 then points = generated end
	end
	if trackedComboClass then
		if CP_FINISHERS[name] then
			rogueComboChangedAt, rogueComboBefore = GetTime(), before
		elseif points then
			rogueComboChangedAt, rogueComboBefore = -math.huge, nil
		end
	end
	if points then
		pendingComboCast = { name = name, before = before, at = GetTime() }
		inferredCp = math.min(5, inferredCp + points)
	elseif CP_FINISHERS[name] then
		pendingComboCast = { name = name, before = before, at = GetTime() }
		inferredCp = 0
		return before
	end
end

-- UNIT_SPELLCAST_SUCCEEDED means the button was accepted, not that
-- the attack landed. The combat log follows with SPELL_MISSED:
-- then restore exactly the state preceding the builder or finisher.
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

-- Resource curves control display visibility without inspecting protected mana
-- or health. The returned alpha is passed straight to a frame or texture.
local resourceCurves, resourceCurveFactory, resourceProbe = {}, nil, nil
local resourceFailures = {}
function AL.ResourceDebugState() return { failures = resourceFailures, buildId = AL.buildId } end
function AL.ResourceIntervalAlpha(kind, unit, powerType, low, high)
	local factory = C_CurveUtil and C_CurveUtil.CreateColorCurve
	local reader
	if kind == "power" then reader = UnitPowerPercent else reader = UnitHealthPercent end
	if type(factory) ~= "function" or type(reader) ~= "function" or type(CreateColor) ~= "function" then return false end
	local ok, alpha = pcall(function()
		if resourceCurveFactory ~= factory then resourceCurves, resourceCurveFactory = {}, factory end
		local key = tostring(low) .. ":" .. tostring(high)
		local curve = resourceCurves[key]
		if not curve then
			curve = factory()
			curve:SetType(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
			curve:AddPoint(0, CreateColor(1, 1, 1, low == 0 and 1 or 0))
			if low > 0 and low <= 1 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
			if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
			if low ~= 1 and high ~= 1 then curve:AddPoint(1, CreateColor(1, 1, 1, low <= 1 and high > 1 and 1 or 0)) end
			resourceCurves[key] = curve
		end
		local color
		if kind == "power" then color = reader(unit, powerType, false, curve)
		else color = reader(unit, false, curve) end
		local _, _, _, value = color:GetRGBA()
		if not (issecretvalue and issecretvalue(value)) and type(value) ~= "number" then error("Resource display alpha unavailable") end
		if not resourceProbe then resourceProbe = CreateFrame("Frame"); resourceProbe:Hide() end
		resourceProbe:SetAlpha(value)
		return value
	end)
	if ok then return true, alpha end
	local message = type(alpha) == "string" and not (issecretvalue and issecretvalue(alpha)) and alpha or "Protected resource display failure"
	local key = kind .. ":" .. tostring(unit)
	local previous = resourceFailures[key]
	resourceFailures[key] = { message = message, at = GetTime(), low = low, high = high,
		count = previous and previous.count + 1 or 1 }
	if (not previous or previous.message ~= message) and AL.Debug and AL.Debug.CaptureError then
		AL.Debug.CaptureError("Resource display (" .. key .. "): " .. message, "resource display")
	end
	return false
end

-- Step curves use single-precision boundaries. Moving an inclusive upper
-- threshold to the next float includes the slider's exact percentage.
function AL.ResourceThresholdCut(percent, inclusive)
	local cut = math.max(0, math.min(100, percent)) / 100
	if not inclusive then return cut end
	if cut <= 0 then return 2^-149 end
	local step = 2^(math.floor(math.log(cut) / math.log(2)) - 23)
	return (math.floor(cut / step + 0.5) + 1) * step
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

-- Rotations mark their self-cast spells: selecting an enemy
-- must never turn a personal heal or buff red for being out of range.
AL.selfCastSpells = AL.selfCastSpells or {}

-- true = in range, false = out of range, nil = unknown/no target
function AL.InRange(spell)
	if AL.selfCastSpells and AL.selfCastSpells[spell] then return true end
	if AL.SafeBoolean(UnitExists, "target") == false then return nil end
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
		-- The legacy numeric signature expects a spellbook INDEX, not a SpellID.
		if ref and ref.index then
			local result = Normalize(pcall(IsSpellInRange, ref.index, BOOKTYPE_SPELL or "spell", "target"))
			if result ~= nil then return result end
		end
		local name = type(spell) == "string" and AL.LocalName(spell) or spell
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
		return Normalize(pcall(C_Spell.IsSpellInRange, AL.SpellIdentifier(spell), "target"))
	end
	return nil
end

local function BookItemName(i)
	if GetSpellBookItemName then return GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell") end
	return C_SpellBook.GetSpellBookItemName(i, Enum.SpellBookSpellBank.Player)
end

-- Exact learned-rank reference for range checks. The old API expects a
-- spellbook index while C_Spell expects a SpellID: keeping both
-- avoids confusing a classic rank ID with Forever's actual spell.
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
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Curse of the Elements"] = 300, ["Curse of Weakness"] = 120,
	["Curse of Recklessness"] = 120, ["Curse of Tongues"] = 30, ["Curse of Exhaustion"] = 12,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Moonfire"] = 9, ["Insect Swarm"] = 12, ["Rake"] = 9, ["Rip"] = 12, ["Lacerate"] = 15, ["Demoralizing Roar"] = 30,
	["Flame Shock"] = 12, ["Frost Shock"] = 8,
	["Frost Nova"] = 8, ["Frostbolt"] = 5, ["Cone of Cold"] = 8,
	["Gouge"] = 4, ["Expose Armor"] = 30, ["Rupture"] = 10,
	["Garrote"] = 18,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Death Mark"] = 6,
}

-- 1.60 blocks aura reads, so player buffs are inferred entirely from our own
-- successful casts with conservative vanilla durations.
local BUFF_GROUPS = {
	-- casting one member replaces the others
	{ "Seal of Command", "Seal of Righteousness", "Seal of the Crusader", "Seal of Light", "Seal of Wisdom" },
	{ "Devotion Aura", "Retribution Aura", "Concentration Aura" },
	{ "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Greater Blessing of Kings", "Blessing of Protection", "Blessing of Freedom" },
	{ "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Beast" },
	{ "Frost Armor", "Ice Armor", "Mage Armor" },
	{ "Demon Skin", "Demon Armor" },
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	{ "Bear Form", "Dire Bear Form", "Cat Form", "Moonkin Form", "Aquatic Form", "Travel Form" },
}
local groupOf = {}
for _, group in ipairs(BUFF_GROUPS) do
	for _, member in ipairs(group) do groupOf[member] = group end
end

local SELF_BUFF_DURATIONS = {
	["Seal of Command"] = 30, ["Seal of Righteousness"] = 30, ["Seal of the Crusader"] = 30,
	["Seal of Light"] = 30, ["Seal of Wisdom"] = 30,
	["Blessing of Might"] = 300, ["Blessing of Wisdom"] = 300,
	["Blessing of Kings"] = 3600, ["Greater Blessing of Kings"] = 3600,
	["Blessing of Protection"] = 10, ["Blessing of Freedom"] = 10,
	["Devotion Aura"] = 3600, ["Retribution Aura"] = 3600, ["Concentration Aura"] = 3600,
	["Righteous Fury"] = 1800, ["Divine Protection"] = 8, ["Divine Shield"] = 12,
	["Aspect of the Hawk"] = 3600, ["Aspect of the Monkey"] = 3600, ["Aspect of the Cheetah"] = 3600,
	["Aspect of the Beast"] = 3600,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Rapid Fire"] = 15, ["Trueshot Aura"] = 3600, ["Blood Fury"] = 15,
	["Arcane Intellect"] = 1800, ["Frost Armor"] = 1800, ["Ice Armor"] = 1800, ["Mage Armor"] = 1800,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Ice Block"] = 10, ["Ice Barrier"] = 60, ["Mana Shield"] = 60, ["Berserking"] = 15,
	["Mark of the Wild"] = 1800, ["Thorns"] = 600, ["Rejuvenation"] = 12,
	["Nature's Swiftness"] = 10, ["Elune's Light"] = 15, ["Tiger's Fury"] = 6,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Bear Form"] = 3600, ["Dire Bear Form"] = 3600, ["Moonkin Form"] = 3600, ["Prowl"] = 3600, ["Enrage"] = 10, ["Cat Form"] = 3600, ["Aquatic Form"] = 3600, ["Travel Form"] = 3600,
	["Power Word: Fortitude"] = 1800, ["Inner Fire"] = 600, ["Renew"] = 15, ["Power Word: Shield"] = 30,
	["Stealth"] = 3600, ["Evasion"] = 15, ["Blade Flurry"] = 15, ["Slice and Dice"] = 12,
	["Lightning Shield"] = 600, ["Water Shield"] = 600,
	["Demon Skin"] = 1800, ["Demon Armor"] = 1800,
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
	["Mutilate"] = true, ["Hemorrhage"] = true, ["Ghostly Strike"] = true,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Shank"] = true, ["Death Mark"] = true,
}

local selfBuffs = {}
local rogueBuffGrace, rogueSliceDurations = {}, {}
local PALADIN_SEALS = {
	["Seal of Command"] = true, ["Seal of Righteousness"] = true, ["Seal of the Crusader"] = true,
	["Seal of Light"] = true, ["Seal of Wisdom"] = true,
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
	["Holy Strike"] = 10, ["Judgement"] = 10, ["Hammer of Justice"] = 60, ["Exorcism"] = 15,
	["Consecration"] = 8, ["Divine Protection"] = 300, ["Divine Shield"] = 300,
	["Holy Shock"] = 10, ["Hammer of Wrath"] = 6, ["Hammer of the Righteous"] = 6,
	["Holy Wrath"] = 60, ["Holy Shield"] = 10, ["Swift Judgement"] = 60,
	["Templar's Bulwark"] = 300, ["Divine Favor"] = 120,
	["Blessing of Protection"] = 300, ["Blessing of Freedom"] = 25, ["Lay on Hands"] = 3600,
	["Arcane Shot"] = 6, ["Multi-Shot"] = 10, ["Raptor Strike"] = 6, ["Rapid Fire"] = 300, ["Disengage"] = 5,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Freezing Trap"] = 30, ["Frost Trap"] = 30, ["Immolation Trap"] = 30, ["Explosive Trap"] = 30,
	["Fire Blast"] = 8, ["Frost Nova"] = 25, ["Cone of Cold"] = 10, ["Counterspell"] = 30,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Ice Barrier"] = 30,
	["Arcane Wrath"] = 6,
	["Ice Block"] = 300, ["Evocation"] = 480, ["Conjure Mana Agate"] = 30,
	["Mind Blast"] = 8, ["Holy Fire"] = 10, ["Devouring Plague"] = 24, ["Vampiric Embrace"] = 30, ["Shadow Word: Death"] = 18,
	["Psychic Scream"] = 30, ["Silence"] = 45, ["Desperate Prayer"] = 600, ["Fade"] = 30,
	["Inner Focus"] = 180, ["Penance"] = 12, ["Prayer of Mending"] = 10, ["Power Infusion"] = 180,
	["Divine Grace"] = 600, ["Dark Sacrifice"] = 600, ["Eureka!"] = 120,
	["Rapid Regeneration"] = 180,
	["Gouge"] = 10, ["Kick"] = 10, ["Evasion"] = 300, ["Blade Flurry"] = 120, ["Stealth"] = 10,
	["Vanish"] = 300, ["Riposte"] = 6,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Ghostly Strike"] = 20,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Shank"] = 10, ["Death Mark"] = 10,
	["Charge"] = 15, ["Bloodrage"] = 60, ["Bash"] = 60, ["Enrage"] = 600, ["Tiger's Fury"] = 1,
	["Swiftmend"] = 15, ["Nature's Swiftness"] = 180, ["Tranquility"] = 300, ["Wild Growth"] = 6,
	["Elune's Light"] = 180,
	["Overpower"] = 5, ["Revenge"] = 5, ["Thunder Clap"] = 4,
	["Mongoose Bite"] = 5, ["Concussive Shot"] = 12, ["Summon Hawk"] = 6,
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Stormstrike"] = 6, ["Riptide"] = 12, ["Mana Tide Totem"] = 300,
	["Lightning Mastery"] = 180, ["Totemic Call"] = 30,
	["Blood Fury"] = 120, ["Berserking"] = 180, ["War Stomp"] = 120,
}
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
local HUNTER_TRAPS = {
	["Freezing Trap"] = true, ["Frost Trap"] = true,
	["Immolation Trap"] = true, ["Explosive Trap"] = true,
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
	local exists = AL.SafeBoolean(UnitExists, "target")
	if exists == true then
		debuffValid = SweepAuras("target", true, tooltipDebuffs)
	elseif exists == false then
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
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- The shared two-second cast watchdog must see these events for every class,
-- including rotations which do not otherwise need cast-time tracking.
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_FAILED_QUIET" }) do
	if not pcall(debuffFrame.RegisterUnitEvent, debuffFrame, event, "player") then
		pcall(debuffFrame.RegisterEvent, debuffFrame, event)
	end
end
if trackedCastClass then
	for _, event in ipairs({ "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_DELAYED" }) do
		if not pcall(debuffFrame.RegisterUnitEvent, debuffFrame, event, "player") then
			pcall(debuffFrame.RegisterEvent, debuffFrame, event)
		end
	end
end
if AL.playerClass == "PRIEST" then
	if not pcall(debuffFrame.RegisterUnitEvent, debuffFrame, "UNIT_SPELLCAST_FAILED_QUIET", "player") then
		pcall(debuffFrame.RegisterEvent, debuffFrame, "UNIT_SPELLCAST_FAILED_QUIET")
	end
end
if not pcall(debuffFrame.RegisterUnitEvent, debuffFrame, "UNIT_AURA", "player", "target") then
	pcall(debuffFrame.RegisterEvent, debuffFrame, "UNIT_AURA")
end
if type(CombatLogGetCurrentEventInfo) == "function" then
	pcall(debuffFrame.RegisterEvent, debuffFrame, "COMBAT_LOG_EVENT_UNFILTERED")
end
pcall(debuffFrame.RegisterEvent, debuffFrame, "UI_ERROR_MESSAGE")
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
pcall(debuffFrame.RegisterEvent, debuffFrame, "PLAYER_REGEN_ENABLED")
pcall(debuffFrame.RegisterEvent, debuffFrame, "PLAYER_ENTERING_WORLD")

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
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	["Curse of the Elements"] = true, ["Curse of Tongues"] = true, ["Curse of Exhaustion"] = true,
}

local function ReadCastGUID(value)
	if type(value) == "string" and not (issecretvalue and issecretvalue(value))
		and value:find("^Cast%-")
	then
		return value
	end
end

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
local function WatchSpellAttempt(event, arg2, arg3, arg4)
	if event ~= "UNIT_SPELLCAST_SENT" and event ~= "UNIT_SPELLCAST_START"
		and event ~= "UNIT_SPELLCAST_CHANNEL_START" and event ~= "UNIT_SPELLCAST_SUCCEEDED"
		and event ~= "UNIT_SPELLCAST_FAILED" and event ~= "UNIT_SPELLCAST_FAILED_QUIET"
		and event ~= "UNIT_SPELLCAST_INTERRUPTED" then return end
	local name = EnglishCastName(arg2, arg3, arg4)
	local guid = ReadCastGUID(arg2)
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
	-- If an actual key press/cast event reaches the client, this is no longer a
	-- pixel that went unseen. Unknown protected spell IDs are inconclusive, so
	-- reset rather than blacklisting an unrelated visible recommendation.
	if spellDisplayPending and (name == nil or name == spellDisplayPending.spell) then
		spellDisplayPending = nil
		spellDisplayQuietUntil = (GetTime and GetTime() or 0) + 0.35
	end
	if event == "UNIT_SPELLCAST_SENT" then
		guid = ReadCastGUID(arg3)
		-- Never substitute the displayed recommendation for a protected event.
		-- The player may have manually cast another spell, and a HealingEngine
		-- overlay may differ from the underlying damage suggestion.
		BeginSpellAttempt(name, guid)
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
		or event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- START/CHANNEL_START proves a long cast was accepted; do not punish a
		-- three-second cast merely because SUCCEEDED arrives after two seconds.
		AcceptSpellAttempt(name, guid)
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
		or event == "UNIT_SPELLCAST_INTERRUPTED" then
		RejectSpellAttempt(name, guid)
	end
end

local function PublicUnitGUID(unit)
	if type(UnitGUID) ~= "function" then return nil end
	local ok, guid = pcall(UnitGUID, unit)
	if ok and type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then
		return guid
	end
end

local function CastTargetGUID()
	return PublicUnitGUID("target")
end

local function HasReadableCastID(arg3, arg4)
	return (type(arg3) == "number" and not (issecretvalue and issecretvalue(arg3)))
		or (type(arg4) == "number" and not (issecretvalue and issecretvalue(arg4)))
end

-- LIKELY identity when IDs are secret: remember only a suggestion
-- authorized by the Warlock rotation on SENT (DoT or mana).
-- SUCCEEDED must confirm that same cast before creating a timer.
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
	-- Without readable GUIDs at both ends, limit the inference to five seconds.
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

-- The player's current cast, tracked by UNIT_SPELLCAST_START even if UnitCastingInfo is secret.
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

-- A spell can be queued while another is finishing its cast.
-- Keep their contexts by GUID rather than overwriting the previous cast.
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
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
		AL.ClearSpellBlacklist()
		return
	end
	if event == "UI_ERROR_MESSAGE" then
		-- old clients pass (message), new ones (messageType, message)
		local msg = type(arg2) == "string" and arg2 or (type(unit) == "string" and unit or nil)
		ComboRotationHook("OnUIError", msg)
		if type(msg) == "string" and not (issecretvalue and issecretvalue(msg)) and msg ~= ""
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
		if issecretvalue and (issecretvalue(sub) or issecretvalue(srcGUID) or issecretvalue(destGUID)
			or issecretvalue(spellName) or issecretvalue(missType)) then return end
		if sub ~= "SPELL_MISSED" or type(spellName) ~= "string"
			or type(srcGUID) ~= "string" or type(destGUID) ~= "string" then return end
		-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
		if AL.playerClass == "DRUID" or AL.playerClass == "HUNTER" or AL.playerClass == "SHAMAN" or AL.playerClass == "ROGUE" then
			spellName = (AL.englishNames and AL.englishNames[spellName]) or spellName
		end
		-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
		-- Miss repair is optional. If combat hides either identity, skip it rather
		-- than comparing or truth-testing a protected GUID.
		local playerGUID, targetGUID = PublicUnitGUID("player"), PublicUnitGUID("target")
		if not playerGUID or not targetGUID or srcGUID ~= playerGUID or destGUID ~= targetGUID then return end
		-- ABSORB/BLOCK stop the damage but the aura still lands
		if missType == "ABSORB" or missType == "BLOCK" then return end
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
		spellDisplayPending = nil
		spellDisplayStatus = nil
		spellDisplayQuietUntil = (GetTime and GetTime() or 0) + 0.35
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
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	WatchSpellAttempt(event, arg2, arg3, arg4)
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
			-- A readable identity corrects the inference saved on SENT.
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
		-- Priest also needs cached learned IDs: modern success events omit arg4,
		-- and live spell-name lookup can be unavailable during combat.
		local ResolveName = AL.playerClass == "PRIEST" and CastName or LegacyCastName
		if event == "UNIT_SPELLCAST_SENT" then
			local n = ResolveName(arg2, arg3, arg4)
			if n then legacyLastSent = { name = n, t = GetTime(),
				guid = AL.playerClass == "PRIEST" and ReadCastGUID(arg3) or nil } end
			return
		end
		-- a failed attempt (out of range etc.) must not be blamed for a later success
		local guid = AL.playerClass == "PRIEST" and ReadCastGUID(arg2) or nil
		local matches = not guid or not legacyLastSent or not legacyLastSent.guid or guid == legacyLastSent.guid
		if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
			if matches then legacyLastSent = nil end
			return
		end
		if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
		name = ResolveName(arg2, arg3, arg4)
		-- SUCCEEDED payload unreadable (secret spellID): trust the last SENT name once
		local canInfer = AL.playerClass ~= "PRIEST" or not HasReadableCastID(arg3, arg4)
			and legacyLastSent and ((guid and guid == legacyLastSent.guid) or (not guid and not legacyLastSent.guid))
		if not name and canInfer and legacyLastSent and GetTime() - legacyLastSent.t < 5 then name = legacyLastSent.name end
		if matches then legacyLastSent = nil end
	end
	if ActionLiteDB and ActionLiteDB.debug and AL.Log then
		-- Keep protected event values inside the guarded logger. Formatting the
		-- arguments before pcall can throw and interrupt successful-cast tracking.
		AL.Log("cast", "trace", "cast payload", { name = name, arg2 = arg2, arg3 = arg3 })
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
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Base Holy Strike is ten seconds. Shieldsworn reduces it by four seconds;
	-- prefer the live learned-rank base cooldown whenever the client exposes it.
	if AL.playerClass == "PALADIN" and name == "Holy Strike" then
		cd = AL.known and AL.known["Shieldsworn"] and 6 or 10
		local reader = C_Spell and C_Spell.GetSpellBaseCooldown or GetSpellBaseCooldown
		local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
		if type(reader) == "function" then
			local ok, milliseconds = pcall(reader, ref and ref.id or name)
			if ok and not (issecretvalue and issecretvalue(milliseconds))
				and type(milliseconds) == "number" and milliseconds > 1500 and milliseconds < 600000 then
				cd = milliseconds / 1000
			end
		end
	end
	if cd then
		cdExpires[name] = time() + cd
		if preciseCooldownClass then
			preciseCooldowns[name] = { ends = GetTime() + cd, epoch = cdExpires[name] }
		end
	end
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Forever gives every trap one shared thirty-second cooldown. Propagate a
	-- confirmed trap cast so protected cooldown data cannot suggest another.
	if AL.playerClass == "HUNTER" and HUNTER_TRAPS[name] then
		local expiration = time() + 30
		for trap in pairs(HUNTER_TRAPS) do cdExpires[trap] = expiration end
	end
	local buffName, sdur = name, SELF_BUFF_DURATIONS[name]
	if AL.playerClass == "PALADIN" and PALADIN_SEALS[name] then sdur = paladinSealDurations[name] or sdur end
	local alias = CAST_BUFF_ALIASES[name]
	if alias then buffName, sdur = alias[1], alias[2] end
	-- LIKELY fallback when Forever protects auras: classic durations
	-- vary with points spent. A readable tooltip still takes priority.
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
	if AL.playerClass == "SHAMAN" and name == "Flame Shock" then
		local mod = AL.rotations and AL.rotations.SHAMAN
		local ok, adjusted = pcall(function() return mod and mod.FlameShockDuration and mod.FlameShockDuration() end)
		if ok and not (issecretvalue and issecretvalue(adjusted)) and type(adjusted) == "number"
			and adjusted >= 12 and adjusted <= 21 then dur = adjusted end
	end
	if name == "Rupture" and spentCombo and spentCombo > 0 then
		dur = 6 + 2 * spentCombo
	end
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	if AL.playerClass == "ROGUE" and dur and (name == "Rupture" or name == "Garrote" or name == "Death Mark") then
		local mod = AL.rotations and AL.rotations.ROGUE
		local ok, adjusted = pcall(function()
			return mod and mod.DebuffDuration and mod.DebuffDuration(name, spentCombo, dur)
		end)
		if ok and type(adjusted) == "number" and adjusted >= dur and adjusted <= 60 then dur = adjusted end
	end
	local targetExists = AL.SafeBoolean(UnitExists, "target")
	if dur and targetExists ~= false and (not trackedCastClass or not sent or matches) then
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
	local healing = AL.HealingEngine
	if healing and type(healing.OnCastSucceeded) == "function" then
		local ok, message = pcall(healing.OnCastSucceeded, healing, name)
		if not ok and AL.Debug and AL.Debug.CaptureError then
			local protected = issecretvalue and select(2, pcall(issecretvalue, message))
			message = not protected and type(message) == "string" and message
				or "protected cast-tracking error"
			AL.Debug.CaptureError("HealingEngine cast tracking failed: " .. message, "healing engine")
		end
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
		-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
		spellBlacklist = AL.SpellBlacklistState(),
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
		local expiration = cdExpires[spell]
		local precise = preciseCooldowns[spell]
		if Finite(start) and Finite(duration) and start >= 0 and duration >= 0 then
			-- An empty/GCD-only API result must not erase a confirmed Fade.
			-- A readable spell cooldown can still refine its actual expiration.
			if AL.playerClass == "PRIEST" and spell == "Fade" and precise and precise.epoch == expiration then
				if start > 0 and duration > 1.5 then precise.ends = start + duration end
				return precise.ends <= GetTime()
			end
			return start == 0 or duration <= 1.5 or start + duration <= GetTime()
		end
		if precise and precise.epoch == expiration then return precise.ends <= GetTime() end
		return not expiration or expiration <= time()
	end
	if type(start) == "number" and type(duration) == "number"
		and not (issecretvalue and (issecretvalue(start) or issecretvalue(duration))) then
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
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- The two-second readability watchdog runs for every class. Keep learned-rank
-- and localized-name maps for every class as well, including Priest/Warrior,
-- so a localized cast event blacklists the same stable English spell key that
-- the Leveling rotation returns.
AL.castSpellNamesByID, AL.localNames, AL.englishNames = {}, {}, {}

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
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
	-- ERR_SPELL_UNLEARNED tracks the canonical English suggestion. Preserve its
	-- last known localized alias before rebuilding the maps, or a rescan on a
	-- French client immediately resurrects a spell the client rejected.
	local suppressedLocalized = {}
	for english in pairs(AL.unlearned) do
		local native = AL.localNames[english]
		if type(native) == "string" then suppressedLocalized[native] = true end
	end
	wipe(AL.known)
	wipe(AL.rangeSpellRefs)
	wipe(AL.futureSpells)
	wipe(AL.castSpellNamesByID)
	wipe(AL.localNames)
	wipe(AL.englishNames)
	local i, misses = 1, 0
	while misses < 40 and i <= 2048 do
		local ok, name = pcall(BookItemName, i)
		if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" then
			local okF, future = pcall(BookItemIsFuture, i)
			if okF and future == true then
				local okID, spellID = pcall(BookItemSpellID, i)
				AL.futureSpells[#AL.futureSpells + 1] = { name = name, index = i, id = okID and spellID or nil }
			elseif not AL.unlearned[name] and not suppressedLocalized[name] then
				AL.known[name] = true
				local okID, spellID = pcall(BookItemSpellID, i)
				if okID and type(spellID) == "number"
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
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Non-English clients list localized names; map them back through the
	-- rotation's stable spell IDs for both rotation gates and the watchdog.
	do
		local mod = AL.rotations[AL.playerClass]
		for _, entry in ipairs(mod and mod.spells or {}) do
			local id, english = entry[1], entry[2]
			if id == 0 and type(english) == "string" then
				local ref = AL.rangeSpellRefs[english]
				if not ref then
					-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
					-- A 0-ID catalog entry has no language-neutral identity. Resolve
					-- only when the client can itself map the name to a learned book
					-- spell; never substitute a guessed NPC/legacy spell ID.
					local native = AL.SpellName(english)
					if type(native) == "string" and AL.known[native] then
						ref = AL.rangeSpellRefs[native]
						AL.known[english], AL.rangeSpellRefs[english] = true, ref
						AL.localNames[english], AL.englishNames[native] = native, english
					end
				end
				local learnedID = ref and ref.id
				if not (issecretvalue and issecretvalue(learnedID)) and type(learnedID) == "number" and learnedID > 0 then
					id, entry[1] = learnedID, learnedID
				end
			end
			if type(id) == "number" and type(english) == "string" and not AL.known[english] then
				local ok, loc = pcall(AL.SpellName, id)
				if ok and type(loc) == "string" and not (issecretvalue and issecretvalue(loc)) and AL.known[loc] then
					AL.known[english] = true
					AL.rangeSpellRefs[english] = AL.rangeSpellRefs[loc]
					AL.localNames[english], AL.englishNames[loc] = loc, english
				end
			end
			-- Base IDs declared by the rotation provide a fallback for a
			-- confirmed learned spell, without replacing an identity read from the book.
			if type(id) == "number" and id > 0 and AL.known[english] and not AL.castSpellNamesByID[id] then
				AL.castSpellNamesByID[id] = english
			end
		end
	end
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.6
	-- Rogue poison application is a macro/item recommendation, not a player
	-- spellbook entry. It must survive rescans and has its own enchant-state
	-- tracking in Rogue.lua; never use spell API or cast-event watchdog for it.
	if AL.playerClass == "ROGUE" then
		AL.known["Apply Main-Hand Poison"] = true
		AL.known["Apply Off-Hand Poison"] = true
	end
	if trackedCastClass then
		WarlockManaHook("RefreshManaCache")
		RefreshRogueSliceDurations()
	end
	-- Cache every readable learned rank for callers that request artwork by ID.
	for name, texture in pairs(AL.SpellTextureOverrides[AL.playerClass] or {}) do
		local ref = AL.rangeSpellRefs[name]
		local id = ref and ref.id
		if AL.known[name] and type(id) == "number" and not (issecretvalue and issecretvalue(id)) and id > 0 then
			fixedTexturesByID[id] = texture
			local module = AL.rotations[AL.playerClass]
			for _, entry in ipairs(module and module.spells or {}) do
				if entry[1] == 0 and entry[2] == name then entry[1] = id; break end
			end
		end
	end
end

function AL.TargetInMelee()
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- A secret interact result cannot be used in a Lua condition.  Returning nil
	-- makes optional melee actions fail closed until the client exposes a safe
	-- range signal.
	return AL.SafeBoolean(CheckInteractDistance, "target", 3)
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
	if s.p_dead and AL.SafeBoolean(UnitIsDeadOrGhost, "player") == true then return true end
	if s.p_mounted and AL.SafeBoolean(IsMounted) == true then return true end
	if s.p_targeting and AL.SafeBoolean(SpellIsTargeting) == true then return true end
	if s.p_vehicle and UnitInVehicle then
		if AL.SafeBoolean(UnitInVehicle, "player") == true then return true end
	end
	if s.p_loot and LootFrame and LootFrame:IsShown() then return true end
	if s.p_eating and (AL.HasBuff("player", "Food") or AL.HasBuff("player", "Drink")) then return true end
	if s.p_ooc and AL.SafeBoolean(UnitAffectingCombat, "player") == false then return true end
	return false
end

-- Returns spell name, reason
function AL.NextSpell()
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	AL.PruneSpellAttempts()
	local s = AL.S()
	-- Role mode is the authoritative gate for DPS, dungeon healing and tank
	-- threat behavior.  Normalizing here also keeps legacy Paladin/Warrior role
	-- fields synchronized if an external button changed the shared selector.
	if type(AL.GetRotationMode) == "function" then AL.GetRotationMode(s, AL.playerClass) end
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
		-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
		if AL.known[q] and not AL.IsSpellBlacklisted(q) then
			local extra = #AL.queue > 1 and (" (+" .. (#AL.queue - 1) .. ")") or ""
			return q, "queued" .. extra
		end
		table.remove(AL.queue, 1)
	end
	local mod = AL.rotations[AL.playerClass]
	if not mod or not mod.NextSpell then return nil, "Ready" end
	local inCombat = AL.SafeBoolean(UnitAffectingCombat, "player") == true
	local targetExists = AL.SafeBoolean(UnitExists, "target")
	local targetAttackable = AL.SafeBoolean(UnitCanAttack, "player", "target")
	local targetDead = AL.SafeBoolean(UnitIsDeadOrGhost, "target")
	local hostile = targetExists == true and targetAttackable == true
		and not (s.p_targetdead and targetDead ~= false)
	local healing = AL.HealingEngine
	if healing and type(healing.BaseSuggestion) == "function" then
		local ok, spell, reason, handled = pcall(healing.BaseSuggestion, healing, s, inCombat, hostile)
		if ok and handled then return spell, reason end
		if not ok and AL.Debug and AL.Debug.CaptureError then
			local message = type(spell) == "string" and not (issecretvalue and issecretvalue(spell))
				and spell or "Protected base-rule failure"
			if message ~= healing.lastBaseRuleError then
				healing.lastBaseRuleError = message
				AL.Debug.CaptureError("HealingEngine base rules: " .. message, "healing engine")
			end
		end
	end
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Most class modules already call AL.Allowed, which observes the temporary
	-- blacklist. Older Leveling branches sometimes test AL.known directly, so
	-- mask a rejected spell only long enough to ask for their next priority.
	local hidden = {}
	local hadSpellTable = type(s.spells) == "table"
	if not hadSpellTable then s.spells = {} end
	local function RestoreHidden()
		for name, state in pairs(hidden) do
			AL.known[name] = state.known
			if state.hadSetting then s.spells[name] = state.setting else s.spells[name] = nil end
		end
		if not hadSpellTable and next(s.spells) == nil then s.spells = nil end
	end
	for _ = 1, 12 do
		local ok, spell, reason = pcall(mod.NextSpell, s, inCombat, hostile)
		if not ok then
			RestoreHidden()
			error(spell)
		end
		if not spell or not AL.IsSpellBlacklisted(spell) then
			RestoreHidden()
			return spell, reason
		end
		if hidden[spell] then
			RestoreHidden()
			return nil, spell .. " temporarily skipped"
		end
		hidden[spell] = {
			known = AL.known[spell],
			hadSetting = s.spells[spell] ~= nil,
			setting = s.spells[spell],
		}
		AL.known[spell], s.spells[spell] = nil, false
	end
	RestoreHidden()
	return nil, "Temporarily skipped unreadable spell icons"
end
