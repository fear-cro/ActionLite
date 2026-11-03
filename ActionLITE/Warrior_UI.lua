local ADDON, AL = ...
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
local UI_VERSION = "0.10.7"
local L = AL.L

-- ============================================================================
-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- ActionLITE - Warrior_UI.lua - v0.10.7
-- ----------------------------------------------------------------------------
-- Warrior options page with a compact two-column layout.
-- No combat rules here: all displayed values come from
-- rotation\Warrior.lua through M.GetUIState(), so the interface can
-- never diverge from the rotation.
--
-- The page is built once. Live updates only
-- rewrite badge text; they never rebuild frames.
--
-- Page convention: each option with half = true takes up
-- half the width and pairs with the next option. Labels stay short;
-- details go in the tooltip.
-- ============================================================================

local function BuildWarriorUI(page, ui)
	local thresholdHelp = "Requires the selected Rage amount, even when Forever hides the number. "
		.. "If the threshold cannot be checked, this optional spell waits while other abilities continue."
	local rotation = AL.rotations and AL.rotations.WARRIOR
	if rotation and rotation.NormalizeBuild then rotation.NormalizeBuild(ui.Profile()) end
	if rotation and rotation.InitializeProtectionSettings then
		rotation.InitializeProtectionSettings(ui.Profile())
	end
	local THEME = ui.Theme
	local stack = ui.Body(page)
	local spellIDs = {}
	for _, entry in ipairs((rotation and rotation.spells) or {}) do
		spellIDs[entry[2]] = entry[1]
	end
	local function SpellIcon(name)
		return ui.SpellIcon(name, spellIDs[name])
	end

	local STEEL = THEME.textDim
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	local function DPSLevelingVisible(profile)
		return profile.leveling == true and profile.warriorRole ~= "TANK"
	end

	-- --------------------------------------------------------- role selection
	local levelingCard = ui.Card(stack, "LEVELING ROTATION", "Finalized leveling priorities", { id="levelingCard", build="leveling", group="damage" })
	ui.Check(levelingCard, {
		profileKey = "leveling", label = "Leveling Rotation", icon = SpellIcon("Heroic Strike"),
		get = function() return true end,
		set = function() rotation.SetBuild("leveling", true, ui.Profile()) end,
		onChange = ui.Repaint,
		tooltip = { "Leveling Rotation", "Uses the finalized leveling rotation and every learned spell that its controls enable. This is the only selectable Warrior rotation in this release." },
	})

	local role = ui.Card(stack, L("WARRIOR_ROLE"), L("WARRIOR_ROLE_HELP"), { id="role", build="leveling", group="preparation" })
	ui.StackDropdown(role, {
		caption = "Leveling role",
		options = {
			{ label = L("ROLE_DPS"), value = "DPS" },
			{ label = L("ROLE_TANK"), value = "TANK" },
		},
		get = function()
			return ui.Profile().warriorRole == "TANK" and "TANK" or "DPS"
		end,
		set = function(value)
			local profile = ui.Profile()
			profile.warriorRole = value == "TANK" and "TANK" or "DPS"
			profile.levelingWarriorRole = profile.warriorRole
			rotation.NormalizeBuild(profile)
		end,
		onSelect = ui.Repaint,
	})
	ui.Help(role, "Select the finalized DPS or Tank leveling priority. Both choices use only spells the character has actually learned.")

	-- ---------------------------------------------------------------- header
	local head = ui.Card(stack, L("LIVE_STATUS"), L("WARRIOR_PROFILE", UI_VERSION), { id="head", group="status", status=true })

	local rowA = ui.BadgeRow(head, 3)
	local rowB = ui.BadgeRow(head, 3)
	local badges = {
		level  = rowA.badges[1],
		rage   = rowA.badges[2],
		spells = rowA.badges[3],
		aoe    = rowB.badges[1],
		burst  = rowB.badges[2],
		state  = rowB.badges[3],
	}

	ui.Help(head, L("RAGE_PROTECTED"),
		{ height = 28, justify = "CENTER" })

	-- ------------------------------------------------------- basic rotation
	local core = ui.Card(stack, L("MAIN_ROTATION"), nil, { id="core", group="damage" })
	ui.SettingCheck(core, "shout", {
		label = "Battle Shout", icon = SpellIcon("Battle Shout"), half = true,
		tooltip = { "Battle Shout", L("BATTLE_SHOUT_HELP") },
	})
	ui.SettingCheck(core, "rend", {
		label = "Rend", icon = SpellIcon("Rend"), half = true,
		tooltip = { "Rend", L("REND_HELP") },
	})
	ui.SettingCheck(core, "sunder", {
		label = "Sunder Armor", icon = SpellIcon("Sunder Armor"), half = true,
		tooltip = { "Sunder Armor", L("SUNDER_HELP") },
	})
	ui.Check(core, {
		label = "Hamstring", icon = SpellIcon("Hamstring"), half = true,
		get = function() return ui.Profile().hamstring == true end,
		set = function(value) rotation.SetHamstring(value, ui.Profile()) end,
		tooltip = { "Hamstring", "Keep Hamstring applied to your current hostile target in combat when usable in your stance.",
			"Reapply only when missing or expired. Toggle macro: /alhamstring" },
	})

	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- These options are not consulted by the Tank Leveling priority.
	local dpsCore = ui.Card(stack, "DPS LEVELING SETTINGS", "DPS Leveling role only", { id="dps-core", build=DPSLevelingVisible, group="damage" })
	ui.SettingCheck(dpsCore, "slam", {
		label = L("SLAM_LABEL"), icon = SpellIcon("Slam"), half = true,
		tooltip = { "Slam", L("SLAM_HELP"), "Uses the live cooldown. If it becomes protected, the fallback respects the character's actual Improved Slam talent rank." },
	})
	ui.SettingCheck(dpsCore, "spear", {
		label = "Spearing Strike", icon = SpellIcon("Spearing Strike"), half = true,
		tooltip = { "Spearing Strike", L("SPEAR_HELP") },
	})
	ui.SettingCheck(dpsCore, "overpower", {
		label = "Overpower", icon = SpellIcon("Overpower"), half = true,
		tooltip = { "Overpower", L("OVERPOWER_HELP") },
	})
	ui.SettingCheck(dpsCore, "demo", {
		label = "Demoralizing Shout", icon = SpellIcon("Demoralizing Shout"), half = true,
		tooltip = { "Demoralizing Shout", L("DEMO_HELP") },
	})
	ui.Divider(dpsCore)
	ui.Slider(dpsCore, {
		label = L("SUNDER_STACKS"), half = true,
		min = 0, max = 5, step = 1,
		format = function(v) return tostring(v) .. "/5" end,
		get = function() return tonumber(ui.Profile().sunderMaxStacks) or 2 end,
		set = function(v) ui.Profile().sunderMaxStacks = v end,
		tooltip = {
			L("SUNDER_LIMIT"), L("SUNDER_ZERO"), L("SUNDER_ONE_FIVE"),
		},
	})
	ui.Slider(dpsCore, {
        profileKey="slamReserveRage",
		label = L("SLAM_RESERVE"), half = true,
		min = 15, max = 100, step = 5, suffix = " rage",
		get = function() return tonumber(ui.Profile().slamReserveRage) or 30 end,
		set = function(v) ui.Profile().slamReserveRage = v end,
		tooltip = { L("SLAM_RESERVE"), L("SLAM_RESERVE_HELP"), thresholdHelp },
	})
	ui.Slider(dpsCore, {
		profileKey="heroicDumpRage",
		label = L("HEROIC_THRESHOLD") .. " (DPS)",
		min = 15, max = 100, step = 5, suffix = " rage",
		get = function()
			local configured = tonumber(ui.Profile().heroicDumpRage)
			if configured then return configured end
			local state = (rotation and rotation.GetUIState and ui.State()) or {}
			return state.heroicDumpAt or 75
		end,
		set = function(v) ui.Profile().heroicDumpRage = v end,
		tooltip = {
			L("HEROIC_THRESHOLD_TITLE"), L("HEROIC_THRESHOLD_HELP"),
			L("HEROIC_AUTO"), thresholdHelp,
		},
	})

	-- ------------------------------------------------------ procs & finishers
	local procs = ui.Card(stack, L("PROCS_FINISHERS"), nil, { id="procs", group="damage" })
	ui.SettingCheck(procs, "victory", {
		label = "Victory Rush", icon = SpellIcon("Victory Rush"), half = true,
		tooltip = { "Victory Rush", L("VICTORY_HELP") },
	})
	ui.SettingCheck(procs, "execute", {
		label = "Execute", icon = SpellIcon("Execute"), half = true,
		tooltip = { "Execute", L("EXECUTE_HELP") },
	})

	-- ------------------------------------------------------- Rage management
	local rage = ui.Card(stack, L("RAGE_MANAGEMENT"), nil, { id="rage", group="resources" })
	ui.SettingCheck(rage, "bloodrage", {
		label = "Bloodrage", icon = SpellIcon("Bloodrage"), half = true,
		tooltip = { "Bloodrage", L("BLOODRAGE_HELP") },
	})
	ui.SettingCheck(rage, "heroic", {
		label = "Heroic Strike", icon = SpellIcon("Heroic Strike"), half = true,
		tooltip = { "Heroic Strike", L("HEROIC_HELP") },
	})
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	-- Talent actives remain in the one public Leveling profile. These controls do
	-- not infer a specialization: the rotation still requires the exact spell to
	-- be learned, ready, usable and valid for the current stance.
	local dpsLearned = ui.Card(stack, "LEARNED DPS ABILITIES", "DPS Leveling role only", { id="dps-learned", build=DPSLevelingVisible, group="damage" })
	ui.Help(dpsLearned, "Only abilities actually learned by this character can be suggested. Mortal Strike and Bloodthirst are checked independently; the rotation never guesses a talent build.")
	ui.SettingCheck(dpsLearned, "mortalStrike", {
		label = "Mortal Strike", icon = SpellIcon("Mortal Strike"), half = true,
		tooltip = { "Mortal Strike", "Use this learned primary strike in the DPS Leveling role when it is ready, usable and affordable." },
	})
	ui.SettingCheck(dpsLearned, "bloodthirst", {
		label = "Bloodthirst", icon = SpellIcon("Bloodthirst"), half = true,
		tooltip = { "Bloodthirst", "Use this learned primary strike in the DPS Leveling role when it is ready, usable and affordable." },
	})
	ui.SettingCheck(dpsLearned, "pummel", {
		label = "Pummel", icon = SpellIcon("Pummel"), half = true,
		tooltip = { "Pummel", "Interrupt a detected enemy cast when Pummel is learned and usable in the current stance." },
	})
	ui.SettingCheck(dpsLearned, "whirlwind", {
		label = "Whirlwind with AoE On", icon = SpellIcon("Whirlwind"), half = true,
		tooltip = { "Whirlwind", "Use learned Whirlwind only with AoE On, enough nearby enemies, the correct stance and sufficient Rage." },
	})

	-- ---------------------------------------------------------- Leveling Burst
	local burst = ui.Card(stack, "LEVELING BURST", "DPS role; requires Burst On at the spell icon", { id="burst", build=DPSLevelingVisible, group="burst" })
	ui.SettingCheck(burst, "recklessSwings", {
		label = "Use Reckless Swings", icon = SpellIcon("Reckless Swings"),
		tooltip = { "Reckless Swings", "When this Fury talent is learned, Burst On can use it in melee above 70% health. It costs 25% of base health and makes the next four attacks generate 5 additional Rage." },
	})
	ui.SettingCheck(burst, "deathWish", {
		label = "Use Death Wish", icon = SpellIcon("Death Wish"), half = true,
		tooltip = { "Death Wish", "Burst On only. Requires the learned spell, a surviving target, the current stance and enough Rage." },
	})
	ui.SettingCheck(burst, "recklessness", {
		label = "Use Recklessness", icon = SpellIcon("Recklessness"), half = true,
		tooltip = { "Recklessness", "Burst On only. Requires the learned spell and a compatible current stance; Leveling does not force a speculative stance swap." },
	})

	-- ------------------------------------------------------------ Tank profile
	local tank = ui.Card(stack, L("TANK_ROTATION"), L("TANK_PROFILE_HELP"), { id="tank", build="leveling", group="damage", levelingTank=true })
	ui.Help(tank, "The Tank leveling role maintains Defensive Stance and uses learned threat, mitigation and interrupt abilities. Thunder Clap and Cleave require AoE On; Heroic Strike remains single-target.")
	ui.SettingCheck(tank, "tankAutoStance", {
		label = "Defensive Stance", icon = SpellIcon("Defensive Stance"), half = true,
		tooltip = { "Defensive Stance", L("TANK_STANCE_HELP") },
	})
	ui.SettingCheck(tank, "tankTaunt", {
		label = "Taunt", icon = SpellIcon("Taunt"), half = true,
		tooltip = { "Taunt", L("TANK_TAUNT_HELP") },
	})
	ui.SettingCheck(tank, "tankAoETaunt", {
		label = "Challenging Shout", icon = SpellIcon("Challenging Shout"), half = true,
		tooltip = { "Challenging Shout", "Requires AoE On and at least three confirmed nearby engaged enemies attacking allies. Enemies already attacking you do not trigger it." },
	})
	ui.SettingCheck(tank, "tankInterrupt", {
		label = "Shield Bash", icon = SpellIcon("Shield Bash"), half = true,
		tooltip = { "Shield Bash", L("TANK_INTERRUPT_HELP") },
	})
	ui.SettingCheck(tank, "tankShieldBlock", {
		label = "Shield Block", icon = SpellIcon("Shield Block"), half = true,
		tooltip = { "Shield Block", L("TANK_BLOCK_HELP") },
	})
	ui.SettingCheck(tank, "tankShieldWall", {
		label = "Shield Wall", icon = SpellIcon("Shield Wall"), half = true,
		tooltip = { "Shield Wall", L("TANK_WALL_HELP") },
	})
	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	ui.SettingCheck(tank, "tankShieldSlam", {
		label = "Shield Slam", icon = SpellIcon("Shield Slam"), half = true,
		tooltip = { "Shield Slam", "Use the learned Protection strike with a shield when ready, usable and affordable." },
	})
	ui.SettingCheck(tank, "tankLastStand", {
		label = "Last Stand", icon = SpellIcon("Last Stand"), half = true,
		tooltip = { "Last Stand", "Use the learned emergency defensive at or below its health slider." },
	})
	ui.SettingCheck(tank, "tankConcussionBlow", {
		label = "Concussion Blow", icon = SpellIcon("Concussion Blow"), half = true,
		tooltip = { "Concussion Blow", "Use the learned stun against a detected cast when Shield Bash is unavailable." },
	})
	ui.SettingCheck(tank, "tankDemo", {
		label = "Demoralizing Shout", icon = SpellIcon("Demoralizing Shout"), half = true,
		tooltip = { "Demoralizing Shout", L("TANK_DEMO_HELP") },
	})
	ui.Divider(tank)
	ui.Slider(tank, {
		label = L("TANK_SUNDER_STACKS"), half = true,
		min = 0, max = 5, step = 1,
		format = function(v) return tostring(v) .. "/5" end,
		get = function() return rotation.TankSetting(ui.Profile(),"tankSunderMaxStacks") end,
		set = function(v) ui.Profile().tankSunderMaxStacks = v end,
		tooltip = { L("TANK_SUNDER_STACKS"), L("TANK_SUNDER_HELP") },
	})
	ui.Slider(tank, {
		label = L("TANK_HEROIC_THRESHOLD"), half = true,
		min = 20, max = 100, step = 5, suffix = " rage",
		get = function() return rotation.TankSetting(ui.Profile(),"tankHeroicDumpRage") end,
		set = function(v) ui.Profile().tankHeroicDumpRage = v end,
		tooltip = { L("TANK_HEROIC_THRESHOLD"), "Minimum Rage before queueing Heroic Strike in Tank mode. Default: 20. Spell cost is also checked; primary attacks and defenses take priority. The selected threshold also applies to protected combat Rage." },
	})
	ui.Slider(tank, {
		label = "Tank Cleave Rage", half = true,
		min = 20, max = 100, step = 5, suffix = " rage",
		get = function() return rotation.TankSetting(ui.Profile(),"tankCleaveDumpRage") end,
		set = function(v) ui.Profile().tankCleaveDumpRage = v end,
		tooltip = { "Tank Cleave Rage", "Minimum Rage for Cleave with AoE On and the configured number of confirmed engaged melee enemies.",
			"Default: 20 Rage. The selected threshold also applies to protected combat Rage. The separate Cleave threshold below applies to DPS." },
	})
	ui.Slider(tank, {
		label = L("SHIELD_WALL_HP"),
		min = 10, max = 80, step = 5, suffix = " % HP",
		get = function() return rotation.TankSetting(ui.Profile(),"tankShieldWallHP") end,
		set = function(v) ui.Profile().tankShieldWallHP = v end,
		tooltip = { L("SHIELD_WALL_HP"), L("SHIELD_WALL_HP_HELP") },
	})
	ui.Slider(tank, {
		label = "Last Stand at player health",
		min = 10, max = 80, step = 5, suffix = " % HP",
		get = function() return rotation.TankSetting(ui.Profile(),"tankLastStandHP") end,
		set = function(v) ui.Profile().tankLastStandHP = v end,
		tooltip = { "Last Stand health", "Use learned Last Stand at or below this player-health threshold. Default: 30%." },
	})
	local shieldInfo = ui.Info(tank, L("SHIELD_UNKNOWN"))
	-- ------------------------------------------------------------ multiple targets
	local aoe = ui.Card(stack, L("MULTI_TARGET"), nil, { id="aoe", group="aoe" })
	ui.Help(aoe,
		"Area attacks require AoE On. Thunder Clap and Cleave follow the selected Leveling role. "
		.. "If enemy count is unreadable, AoE On remains the manual fallback. "
		.. "The Tank role uses its separate Cleave Rage threshold.")
	ui.SettingCheck(aoe, "aoe", {
		label = L("ENABLE_AOE"),
		tooltip = { L("ENABLE_AOE"), L("AOE_HELP"), L("AOE_COMMAND") },
		onChange = ui.Repaint,
	})
	ui.Divider(aoe)
	ui.Help(aoe, L("THUNDER_INFO"),
		{ icon = SpellIcon("Thunder Clap") })
	ui.Help(aoe, L("CLEAVE_INFO"),
		{ icon = SpellIcon("Cleave") })
	ui.Slider(aoe, {
		label = L("MIN_ENEMIES"), half = true,
		min = 2, max = 5, step = 1,
		get = function() return tonumber(ui.Profile().aoeMinEnemies) or 2 end,
		set = function(v) ui.Profile().aoeMinEnemies = v end,
		tooltip = { L("MIN_ENEMIES"), L("MIN_ENEMIES_HELP"), L("ENEMY_FALLBACK") },
	})

	-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
	local dpsAoE = ui.Card(stack, "DPS AREA SETTINGS", "DPS Leveling role only; requires AoE On", { id="dps-aoe", build=DPSLevelingVisible, group="aoe" })
	ui.Help(dpsAoE, L("SWEEPING_INFO"),
		{ icon = SpellIcon("Sweeping Strikes") })
	ui.Help(dpsAoE, "Sweeping Strikes requires Battle Stance and the learned talent. Whirlwind also follows its learned-spell checkbox in DPS Leveling settings.")
	ui.Slider(dpsAoE, {
        profileKey="cleaveDumpRage",
		label = L("CLEAVE_THRESHOLD") .. " (DPS)", half = true,
		min = 20, max = 100, step = 5, suffix = " rage",
		get = function() return tonumber(ui.Profile().cleaveDumpRage) or 60 end,
		set = function(v) ui.Profile().cleaveDumpRage = v end,
		tooltip = { L("CLEAVE_THRESHOLD"), L("CLEAVE_THRESHOLD_HELP"), thresholdHelp },
	})
	ui.Slider(dpsAoE, {
        profileKey="sweepingReserveRage",
		label = L("SWEEPING_RESERVE"),
		min = 30, max = 100, step = 5, suffix = " rage",
		get = function() return tonumber(ui.Profile().sweepingReserveRage) or 50 end,
		set = function(v) ui.Profile().sweepingReserveRage = v end,
		tooltip = { L("SWEEPING_RESERVE_TITLE"), L("SWEEPING_RESERVE_HELP"), thresholdHelp },
	})

	-- --------------------------------------------------- defense / utility
	local utility = ui.Card(stack, L("DEFENSIVE_UTILITY"), L("UTILITY_HELP"), { id="utility", group="survival" })
	ui.SettingCheck(utility, "revenge", {
		label = "Revenge", icon = SpellIcon("Revenge"), half = true,
		tooltip = { "Revenge", L("REVENGE_HELP") },
	})

	-- ------------------------------------------------------------ live state
	local last = {}
	local function SetBadge(key, text, color)
		if last[key] == text then return end
		last[key] = text
		badges[key]:SetBadge(text, color)
	end

	local function PaintLiveStatus()
		local state = (rotation and rotation.GetUIState and ui.State()) or {}
		local profile = ui.Profile()

		SetBadge("level", L("LEVEL") .. " " .. tostring(state.level or "?"), STEEL)

		-- Never invent a Rage value: Forever can make it unreadable.
		if type(state.rage) == "number" then
			SetBadge("rage", "RAGE " .. tostring(state.rage), THEME.gold)
		else
			SetBadge("rage", "RAGE : ?", THEME.warn)
		end

		SetBadge("spells", tostring(state.knownCount or 0) .. " " .. L("SPELLS"):upper(), STEEL)
		local enemyText = type(state.enemyCount7) == "number"
			and (" " .. tostring(state.enemyCount7) .. "@7yd")
			or ""
		SetBadge("aoe",
			(profile.aoe and L("AOE_ON") or L("AOE_OFF")) .. enemyText,
			(type(state.enemyCount7) == "number" and state.enemyCount7 >= 2)
				and THEME.ok
				or (profile.aoe and THEME.ok or THEME.textFaint))
		SetBadge("burst", AL.burst and L("BURST_ON") or L("BURST_OFF"),
			AL.burst and THEME.gold or THEME.textFaint)

		if not rotation then
			SetBadge("state", L("NO_ROTATION"), THEME.danger)
		elseif state.role == "TANK" then
			SetBadge("state", L("ROLE_TANK"), THEME.warn)
		else
			SetBadge("state", L("ROLE_DPS"), THEME.ok)
		end

		if state.hasShield == true then
			shieldInfo:SetText(L("SHIELD_READY"))
		elseif state.hasShield == false then
			shieldInfo:SetText(L("SHIELD_MISSING"))
		else
			shieldInfo:SetText(L("SHIELD_UNKNOWN"))
		end

		rowA:Layout()
		rowB:Layout()

	end

	ui.Paint(PaintLiveStatus)
	PaintLiveStatus()

	-- Lightweight refresh: only while the page is visible, updating
	-- text only, never frames.
	local elapsed = 0
	page:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < 0.20 then return end
		elapsed = 0
		PaintLiveStatus()
	end)
end

if AL.RegisterClassUI then
	AL.RegisterClassUI("WARRIOR", BuildWarriorUI, UI_VERSION)
end
if AL.rotations and AL.rotations.WARRIOR then
	AL.rotations.WARRIOR.uiVersion = UI_VERSION
end
