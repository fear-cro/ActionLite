local ADDON, AL = ...
local UI_VERSION = "0.7.11"
local L = AL.L

-- ============================================================================
-- ActionLITE - Warrior_UI.lua - v0.7.11
-- ----------------------------------------------------------------------------
-- Page d'options du Guerrier, disposition dense a deux colonnes.
-- Aucune regle de combat ici : toutes les valeurs affichees proviennent de
-- rotation\Warrior.lua via M.GetUIState(), de sorte que l'interface ne peut
-- jamais diverger de la rotation.
--
-- La page est construite une seule fois. Les mises a jour en direct ne font que
-- reecrire des textes de pastilles, jamais reconstruire des frames.
--
-- Convention de cette page : toute option passee avec half = true occupe une
-- demi-largeur et se met en paire avec la suivante. Le libelle reste court, le
-- detail part dans l'infobulle.
-- ============================================================================

local function BuildWarriorUI(page, ui)
	local rotation = AL.rotations and AL.rotations.WARRIOR
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

	local STEEL = { 0.72, 0.62, 0.50, 1 }

	-- --------------------------------------------------------- choix du role
	local role = ui.Card(stack, L("WARRIOR_ROLE"), L("WARRIOR_ROLE_HELP"))
	ui.StackDropdown(role, {
		caption = L("ACTIVE_ROTATION"),
		options = {
			{ label = L("ROLE_DPS"), value = "DPS" },
			{ label = L("ROLE_TANK"), value = "TANK" },
		},
		get = function()
			return ui.Profile().warriorRole == "TANK" and "TANK" or "DPS"
		end,
		set = function(value)
			ui.Profile().warriorRole = value == "TANK" and "TANK" or "DPS"
		end,
		onSelect = ui.Repaint,
	})
	ui.Info(role, L("ROLE_SWITCH_HELP"))
	ui.Info(role, "Defensive Stance automatically activates the Protection rotation.")

	-- ---------------------------------------------------------------- en-tete
	local head = ui.Card(stack, L("LIVE_STATUS"), L("WARRIOR_PROFILE", UI_VERSION))

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

	ui.Info(head, L("RAGE_PROTECTED"),
		{ height = 28, justify = "CENTER" })

	-- ------------------------------------------------------- rotation de base
	local core = ui.Card(stack, L("MAIN_ROTATION"))
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
	ui.SettingCheck(core, "slam", {
		label = L("SLAM_LABEL"), icon = SpellIcon("Slam"), half = true,
		tooltip = { "Slam", L("SLAM_HELP") },
	})
	ui.SettingCheck(core, "spear", {
		label = "Spearing Strike", icon = SpellIcon("Spearing Strike"), half = true,
		tooltip = { "Spearing Strike", L("SPEAR_HELP") },
	})
	ui.Check(core, {
		label = "Hamstring", icon = SpellIcon("Hamstring"), half = true,
		get = function() return ui.Profile().hamstring == true end,
		set = function(value) rotation.SetHamstring(value, ui.Profile()) end,
		tooltip = { "Hamstring", "Keep Hamstring applied to your current hostile target in combat when usable in your stance.",
			"Reapply only when missing or expired. Toggle macro: /alhamstring" },
	})
	ui.Divider(core)
	ui.Slider(core, {
		label = L("SUNDER_STACKS"), half = true,
		min = 0, max = 5, step = 1,
		format = function(v) return tostring(v) .. "/5" end,
		get = function() return tonumber(ui.Profile().sunderMaxStacks) or 2 end,
		set = function(v) ui.Profile().sunderMaxStacks = v end,
		tooltip = {
			L("SUNDER_LIMIT"), L("SUNDER_ZERO"), L("SUNDER_ONE_FIVE"),
		},
	})
	ui.Slider(core, {
		label = L("SLAM_RESERVE"), half = true,
		min = 15, max = 100, step = 5, suffix = " rage",
		get = function() return tonumber(ui.Profile().slamReserveRage) or 30 end,
		set = function(v) ui.Profile().slamReserveRage = v end,
		tooltip = { L("SLAM_RESERVE"), L("SLAM_RESERVE_HELP"), L("RAGE_FALLBACK") },
	})

	-- ------------------------------------------------------ procs & finishers
	local procs = ui.Card(stack, L("PROCS_FINISHERS"))
	ui.SettingCheck(procs, "overpower", {
		label = "Overpower", icon = SpellIcon("Overpower"), half = true,
		tooltip = { "Overpower", L("OVERPOWER_HELP") },
	})
	ui.SettingCheck(procs, "victory", {
		label = "Victory Rush", icon = SpellIcon("Victory Rush"), half = true,
		tooltip = { "Victory Rush", L("VICTORY_HELP") },
	})
	ui.SettingCheck(procs, "execute", {
		label = "Execute", icon = SpellIcon("Execute"), half = true,
		tooltip = { "Execute", L("EXECUTE_HELP") },
	})

	-- ------------------------------------------------------- gestion de rage
	local rage = ui.Card(stack, L("RAGE_MANAGEMENT"))
	ui.SettingCheck(rage, "bloodrage", {
		label = "Bloodrage", icon = SpellIcon("Bloodrage"), half = true,
		tooltip = { "Bloodrage", L("BLOODRAGE_HELP") },
	})
	ui.SettingCheck(rage, "heroic", {
		label = "Heroic Strike", icon = SpellIcon("Heroic Strike"), half = true,
		tooltip = { "Heroic Strike", L("HEROIC_HELP") },
	})
	ui.Slider(rage, {
		label = L("HEROIC_THRESHOLD"),
		min = 15, max = 100, step = 5, suffix = " rage",
		get = function()
			local configured = tonumber(ui.Profile().heroicDumpRage)
			if configured then return configured end
			local state = (rotation and rotation.GetUIState and rotation.GetUIState()) or {}
			return state.heroicDumpAt or 75
		end,
		set = function(v) ui.Profile().heroicDumpRage = v end,
		tooltip = {
			L("HEROIC_THRESHOLD_TITLE"), L("HEROIC_THRESHOLD_HELP"),
			L("HEROIC_AUTO"), L("RAGE_FALLBACK"),
		},
	})

	-- ------------------------------------------------------------ profil Tank
	local tank = ui.Card(stack, L("TANK_ROTATION"), L("TANK_PROFILE_HELP"))
	ui.Info(tank, "Use Rend and Heroic Strike on one target, and Cleave on 2+ engaged enemies. "
		.. "Rend and Heroic Strike follow their Main Rotation/Rage Management checkboxes. "
		.. "Defensive abilities and Thunder Clap retain priority over queued strikes.")
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
		tooltip = { "Challenging Shout", L("TANK_AOE_TAUNT_HELP") },
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
	ui.SettingCheck(tank, "tankDemo", {
		label = "Demoralizing Shout", icon = SpellIcon("Demoralizing Shout"), half = true,
		tooltip = { "Demoralizing Shout", L("TANK_DEMO_HELP") },
	})
	ui.Divider(tank)
	ui.Slider(tank, {
		label = L("TANK_SUNDER_STACKS"), half = true,
		min = 0, max = 5, step = 1,
		format = function(v) return tostring(v) .. "/5" end,
		get = function() return tonumber(ui.Profile().tankSunderMaxStacks) or 5 end,
		set = function(v) ui.Profile().tankSunderMaxStacks = v end,
		tooltip = { L("TANK_SUNDER_STACKS"), L("TANK_SUNDER_HELP") },
	})
	ui.Slider(tank, {
		label = L("TANK_HEROIC_THRESHOLD"), half = true,
		min = 20, max = 100, step = 5, suffix = " rage",
		get = function() return tonumber(ui.Profile().tankHeroicDumpRage) or 20 end,
		set = function(v) ui.Profile().tankHeroicDumpRage = v end,
		tooltip = { L("TANK_HEROIC_THRESHOLD"), L("TANK_HEROIC_HELP"), L("RAGE_FALLBACK") },
	})
	ui.Slider(tank, {
		label = "Protection Cleave Rage", half = true,
		min = 20, max = 100, step = 5, suffix = " rage",
		get = function() return tonumber(ui.Profile().tankCleaveDumpRage) or 20 end,
		set = function(v) ui.Profile().tankCleaveDumpRage = v end,
		tooltip = { "Protection Cleave Rage", "Minimum Rage for Cleave against 2+ engaged enemies in the Protection rotation.",
			"Default: 20 Rage. The separate Cleave threshold below applies to DPS.", L("RAGE_FALLBACK") },
	})
	ui.Slider(tank, {
		label = L("SHIELD_WALL_HP"),
		min = 10, max = 80, step = 5, suffix = " % HP",
		get = function() return tonumber(ui.Profile().tankShieldWallHP) or 35 end,
		set = function(v) ui.Profile().tankShieldWallHP = v end,
		tooltip = { L("SHIELD_WALL_HP"), L("SHIELD_WALL_HP_HELP") },
	})
	local shieldInfo = ui.Info(tank, L("SHIELD_UNKNOWN"))

	-- ------------------------------------------------------------ multi-cible
	local aoe = ui.Card(stack, L("MULTI_TARGET"))
	ui.Info(aoe,
		"Cleave automatically detects 2+ engaged enemies within melee range "
		.. "(conservatively inside the 7 yd target). Cleave has priority over "
		.. "Heroic Strike and Rage will be reserved for Cleave when needed. "
		.. "Enabled AoE prioritizes Sweeping Strikes, Thunder Clap and Cleave over Heroic Strike. "
		.. "Protection uses its own Cleave Rage threshold in the Tank Rotation card.")
	ui.SettingCheck(aoe, "aoe", {
		label = L("ENABLE_AOE"),
		tooltip = { L("ENABLE_AOE"), L("AOE_HELP"), L("AOE_COMMAND") },
		onChange = ui.Repaint,
	})
	ui.Divider(aoe)
	ui.Info(aoe, L("SWEEPING_INFO"),
		{ icon = SpellIcon("Sweeping Strikes") })
	ui.Info(aoe, "Sweeping Strikes requires Battle Stance and the learned talent.")
	ui.Info(aoe, L("THUNDER_INFO"),
		{ icon = SpellIcon("Thunder Clap") })
	ui.Info(aoe, L("CLEAVE_INFO"),
		{ icon = SpellIcon("Cleave") })
	ui.Slider(aoe, {
		label = L("MIN_ENEMIES"), half = true,
		min = 2, max = 5, step = 1,
		get = function() return tonumber(ui.Profile().aoeMinEnemies) or 2 end,
		set = function(v) ui.Profile().aoeMinEnemies = v end,
		tooltip = { L("MIN_ENEMIES"), L("MIN_ENEMIES_HELP"), L("ENEMY_FALLBACK") },
	})
	ui.Slider(aoe, {
		label = L("CLEAVE_THRESHOLD"), half = true,
		min = 20, max = 100, step = 5, suffix = " rage",
		get = function() return tonumber(ui.Profile().cleaveDumpRage) or 60 end,
		set = function(v) ui.Profile().cleaveDumpRage = v end,
		tooltip = { L("CLEAVE_THRESHOLD"), L("CLEAVE_THRESHOLD_HELP"), L("RAGE_FALLBACK") },
	})
	ui.Slider(aoe, {
		label = L("SWEEPING_RESERVE"),
		min = 30, max = 100, step = 5, suffix = " rage",
		get = function() return tonumber(ui.Profile().sweepingReserveRage) or 50 end,
		set = function(v) ui.Profile().sweepingReserveRage = v end,
		tooltip = { L("SWEEPING_RESERVE_TITLE"), L("SWEEPING_RESERVE_HELP"), L("RAGE_FALLBACK") },
	})

	-- --------------------------------------------------- defensif / utilitaire
	local utility = ui.Card(stack, L("DEFENSIVE_UTILITY"), L("UTILITY_HELP"))
	ui.SettingCheck(utility, "demo", {
		label = "Demoralizing Shout", icon = SpellIcon("Demoralizing Shout"), half = true,
		tooltip = { "Demoralizing Shout", L("DEMO_HELP") },
	})
	ui.SettingCheck(utility, "revenge", {
		label = "Revenge", icon = SpellIcon("Revenge"), half = true,
		tooltip = { "Revenge", L("REVENGE_HELP") },
	})

	-- ------------------------------------------------------------ etat direct
	local last = {}
	local function SetBadge(key, text, color)
		if last[key] == text then return end
		last[key] = text
		badges[key]:SetBadge(text, color)
	end

	local function PaintLiveStatus()
		local state = (rotation and rotation.GetUIState and rotation.GetUIState()) or {}
		local profile = ui.Profile()

		SetBadge("level", L("LEVEL") .. " " .. tostring(state.level or "?"), STEEL)

		-- Ne jamais inventer une valeur de rage : Forever peut la rendre illisible.
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

	-- Rafraichissement leger : uniquement lorsque la page est visible, et
	-- uniquement des textes, jamais des frames.
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
