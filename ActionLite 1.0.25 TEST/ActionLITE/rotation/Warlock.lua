local ADDON, AL = ...

-- ActionLITE Warlock v0.20.3: original Leveling plus optional talent builds.

-- Leveling keeps the finalized pre-simulation implementation in its own
-- scope. Talent builds use the separate implementation below. Both observe
-- real casts so switching rotations retains resource and spell history.
do
    local root = AL
    local leveling, advanced
    local function UsesLeveling(profile)
        profile = profile or (root.Profile and root.Profile("WARLOCK")) or (root.S and root.S())
        if advanced and type(profile) == "table" then
            return advanced.NormalizeBuild(profile) == "leveling"
        end
        return true
    end
    local function RotationScope(isLeveling)
        local scope = {
            RegisterRotation = function(token, module)
                assert(token == "WARLOCK", "Unexpected class rotation")
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
                    if root.playerClass == "WARLOCK" and UsesLeveling() == isLeveling then root[key] = value end
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
-- BEGIN ORIGINAL LEVELING IMPLEMENTATION (Warlock(20261005-010754).Lua)
local ADDON, AL = ...

-- Affliction leveling priority per the WoW Forever guide (levels 1-30)
local M = {
	defaults = {
		armor = true, pet = true, immolate = true, agony = true,
		curseElements = false, curseWeakness = false, curseRecklessness = false, curseTongues = false,
		lifetap = true, lifeTapMana = 25, shootMana = 25, drainsoul = true, fear = true, drink = true,
		healthfunnel = true, healthFunnelPetHP = 40, healthFunnelMinPlayerHP = 60,
		drainSoulMinShards = 1,
	},
}

M.spells = {
	{ 980, "Bane of Agony" },
	{ 710, "Banish" },
	{ 172, "Corruption" },
	{ 6201, "Create Healthstone" },
	{ 693, "Create Soulstone" },
	{ 0, "Curse of Agony" }, -- Legacy name fallback; Forever uses Bane of Agony.
	{ 440892, "Curse of the Elements" },
	{ 704, "Curse of Recklessness" },
	{ 1714, "Curse of Tongues" },
	{ 702, "Curse of Weakness" },
	{ 706, "Demon Armor" },
	{ 687, "Demon Skin" },
	{ 132, "Detect Lesser Invisibility" },
	{ 689, "Drain Life" },
	{ 5138, "Drain Mana" },
	{ 1120, "Drain Soul" },
	{ 1098, "Enslave Demon" },
	{ 126, "Eye of Kilrogg" },
	{ 5782, "Fear" },
	{ 755, "Health Funnel" },
	{ 348, "Immolate" },
	{ 1454, "Life Tap" },
	{ 5740, "Rain of Fire" },
	{ 698, "Ritual of Summoning" },
	{ 5500, "Sense Demons" },
	{ 5019, "Shoot" },
	{ 686, "Shadow Bolt" },
	{ 18265, "Siphon Life" },
	{ 688, "Summon Imp" },
	{ 712, "Summon Succubus" },
	{ 697, "Summon Voidwalker" },
	{ 5697, "Unending Breath" },
}

local SOUL_SHARD = { 6265 }

-- Read the actual bag count for Soul Shards.
--
-- Forever can protect GetItemCount(), so use a layered detector:
--   1. GetItemCount(6265)
--   2. Direct bag-slot scan through legacy container APIs
--   3. Direct bag-slot scan through C_Container APIs
--
-- Return count, source.  nil means every readable inventory path was blocked.
local SOUL_SHARD_ID = 6265

local function ReadableNumber(v)
	if type(v) ~= "number" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	if v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end

local function ReadableString(v)
	if type(v) ~= "string" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h, i, j = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e, f, g, h, i, j
end

local function ContainerNumSlots(bag)
	local n
	if type(GetContainerNumSlots) == "function" then
		n = ReadableNumber((SafeCall(GetContainerNumSlots, bag)))
		if n ~= nil then return n, "legacy" end
	end
	if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
		n = ReadableNumber((SafeCall(C_Container.GetContainerNumSlots, bag)))
		if n ~= nil then return n, "C_Container" end
	end
end

local function ContainerItemID(bag, slot)
	local id
	if type(GetContainerItemID) == "function" then
		id = ReadableNumber((SafeCall(GetContainerItemID, bag, slot)))
		if id ~= nil then return id end
	end
	if C_Container and type(C_Container.GetContainerItemID) == "function" then
		id = ReadableNumber((SafeCall(C_Container.GetContainerItemID, bag, slot)))
		if id ~= nil then return id end
	end

	-- Fallback: parse the item ID out of a readable item link.
	local link
	if type(GetContainerItemLink) == "function" then
		link = ReadableString((SafeCall(GetContainerItemLink, bag, slot)))
	end
	if not link and C_Container and type(C_Container.GetContainerItemLink) == "function" then
		link = ReadableString((SafeCall(C_Container.GetContainerItemLink, bag, slot)))
	end
	if link then
		return tonumber(link:match("item:(%d+)"))
	end

	-- Newer C_Container can return itemID inside the info table.
	if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
		local info = SafeCall(C_Container.GetContainerItemInfo, bag, slot)
		if type(info) == "table" then
			id = ReadableNumber(info.itemID)
			if id ~= nil then return id end
		end
	end
end

local function ContainerStackCount(bag, slot)
	-- Modern API.
	if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
		local info = SafeCall(C_Container.GetContainerItemInfo, bag, slot)
		if type(info) == "table" then
			local n = ReadableNumber(info.stackCount or info.count)
			if n ~= nil then return n end
		end
	end

	-- Legacy API: second return value is stack count.
	if type(GetContainerItemInfo) == "function" then
		local _, count = SafeCall(GetContainerItemInfo, bag, slot)
		count = ReadableNumber(count)
		if count ~= nil then return count end
	end
end

local function SoulShardsFromBagSlots()
	local total = 0
	local readableBag = false

	-- 0 = backpack, 1-4 = equipped bags, 5 is harmless on clients that expose
	-- an extra container and simply reports zero/nil elsewhere.
	for bag = 0, 5 do
		local slots = ContainerNumSlots(bag)
		if slots ~= nil then
			readableBag = true
			for slot = 1, slots do
				local id = ContainerItemID(bag, slot)
				if id == SOUL_SHARD_ID then
					local stack = ContainerStackCount(bag, slot)
					-- Soul Shards are normally one per slot on this ruleset.
					-- If stack size is readable, honor it; otherwise count the
					-- confirmed matching slot as one shard.
					total = total + (stack and math.max(1, stack) or 1)
				end
			end
		end
	end

	if readableBag then
		return total
	end
end

local function SoulShardCount()
	-- Fast path.
	if type(GetItemCount) == "function" then
		local count = ReadableNumber((SafeCall(GetItemCount, SOUL_SHARD_ID)))
		if count ~= nil then
			return count, "GetItemCount"
		end
	end

	-- Forever fallback.
	local count = SoulShardsFromBagSlots()
	if count ~= nil then
		return count, "bag scan"
	end

	return nil, "unreadable"
end

-- Expose the exact detector to the Warlock UI for live diagnostics.
M.SoulShardCount = SoulShardCount

local function AgonySpell()
	if AL.Ok("Bane of Agony") then return "Bane of Agony" end
	if AL.Ok("Curse of Agony") then return "Curse of Agony" end
end

-- Le DoT en cours d'incantation compte comme pose : l'icone passe au suivant.
local function DotUp(name, casting)
	local timer = AL.targetDebuffs and AL.targetDebuffs[name]
	return casting == name
		or (timer and (not timer.expires or timer.expires > GetTime()))
		or AL.HasDebuff("target", name)
end

local function AgonyOnTarget(casting)
	return DotUp("Bane of Agony", casting) or DotUp("Curse of Agony", casting)
end

local function BestArmor()
	if AL.Ok("Demon Armor") then return "Demon Armor" end
	if AL.Ok("Demon Skin") then return "Demon Skin" end
end

-- Return the readable spell name currently being cast/channelled by the player.
-- While Immolate is still in flight, its debuff has not landed yet, so without
-- this check the rotation would continue recommending Immolate every refresh.
-- Sort lisible en cours (incantation ou canalisation), sinon celui que Core connait par UNIT_SPELLCAST_START.
local function PlayerCastingSpell()
	if UnitCastingInfo then
		local ok, name = pcall(UnitCastingInfo, "player")
		if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
			return (AL.englishNames and AL.englishNames[name]) or name
		end
	end
	if UnitChannelInfo then
		local ok, name = pcall(UnitChannelInfo, "player")
		if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
			return (AL.englishNames and AL.englishNames[name]) or name
		end
	end
	return AL.CastingSpell and AL.CastingSpell() or nil
end

-- Health Funnel is only suggested when movement is positively readable as zero.
local function PlayerStationary()
	if type(GetUnitSpeed) ~= "function" then return false end
	local ok, speed = pcall(GetUnitSpeed, "player")
	if not ok or (issecretvalue and issecretvalue(speed)) or type(speed) ~= "number" then
		return false
	end
	return speed == 0
end

-- Movement is only considered true when Forever gives us a readable speed
-- greater than zero. If the value is protected/unknown, do not guess.
local function PlayerMoving()
	if type(GetUnitSpeed) ~= "function" then return false end
	local ok, speed = pcall(GetUnitSpeed, "player")
	if not ok or (issecretvalue and issecretvalue(speed)) or type(speed) ~= "number" then
		return false
	end
	return speed > 0
end

-- Pure Soul Shard comparison. This intentionally does NOT check movement,
-- spell usability, casting state, or target health. A shard deficit is simply:
-- detected bag count < configured minimum.
local function SoulShardDeficit(s)
	-- A new character cannot build shards before Drain Soul is learned.
	if not s.drainsoul or not AL.Ok("Drain Soul") then return false end

	local shards = SoulShardCount()
	if shards == nil then return false end

	local minimumShards = math.max(1, math.floor(tonumber(s.drainSoulMinShards) or 1))
	if shards >= minimumShards then
		return false, shards, minimumShards
	end

	return true, shards, minimumShards
end

-- After the initial DoT package, a readable shard deficit owns the filler slot.
-- Known movement is handled earlier by the Shoot override. If movement is
-- unreadable, do not let that uncertainty re-enable Shadow Bolt.
local function ForcedDrainSoul(s)
	local deficit, shards, minimumShards = SoulShardDeficit(s)
	if not deficit then return false, shards, minimumShards end

	if AL.Ok("Drain Soul") then
		return true, shards, minimumShards
	end

	-- Still return the deficit separately to callers so Shadow Bolt remains
	-- blocked even if the spellbook detector temporarily cannot confirm Drain Soul.
	return false, shards, minimumShards, true
end

-- Readable mana wins. When Forever protects it, maintain an estimate from
-- learned-rank spell costs, successful casts, Life Tap and mana regeneration.
-- The maximum-mana bootstrap assumes a full pool at login/reload; it is never
-- repeated just because combat ends or the target changes.
local manaTracker = {
	updatedAt = GetTime(), lastSpend = -math.huge, processed = {},
}
local manaCosts, tapGains = {}, {}

local function ManaMaximum()
	local maximum = ReadableNumber((SafeCall(UnitPowerMax, "player", 0)))
	return maximum and maximum > 0 and maximum or manaTracker.maximum
end

local function NormalizePercent(value, minimum, maximum)
	value, minimum, maximum = ReadableNumber(value), ReadableNumber(minimum), ReadableNumber(maximum)
	if value == nil or minimum == nil or maximum == nil then return nil end
	if maximum <= minimum or value < minimum or value > maximum then return nil end
	return (value - minimum) / (maximum - minimum) * 100
end

local function ManaFromStatusBar(bar)
	if not bar or type(bar.GetValue) ~= "function" or type(bar.GetMinMaxValues) ~= "function" then return nil end
	local value = SafeCall(bar.GetValue, bar)
	local minimum, maximum = SafeCall(bar.GetMinMaxValues, bar)
	return NormalizePercent(value, minimum, maximum)
end

local function ManaFromFontString(fontString, knownMaximum)
	if not fontString or type(fontString.GetText) ~= "function" then return nil end
	local text = ReadableString((SafeCall(fontString.GetText, fontString)))
	if not text then return nil end
	text = text:gsub(",", "")
	local current, maximum = text:match("(%d+)%s*/%s*(%d+)")
	current, maximum = tonumber(current), tonumber(maximum)
	if current and maximum then return NormalizePercent(current, 0, maximum) end
	local percent = tonumber(text:match("(%d+%.?%d*)%s*%%"))
	if percent then return NormalizePercent(percent, 0, 100) end
	current = tonumber(text:match("^%s*(%d+)%s*$"))
	if current and knownMaximum then return NormalizePercent(current, 0, knownMaximum) end
end

local function ReadManaPercent(maximum)
	local current = ReadableNumber((SafeCall(UnitPower, "player", 0)))
	local pct = current and maximum and NormalizePercent(current, 0, maximum)
	if pct then return pct, "UnitPower" end
	pct = ManaFromStatusBar(_G.PlayerFrameManaBar)
	if pct then return pct, "player mana bar" end
	local frame = _G.PlayerFrame
	local content = frame and frame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local area = main and main.ManaBarArea
	pct = ManaFromStatusBar(area and area.ManaBar)
	if pct then return pct, "nested mana bar" end
	pct = ReadableNumber((SafeCall(AL.ManaPercent)))
	if pct and pct >= 0 and pct <= 100 then return pct, "Core mana" end
	pct = ManaFromFontString(_G.PlayerFrameManaBarText, maximum)
	if pct then return pct, "mana text" end
	local right = _G.PlayerFrameManaBarTextRight
	local rightText = right and ReadableString((SafeCall(right.GetText, right)))
	local textMax = rightText and tonumber(rightText:gsub(",", ""):match("(%d+)"))
	pct = ManaFromFontString(_G.PlayerFrameManaBarTextLeft, textMax or maximum)
	if pct then return pct, "mana text" end
end

local function RefreshManaRegen()
	local base, casting = SafeCall(GetManaRegen)
	base, casting = ReadableNumber(base), ReadableNumber(casting)
	if base and base >= 0 then manaTracker.baseRegen = base end
	if casting and casting >= 0 then manaTracker.castingRegen = casting end
end

local function UpdateMana()
	local now = GetTime()
	RefreshManaRegen()
	if manaTracker.amount and manaTracker.maximum then
		local from = manaTracker.updatedAt
		local dt = math.max(0, now - from)
		-- Five-second rule: split an interval that crosses the recovery boundary.
		local reduced = math.max(0, math.min(now, manaTracker.lastSpend + 5) - from)
		reduced = math.min(dt, reduced)
		local regen = reduced * (manaTracker.castingRegen or 0)
			+ (dt - reduced) * (manaTracker.baseRegen or 0)
		manaTracker.amount = math.min(manaTracker.maximum, manaTracker.amount + regen)
	end
	manaTracker.updatedAt = now
	local maximum = ManaMaximum()
	if maximum then
		manaTracker.maximum = maximum
		if manaTracker.amount then manaTracker.amount = math.min(maximum, manaTracker.amount) end
	end
	local pct = ReadManaPercent(maximum)
	manaTracker.readable = pct ~= nil
	if pct ~= nil then
		if maximum then manaTracker.amount = maximum * pct / 100 end
	elseif manaTracker.amount == nil and maximum then
		manaTracker.amount = maximum
	end
	if pct ~= nil then return pct end
	if manaTracker.amount and maximum then return manaTracker.amount / maximum * 100 end
end

local function ManaSpellID(name, spellID)
	spellID = ReadableNumber(spellID)
	if spellID and spellID > 0 then return spellID end
	local ref = name and AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	local learned = ref and ReadableNumber(ref.id)
	if learned and learned > 0 then return learned end
	-- Names resolve the current learned rank; a declared base ID might be rank 1.
	return name and ((AL.localNames and AL.localNames[name]) or name)
end

local function ReadManaCost(identifier)
	local fn = C_Spell and C_Spell.GetSpellPowerCost or GetSpellPowerCost
	local costs = identifier and SafeCall(fn, identifier)
	if type(costs) ~= "table" or (issecretvalue and issecretvalue(costs)) then return nil end
	local total = 0
	for _, info in ipairs(costs) do
		if type(info) ~= "table" or (issecretvalue and issecretvalue(info)) then return nil end
		local powerType, token = ReadableNumber(info.type), ReadableString(info.name)
		if powerType == nil and token == nil then return nil end
		if powerType == 0 or token == "MANA" then
			local required = ReadableNumber(info.requiredAuraID)
			if issecretvalue and issecretvalue(info.requiredAuraID) then return nil end
			local active = true
			if required and required > 0 then
				local hasAura = info.hasRequiredAura
				if (issecretvalue and issecretvalue(hasAura)) or type(hasAura) ~= "boolean" then return nil end
				active = hasAura
			end
			if active then
				local cost = ReadableNumber(info.cost)
				if cost == nil or cost < 0 then return nil end
				total = total + cost
			end
		end
	end
	return total
end

local function SpellManaCost(name, spellID)
	local identifier = ManaSpellID(name, spellID)
	local cost = ReadManaCost(identifier)
	if cost ~= nil then
		manaCosts[identifier] = cost
		return cost, identifier, "spell power cost"
	end
	if identifier and manaCosts[identifier] ~= nil then return manaCosts[identifier], identifier, "cached spell power cost" end
	if name == "Shoot" or name == "Attack" or name == "Life Tap" then return 0, identifier, "no mana cost" end
	return nil, identifier, "unavailable"
end

local function LifeTapGain(name, spellID)
	if name ~= "Life Tap" then return 0, "not Life Tap" end
	local identifier = ManaSpellID(name, spellID)
	local fn = C_Spell and C_Spell.GetSpellDescription or GetSpellDescription
	local text = identifier and ReadableString((SafeCall(fn, identifier)))
	if text then
		-- Keep the live rank's amount, rather than treating Life Tap as a free cast.
		text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub(",", ""):lower()
		local gain = tonumber(text:match("(%d+%.?%d*)%s+mana"))
		if gain and gain > 0 then tapGains[identifier] = gain; return gain, "spell description" end
	end
	if identifier and tapGains[identifier] then return tapGains[identifier], "cached spell description" end
	return nil, "unavailable"
end

function M.RefreshManaCache()
	UpdateMana()
	for name, ref in pairs(AL.rangeSpellRefs or {}) do
		local english = (AL.englishNames and AL.englishNames[name]) or name
		SpellManaCost(english, ref.id)
		if english == "Life Tap" then LifeTapGain(english, ref.id) end
	end
end

function M.OnManaCastSent(name, spellID)
	UpdateMana()
	local cost, identifier = SpellManaCost(name, spellID)
	local gain = LifeTapGain(name, spellID)
	return { name = name, id = identifier, cost = cost, gain = gain }
end

function M.OnManaCastSucceeded(name, spellID, castGUID, pending)
	local now = GetTime()
	for guid, at in pairs(manaTracker.processed) do
		if now - at >= 60 then manaTracker.processed[guid] = nil end
	end
	if castGUID and manaTracker.processed[castGUID] then return end
	if castGUID then manaTracker.processed[castGUID] = now end
	if pending and pending.manaApplied then return end
	if pending then pending.manaApplied = true end
	local saved = pending and pending.mana
	local identifier = ManaSpellID(name, spellID)
	local cost, gain
	if saved and saved.name == name and saved.id == identifier then
		cost, gain = saved.cost, saved.gain
	end
	if cost == nil then cost = SpellManaCost(name, spellID) end
	if gain == nil then gain = LifeTapGain(name, spellID) end
	UpdateMana()
	if not manaTracker.readable and manaTracker.amount then
		manaTracker.amount = math.max(0, math.min(manaTracker.maximum,
			manaTracker.amount - (cost or 0) + (gain or 0)))
	end
	if cost and cost > 0 then manaTracker.lastSpend = now end
end

local function WarlockManaPercent() return UpdateMana() end

-- Preserve a minimum mana reserve even when the Shoot slider is set lower.
local HARD_SHOOT_MANA = 10

local function ShootThreshold(s)
	local configured = math.max(0, math.min(100, tonumber(s.shootMana) or 25))
	return math.max(HARD_SHOOT_MANA, configured), configured
end

local function ShadowBoltOutOfMana()
	local fn = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
	local usable, noMana = SafeCall(fn, ManaSpellID("Shadow Bolt"))
	if issecretvalue and (issecretvalue(usable) or issecretvalue(noMana)) then return false end
	return usable == false and noMana == true
end

local function ShootState(s, manaPct)
	local threshold, configured = ShootThreshold(s)
	-- The wand reserve must not disable usable spells without a wand.
	if not AL.WandEquipped() then
		return false, manaPct, threshold, configured, "no wand equipped"
	end
	if type(manaPct) ~= "number" then return true, manaPct, threshold, configured, "mana unavailable" end
	if manaPct <= HARD_SHOOT_MANA then
		return true, manaPct, threshold, configured, "Shoot protection: mana <= " .. tostring(HARD_SHOOT_MANA) .. "%"
	end
	if manaPct <= threshold then
		return true, manaPct, threshold, configured, "Shoot mana " .. tostring(math.floor(manaPct + 0.5)) .. "% <= " .. tostring(configured) .. "%"
	end
	if ShadowBoltOutOfMana() then return true, manaPct, threshold, configured, "Shadow Bolt out of mana" end
	return false, manaPct, threshold, configured, nil
end

-- Curses share one slot; Bane of Agony has its own slot on Forever.
-- Select ONE checked, learned/enabled curse before checking its aura. If more
-- than one is checked, this stable order prevents curses replacing each other
-- every frame. An unusable selected curse does not trigger a different curse.
local CURSE_CHOICES = {
	{ key = "curseElements", spell = "Curse of the Elements" },
	{ key = "curseWeakness", spell = "Curse of Weakness" },
	{ key = "curseRecklessness", spell = "Curse of Recklessness" },
	{ key = "curseTongues", spell = "Curse of Tongues" },
}

function M.SelectedCurse(s)
	for _, choice in ipairs(CURSE_CHOICES) do
		if s[choice.key] and AL.Ok(choice.spell) then
			return choice.spell
		end
	end
end

-- Une seule malediction utilitaire suffit pour cette cible. Le sort vraiment
-- lance peut differer de la selection (raccourci/macro ou changement de profil).
-- Ne pas rester bloque en attendant un autre nom, ni remplacer la malediction
-- deja posee. Bane of Agony ne fait pas partie de ce groupe.
function M.ActiveCurse(casting)
	local now = GetTime()
	for _, choice in ipairs(CURSE_CHOICES) do
		local name = choice.spell
		local timer = AL.targetDebuffs and AL.targetDebuffs[name]
		if casting == name
			or (timer and (not timer.expires or timer.expires > now))
			or AL.HasDebuff("target", name)
		then
			return name
		end
	end
end

local function NextCurse(s, casting)
	local curse = M.SelectedCurse(s)
	if not curse then return nil end
	-- Core enregistre le succes immediatement, meme si les auras sont bloquees.
	-- Toute malediction utilitaire active termine cette phase : passer aux DoT.
	if M.ActiveCurse(casting) then return nil end
	if AL.SpellUsable(curse) then
		return curse, "selected curse"
	end
end

-- DoT autorises pour le repli LIKELY de Core lorsque l'identite est secrete.
-- Un succes de lancement reste obligatoire ; aucune simple suggestion ne
-- doit creer un timer. Les curses utilisent SelectedCurse separement.
local TRACKED_DOT_SETTINGS = {
	["Immolate"] = "immolate", ["Corruption"] = true,
	["Bane of Agony"] = "agony", ["Curse of Agony"] = "agony",
	["Siphon Life"] = true,
}

function M.CanTrackSuggestedDebuff(name, s)
	local setting = TRACKED_DOT_SETTINGS[name]
	return setting and (setting == true or s[setting]) and AL.Ok(name) or false
end

-- Mana-only recommendation fallback also covers filler, Life Tap and buffs.
-- Core still requires a matching successful cast before accounting for it.
function M.CanTrackSuggestedSpell(name, s)
	for _, choice in ipairs(CURSE_CHOICES) do
		if choice.spell == name then return M.SelectedCurse(s) == name end
	end
	if TRACKED_DOT_SETTINGS[name] then return M.CanTrackSuggestedDebuff(name, s) end
	for _, entry in ipairs(M.spells) do
		if entry[2] == name then return AL.Ok(name) end
	end
	return false
end

-- Any DoT that is CURRENTLY being cast is treated as committed even though
-- its debuff cannot appear on the target until the cast finishes.
--
-- This keeps the recommendation moving forward:
--   Immolate -> Corruption -> Agony -> Siphon Life -> Drain Soul (if needed) -> Shoot (low mana) / Shadow Bolt
local function AfterCastingDot(casting, s, targetHp)
	local stage
	if casting == "Immolate" then
		stage = 1
	elseif casting == "Corruption" then
		stage = 2
	elseif casting == "Bane of Agony" or casting == "Curse of Agony" then
		stage = 3
	elseif casting == "Siphon Life" then
		stage = 4
	else
		return nil
	end

	-- After Immolate, Corruption is next.
	if stage < 2
		and AL.Ok("Corruption")
		and not DotUp("Corruption", casting)
		and (not targetHp or targetHp > 30)
		and AL.SpellUsable("Corruption")
	then
		return "Corruption", "queued after " .. casting
	end

	-- After Immolate/Corruption, Agony is next.
	if stage < 3 then
		local agony = AgonySpell()
		if s.agony
			and agony
			and not AgonyOnTarget(casting)
			and (not targetHp or targetHp > 40)
			and AL.SpellUsable(agony)
		then
			return agony, "queued after " .. casting
		end
	end

	-- After the earlier DoTs, Siphon Life is next when learned.
	if stage < 4
		and AL.Ok("Siphon Life")
		and not DotUp("Siphon Life", casting)
		and (not targetHp or targetHp > 40)
		and AL.SpellUsable("Siphon Life")
	then
		return "Siphon Life", "queued after " .. casting
	end

	-- Once the DoTs ahead of us are handled, the shard comparison is absolute:
	-- below the configured minimum means Drain Soul, never Shadow Bolt.
	local deficit, shards, minimumShards = SoulShardDeficit(s)
	if deficit then
		if AL.Ok("Drain Soul") then
			return "Drain Soul", "Soul Shards " .. tostring(shards) .. "/" .. tostring(minimumShards)
		end
		return nil, "Soul Shard deficit " .. tostring(shards) .. "/" .. tostring(minimumShards)
	end

	local manaPct = WarlockManaPercent()
	local forceShoot, _, _, _, shootReason = ShootState(s, manaPct)
	if forceShoot then
		if AL.WandEquipped() and AL.Ok("Shoot") then
			return "Shoot", shootReason or "Shoot mode"
		end
		return nil, "Shadow Bolt blocked: " .. tostring(shootReason or "Shoot mode")
	end

	-- With a wand equipped, Shadow Bolt requires mana above its threshold.
	-- Without one, native spell usability remains the authority.
	if AL.Ok("Shadow Bolt") and AL.SpellUsable("Shadow Bolt") then
		return "Shadow Bolt", "queued after " .. casting
	end
	if AL.WandEquipped() and AL.Ok("Shoot") then
		return "Shoot", "Shadow Bolt unavailable"
	end
end

local function NextDot(s, casting, targetHp)
	local curse, curseReason = NextCurse(s, casting)
	if curse then return curse, curseReason end
	if s.immolate and AL.Ok("Immolate") and not DotUp("Immolate", casting)
		and (not targetHp or targetHp > 50)
		and AL.SpellUsable("Immolate")
	then
		return "Immolate", "dot"
	end
	if AL.Ok("Corruption") and not DotUp("Corruption", casting)
		and (not targetHp or targetHp > 30)
		and AL.SpellUsable("Corruption")
	then
		return "Corruption", "dot"
	end
	local agony = AgonySpell()
	if s.agony and agony and not AgonyOnTarget(casting)
		and (not targetHp or targetHp > 40)
		and AL.SpellUsable(agony)
	then
		return agony, "dot"
	end
	if AL.Ok("Siphon Life") and not DotUp("Siphon Life", casting)
		and (not targetHp or targetHp > 40)
		and AL.SpellUsable("Siphon Life")
	then
		return "Siphon Life", "dot"
	end
end

function M.NextSpell(s, inCombat, hostile)
	local myHp = AL.HealthPercent("player")
	local manaPct = WarlockManaPercent()
	local petUp = UnitExists("pet") and not UnitIsDeadOrGhost("pet")
	local petHp = petUp and AL.HealthPercent("pet") or nil
	local targetHp = hostile and AL.HealthPercent("target") or nil
	local casting = PlayerCastingSpell()
	local lifeTapMana = tonumber(s.lifeTapMana) or 25
	local shootMana = tonumber(s.shootMana) or 25
	local forceShoot, readableShootMana, effectiveShootThreshold, configuredShootMana, shootReason =
		ShootState(s, manaPct)

	-- Core normally intercepts every active channel and returns the global
	-- no-action/pooling state before this rotation runs. Keep this local fallback
	-- for Warlock in case the class function is called directly.
	if casting == "Health Funnel" or casting == "Drain Soul"
		or casting == "Drain Life" or casting == "Drain Mana"
		or casting == "Rain of Fire"
	then
		return nil, "Channeling"
	end

	-- Pet recovery: learned/enabled, pet below threshold, player safely above
	-- threshold, and player confirmed stationary.
	local funnelPetHP = tonumber(s.healthFunnelPetHP) or 40
	local funnelPlayerHP = tonumber(s.healthFunnelMinPlayerHP) or 60
	if s.healthfunnel
		and petUp
		and petHp and petHp < funnelPetHP
		and myHp and myHp > funnelPlayerHP
		and PlayerStationary()
		and AL.Ok("Health Funnel")
		and AL.SpellUsable("Health Funnel")
	then
		return "Health Funnel", "pet below " .. tostring(funnelPetHP) .. "%"
	end

	if not inCombat then
		if s.armor then
			local armor = BestArmor()
			if armor and not AL.HasBuff("player", "Demon Armor") and not AL.HasBuff("player", "Demon Skin") then
				return armor, "buff"
			end
		end
		if s.pet and not petUp then
			local shards = AL.ItemCount(SOUL_SHARD)
			if AL.Ok("Summon Voidwalker") and (not shards or shards > 0) then
				return "Summon Voidwalker", "pet"
			end
			if AL.Ok("Summon Imp") then return "Summon Imp", "pet" end
		end
		-- Life Tap out of combat uses the same configured mana threshold.
		-- Keep the higher OOC health safety margin before trading HP for mana.
		if s.lifetap and manaPct and manaPct < lifeTapMana
			and myHp and myHp > 80
			and AL.Ok("Life Tap")
		then
			return "Life Tap", "mana below " .. tostring(lifeTapMana) .. "%"
		end
		if s.drink then
			if manaPct and manaPct < 30 then return nil, "Drink" end
		end
		if hostile then
			local curse, curseReason = NextCurse(s, casting)
			if curse then return curse, curseReason end
			-- A DoT being cast is already committed even though its debuff has not
			-- landed yet. Advance the icon to the next priority immediately.
			local nextSpell, reason = AfterCastingDot(casting, s, targetHp)
			if nextSpell then return nextSpell, reason end

			local dot, dotReason = NextDot(s, casting, targetHp)
			if dot then return dot, dotReason end

			-- Never use Shadow Bolt as an opener while the readable Soul Shard
			-- count is below the configured minimum.
			local deficit, shards, minimumShards = SoulShardDeficit(s)
			if deficit then
				if AL.Ok("Drain Soul") then
					return "Drain Soul", "Soul Shards " .. tostring(shards) .. "/" .. tostring(minimumShards)
				end
				return nil, "Soul Shard deficit " .. tostring(shards) .. "/" .. tostring(minimumShards)
			end

			local openerForceShoot, _, _, _, openerShootReason = ShootState(s, manaPct)
			if openerForceShoot then
				if AL.WandEquipped() and AL.Ok("Shoot") then
					return "Shoot", openerShootReason or "Shoot opener"
				end
				return nil, "Shadow Bolt blocked: " .. tostring(openerShootReason or "mana")
			end

			if AL.Ok("Shadow Bolt") and AL.SpellUsable("Shadow Bolt") then
				return "Shadow Bolt", "opener"
			end
			if AL.WandEquipped() and AL.Ok("Shoot") then
				return "Shoot", "Shadow Bolt unavailable"
			end
			return nil, "opener"
		end
		return nil, "Ready"
	end

	if not hostile then return nil, "No target" end

	-- In-combat movement override. While the player is positively detected as
	-- moving, recommend wand Shoot instead of cast-time/channel priorities.
	-- Core's global channel pool happens before this rotation, so an active
	-- channel still remains protected and cannot be replaced by Shoot.
	if PlayerMoving()
		and AL.WandEquipped()
		and AL.Ok("Shoot")
	then
		return "Shoot", "moving"
	end

	if s.fear and casting ~= "Fear" and AL.Ok("Fear")
		and AL.TargetInMelee() and myHp and myHp < 45
		and not DotUp("Fear", casting)
	then
		return "Fear", "create space"
	end
	if AL.burst then
		if AL.OkReady("Blood Fury") then return "Blood Fury", "burst" end
		if AL.OkReady("Berserking") then return "Berserking", "burst" end
	end

	local curse, curseReason = NextCurse(s, casting)
	if curse then return curse, curseReason end

	-- If any maintained DoT is already being cast, move the recommendation to
	-- the next priority instead of showing the same DoT a second time.
	do
		local nextSpell, reason = AfterCastingDot(casting, s, targetHp)
		if nextSpell then return nextSpell, reason end
	end

	local dot, dotReason = NextDot(s, casting, targetHp)
	if dot then return dot, dotReason end

	-- Soul Shard builder comes after the maintained DoT package. The bag-count
	-- comparison is the authority: if detected shards are below the slider value,
	-- Drain Soul replaces every normal filler, including Shadow Bolt.
	do
		local deficit, shards, minimumShards = SoulShardDeficit(s)
		if deficit then
			if AL.Ok("Drain Soul") then
				return "Drain Soul", "Soul Shards " .. tostring(shards) .. "/" .. tostring(minimumShards)
			end
			-- Important: do not fall through to Shadow Bolt if the shard deficit is
			-- known but Drain Soul cannot currently be confirmed by the spellbook.
			return nil, "Soul Shard deficit " .. tostring(shards) .. "/" .. tostring(minimumShards)
		end
	end
	-- HARD SHOOT STATE:
	-- DoTs and Drain Soul are above this point. Once filler is reached, Shoot
	-- completely replaces Shadow Bolt whenever mana is at/below the slider,
	-- at/below the hard 10% floor, unreadable, or Shadow Bolt reports no mana.
	-- This reserve applies only while a wand is equipped.
	if forceShoot then
		if AL.WandEquipped() and AL.Ok("Shoot") then
			return "Shoot", shootReason or "Shoot mode"
		end
		return nil, "Shadow Bolt blocked: " .. tostring(shootReason or "Shoot mode")
	end

	-- Life Tap remains independent, but only after ShootState has positively
	-- established that mana is above the Shoot threshold.
	if s.lifetap and manaPct and manaPct < lifeTapMana
		and myHp and myHp > 60
		and AL.Ok("Life Tap")
	then
		return "Life Tap", "mana below " .. tostring(lifeTapMana) .. "%"
	end

	if myHp and myHp < 70 and AL.Ok("Drain Life") and AL.SpellUsable("Drain Life") then
		return "Drain Life", "sustain"
	end

	-- Absolute final interlock immediately before Shadow Bolt. Re-read mana so
	-- no earlier stale value can authorize the filler.
	do
		local finalMana = WarlockManaPercent()
		local blockShadow, _, _, _, finalReason = ShootState(s, finalMana)
		if blockShadow then
			if AL.WandEquipped() and AL.Ok("Shoot") then
				return "Shoot", finalReason or "Shoot mode"
			end
			return nil, "Shadow Bolt blocked: " .. tostring(finalReason or "Shoot mode")
		end
	end

	if AL.Ok("Shadow Bolt") and AL.SpellUsable("Shadow Bolt") then
		return "Shadow Bolt", "filler"
	end

	-- Original unconditional wand fallback: if normal filler cannot be used for
	-- any reason, show Shoot regardless of the slider.
	if AL.WandEquipped() and AL.Ok("Shoot") then
		return "Shoot", "Shadow Bolt unavailable"
	end

	return AL.known["Attack"] and "Attack" or nil, "melee"
end

function M.BuildOptions(page, ui)
	local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h:SetPoint("TOP", 0, -30)
	h:SetText("Rotation hints:")
	ui.SettingCheck(page, 70, -52, "Demon Armor upkeep", "armor")
	ui.SettingCheck(page, 70, -78, "Summon pet", "pet")
	ui.SettingCheck(page, 70, -104, "Immolate", "immolate")
	ui.SettingCheck(page, 70, -130, "Bane/Curse of Agony", "agony")
	ui.SettingCheck(page, 290, -52, "Life Tap", "lifetap")
	ui.SettingCheck(page, 290, -78, "Drain Soul for Soul Shard", "drainsoul")
	ui.SettingCheck(page, 290, -104, "Fear at melee", "fear")
	ui.SettingCheck(page, 290, -130, "Drink reminder", "drink")
end

AL.RegisterRotation("WARLOCK", M)
-- END ORIGINAL LEVELING IMPLEMENTATION
    end)(ADDON, RotationScope(true))

    ;(function(...)
-- BEGIN OPTIONAL TALENT BUILD IMPLEMENTATION
local ADDON, AL = ...

-- ActionLITE Warlock v0.20.3: Destruction 11/11/29, Affliction, Demonology and leveling.
-- MythicSim Forever engine 944a791060db; learned spells only, no consumables.
local M = {
	defaults = {
        leveling = true,
		destruction = false, destConflagrate = true, destShadowburn = true, destDoom = true,
		destFinishers = true, destImpSacrifice = true,
		destEureka = true, destRacials = true, destDeathCoil = false, destSoulFire = false,
		destBurstMinTargetHP = 40, destBurstMinMana = 35,
		affliction = false, affNightfall = true, affDoom = true, affFastImmolate = true,
		affFinishers = true, affWrack = false,
		affAmplifyCurse = true, affEureka = true, affDeathCoil = false,
		affBurstMinTargetHP = 40, affBurstMinMana = 35,
		demonology = false, demoBrand = true, demoImpSacrifice = true, soulLink = true,
		corruption = true, siphonLife = true, shadowBolt = true, demoDoom = true,
		rainOfFire = true, hellfire = false, hellfireMinHP = 70,
		demoEureka = true, demoDeathCoil = true, demoSoulFire = false, demoFelDomination = true,
		demoBurstMinTargetHP = 40, demoBurstMinMana = 35,
		armor = true, pet = true, immolate = true, agony = true,
		curseElements = true, curseWeakness = false, curseRecklessness = false, curseTongues = false,
		lifetap = true, lifeTapMana = 25, shootMana = 25, drainsoul = true, fear = true, drink = true,
		healthfunnel = true, healthFunnelPetHP = 40, healthFunnelMinPlayerHP = 60,
		drainSoulMinShards = 1,
		aoe = false, aoeMinEnemies = 3, aoeMinMana = 30,
	},
}

-- Exactly one rotation stays selected. Leveling is the default and the
-- fallback when a selected specialization is switched off or saved flags
-- conflict. A valid saved specialization takes priority during migration.
M.buildKeys = { "leveling", "destruction", "affliction", "demonology" }
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
    s = s or AL.Profile("WARLOCK")
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
	{ 18288, "Amplify Curse" },
	{ 980, "Bane of Agony" },
	{ 710, "Banish" },
	{ 20554, "Berserking" },
	{ 20572, "Blood Fury" },
	{ 1293817, "Conflagrate" }, -- Forever rank 1, learned at 25; not Classic rank 1.
	{ 172, "Corruption" },
	{ 6201, "Create Healthstone" },
	{ 693, "Create Soulstone" },
	{ 0, "Curse of Agony" }, -- Legacy name fallback; Forever uses Bane of Agony.
	{ 440892, "Curse of the Elements" },
	{ 704, "Curse of Recklessness" },
	{ 1714, "Curse of Tongues" },
	{ 702, "Curse of Weakness" },
	{ 706, "Demon Armor" },
	{ 687, "Demon Skin" },
	{ 132, "Detect Lesser Invisibility" },
	{ 689, "Drain Life" },
	{ 5138, "Drain Mana" },
	{ 1120, "Drain Soul" },
	{ 1098, "Enslave Demon" },
	{ 1259821, "Eureka!" },
	{ 126, "Eye of Kilrogg" },
	{ 5782, "Fear" },
	{ 755, "Health Funnel" },
	{ 1949, "Hellfire" },
	{ 348, "Immolate" },
	{ 1454, "Life Tap" },
	{ 5740, "Rain of Fire" },
	{ 698, "Ritual of Summoning" },
	{ 5500, "Sense Demons" },
	{ 5019, "Shoot" },
	{ 5676, "Searing Pain" },
	{ 686, "Shadow Bolt" },
	{ 17877, "Shadowburn" },
	{ 18265, "Siphon Life" },
	{ 603, "Bane of Doom" },
	{ 18788, "Demonic Sacrifice" },
	{ 18708, "Fel Domination" },
	{ 19028, "Soul Link" },
	{ 6353, "Soul Fire" },
	{ 6789, "Death Coil" },
	{ 688, "Summon Imp" },
	{ 712, "Summon Succubus" },
	{ 697, "Summon Voidwalker" },
	{ 5697, "Unending Breath" },
	{ 1316697, "Wrack" },
}

