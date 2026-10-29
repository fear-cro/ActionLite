local _, AL = ...
local C = { version = "1.0.0", returns = {}, structures = {} }
AL.ActionLiteDebug.Catalog = C

-- Forever diagnostics: getters used by the current addon and their legacy
-- counterparts. Presence is checked at runtime; missing APIs are never called.
-- No retail expansion, restricted-action, empowered-cast or retail-class scans.
C.globals = {
    "InCombatLockdown", "GetTime", "GetFramerate", "GetNetStats", "GetManaRegen", "GetPowerRegen",
    "GetComboPoints", "GetShapeshiftForm", "GetWeaponEnchantInfo", "GetNumGroupMembers", "IsMounted",
}
C.unit = {
    "UnitExists", "UnitGUID", "UnitLevel", "UnitClassification", "UnitCreatureType", "UnitCreatureFamily",
    "UnitAffectingCombat", "UnitIsDeadOrGhost", "UnitPowerType", "UnitHealth", "UnitHealthMax",
    "UnitHealthPercent", "UnitCastingInfo", "UnitChannelInfo", "UnitAttackSpeed", "UnitRangedDamage", "GetUnitSpeed",
}
C.spell = {
    "C_Spell.GetSpellInfo", "C_Spell.GetSpellPowerCost", "C_Spell.GetSpellCooldown",
    "C_Spell.IsSpellUsable", "C_Spell.IsCurrentSpell", "C_Spell.IsAutoRepeatSpell",
    "C_Spell.GetSpellBaseCooldown", "C_SpellBook.IsSpellKnown",
    "GetSpellCooldown", "IsUsableSpell", "IsCurrentSpell", "IsAutoRepeatSpell", "IsPlayerSpell", "IsSpellKnown",
}
C.references = {}
local listed = {}
local function Reference(name)
    if not listed[name] then listed[name] = true; C.references[#C.references + 1] = name end
end
for _, list in ipairs({ C.globals, C.unit, C.spell, {
    "GetBuildInfo", "GetLocale", "GetServerTime", "GetPhysicalScreenSize", "UnitClass", "UnitRace",
    "UnitCanAttack", "UnitIsUnit", "UnitIsFriend", "UnitPower", "UnitPowerMax", "UnitPowerPercent",
    "CheckInteractDistance", "UnitThreatSituation", "UnitDetailedThreatSituation", "GetTotemInfo",
    "GetActionInfo", "GetActionCooldown", "IsActionInRange", "IsUsableAction", "GetBindingKey",
    "GetMacroSpell", "GetInventoryItemID", "GetItemCount", "C_Item.GetItemCount",
    "C_Spell.GetSpellName", "C_Spell.GetSpellTexture", "C_Spell.GetSpellDescription",
    "C_Spell.IsSpellInRange", "IsSpellInRange", "UnitBuff", "UnitDebuff", "UnitAura",
    "C_UnitAuras.GetAuraDataByIndex", "GetSpellBookItemName", "GetSpellBookItemInfo",
    "C_SpellBook.GetSpellBookItemName", "C_SpellBook.GetSpellBookItemInfo",
    "GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo",
    "C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetSpecializationInfo",
    "C_NamePlate.GetNamePlates", "C_NamePlate.GetNamePlateForUnit", "C_CurveUtil.CreateColorCurve",
    "CombatLogGetCurrentEventInfo", "issecretvalue", "canaccessvalue", "canaccesstable",
} }) do for _, name in ipairs(list) do Reference(name) end end
table.sort(C.references)

local function Structure(name, fields)
    local result = {}
    for field in fields:gmatch("%S+") do result[#result + 1] = { Name = field } end
    C.structures[name] = result
end
Structure("AuraData", "name icon applications dispelName duration expirationTime sourceUnit spellId auraInstanceID isBossAura isFromPlayerOrPlayerPet isHelpful isHarmful points")
Structure("SpellCooldownInfo", "startTime duration isEnabled isActive modRate activeCategory timeUntilEndOfStartRecovery isOnGCD")
Structure("SpellInfo", "name iconID originalIconID castTime minRange maxRange spellID")
Structure("SpellPowerCostInfo", "type name cost minCost costPercent costPerSec requiredAuraID hasRequiredAura")
Structure("SpellBookItemInfo", "itemType spellID actionID name isPassive isOffSpec")
C.returns["C_Spell.GetSpellCooldown"] = { returns = {{ Name = "cooldown", Type = "SpellCooldownInfo" }} }
C.returns["C_Spell.GetSpellInfo"] = { returns = {{ Name = "spell", Type = "SpellInfo" }} }
C.returns["C_Spell.GetSpellPowerCost"] = { returns = {{ Name = "costs", InnerType = "SpellPowerCostInfo" }} }
C.returns["C_UnitAuras.GetAuraDataByIndex"] = { returns = {{ Name = "aura", Type = "AuraData" }} }
C.returns["C_SpellBook.GetSpellBookItemInfo"] = { returns = {{ Name = "item", Type = "SpellBookItemInfo" }} }
