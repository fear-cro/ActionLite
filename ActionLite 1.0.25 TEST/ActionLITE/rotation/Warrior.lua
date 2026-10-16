local ADDON, AL = ...

-- ActionLITE Warrior v0.10.4: original Leveling plus optional talent builds.

-- Leveling keeps the finalized pre-simulation implementation in its own
-- scope. Talent builds use the separate implementation below. Both observe
-- real casts so switching rotations retains resource and spell history.
do
    local root = AL
    local leveling, advanced
    local function UsesLeveling(profile)
        profile = profile or (root.Profile and root.Profile("WARRIOR")) or (root.S and root.S())
        if advanced and type(profile) == "table" then
            return advanced.NormalizeBuild(profile) == "leveling"
        end
        return true
    end
    local function RotationScope(isLeveling)
        local scope = {
            RegisterRotation = function(token, module)
                assert(token == "WARRIOR", "Unexpected class rotation")
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
                    if root.playerClass == "WARRIOR" and UsesLeveling() == isLeveling then root[key] = value end
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
-- BEGIN ORIGINAL LEVELING IMPLEMENTATION (Warrior(7).lua)
local ADDON, AL = ...

-- WoW Forever Warrior DPS / Tank leveling 1-30
-- ActionLITE Warrior rotation v0.7.13
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
	if not SafeUnitExists("targettarget")
		or type(UnitIsUnit) ~= "function" or type(UnitIsFriend) ~= "function" then return false end
	local okSelf, isSelf = pcall(UnitIsUnit, "targettarget", "player")
	-- Protected relationship results cannot be tested as booleans. Unknown
	-- aggro skips the optional taunt without interrupting the tank rotation.
	if not okSelf or not SafeValue(isSelf) or type(isSelf) ~= "boolean" or isSelf then return false end
	local okFriend, isFriend = pcall(UnitIsFriend, "player", "targettarget")
	return okFriend and SafeValue(isFriend) and isFriend == true
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


-- Optional spenders must honor their sliders even when the client protects
-- Rage. The existing display can apply native color-curve alpha to the main
-- icon, mini-icon, key and glow without comparing a protected value in Lua.
local plannedDumpRage, collectingRageCuts, lastRageDecision
local rageCurves, rageCurveFactory = {}, nil
local rageCurveFailure, rageCurveCapability, rageCurveProbe

local function RageCurveFailed()
	rageCurveFailure = { reader = UnitPowerPercent,
		factory = C_CurveUtil and C_CurveUtil.CreateColorCurve, at = GetTime() }
	rageCurveCapability = nil
end

local function DumpGate(rage, threshold)
	local readable = HamstringNumber(rage)
	if readable ~= nil then return readable >= threshold, "numeric" end
	if plannedDumpRage ~= nil then return plannedDumpRage >= threshold, "native Rage threshold" end
	if collectingRageCuts then collectingRageCuts[threshold] = true end
	-- Affording a 15-Rage spell is not evidence that a 65-Rage slider passed.
	-- Essential attacks still use HasRage + real spell usability independently.
	return false, "Rage threshold unavailable"
end

local function RageIntervalCurve(low, high)
	local factory = C_CurveUtil.CreateColorCurve
	if factory ~= rageCurveFactory then rageCurves, rageCurveFactory = {}, factory end
	local key = tostring(low) .. ":" .. tostring(high)
	if rageCurves[key] then return rageCurves[key] end
	local curve = factory()
	curve:SetType(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	curve:AddPoint(0, CreateColor(1, 1, 1, low == 0 and 1 or 0))
	if low > 0 and low <= 1 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
	if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
	if low ~= 1 and high ~= 1 then
		curve:AddPoint(1, CreateColor(1, 1, 1, low <= 1 and high > 1 and 1 or 0))
	end
	rageCurves[key] = curve
	return curve
end

local function RageVisualAlpha(mask)
	local color = UnitPowerPercent("player", 1, false, RageIntervalCurve(mask.low, mask.high))
	local _, _, _, alpha = color:GetRGBA()
	if SafeValue(alpha) and HamstringNumber(alpha) == nil then error("Rage curve has no display alpha") end
	return alpha
end

local function RageCurvesAvailable()
	local reader = UnitPowerPercent
	local factory = C_CurveUtil and C_CurveUtil.CreateColorCurve
	if type(reader) ~= "function" or type(factory) ~= "function" or type(CreateColor) ~= "function" then return false end
	if rageCurveFailure and rageCurveFailure.reader == reader and rageCurveFailure.factory == factory
		and GetTime() - rageCurveFailure.at < 1 then return false end
	if rageCurveCapability and rageCurveCapability.reader == reader and rageCurveCapability.factory == factory then return true end
	local ok = pcall(function()
		local alpha = RageVisualAlpha({ low = 0, high = 0.5 })
		rageCurveProbe = rageCurveProbe or CreateFrame("Frame")
		rageCurveProbe:Hide()
		rageCurveProbe:SetAlpha(alpha)
	end)
	if not ok then
		RageCurveFailed()
		return false
	end
	rageCurveCapability = { reader = reader, factory = factory }
	return true
end

local function RageMaximum()
	if type(UnitPowerMax) ~= "function" then return nil end
	local ok, value = pcall(UnitPowerMax, "player", 1)
	local maximum = ok and HamstringNumber(value) or nil
	if maximum == nil then
		ok, value = pcall(UnitPowerMax, "player")
		maximum = ok and HamstringNumber(value) or nil
	end
	return maximum and maximum > 0 and maximum or nil
end

local function WarriorRage()
	local rage = HamstringNumber(AL.Power(1))
	if rage ~= nil then return rage end
	if type(UnitPowerPercent) ~= "function" then return nil end
	local maximum = RageMaximum()
	if not maximum then return nil end
	local scale = CurveConstants and CurveConstants.ScaleTo100
	local ok, value = pcall(UnitPowerPercent, "player", 1, false, scale)
	local percent = ok and HamstringNumber(value) or nil
	if percent == nil then return nil end
	if not scale then percent = percent * 100 end
	if percent < 0 or percent > 100 then return nil end
	return percent / 100 * maximum
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
	if ReadyRageSpell(name) and DumpGate(rage, math.max(threshold, cost)) then
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
		and DumpGate(rage, math.max(RageSpellCost("Sweeping Strikes", 30),
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
		and ReadyRageSpell("Cleave") and DumpGate(rage, math.max(cleaveAt, RageSpellCost("Cleave", 20))) then
		return "Cleave", "AoE queued melee attack"
	end
end


local function RageOverflowing(rage)
	return DumpGate(rage, RAGE_OVERFLOW_DUMP)
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

	local rage = WarriorRage()
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
			local allowed, rageSource = DumpGate(rage, cleaveAt)
			if allowed then
				return "Cleave",
					rageSource == "numeric"
						and ("2+ enemies within 7 yd - rage " .. tostring(cleaveAt) .. "+")
						or ("2+ enemies within 7 yd - native Rage threshold " .. tostring(cleaveAt) .. "+")
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
		local allowed, rageSource = DumpGate(rage, slamAt)

		if allowed then
			local timing, timingSource = SlamTimingState()

			if timing ~= false then
				if timing == true then
					return "Slam", "post-swing | " .. timingSource
				end

				return "Slam",
					rageSource == "numeric"
						and ("Slam ready " .. tostring(slamAt) .. "+ | swing timing unavailable")
						or ("Slam ready " .. tostring(slamAt) .. "+ | protected resource display")
			end
		end
	end

	-- Heroic Strike remains the single-target fallback spender, but it no longer
	-- starves Slam when Slam is ready. The 80+ emergency overflow guard still
	-- sits earlier in the rotation.
	if not aoeActive and s.heroic and Ok("Heroic Strike") and AL.SpellUsable("Heroic Strike") then
		local dumpAt = HeroicDumpAt(s)
		local allowed, rageSource = DumpGate(rage, dumpAt)
		if allowed then
			return "Heroic Strike",
				rageSource == "numeric"
					and ("rage dump " .. tostring(dumpAt) .. "+")
					or ("Heroic Strike " .. tostring(dumpAt) .. "+ | protected resource display")
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

	local rage = WarriorRage()
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

local function ChooseSpell(s, inCombat, hostile)
	if WarriorRole(s) == "TANK" then
		return NextTank(s, inCombat, hostile)
	end
	return NextDPS(s, inCombat, hostile)
end

function M.NextSpell(s, inCombat, hostile)
	M.InitializeProtectionSettings(s)
	plannedDumpRage, lastRageDecision = nil, nil
	local cuts = {}
	collectingRageCuts = cuts
	local spell, reason = ChooseSpell(s, inCombat, hostile)
	collectingRageCuts = nil
	if next(cuts) then
		lastRageDecision = { at = GetTime(), settings = s, inCombat = inCombat, hostile = hostile,
			cuts = cuts, baseSpell = spell, baseReason = reason }
	end
	return spell, reason
end

function M.SecretVisualPlan(spell, reason)
	local d = lastRageDecision
	if not d or GetTime() - d.at > 0.3 or spell ~= d.baseSpell or reason ~= d.baseReason then return nil end
	if d.visualPlan ~= nil then return d.visualPlan or nil end
	local maximum = RageMaximum()
	if not maximum or not RageCurvesAvailable() then d.visualPlan = false; return nil end
	local cuts, seen = { 0, 2 }, { [0] = true, [2] = true }
	for threshold in pairs(d.cuts) do
		local cut = threshold / maximum
		if cut > 0 and cut < 2 and not seen[cut] then cuts[#cuts + 1], seen[cut] = cut, true end
	end
	table.sort(cuts)
	local plan = { rows = {}, masks = {}, spells = {}, baseSpell = spell, baseReason = reason }
	local differs = false
	for i = 1, #cuts - 1 do
		local low, high = cuts[i], cuts[i + 1]
		-- These samples are public interval boundaries from the user's settings,
		-- not estimates or reads of protected Rage. Native alpha selects the row.
		plannedDumpRage = (low + high) / 2 * maximum
		local ok, candidate, why = pcall(ChooseSpell, d.settings, d.inCombat, d.hostile)
		plannedDumpRage = nil
		if not ok then d.visualPlan = false; return nil end
		local key = "playerRage:" .. tostring(low) .. ":" .. tostring(high)
		local mask = { key = key, kind = "power", unit = "player", powerType = 1, low = low, high = high }
		plan.masks[key] = mask
		plan.rows[#plan.rows + 1] = { spell = candidate, reason = why, masks = { mask } }
		if candidate then plan.spells[candidate] = true end
		if candidate ~= spell then differs = true end
	end
	if not differs then d.visualPlan = false; return nil end
	d.visualPlan = plan
	return plan
end

function M.EvaluateVisualMasks(plan)
	local values = {}
	for key, mask in pairs(plan.masks) do
		local ok, value = pcall(RageVisualAlpha, mask)
		if not ok then
			RageCurveFailed()
			return nil
		end
		values[key] = value
	end
	return values
end

function M.ApplyVisualRow(nodes, row, values)
	for i, node in ipairs(nodes) do
		local mask = row.masks[i]
		if mask then node:SetAlpha(values[mask.key]) else node:SetAlpha(1) end
	end
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
		rage = WarriorRage(),
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
	local rage = WarriorRage()
	local enemyCount = EnemyCountMelee(5)
	local chargeRange, chargeRangeSource = SpellRangeState("Charge")
	local targetHp = AL.HealthPercent("target")
	local myHp = AL.HealthPercent("player")
	local ttd = TargetTTD()
	local bloodrageRecommended, bloodrageReason = ShouldBloodrage(s, rage, myHp)
	local rendActive = RendActive()

	return {
		build = "0.7.13",
		rage = rage,
		rageReadable = type(rage) == "number",
		rageOverflowAt = RAGE_OVERFLOW_DUMP,
		ragePolicy = type(rage) == "number"
			and "numeric thresholds"
			or "protected Rage -> native display thresholds; core attacks use usability",
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
-- END ORIGINAL LEVELING IMPLEMENTATION
    end)(ADDON, RotationScope(true))

    ;(function(...)
-- BEGIN OPTIONAL TALENT BUILD IMPLEMENTATION
local ADDON, AL = ...

-- WoW Forever Warrior DPS / Tank leveling 1-60
-- ActionLITE Warrior rotation v0.10.4 - Protection 0/20/31, Arms 39/10/2 and Fury 18/31/2
-- Reference: MythicSim Forever b1137248e6b4 (1.60.1.70338).
-- Validate learned spells and combat behavior in the live Forever client.

local A = _G.Action

local M = {
	defaults = {
        leveling = true,
		warriorRole = "DPS",
		protection = false,
		tankShieldSlam = true,
		tankLastStand = true,
		tankLastStandHP = 25,
		tankConcussionBlow = true,
		tankThunderClap = true,
		tankBloodFury = false,
		tankBerserking = true,
		tankBurstMinTargetHP = 35,
		arms = false,
		mortalStrike = true,
		armsAutoStance = true,
		armsSlam = true,
		armsHamstringFiller = false,
		armsInterrupt = true,
		armsRecklessness = true,
		armsBloodFury = true,
		armsBerserking = true,
		armsBurstMinTargetHP = 35,
		armsSunderMaxStacks = 1,
		armsSlamReserveRage = 15,
		armsHeroicDumpRage = 80,
		armsCleaveDumpRage = 80,
		armsFillerReserveRage = 20,
		fury = false,
		furyDeathWish = true,
		furyRecklessness = true,
		furyBurstMinTargetHP = 35,
		furySlam = false,
		bloodthirst = true,
		furyAutoStance = true,
		furyOverpowerDance = true,
		furyInterrupt = true,
		furyIntercept = true,
		furyBerserkerRage = true,
		whirlwind = true,
		furyCleaveDumpRage = 40,
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

-- ==========================================================================
-- DATA
-- ==========================================================================

-- IDs de rang 1 utilises pour identifier et afficher les sorts.
-- Exactly one rotation stays selected. Leveling is the default and the
-- fallback when a selected specialization is switched off or saved flags
-- conflict. A valid saved specialization takes priority during migration.
M.buildKeys = { "leveling", "protection", "arms", "fury" }
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
    local owner = s.warriorRoleBuild
    if issecretvalue and issecretvalue(owner) then owner = nil end
    local function IsTank(value)
        return not (issecretvalue and issecretvalue(value)) and value == "TANK"
    end
    if selected == "leveling" then
        if owner and owner ~= "leveling" then
            s.warriorRole = IsTank(s.levelingWarriorRole) and "TANK" or "DPS"
        else
            s.levelingWarriorRole = IsTank(s.warriorRole) and "TANK" or "DPS"
        end
    else
        if owner == "leveling" then
            s.levelingWarriorRole = IsTank(s.warriorRole) and "TANK" or "DPS"
        end
        s.warriorRole = selected == "protection" and "TANK" or "DPS"
    end
    s.warriorRoleBuild = selected
    s.protectionPreviousDPS = nil
    return selected
end
function M.SetBuild(key, enabled, s)
    if (issecretvalue and issecretvalue(enabled)) or type(enabled) ~= "boolean" then return end
    local valid = false
    for _, candidate in ipairs(M.buildKeys) do if candidate == key then valid = true; break end end
    if not valid then return end
    s = s or AL.Profile("WARRIOR")
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
	{ 6673, "Battle Shout" },
	{ 2457, "Battle Stance" },
	{ 2458, "Berserker Stance" },
	{ 2687, "Bloodrage" },
	{ 23881, "Bloodthirst" },
	{ 18499, "Berserker Rage" },
	{ 20554, "Berserking" },
	{ 20572, "Blood Fury" },
	{ 1161, "Challenging Shout" },
	{ 100, "Charge" },
	{ 845, "Cleave" },
	{ 12809, "Concussion Blow" },
	{ 71, "Defensive Stance" },
	{ 1160, "Demoralizing Shout" },
	{ 12328, "Death Wish" },
	{ 676, "Disarm" },
	{ 5308, "Execute" },
	{ 1715, "Hamstring" },
	{ 78, "Heroic Strike" },
	{ 20252, "Intercept" },
	{ 5246, "Intimidating Shout" },
	{ 694, "Mocking Blow" },
	{ 12975, "Last Stand" },
	{ 12294, "Mortal Strike" },
	{ 7384, "Overpower" },
	{ 6552, "Pummel" },
	{ 1719, "Recklessness" },
	{ 772, "Rend" },
	{ 20230, "Retaliation" },
	{ 6572, "Revenge" },
	{ 72, "Shield Bash" },
	{ 2565, "Shield Block" },
	{ 23922, "Shield Slam" },
	{ 871, "Shield Wall" },
	{ 1240193, "Slam" },            -- Forever Rank 1, niveau 20
	{ 7386, "Sunder Armor" },
	{ 355, "Taunt" },
	{ 6343, "Thunder Clap" },
	{ 402927, "Victory Rush" },     -- Forever, niveau 20
	{ 1680, "Whirlwind" },
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
	["Berserker Rage"] = 30,
	["Death Wish"] = 30,
	["Whirlwind"] = 36,
	["Pummel"] = 38,
	["Bloodthirst"] = 40,
	["Mortal Strike"] = 40,
	["Recklessness"] = 50,
	["Last Stand"] = 20,
	["Concussion Blow"] = 30,
	["Shield Slam"] = 40,
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
	["Bloodrage"] = 60,
	["Bloodthirst"] = 6,
	["Whirlwind"] = 10,
	["Pummel"] = 10,
	["Berserker Rage"] = 30,
	["Overpower"] = 5,
	["Intercept"] = 30,
	["Death Wish"] = 180,
	["Recklessness"] = 1800,
	["Mortal Strike"] = 6,
	["Blood Fury"] = 120,
	["Berserking"] = 180,
	["Shield Slam"] = 6,
	["Revenge"] = 5,
	["Shield Bash"] = 12,
	["Shield Wall"] = 900,
	["Last Stand"] = 180,
	["Concussion Blow"] = 45,
	["Taunt"] = 8,
	["Mocking Blow"] = 120,
	["Challenging Shout"] = 600,
}

-- ==========================================================================
-- TRACKERS LEGERS
-- ==========================================================================

-- ActionLITE doit rester autonome. Ces trackers ne servent que lorsque les
-- lectures d'aura/cooldown deviennent secretes en combat sur le client 1.60.
local localCooldowns = {}
local localCastAt = {}
local tankCooldownDurations = {}
local tankCooldownNames = { ["Shield Slam"]=true, ["Revenge"]=true, ["Shield Bash"]=true,
	["Shield Block"]=true, ["Shield Wall"]=true, ["Last Stand"]=true, ["Concussion Blow"]=true,
	["Taunt"]=true, ["Mocking Blow"]=true, ["Challenging Shout"]=true }
local furyDecision
local furyCurveFailures, furyVisibilityCurves = {}, {}
local furyRetryAfter = {}
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

-- Talent reads are cached between public talent/spell changes. A selected
-- reference build never grants talents that the character has not learned.
local armsTalentRanks, tankTalentRanks
local function ArmsTalentRank(name)
	if armsTalentRanks then return armsTalentRanks[name] end
	armsTalentRanks = {}
	if type(GetTalentInfo) ~= "function" then return nil end
	for index = 1, 40 do
		local ok, talent, _, _, _, rank = pcall(GetTalentInfo, 1, index, false, false)
		if ok and SafeValue(talent) and type(talent) == "string" then
			local value = HamstringNumber(rank)
			if value and value >= 0 and value <= 5 then
				armsTalentRanks[talent] = value
				local english = AL.englishNames and AL.englishNames[talent]
				if english then armsTalentRanks[english] = value end
			end
		end
	end
	for english,id in pairs({["Improved Slam"]=12862,["Improved Tactical Mastery"]=12295}) do
		local reader=C_Spell and C_Spell.GetSpellName
		if type(reader)=="function" then
			local ok,localized=pcall(reader,id)
			if ok and SafeValue(localized) and type(localized)=="string" and armsTalentRanks[localized]~=nil then
				armsTalentRanks[english]=armsTalentRanks[localized]
			end
		end
	end
	return armsTalentRanks[name]
end
local armsTalentEvents = CreateFrame("Frame")
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED","PLAYER_TALENT_UPDATE",
	"ACTIVE_TALENT_GROUP_CHANGED","SPELLS_CHANGED"}) do pcall(armsTalentEvents.RegisterEvent,armsTalentEvents,event) end
armsTalentEvents:SetScript("OnEvent",function(_,event)
	armsTalentRanks,tankTalentRanks=nil,nil
	if event~="PLAYER_REGEN_ENABLED" then tankCooldownDurations={} end
end)

local function TankTalentRank(name)
	if not tankTalentRanks then
		tankTalentRanks={}
		if type(GetTalentInfo)=="function" then
			for index=1,40 do
				local ok,talent,_,_,_,rank=pcall(GetTalentInfo,3,index,false,false)
				local value=HamstringNumber(rank)
				if ok and SafeValue(talent) and type(talent)=="string" and value and value>=0 and value<=5 then
					tankTalentRanks[talent]=value
				end
			end
		end
		local reader=C_Spell and C_Spell.GetSpellName
		if type(reader)=="function" then
			local ok,localized=pcall(reader,12312)
			if ok and SafeValue(localized) and type(localized)=="string" then
				tankTalentRanks["Improved Shield Wall"]=tankTalentRanks[localized]
			end
		end
	end
	return tankTalentRanks[name]
end

local function TankCooldownFallback(name,fallback)
	if tankCooldownDurations[name] then return tankCooldownDurations[name] end
	if name=="Shield Wall" then
		local rank=TankTalentRank("Improved Shield Wall")
		if rank and rank<=2 then return 900-330*rank end
	end
	return fallback
end

local function ArmsSlamCastTime()
	local rank=ArmsTalentRank("Improved Slam")
	if rank and rank<=2 then return math.max(0,1.5-0.25*rank) end
	local ref=AL.rangeSpellRefs and AL.rangeSpellRefs["Slam"]
	local reader=C_Spell and C_Spell.GetSpellInfo
	if type(reader)=="function" then
		local ok,info=pcall(reader,ref and HamstringNumber(ref.id) or "Slam")
		if ok and SafeValue(info) and type(info)=="table" then
			local ms=HamstringNumber(info.castTime)
			if ms and ms>=0 and ms<=10000 then return ms/1000 end
		end
	end
end

local function ArmsCooldownFallback(name, fallback)
	local s=AL.Profile("WARRIOR")
	if not s or s.arms~=true then return fallback end
	if name=="Slam" then
		local rank=ArmsTalentRank("Improved Slam")
		-- The client curve scales cast time/GCD by rank, while its separate
		-- cooldown effect is a flat three seconds at either learned rank.
		if rank and rank<=2 then return rank>0 and 15 or 18 end
	end
	return fallback
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
	local profile=AL.Profile("WARRIOR")
	if profile and (profile.arms==true or M.ProtectionActive and M.ProtectionActive(profile)) then
		local ref=AL.rangeSpellRefs and AL.rangeSpellRefs["Rend"]
		local id=ref and HamstringNumber(ref.id)
		local duration=({[772]=9,[6546]=12,[6547]=15,[6548]=18,[11572]=21,[11573]=21,[11574]=21})[id]
		if duration then return duration end
		if level>=40 then return 21 end
	end
	if level >= 30 then return 18 end
	if level >= 20 then return 15 end
	if level >= 10 then return 12 end
	return 9
end

local function TrackSuccessfulCast(name, targetMatches)
	local now = GetTime()
	furyRetryAfter[name] = nil
	local cooldown = ArmsCooldownFallback(name, TankCooldownFallback(name, LOCAL_COOLDOWNS[name]))
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
					if nativeEnd > now then
						expires = nativeEnd
						if tankCooldownNames[name] then tankCooldownDurations[name]=duration/rate end
					end
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
		demoExpires = now + (M.ProtectionActive and M.ProtectionActive(AL.Profile("WARRIOR")) and 45 or 30)
	elseif name == "Sunder Armor" and (guid or targetMatches) then
		sunderStacks = math.min(SUNDER_MAX_STACKS, sunderStacks + 1)
		sunderExpires = now + 30
	end
end

local TRACKED_CASTS = {
	["Shield Slam"] = true,
	["Revenge"] = true,
	["Shield Bash"] = true,
	["Shield Wall"] = true,
	["Last Stand"] = true,
	["Concussion Blow"] = true,
	["Taunt"] = true,
	["Mocking Blow"] = true,
	["Challenging Shout"] = true,
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
	["Bloodrage"] = true,
	["Bloodthirst"] = true,
	["Whirlwind"] = true,
	["Pummel"] = true,
	["Berserker Rage"] = true,
	["Overpower"] = true,
	["Intercept"] = true,
	["Death Wish"] = true,
	["Recklessness"] = true,
	["Mortal Strike"] = true,
	["Blood Fury"] = true,
	["Berserking"] = true,
}

local furyCastIDs = {
	[23922]="Shield Slam",[23923]="Shield Slam",[23924]="Shield Slam",[23925]="Shield Slam",
	[6572]="Revenge",[6574]="Revenge",[7379]="Revenge",[11600]="Revenge",[11601]="Revenge",[25288]="Revenge",
	[72]="Shield Bash",[1671]="Shield Bash",[1672]="Shield Bash",[2565]="Shield Block",
	[871]="Shield Wall",[12975]="Last Stand",[12809]="Concussion Blow",[355]="Taunt",
	[694]="Mocking Blow",[7400]="Mocking Blow",[7402]="Mocking Blow",[20559]="Mocking Blow",[20560]="Mocking Blow",
	[1161]="Challenging Shout",
	[2687] = "Bloodrage",
	[23881] = "Bloodthirst", [23892] = "Bloodthirst", [23893] = "Bloodthirst", [23894] = "Bloodthirst",
	[1680] = "Whirlwind", [6552] = "Pummel", [6554] = "Pummel", [18499] = "Berserker Rage",
	[7384] = "Overpower", [7887] = "Overpower", [11584] = "Overpower", [11585] = "Overpower",
	[20252] = "Intercept", [20616] = "Intercept", [20617] = "Intercept",
	[12328] = "Death Wish", [1719] = "Recklessness",
	[12294] = "Mortal Strike", [21551] = "Mortal Strike", [21552] = "Mortal Strike", [21553] = "Mortal Strike",
	[20572] = "Blood Fury", [20554] = "Berserking", [26296] = "Berserking",
}
local furyCooldownNames = { ["Bloodrage"] = true, ["Bloodthirst"] = true, ["Whirlwind"] = true,
	["Pummel"] = true, ["Berserker Rage"] = true, ["Overpower"] = true, ["Intercept"] = true,
	["Death Wish"] = true, ["Recklessness"] = true, ["Mortal Strike"] = true,
	["Blood Fury"] = true, ["Berserking"] = true }
local armsCooldownNames={ ["Slam"]=true,["Spearing Strike"]=true }
local function ArmsOwnsCooldown(name)
	local s=AL.Profile("WARRIOR")
	return armsCooldownNames[name] and s and s.arms==true
end

local function TrackedCastName(arg2, arg3, arg4)
	local function Read(value)
		if SafeValue(value) then
			if type(value) == "string" and TRACKED_CASTS[value] then
				return value
			elseif type(value) == "number" then
				if furyCastIDs[value] then return furyCastIDs[value] end
				for name in pairs(TRACKED_CASTS) do
					local ref = AL.rangeSpellRefs and AL.rangeSpellRefs[name]
					if ref and value == HamstringNumber(ref.id) then return name end
				end
				local ok, name = pcall(AL.SpellName, value)
				if ok and SafeValue(name) and type(name) == "string" then
					name = (AL.englishNames and AL.englishNames[name]) or name
					if furyCooldownNames[name] or tankCooldownNames[name] then return nil end
					if ArmsOwnsCooldown(name) then
						local allowed=name=="Spearing Strike" and value==1310222
							or name=="Slam" and ({[1240193]=true,[1464]=true,[8820]=true,[11604]=true,[11605]=true,
							[1310196]=true,[1310197]=true,[1310198]=true,[1310199]=true,[1310200]=true})[value]
						if not allowed then return nil end
					end
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
		furyRetryAfter = {}
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
			if not (furyDecision and furyDecision.visualCandidate) and SafeValue(suggestion) and TRACKED_CASTS[suggestion] then name = suggestion end
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
		if pendingTrackedCast and (furyCooldownNames[pendingTrackedCast.name] or tankCooldownNames[pendingTrackedCast.name])
			and (not guid or not pendingTrackedCast.guid or guid == pendingTrackedCast.guid) then
			furyRetryAfter[pendingTrackedCast.name] = GetTime() + 1
		end
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
			if matches and sent.name ~= name then return end
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
			demoExpires = GetTime() + (M.ProtectionActive and M.ProtectionActive(AL.Profile("WARRIOR")) and 45 or 30)
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
	local raw = s and s[key]
	local value = SafeValue(raw) and HamstringNumber(tonumber(raw)) or nil
	if value == nil then value = defaultValue end
	value = math.floor(value + 0.5)
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

local function LocalReady(name)
	local expires = localCooldowns[name]
	if name == "Shield Block" or name == "Thunder Clap" or name == "Sweeping Strikes" or furyCooldownNames[name] or tankCooldownNames[name] or ArmsOwnsCooldown(name) then
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
	-- Explicit DPS selection takes priority; all unchecked keeps the earlier
	-- stance-based leveling fallback, including Defensive Stance tanking.
	if s and s.protection == true then return "TANK" end
	if s and (s.arms == true or s.fury == true) then return "DPS" end
	if PlayerStance() == 2 then return "TANK" end
	return s and (s.protection==true or s.warriorRole=="TANK") and "TANK" or "DPS"
end

function M.ProtectionActive(s)
	return WarriorRole(s)=="TANK"
end

function M.ArmsSelected(s)
	return s and SafeValue(s.arms) and s.arms==true and WarriorRole(s)=="DPS"
end

function M.SetTankBuild(enabled, profile)
 return M.SetBuild("protection", enabled, profile)
end

function M.InitializeProtectionSettings(s)
	if type(s)~="table" then return end
	if s.protectionAttacksVersion~=1 then
		local heroic=SafeValue(s.tankHeroicDumpRage) and HamstringNumber(tonumber(s.tankHeroicDumpRage))
		if not heroic or heroic==70 then s.tankHeroicDumpRage=20 end
		if not (SafeValue(s.tankCleaveDumpRage) and HamstringNumber(tonumber(s.tankCleaveDumpRage))) then s.tankCleaveDumpRage=20 end
		s.protectionAttacksVersion=1
	end
	if s.protectionBuildVersion~=1 then
		s.protectionBuildVersion=1
		-- The explicit build checkbox owns the saved role; no automatic selection.
		M.NormalizeBuild(s)
	end
end

function M.TankSetting(s,key)
	local bounds={tankSunderMaxStacks={5,0,5},tankHeroicDumpRage={20,20,100},
		tankCleaveDumpRage={20,20,100},tankShieldWallHP={35,10,80},tankLastStandHP={25,10,80},
		tankBurstMinTargetHP={35,0,100}}
	local limits=bounds[key]
	if limits then return SettingNumber(s,key,limits[1],limits[2],limits[3]) end
end

function M.SetDPSBuild(build, enabled, profile)
 if build ~= "arms" and build ~= "fury" then return end
 return M.SetBuild(build, enabled, profile)
end

function M.FuryUsesTalentSettings(s)
	return s and not M.ArmsSelected(s) and s.fury == true and WarriorRole(s) == "DPS" and Known("Bloodthirst")
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
	if type(GetInventoryItemID)~="function" then return nil end
	local okID,itemID=pcall(GetInventoryItemID,"player",17)
	if not okID or not SafeValue(itemID) then return nil end
	if itemID==nil or itemID==0 then return false end
	if not HamstringNumber(itemID) then return nil end
	local reader=type(GetItemInfoInstant)=="function" and GetItemInfoInstant or C_Item and C_Item.GetItemInfoInstant
	if type(reader)~="function" then return nil end
	local ok,_,_,_,equipLoc,_,classID,subClassID=pcall(reader,itemID)
	if not ok then return nil end
	if SafeValue(equipLoc) and type(equipLoc)=="string" and equipLoc~="" then return equipLoc=="INVTYPE_SHIELD" end
	classID,subClassID=HamstringNumber(classID),HamstringNumber(subClassID)
	if classID and subClassID then return classID==4 and subClassID==6 end
end

local function TargetNeedsTaunt(unit)
	unit=(unit or "target").."target"
	if not SafeUnitExists(unit) or type(UnitIsUnit)~="function" or type(UnitIsFriend)~="function" then return false end
	local okSelf,isSelf=pcall(UnitIsUnit,unit,"player")
	if not okSelf or not SafeValue(isSelf) or type(isSelf)~="boolean" or isSelf then return false end
	local okFriend,isFriend=pcall(UnitIsFriend,"player",unit)
	return okFriend and SafeValue(isFriend) and isFriend==true
end

local function TankLooseEnemies()
	local count,seen=0,{}
	for _,unit in ipairs(NAMEPLATE_UNITS) do
		if SafeUnitExists(unit) and SafeCanAttack(unit)==true and SafeUnitCombat(unit)==true
			and HeroicStrikeInRange(unit)==true and TargetNeedsTaunt(unit) then
			local ok,guid=pcall(UnitGUID,unit)
			if ok and SafeValue(guid) and type(guid)=="string" and not seen[guid] then
				seen[guid]=true;count=count+1
			end
		end
	end
	return count
end

local function TankSunderCap(s)
	return SettingNumber(s, "tankSunderMaxStacks", 5, 0, SUNDER_MAX_STACKS)
end

local function PlayerMoving()
	if A and A.Player and A.Player.IsMoving then
		local ok, moving = pcall(A.Player.IsMoving, A.Player)
		if ok and SafeValue(moving) and type(moving) == "boolean" then return moving end
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
	if M.ArmsSelected(AL.Profile("WARRIOR")) or WarriorRole(AL.Profile("WARRIOR"))=="TANK" then
		-- The older Core can retain a Warrior debuff entry after its timer.
		-- Confirmed learned-rank Rend timing must still permit a refresh.
		if rendExpires>0 then return rendExpires>GetTime() end
		local entry=AL.targetDebuffs and AL.targetDebuffs["Rend"]
		local expires=type(entry)=="table" and HamstringNumber(entry.expires)
		if expires then return expires>GetTime() end
	end
	local ok,active=pcall(AL.HasDebuff,"target","Rend")
	return rendExpires>GetTime() or ok and SafeValue(active) and active==true
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
	local precise=M.ArmsSelected(AL.Profile("WARRIOR")) or M.ProtectionActive(AL.Profile("WARRIOR"))
	if precise and demoExpires>0 then return demoExpires>GetTime() end
	local entry=AL.targetDebuffs and AL.targetDebuffs["Demoralizing Shout"]
	if precise and type(entry)=="table" and HamstringNumber(entry.expires) then return entry.expires>GetTime() end
	local ok,active=pcall(AL.HasDebuff,"target","Demoralizing Shout")
	return demoExpires>GetTime() or ok and SafeValue(active) and active==true
end

local function BattleShoutActive()
	local ok,active=pcall(AL.HasBuff,"player","Battle Shout")
	return battleShoutExpires>GetTime() or ok and SafeValue(active) and active==true
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
			stacks=HamstringNumber(stacks)
			if okStacks and stacks and stacks>sunderStacks then
				sunderStacks = math.min(SUNDER_MAX_STACKS, stacks)
			end
		end
	end

	-- Fallback ActionLITE : chaque expiration differente correspond a un cast reussi.
	local coreDebuff = AL.targetDebuffs and AL.targetDebuffs["Sunder Armor"]
	if type(coreDebuff)=="table" and HamstringNumber(coreDebuff.expires)
		and (not M.ArmsSelected(AL.Profile("WARRIOR")) and WarriorRole(AL.Profile("WARRIOR"))~="TANK" or coreDebuff.expires>GetTime())
		and coreDebuff.expires > lastCoreSunderExpires + 0.01 then
		if sunderExpires == 0 or math.abs(coreDebuff.expires - sunderExpires) > 1 then
			sunderStacks = math.min(SUNDER_MAX_STACKS, sunderStacks + 1)
		end
		lastCoreSunderExpires = coreDebuff.expires
		sunderExpires = math.max(sunderExpires, coreDebuff.expires)
	end

	local expiredArmsEntry=(M.ArmsSelected(AL.Profile("WARRIOR")) or WarriorRole(AL.Profile("WARRIOR"))=="TANK") and coreDebuff
		and HamstringNumber(coreDebuff.expires) and coreDebuff.expires<=GetTime()
	local auraOK,auraActive=pcall(AL.HasDebuff,"target","Sunder Armor")
	if sunderStacks==0 and not expiredArmsEntry and auraOK and SafeValue(auraActive) and auraActive==true then
		sunderStacks = 1
	end

	return sunderStacks
end

local function HeroicDumpAt(s)
	if M.ArmsSelected(s) then return SettingNumber(s,"armsHeroicDumpRage",80,15,100) end
	local configured = tonumber(s and s.heroicDumpRage)
	if configured ~= nil then
		return SettingNumber(s, "heroicDumpRage", HEROIC_DUMP_RAGE, 15, 100)
	end
	if M.FuryUsesTalentSettings(s) then return 50 end
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
			if SafeValue(info.isEnabled) and info.isEnabled == false then return false end
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
				if tankCooldownNames[name] and start and start>0 and duration and duration>1.5 and rate and rate>0 then
					tankCooldownDurations[name]=duration/rate
					localCooldowns[name]=start+duration/rate
				end
				return ready
			end
		end
	end
	if furyCooldownNames[name] or tankCooldownNames[name] or ArmsOwnsCooldown(name) then return LocalReady(name) end
	return LocalReady(name) and AL.IsReady(name)
end

local function ReadyRageSpell(name)
	if furyRetryAfter[name] and furyRetryAfter[name] > GetTime() then return false end
	if not Ok(name) then return false end
	if name == "Thunder Clap" or name == "Sweeping Strikes" or furyCooldownNames[name] or tankCooldownNames[name] or ArmsOwnsCooldown(name) then
		if not AoECooldownReady(name) then return false end
	elseif not LocalReady(name) or not AL.IsReady(name) then return false end
	if M.ArmsSelected(AL.Profile("WARRIOR")) or WarriorRole(AL.Profile("WARRIOR"))=="TANK" then
		local reader=C_Spell and C_Spell.IsSpellUsable
		local ref=AL.rangeSpellRefs and AL.rangeSpellRefs[name]
		if type(reader)=="function" then
			local ok,usable,shortage=pcall(reader,ref and HamstringNumber(ref.id) or name)
			if ok and SafeValue(usable) and usable==false then return false end
			if ok and SafeValue(shortage) and shortage==true then return false end
		end
	end
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
	if M.ArmsSelected(s) then return SettingNumber(s,"armsSunderMaxStacks",1,0,SUNDER_MAX_STACKS) end
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
	local multiTarget = s.aoe and MultiTargetConfirmed(enemyCount)
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
		local overflowSpell, overflowReason = OverflowDump(s, rage, s.aoe and enemyCount or 1, false)
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

-- Fury uses public decisions and native display masks when combat hides Rage
-- or health. Protected values are passed to SetAlpha, never compared in Lua.
local function FuryCurveAvailable(kind, unit)
	local reader = kind == "power" and UnitPowerPercent or UnitHealthPercent
	local failure = furyCurveFailures[kind .. ":" .. unit]
	return not (failure and failure == reader) and type(reader) == "function"
		and C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function" and type(CreateColor) == "function"
end

local function FuryNextFloat(value)
	if value <= 0 then return 2 ^ -149 end
	local step = 2 ^ (math.floor(math.log(value) / math.log(2)) - 23)
	return (math.floor(value / step + 0.5) + 1) * step
end

local function FuryGate(kind, unit, value, threshold, below, strict, fallback)
	value = HamstringNumber(value)
	if value ~= nil then
		if math.abs(value - threshold) < 1e-7 then value = threshold end
		if below then return strict and value < threshold or not strict and value <= threshold end
		return strict and value > threshold or not strict and value >= threshold
	end
	if not FuryCurveAvailable(kind, unit) then return fallback == true end
	local cut = threshold / 100
	if below and not strict or not below and strict then cut = FuryNextFloat(cut) end
	return { axis = kind .. ":" .. unit, kind = kind, unit = unit,
		powerType = kind == "power" and 1 or nil, cut = cut, below = below }
end

local function FuryAdd(spell, reason, gates)
	local conditions = {}
	for _, gate in ipairs(gates or {}) do
		if gate == false then return false end
		if type(gate) == "table" then conditions[#conditions + 1] = gate end
	end
	local actions = furyDecision.actions
	if #actions > 0 and #actions[#actions].conditions == 0 then return false end
	actions[#actions + 1] = { spell = spell, reason = reason, conditions = conditions }
	if #conditions > 0 then furyDecision.visualCandidate = true end
	return true
end

local function FuryRageGate(rage, threshold, below, strict, fallback)
	return FuryGate("power", "player", rage, threshold, below, strict, fallback)
end

local function FuryOffer(name, reason, rage, fallbackCost, gates)
	if not ReadyRageSpell(name) then return false end
	if name ~= "Whirlwind" and name ~= "Battle Shout" and name ~= "Bloodrage"
		and name ~= "Berserker Rage" and name ~= "Berserker Stance" and name ~= "Battle Stance"
		and name ~= "Death Wish" and name ~= "Recklessness" and name ~= "Blood Fury" and name ~= "Berserking"
		and name ~= "Defensive Stance" and name ~= "Shield Block" and name ~= "Shield Wall"
		and name ~= "Last Stand" and name ~= "Challenging Shout" then
		if SpellRangeState(name) == false then return false end
	end
	local conditions = { FuryRageGate(rage, RageSpellCost(name, fallbackCost or 0), false, false, true) }
	for _, gate in ipairs(gates or {}) do conditions[#conditions + 1] = gate end
	return FuryAdd(name, reason, conditions)
end

local function FuryOverpowerWindow()
	local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if type(reader) ~= "function" then return false end
	for index = 1, 40 do
		local ok, aura = pcall(reader, "player", index, "HELPFUL")
		if not ok or not SafeValue(aura) then return false end
		if aura == nil then return false end
		if type(aura) ~= "table" then return false end
		if HamstringNumber(aura.spellId) == 1282733 then return true end
	end
	return false
end

local function FuryBurstActive(name, duration)
	local ok, active = pcall(AL.HasBuff, "player", name)
	if ok and SafeValue(active) and active == true then return true end
	local at = localCastAt[name]
	return at ~= nil and GetTime() < at + duration
end

function M.FuryBurstMinimum(s)
	local raw = s and s.furyBurstMinTargetHP
	local value = SafeValue(raw) and HamstringNumber(tonumber(raw)) or nil
	return math.max(0, math.min(100, math.floor((value or 35) + 0.5)))
end

local function FuryBurst(s, rage, targetHP, stance)
	if not AL.burst then return end
	local minimum = M.FuryBurstMinimum(s)
	local gate = minimum <= 0 or FuryGate("health", "target", targetHP, minimum, false, false, false)
	if s.furyDeathWish and not FuryBurstActive("Death Wish", 30) then
		FuryOffer("Death Wish", "Burst: physical damage", rage, 10, { gate })
	end
	if s.furyRecklessness and not FuryBurstActive("Recklessness", 15) then
		if stance == 3 then
			FuryOffer("Recklessness", "Burst: critical strikes", rage, 0, { gate })
		elseif s.furyAutoStance and stance == 1 and Ok("Recklessness") and AoECooldownReady("Recklessness") then
			FuryOffer("Berserker Stance", "prepare Burst Recklessness", rage, 0, { gate })
		end
	end
end

local function FuryPrimaryRemaining(s)
	if not s.bloodthirst or not Ok("Bloodthirst") then return 100 end
	local ref = AL.rangeSpellRefs and AL.rangeSpellRefs["Bloodthirst"]
	local reader = C_Spell and C_Spell.GetSpellCooldown
	if type(reader) == "function" then
		local ok, info = pcall(reader, ref and HamstringNumber(ref.id) or "Bloodthirst")
		if ok and SafeValue(info) and type(info) == "table" then
			local start, duration, rate = HamstringNumber(info.startTime), HamstringNumber(info.duration), HamstringNumber(info.modRate)
			if SafeValue(info.modRate) and info.modRate == nil then rate = 1 end
			if start and duration and rate and rate > 0 then
				local remaining = math.max(0, start + duration / rate - GetTime())
				if remaining > 0 or not localCastAt["Bloodthirst"] or GetTime() - localCastAt["Bloodthirst"] >= 0.5 then return remaining end
			end
		end
	end
	return math.max(0, (localCooldowns["Bloodthirst"] or 0) - GetTime())
end

local function NextFury(s, inCombat, hostile)
	if not inCombat then
		if hostile and s.furyAutoStance and PlayerStance() == 3 and Known("Charge")
			and SpellRangeState("Charge") == true and OkReady("Battle Stance") and AL.SpellUsable("Battle Stance") then
			return "Battle Stance", "prepare learned Charge"
		end
		return NextDPS(s, false, hostile)
	end
	if not hostile then return nil, "No target" end
	if ChargeAvailable() then return "Charge", "in-combat Charge usable + verified range" end
	local casting = AL.CastingSpell and AL.CastingSpell()
	if SafeValue(casting) and type(casting) == "string" then return nil, "Casting" end
	for _, reader in pairs({ UnitCastingDuration, UnitChannelDuration }) do
		if type(reader) == "function" then
			local ok, duration = pcall(reader, "player")
			if ok and SafeValue(duration) and (type(duration) == "table" or type(duration) == "userdata") then return nil, "Casting" end
		end
	end
	local rage, hp, targetHP = HamstringNumber(AL.Power(1)), HamstringNumber(AL.HealthPercent("player")), HamstringNumber(AL.HealthPercent("target"))
	local stance, ttd = PlayerStance(), TargetTTD()
	furyDecision = { at = GetTime(), actions = {} }
	if not VerifiedMelee(AL.TargetInMelee()) then
		if s.furyIntercept and stance == 3 and SpellRangeState("Intercept") == true then FuryOffer("Intercept", "verified gap closer", rage, 10) end
		FuryAdd(AL.known["Attack"] and "Attack" or nil, "move to melee")
		local base = furyDecision.actions[#furyDecision.actions]
		furyDecision.baseSpell, furyDecision.baseReason = base.spell, base.reason
		return base.spell, base.reason
	end
	local minimum = SettingNumber(s, "aoeMinEnemies", 2, 2, 5)
	local enemies = EnemyCountMelee(math.max(minimum, 5))
	local aoeActive = AoEModeActive(s, enemies, minimum)

	if s.furyInterrupt and stance == 3 and AL.TargetCasting() then FuryOffer("Pummel", "interrupt", rage, 10) end
	if s.victory then FuryOffer("Victory Rush", "heal + free damage", rage, 0, {
		FuryGate("health", "player", hp, 65, true, false, false) }) end
	local slowSpell, slowReason = MaintainHamstring(s, rage, true)
	if slowSpell then FuryOffer(slowSpell, slowReason, rage, 10) end
	if s.shout and not BattleShoutActive() then FuryOffer("Battle Shout", "maintain own attack-power buff", rage, 10) end
	if s.sunder and ShouldSunder(s, targetHP, ttd, SunderStacks()) then
		FuryOffer("Sunder Armor", "own armor stack " .. tostring(SunderStacks() + 1), rage, 15, {
			FuryRageGate(rage, 30, false, false, true),
			FuryGate("health", "target", targetHP, SUNDER_STOP_HP, false, false, true) })
	end

	FuryBurst(s, rage, targetHP, stance)

	-- Area attacks exist only here and require the selected AoE mode.
	if aoeActive then
		if stance == 3 and s.whirlwind then FuryOffer("Whirlwind", "Fury AoE", rage, 25) end
		if stance == 1 then
			local active = AL.HasBuff("player", "Sweeping Strikes")
			if not (SafeValue(active) and active == true) then FuryOffer("Sweeping Strikes", "AoE opener", rage, 30, {
				FuryRageGate(rage, SettingNumber(s, "sweepingReserveRage", 50, 30, 100), false, false, false) }) end
			FuryOffer("Thunder Clap", "AoE damage + attack-speed slow", rage, 20)
		end
	end
	if s.execute then FuryOffer("Execute", "finisher", rage, 15, {
		FuryGate("health", "target", targetHP, 20, true, false, true) }) end

	local overpowerWindow = s.overpower and s.furyOverpowerDance and AoECooldownReady("Overpower") and FuryOverpowerWindow()
	if stance == 3 and s.furyAutoStance and overpowerWindow and Ok("Overpower") and LocalReady("Overpower") then
		FuryOffer("Battle Stance", "verified Overpower window", rage, 0, {
			FuryRageGate(rage, 50, true, false, false) })
	end
	if stance == 1 and s.overpower then FuryOffer("Overpower", "usable proc", rage, 5) end
	if s.bloodthirst then FuryOffer("Bloodthirst", "Fury primary strike", rage, 30) end
	if s.furyAutoStance and stance == 1 and not overpowerWindow
		and (Known("Bloodthirst") or aoeActive and s.whirlwind and Known("Whirlwind")) then
		FuryOffer("Berserker Stance", "Fury stance", rage, 0)
	end
	if not Known("Bloodthirst") and stance == 1 and s.rend and not RendActive() and ShouldRend(targetHP, ttd) then
		FuryOffer("Rend", "leveling bleed", rage, 10)
	end
	if s.victory then FuryOffer("Victory Rush", "free damage + heal", rage, 0) end

	if aoeActive then
		if not StrikeQueued("Cleave") and not StrikeQueued("Heroic Strike") then FuryOffer("Cleave", "Fury AoE queued attack", rage, 20, {
			FuryRageGate(rage, SettingNumber(s, "furyCleaveDumpRage", 40, 20, 100), false, false, false) }) end
	else
		if s.heroic and not StrikeQueued("Heroic Strike") and not StrikeQueued("Cleave") then
			-- Keep the confirmed full-Rage safety dump while allowing the normal
			-- configured threshold to reserve Rage for Bloodthirst and Execute.
			FuryOffer("Heroic Strike", "prevent rage overflow", rage, 15, {
				FuryRageGate(rage, RAGE_OVERFLOW_DUMP, false, false, false) })
		end
		local useSlam = s.slam
		if M.FuryUsesTalentSettings(s) then useSlam = s.furySlam end
		if useSlam and not PlayerMoving() and FuryPrimaryRemaining(s) > 1.5 then
			local timing = SlamTimingState()
			if timing ~= false then FuryOffer("Slam", "Fury filler between primary strikes", rage, 15, {
				FuryRageGate(rage, SettingNumber(s, "slamReserveRage", 30, 15, 100), false, false, false) }) end
		end
		if s.heroic and not StrikeQueued("Heroic Strike") and not StrikeQueued("Cleave") then FuryOffer("Heroic Strike", "Fury queued rage dump", rage, 15, {
			FuryRageGate(rage, HeroicDumpAt(s), false, false, false) }) end
	end
	if s.demo and not DemoActive() then FuryOffer("Demoralizing Shout", "mitigation", rage, 10) end
	if s.bloodrage then
		local legacy, reason = ShouldBloodrage(s, rage, hp)
		FuryOffer("Bloodrage", reason, rage, 0, {
			FuryRageGate(rage, 20, true, true, legacy),
			FuryGate("health", "player", hp, 75, false, false, hp == nil) })
	end
	if s.furyBerserkerRage and stance == 3 then FuryOffer("Berserker Rage", "damage-taken rage + fear immunity", rage, 0) end
	if AL.burst and (targetHP == nil or targetHP > 35) and (ttd == nil or ttd >= 10) then
		if OkReady("Blood Fury") then FuryAdd("Blood Fury", "burst") end
		if OkReady("Berserking") then FuryAdd("Berserking", "burst") end
	end
	FuryAdd(AL.known["Attack"] and "Attack" or nil, "melee / pool rage")
	local base = furyDecision.actions[#furyDecision.actions]
	furyDecision.baseSpell, furyDecision.baseReason = base.spell, base.reason
	return base.spell, base.reason
end

-- Arms uses the same protected-resource display engine as Fury. A reference
-- selection only changes priorities; all casts still require learned spells.
local function ArmsRemaining(name)
	if not Ok(name) then return 100 end
	local reader=C_Spell and C_Spell.GetSpellCooldown
	local ref=AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	if type(reader)=="function" then
		local ok,info=pcall(reader,ref and HamstringNumber(ref.id) or name)
		if ok and SafeValue(info) and type(info)=="table" then
			local start,duration,rate=HamstringNumber(info.startTime),HamstringNumber(info.duration),HamstringNumber(info.modRate)
			if SafeValue(info.modRate) and info.modRate==nil then rate=1 end
			if start and start>=0 and duration and duration>=0 and rate and rate>0 then
				local remaining=duration<=1.5 and 0 or math.max(0,start+duration/rate-GetTime())
				if remaining>0 or not localCastAt[name] or GetTime()-localCastAt[name]>=0.5 then return remaining end
			end
		end
	end
	if localCooldowns[name] then return math.max(0,localCooldowns[name]-GetTime()) end
	if AoECooldownReady(name) then return 0 end
	return nil
end

local function ArmsBuildersBusy(s)
	for _,row in ipairs({{"Mortal Strike",s.mortalStrike},{"Slam",s.armsSlam}}) do
		if row[2] and Ok(row[1]) then
			local remains=ArmsRemaining(row[1])
			if remains==nil or remains<=1 then return false end
		end
	end
	return true
end

local function ArmsProcAvailable(name)
	local reader=C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
	local ref=AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	if type(reader)=="function" then
		local ok,usable=pcall(reader,ref and HamstringNumber(ref.id) or name)
		if ok and SafeValue(usable) and type(usable)=="boolean" then return usable end
	end
	return name=="Overpower" and FuryOverpowerWindow()
end

function M.ArmsBurstMinimum(s)
	local raw=s and s.armsBurstMinTargetHP
	local value=SafeValue(raw) and HamstringNumber(tonumber(raw)) or nil
	return math.max(0,math.min(100,math.floor((value or 35)+0.5)))
end

local function ArmsBurst(s,rage,targetHP,stance)
	if not AL.burst then return end
	local minimum=M.ArmsBurstMinimum(s)
	local gate=minimum<=0 or FuryGate("health","target",targetHP,minimum,false,false,false)
	if s.armsRecklessness and not FuryBurstActive("Recklessness",15) then
		if stance==3 then FuryOffer("Recklessness","Arms Burst: critical strikes",rage,0,{gate})
		elseif stance==1 and s.armsAutoStance and Ok("Recklessness") and AoECooldownReady("Recklessness") then
			FuryOffer("Berserker Stance","prepare Arms Burst Recklessness",rage,0,
				{gate,FuryRageGate(rage,25,true,false,false)})
		end
	end
	if s.armsBloodFury and not FuryBurstActive("Blood Fury",15) then FuryOffer("Blood Fury","Arms Burst: learned racial",rage,0,{gate}) end
	if s.armsBerserking and not FuryBurstActive("Berserking",10) then FuryOffer("Berserking","Arms Burst: learned racial",rage,0,{gate}) end
end

local function NextArms(s,inCombat,hostile)
	if not inCombat then
		if hostile and s.armsAutoStance and PlayerStance()==3 and OkReady("Battle Stance") and AL.SpellUsable("Battle Stance") then
			return "Battle Stance","prepare Arms Battle Stance"
		end
		return NextDPS(s,false,hostile)
	end
	if not hostile then return nil,"No target" end
	local casting=AL.CastingSpell and AL.CastingSpell()
	if not SafeValue(casting) or type(casting)=="string" then return nil,"Casting" end
	for _,reader in pairs({UnitCastingInfo,UnitChannelInfo,UnitCastingDuration,UnitChannelDuration}) do
		if type(reader)=="function" then
			local ok,value=pcall(reader,"player")
			if ok and (not SafeValue(value) or value~=nil and value~=false) then return nil,"Casting" end
		end
	end
	if ChargeAvailable() then return "Charge","in-combat Charge usable + verified range" end
	local rage=HamstringNumber(AL.Power(1))
	local hp,targetHP=HamstringNumber(AL.HealthPercent("player")),HamstringNumber(AL.HealthPercent("target"))
	local stance,ttd=PlayerStance(),TargetTTD()
	furyDecision={at=GetTime(),actions={}}
	if not VerifiedMelee(AL.TargetInMelee()) then
		FuryAdd(AL.known.Attack and "Attack" or nil,"move to melee")
	else
		local minimum=SettingNumber(s,"aoeMinEnemies",2,2,5)
		local enemies=EnemyCountMelee(math.max(minimum,5))
		local aoe=s.aoe==true and HamstringNumber(enemies)~=nil and enemies>=minimum
		if s.armsInterrupt and AL.TargetCasting() then
			if stance==3 then FuryOffer("Pummel","interrupt",rage,10)
			elseif stance==1 and ShieldEquipped()==true then FuryOffer("Shield Bash","shield interrupt",rage,10) end
		end
		if s.victory and ArmsProcAvailable("Victory Rush") then FuryOffer("Victory Rush","heal + free damage",rage,0,{FuryGate("health","player",hp,65,true,false,false)}) end
		local slow,reason=MaintainHamstring(s,rage,true)
		if slow then FuryOffer(slow,reason,rage,10) end
		if s.shout and not BattleShoutActive() then FuryOffer("Battle Shout","maintain own attack-power buff",rage,10) end
		ArmsBurst(s,rage,targetHP,stance)
		-- The default Arms preset uses Berserker Stance in execute at <=25 Rage.
		-- Otherwise Battle Stance keeps Rend, Overpower and Spearing available.
		local executeGate=FuryGate("health","target",targetHP,20,true,false,false)
		local normalGate=FuryGate("health","target",targetHP,20,false,true,true)
		if s.armsAutoStance then
			if stance==3 then FuryOffer("Battle Stance","Arms normal stance",rage,0,{normalGate})
			elseif stance==1 and s.execute and Known("Execute") and Known("Berserker Stance") then
				FuryOffer("Berserker Stance","Arms execute stance",rage,0,{executeGate,FuryRageGate(rage,25,true,false,false)})
			end
		end
		if s.sunder and ShouldSunder(s,targetHP,ttd,SunderStacks()) then
			FuryOffer("Sunder Armor","own Arms armor stack",rage,15,
				{FuryGate("health","target",targetHP,SUNDER_STOP_HP,false,false,false)})
		end
		-- Every automatic area attack remains inside the enabled AoE branch.
		if aoe then
			if stance==1 and not FuryBurstActive("Sweeping Strikes",20) then
				FuryOffer("Sweeping Strikes","Arms AoE opener",rage,30,
					{FuryRageGate(rage,SettingNumber(s,"sweepingReserveRage",50,30,100),false,false,false)})
			end
			if stance==1 then FuryOffer("Thunder Clap","Arms AoE damage",rage,20) end
			if stance==3 and s.whirlwind then FuryOffer("Whirlwind","Arms AoE in Berserker Stance",rage,25) end
		end
		if s.execute then FuryOffer("Execute","Arms finisher",rage,15,{executeGate}) end
		if stance==1 and s.rend and not RendActive() and (ttd==nil or ttd>=REND_MIN_TTD) then
			FuryOffer("Rend","Rend for Bloodthrill",rage,10,{normalGate})
		end
		if stance==1 and s.overpower and ArmsProcAvailable("Overpower") then FuryOffer("Overpower","usable dodge / Bloodthrill proc",rage,5) end
		local castTime=ArmsSlamCastTime()
		local slamGates={FuryRageGate(rage,SettingNumber(s,"armsSlamReserveRage",15,15,100),false,false,false)}
		if s.armsSlam and castTime and castTime<1.5 and not PlayerMoving() then
			FuryOffer("Slam","improved Arms Slam",rage,15,slamGates)
		end
		if s.mortalStrike then FuryOffer("Mortal Strike","Arms primary strike",rage,30) end
		if s.armsSlam and (not castTime or castTime>=1.5) and not PlayerMoving() and SlamTimingState()~=false then
			FuryOffer("Slam","leveling Arms Slam",rage,15,slamGates)
		end
		if s.victory and ArmsProcAvailable("Victory Rush") then FuryOffer("Victory Rush","free damage + heal",rage,0) end
		local busy=ArmsBuildersBusy(s)
		local filler=FuryRageGate(rage,SettingNumber(s,"armsFillerReserveRage",20,15,100),false,false,false)
		if stance==1 and s.spear and busy then FuryOffer("Spearing Strike","Arms filler between primary strikes",rage,15,{filler}) end
		if aoe then
			if not StrikeQueued("Cleave") and not StrikeQueued("Heroic Strike") then
				FuryOffer("Cleave","Arms AoE queued attack",rage,20,
					{FuryRageGate(rage,SettingNumber(s,"armsCleaveDumpRage",80,20,100),false,false,false)})
			end
		elseif s.heroic and not StrikeQueued("Heroic Strike") and not StrikeQueued("Cleave") then
			FuryOffer("Heroic Strike","prevent rage overflow",rage,15,
				{FuryRageGate(rage,RAGE_OVERFLOW_DUMP,false,false,false)})
			FuryOffer("Heroic Strike","Arms queued Rage dump",rage,15,
				{FuryRageGate(rage,HeroicDumpAt(s),false,false,false)})
		end
		if s.armsHamstringFiller and busy and (stance==1 or stance==3) then
			FuryOffer("Hamstring","optional Arms damage filler",rage,10,{filler})
		end
		if s.demo and not DemoActive() then FuryOffer("Demoralizing Shout","mitigation",rage,10) end
		if s.bloodrage then
			local legacy,reason=ShouldBloodrage(s,rage,hp)
			FuryOffer("Bloodrage",reason,rage,0,{FuryRageGate(rage,20,true,true,legacy),FuryGate("health","player",hp,75,false,false,hp==nil)})
		end
		FuryAdd(AL.known.Attack and "Attack" or nil,"Arms melee / pool Rage")
	end
	local base=furyDecision.actions[#furyDecision.actions]
	furyDecision.baseSpell,furyDecision.baseReason=base.spell,base.reason
	return base.spell,base.reason
end

-- ========================================================================
-- TANK : donjons / leveling 1-60
-- ========================================================================
local function TankProcAvailable(name)
	if C_Spell and type(C_Spell.IsSpellUsable)=="function" or type(IsUsableSpell)=="function" then
		return ArmsProcAvailable(name)
	end
	local usable=AL.SpellUsable(name)
	return SafeValue(usable) and usable==true
end

local function NextTank(s,inCombat,hostile)
	if not inCombat then
		if hostile then
			if ChargeAvailable() then return "Charge","verified tank Charge range + rage" end
			return AL.known.Attack and "Attack" or nil,"tank opener"
		end
		return nil,"Ready"
	end
	local rage=HamstringNumber(AL.Power(1))
	local hp,targetHP=HamstringNumber(AL.HealthPercent("player")),HamstringNumber(AL.HealthPercent("target"))
	local stance,shield=PlayerStance(),ShieldEquipped()
	local melee=hostile and VerifiedMelee(AL.TargetInMelee())
	furyDecision={at=GetTime(),actions={}}

	-- Survival is independent of Burst and still works without a target.
	if s.tankShieldWall and stance==2 and shield~=false then
		FuryOffer("Shield Wall","emergency defensive",rage,0,{
			FuryGate("health","player",hp,M.TankSetting(s,"tankShieldWallHP"),true,false,false)})
	end
	if s.tankLastStand and not FuryBurstActive("Shield Wall",12) then
		FuryOffer("Last Stand","emergency maximum health",rage,0,{
			FuryGate("health","player",hp,M.TankSetting(s,"tankLastStandHP"),true,false,false)})
	end
	if hostile then
		if s.tankAutoStance and stance and stance~=2 then
			FuryOffer("Defensive Stance","tank stance",rage,0)
		end
		if s.tankTaunt and stance==2 and TargetNeedsTaunt() then FuryOffer("Taunt","recover aggro",rage,0) end
		local minimum=SettingNumber(s,"aoeMinEnemies",2,2,5)
		local enemies=EnemyCountMelee(math.max(minimum,5))
		local aoe=s.aoe==true and enemies~=nil and enemies>=minimum
		if s.tankAoETaunt and aoe and TankLooseEnemies()>=3 then
			FuryOffer("Challenging Shout","recover 3+ enemies attacking allies",rage,5)
		end
		local slowSpell,slowReason=MaintainHamstring(s,rage,AL.TargetInMelee())
		if melee then
			local castingOK,casting=pcall(AL.TargetCasting or function()return false end)
			if s.tankInterrupt and castingOK and SafeValue(casting) and casting==true then
				if shield~=false and (stance==1 or stance==2) then FuryOffer("Shield Bash","interrupt",rage,10) end
				-- This talent is a stun fallback, not a damage filler or boss opener.
				local ok,classification=pcall(UnitClassification or function()end,"target")
				local levelOK,targetLevel=pcall(UnitLevel,"target")
				if s.tankConcussionBlow and ok and SafeValue(classification)
					and (classification=="normal" or classification=="rare" or classification=="elite" or classification=="rareelite")
					and levelOK and HamstringNumber(targetLevel) and targetLevel>0 then
					FuryOffer("Concussion Blow","interrupt with learned stun",rage,10)
				end
			end
			if s.victory and TankProcAvailable("Victory Rush") then FuryOffer("Victory Rush","tank self-heal",rage,0,{
				FuryGate("health","player",hp,65,true,false,false)}) end
			if s.tankShieldBlock and stance==2 and shield~=false then FuryOffer("Shield Block","block + revenge setup",rage,10) end
			if slowSpell then FuryOffer(slowSpell,slowReason,rage,10) end
			if s.shout and not BattleShoutActive() then FuryOffer("Battle Shout","maintain own attack-power buff",rage,10) end
			if AL.burst then
				local minimumHP=M.TankSetting(s,"tankBurstMinTargetHP")
				local gate=minimumHP==0 or FuryGate("health","target",targetHP,minimumHP,false,false,false)
				if s.tankBloodFury then FuryOffer("Blood Fury","Burst: racial attack power",rage,0,{gate}) end
				if s.tankBerserking then FuryOffer("Berserking","Burst: racial attack speed",rage,0,{gate}) end
			end
			if s.tankShieldSlam and shield~=false then FuryOffer("Shield Slam","Protection primary strike",rage,20) end
			if s.revenge and stance==2 and TankProcAvailable("Revenge") then FuryOffer("Revenge","usable block / dodge / parry proc",rage,5) end

			-- All damaging area actions are confined to the confirmed AoE branch.
			if aoe and s.tankThunderClap and (stance==1 or stance==2) then
				FuryOffer("Thunder Clap","Protection AoE damage + attack-speed slow",rage,20)
			end
			if not aoe and s.rend and (stance==1 or stance==2) and not RendActive() and ShouldRend(targetHP,TargetTTD()) then
				FuryOffer("Rend","protection single-target bleed",rage,10,{
					FuryGate("health","target",targetHP,REND_STOP_HP,false,true,true)})
			end
			if s.tankDemo and not DemoActive() then FuryOffer("Demoralizing Shout","physical mitigation",rage,10) end
			if s.sunder and TankSunderCap(s)>0 then
				local stacks=SunderStacks()
				if stacks<TankSunderCap(s) or sunderExpires>0 and sunderExpires-GetTime()<=5 then
					FuryOffer("Sunder Armor","maintain own armor stacks",rage,15)
				end
			end
			if s.victory and TankProcAvailable("Victory Rush") then FuryOffer("Victory Rush","free tank damage",rage,0) end
			if not StrikeQueued("Heroic Strike") and not StrikeQueued("Cleave") then
				if aoe then
					FuryOffer("Cleave","Protection AoE queued attack",rage,20,{
						FuryRageGate(rage,M.TankSetting(s,"tankCleaveDumpRage"),false,false,false)})
				elseif s.heroic then
					FuryOffer("Heroic Strike","Protection queued Rage dump",rage,15,{
						FuryRageGate(rage,M.TankSetting(s,"tankHeroicDumpRage"),false,false,false)})
				end
			end
		elseif slowSpell then FuryOffer(slowSpell,slowReason,rage,10) end
		if s.bloodrage then FuryOffer("Bloodrage","safe tank Rage generation",rage,0,{
			FuryRageGate(rage,20,true,true,false),FuryGate("health","player",hp,75,false,false,false)}) end
	end
	FuryAdd(hostile and AL.known.Attack and "Attack" or nil,hostile and "tank melee / pool rage" or "No target")
	local base=furyDecision.actions[#furyDecision.actions]
	furyDecision.baseSpell,furyDecision.baseReason=base.spell,base.reason
	return base.spell,base.reason
end

function M.NextSpell(s, inCombat, hostile)
    M.NormalizeBuild(s)
	furyDecision = nil
	if not inCombat then furyCurveFailures = {} end
	M.InitializeProtectionSettings(s)
	if WarriorRole(s) == "TANK" then
		return NextTank(s, inCombat, hostile)
	end
	if M.ArmsSelected(s) then return NextArms(s,inCombat,hostile) end
	if s.fury == true then return NextFury(s, inCombat, hostile) end
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
		cleaveDumpRage = M.ArmsSelected(profile) and SettingNumber(profile,"armsCleaveDumpRage",80,20,100)
			or profile.fury == true and WarriorRole(profile) == "DPS"
			and SettingNumber(profile, "furyCleaveDumpRage", 40, 20, 100)
			or SettingNumber(profile, "cleaveDumpRage", CLEAVE_DUMP_RAGE, 20, 100),
		slamReserveRage = M.ArmsSelected(profile) and SettingNumber(profile,"armsSlamReserveRage",15,15,100)
			or SettingNumber(profile, "slamReserveRage", SLAM_RESERVE_RAGE, 15, 100),
		sweepingReserveRage = SettingNumber(profile, "sweepingReserveRage", SWEEPING_RESERVE_RAGE, 30, 100),
		aoeMinEnemies = SettingNumber(profile, "aoeMinEnemies", 2, 2, 5),
		enemyCount7 = EnemyCountMelee(5),
		rageOverflowAt = RAGE_OVERFLOW_DUMP,
		sunderMaxStacks = SunderStackCap(profile),
		role = WarriorRole(profile),
		arms = M.ArmsSelected(profile),
		fury = profile.fury == true and WarriorRole(profile) == "DPS" and not M.ArmsSelected(profile),
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
		build = "0.10.4",
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


function M.OnTargetChanged()
    furyDecision, AL.rotationSecretVisual = nil, nil
end

function M.CanTrackSuggestedSpell(name)
    if furyDecision and furyDecision.visualCandidate then return false end
    return name ~= nil and Ok(name)
end

if AL.selfCastSpells then
    for _, name in ipairs({ "Berserker Rage", "Death Wish", "Recklessness", "Whirlwind", "Blood Fury", "Berserking",
		"Last Stand", "Shield Block", "Shield Wall", "Defensive Stance", "Challenging Shout" }) do
        AL.selfCastSpells[name] = true
    end
end

local function IntervalCurve(low, high)
	local key = tostring(low) .. ":" .. tostring(high)
	if furyVisibilityCurves[key] then return furyVisibilityCurves[key] end
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	curve:AddPoint(0, CreateColor(1, 1, 1, low == 0 and 1 or 0))
	if low > 0 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
	if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
	if low ~= 1 and high ~= 1 then curve:AddPoint(1, CreateColor(1, 1, 1, high > 1 and 1 or 0)) end
	furyVisibilityCurves[key] = curve
	return curve
end

function M.SecretVisualPlan(spell, reason)
	local d = furyDecision
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
				furyCurveFailures[mask.kind .. ":" .. mask.unit] = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent
				error("Fury resource curve unavailable")
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


AL.RegisterRotation("WARRIOR", M)
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
    root.RegisterRotation("WARRIOR", advanced)
end
