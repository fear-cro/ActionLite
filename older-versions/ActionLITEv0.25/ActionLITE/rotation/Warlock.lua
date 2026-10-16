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