local SOUL_SHARD = { 6265 }

-- Read the actual bag count for Soul Shards.
--
-- Forever can protect GetItemCount(), so use a layered detector:
--   1. GetItemCount(6265)
--   2. Direct bag-slot scan through legacy container APIs
--   3. Direct bag-slot scan through C_Container APIs
--
-- Return count, source.  nil means every readable inventory path was blocked.
local SOUL_SHARD_ID = 6265

local function ReadableNumber(v)
	if type(v) ~= "number" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	if v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end

local function ReadableString(v)
	if type(v) ~= "string" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h, i, j = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e, f, g, h, i, j
end

local function ContainerNumSlots(bag)
	local n
	if type(GetContainerNumSlots) == "function" then
		n = ReadableNumber((SafeCall(GetContainerNumSlots, bag)))
		if n ~= nil then return n, "legacy" end
	end
	if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
		n = ReadableNumber((SafeCall(C_Container.GetContainerNumSlots, bag)))
		if n ~= nil then return n, "C_Container" end
	end
end

local function ContainerItemID(bag, slot)
	local id
	if type(GetContainerItemID) == "function" then
		id = ReadableNumber((SafeCall(GetContainerItemID, bag, slot)))
		if id ~= nil then return id end
	end
	if C_Container and type(C_Container.GetContainerItemID) == "function" then
		id = ReadableNumber((SafeCall(C_Container.GetContainerItemID, bag, slot)))
		if id ~= nil then return id end
	end

	-- Fallback: parse the item ID out of a readable item link.
	local link
	if type(GetContainerItemLink) == "function" then
		link = ReadableString((SafeCall(GetContainerItemLink, bag, slot)))
	end
	if not link and C_Container and type(C_Container.GetContainerItemLink) == "function" then
		link = ReadableString((SafeCall(C_Container.GetContainerItemLink, bag, slot)))
	end
	if link then
		return tonumber(link:match("item:(%d+)"))
	end

	-- Newer C_Container can return itemID inside the info table.
	if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
		local info = SafeCall(C_Container.GetContainerItemInfo, bag, slot)
		if type(info) == "table" then
			id = ReadableNumber(info.itemID)
			if id ~= nil then return id end
		end
	end
