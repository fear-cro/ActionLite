local ADDON, AL = ...

-- WoW Forever Warrior DPS / Tank leveling 1-30
-- ActionLITE Warrior rotation v0.7.11
-- Cible : beta 1.60.1.69913
-- Donnees : extraction client 1.60.1.69876, inchangee dans 69893/69913.
-- Statut : LIKELY jusqu'a validation directe dans le client Forever cible.

local A = _G.Action

local M = {
	defaults = {
		warriorRole = "DPS",
		shout = true,
		rend = true,
		hamstring = false,
		sunder = true,
		sunderMaxStacks = 2,
		slamReserveRage = 30,
		overpower = true,
		victory = true,
		heroic = true,
		execute = true,
		bloodrage = true,
		revenge = true,
		slam = true,
		spear = true,
		demo = false,
		aoe = false,
		aoeMinEnemies = 2,
		cleaveDumpRage = 60,
		sweepingReserveRage = 50,
		tankAutoStance = true,
		tankTaunt = true,
		tankAoETaunt = true,
		tankInterrupt = true,
		tankShieldBlock = true,
		tankShieldWall = true,
		tankDemo = true,
		tankSunderMaxStacks = 5,
		tankHeroicDumpRage = 20,
		tankCleaveDumpRage = 20,
		tankShieldWallHP = 35,
	},
}

-- Upgrade the old stock Tank threshold once. Other user-selected thresholds,
-- and all changes made after this upgrade, remain saved as chosen.
function M.InitializeProtectionSettings(s)
	if type(s) ~= "table" or s.protectionAttacksVersion == 1 then return end
	local heroic = tonumber(s.tankHeroicDumpRage)
	if heroic == nil or heroic == 70 then s.tankHeroicDumpRage = 20 end
	if tonumber(s.tankCleaveDumpRage) == nil then s.tankCleaveDumpRage = 20 end
	s.protectionAttacksVersion = 1
end

-- ==========================================================================
-- DATA
-- ==========================================================================

-- IDs de rang 1 utilises pour identifier et afficher les sorts.
M.spells = {
	{ 6673, "Battle Shout" },
	{ 2457, "Battle Stance" },
	{ 2458, "Berserker Stance" },
	{ 2687, "Bloodrage" },
	{ 1161, "Challenging Shout" },
	{ 100, "Charge" },
	{ 845, "Cleave" },
	{ 71, "Defensive Stance" },
	{ 1160, "Demoralizing Shout" },
	{ 676, "Disarm" },
	{ 5308, "Execute" },
	{ 1715, "Hamstring" },
	{ 78, "Heroic Strike" },
	{ 20252, "Intercept" },
	{ 5246, "Intimidating Shout" },
	{ 694, "Mocking Blow" },
	{ 7384, "Overpower" },
	{ 772, "Rend" },
	{ 20230, "Retaliation" },
	{ 6572, "Revenge" },
	{ 72, "Shield Bash" },
	{ 2565, "Shield Block" },
	{ 871, "Shield Wall" },
	{ 1240193, "Slam" },            -- Forever Rank 1, niveau 20
	{ 7386, "Sunder Armor" },
	{ 355, "Taunt" },
	{ 6343, "Thunder Clap" },
	{ 402927, "Victory Rush" },     -- Forever, niveau 20
	{ 1310222, "Spearing Strike" }, -- Talent Arms, rang 4
	{ 12292, "Sweeping Strikes" },  -- Talent Arms, rang 5
}

-- Le spellbook Forever peut exposer des sorts avant leur apprentissage reel.
local MINLEVEL = {
	["Heroic Strike"] = 1,
	["Battle Shout"] = 1,
	["Battle Stance"] = 1,
	["Charge"] = 4,
	["Rend"] = 4,
	["Thunder Clap"] = 6,
	["Hamstring"] = 8,
	["Bloodrage"] = 10,
	["Sunder Armor"] = 10,
	["Taunt"] = 10,
	["Defensive Stance"] = 10,
	["Overpower"] = 12,
	["Shield Bash"] = 12,
	["Revenge"] = 14,
	["Demoralizing Shout"] = 14,
	["Mocking Blow"] = 16,
	["Shield Block"] = 16,
	["Disarm"] = 18,
	["Cleave"] = 20,
	["Retaliation"] = 20,
	["Victory Rush"] = 20,
	["Slam"] = 20,
	["Intimidating Shout"] = 22,
	["Execute"] = 24,
	["Spearing Strike"] = 25, -- premier acces theorique a la rangee 4 Arms
	["Challenging Shout"] = 26,
	["Shield Wall"] = 28,
	["Berserker Stance"] = 30,
	["Intercept"] = 30,
	["Sweeping Strikes"] = 30,
}

local Ok, OkReady, Known = AL.LevelGates(MINLEVEL)
M.minLevels = MINLEVEL

-- ==========================================================================
-- TUNING
-- ==========================================================================

local REND_STOP_HP = 35
local REND_MIN_TTD = 8
local REND_UNREADABLE_HP_WINDOW = 12

local SUNDER_STOP_HP = 60
local SUNDER_MIN_TTD = 8
local SUNDER_MAX_STACKS = 5

local BLOODRAGE_MAX_RAGE = 20
local BLOODRAGE_MIN_HP = 75
local BLOODRAGE_PROTECTED_OPENER = 6

local SLAM_RESERVE_RAGE = 30
local SWING_WINDOW = 0.45
M.swingWindow = SWING_WINDOW

local SWEEPING_RESERVE_RAGE = 50
local CLEAVE_DUMP_RAGE = 60
local HEROIC_DUMP_RAGE = 75

local RAGE_OVERFLOW_DUMP = 80
local CLEAVE_AUTO_RANGE = 7

local LOCAL_COOLDOWNS = {
	["Victory Rush"] = 30,
	["Slam"] = 18,
	["Spearing Strike"] = 20,
	["Sweeping Strikes"] = 30,
	["Thunder Clap"] = 6,
	["Shield Block"] = 5,
}

-- ==========================================================================
-- TRACKERS LEGERS
-- ==========================================================================

-- ActionLITE doit rester autonome. Ces trackers ne servent que lorsque les
-- lectures d'aura/cooldown deviennent secretes en combat sur le client 1.60.
local localCooldowns = {}
local localCastAt = {}
local lastSwingAt = 0
local battleShoutExpires = 0
local combatStartedAt = 0
local rendWindowStartedAt = 0

local trackedTargetGUID
local rendExpires = 0
local demoExpires = 0
local sunderStacks = 0
local sunderExpires = 0
local lastCoreSunderExpires = 0

local function SafeValue(value)
	return not (issecretvalue and issecretvalue(value))
end

local function TargetGUID()
	local ok, guid = pcall(UnitGUID, "target")
	if not ok or type(guid) ~= "string" or not SafeValue(guid) then return nil end
	return guid
end

-- Hamstring owns its cast/target state so this two-file update works with the
-- current Core, including when combat aura reads or success IDs are protected.
local HAMSTRING_DURATION = 15
local hamstringDuration = HAMSTRING_DURATION
local hamstringTargets, hamstringCasts = {}, {}
local hamstringLastSent, hamstringLastSucceeded
local hamstringTargetEpoch = 0
local hamstringAuraCache, hamstringAurasBlocked

local function HamstringTargetKey()
	return TargetGUID() or hamstringTargetEpoch
end

local function HamstringNumber(value)
	if SafeValue(value) and type(value) == "number" and value == value
		and value ~= math.huge and value ~= -math.huge then return value end
end

local function HamstringSpellID(id)
	id = HamstringNumber(id)
	if not id then return false end
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs["Hamstring"]
	local learned = ref and HamstringNumber(ref.id)
	return (learned and id == learned) or id == 1715 or id == 7372 or id == 7373
end

local function HamstringCastIdentity(arg2, arg3, arg4)
	local id = HamstringNumber(arg4) or HamstringNumber(arg3)
	if id then return HamstringSpellID(id) end
	if SafeValue(arg2) and type(arg2) == "string" then
		local name = (AL.englishNames and AL.englishNames[arg2]) or arg2
		if name == "Hamstring" then return true end
		if AL.known and AL.known[name] then return false end
	end
end

local function HamstringCastGUID(value)
	if SafeValue(value) and type(value) == "string" and value:find("^Cast%-") then return value end
end

local function PruneHamstring()
	local now = GetTime()
	for key, entry in pairs(hamstringTargets) do
		if entry.expires <= now then hamstringTargets[key] = nil end
	end
	for guid, entry in pairs(hamstringCasts) do
		if now - entry.at > 20 then hamstringCasts[guid] = nil end
	end
end

local function HamstringApplied(key)
	local now = GetTime()
	hamstringTargets[key] = { expires = now + hamstringDuration, appliedAt = now }
	hamstringAuraCache = nil
end

