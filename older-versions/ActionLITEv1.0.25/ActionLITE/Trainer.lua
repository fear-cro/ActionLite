local ADDON, AL = ...
local L = AL.L

-- ============================================================================
-- ActionLITE - Trainer.lua
-- ----------------------------------------------------------------------------
-- Manual report of spells and ranks available from the class trainer.
-- ============================================================================

local function Level(v)
	if type(v) == "number" and not (issecretvalue and issecretvalue(v)) and v > 0 then return v end
end

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	return ok and Level(v) or nil
end

local function BookLevel(entry)
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	local api = C_SpellBook and C_SpellBook.GetSpellBookItemLevelLearned
	local spellApi = C_Spell and C_Spell.GetSpellLevelLearned
	return Try(GetSpellAvailableLevel, entry.index, BOOKTYPE_SPELL or "spell")
		or (bank and Try(api, entry.index, bank))
		or (entry.id and (Try(spellApi, entry.id) or Try(GetSpellLevelLearned, entry.id)))
end

-- classic reference levels: a guess for a new spell, never for a new rank
local function ReferenceLevel(name)
	local mod = AL.rotations[AL.playerClass]
	return mod and mod.minLevels and Level(mod.minLevels[name])
end

local function SortedNames(levels)
	local out = {}
	for name in pairs(levels) do out[#out + 1] = name end
	table.sort(out, function(a, b)
		if levels[a] ~= levels[b] then return levels[a] < levels[b] end
		return a < b
	end)
	return out
end

-- Returns two sorted lists: new spells, and new ranks of spells already known.
function AL.TrainableSpells(playerLevel)
	local spells, ranks = {}, {}
	if not Level(playerLevel) then return {}, {} end
	for _, entry in ipairs(AL.futureSpells or {}) do
		local rank = AL.known[entry.name]
		local lvl = BookLevel(entry) or (not rank and ReferenceLevel(entry.name))
		local into = rank and ranks or spells
		if lvl and lvl <= playerLevel and (not into[entry.name] or lvl < into[entry.name]) then
			into[entry.name] = lvl
		end
	end
	for name in pairs(AL.unlearned or {}) do
		local lvl = ReferenceLevel(name)
		if lvl and lvl <= playerLevel and not spells[name] then spells[name] = lvl end
	end
	return SortedNames(spells), SortedNames(ranks)
end

function AL.ReportTrainable(playerLevel, quietWhenEmpty)
	local spells, ranks = AL.TrainableSpells(playerLevel)
	if #spells > 0 then AL.Say(L("TRAIN_NEW", "|cffffcc00" .. table.concat(spells, ", ") .. "|r")) end
	if #ranks > 0 then AL.Say(L("TRAIN_RANKS", "|cffffcc00" .. table.concat(ranks, ", ") .. "|r")) end
	if #spells == 0 and #ranks == 0 and not quietWhenEmpty then AL.Say(L("TRAIN_NONE")) end
end