end

local function ContainerStackCount(bag, slot)
	-- Modern API.
	if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
		local info = SafeCall(C_Container.GetContainerItemInfo, bag, slot)
		if type(info) == "table" then
			local n = ReadableNumber(info.stackCount or info.count)
			if n ~= nil then return n end
		end
	end

	-- Legacy API: second return value is stack count.
	if type(GetContainerItemInfo) == "function" then
		local _, count = SafeCall(GetContainerItemInfo, bag, slot)
		count = ReadableNumber(count)
		if count ~= nil then return count end
	end
end

local function SoulShardsFromBagSlots()
	local total = 0
	local readableBag = false

	-- 0 = backpack, 1-4 = equipped bags, 5 is harmless on clients that expose
	-- an extra container and simply reports zero/nil elsewhere.
	for bag = 0, 5 do
		local slots = ContainerNumSlots(bag)
		if slots ~= nil then
			readableBag = true
			for slot = 1, slots do
				local id = ContainerItemID(bag, slot)
				if id == SOUL_SHARD_ID then
					local stack = ContainerStackCount(bag, slot)
					-- Soul Shards are normally one per slot on this ruleset.
					-- If stack size is readable, honor it; otherwise count the
					-- confirmed matching slot as one shard.
					total = total + (stack and math.max(1, stack) or 1)
				end
			end
		end
	end

	if readableBag then
		return total
	end
end

local function SoulShardCount()
	-- Fast path.
	if type(GetItemCount) == "function" then
		local count = ReadableNumber((SafeCall(GetItemCount, SOUL_SHARD_ID)))
		if count ~= nil then
			return count, "GetItemCount"
		end
	end

	-- Forever fallback.
	local count = SoulShardsFromBagSlots()
	if count ~= nil then
		return count, "bag scan"
	end

	return nil, "unreadable"
end

-- Expose the exact detector to the Warlock UI for live diagnostics.
M.SoulShardCount = SoulShardCount

local function AgonySpell()
	if AL.Ok("Bane of Agony") then return "Bane of Agony" end
	if AL.Ok("Curse of Agony") then return "Curse of Agony" end
end

-- Le DoT en cours d'incantation compte comme pose : l'icone passe au suivant.
local function DotUp(name, casting)
	if casting == name then return true end
	if AL.DPS60 and AL.DPS60.Active() and AL.DPS60.Info(name) then
		local active = AL.DPS60.Aura(name, true)
		if active ~= nil then return active end
	end
	local timer = AL.targetDebuffs and AL.targetDebuffs[name]
	return casting == name
		or (timer and (not timer.expires or timer.expires > GetTime()))
		or AL.HasDebuff("target", name)
end

local function AgonyOnTarget(casting)
	return DotUp("Bane of Agony", casting) or DotUp("Curse of Agony", casting)
end

local function BestArmor()
	if AL.Ok("Demon Armor") then return "Demon Armor" end
	if AL.Ok("Demon Skin") then return "Demon Skin" end
end

-- Return the readable spell name currently being cast/channelled by the player.
-- While Immolate is still in flight, its debuff has not landed yet, so without
-- this check the rotation would continue recommending Immolate every refresh.
-- Sort lisible en cours (incantation ou canalisation), sinon celui que Core connait par UNIT_SPELLCAST_START.
local function PlayerCastingSpell()
	if UnitCastingInfo then
		local ok, name = pcall(UnitCastingInfo, "player")
		if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
			return (AL.englishNames and AL.englishNames[name]) or name
		end
	end
	if UnitChannelInfo then
		local ok, name = pcall(UnitChannelInfo, "player")
		if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
			return (AL.englishNames and AL.englishNames[name]) or name
		end
	end
	return AL.CastingSpell and AL.CastingSpell() or nil
end

-- Health Funnel is only suggested when movement is positively readable as zero.
local function PlayerStationary()
	if type(GetUnitSpeed) ~= "function" then return false end
	local ok, speed = pcall(GetUnitSpeed, "player")
	if not ok or (issecretvalue and issecretvalue(speed)) or type(speed) ~= "number" then
		return false
	end
	return speed == 0
end

-- Movement is only considered true when Forever gives us a readable speed
-- greater than zero. If the value is protected/unknown, do not guess.
local function PlayerMoving()
	if type(GetUnitSpeed) ~= "function" then return false end
	local ok, speed = pcall(GetUnitSpeed, "player")
	if not ok or (issecretvalue and issecretvalue(speed)) or type(speed) ~= "number" then
		return false
	end
	return speed > 0
end

-- Pure Soul Shard comparison. This intentionally does NOT check movement,
-- spell usability, casting state, or target health. A shard deficit is simply:
-- detected bag count < configured minimum.
local function SoulShardDeficit(s)
	-- A new character cannot build shards before Drain Soul is learned.
	if not s.drainsoul or not AL.Ok("Drain Soul") then return false end

	local shards = SoulShardCount()
	if shards == nil then return false end

	local minimumShards = math.max(1, math.floor(tonumber(s.drainSoulMinShards) or 1))
	if shards >= minimumShards then
		return false, shards, minimumShards
	end

	return true, shards, minimumShards
end

-- After the initial DoT package, a readable shard deficit owns the filler slot.
-- Known movement is handled earlier by the Shoot override. If movement is
-- unreadable, do not let that uncertainty re-enable Shadow Bolt.
local function ForcedDrainSoul(s)
	local deficit, shards, minimumShards = SoulShardDeficit(s)
	if not deficit then return false, shards, minimumShards end

	if AL.Ok("Drain Soul") then
		return true, shards, minimumShards
	end

	-- Still return the deficit separately to callers so Shadow Bolt remains
	-- blocked even if the spellbook detector temporarily cannot confirm Drain Soul.
	return false, shards, minimumShards, true
end

-- Readable mana wins. When Forever protects it, maintain an estimate from
-- learned-rank spell costs, successful casts, Life Tap and mana regeneration.
-- The maximum-mana bootstrap assumes a full pool at login/reload; it is never
-- repeated just because combat ends or the target changes.
local CAST_HISTORY_SECONDS = 600 -- Cover the longest tracked build cooldown, not only the GCD.
local manaTracker = {
	updatedAt = GetTime(), lastSpend = -math.huge, processed = {},
}
local manaCosts, tapGains = {}, {}

local function ManaMaximum()
	local maximum = ReadableNumber((SafeCall(UnitPowerMax, "player", 0)))
	return maximum and maximum > 0 and maximum or manaTracker.maximum
end

local function NormalizePercent(value, minimum, maximum)
	value, minimum, maximum = ReadableNumber(value), ReadableNumber(minimum), ReadableNumber(maximum)
	if value == nil or minimum == nil or maximum == nil then return nil end
	if maximum <= minimum or value < minimum or value > maximum then return nil end
	return (value - minimum) / (maximum - minimum) * 100
end

local function ManaFromStatusBar(bar)
	if not bar or type(bar.GetValue) ~= "function" or type(bar.GetMinMaxValues) ~= "function" then return nil end
	local value = SafeCall(bar.GetValue, bar)
	local minimum, maximum = SafeCall(bar.GetMinMaxValues, bar)
	return NormalizePercent(value, minimum, maximum)
end

local function ManaFromFontString(fontString, knownMaximum)
	if not fontString or type(fontString.GetText) ~= "function" then return nil end
	local text = ReadableString((SafeCall(fontString.GetText, fontString)))
	if not text then return nil end
	text = text:gsub(",", "")
	local current, maximum = text:match("(%d+)%s*/%s*(%d+)")
	current, maximum = tonumber(current), tonumber(maximum)
	if current and maximum then return NormalizePercent(current, 0, maximum) end
	local percent = tonumber(text:match("(%d+%.?%d*)%s*%%"))
	if percent then return NormalizePercent(percent, 0, 100) end
	current = tonumber(text:match("^%s*(%d+)%s*$"))
	if current and knownMaximum then return NormalizePercent(current, 0, knownMaximum) end
end

local function ReadManaPercent(maximum)
	local current = ReadableNumber((SafeCall(UnitPower, "player", 0)))
	local pct = current and maximum and NormalizePercent(current, 0, maximum)
	if pct then return pct, "UnitPower" end
	pct = ManaFromStatusBar(_G.PlayerFrameManaBar)
	if pct then return pct, "player mana bar" end
	local frame = _G.PlayerFrame
	local content = frame and frame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local area = main and main.ManaBarArea
	pct = ManaFromStatusBar(area and area.ManaBar)
	if pct then return pct, "nested mana bar" end
	pct = ReadableNumber((SafeCall(AL.ManaPercent)))
	if pct and pct >= 0 and pct <= 100 then return pct, "Core mana" end
	pct = ManaFromFontString(_G.PlayerFrameManaBarText, maximum)
	if pct then return pct, "mana text" end
	local right = _G.PlayerFrameManaBarTextRight
	local rightText = right and ReadableString((SafeCall(right.GetText, right)))
	local textMax = rightText and tonumber(rightText:gsub(",", ""):match("(%d+)"))
	pct = ManaFromFontString(_G.PlayerFrameManaBarTextLeft, textMax or maximum)
	if pct then return pct, "mana text" end