local hamstringTracker = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_TARGET_CHANGED",
	"PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_AURA" }) do
	pcall(hamstringTracker.RegisterEvent, hamstringTracker, event)
end
pcall(hamstringTracker.RegisterEvent, hamstringTracker, "COMBAT_LOG_EVENT_UNFILTERED")
hamstringTracker:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
	if AL.playerClass ~= "WARRIOR" then return end
	if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
		hamstringTargets, hamstringCasts = {}, {}
		hamstringLastSent, hamstringLastSucceeded = nil, nil
		hamstringTargetEpoch = hamstringTargetEpoch + 1
		hamstringAuraCache, hamstringAurasBlocked = nil, nil
		return
	elseif event == "PLAYER_TARGET_CHANGED" then
		hamstringTargetEpoch = hamstringTargetEpoch + 1
		hamstringAuraCache = nil
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		hamstringLastSent = nil
		hamstringAuraCache, hamstringAurasBlocked = nil, nil
		return
	elseif event == "UNIT_AURA" then
		if SafeValue(unit) and unit == "target" then hamstringAuraCache = nil end
		return
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if type(CombatLogGetCurrentEventInfo) ~= "function" then return end
		local ok, _, subEvent, _, source, _, _, _, dest, _, _, _, spellID = pcall(CombatLogGetCurrentEventInfo)
		local okPlayer, player = pcall(UnitGUID, "player")
		if not ok or not okPlayer or not SafeValue(subEvent) or not SafeValue(source)
			or not SafeValue(player) or not SafeValue(dest) or type(dest) ~= "string"
			or source ~= player or not HamstringSpellID(spellID) then return end
		if subEvent == "SPELL_MISSED" or subEvent == "SPELL_AURA_REMOVED" then
			hamstringTargets[dest] = nil
			hamstringAuraCache = nil
		elseif subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH" then
			HamstringApplied(dest)
		end
		return
	end
	if not SafeValue(unit) or unit ~= "player" then return end
	PruneHamstring()
	local guidValue = arg2
	if event == "UNIT_SPELLCAST_SENT" then guidValue = arg3 end
	local guid = HamstringCastGUID(guidValue)
	local identity = HamstringCastIdentity(arg2, arg3, arg4)
	if event == "UNIT_SPELLCAST_SENT" then
		hamstringLastSent = nil
		if identity == nil then
			identity = AL.lastSuggestion == "Hamstring" and AL.Profile("WARRIOR").hamstring == true
		end
		if identity ~= true then return end
		local entry = { at = GetTime(), target = HamstringTargetKey() }
		-- A mouseover/focus cast must not mark the selected enemy as slowed.
		if SafeValue(arg2) and type(arg2) == "string" and arg2 ~= "" and type(UnitName) == "function" then
			local ok, targetName, realm = pcall(UnitName, "target")
			if ok and SafeValue(targetName) and type(targetName) == "string" then
				local fullName = targetName
				if SafeValue(realm) and type(realm) == "string" and realm ~= "" then fullName = targetName .. "-" .. realm end
				if arg2 ~= targetName and arg2 ~= fullName then entry.failed = true end
			end
		end
		hamstringLastSent = entry
		if guid then hamstringCasts[guid] = entry end
		return
	end
	local entry = guid and hamstringCasts[guid] or (not guid and hamstringLastSent)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		if entry then entry.failed = true end
		return
	end
	if identity == false or not entry or entry.failed or entry.done
		or (guid and guid == hamstringLastSucceeded) then return end
	if GetTime() - entry.at > 5 then return end
	entry.done = true
	hamstringLastSucceeded = guid
	HamstringApplied(entry.target)
end)

local function HamstringAuraState(key)
	local now = GetTime()
	if hamstringAuraCache and hamstringAuraCache.key == key and now - hamstringAuraCache.at < 0.2 then
		return hamstringAuraCache.active
	end
	if hamstringAurasBlocked then return nil end
	local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if type(reader) ~= "function" then return nil end
	local complete = true
	for i = 1, 40 do
		local ok, aura = pcall(reader, "target", i, "HARMFUL")
		if not ok or not SafeValue(aura) then hamstringAurasBlocked = true; return nil end
		if aura == nil then
			local state
			if complete then state = false end
			hamstringAuraCache = { key = key, at = now, active = state }
			return state
		end
		if type(aura) ~= "table" then return nil end
		local id = HamstringNumber(aura.spellId)
		local name = SafeValue(aura.name) and type(aura.name) == "string" and aura.name or nil
		if name then name = (AL.englishNames and AL.englishNames[name]) or name end
		if HamstringSpellID(id) or name == "Hamstring" then
			local duration, expires = HamstringNumber(aura.duration), HamstringNumber(aura.expirationTime)
			if duration and duration > 0 and duration <= 60 then hamstringDuration = duration end
			local active = expires == nil or expires == 0 or expires > now
			hamstringAuraCache = { key = key, at = now, active = active }
			return active
		end
		if not id and not name then complete = false end
	end
	-- A truncated scan cannot prove the debuff is missing.
end

local function HamstringActive()
	PruneHamstring()
	local key = HamstringTargetKey()
	local entry = hamstringTargets[key]
	if entry and GetTime() - entry.appliedAt < 0.5 then return true end
	local state = HamstringAuraState(key)
	if state ~= nil then
		if state == false then hamstringTargets[key] = nil end
		return state
	end
	local ok, active = pcall(AL.HasDebuff, "target", "Hamstring")
	if ok and SafeValue(active) and active == true then return true end
	return entry ~= nil and entry.expires > GetTime()
end

local function ResetTargetTrackers()
	trackedTargetGUID = TargetGUID()
	rendWindowStartedAt = GetTime()
	rendExpires = 0
	demoExpires = 0
	sunderStacks = 0
	sunderExpires = 0
	lastCoreSunderExpires = 0
end

local function PlayerLevel()
	local level = UnitLevel and UnitLevel("player") or nil
	if type(level) ~= "number" or not SafeValue(level) then return nil end
	return level
end

local function RendDuration()
	local level = PlayerLevel() or 1
	if level >= 30 then return 18 end
	if level >= 20 then return 15 end
	if level >= 10 then return 12 end
	return 9
end

local function TrackSuccessfulCast(name, targetMatches)
	local now = GetTime()
	local cooldown = LOCAL_COOLDOWNS[name]
	if cooldown then
		localCastAt[name] = now
		local expires = now + cooldown
		-- Use readable learned-rank cooldowns, including rate changes, when
		-- available. GCD-only/stale data must not replace the spell fallback.
		local reader = C_Spell and C_Spell.GetSpellCooldown
		local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
		if type(reader) == "function" then
			local ok, info = pcall(reader, ref and HamstringNumber(ref.id) or name)
			if ok and SafeValue(info) and type(info) == "table" then
				local start = HamstringNumber(info.startTime)
				local duration = HamstringNumber(info.duration)
				local rate = HamstringNumber(info.modRate) or 1
				if start and start > 0 and duration and duration > 1.5 and rate > 0 then
					local nativeEnd = start + duration / rate
					if nativeEnd > now then expires = nativeEnd end
				end
			end
		end
		localCooldowns[name] = expires
	end

	local guid = TargetGUID()
	if guid and guid ~= trackedTargetGUID then ResetTargetTrackers() end

	if name == "Battle Shout" then
		battleShoutExpires = now + 180
		return
	end
	if targetMatches == false then return end
	if name == "Rend" and (guid or targetMatches) then
		rendExpires = now + RendDuration()
	elseif name == "Demoralizing Shout" and (guid or targetMatches) then
		demoExpires = now + 30
	elseif name == "Sunder Armor" and (guid or targetMatches) then
		sunderStacks = math.min(SUNDER_MAX_STACKS, sunderStacks + 1)
		sunderExpires = now + 30
	end
end

local TRACKED_CASTS = {
	["Rend"] = true,
	["Demoralizing Shout"] = true,
	["Sunder Armor"] = true,
	["Victory Rush"] = true,
	["Slam"] = true,
	["Spearing Strike"] = true,
	["Sweeping Strikes"] = true,
	["Thunder Clap"] = true,
	["Battle Shout"] = true,
	["Shield Block"] = true,
}

local function TrackedCastName(arg2, arg3, arg4)
	local function Read(value)
		if SafeValue(value) then
			if type(value) == "string" and TRACKED_CASTS[value] then
				return value
			elseif type(value) == "number" then
				local ok, name = pcall(AL.SpellName, value)
				if ok and SafeValue(name) and type(name) == "string" then
					name = (AL.englishNames and AL.englishNames[name]) or name
					-- Sweeping Strikes damage procs have the same name as its
					-- activation. Only the cast spell can restart its cooldown.
					if name == "Sweeping Strikes" then
						local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
						local learned = ref and HamstringNumber(ref.id)
						if value ~= 12292 and value ~= learned then return nil end
					end
					if TRACKED_CASTS[name] then return name end
				end
			end
		end
	end
	return Read(arg4) or Read(arg3) or Read(arg2)