end

local function RefreshManaRegen()
	local base, casting = SafeCall(GetManaRegen)
	base, casting = ReadableNumber(base), ReadableNumber(casting)
	if base and base >= 0 then manaTracker.baseRegen = base end
	if casting and casting >= 0 then manaTracker.castingRegen = casting end
end

local function UpdateMana()
	local now = GetTime()
	RefreshManaRegen()
	if manaTracker.amount and manaTracker.maximum then
		local from = manaTracker.updatedAt
		local dt = math.max(0, now - from)
		-- Five-second rule: split an interval that crosses the recovery boundary.
		local reduced = math.max(0, math.min(now, manaTracker.lastSpend + 5) - from)
		reduced = math.min(dt, reduced)
		local regen = reduced * (manaTracker.castingRegen or 0)
			+ (dt - reduced) * (manaTracker.baseRegen or 0)
		manaTracker.amount = math.min(manaTracker.maximum, manaTracker.amount + regen)
	end
	manaTracker.updatedAt = now
	local maximum = ManaMaximum()
	if maximum then
		manaTracker.maximum = maximum
		if manaTracker.amount then manaTracker.amount = math.min(maximum, manaTracker.amount) end
	end
	local pct = ReadManaPercent(maximum)
	manaTracker.readable = pct ~= nil
	if pct ~= nil then
		if maximum then manaTracker.amount = maximum * pct / 100 end
	elseif manaTracker.amount == nil and maximum then
		manaTracker.amount = maximum
	end
	if pct ~= nil then return pct end
	if manaTracker.amount and maximum then return manaTracker.amount / maximum * 100 end
end

local function ManaSpellID(name, spellID)
	spellID = ReadableNumber(spellID)
	if spellID and spellID > 0 then return spellID end
	local ref = name and AL.rangeSpellRefs and AL.rangeSpellRefs[name]
	local learned = ref and ReadableNumber(ref.id)
	if learned and learned > 0 then return learned end
	-- Names resolve the current learned rank; a declared base ID might be rank 1.
	return name and ((AL.localNames and AL.localNames[name]) or name)
end

local function ReadManaCost(identifier)
	local fn = C_Spell and C_Spell.GetSpellPowerCost or GetSpellPowerCost
	local costs = identifier and SafeCall(fn, identifier)
	if type(costs) ~= "table" or (issecretvalue and issecretvalue(costs)) then return nil end
	local total = 0
	for _, info in ipairs(costs) do
		if type(info) ~= "table" or (issecretvalue and issecretvalue(info)) then return nil end
		local powerType, token = ReadableNumber(info.type), ReadableString(info.name)
		if powerType == nil and token == nil then return nil end
		if powerType == 0 or token == "MANA" then
			local required = ReadableNumber(info.requiredAuraID)
			if issecretvalue and issecretvalue(info.requiredAuraID) then return nil end
			local active = true
			if required and required > 0 then
				local hasAura = info.hasRequiredAura
				if (issecretvalue and issecretvalue(hasAura)) or type(hasAura) ~= "boolean" then return nil end
				active = hasAura
			end
			if active then
				local cost = ReadableNumber(info.cost)
				if cost == nil or cost < 0 then return nil end
				total = total + cost
			end
		end
	end
	return total
end

local function SpellManaCost(name, spellID)
	local identifier = ManaSpellID(name, spellID)
	local cost = ReadManaCost(identifier)
	if cost ~= nil then
		manaCosts[identifier] = cost
		return cost, identifier, "spell power cost"
	end
	if identifier and manaCosts[identifier] ~= nil then return manaCosts[identifier], identifier, "cached spell power cost" end
	if name == "Shoot" or name == "Attack" or name == "Life Tap" then return 0, identifier, "no mana cost" end
	return nil, identifier, "unavailable"
end

local function LifeTapGain(name, spellID)
	if name ~= "Life Tap" then return 0, "not Life Tap" end
	local identifier = ManaSpellID(name, spellID)
	local fn = C_Spell and C_Spell.GetSpellDescription or GetSpellDescription
	local text = identifier and ReadableString((SafeCall(fn, identifier)))
	if text then
		-- Keep the live rank's amount, rather than treating Life Tap as a free cast.
		text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub(",", ""):lower()
		local gain = tonumber(text:match("(%d+%.?%d*)%s+mana"))
		if gain and gain > 0 then tapGains[identifier] = gain; return gain, "spell description" end
	end
	if identifier and tapGains[identifier] then return tapGains[identifier], "cached spell description" end
	return nil, "unavailable"
end

function M.RefreshManaCache()
	UpdateMana()
	for name, ref in pairs(AL.rangeSpellRefs or {}) do
		local english = (AL.englishNames and AL.englishNames[name]) or name
		SpellManaCost(english, ref.id)
		if english == "Life Tap" then LifeTapGain(english, ref.id) end
	end
end

function M.OnManaCastSent(name, spellID)
	UpdateMana()
	local cost, identifier = SpellManaCost(name, spellID)
	local gain = LifeTapGain(name, spellID)
	return { name = name, id = identifier, cost = cost, gain = gain }
end

function M.OnManaCastSucceeded(name, spellID, castGUID, pending)
	if M.ShouldAccountManaCast and not M.ShouldAccountManaCast(name, castGUID, spellID, pending) then return end
	local now = GetTime()
	for guid, at in pairs(manaTracker.processed) do
		if now - at >= CAST_HISTORY_SECONDS then manaTracker.processed[guid] = nil end
	end
	if castGUID and manaTracker.processed[castGUID] then return end
	if castGUID then manaTracker.processed[castGUID] = now end
	if pending and pending.manaApplied then return end
	if pending then pending.manaApplied = true end
	local saved = pending and pending.mana
	local identifier = ManaSpellID(name, spellID)
	-- A readable SENT rank remains authoritative when SUCCEEDED hides its ID.
	if saved and saved.name == name and ReadableNumber(spellID) == nil and saved.id ~= nil then identifier = saved.id end
	local cost, gain
	if saved and saved.name == name and saved.id == identifier then
		cost, gain = saved.cost, saved.gain
	end
	if cost == nil then cost = SpellManaCost(name, spellID) end
	if gain == nil then gain = LifeTapGain(name, spellID) end
	UpdateMana()
	if not manaTracker.readable and manaTracker.amount then
		manaTracker.amount = math.max(0, math.min(manaTracker.maximum,
			manaTracker.amount - (cost or 0) + (gain or 0)))
	end
	if cost and cost > 0 then manaTracker.lastSpend = now end
end

local function WarlockManaPercent() return UpdateMana() end

-- Preserve a minimum mana reserve even when the Shoot slider is set lower.
local HARD_SHOOT_MANA = 10

local function ShootThreshold(s)
	local configured = math.max(0, math.min(100, tonumber(s.shootMana) or 25))
	return math.max(HARD_SHOOT_MANA, configured), configured
end

local function ShadowBoltOutOfMana()
	local fn = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
	local usable, noMana = SafeCall(fn, ManaSpellID("Shadow Bolt"))
	if issecretvalue and (issecretvalue(usable) or issecretvalue(noMana)) then return false end
	return usable == false and noMana == true
end

local function ShootState(s, manaPct)
	local threshold, configured = ShootThreshold(s)
	-- The wand reserve must not disable usable spells without a wand.
	if not AL.WandEquipped() then
		return false, manaPct, threshold, configured, "no wand equipped"
	end
	if type(manaPct) ~= "number" then return true, manaPct, threshold, configured, "mana unavailable" end
	if manaPct <= HARD_SHOOT_MANA then
		return true, manaPct, threshold, configured, "Shoot protection: mana <= " .. tostring(HARD_SHOOT_MANA) .. "%"
	end
	if manaPct <= threshold then
		return true, manaPct, threshold, configured, "Shoot mana " .. tostring(math.floor(manaPct + 0.5)) .. "% <= " .. tostring(configured) .. "%"
	end
	if ShadowBoltOutOfMana() then return true, manaPct, threshold, configured, "Shadow Bolt out of mana" end
	return false, manaPct, threshold, configured, nil
end

-- Curses share one slot; Bane of Agony has its own slot on Forever.
-- Select ONE checked, learned/enabled curse before checking its aura. If more
-- than one is checked, this stable order prevents curses replacing each other
-- every frame. An unusable selected curse does not trigger a different curse.
local CURSE_CHOICES = {
	{ key = "curseElements", spell = "Curse of the Elements" },
	{ key = "curseWeakness", spell = "Curse of Weakness" },
	{ key = "curseRecklessness", spell = "Curse of Recklessness" },
	{ key = "curseTongues", spell = "Curse of Tongues" },
}

function M.SelectedCurse(s)
	for _, choice in ipairs(CURSE_CHOICES) do
		if s[choice.key] and AL.Ok(choice.spell) then
			return choice.spell
		end
	end
end

-- Une seule malediction utilitaire suffit pour cette cible. Le sort vraiment
-- lance peut differer de la selection (raccourci/macro ou changement de profil).
-- Ne pas rester bloque en attendant un autre nom, ni remplacer la malediction
-- deja posee. Bane of Agony ne fait pas partie de ce groupe.
function M.ActiveCurse(casting)
	local now = GetTime()
	for _, choice in ipairs(CURSE_CHOICES) do
		local name = choice.spell
		local timer = AL.targetDebuffs and AL.targetDebuffs[name]
		if casting == name
			or (timer and (not timer.expires or timer.expires > now))
			or AL.HasDebuff("target", name)
		then
			return name
		end
	end
end

local function NextCurse(s, casting)
	local curse = M.SelectedCurse(s)
	if not curse then return nil end
	-- Core enregistre le succes immediatement, meme si les auras sont bloquees.
	-- Toute malediction utilitaire active termine cette phase : passer aux DoT.
	if M.ActiveCurse(casting) then return nil end
	if AL.SpellUsable(curse) then
		return curse, "selected curse"
	end
end

-- DoT autorises pour le repli LIKELY de Core lorsque l'identite est secrete.
-- Un succes de lancement reste obligatoire ; aucune simple suggestion ne
-- doit creer un timer. Les curses utilisent SelectedCurse separement.
local TRACKED_DOT_SETTINGS = {
	["Immolate"] = "immolate", ["Corruption"] = "corruption",
	["Bane of Agony"] = "agony", ["Curse of Agony"] = "agony",
	["Siphon Life"] = "siphonLife",
}

function M.CanTrackSuggestedDebuff(name, s)
	local setting = TRACKED_DOT_SETTINGS[name]
	if setting == "corruption" or setting == "siphonLife" then return s[setting] ~= false and AL.Ok(name) or false end
	return setting and (setting == true or s[setting]) and AL.Ok(name) or false
end

-- Mana-only recommendation fallback also covers filler, Life Tap and buffs.
-- Core still requires a matching successful cast before accounting for it.
function M.CanTrackSuggestedSpell(name, s)
	for _, choice in ipairs(CURSE_CHOICES) do
		if choice.spell == name then return M.SelectedCurse(s) == name end
	end
	if TRACKED_DOT_SETTINGS[name] then return M.CanTrackSuggestedDebuff(name, s) end
	for _, entry in ipairs(M.spells) do
		if entry[2] == name then return AL.Ok(name) end
	end
	return false
end

-- Any DoT that is CURRENTLY being cast is treated as committed even though
-- its debuff cannot appear on the target until the cast finishes.
--
-- This keeps the recommendation moving forward:
--   Immolate -> Corruption -> Agony -> Siphon Life -> Drain Soul (if needed) -> Shoot (low mana) / Shadow Bolt
local function AfterCastingDot(casting, s, targetHp)
	local stage
	if casting == "Immolate" then
		stage = 1
	elseif casting == "Corruption" then
		stage = 2
	elseif casting == "Bane of Agony" or casting == "Curse of Agony" then
		stage = 3
	elseif casting == "Siphon Life" then
		stage = 4
	else
		return nil
	end

	-- After Immolate, Corruption is next.
	if stage < 2
		and s.corruption ~= false and AL.Ok("Corruption")
		and not DotUp("Corruption", casting)
		and (not targetHp or targetHp > 30)
		and AL.SpellUsable("Corruption")
	then
		return "Corruption", "queued after " .. casting
	end

	-- After Immolate/Corruption, Agony is next.
	if stage < 3 then
		local agony = AgonySpell()
		if s.agony
			and agony
			and not AgonyOnTarget(casting)
			and (not targetHp or targetHp > 40)
			and AL.SpellUsable(agony)
		then
			return agony, "queued after " .. casting
		end
	end

	-- After the earlier DoTs, Siphon Life is next when learned.
	if stage < 4
		and s.siphonLife ~= false and AL.Ok("Siphon Life")
		and not DotUp("Siphon Life", casting)
		and (not targetHp or targetHp > 40)
		and AL.SpellUsable("Siphon Life")
	then
		return "Siphon Life", "queued after " .. casting
	end

	-- Once the DoTs ahead of us are handled, the shard comparison is absolute:
	-- below the configured minimum means Drain Soul, never Shadow Bolt.
	local deficit, shards, minimumShards = SoulShardDeficit(s)
	if deficit then
		if AL.Ok("Drain Soul") then
			return "Drain Soul", "Soul Shards " .. tostring(shards) .. "/" .. tostring(minimumShards)
		end
		return nil, "Soul Shard deficit " .. tostring(shards) .. "/" .. tostring(minimumShards)
	end

	local manaPct = WarlockManaPercent()
	local forceShoot, _, _, _, shootReason = ShootState(s, manaPct)
	if forceShoot then
		if AL.WandEquipped() and AL.Ok("Shoot") then
			return "Shoot", shootReason or "Shoot mode"
		end
		return nil, "Shadow Bolt blocked: " .. tostring(shootReason or "Shoot mode")
	end

	-- With a wand equipped, Shadow Bolt requires mana above its threshold.
	-- Without one, native spell usability remains the authority.
	if s.shadowBolt ~= false and AL.Ok("Shadow Bolt") and AL.SpellUsable("Shadow Bolt") then
		return "Shadow Bolt", "queued after " .. casting
	end
	if AL.WandEquipped() and AL.Ok("Shoot") then
		return "Shoot", "Shadow Bolt unavailable"
	end
end

local function NextDot(s, casting, targetHp)
	local curse, curseReason = NextCurse(s, casting)
	if curse then return curse, curseReason end
	if s.immolate and AL.Ok("Immolate") and not DotUp("Immolate", casting)
		and (not targetHp or targetHp > 50)
		and AL.SpellUsable("Immolate")
	then
		return "Immolate", "dot"
	end
	if s.corruption ~= false and AL.Ok("Corruption") and not DotUp("Corruption", casting)
		and (not targetHp or targetHp > 30)
		and AL.SpellUsable("Corruption")
	then
		return "Corruption", "dot"
	end
	local agony = AgonySpell()
	if s.agony and agony and not AgonyOnTarget(casting)
		and (not targetHp or targetHp > 40)
		and AL.SpellUsable(agony)
	then
		return agony, "dot"
	end
	if s.siphonLife ~= false and AL.Ok("Siphon Life") and not DotUp("Siphon Life", casting)
		and (not targetHp or targetHp > 40)
		and AL.SpellUsable("Siphon Life")
	then
		return "Siphon Life", "dot"
	end
end

-- Shared build tracking and protected-percentage display; no Core replacement required.
local demoDecision
local demoVisibilityCurves, demoCurveFailures = {}, {}
local function DemoSafe(value) return not (issecretvalue and issecretvalue(value)) end
local function DemoBool(value) if DemoSafe(value) and type(value)=="boolean" then return value end end
local function DemoSetting(s,key,default,low,high)
    local value = DemoSafe(s[key]) and ReadableNumber(tonumber(s[key])) or nil
    return math.max(low,math.min(high,math.floor((value or default)+0.5)))
end
local DEMO_MIN_LEVELS = { ["Corruption"]=4,["Curse of Weakness"]=4,["Life Tap"]=6,["Bane of Agony"]=8,
    ["Curse of Agony"]=8,["Fear"]=8,["Drain Soul"]=10,["Health Funnel"]=12,["Drain Life"]=14,
    ["Curse of Recklessness"]=14,["Searing Pain"]=18,["Demon Armor"]=20,["Rain of Fire"]=20,
    ["Curse of the Elements"]=20,["Drain Mana"]=24,["Curse of Tongues"]=26,["Hellfire"]=30,
    ["Summon Imp"]=1,["Summon Voidwalker"]=10,["Summon Succubus"]=20,
    ["Death Coil"]=42,["Soul Fire"]=48,["Bane of Doom"]=60,["Shadowburn"]=20,["Wrack"]=40,["Conflagrate"]=25 }
local DemoOk, _, DemoKnown = AL.LevelGates(DEMO_MIN_LEVELS)
M.minLevels = DEMO_MIN_LEVELS
local function DemoTalent(name,id)
    if DemoSafe(AL.known[name]) and AL.known[name]==true then return true end
    local cached=AL.castSpellNamesByID and ReadableString(AL.castSpellNamesByID[id])
    if cached and DemoSafe(AL.known[cached]) and AL.known[cached]==true then return true end
    return DemoBool((SafeCall(IsPlayerSpell,id)))==true