end

local pendingTrackedCast
local finishedTrackedCasts = {}
local function PruneTrackedCasts()
	for guid, at in pairs(finishedTrackedCasts) do
		if GetTime() - at > 30 then finishedTrackedCasts[guid] = nil end
	end
end

local tracker = CreateFrame("Frame")
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("PLAYER_TARGET_CHANGED")
tracker:RegisterEvent("PLAYER_REGEN_DISABLED")
tracker:RegisterEvent("PLAYER_REGEN_ENABLED")
tracker:RegisterEvent("PLAYER_DEAD")
pcall(tracker.RegisterEvent, tracker, "COMBAT_LOG_EVENT_UNFILTERED")
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
	if not pcall(tracker.RegisterUnitEvent, tracker, event, "player") then
		pcall(tracker.RegisterEvent, tracker, event)
	end
end

tracker:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
	if event == "PLAYER_ENTERING_WORLD" then
		pendingTrackedCast, finishedTrackedCasts = nil, {}
		ResetTargetTrackers()
		lastSwingAt = 0
		combatStartedAt = 0

		if type(UnitAffectingCombat) == "function" then
			local ok, active = pcall(UnitAffectingCombat, "player")
			if ok and SafeValue(active) and active then
				combatStartedAt = GetTime()
				rendWindowStartedAt = combatStartedAt
			end
		end
		return
	end

	if event == "PLAYER_TARGET_CHANGED" then
		ResetTargetTrackers()
		lastSwingAt = 0
		return
	end

	if event == "PLAYER_REGEN_DISABLED" then
		combatStartedAt = GetTime()
		rendWindowStartedAt = combatStartedAt
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		combatStartedAt = 0
		rendWindowStartedAt = 0
		lastSwingAt = 0
		return
	end

	if event == "PLAYER_DEAD" then
		pendingTrackedCast, finishedTrackedCasts = nil, {}
		battleShoutExpires = 0
		ResetTargetTrackers()
		combatStartedAt = 0
		rendWindowStartedAt = 0
		lastSwingAt = 0
		return
	end

	if event == "UNIT_SPELLCAST_SENT" then
		if not SafeValue(unit) or unit ~= "player" then return end
		PruneTrackedCasts()
		local name = TrackedCastName(arg2, arg3, arg4)
		-- A readable different spell ID must never inherit the recommendation.
		if not name and HamstringNumber(arg3) == nil and HamstringNumber(arg4) == nil then
			local suggestion = AL.lastSuggestion
			if SafeValue(suggestion) and TRACKED_CASTS[suggestion] then name = suggestion end
		end
		local targetKey = HamstringTargetKey()
		if type(UnitName) == "function" and SafeValue(arg2) and type(arg2) == "string" then
			local ok, targetName, realm = pcall(UnitName, "target")
			if ok and SafeValue(targetName) and type(targetName) == "string" then
				local fullName = targetName
				if SafeValue(realm) and type(realm) == "string" and realm ~= "" then fullName = targetName .. "-" .. realm end
				if arg2 ~= "" and arg2 ~= targetName and arg2 ~= fullName then targetKey = nil end
			end
		end
		pendingTrackedCast = name and { name = name, at = GetTime(),
			guid = HamstringCastGUID(arg3), targetKey = targetKey } or nil
		return
	end
	if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
		or event == "UNIT_SPELLCAST_INTERRUPTED" then
		if not SafeValue(unit) or unit ~= "player" then return end
		local guid = HamstringCastGUID(arg2)
		if guid then finishedTrackedCasts[guid] = GetTime() end
		if not guid or not pendingTrackedCast or not pendingTrackedCast.guid
			or guid == pendingTrackedCast.guid then pendingTrackedCast = nil end
		return
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if not SafeValue(unit) or unit ~= "player" then return end
		PruneTrackedCasts()
		local guid = HamstringCastGUID(arg2)
		if guid and finishedTrackedCasts[guid] then return end
		local sent = pendingTrackedCast
		local matches = sent and GetTime() - sent.at <= 5
			and (not guid or not sent.guid or guid == sent.guid)
		local name = TrackedCastName(arg2, arg3, arg4)
		if not name and matches and HamstringNumber(arg3) == nil and HamstringNumber(arg4) == nil then
			name = sent.name
		end
		if matches then pendingTrackedCast = nil end
		if name then
			if guid then finishedTrackedCasts[guid] = GetTime() end
			local targetMatches = matches and sent.targetKey ~= nil and sent.targetKey == HamstringTargetKey()
				or (not matches and TargetGUID() ~= nil)
			TrackSuccessfulCast(name, targetMatches)
		end
		return
	end

	if event ~= "COMBAT_LOG_EVENT_UNFILTERED" or not CombatLogGetCurrentEventInfo then return end

	local ok, _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, _, spellName, _, _, amount =
		pcall(CombatLogGetCurrentEventInfo)
	if not ok or not SafeValue(subEvent) or not SafeValue(sourceGUID) then return end
	if sourceGUID ~= UnitGUID("player") then return end

	if subEvent == "SWING_DAMAGE" or subEvent == "SWING_MISSED" then
		lastSwingAt = GetTime()
		return
	end

	if not SafeValue(spellName) or (spellName ~= "Rend" and spellName ~= "Sunder Armor"
		and spellName ~= "Demoralizing Shout") then return end
	local targetGUID = TargetGUID()
	if not targetGUID or (SafeValue(destGUID) and destGUID ~= targetGUID) then return end

	if spellName == "Demoralizing Shout" then
		if subEvent == "SPELL_MISSED" or subEvent == "SPELL_AURA_REMOVED" then
			demoExpires = 0
		elseif subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH" then
			demoExpires = GetTime() + 30
		end
		return
	end

	if subEvent == "SPELL_MISSED" then
		if spellName == "Rend" then
			rendExpires = 0
		else
			sunderStacks = math.max(0, sunderStacks - 1)
		end
	elseif subEvent == "SPELL_AURA_REMOVED" then
		if spellName == "Rend" then
			rendExpires = 0
		else
			sunderStacks = 0
			sunderExpires = 0
		end
	elseif spellName == "Rend" and subEvent == "SPELL_AURA_APPLIED" then
		rendExpires = GetTime() + RendDuration()
	elseif spellName == "Sunder Armor" then
		if subEvent == "SPELL_AURA_APPLIED" then
			sunderStacks = math.max(1, sunderStacks)
			sunderExpires = GetTime() + 30
		elseif subEvent == "SPELL_AURA_APPLIED_DOSE" then
			if type(amount) == "number" and SafeValue(amount) then
				sunderStacks = math.min(SUNDER_MAX_STACKS, amount)
			end
			sunderExpires = GetTime() + 30
		end
	end
end)

-- ==========================================================================
-- HELPERS
-- ==========================================================================

local function HasRage(rage, amount)
	-- Forever masque parfois la rage en combat. nil signifie "inconnue", pas
	-- "zero" : dans ce cas SpellUsable et l'ordre de priorite gardent la
	-- rotation active au lieu de bloquer tous les sorts consommateurs.
	return rage == nil or (type(rage) == "number" and rage >= amount)
end

local function SettingNumber(s, key, defaultValue, minValue, maxValue)
	local value = tonumber(s and s[key])
	if value == nil then value = defaultValue end
	value = math.floor(value + 0.5)
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

local function LocalReady(name)
	local expires = localCooldowns[name]
	if name == "Shield Block" or name == "Thunder Clap" or name == "Sweeping Strikes" then
		return not expires or expires <= GetTime()
	end
	return not expires or expires - GetTime() <= 0.2
end

local function ReadyUsable(name)
	return Ok(name)
		and LocalReady(name)
		and AL.SpellUsable(name)
		and AL.IsReady(name)
end

local function TargetTTD()
	if not A or not A.Unit then return nil end
	local okUnit, unit = pcall(A.Unit, "target")
	if not okUnit or not unit or not unit.TimeToDie then return nil end
	local okTTD, ttd = pcall(unit.TimeToDie, unit)
	if not okTTD or not SafeValue(ttd) or type(ttd) ~= "number" or ttd <= 0 or ttd >= 500 then return nil end
	return ttd
end

local NAMEPLATE_UNITS = {}
for i = 1, 40 do
	NAMEPLATE_UNITS[i] = "nameplate" .. i
end

local enemyCountDebug = {
	source = "nameplate/threat/heroic-range",
	existing = 0,
	hostile = 0,
	combat = 0,
	threat = 0,
	melee = 0,
	qualified = 0,
	unreadable = false,
}

local function SafeUnitExists(unit)
	if type(UnitExists) ~= "function" then return false end
	local ok, value = pcall(UnitExists, unit)
	return ok and SafeValue(value) and value and true or false