end
local function DemoID(name)
    local ref=AL.rangeSpellRefs and AL.rangeSpellRefs[name]
    local id=ref and ReadableNumber(ref.id)
    if id then return id end
    for _,entry in ipairs(M.spells)do if entry[2]==name and entry[1]>0 then return entry[1] end end
end
local demoCDBase={ ["Conflagrate"]=10,["Amplify Curse"]=180,["Shadowburn"]=15,["Eureka!"]=120, ["Fel Domination"]=300, ["Death Coil"]=120,
    ["Soul Fire"]=60, ["Bane of Doom"]=60, ["Blood Fury"]=120, ["Berserking"]=180 }
local demoCDEnds,demoCastAt,demoRetry={}, {}, {}
local demoDots, demoSelf, demoPending, demoFinished = {}, {}, {}, {}
local demoFailedCasts = {}
local demoEpoch, demoLastSent, demoPetKind, demoPetAt, demoPetGUID = 0,nil,nil,nil,nil
local demoAuraCache,demoAurasBlocked={},{}
local demoDuration={ ["Immolate"]=15,["Corruption"]=18,["Bane of Agony"]=24,["Curse of Agony"]=24,
    ["Siphon Life"]=30,["Bane of Doom"]=60,["Demonic Brand"]=10,["Fear"]=10,
    ["Curse of the Elements"]=300,["Curse of Weakness"]=120,["Curse of Recklessness"]=120,["Curse of Tongues"]=30 }
local demoSelfDuration={ ["Demon Armor"]=1800,["Demon Skin"]=1800,["Burning Shadow"]=7200,
    ["Soul Link"]=math.huge,["Fel Domination"]=15,["Eureka!"]=15,["Amplify Curse"]=30 }
local demoSelfIDs={ ["Burning Shadow"]={[18789]=true}, ["Soul Link"]={[19028]=true,[25228]=true,[18814]=true},
    ["Demonic Brand"]={[1293696]=true},["Shadow Trance"]={[17941]=true} }
local demoCastIDs={}
local function DemoRanks(name,ids) for _,id in ipairs(ids)do demoCastIDs[id]=name end end
DemoRanks("Searing Pain",{5676,17919,17920,17921,17922,17923})
DemoRanks("Soul Fire",{6353,17924});DemoRanks("Death Coil",{6789,17925,17926})
DemoRanks("Demon Armor",{706,1086,11733,11734,11735});DemoRanks("Demon Skin",{687,696})
DemoRanks("Immolate",{348,707,1094,2941,11665,11667,11668,25309})
DemoRanks("Corruption",{172,6222,6223,7648,11671,11672,25311})
DemoRanks("Bane of Agony",{980,1014,6217,11711,11712,11713})
DemoRanks("Siphon Life",{18265,18879,18880,18881})
DemoRanks("Shadow Bolt",{686,695,705,1088,1106,7641,11659,11660,11661,25307})
DemoRanks("Shadowburn",{17877,18867,18868,18869,18870,18871})
DemoRanks("Conflagrate",{1293817,1293818,17962,18930,18931,18932})
DemoRanks("Curse of the Elements",{440892,1311676,1311677,1311680})
DemoRanks("Curse of Weakness",{702,1108,6205,7646,11707,11708})
DemoRanks("Curse of Recklessness",{704,7658,7659,11717})
DemoRanks("Curse of Tongues",{1714,11719});DemoRanks("Fear",{5782,6213,6215})
for _,entry in ipairs(M.spells)do
    if demoCDBase[entry[2]] or demoSelfDuration[entry[2]] or entry[2]=="Demonic Sacrifice" or entry[2]:find("^Summon ") then
        demoCastIDs[entry[1]]=entry[2]
    end
end
demoCastIDs[20572],demoCastIDs[20554]="Blood Fury","Berserking"
local function DemoTargetKey() return ReadableString((SafeCall(UnitGUID,"target"))) or demoEpoch end
local function DemoCastName(id)
    id=ReadableNumber(id);if not id then return nil end
    if demoCastIDs[id] then return demoCastIDs[id] end
    for _,entry in ipairs(M.spells)do
        local ref=AL.rangeSpellRefs and AL.rangeSpellRefs[entry[2]]
        if ref and id==ReadableNumber(ref.id) then return entry[2] end
    end
end
local function DemoGUID(value)
    value=ReadableString(value);return value and value:find("^Cast%-") and value or nil
end
function M.ShouldAccountManaCast(name,guid,spellID,pending)
    local settings=AL.S and AL.S()
    if settings and (settings.affliction==true or settings.destruction==true) then
        -- Proc/aura SUCCEEDED events are not another paid cast. A readable
        -- SENT rank remains the fallback when SUCCEEDED hides its spell ID.
        local id=ReadableNumber(spellID)
        local saved=pending and pending.mana
        if not id and saved then id=ReadableNumber(saved.id) end
        if id and DemoCastName(id)~=name then return false end
    end
    guid=DemoGUID(guid)
    if guid and demoFailedCasts[guid] then return false end
    if not guid and demoLastSent and demoLastSent.failed and demoLastSent.name==name
        and GetTime()-demoLastSent.at<=5 then return false end
    return true
end
local function DemoReadAura(unit,name,own)
    local now=GetTime();local cache=demoAuraCache[unit]
    if not cache or now-cache.at>=0.2 then
        cache={at=now,entries={},complete=false};demoAuraCache[unit]=cache
        local reader=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
        if not demoAurasBlocked[unit] and type(reader)=="function" then
            local complete=true
            for i=1,40 do
                local ok,aura=pcall(reader,unit,i,unit=="target" and "HARMFUL" or "HELPFUL")
                if not ok or not DemoSafe(aura) then demoAurasBlocked[unit]=true;break end
                if aura==nil then cache.complete=complete;break end
                if type(aura)~="table" then complete=false
                else
                    local id=ReadableNumber(aura.spellId);local label=ReadableString(aura.name)
                    label=label and ((AL.englishNames and AL.englishNames[label]) or label)
                    local mine=DemoBool(aura.isFromPlayerOrPlayerPet)
                    local caster=ReadableString(aura.sourceUnit)
                    if mine==nil and caster then mine=caster=="player" or caster=="pet" or caster=="vehicle" end
                    if id or label then cache.entries[#cache.entries+1]={id=id,name=label,mine=mine,expires=ReadableNumber(aura.expirationTime)}
                    else complete=false end
                end
            end
        end
    end
    local unknownOwner=false
    for _,aura in ipairs(cache.entries)do
        if aura.name==name or aura.id and (aura.id==DemoID(name) or demoCastIDs[aura.id]==name
            or demoSelfIDs[name] and demoSelfIDs[name][aura.id]) then
            if not own or aura.mine==true then return true,aura.expires end
            if aura.mine==nil then unknownOwner=true end
        end
    end
    if unknownOwner then return nil end
    if cache.complete then return false end
end
local function DemoSelfActive(name)
    local state=demoSelf[name];local now=GetTime()
    if state and now-state.at<0.5 then return state.expires>now end
    local active,expires=DemoReadAura("player",name)
    if active~=nil then
        if not active then demoSelf[name]=nil;return false end
        if expires and expires>0 then demoSelf[name]={at=now,expires=expires} end
        return true
    end
    if state and state.expires>now then return true end
    return DemoBool((SafeCall(AL.HasBuff,"player",name)))==true
end
local function DemoDotActive(name,casting,own)
    if casting==name then return true end
    local state=demoDots[name];local now=GetTime()
    if state and state.target==DemoTargetKey() and now-state.at<0.5 then return state.expires>now end
    local active=DemoReadAura("target",name,own)
    if active~=nil then return active end
    if state and state.target==DemoTargetKey() then return state.expires>now end
    if own then return false end
    if name=="Demonic Brand" or name=="Bane of Doom" then return false end
    local timer=AL.targetDebuffs and AL.targetDebuffs[name]
    if timer and DemoSafe(timer) and (not timer.targetGUID or timer.targetGUID==DemoTargetKey()) then
        local expires=ReadableNumber(timer.expires)
        if expires and expires>now then return true end
    end
    return DemoBool((SafeCall(AL.HasDebuff,"target",name)))==true
end
local function DemoCooldownEnd(name)
    local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,DemoID(name) or name)
    if not DemoSafe(info) or type(info)~="table" then return nil end
    local start,duration,rate=ReadableNumber(info.startTime),ReadableNumber(info.duration),ReadableNumber(info.modRate)
    if DemoSafe(info.modRate) and info.modRate==nil then rate=1 end
    if start and start>0 and duration and duration>1.5 and rate and rate>0 then return start+duration/rate end
end
local function DemoReady(name)
    if not DemoOk(name) or demoRetry[name] and demoRetry[name]>GetTime() then return false end
    if not demoCDBase[name] then return AL.IsReady(name) end
    local info=SafeCall(C_Spell and C_Spell.GetSpellCooldown,DemoID(name) or name)
    if DemoSafe(info) and type(info)=="table" then
        if DemoBool(info.isEnabled)==false then return false end
        local start,duration,rate=ReadableNumber(info.startTime),ReadableNumber(info.duration),ReadableNumber(info.modRate)
        if DemoSafe(info.modRate) and info.modRate==nil then rate=1 end
        local ready
        if start and start>=0 and duration and duration>=0 and rate and rate>0 then ready=start==0 or duration<=1.5 or start+duration/rate<=GetTime()
        elseif DemoBool(info.isActive)==false then ready=true
        elseif DemoBool(info.isActive)==true and DemoBool(info.isOnGCD)==false then ready=false end
        if DemoBool(info.isOnGCD)==true and (not duration or duration<=1.5)
            and demoCDEnds[name] and demoCDEnds[name]>GetTime() then return false end
        if ready~=nil then
            if ready and demoCastAt[name] and GetTime()-demoCastAt[name]<0.5 and demoCDEnds[name] and demoCDEnds[name]>GetTime() then return false end
            return ready
        end
    end
    return not demoCDEnds[name] or demoCDEnds[name]<=GetTime()
end
local function DemoPetType()
    local family=ReadableString((SafeCall(UnitCreatureFamily,"pet")))
    if family then
        if family=="Imp" then return "Imp" elseif family=="Succubus" or family=="Sayaad" then return "Succubus"
        elseif family=="Voidwalker" then return "Voidwalker" end
    end
    local guid=ReadableString((SafeCall(UnitGUID,"pet")))
    if demoPetKind and (demoPetAt and GetTime()-demoPetAt<0.5 or not guid or not demoPetGUID or guid==demoPetGUID) then return demoPetKind end
end
local destTalentWarm, destShadowAndFlame
local function DestructionTalentRank()
    if not destTalentWarm then
        destTalentWarm=true
        local localized=ReadableString((SafeCall(C_Spell and C_Spell.GetSpellName,426316)))
        for tab=1,3 do for index=1,40 do
            local name,_,_,_,rank=SafeCall(GetTalentInfo,tab,index,false,false)
            name,rank=ReadableString(name),ReadableNumber(rank)
            if name and rank and rank>=0 and rank<=5
                and (name=="Shadow and Flame" or localized and name==localized
                    or AL.englishNames and AL.englishNames[name]=="Shadow and Flame") then
                destShadowAndFlame=rank
            end
        end end
    end
    return destShadowAndFlame
end
local demoTracker=CreateFrame("Frame")
for _,event in ipairs({"UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET","UNIT_SPELLCAST_INTERRUPTED","PLAYER_TARGET_CHANGED",
    "PLAYER_ENTERING_WORLD","PLAYER_DEAD","UNIT_PET","UNIT_AURA","PLAYER_REGEN_ENABLED","SPELLS_CHANGED","PLAYER_TALENT_UPDATE"})do
    pcall(demoTracker.RegisterEvent,demoTracker,event)
end
demoTracker:SetScript("OnEvent",function(_,event,unit,a2,a3,a4)
    if AL.playerClass~="WARLOCK" then return end
    if event=="PLAYER_TARGET_CHANGED" then
        demoEpoch=demoEpoch+1;demoDots={};demoAuraCache.target=nil;demoAurasBlocked.target=nil;demoDecision=nil;return
    end
    if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_DEAD" then
        demoPending,demoFinished,demoFailedCasts,demoLastSent,demoRetry={}, {},{},nil,{}
        demoAuraCache,demoAurasBlocked={},{};demoDots={};demoDecision=nil
        if event=="PLAYER_ENTERING_WORLD" then destTalentWarm,destShadowAndFlame=nil,nil end
        if event=="PLAYER_DEAD" then demoSelf={};demoPetKind,demoPetAt,demoPetGUID=nil,nil,nil end
        return
    end
    if event=="PLAYER_REGEN_ENABLED" or event=="SPELLS_CHANGED" or event=="PLAYER_TALENT_UPDATE" then
        destTalentWarm,destShadowAndFlame=nil,nil
        demoAuraCache,demoAurasBlocked={},{};demoCurveFailures={};return
    end
    if event=="UNIT_AURA" then
        if ReadableString(unit) then demoAuraCache[unit]=nil end;return
    end
    if event=="UNIT_PET" then
        if DemoSafe(unit) and unit=="player" then
            demoSelf["Soul Link"]=nil;demoAuraCache.player=nil
            if not demoPetAt or GetTime()-demoPetAt>=0.5 then demoPetKind,demoPetGUID=nil,nil end
        end
        return
    end
    if not DemoSafe(unit) or unit~="player" then return end
    for guid,cast in pairs(demoPending)do if GetTime()-cast.at>30 then demoPending[guid]=nil end end
    for guid,at in pairs(demoFinished)do if GetTime()-at>CAST_HISTORY_SECONDS then demoFinished[guid]=nil end end
    for guid,at in pairs(demoFailedCasts)do if GetTime()-at>CAST_HISTORY_SECONDS then demoFailedCasts[guid]=nil end end
    local guid=DemoGUID(event=="UNIT_SPELLCAST_SENT" and a3 or a2)
    local id=ReadableNumber(a4) or ReadableNumber(a3);local name=DemoCastName(id)
    local readable=id~=nil
    if not readable then
        local label=ReadableString(a2)
        label=label and ((AL.englishNames and AL.englishNames[label]) or label)
        if label and (demoCDBase[label] or demoDuration[label] or demoSelfDuration[label] or label=="Demonic Sacrifice" or label:find("^Summon ")) then name,readable=label,true end
    end
    if event=="UNIT_SPELLCAST_SENT" then
        if not readable and not (demoDecision and demoDecision.visualCandidate) then
            local hint=ReadableString(AL.lastSuggestion)
            if hint and DemoOk(hint) then name=hint end
        end
        local targetKey=DemoTargetKey()
        local sentTarget=ReadableString(a2)
        local targetName,realm=SafeCall(UnitName,"target")
        targetName,realm=ReadableString(targetName),ReadableString(realm)
        if sentTarget and sentTarget~="" and targetName then
            local fullName=realm and realm~="" and targetName.."-"..realm or targetName
            if sentTarget~=targetName and sentTarget~=fullName then targetKey=nil end
        end
        demoLastSent={name=name,at=GetTime(),target=targetKey,pet=DemoPetType(),guid=guid}
        if guid then demoPending[guid]=demoLastSent end;return
    end
    local sent=guid and demoPending[guid] or not guid and demoLastSent
    if event~="UNIT_SPELLCAST_SUCCEEDED" then
        if sent and not sent.done then sent.failed=true;if sent.name then demoRetry[sent.name]=GetTime()+1 end end
        if not (sent and sent.done) then
            local failedGUID=guid or sent and sent.guid
            if failedGUID then demoFailedCasts[failedGUID]=GetTime() end
        end
        if guid and not (sent and sent.done) then demoFinished[guid]=GetTime() end;return
    end
    if guid and demoFinished[guid] or sent and (sent.done or sent.failed) then return end
    if not readable and sent and GetTime()-sent.at<=5 then name=sent.name end
    if not name or sent and sent.name and sent.name~=name then return end
    if sent then sent.done=true end;if guid then demoFinished[guid]=GetTime() end
    local now=GetTime();demoRetry[name]=nil
    if name=="Shadow Bolt" then demoSelf["Shadow Trance"]={at=now,expires=now};demoAuraCache.player=nil end
    if name=="Bane of Agony" or name=="Curse of Agony" then
        demoSelf["Amplify Curse"]={at=now,expires=now};demoAuraCache.player=nil
    end
    if demoCDBase[name] then demoCastAt[name]=now;demoCDEnds[name]=DemoCooldownEnd(name) or now+demoCDBase[name] end
    if demoSelfDuration[name] then demoSelf[name]={at=now,expires=now+demoSelfDuration[name]};demoAuraCache.player=nil end
    if name:find("^Summon ") then
        demoPetKind=name:match("^Summon (.+)$");demoPetAt=now;demoPetGUID=ReadableString((SafeCall(UnitGUID,"pet")))
        demoSelf["Fel Domination"],demoSelf["Soul Link"]=nil,nil
        local settings=AL.S and AL.S()
        if name=="Summon Imp" or settings and settings.destruction==true and not DemoTalent("Demonic Pact",425464) then
            demoSelf["Burning Shadow"]=nil
        end
    elseif name=="Demonic Sacrifice" and (sent and sent.pet or DemoPetType())=="Imp" then
        demoSelf["Burning Shadow"]={at=now,expires=now+7200};demoSelf["Soul Link"]=nil
        demoPetKind,demoPetAt,demoPetGUID=nil,nil,nil;demoAuraCache.player=nil
    end
    local dotName=name
    if name=="Searing Pain" and DemoTalent("Demonic Brand",1293695) then dotName="Demonic Brand" end
    if sent and sent.target~=DemoTargetKey() then
        -- The older Core may attach a mouseover cast to its current target.
        -- Keep a class-owned negative result unless a valid own timer exists;
        -- readable auras still take priority over this fallback.
        if demoDuration[dotName] and not demoDots[dotName] then
            demoDots[dotName]={at=now-1,expires=now,target=DemoTargetKey()}
        end
        return
    end
    if name=="Conflagrate" and DestructionTalentRank()~=5 then
        -- Below 5/5 the DoT may be consumed. Readable auras will confirm its
        -- survival after the event grace; never assume the full-rank talent.
        demoDots.Immolate={at=now,expires=now,target=DemoTargetKey()}
        demoAuraCache.target=nil
    end
    if demoDuration[dotName] then
        if dotName=="Bane of Doom" then demoDots["Bane of Agony"],demoDots["Curse of Agony"]=nil,nil
        elseif dotName=="Bane of Agony" or dotName=="Curse of Agony" then demoDots["Bane of Doom"]=nil
        else
            for _,choice in ipairs(CURSE_CHOICES)do if choice.spell==dotName then for _,other in ipairs(CURSE_CHOICES)do demoDots[other.spell]=nil end end end
        end
        demoDots[dotName]={at=now,expires=now+demoDuration[dotName],target=DemoTargetKey()};demoAuraCache.target=nil
    end
end)
local function DemoCurveAvailable(kind,unit)
    local reader=kind=="power" and UnitPowerPercent or UnitHealthPercent
    if demoCurveFailures[kind..":"..unit]==reader then return false end
    return C_CurveUtil and type(C_CurveUtil.CreateColorCurve)=="function" and type(CreateColor)=="function" and type(reader)=="function"