end

local function SafeCanAttack(unit)
	if type(UnitCanAttack) ~= "function" then return nil end
	local ok, value = pcall(UnitCanAttack, "player", unit)
	if not ok or not SafeValue(value) or type(value) ~= "boolean" then return nil end
	return value
end

local function SafeUnitCombat(unit)
	if type(UnitAffectingCombat) ~= "function" then return nil end
	local ok, value = pcall(UnitAffectingCombat, unit)
	if not ok or not SafeValue(value) or type(value) ~= "boolean" then return nil end
	return value
end

local function SafeThreat(unit)
	if type(UnitThreatSituation) ~= "function" then return nil, false end
	local ok, value = pcall(UnitThreatSituation, "player", unit)
	if not ok or not SafeValue(value) then return nil, false end
	if value == nil then return nil, true end -- readable: absent from our threat table
	if type(value) ~= "number" then return nil, false end
	return value, true
end

local function HeroicStrikeInRange(unit)
	local identifiers = {}
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs["Heroic Strike"]
	if type(ref) == "table" and ref.id then identifiers[#identifiers + 1] = ref.id end
	identifiers[#identifiers + 1] = "Heroic Strike"

	for _, identifier in ipairs(identifiers) do
		if C_Spell and type(C_Spell.IsSpellInRange) == "function" then
			local ok, value = pcall(C_Spell.IsSpellInRange, identifier, unit)
			if ok and SafeValue(value) and type(value) == "boolean" then
				return value, "C_Spell.IsSpellInRange"
			end
		end

		if type(IsSpellInRange) == "function" then
			local ok, value = pcall(IsSpellInRange, identifier, unit)
			if ok and SafeValue(value) then
				if value == 1 or value == true then return true, "IsSpellInRange" end
				if value == 0 or value == false then return false, "IsSpellInRange" end
			end
		end
	end

	return nil, "unreadable"
end

local function EnemyCountMelee(limit)
	enemyCountDebug.existing = 0
	enemyCountDebug.hostile = 0
	enemyCountDebug.combat = 0
	enemyCountDebug.threat = 0
	enemyCountDebug.melee = 0
	enemyCountDebug.qualified = 0
	enemyCountDebug.unreadable = false

	-- Production detector validated against two simultaneous attackers:
	-- visible hostile nameplate + combat + player threat table + Heroic Strike range.
	-- Heroic Strike is a conservative melee gate inside the requested 7 yd radius.
	if type(UnitExists) ~= "function"
		or type(UnitCanAttack) ~= "function"
		or type(UnitAffectingCombat) ~= "function"
		or type(UnitThreatSituation) ~= "function"
	then
		enemyCountDebug.source = "required API unavailable"
		return nil
	end

	enemyCountDebug.source = "nameplate/threat/heroic-range"

	local count = 0
	local seen = {}
	local stopAt = type(limit) == "number" and math.max(2, limit) or 5

	for i = 1, #NAMEPLATE_UNITS do
		local unit = NAMEPLATE_UNITS[i]
		if SafeUnitExists(unit) then
			enemyCountDebug.existing = enemyCountDebug.existing + 1

			local guid
			if type(UnitGUID) == "function" then
				local okGUID, value = pcall(UnitGUID, unit)
				if okGUID and SafeValue(value) and type(value) == "string" then
					guid = value
				end
			end

			if not guid or not seen[guid] then
				if guid then seen[guid] = true end

				local hostile = SafeCanAttack(unit)
				if hostile == nil then enemyCountDebug.unreadable = true end
				if hostile then
					enemyCountDebug.hostile = enemyCountDebug.hostile + 1

					local combat = SafeUnitCombat(unit)
					if combat == nil then enemyCountDebug.unreadable = true end
					if combat then
						enemyCountDebug.combat = enemyCountDebug.combat + 1

						local threat, readable = SafeThreat(unit)
						if not readable then enemyCountDebug.unreadable = true end
						if threat ~= nil then
							enemyCountDebug.threat = enemyCountDebug.threat + 1

							local inRange = HeroicStrikeInRange(unit)
							if inRange == nil then enemyCountDebug.unreadable = true end
							if inRange == true then
								enemyCountDebug.melee = enemyCountDebug.melee + 1
								count = count + 1
								enemyCountDebug.qualified = count

								if count >= stopAt then
									return count
								end
							end
						end
					end
				end
			end
		end
	end

	return count
end


local function TauntableEnemyCount(limit)
	return EnemyCountMelee(limit or 3)
end

local function PlayerStance()
	if GetShapeshiftForm then
		local ok, stance = pcall(GetShapeshiftForm)
		if ok and type(stance) == "number" and SafeValue(stance) then return stance end
	end
	if A and A.Player and A.Player.GetStance then
		local ok, stance = pcall(A.Player.GetStance, A.Player)
		if ok and type(stance) == "number" and SafeValue(stance) then return stance end
	end
	return nil
end

local function WarriorRole(s)
	if PlayerStance() == 2 then return "TANK" end
	return s and s.warriorRole == "TANK" and "TANK" or "DPS"
end


local function SpellRangeState(name)
	local identifiers = {}
	local seen = {}

	local function Add(value)
		if value == nil or seen[value] then return end
		seen[value] = true
		identifiers[#identifiers + 1] = value
	end

	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	if type(ref) == "table" then Add(ref.id) end
	Add(name)

	for _, identifier in ipairs(identifiers) do
		if C_Spell and type(C_Spell.IsSpellInRange) == "function" then
			local ok, value = pcall(C_Spell.IsSpellInRange, identifier, "target")
			if ok and SafeValue(value) and type(value) == "boolean" then
				return value, "C_Spell.IsSpellInRange"
			end
		end

		if type(IsSpellInRange) == "function" then
			local ok, value = pcall(IsSpellInRange, identifier, "target")
			if ok and SafeValue(value) then
				if value == 1 or value == true then return true, "IsSpellInRange" end
				if value == 0 or value == false then return false, "IsSpellInRange" end
			end
		end
	end

	return nil, "range unreadable"
end

local lastChargeRange = nil
local lastChargeRangeSource = "not checked"
local lastChargeBlockReason = nil

local function ChargeAvailable()
	lastChargeRange = nil
	lastChargeRangeSource = "not checked"
	lastChargeBlockReason = nil

	if not OkReady("Charge") then
		lastChargeBlockReason = "not learned / cooldown"
		return false
	end

	if not AL.SpellUsable("Charge") then
		lastChargeBlockReason = "not usable"
		return false
	end

	if AL.TargetInMelee() then
		lastChargeRange = false
		lastChargeRangeSource = "melee check"
		lastChargeBlockReason = "target already in melee"
		return false
	end

	local stance = PlayerStance()
	if type(stance) == "number" and stance ~= 1 then
		lastChargeBlockReason = "not in Battle Stance"
		return false
	end

	local inRange, source = SpellRangeState("Charge")
	lastChargeRange = inRange
	lastChargeRangeSource = source

	if inRange ~= true then
		lastChargeBlockReason =
			inRange == false and "outside Charge range" or "Charge range unreadable"
		return false
	end

	return true
end

-- true = bouclier confirme, false = absence confirmee, nil = API illisible.
local function ShieldEquipped()
	if not GetInventoryItemID then return nil end
	local okID, itemID = pcall(GetInventoryItemID, "player", 17)
	if not okID or not SafeValue(itemID) then return nil end
	if not itemID then return false end
	if not GetItemInfoInstant then return nil end
	local ok, _, _, _, equipLoc, _, classID, subClassID = pcall(GetItemInfoInstant, itemID)
	if not ok then return nil end
	if equipLoc == "INVTYPE_SHIELD" then return true end
	if type(classID) == "number" and type(subClassID) == "number" then
		return classID == 4 and subClassID == 6
	end
	return nil
end

local function TargetNeedsTaunt()
	if not UnitExists or not UnitExists("targettarget") then return false end
	if UnitIsUnit then
		local okSelf, isSelf = pcall(UnitIsUnit, "targettarget", "player")
		if okSelf and isSelf then return false end
	end
	if UnitIsFriend then
		local okFriend, isFriend = pcall(UnitIsFriend, "player", "targettarget")
		if okFriend and isFriend then return true end
	end
	return false
end

local function TankSunderCap(s)
	return SettingNumber(s, "tankSunderMaxStacks", 5, 0, SUNDER_MAX_STACKS)
end

local function PlayerMoving()
	if A and A.Player and A.Player.IsMoving then
		local ok, moving = pcall(A.Player.IsMoving, A.Player)
		if ok and type(moving) == "boolean" then return moving end
	end
	if GetUnitSpeed then
		local ok, speed = pcall(GetUnitSpeed, "player")
		if ok and type(speed) == "number" and SafeValue(speed) then return speed > 0 end
	end
	return false
end

local function SlamTimingState()
	if PlayerMoving() then return false, "moving" end

	if lastSwingAt > 0 then
		local elapsed = GetTime() - lastSwingAt
		if elapsed <= SWING_WINDOW then
			return true, "combat-log swing"
		end

		-- If combat-log swing tracking has actually produced data, keep honoring
		-- the post-swing optimization instead of casting at a random point.
		if type(CombatLogGetCurrentEventInfo) == "function" then
			return false, "waiting post-swing"
		end
	end

	-- Use the Action swing tracker when it exists.
	if A and A.Player and A.Player.GetSwing and A.Player.GetSwingMax then
		local okRemains, remains = pcall(A.Player.GetSwing, A.Player, 1)
		local okMax, maximum = pcall(A.Player.GetSwingMax, A.Player, 1)
		if okRemains and okMax
			and type(remains) == "number"
			and type(maximum) == "number"
			and maximum > 0
		then
			return remains > 0 and remains >= maximum - SWING_WINDOW,
				"Action swing tracker"
		end
	end

	-- Forever 1.60 can hide/remove both swing timing sources. nil means
	-- "timing unavailable", not "Slam forbidden".
	return nil, "swing timing unavailable"
end

local function RendActive()
	local guid = TargetGUID()
	if guid and guid ~= trackedTargetGUID then ResetTargetTrackers() end
	return rendExpires > GetTime() or AL.HasDebuff("target", "Rend")
end

local function MaintainHamstring(s, rage, inMelee)
	if s.hamstring ~= true or not ReadyUsable("Hamstring") then return nil end
	local stance = PlayerStance()
	if stance and stance ~= 1 and stance ~= 3 then return nil end
	local cost = 10
	local reader = C_Spell and C_Spell.GetSpellPowerCost
	if type(reader) == "function" then
		local ref = AL.rangeSpellRefs and AL.rangeSpellRefs["Hamstring"]
		local id = ref and HamstringNumber(ref.id) or 1715
		local ok, costs = pcall(reader, id)
		if ok and SafeValue(costs) and type(costs) == "table" then
			for _, power in ipairs(costs) do
				if SafeValue(power) and type(power) == "table" and HamstringNumber(power.type) == 1 then
					local amount = HamstringNumber(power.cost)
					if amount and amount >= 0 then cost = amount; break end
				end
			end
		end
	end
	if not HasRage(rage, cost) then return nil end
	local inRange = SpellRangeState("Hamstring")
	if inRange == false or (inRange ~= true and inMelee ~= true) then return nil end
	if not HamstringActive() then return "Hamstring", "maintain target slow" end
end

local function DemoActive()
	local guid = TargetGUID()
	if guid and guid ~= trackedTargetGUID then ResetTargetTrackers() end
	return demoExpires > GetTime() or AL.HasDebuff("target", "Demoralizing Shout")
end

local function BattleShoutActive()
	return battleShoutExpires > GetTime() or AL.HasBuff("player", "Battle Shout")
end

local function SunderStacks()
	local guid = TargetGUID()
	if guid and guid ~= trackedTargetGUID then ResetTargetTrackers() end

	if sunderExpires > 0 and sunderExpires <= GetTime() then
		sunderStacks = 0
		sunderExpires = 0
		lastCoreSunderExpires = 0
	end

	-- Reprend le compteur du framework Action lorsqu'il est disponible.
	if A and A.Unit then
		local okUnit, unit = pcall(A.Unit, "target")
		if okUnit and unit and unit.HasDeBuffsStacks then
			local okStacks, stacks = pcall(unit.HasDeBuffsStacks, unit, "Sunder Armor")
			if okStacks and type(stacks) == "number" and stacks > sunderStacks then
				sunderStacks = math.min(SUNDER_MAX_STACKS, stacks)
			end
		end
	end

	-- Fallback ActionLITE : chaque expiration differente correspond a un cast reussi.
	local coreDebuff = AL.targetDebuffs and AL.targetDebuffs["Sunder Armor"]
	if coreDebuff and type(coreDebuff.expires) == "number"
		and coreDebuff.expires > lastCoreSunderExpires + 0.01 then
		if sunderExpires == 0 or math.abs(coreDebuff.expires - sunderExpires) > 1 then
			sunderStacks = math.min(SUNDER_MAX_STACKS, sunderStacks + 1)
		end
		lastCoreSunderExpires = coreDebuff.expires
		sunderExpires = math.max(sunderExpires, coreDebuff.expires)
	end

	if sunderStacks == 0 and AL.HasDebuff("target", "Sunder Armor") then
		sunderStacks = 1
	end

	return sunderStacks
end

local function HeroicDumpAt(s)
	local configured = tonumber(s and s.heroicDumpRage)
	if configured ~= nil then
		return SettingNumber(s, "heroicDumpRage", HEROIC_DUMP_RAGE, 15, 100)
	end
	if not Known("Rend") then return 15 end
	if not Known("Sunder Armor") then return 30 end
	if not Known("Overpower") then return 45 end
	return HEROIC_DUMP_RAGE
end


local function DumpGate(rage, threshold, spell)
	if type(rage) == "number" then
		return rage >= threshold, "numeric"
	end

	-- Forever protects Rage in combat. In that state we cannot honestly claim
	-- a threshold was crossed, so use the game's own affordability/usability
	-- result. This keeps spenders active and prevents Rage from being hoarded
	-- behind an unreadable numeric check.
	if spell and AL.SpellUsable(spell) then
		return true, "spell usable fallback"
	end

	return false, "rage unreadable"
end

local function VerifiedMelee(inMelee)
	local inRange = HeroicStrikeInRange("target")
	if inRange ~= nil then return inRange end
	return SafeValue(inMelee) and inMelee == true
end

local function RageSpellCost(name, fallback)
	local reader = C_Spell and C_Spell.GetSpellPowerCost
	if type(reader) ~= "function" then return fallback end
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	local ok, costs = pcall(reader, ref and HamstringNumber(ref.id) or name)
	if ok and SafeValue(costs) and type(costs) == "table" then
		for _, power in ipairs(costs) do
			if SafeValue(power) and type(power) == "table" and HamstringNumber(power.type) == 1 then
				local cost = HamstringNumber(power.cost)
				if cost and cost >= 0 then return cost end
			end
		end
	end
	return fallback
end

local function AoECooldownReady(name)
	local reader = C_Spell and C_Spell.GetSpellCooldown
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	if type(reader) == "function" then
		local ok, info = pcall(reader, ref and HamstringNumber(ref.id) or name)
		if ok and SafeValue(info) and type(info) == "table" then
			local start = HamstringNumber(info.startTime)
			local duration = HamstringNumber(info.duration)
			local rate = HamstringNumber(info.modRate)
			if SafeValue(info.modRate) and info.modRate == nil then rate = 1 end
			local ready
			if start and start >= 0 and duration and duration >= 0 and rate and rate > 0 then
				ready = start == 0 or duration <= 1.5 or start + duration / rate <= GetTime()
			elseif SafeValue(info.isActive) and info.isActive == false then
				ready = true
			elseif SafeValue(info.isActive) and info.isActive == true
				and SafeValue(info.isOnGCD) and info.isOnGCD == false then
				ready = false
			end
			if ready ~= nil then
				-- Immediately after success, a readable zero cooldown can be
				-- the previous frame's data. Keep the confirmed cast briefly.
				if ready and localCastAt[name] and GetTime() - localCastAt[name] < 0.5
					and not LocalReady(name) then return false end
				return ready
			end
		end
	end
	return LocalReady(name) and AL.IsReady(name)
end

local function ReadyRageSpell(name)
	if not Ok(name) then return false end
	if name == "Thunder Clap" or name == "Sweeping Strikes" then
		if not AoECooldownReady(name) then return false end
	elseif not LocalReady(name) or not AL.IsReady(name) then return false end
	local usable, insufficient = AL.SpellUsable(name)
	return SafeValue(usable) and usable == true
		and not (SafeValue(insufficient) and insufficient == true)
end

local function StrikeQueued(name)
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	local id = ref and HamstringNumber(ref.id) or name
	for _, reader in pairs({ IsCurrentSpell, C_Spell and C_Spell.IsCurrentSpell }) do
		if type(reader) == "function" then
			local ok, active = pcall(reader, id)
			if ok and SafeValue(active) and active == true then return true end
		end
	end
	return false
end

local function ProtectionSwing(s, rage, multiTarget, inMelee)
	if not VerifiedMelee(inMelee) then return nil end
	-- Both attacks occupy the next melee swing. Do not repeatedly queue or
	-- replace one while it is active; the rest of the rotation can still run.
	if StrikeQueued("Heroic Strike") or StrikeQueued("Cleave") then return nil end
	local name, threshold, cost
	if multiTarget then
		name = "Cleave"
		threshold = SettingNumber(s, "tankCleaveDumpRage", 20, 20, 100)
		cost = RageSpellCost(name, 20)
	else
		if not s.heroic then return nil end
		name = "Heroic Strike"
		threshold = SettingNumber(s, "tankHeroicDumpRage", 20, 20, 100)
		cost = RageSpellCost(name, 15)
	end
	if ReadyRageSpell(name) and HasRage(rage, math.max(threshold, cost)) then
		return name, multiTarget and "protection 2+ engaged targets" or "protection single target"
	end
end

local function AoEModeActive(s, enemyCount, minimum)
	if not s.aoe then return false end
	-- An unreadable/incomplete count is not proof that AoE is unnecessary.
	-- The manual toggle remains the fallback when nameplates are unavailable.
	return enemyCount == nil or enemyCount >= minimum
		or enemyCountDebug.unreadable or enemyCountDebug.existing == 0
end

local function AoEDamage(s, rage, inMelee, tankMode)
	if not VerifiedMelee(inMelee) then return nil end
	local stance = PlayerStance()
	-- Sweeping Strikes is Battle Stance only. Never leave Defensive Stance
	-- or recommend an unusable stance-specific talent to force it into AoE.
	local ok, active = pcall(AL.HasBuff, "player", "Sweeping Strikes")
	local sweepingActive = ok and SafeValue(active) and active == true
	if stance == 1 and not sweepingActive and ReadyRageSpell("Sweeping Strikes")
		and HasRage(rage, math.max(RageSpellCost("Sweeping Strikes", 30),
			SettingNumber(s, "sweepingReserveRage", SWEEPING_RESERVE_RAGE, 30, 100))) then
		return "Sweeping Strikes", "AoE opener"
	end
	if (stance == nil or stance == 1 or stance == 2)
		and ReadyRageSpell("Thunder Clap") and HasRage(rage, RageSpellCost("Thunder Clap", 20)) then
		return "Thunder Clap", "AoE damage + attack-speed slow"
	end
	local cleaveAt = tankMode and SettingNumber(s, "tankCleaveDumpRage", 20, 20, 100)
		or SettingNumber(s, "cleaveDumpRage", CLEAVE_DUMP_RAGE, 20, 100)
	if not StrikeQueued("Cleave") and not StrikeQueued("Heroic Strike")
		and ReadyRageSpell("Cleave") and HasRage(rage, math.max(cleaveAt, RageSpellCost("Cleave", 20))) then
		return "Cleave", "AoE queued melee attack"
	end
end


local function RageOverflowing(rage)
	return type(rage) == "number" and rage >= RAGE_OVERFLOW_DUMP
end

local function MultiTargetConfirmed(enemyCount)
	return type(enemyCount) == "number" and enemyCount >= 2
end

local function OverflowDump(s, rage, enemyCount, tankMode)
	if not RageOverflowing(rage) then return nil end

	local cleavePriority = MultiTargetConfirmed(enemyCount) and Ok("Cleave")

	if cleavePriority and AL.SpellUsable("Cleave") then
		return "Cleave", "prevent rage overflow - 2+ targets"
	end

	-- Never dump Rage into Heroic Strike while Cleave is the active 2+ target
	-- spender. If Cleave is not affordable yet, preserve the Rage for Cleave.
	if cleavePriority then return nil end

	if s.heroic and Ok("Heroic Strike") and AL.SpellUsable("Heroic Strike") then
		return "Heroic Strike",
			(tankMode and "tank " or "") .. "prevent rage overflow " .. tostring(rage) .. "+"
	end
end

local function ElapsedSince(startedAt)
	if type(startedAt) ~= "number" or startedAt <= 0 then return nil end
	return math.max(0, GetTime() - startedAt)
end

local function ShouldRend(targetHp, ttd)
	if targetHp and targetHp <= REND_STOP_HP then return false end
	if ttd and ttd < REND_MIN_TTD then return false end

	-- If Forever protects both health and TTD, only allow the first Rend during
	-- the opening target window. This prevents a missing opener from surfacing
	-- as a surprise Rend near the end of the fight.
	local windowAge = ElapsedSince(rendWindowStartedAt)
	if targetHp == nil and windowAge and windowAge > REND_UNREADABLE_HP_WINDOW then
		return false
	end

	return true
end

local function AnyRageSpenderUsable()
	return (Ok("Heroic Strike") and AL.SpellUsable("Heroic Strike"))
		or (Ok("Cleave") and AL.SpellUsable("Cleave"))
		or (Ok("Slam") and AL.SpellUsable("Slam"))
		or (Ok("Rend") and AL.SpellUsable("Rend"))
		or (Ok("Sunder Armor") and AL.SpellUsable("Sunder Armor"))
		or (Ok("Thunder Clap") and AL.SpellUsable("Thunder Clap"))
end

local function ShouldBloodrage(s, rage, myHp)
	if not s.bloodrage or not OkReady("Bloodrage")
		or not AL.SpellUsable("Bloodrage") then
		return false, "disabled / unavailable"
	end

	if myHp and myHp < BLOODRAGE_MIN_HP then
		return false, "health below safety threshold"
	end

	if type(rage) == "number" then
		if rage < BLOODRAGE_MAX_RAGE then
			return true, "safe rage generation"
		end
		return false, "rage already sufficient"
	end

	-- Rage can be protected in Forever combat. The short opener window is a
	-- bounded exception; later, infer low Rage only when the game reports that
	-- no core Rage spender is currently affordable.
	local combatAge = ElapsedSince(combatStartedAt)
	if combatAge and combatAge <= BLOODRAGE_PROTECTED_OPENER then
		return true, "protected Rage - opener generation"
	end
	if not AnyRageSpenderUsable() then
		return true, "protected Rage - no spender affordable"
	end

	return false, "protected Rage - spender already affordable"
end

local function SunderStackCap(s)
	local configured = tonumber(s and s.sunderMaxStacks)
	-- Les profils crees avant la 0.6.3 n'ont pas encore cette cle. Le repli a
	-- 2 garantit que la valeur affichee dans l'UI est aussi la valeur appliquee,
	-- meme avant que le joueur touche le curseur.
	if configured == nil then configured = 2 end
	configured = math.floor(configured + 0.5)
	if configured < 0 then return 0 end
	if configured > SUNDER_MAX_STACKS then return SUNDER_MAX_STACKS end
	return configured
end

local function ShouldSunder(s, targetHp, ttd, stacks)
	local cap = SunderStackCap(s)
	if cap <= 0 then return false end
	if targetHp and targetHp < SUNDER_STOP_HP then return false end
	if ttd and ttd < SUNDER_MIN_TTD then return false end
	return stacks < cap
end

local function SpearingTarget()
	local creatureType = AL.CreatureType("target")
	return creatureType == "Giant" or creatureType == "Dragonkin"
end

-- ==========================================================================
-- ROTATION
-- ==========================================================================

local function NextDPS(s, inCombat, hostile)
	if not inCombat then
		if hostile then
			if ChargeAvailable() then
				return "Charge", "verified Charge range + rage"
			end
			return AL.known["Attack"] and "Attack" or nil, "opener"
		end
		return nil, "Ready"
	end

	if not hostile then return nil, "No target" end

	-- Normal Charge remains unusable in combat, but Warbringer can make it legal.
	-- ChargeAvailable() requires SpellUsable + a positively verified range, so
	-- this cannot create the old dungeon/out-of-range hang.
	if ChargeAvailable() then
		return "Charge", "in-combat Charge usable + verified range"
	end

	local rage = AL.Power(1)
	local targetHp = AL.HealthPercent("target")
	local myHp = AL.HealthPercent("player")
	local inMelee = AL.TargetInMelee()
	local ttd = TargetTTD()
	local aoeMinEnemies = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)

	local enemyCount = EnemyCountMelee(math.max(aoeMinEnemies, 5))
	local multiTarget = MultiTargetConfirmed(enemyCount)
	local aoeActive = AoEModeActive(s, enemyCount, aoeMinEnemies)

	-- Procs courts et survie.
	if s.victory and myHp and myHp <= 65 and ReadyUsable("Victory Rush") then
		return "Victory Rush", "heal + free damage"
	end
	if s.overpower and ReadyUsable("Overpower") then
		return "Overpower", "proc"
	end
	if s.revenge and ReadyUsable("Revenge") then
		return "Revenge", "proc"
	end
	if s.victory and ReadyUsable("Victory Rush") then
		return "Victory Rush", "free damage + heal"
	end

	local slowSpell, slowReason = MaintainHamstring(s, rage, inMelee)
	if slowSpell then return slowSpell, slowReason end

	-- Execute reste un finisher prioritaire : SpellUsable filtre la phase <=20%.
	if s.execute and Ok("Execute")
		and (targetHp == nil or targetHp <= 20)
		and AL.SpellUsable("Execute") then
		return "Execute", "finisher"
	end

	-- Enabled AoE must be checked before Rend, overflow dumps and the Cleave
	-- pooling return. Otherwise those branches can hide Thunder Clap forever.
	if aoeActive then
		local aoeSpell, aoeReason = AoEDamage(s, rage, inMelee, false)
		if aoeSpell then return aoeSpell, aoeReason end
	end

	-- Apply Rend as an opener before queued strikes and other Rage dumps can
	-- starve it. Keep the existing 2+ target Cleave policy intact.
	if not aoeActive and not multiTarget and s.rend and Ok("Rend") and not RendActive()
		and HasRage(rage, 10)
		and ShouldRend(targetHp, ttd)
		and AL.SpellUsable("Rend") then
		return "Rend", "opening bleed / Arms synergy"
	end

	if not aoeActive then
		local overflowSpell, overflowReason = OverflowDump(s, rage, enemyCount, false)
		if overflowSpell then return overflowSpell, overflowReason end
	end

	local useBloodrage, bloodrageReason = ShouldBloodrage(s, rage, myHp)
	if useBloodrage then
		return "Bloodrage", bloodrageReason
	end

	-- Maintenance personnelle.
	if s.shout and Ok("Battle Shout")
		and not BattleShoutActive()
		and HasRage(rage, 10)
		and AL.SpellUsable("Battle Shout") then
		return "Battle Shout", "3 min buff"
	end

	-- Cooldowns raciaux uniquement sur une cible qui devrait survivre.
	if AL.burst and (not targetHp or targetHp > 35) and (not ttd or ttd >= 10) then
		if OkReady("Blood Fury") then return "Blood Fury", "burst" end
		if OkReady("Berserking") then return "Berserking", "burst" end
	end

	if not aoeActive and multiTarget and Ok("Cleave") then
		local cleaveAt = SettingNumber(s, "cleaveDumpRage", CLEAVE_DUMP_RAGE, 20, 100)
		local cleaveUsable = AL.SpellUsable("Cleave")

		if cleaveUsable then
			local allowed, rageSource = DumpGate(rage, cleaveAt, "Cleave")
			if allowed then
				return "Cleave",
					rageSource == "numeric"
						and ("2+ enemies within 7 yd - rage " .. tostring(cleaveAt) .. "+")
						or "2+ enemies within 7 yd - Rage protected, Cleave usable"
			end
		end

		-- Hard multi-target spender priority: do not let Heroic Strike or other
		-- Rage consumers starve Cleave. Auto-attack until Cleave is affordable.
		return AL.known["Attack"] and "Attack" or nil,
			cleaveUsable
				and ("2+ enemies - reserve rage for Cleave " .. tostring(cleaveAt) .. "+")
				or "2+ enemies - pool rage for Cleave"
	end

	-- Spearing Strike est rentable en priorite sur ses cibles specialisees.
	if not aoeActive and s.spear and SpearingTarget() and ReadyUsable("Spearing Strike")
		and HasRage(rage, 15) and inMelee then
		return "Spearing Strike", "giant / dragonkin bonus"
	end

	-- Slam is a real single-target spender. Prefer verified post-swing timing
	-- when Forever exposes it; if the client hides all swing timing, fall back
	-- to ready + usable + stationary instead of disabling Slam forever.
	if not aoeActive and s.slam and inMelee and not PlayerMoving() and ReadyUsable("Slam") then
		local slamAt = SettingNumber(s, "slamReserveRage", SLAM_RESERVE_RAGE, 15, 100)
		local allowed, rageSource = DumpGate(rage, slamAt, "Slam")

		if allowed then
			local timing, timingSource = SlamTimingState()

			if timing ~= false then
				if timing == true then
					return "Slam", "post-swing | " .. timingSource
				end

				return "Slam",
					rageSource == "numeric"
						and ("Slam ready " .. tostring(slamAt) .. "+ | swing timing unavailable")
						or "Rage protected - Slam usable | swing timing unavailable"
			end
		end
	end

	-- Heroic Strike remains the single-target fallback spender, but it no longer
	-- starves Slam when Slam is ready. The 80+ emergency overflow guard still
	-- sits earlier in the rotation.
	if not aoeActive and s.heroic and Ok("Heroic Strike") and AL.SpellUsable("Heroic Strike") then
		local dumpAt = HeroicDumpAt(s)
		local allowed, rageSource = DumpGate(rage, dumpAt, "Heroic Strike")
		if allowed then
			return "Heroic Strike",
				rageSource == "numeric"
					and ("rage dump " .. tostring(dumpAt) .. "+")
					or "Rage protected - Heroic Strike usable"
		end
	end

	if s.demo and Ok("Demoralizing Shout")
		and not DemoActive()
		and HasRage(rage, 10)
		and inMelee and AL.SpellUsable("Demoralizing Shout") then
		return "Demoralizing Shout", "mitigation"
	end

	if s.sunder and Ok("Sunder Armor")
		and HasRage(rage, 30)
		and AL.SpellUsable("Sunder Armor") then
		local stacks = SunderStacks()
		if ShouldSunder(s, targetHp, ttd, stacks) then
			return "Sunder Armor", "armor stack " .. tostring(stacks + 1)
		end
	end

	return AL.known["Attack"] and "Attack" or nil, "melee / pool rage"
end

-- ========================================================================
-- TANK : donjons / leveling 1-30
-- ========================================================================
local function NextTank(s, inCombat, hostile)
	if not inCombat then
		if hostile then
			if ChargeAvailable() then
				return "Charge", "verified tank Charge range + rage"
			end
			return AL.known["Attack"] and "Attack" or nil, "tank opener"
		end
		return nil, "Ready"
	end

	if not hostile then return nil, "No target" end

	if ChargeAvailable() then
		return "Charge", "in-combat tank Charge usable + verified range"
	end

	local rage = AL.Power(1)
	local targetHp = AL.HealthPercent("target")
	local myHp = AL.HealthPercent("player")
	local inMelee = AL.TargetInMelee()
	local stance = PlayerStance()
	local shield = ShieldEquipped()
	local needsTaunt = TargetNeedsTaunt()
	local aoeMinEnemies = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
	local enemyCount = EnemyCountMelee(math.max(aoeMinEnemies, 5))
	local multiTarget = MultiTargetConfirmed(enemyCount)
	local aoeActive = AoEModeActive(s, enemyCount, aoeMinEnemies)

	-- Survie gratuite avant toute depense de rage.
	if s.victory and myHp and myHp <= 65 and ReadyUsable("Victory Rush") then
		return "Victory Rush", "tank self-heal"
	end

	-- La posture defensive est la base du profil Tank. Si la posture devient
	-- protegee/illisible, ne jamais la proposer en boucle.
	if s.tankAutoStance and Known("Defensive Stance")
		and type(stance) == "number" and stance ~= 2
		and Ok("Defensive Stance") and AL.SpellUsable("Defensive Stance") then
		return "Defensive Stance", "tank stance"
	end

	-- Reprendre une cible qui attaque un membre amical. Mocking Blow reste un
	-- repli seulement lorsqu'il est directement utilisable dans la posture.
	if s.tankTaunt and needsTaunt then
		if ReadyUsable("Taunt") then return "Taunt", "recover aggro" end
		if ReadyUsable("Mocking Blow") then return "Mocking Blow", "taunt fallback" end
	end
	if s.tankAoETaunt and aoeActive then
		local looseEnemies = TauntableEnemyCount(3)
		if looseEnemies and looseEnemies >= 3 and ReadyUsable("Challenging Shout") then
			return "Challenging Shout", "recover 3+ enemies"
		end
	end

	-- Defensive d'urgence. SpellUsable gere lui-meme l'exigence du bouclier.
	if s.tankShieldWall and myHp and myHp <= SettingNumber(s, "tankShieldWallHP", 35, 10, 80)
		and ReadyUsable("Shield Wall") then
		return "Shield Wall", "emergency defensive"
	end

	-- Interruption prioritaire lorsque la cible incante et qu'un bouclier est
	-- equipe (ou que l'etat d'equipement est masque par le client).
	if s.tankInterrupt and shield ~= false and AL.TargetCasting
		and AL.TargetCasting() and ReadyUsable("Shield Bash") then
		return "Shield Bash", "interrupt"
	end

	-- Revenge est le meilleur bouton de menace reactif du profil.
	if s.revenge and ReadyUsable("Revenge") then
		return "Revenge", "reactive threat"
	end

	local slowSpell, slowReason = MaintainHamstring(s, rage, inMelee)
	if slowSpell then return slowSpell, slowReason end

	-- Shield Block prepare Revenge et lisse les coups recus.
	if s.tankShieldBlock and shield ~= false and inMelee
		and HasRage(rage, 10) and ReadyUsable("Shield Block") then
		return "Shield Block", "block + revenge setup"
	end

	if aoeActive then
		local aoeSpell, aoeReason = AoEDamage(s, rage, inMelee, true)
		if aoeSpell then return aoeSpell, aoeReason end
	end

	-- Rend is a single-target opener, using the same missing-aura and
	-- near-death rules as DPS. Apply it before the queued swing can spend Rage.
	if not aoeActive and not multiTarget and s.rend and not RendActive()
		and VerifiedMelee(inMelee) and ShouldRend(targetHp, TargetTTD())
		and ReadyRageSpell("Rend")
		and HasRage(rage, RageSpellCost("Rend", 10)) then
		return "Rend", "protection single-target bleed"
	end

	local useBloodrage, bloodrageReason = ShouldBloodrage(s, rage, myHp)
	if useBloodrage then
		return "Bloodrage", "tank " .. bloodrageReason
	end

	if s.shout and Ok("Battle Shout") and not BattleShoutActive()
		and HasRage(rage, 10) and AL.SpellUsable("Battle Shout") then
		return "Battle Shout", "group attack power"
	end

	if s.tankDemo and Ok("Demoralizing Shout")
		and not DemoActive()
		and HasRage(rage, 10) and inMelee and AL.SpellUsable("Demoralizing Shout") then
		return "Demoralizing Shout", "mitigation + aoe threat"
	end

	-- Sunder est la source de menace mono-cible stable. En Tank, le plafond est
	-- independant du reglage DPS et n'est pas coupe par le TTD de la cible.
	if s.sunder and TankSunderCap(s) > 0 and Ok("Sunder Armor")
		and HasRage(rage, 15) and AL.SpellUsable("Sunder Armor") then
		local stacks = SunderStacks()
		if stacks < TankSunderCap(s) then
			return "Sunder Armor", "tank threat " .. tostring(stacks + 1)
		end
	end

	if s.execute and Ok("Execute")
		and (targetHp == nil or targetHp <= 20)
		and AL.SpellUsable("Execute") then
		return "Execute", "tank finisher"
	end

	if s.victory and ReadyUsable("Victory Rush") then
		return "Victory Rush", "free tank damage"
	end

	local swingSpell, swingReason = ProtectionSwing(s, rage, multiTarget or aoeActive, inMelee)
	if swingSpell then return swingSpell, swingReason end

	return AL.known["Attack"] and "Attack" or nil, "tank melee / pool rage"
end

function M.NextSpell(s, inCombat, hostile)
	M.InitializeProtectionSettings(s)
	if WarriorRole(s) == "TANK" then
		return NextTank(s, inCombat, hostile)
	end
	return NextDPS(s, inCombat, hostile)
end

-- One setter serves the menu and the macro; redraws never print status.
function M.SetHamstring(enabled, profile)
	if type(enabled) ~= "boolean" or not SafeValue(enabled) then return end
	profile = profile or AL.Profile("WARRIOR")
	profile.hamstring = enabled
	print(enabled and "Hamstring: ON" or "Hamstring: OFF")
	if AL.UI and type(AL.UI.Repaint) == "function" then AL.UI.Repaint() end
	return enabled
end

function M.ToggleHamstring()
	local profile = AL.Profile("WARRIOR")
	return M.SetHamstring(profile.hamstring ~= true, profile)
end

SLASH_ACTIONLITEHAMSTRING1 = "/alhamstring"
SlashCmdList.ACTIONLITEHAMSTRING = function(message)
	local command = type(message) == "string" and message:match("^%s*(.-)%s*$"):lower() or ""
	if command == "on" then return M.SetHamstring(true) end
	if command == "off" then return M.SetHamstring(false) end
	if command == "" or command == "toggle" then return M.ToggleHamstring() end
	print("Usage: /alhamstring [on|off|toggle]")
end

-- Etat public minimal consomme par Warrior_UI.lua. La logique et les seuils
-- restent ici afin que le fichier d'interface ne duplique aucune regle combat.
function M.GetUIState()
	local knownCount = 0
	for _, entry in ipairs(M.spells) do
		if AL.known[entry[2]] then knownCount = knownCount + 1 end
	end

	local profile = AL.ES()
	M.InitializeProtectionSettings(profile)
	return {
		level = PlayerLevel(),
		rage = AL.Power(1),
		heroicDumpAt = HeroicDumpAt(profile),
		cleaveDumpRage = SettingNumber(profile, "cleaveDumpRage", CLEAVE_DUMP_RAGE, 20, 100),
		slamReserveRage = SettingNumber(profile, "slamReserveRage", SLAM_RESERVE_RAGE, 15, 100),
		sweepingReserveRage = SettingNumber(profile, "sweepingReserveRage", SWEEPING_RESERVE_RAGE, 30, 100),
		aoeMinEnemies = SettingNumber(profile, "aoeMinEnemies", 2, 2, 5),
		enemyCount7 = EnemyCountMelee(5),
		rageOverflowAt = RAGE_OVERFLOW_DUMP,
		sunderMaxStacks = SunderStackCap(profile),
		role = WarriorRole(profile),
		stance = PlayerStance(),
		hasShield = ShieldEquipped(),
		needsTaunt = TargetNeedsTaunt(),
		tankSunderMaxStacks = TankSunderCap(profile),
		tankHeroicDumpRage = SettingNumber(profile, "tankHeroicDumpRage", 20, 20, 100),
		tankCleaveDumpRage = SettingNumber(profile, "tankCleaveDumpRage", 20, 20, 100),
		tankShieldWallHP = SettingNumber(profile, "tankShieldWallHP", 35, 10, 80),
		knownCount = knownCount,
	}
end

function M.DebugState()
	local s = AL.S()
	local rage = AL.Power(1)
	local enemyCount = EnemyCountMelee(5)
	local chargeRange, chargeRangeSource = SpellRangeState("Charge")
	local targetHp = AL.HealthPercent("target")
	local myHp = AL.HealthPercent("player")
	local ttd = TargetTTD()
	local bloodrageRecommended, bloodrageReason = ShouldBloodrage(s, rage, myHp)
	local rendActive = RendActive()

	return {
		build = "0.7.11",
		rage = rage,
		rageReadable = type(rage) == "number",
		rageOverflowAt = RAGE_OVERFLOW_DUMP,
		ragePolicy = type(rage) == "number"
			and "numeric thresholds"
			or "protected Rage -> opener / spender usability fallback",
		combatAge = ElapsedSince(combatStartedAt),

		bloodrageRecommended = bloodrageRecommended,
		bloodrageReason = bloodrageReason,
		bloodrageMaxRage = BLOODRAGE_MAX_RAGE,
		bloodrageMinHP = BLOODRAGE_MIN_HP,
		bloodrageProtectedOpener = BLOODRAGE_PROTECTED_OPENER,

		rendActive = rendActive,
		rendShouldApply = not rendActive and ShouldRend(targetHp, ttd) or false,
		rendWindowAge = ElapsedSince(rendWindowStartedAt),
		rendStopHP = REND_STOP_HP,
		rendMinTTD = REND_MIN_TTD,
		targetHP = targetHp,
		targetTTD = ttd,

		heroicDumpAt = HeroicDumpAt(s),
		heroicUsable = Ok("Heroic Strike") and AL.SpellUsable("Heroic Strike") or false,
		cleaveDumpAt = SettingNumber(s, "cleaveDumpRage", CLEAVE_DUMP_RAGE, 20, 100),
		cleaveUsable = Ok("Cleave") and AL.SpellUsable("Cleave") or false,

		slamReserveAt = SettingNumber(s, "slamReserveRage", SLAM_RESERVE_RAGE, 15, 100),
		slamUsable = Ok("Slam") and AL.SpellUsable("Slam") or false,
		slamReady = Ok("Slam") and LocalReady("Slam") and AL.IsReady("Slam") or false,
		slamMoving = PlayerMoving(),
		slamTiming = select(1, SlamTimingState()),
		slamTimingSource = select(2, SlamTimingState()),

		enemyCount7 = enemyCount,
		enemyCountSource = enemyCountDebug.source,
		enemyNameplates = enemyCountDebug.existing,
		enemyHostile = enemyCountDebug.hostile,
		enemyInCombat = enemyCountDebug.combat,
		enemyOnThreatTable = enemyCountDebug.threat,
		enemyInMeleeRange = enemyCountDebug.melee,
		multiTarget7 = MultiTargetConfirmed(enemyCount),
		aoeEnabled = s.aoe and true or false,

		chargeRange = chargeRange,
		chargeRangeSource = chargeRangeSource,
		lastChargeRange = lastChargeRange,
		lastChargeRangeSource = lastChargeRangeSource,
		lastChargeBlockReason = lastChargeBlockReason,
		stance = PlayerStance(),
		inMelee = AL.TargetInMelee(),
		chargeUsable = Ok("Charge") and AL.SpellUsable("Charge") or false,
	}
end

AL.RegisterRotation("WARRIOR", M)