end
local function DemoNextFloat(value)
    if value<=0 then return 2^-149 end
    local step=2^(math.floor(math.log(value)/math.log(2))-23)
    return (math.floor(value/step+0.5)+1)*step
end
local function DemoGate(kind,unit,value,threshold,below,strict)
    value=ReadableNumber(value)
    if value~=nil then
        if math.abs(value-threshold)<1e-7 then value=threshold end
        if below then return strict and value<threshold or not strict and value<=threshold end
        return strict and value>threshold or not strict and value>=threshold
    end
    if not below and not strict and threshold<=0 then return true end
    if not DemoCurveAvailable(kind,unit) then return false end
    local cut=threshold/100
    if below and not strict or not below and strict then cut=DemoNextFloat(cut) end
    return {axis=kind..":"..unit,kind=kind,unit=unit,powerType=kind=="power" and 0 or nil,cut=cut,below=below}
end
local function DemoAdd(name,reason,gates)
    local conditions={}
    for _,gate in ipairs(gates or {})do if gate==false then return false end;if type(gate)=="table" then conditions[#conditions+1]=gate end end
    local actions=demoDecision.actions
    if #actions>0 and #actions[#actions].conditions==0 then return false end
    actions[#actions+1]={spell=name,reason=reason,conditions=conditions};if #conditions>0 then demoDecision.visualCandidate=true end
    return true
end
local function DemoManaCostGate(cost,mana)
    cost=ReadableNumber(cost);if cost==nil or cost<=0 then return true end
    local maximum=ManaMaximum();if not maximum or cost>maximum then return false end
    return DemoGate("power","player",mana,cost/maximum*100,false,false)
end
local demoSelfSpells={ ["Amplify Curse"]=true,["Eureka!"]=true,["Fel Domination"]=true,["Demonic Sacrifice"]=true,["Soul Link"]=true,
    ["Demon Armor"]=true,["Demon Skin"]=true,["Summon Imp"]=true,["Summon Succubus"]=true,["Summon Voidwalker"]=true,
    ["Life Tap"]=true,["Hellfire"]=true,["Blood Fury"]=true,["Berserking"]=true }
local function DemoUsable(name)
    local usable,shortage=SafeCall(C_Spell and C_Spell.IsSpellUsable or IsUsableSpell,DemoID(name) or name)
    return DemoBool(usable),DemoBool(shortage)
end
local function DemoInRange(name)
    local value=DemoBool((SafeCall(C_Spell and C_Spell.IsSpellInRange,DemoID(name) or name,"target")))
    if value==nil then value=DemoBool((SafeCall(AL.InRange,name))) end
    return value
end
local function DemoOffer(name,reason,mana,gates)
    if not name or not DemoReady(name) then return false end
    local usable,shortage=DemoUsable(name);if usable==false or shortage==true then return false end
    if not demoSelfSpells[name] and name~="Rain of Fire" and name~="Health Funnel" and DemoInRange(name)==false then return false end
    local conditions={DemoManaCostGate(SpellManaCost(name),mana)}
    for _,gate in ipairs(gates or {})do conditions[#conditions+1]=gate end
    return DemoAdd(name,reason,conditions)
end
local function DemoHealth(unit)
    return ReadableNumber((SafeCall(AL.HealthPercent,unit)))
end
local function DemoTTD()
    local a=_G.Action;local object=a and SafeCall(a.Unit,"target")
    if DemoSafe(object) and (type(object)=="table" or type(object)=="userdata") then
        local value=ReadableNumber((SafeCall(object.TimeToDie,object)))
        if value and value>0 and value<3600 then return value end
    end
    local value=ReadableNumber((SafeCall(AL.TargetTTD)))
    if value and value>0 and value<3600 then return value end
end
local function DemoUnitNear(unit,yards)
    local squared,checked=SafeCall(UnitDistanceSquared,unit);squared=ReadableNumber(squared)
    if squared and squared>=0 and DemoBool(checked)~=false then return squared<=yards*yards end
    local a=_G.Action;local object=a and SafeCall(a.Unit,unit)
    if DemoSafe(object) and (type(object)=="table" or type(object)=="userdata") then
        local lower,upper=SafeCall(object.GetRange,object)
        if DemoSafe(upper) then
            lower,upper=ReadableNumber(lower),ReadableNumber(upper)
            local range=lower and upper and math.max(lower,upper) or upper or lower
            if range and range>=0 then return range<=yards end
        end
    end
    if yards>=30 then
        for _,spell in ipairs({"Searing Pain","Shadow Bolt"})do
            if DemoKnown(spell) then
                local value=DemoBool((SafeCall(C_Spell and C_Spell.IsSpellInRange,DemoID(spell) or spell,unit)))
                if value~=nil then return value end
            end
        end
    end
    if yards>=10 then
        local near=DemoBool((SafeCall(CheckInteractDistance,unit,3)))
        if near==true or yards==10 then return near end
    end
end
local function DemoEnemyCount(yards)
    local a=_G.Action;local count=ReadableNumber((SafeCall(AL.EnemyCount,yards)))
    if a and a.MultiUnits then
        local value=ReadableNumber((SafeCall(a.MultiUnits.GetByRangeInCombat,a.MultiUnits,yards,5)))
        if value then count=math.max(count or 0,value) end
    end
    if not count or count<0 or count>40 or count~=math.floor(count) then count=nil end
    local found,seen,unidentifiedTarget=0,{},false
    for i=0,40 do
        local unit=i==0 and "target" or "nameplate"..i
        if DemoBool((SafeCall(UnitExists,unit)))==true and DemoBool((SafeCall(UnitCanAttack,"player",unit)))==true
            and DemoBool((SafeCall(UnitIsDeadOrGhost,unit)))~=true and DemoUnitNear(unit,yards)==true then
            local threat=ReadableNumber((SafeCall(UnitThreatSituation,"player",unit)))
            local engaged=DemoBool((SafeCall(UnitAffectingCombat,unit)))==true or threat and threat>0
            local guid=ReadableString((SafeCall(UnitGUID,unit)))
            if engaged and (not guid or not seen[guid]) then
                if i==0 and not guid then unidentifiedTarget=true
                else found=found+1;if guid then seen[guid]=true end end
            end
        end
    end
    if found==0 and unidentifiedTarget then found=1 end
    return math.max(count or 0,found)
end
local function DemoPetPreparation(s,inCombat,petUp,mana)
    local kind=petUp and DemoPetType();local shards=SoulShardCount()
    local summon=DemoOk("Summon Succubus") and shards and shards>=1 and "Summon Succubus"
        or DemoOk("Summon Voidwalker") and shards and shards>=1 and "Summon Voidwalker"
        or DemoOk("Summon Imp") and "Summon Imp" or nil
    if not s.pet then return end
    if not inCombat and s.demoImpSacrifice and DemoTalent("Demonic Pact",425464) and DemoOk("Demonic Sacrifice")
        and DemoOk("Summon Imp") and DemoOk("Summon Succubus") and shards and shards>=1 and not DemoSelfActive("Burning Shadow") then
        local costImp,costSucc=SpellManaCost("Summon Imp"),SpellManaCost("Summon Succubus")
        if costImp and costSucc then
            local gate=DemoManaCostGate(costImp+costSucc,mana)
            if kind=="Imp" then
                local usable,shortage=DemoUsable("Summon Succubus")
                if usable~=false and shortage~=true then DemoOffer("Demonic Sacrifice","prepare own Burning Shadow",mana,{gate}) end
            elseif not petUp or kind then DemoOffer("Summon Imp","prepare learned Imp sacrifice",mana,{gate}) end
        end
    end
    if not petUp then
        local usable,shortage
        if summon then usable,shortage=DemoUsable(summon) end
        if inCombat and AL.burst and s.demoFelDomination and summon and usable~=false and shortage~=true
            and not DemoSelfActive("Fel Domination") then
            DemoOffer("Fel Domination","Burst: replace missing pet",mana,{DemoManaCostGate(SpellManaCost(summon),mana)})
        end
        DemoOffer(summon,"summon learned demon",mana)
    end
end
local function DemoAoE(s,mana,hp,aboveShoot)
    if not s.aoe or not PlayerStationary() then return end
    local minimum=DemoSetting(s,"aoeMinEnemies",3,2,5)
    local gates={DemoGate("power","player",mana,DemoSetting(s,"aoeMinMana",30,0,100),false,false),aboveShoot}
    if s.hellfire and DemoEnemyCount(10)>=minimum then
        DemoOffer("Hellfire","AoE: nearby engaged enemies",mana,{gates[1],gates[2],DemoGate("health","player",hp,DemoSetting(s,"hellfireMinHP",70,20,100),false,true)})
    end
    if s.rainOfFire~=false and DemoEnemyCount(30)>=minimum and DemoInRange("Rain of Fire")~=false then
        DemoOffer("Rain of Fire","AoE: engaged enemies",mana,gates)
    end
end
local function NextDemonology(s,inCombat,hostile)
    if not inCombat then demoCurveFailures={} end
    demoDecision={at=GetTime(),actions={}}
    local trackedMana=WarlockManaPercent();local mana=ReadManaPercent(ManaMaximum())
    if mana==nil and not DemoCurveAvailable("power","player") then mana=trackedMana end
    local hp,petHP,targetHP=DemoHealth("player"),DemoHealth("pet"),hostile and DemoHealth("target") or nil
    local petUp=DemoBool((SafeCall(UnitExists,"pet")))==true and DemoBool((SafeCall(UnitIsDeadOrGhost,"pet")))~=true
    local casting=ReadableString(PlayerCastingSpell())
    local channel=SafeCall(UnitChannelInfo,"player")
    if not DemoSafe(channel) or channel~=nil and channel~="" then return nil,"Channeling" end
    for _,reader in pairs({UnitChannelDuration})do
        local duration=SafeCall(reader,"player")
        if DemoSafe(duration) and (type(duration)=="table" or type(duration)=="userdata") then return nil,"Channeling" end
    end
    if casting and casting~="Immolate" and casting~="Corruption" and casting~="Searing Pain" then return nil,"Casting" end
    if not casting then
        local name=SafeCall(UnitCastingInfo,"player")
        if not DemoSafe(name) then return nil,"Casting" end
        local duration=SafeCall(UnitCastingDuration,"player")
        if DemoSafe(duration) and (type(duration)=="table" or type(duration)=="userdata") then return nil,"Casting" end
    end
    if inCombat and hostile and PlayerMoving() then
        if AL.WandEquipped() then DemoOffer("Shoot","moving",mana) end
        DemoAdd(nil,"Moving");local base=demoDecision.actions[#demoDecision.actions]
        demoDecision.baseSpell,demoDecision.baseReason=base.spell,base.reason;return base.spell,base.reason
    end
    if s.healthfunnel and petUp and PlayerStationary() then DemoOffer("Health Funnel","pet recovery",mana,{
        DemoGate("health","pet",petHP,DemoSetting(s,"healthFunnelPetHP",40,10,80),true,true),
        DemoGate("health","player",hp,DemoSetting(s,"healthFunnelMinPlayerHP",60,20,100),false,true)}) end
    if not inCombat and s.armor and not DemoSelfActive("Demon Armor") and not DemoSelfActive("Demon Skin") then
        local armor=DemoOk("Demon Armor") and "Demon Armor" or DemoOk("Demon Skin") and "Demon Skin" or nil
        DemoOffer(armor,"maintain own armor",mana)
    end
    if PlayerStationary() then DemoPetPreparation(s,inCombat,petUp,mana) end
    if s.soulLink and petUp and not DemoSelfActive("Soul Link") then DemoOffer("Soul Link","maintain own pet link",mana) end
    if not inCombat then
        if s.lifetap then DemoOffer("Life Tap","out-of-combat mana",mana,{
            DemoGate("power","player",mana,DemoSetting(s,"lifeTapMana",25,5,95),true,true),
            DemoGate("health","player",hp,80,false,true)}) end
        if s.drink then DemoAdd(nil,"Drink",{DemoGate("power","player",mana,30,true,true)}) end
    end
    if hostile then
        local shootThreshold=math.max(10,DemoSetting(s,"shootMana",25,5,95))
        local aboveShoot=true
        if AL.WandEquipped() then aboveShoot=DemoGate("power","player",mana,shootThreshold,false,true) end
        if ShadowBoltOutOfMana() then aboveShoot=false end
        if inCombat and s.fear and AL.TargetInMelee() and not DemoDotActive("Fear",casting) then
            DemoOffer("Fear","create space",mana,{DemoGate("health","player",hp,45,true,true)})
        end
        local curse=M.SelectedCurse(s);local activeCurse
        for _,choice in ipairs(CURSE_CHOICES)do if DemoDotActive(choice.spell,casting) then activeCurse=true;break end end
        if curse and not activeCurse then DemoOffer(curse,"selected curse",mana) end
        if inCombat then DemoAoE(s,mana,hp,aboveShoot) end
        local doom=DemoDotActive("Bane of Doom",casting)
        local agony=DemoDotActive("Bane of Agony",casting) or DemoDotActive("Curse of Agony",casting)
        local ttd=DemoTTD()
        if s.demoDoom and not doom and not agony and ttd and ttd>=60 then DemoOffer("Bane of Doom","confirmed long fight",mana) end
        if s.demoBrand and petUp and DemoTalent("Demonic Brand",1293695) and casting~="Searing Pain" and not DemoDotActive("Demonic Brand",casting) then
            DemoOffer("Searing Pain","apply Demonic Brand through learned talent",mana,{aboveShoot})
        end
        if s.agony and not doom and not agony then DemoOffer(AgonySpell(),"maintain Bane of Agony",mana,{DemoGate("health","target",targetHP,40,false,true)}) end
        if s.corruption~=false and not DemoDotActive("Corruption",casting) then DemoOffer("Corruption","maintain Corruption",mana,{DemoGate("health","target",targetHP,30,false,true)}) end
        if s.immolate and not DemoDotActive("Immolate",casting) then DemoOffer("Immolate","maintain Immolate",mana,{DemoGate("health","target",targetHP,50,false,true)}) end
        if s.siphonLife~=false and not DemoDotActive("Siphon Life",casting) then DemoOffer("Siphon Life","maintain learned Siphon Life",mana,{DemoGate("health","target",targetHP,40,false,true)}) end
        local deficit,shards,minimum=SoulShardDeficit(s)
        if deficit then
            if PlayerStationary() then DemoOffer("Drain Soul","Soul Shards "..tostring(shards).."/"..tostring(minimum),mana) end
            DemoAdd(nil,"Soul Shard deficit")
        end
        -- Burst actions stay in this branch; ordinary damage and AoE do not
        -- enable it. Life Tap and Shoot preserve the previous slider ordering.
        if inCombat and AL.burst then
            local gates={aboveShoot,DemoGate("power","player",mana,DemoSetting(s,"demoBurstMinMana",35,0,100),false,false),
                DemoGate("health","target",targetHP,DemoSetting(s,"demoBurstMinTargetHP",40,0,100),false,false)}
            if s.demoEureka and DemoOk("Shadow Bolt") and DemoReady("Shadow Bolt") and DemoInRange("Shadow Bolt")~=false then
                local usable,shortage=DemoUsable("Shadow Bolt")
                if usable~=false and shortage~=true and not DemoSelfActive("Eureka!") then
                    DemoOffer("Eureka!","Burst: direct damage",mana,{gates[1],gates[2],gates[3],DemoManaCostGate(SpellManaCost("Shadow Bolt"),mana)})
                end
            end
            DemoOffer("Blood Fury","Burst racial",mana,gates);DemoOffer("Berserking","Burst racial",mana,gates)
            if s.demoDeathCoil then DemoOffer("Death Coil","Burst: damage and healing",mana,gates) end
            local reserve=s.drainsoul and DemoSetting(s,"drainSoulMinShards",1,1,5) or 0
            if s.demoSoulFire and PlayerStationary() and shards==nil then shards=SoulShardCount() end
            if s.demoSoulFire and PlayerStationary() and shards and shards>reserve and ttd and ttd>=8 then DemoOffer("Soul Fire","optional Burst cast",mana,gates) end
        end
        if s.lifetap then DemoOffer("Life Tap","mana recovery",mana,{aboveShoot,
            DemoGate("power","player",mana,DemoSetting(s,"lifeTapMana",25,5,95),true,true),DemoGate("health","player",hp,60,false,true)}) end
        DemoOffer("Drain Life","sustain",mana,{aboveShoot,DemoGate("health","player",hp,70,true,true)})
        if s.shadowBolt~=false then DemoOffer("Shadow Bolt","Demonology filler",mana,{aboveShoot}) end
        if AL.WandEquipped() then DemoOffer("Shoot","mana protection / filler fallback",mana) end
        DemoAdd(AL.known.Attack and "Attack" or nil,"melee fallback")
    end
    DemoAdd(nil,inCombat and not hostile and "No target" or "Ready")
    local base=demoDecision.actions[#demoDecision.actions]
    demoDecision.baseSpell,demoDecision.baseReason=base.spell,base.reason
    return base.spell,base.reason
end

local function AffCastSeconds(name)
    local info=SafeCall(C_Spell and C_Spell.GetSpellInfo,DemoID(name) or name)
    if DemoSafe(info) and type(info)=="table" then
        local milliseconds=ReadableNumber(info.castTime)
        if milliseconds and milliseconds>=0 then return milliseconds/1000 end
    end
    local _,_,_,milliseconds=SafeCall(GetSpellInfo,DemoID(name) or name)
    milliseconds=ReadableNumber(milliseconds)
    if milliseconds and milliseconds>=0 then return milliseconds/1000 end
end
local function AffInstant(name)
    if name=="Bane of Agony" or name=="Curse of Agony" or name=="Siphon Life"
        or name=="Shadowburn" or name=="Death Coil" or name=="Life Tap" then return true end
    return AffCastSeconds(name)==0
end
local function AffDotActive(name,casting)
    local own=name=="Bane of Agony" or name=="Curse of Agony" or name=="Bane of Doom"
        or name=="Corruption" or name=="Immolate" or name=="Siphon Life"
    return DemoDotActive(name,casting,own)
end
local function AffPetPreparation(s,inCombat,petUp,mana)
    if not s.pet or petUp or inCombat or not PlayerStationary() then return end
    -- The 33/0/18 reference keeps a Succubus. It has neither sacrifice nor
    -- Soul Link. Keep any existing pet and use a shard-free Imp if necessary.
    local shards=SoulShardCount()
    local summon=DemoOk("Summon Succubus") and shards and shards>=1 and "Summon Succubus"
        or DemoOk("Summon Voidwalker") and shards and shards>=1 and "Summon Voidwalker"
        or DemoOk("Summon Imp") and "Summon Imp" or nil
    DemoOffer(summon,"Affliction: summon learned demon",mana)
end
local function AffBurst(s,mana,targetHP,aboveShoot,casting,agony,doom)
    if not AL.burst then return end
    local gates={aboveShoot,
        DemoGate("power","player",mana,DemoSetting(s,"affBurstMinMana",35,0,100),false,false),
        DemoGate("health","target",targetHP,DemoSetting(s,"affBurstMinTargetHP",40,0,100),false,false)}
    local bane=AgonySpell()
    if s.affAmplifyCurse and s.agony and not agony and not doom and bane and DemoReady(bane)
        and DemoInRange(bane)~=false and not DemoSelfActive("Amplify Curse") then
        local usable,shortage=DemoUsable(bane)
        if usable~=false and shortage~=true then
            DemoOffer("Amplify Curse","Burst: empower the next Bane of Agony",mana,
                {gates[1],gates[2],gates[3],DemoManaCostGate(SpellManaCost(bane),mana)})
        end
    end
    -- The remaining offensive cooldowns follow the initial DoT package.
    if s.agony and DemoOk(bane) and not doom and not agony
        or s.corruption~=false and DemoOk("Corruption") and not AffDotActive("Corruption",casting)
        or s.immolate and DemoOk("Immolate") and not AffDotActive("Immolate",casting)
            and (s.affFastImmolate==false or (AffCastSeconds("Immolate") or math.huge)<=1.5)
        or s.siphonLife~=false and DemoOk("Siphon Life") and not AffDotActive("Siphon Life",casting) then return end
    if PlayerStationary() and s.affEureka and s.shadowBolt~=false and DemoReady("Shadow Bolt")
        and DemoInRange("Shadow Bolt")~=false and not DemoSelfActive("Eureka!") then
        local usable,shortage=DemoUsable("Shadow Bolt")
        if usable~=false and shortage~=true then
            DemoOffer("Eureka!","Burst: direct damage",mana,
                {gates[1],gates[2],gates[3],DemoManaCostGate(SpellManaCost("Shadow Bolt"),mana)})
        end
    end
    DemoOffer("Blood Fury","Burst racial",mana,gates)
    DemoOffer("Berserking","Burst racial",mana,gates)
    if s.affDeathCoil then DemoOffer("Death Coil","Burst: damage and healing",mana,gates) end
end
local function NextAffliction(s,inCombat,hostile)
    if not inCombat then demoCurveFailures={} end
    demoDecision={at=GetTime(),actions={}}
    local trackedMana=WarlockManaPercent();local mana=ReadManaPercent(ManaMaximum())
    if mana==nil and not DemoCurveAvailable("power","player") then mana=trackedMana end
    local hp,petHP,targetHP=DemoHealth("player"),DemoHealth("pet"),hostile and DemoHealth("target") or nil
    local petUp=DemoBool((SafeCall(UnitExists,"pet")))==true and DemoBool((SafeCall(UnitIsDeadOrGhost,"pet")))~=true
    local casting=ReadableString(PlayerCastingSpell())
    local channel=SafeCall(UnitChannelInfo,"player")
    if not DemoSafe(channel) or channel~=nil and channel~="" then return nil,"Channeling" end
    local duration=SafeCall(UnitChannelDuration,"player")
    if DemoSafe(duration) and (type(duration)=="table" or type(duration)=="userdata") then return nil,"Channeling" end
    if casting and casting~="Immolate" and casting~="Corruption" then return nil,"Casting" end
    if not casting then
        local name=SafeCall(UnitCastingInfo,"player")
        if not DemoSafe(name) then return nil,"Casting" end
        duration=SafeCall(UnitCastingDuration,"player")
        if DemoSafe(duration) and (type(duration)=="table" or type(duration)=="userdata") then return nil,"Casting" end
    end
    local stationary=PlayerStationary()
    local function offer(name,reason,gates)
        if stationary or AffInstant(name) or name=="Amplify Curse" or name=="Eureka!"
            or name=="Blood Fury" or name=="Berserking" or name and name:find("^Curse of ") then
            return DemoOffer(name,reason,mana,gates)
        end
        return false
    end
    if s.healthfunnel and petUp and stationary then offer("Health Funnel","pet recovery",{
        DemoGate("health","pet",petHP,DemoSetting(s,"healthFunnelPetHP",40,10,80),true,true),
        DemoGate("health","player",hp,DemoSetting(s,"healthFunnelMinPlayerHP",60,20,100),false,true)}) end
    if not inCombat and s.armor and stationary and not DemoSelfActive("Demon Armor") and not DemoSelfActive("Demon Skin") then
        local armor=DemoOk("Demon Armor") and "Demon Armor" or DemoOk("Demon Skin") and "Demon Skin" or nil
        offer(armor,"maintain own armor")
    end
    AffPetPreparation(s,inCombat,petUp,mana)
    if not inCombat then
        if s.lifetap then offer("Life Tap","out-of-combat mana",{
            DemoGate("power","player",mana,DemoSetting(s,"lifeTapMana",25,5,95),true,true),
            DemoGate("health","player",hp,80,false,true)}) end
        if s.drink then DemoAdd(nil,"Drink",{DemoGate("power","player",mana,30,true,true)}) end
    end
    if hostile then
        local aboveShoot=true
        if AL.WandEquipped() then
            aboveShoot=DemoGate("power","player",mana,math.max(10,DemoSetting(s,"shootMana",25,5,95)),false,true)
        end
        if ShadowBoltOutOfMana() then aboveShoot=false end
        local ttd=DemoTTD()
        local fastImmolate=(AffCastSeconds("Immolate") or math.huge)<=1.5
        if inCombat and s.fear and AL.TargetInMelee() and not AffDotActive("Fear",casting) then
            offer("Fear","create space",{DemoGate("health","player",hp,45,true,true)})
        end
        if inCombat and s.affFinishers and ttd then
            local shards=SoulShardCount();local reserve=s.drainsoul and DemoSetting(s,"drainSoulMinShards",1,1,5) or 0
            if ttd<=1.5 and shards and shards>reserve then offer("Shadowburn","confirmed short-fight finisher",{aboveShoot}) end
            local castTime=AffCastSeconds("Searing Pain")
            if ttd<=3.5 and fastImmolate and castTime and castTime<=ttd then
                offer("Searing Pain","confirmed short-fight finisher",{aboveShoot})
            end
        end
        local curse=M.SelectedCurse(s);local activeCurse
        for _,choice in ipairs(CURSE_CHOICES)do if AffDotActive(choice.spell,casting) then activeCurse=true;break end end
        if curse and not activeCurse then offer(curse,"selected curse") end
        if inCombat and s.affNightfall and s.shadowBolt~=false and casting~="Shadow Bolt" and DemoSelfActive("Shadow Trance") then
            -- Only a positively observed proc permits a moving Shadow Bolt.
            DemoOffer("Shadow Bolt","Nightfall: confirmed Shadow Trance",mana,{aboveShoot})
        end
        local doom=AffDotActive("Bane of Doom",casting)
        local agony=AffDotActive("Bane of Agony",casting) or AffDotActive("Curse of Agony",casting)
        if s.affDoom and not doom and not agony and ttd and ttd>=60 then offer("Bane of Doom","confirmed long fight") end
        if inCombat and AL.burst then
            -- Offer Amplify before the missing Agony; it cannot leak into
            -- Burst Off, normal pet preparation, or an active Doom/Agony.
            AffBurst(s,mana,targetHP,aboveShoot,casting,agony,doom)
        end
        if s.agony and not doom and not agony then offer(AgonySpell(),"maintain Bane of Agony") end
        if s.immolate and (s.affFastImmolate==false or fastImmolate) and not AffDotActive("Immolate",casting) then
            offer("Immolate","maintain fast Immolate")
        end
        if s.corruption~=false and not AffDotActive("Corruption",casting) then offer("Corruption","maintain Corruption") end
        if s.siphonLife~=false and not AffDotActive("Siphon Life",casting) then offer("Siphon Life","maintain learned Siphon Life") end
        -- Keep the maintained DoTs ahead of area channels in Affliction.
        if inCombat then DemoAoE(s,mana,hp,aboveShoot) end
        local deficit,shards,minimum=SoulShardDeficit(s)
        if deficit then
            if stationary then offer("Drain Soul","Soul Shards "..tostring(shards).."/"..tostring(minimum)) end
            DemoAdd(nil,"Soul Shard deficit")
        end
        if s.lifetap then offer("Life Tap","mana recovery",{aboveShoot,
            DemoGate("power","player",mana,DemoSetting(s,"lifeTapMana",25,5,95),true,true),
            DemoGate("health","player",hp,60,false,true)}) end
        offer("Drain Life","sustain",{aboveShoot,DemoGate("health","player",hp,70,true,true)})
        if s.affWrack and agony and AffDotActive("Corruption",casting) and (not ttd or ttd>=6) then
            offer("Wrack","optional learned Affliction channel",{aboveShoot})
        end
        if s.shadowBolt~=false then offer("Shadow Bolt","Affliction filler",{aboveShoot}) end
        if AL.WandEquipped() then DemoOffer("Shoot","mana protection / filler fallback",mana) end
        DemoAdd(AL.known.Attack and "Attack" or nil,"melee fallback")
    end
    DemoAdd(nil,inCombat and not hostile and "No target" or "Ready")
    local base=demoDecision.actions[#demoDecision.actions]
    demoDecision.baseSpell,demoDecision.baseReason=base.spell,base.reason
    return base.spell,base.reason
end

-- Shadow and Flame 11/11/29 has independent choices and shares the proven
-- resource/DoT tracker. Its normal rotation has no consumable or burst action.
local function DestPetPreparation(s,inCombat,petUp,mana)
    if inCombat or not s.pet or not PlayerStationary() then return end
    if s.destImpSacrifice and DemoOk("Demonic Sacrifice") and DemoOk("Summon Imp") then
        if DemoSelfActive("Burning Shadow") then return end
        local kind=petUp and DemoPetType()
        if kind=="Imp" then
            DemoOffer("Demonic Sacrifice","Destruction: prepare own Burning Shadow",mana)
        elseif not petUp or kind then
            DemoOffer("Summon Imp","Destruction: prepare Imp sacrifice",mana)
        end
        return -- An unidentified living pet is kept.
    end
    AffPetPreparation(s,false,petUp,mana)
end
local function DestImmolate()
    local now=GetTime();local state=demoDots.Immolate
    if state and state.target==DemoTargetKey() and now-state.at<0.5 then return state.expires>now,state.expires end
    local active,expires=DemoReadAura("target","Immolate",true)
    if active~=nil then
        if active and not expires and state and state.target==DemoTargetKey() then expires=state.expires end
        return active,expires
    end
    if state and state.target==DemoTargetKey() then return state.expires>now,state.expires end
    return false
end
local function DestConflagrateAllowed()
    local active,expires=DestImmolate()
    if not active then return false end
    if DestructionTalentRank()==5 then return true end
    -- Partial or unknown rank cannot promise preservation. Wait for the last
    -- two seconds of an observed or successfully applied own Immolate.
    return expires~=nil and expires>GetTime() and expires-GetTime()<=2
end
local function DestBurst(s,mana,hp,aboveShoot,ttd,shards,reserve)
    if not AL.burst then return end
    local gates={aboveShoot,
        DemoGate("power","player",mana,DemoSetting(s,"destBurstMinMana",35,0,100),false,false),
        DemoGate("health","target",hp,DemoSetting(s,"destBurstMinTargetHP",40,0,100),false,false)}
    if s.destEureka and not DemoSelfActive("Eureka!") then
        local direct=s.destConflagrate and DestConflagrateAllowed() and DemoReady("Conflagrate") and "Conflagrate"
            or s.destShadowburn and shards and shards>reserve and DemoReady("Shadowburn") and "Shadowburn"
            or PlayerStationary() and s.shadowBolt~=false and DemoReady("Shadow Bolt") and "Shadow Bolt" or nil
        if direct and DemoInRange(direct)~=false then
            local usable,shortage=DemoUsable(direct)
            if usable~=false and shortage~=true then
                DemoOffer("Eureka!","Destruction Burst: direct damage",mana,
                    {gates[1],gates[2],gates[3],DemoManaCostGate(SpellManaCost(direct),mana)})
            end
        end
    end
    if s.destRacials then
        DemoOffer("Blood Fury","Destruction Burst racial",mana,gates)
        DemoOffer("Berserking","Destruction Burst racial",mana,gates)
    end
    if s.destDeathCoil then DemoOffer("Death Coil","Destruction Burst: optional damage and healing",mana,gates) end
    local seconds=AffCastSeconds("Soul Fire")
    if s.destSoulFire and PlayerStationary() and shards and shards>reserve
        and seconds and seconds>0 and ttd and ttd>=math.max(1.5,seconds) then
        DemoOffer("Soul Fire","Destruction Burst: optional learned cast",mana,gates)
    end
end

local function NextDestruction(s,inCombat,hostile)
    if not inCombat then demoCurveFailures={} end
    demoDecision={at=GetTime(),actions={}}
    DestructionTalentRank()
    local trackedMana=WarlockManaPercent();local mana=ReadManaPercent(ManaMaximum())
    if mana==nil and not DemoCurveAvailable("power","player") then mana=trackedMana end
    local hp,petHP,targetHP=DemoHealth("player"),DemoHealth("pet"),hostile and DemoHealth("target") or nil
    local petUp=DemoBool((SafeCall(UnitExists,"pet")))==true and DemoBool((SafeCall(UnitIsDeadOrGhost,"pet")))~=true
    local casting=ReadableString(PlayerCastingSpell())
    local channel=SafeCall(UnitChannelInfo,"player")
    if not DemoSafe(channel) or channel~=nil and channel~="" then return nil,"Channeling" end
    local duration=SafeCall(UnitChannelDuration,"player")
    if DemoSafe(duration) and (type(duration)=="table" or type(duration)=="userdata") then return nil,"Channeling" end
    if casting and casting~="Immolate" and casting~="Corruption" then return nil,"Casting" end
    if not casting then
        local name=SafeCall(UnitCastingInfo,"player")
        if not DemoSafe(name) then return nil,"Casting" end
        duration=SafeCall(UnitCastingDuration,"player")
        if DemoSafe(duration) and (type(duration)=="table" or type(duration)=="userdata") then return nil,"Casting" end
    end
    local stationary=PlayerStationary()
    local function offer(name,reason,gates)
        if stationary or name=="Conflagrate" or AffInstant(name) or name and name:find("^Curse of ") then
            return DemoOffer(name,reason,mana,gates)
        end
        return false
    end
    if s.healthfunnel and petUp and stationary then offer("Health Funnel","pet recovery",{
        DemoGate("health","pet",petHP,DemoSetting(s,"healthFunnelPetHP",40,10,80),true,true),
        DemoGate("health","player",hp,DemoSetting(s,"healthFunnelMinPlayerHP",60,20,100),false,true)}) end
    if not inCombat and s.armor and stationary and not DemoSelfActive("Demon Armor") and not DemoSelfActive("Demon Skin") then
        offer(DemoOk("Demon Armor") and "Demon Armor" or DemoOk("Demon Skin") and "Demon Skin" or nil,"maintain own armor")
    end
    DestPetPreparation(s,inCombat,petUp,mana)
    if not inCombat then
        if s.lifetap then offer("Life Tap","out-of-combat mana",{
            DemoGate("power","player",mana,DemoSetting(s,"lifeTapMana",25,5,95),true,true),
            DemoGate("health","player",hp,80,false,true)}) end
        if s.drink then DemoAdd(nil,"Drink",{DemoGate("power","player",mana,30,true,true)}) end
    end
    if hostile then
        local aboveShoot=true
        if AL.WandEquipped() then
            aboveShoot=DemoGate("power","player",mana,math.max(10,DemoSetting(s,"shootMana",25,5,95)),false,true)
        end
        if ShadowBoltOutOfMana() then aboveShoot=false end
        local ttd,shards=DemoTTD(),SoulShardCount()
        local reserve=s.drainsoul and DemoSetting(s,"drainSoulMinShards",1,1,5) or 0
        if inCombat and s.fear and AL.TargetInMelee() and not AffDotActive("Fear",casting) then
            offer("Fear","create space",{DemoGate("health","player",hp,45,true,true)})
        end
        if inCombat and s.destFinishers and ttd then
            if s.destShadowburn and ttd<=1.5 and shards and shards>reserve then
                offer("Shadowburn","Destruction: confirmed short-fight finisher",{aboveShoot})
            end
            local seconds=AffCastSeconds("Searing Pain")
            if ttd<=3.5 and seconds and seconds>0 and seconds<=ttd then
                offer("Searing Pain","Destruction: confirmed short-fight finisher",{aboveShoot})
            end
        end
        local curse=M.SelectedCurse(s);local activeCurse
        for _,choice in ipairs(CURSE_CHOICES)do if AffDotActive(choice.spell,casting) then activeCurse=true;break end end
        if curse and not activeCurse then offer(curse,"selected curse") end
        local doom=AffDotActive("Bane of Doom",casting)
        local agony=AffDotActive("Bane of Agony",casting) or AffDotActive("Curse of Agony",casting)
        if s.destDoom and not doom and not agony and ttd and ttd>=60 then offer("Bane of Doom","confirmed long fight") end
        if s.agony and not doom and not agony then offer(AgonySpell(),"Destruction: maintain Bane of Agony") end
        if s.corruption~=false and not AffDotActive("Corruption",casting) then offer("Corruption","Destruction: maintain Corruption") end
        if s.immolate and not AffDotActive("Immolate",casting) then offer("Immolate","Destruction: maintain Immolate") end
        if s.siphonLife~=false and not AffDotActive("Siphon Life",casting) then offer("Siphon Life","maintain learned Siphon Life") end
        -- AoE owns only this branch, and only with AoE On at the spell icon.
        if inCombat then DemoAoE(s,mana,hp,aboveShoot) end
        local deficit,_,minimum=SoulShardDeficit(s)
        if deficit then
            if stationary then offer("Drain Soul","Soul Shards "..tostring(shards).."/"..tostring(minimum)) end
            DemoAdd(nil,"Soul Shard deficit")
        end
        if inCombat then DestBurst(s,mana,targetHP,aboveShoot,ttd,shards,reserve) end
        if s.destConflagrate and DestConflagrateAllowed() then offer("Conflagrate","Destruction: own Immolate applied",{aboveShoot}) end
        if s.destShadowburn and shards and shards>reserve then offer("Shadowburn","Destruction: learned cooldown",{aboveShoot}) end
        if inCombat and s.lifetap then offer("Life Tap","mana recovery",{aboveShoot,
            DemoGate("power","player",mana,DemoSetting(s,"lifeTapMana",25,5,95),true,true),
            DemoGate("health","player",hp,60,false,true)}) end
        offer("Drain Life","sustain",{aboveShoot,DemoGate("health","player",hp,70,true,true)})
        if s.shadowBolt~=false then offer("Shadow Bolt","Destruction filler",{aboveShoot}) end
        if AL.WandEquipped() then DemoOffer("Shoot","mana protection / filler fallback",mana) end
        DemoAdd(AL.known.Attack and "Attack" or nil,"melee fallback")
    end
    DemoAdd(nil,inCombat and not hostile and "No target" or "Ready")
    local base=demoDecision.actions[#demoDecision.actions]
    demoDecision.baseSpell,demoDecision.baseReason=base.spell,base.reason
    return base.spell,base.reason
end

local function NextLeveling(s, inCombat, hostile)
	local myHp = AL.HealthPercent("player")
	local manaPct = WarlockManaPercent()
	local petUp = UnitExists("pet") and not UnitIsDeadOrGhost("pet")
	local petHp = petUp and AL.HealthPercent("pet") or nil
	local targetHp = hostile and AL.HealthPercent("target") or nil
	local casting = PlayerCastingSpell()
	local lifeTapMana = tonumber(s.lifeTapMana) or 25
	local shootMana = tonumber(s.shootMana) or 25
	local forceShoot, readableShootMana, effectiveShootThreshold, configuredShootMana, shootReason =
		ShootState(s, manaPct)

	-- Core normally intercepts every active channel and returns the global
	-- no-action/pooling state before this rotation runs. Keep this local fallback
	-- for Warlock in case the class function is called directly.
	if casting == "Health Funnel" or casting == "Drain Soul"
		or casting == "Drain Life" or casting == "Drain Mana"
		or casting == "Rain of Fire"
	then
		return nil, "Channeling"
	end

	-- Pet recovery: learned/enabled, pet below threshold, player safely above
	-- threshold, and player confirmed stationary.
	local funnelPetHP = tonumber(s.healthFunnelPetHP) or 40
	local funnelPlayerHP = tonumber(s.healthFunnelMinPlayerHP) or 60
	if s.healthfunnel
		and petUp
		and petHp and petHp < funnelPetHP
		and myHp and myHp > funnelPlayerHP
		and PlayerStationary()
		and AL.Ok("Health Funnel")
		and AL.SpellUsable("Health Funnel")
	then
		return "Health Funnel", "pet below " .. tostring(funnelPetHP) .. "%"
	end

	if not inCombat then
		if s.armor then
			local armor = BestArmor()
			if armor and not AL.HasBuff("player", "Demon Armor") and not AL.HasBuff("player", "Demon Skin") then
				return armor, "buff"
			end
		end
		if s.pet and not petUp then
			local shards = AL.ItemCount(SOUL_SHARD)
			if AL.Ok("Summon Voidwalker") and (not shards or shards > 0) then
				return "Summon Voidwalker", "pet"
			end
			if AL.Ok("Summon Imp") then return "Summon Imp", "pet" end
		end
		-- Life Tap out of combat uses the same configured mana threshold.
		-- Keep the higher OOC health safety margin before trading HP for mana.
		if s.lifetap and manaPct and manaPct < lifeTapMana
			and myHp and myHp > 80
			and AL.Ok("Life Tap")
		then
			return "Life Tap", "mana below " .. tostring(lifeTapMana) .. "%"
		end
		if s.drink then
			if manaPct and manaPct < 30 then return nil, "Drink" end
		end
		if hostile then
			local curse, curseReason = NextCurse(s, casting)
			if curse then return curse, curseReason end
			-- A DoT being cast is already committed even though its debuff has not
			-- landed yet. Advance the icon to the next priority immediately.
			local nextSpell, reason = AfterCastingDot(casting, s, targetHp)
			if nextSpell then return nextSpell, reason end

			local dot, dotReason = NextDot(s, casting, targetHp)
			if dot then return dot, dotReason end

			-- Never use Shadow Bolt as an opener while the readable Soul Shard
			-- count is below the configured minimum.
			local deficit, shards, minimumShards = SoulShardDeficit(s)
			if deficit then
				if AL.Ok("Drain Soul") then
					return "Drain Soul", "Soul Shards " .. tostring(shards) .. "/" .. tostring(minimumShards)
				end
				return nil, "Soul Shard deficit " .. tostring(shards) .. "/" .. tostring(minimumShards)
			end

			local openerForceShoot, _, _, _, openerShootReason = ShootState(s, manaPct)
			if openerForceShoot then
				if AL.WandEquipped() and AL.Ok("Shoot") then
					return "Shoot", openerShootReason or "Shoot opener"
				end
				return nil, "Shadow Bolt blocked: " .. tostring(openerShootReason or "mana")
			end

			if s.shadowBolt ~= false and AL.Ok("Shadow Bolt") and AL.SpellUsable("Shadow Bolt") then
				return "Shadow Bolt", "opener"
			end
			if AL.WandEquipped() and AL.Ok("Shoot") then
				return "Shoot", "Shadow Bolt unavailable"
			end
			return nil, "opener"
		end
		return nil, "Ready"
	end

	if not hostile then return nil, "No target" end

	-- In-combat movement override. While the player is positively detected as
	-- moving, recommend wand Shoot instead of cast-time/channel priorities.
	-- Core's global channel pool happens before this rotation, so an active
	-- channel still remains protected and cannot be replaced by Shoot.
	if PlayerMoving()
		and AL.WandEquipped()
		and AL.Ok("Shoot")
	then
		return "Shoot", "moving"
	end

	if s.fear and casting ~= "Fear" and AL.Ok("Fear")
		and AL.TargetInMelee() and myHp and myHp < 45
		and not DotUp("Fear", casting)
	then
		return "Fear", "create space"
	end
	if AL.burst then
		if AL.OkReady("Blood Fury") then return "Blood Fury", "burst" end
		if AL.OkReady("Berserking") then return "Berserking", "burst" end
	end

	local curse, curseReason = NextCurse(s, casting)
	if curse then return curse, curseReason end

	-- Area damage is separate from the normal single-target DoT/filler path.
	if AL.DPS60 and AL.DPS60.Active() and s.aoe and s.rainOfFire ~= false and not forceShoot and PlayerStationary()
		and type(manaPct) == "number" and manaPct >= (tonumber(s.aoeMinMana) or 30) then
		local enemies = AL.DPS60.EnemyCount(30)
		if type(enemies) == "number" and not (issecretvalue and issecretvalue(enemies))
			and enemies >= (tonumber(s.aoeMinEnemies) or 3) and AL.DPS60.Ready("Rain of Fire")
			and AL.SpellUsable("Rain of Fire") and AL.InRange("Rain of Fire") ~= false then
			return "Rain of Fire", "AoE damage"
		end
	end

	-- If any maintained DoT is already being cast, move the recommendation to
	-- the next priority instead of showing the same DoT a second time.
	do
		local nextSpell, reason = AfterCastingDot(casting, s, targetHp)
		if nextSpell then return nextSpell, reason end
	end

	local dot, dotReason = NextDot(s, casting, targetHp)
	if dot then return dot, dotReason end

	-- Soul Shard builder comes after the maintained DoT package. The bag-count
	-- comparison is the authority: if detected shards are below the slider value,
	-- Drain Soul replaces every normal filler, including Shadow Bolt.
	do
		local deficit, shards, minimumShards = SoulShardDeficit(s)
		if deficit then
			if AL.Ok("Drain Soul") then
				return "Drain Soul", "Soul Shards " .. tostring(shards) .. "/" .. tostring(minimumShards)
			end
			-- Important: do not fall through to Shadow Bolt if the shard deficit is
			-- known but Drain Soul cannot currently be confirmed by the spellbook.
			return nil, "Soul Shard deficit " .. tostring(shards) .. "/" .. tostring(minimumShards)
		end
	end
	-- HARD SHOOT STATE:
	-- DoTs and Drain Soul are above this point. Once filler is reached, Shoot
	-- completely replaces Shadow Bolt whenever mana is at/below the slider,
	-- at/below the hard 10% floor, unreadable, or Shadow Bolt reports no mana.
	-- This reserve applies only while a wand is equipped.
	if forceShoot then
		if AL.WandEquipped() and AL.Ok("Shoot") then
			return "Shoot", shootReason or "Shoot mode"
		end
		return nil, "Shadow Bolt blocked: " .. tostring(shootReason or "Shoot mode")
	end

	-- Life Tap remains independent, but only after ShootState has positively
	-- established that mana is above the Shoot threshold.
	if s.lifetap and manaPct and manaPct < lifeTapMana
		and myHp and myHp > 60
		and AL.Ok("Life Tap")
	then
		return "Life Tap", "mana below " .. tostring(lifeTapMana) .. "%"
	end

	if myHp and myHp < 70 and AL.Ok("Drain Life") and AL.SpellUsable("Drain Life") then
		return "Drain Life", "sustain"
	end

	-- Absolute final interlock immediately before Shadow Bolt. Re-read mana so
	-- no earlier stale value can authorize the filler.
	do
		local finalMana = WarlockManaPercent()
		local blockShadow, _, _, _, finalReason = ShootState(s, finalMana)
		if blockShadow then
			if AL.WandEquipped() and AL.Ok("Shoot") then
				return "Shoot", finalReason or "Shoot mode"
			end
			return nil, "Shadow Bolt blocked: " .. tostring(finalReason or "Shoot mode")
		end
	end

    if AL.DPS60 and AL.DPS60.Active() then
        local build = AL.DPS60.Build("WARLOCK", s, "AFFLICTION")
        if build == "DESTRUCTION" then
            if AL.DPS60.Ready("Conflagrate") and AL.SpellUsable("Conflagrate") and DotUp("Immolate", casting) then
                return "Conflagrate", "Destruction priority"
            end
        end
        if targetHp and targetHp <= 20 then
            local shards = SoulShardCount()
            local minimum = s.drainsoul and math.max(1, math.floor(tonumber(s.drainSoulMinShards) or 1)) or 0
            if build == "DESTRUCTION" and type(shards) == "number" and shards > minimum
                and AL.DPS60.Ready("Shadowburn") and AL.SpellUsable("Shadowburn") then return "Shadowburn", "short-fight finisher" end
            if AL.DPS60.Ready("Searing Pain") and AL.SpellUsable("Searing Pain") then return "Searing Pain", "short cast to finish" end
        end
    end
	if s.shadowBolt ~= false and AL.Ok("Shadow Bolt") and AL.SpellUsable("Shadow Bolt") then
		return "Shadow Bolt", "filler"
	end

	-- Original unconditional wand fallback: if normal filler cannot be used for
	-- any reason, show Shoot regardless of the slider.
	if AL.WandEquipped() and AL.Ok("Shoot") then
		return "Shoot", "Shadow Bolt unavailable"
	end

	return AL.known["Attack"] and "Attack" or nil, "melee"
end

function M.BuildOptions(page, ui)
	local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h:SetPoint("TOP", 0, -30)
	h:SetText("Rotation hints:")
	ui.SettingCheck(page, 70, -52, "Demon Armor upkeep", "armor")
	ui.SettingCheck(page, 70, -78, "Summon pet", "pet")
	ui.SettingCheck(page, 70, -104, "Immolate", "immolate")
	ui.SettingCheck(page, 70, -130, "Bane/Curse of Agony", "agony")
	ui.SettingCheck(page, 290, -52, "Life Tap", "lifetap")
	ui.SettingCheck(page, 290, -78, "Drain Soul for Soul Shard", "drainsoul")
	ui.SettingCheck(page, 290, -104, "Fear at melee", "fear")
	ui.SettingCheck(page, 290, -130, "Drink reminder", "drink")
end

local function IntervalCurve(low, high)
	local key = tostring(low) .. ":" .. tostring(high)
	if demoVisibilityCurves[key] then return demoVisibilityCurves[key] end
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1)
	if low > 1 or high <= 0 or high <= low then
		-- A strict >100% safety threshold is empty, including protected values.
		curve:AddPoint(0, CreateColor(1, 1, 1, 0))
		curve:AddPoint(1, CreateColor(1, 1, 1, 0))
		demoVisibilityCurves[key] = curve
		return curve
	end
	curve:AddPoint(0, CreateColor(1, 1, 1, low == 0 and 1 or 0))
	if low > 0 then curve:AddPoint(low, CreateColor(1, 1, 1, 1)) end
	if high <= 1 then curve:AddPoint(high, CreateColor(1, 1, 1, 0)) end
	if low ~= 1 and high ~= 1 then curve:AddPoint(1, CreateColor(1, 1, 1, high > 1 and 1 or 0)) end
	demoVisibilityCurves[key] = curve
	return curve
end

function M.SecretVisualPlan(spell, reason)
	local d = demoDecision
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
				demoCurveFailures[mask.kind .. ":" .. mask.unit] = mask.kind == "power" and UnitPowerPercent or UnitHealthPercent
				error("Warlock resource curve unavailable")
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



local legacyTrackSuggestion = M.CanTrackSuggestedSpell
function M.CanTrackSuggestedSpell(name,s)
    if s and (s.destruction or s.demonology or s.affliction) and demoDecision and demoDecision.visualCandidate then return false end
    return legacyTrackSuggestion(name,s)
end
function M.OnTargetChanged()
    demoDecision, AL.rotationSecretVisual = nil, nil
end
function M.NextSpell(s,inCombat,hostile)
    M.NormalizeBuild(s)
    if s.destruction==true then return NextDestruction(s,inCombat,hostile) end
    if s.affliction==true then return NextAffliction(s,inCombat,hostile) end
    if s.demonology==true then return NextDemonology(s,inCombat,hostile) end
    demoDecision=nil
    return NextLeveling(s,inCombat,hostile)
end
if AL.selfCastSpells then
    for name in pairs(demoSelfSpells)do AL.selfCastSpells[name]=true end
end

AL.RegisterRotation("WARLOCK", M)
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
    root.RegisterRotation("WARLOCK", advanced)
end
