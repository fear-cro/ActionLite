local ADDON, AL = ...
local UI_VERSION = "0.10.4"
local L = AL.L

-- ============================================================================
-- ActionLITE - Warrior_UI.lua - v0.10.4
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

	-- --------------------------------------------------------- role selection
	local levelingCard = ui.Card(stack, "LEVELING ROTATION", "Original class rotation", { id="levelingCard", build="leveling", group="damage" })
	ui.Check(levelingCard, {
		profileKey = "leveling", label = "Leveling Rotation", icon = SpellIcon("Heroic Strike"),
		get = function() return ui.Profile().leveling == true end,
		set = function(value) rotation.SetBuild("leveling", value, ui.Profile()) end,
		onChange = ui.Repaint,
		tooltip = { "Leveling Rotation", "Uses the finalized class rotation from before the level-60 sim builds, with its original priorities and existing settings. Select a DPS or Tank build to switch rotations. Turning the active build off automatically selects Leveling Rotation. One rotation always stays selected." },
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
            local profile=ui.Profile()
            rotation.SetBuild("leveling",true,profile)
            profile.warriorRole=value=="TANK" and "TANK" or "DPS"
            profile.levelingWarriorRole=profile.warriorRole
            rotation.NormalizeBuild(profile)
		end,
		onSelect = ui.Repaint,
	})
	ui.Help(role, "Selects the earlier DPS or Tank leveling priority. Choose Protection above for the level-60 talent build.")
	ui.Help(role, "With Leveling Rotation selected, Defensive Stance retains the earlier tank fallback. Explicit DPS or Tank selections take priority.")
	ui.Check(role, {
		profileKey="protection",label="Tank - Protection (0/20/31)",icon=SpellIcon("Shield Slam"),
		get=function() return ui.Profile().protection==true end,
		set=function(value) rotation.SetTankBuild(value,ui.Profile()) end,onChange=ui.Repaint,
		tooltip={"Tank - Protection (0/20/31)","Selects learned Protection priorities and deselects Arms/Fury. Turning it off automatically selects Leveling Rotation. With Leveling Rotation selected, Defensive Stance keeps its earlier tank fallback. Talents and equipment are not changed."},
	})
	local arms = ui.Card(stack, "DPS BUILD - ARMS", "MythicSim default level-60 talents: 39/10/2", { id="arms", build="arms", group="damage" })
	ui.Check(arms, {
		profileKey = "arms", label = "Use Arms (39/10/2)", icon = SpellIcon("Mortal Strike"),
		get = function() return ui.Profile().arms==true end,
		set = function(value) rotation.SetDPSBuild("arms",value,ui.Profile()) end,
		onChange = ui.Repaint,
		tooltip = { "Use Arms", "Selects Arms priorities and deselects Fury. Talents and equipment are not changed. Explicit Arms selection takes priority over the current stance." },
	})
	ui.SettingCheck(arms, "mortalStrike", {
		label = "Use Mortal Strike", icon = SpellIcon("Mortal Strike"), half = true,
		tooltip = { "Mortal Strike", "Uses the learned rank when ready, in range and affordable. Available from level 40 with the actual Arms talent." },
	})
	ui.SettingCheck(arms, "armsAutoStance", {
		label = "Automatic Arms stance", icon = SpellIcon("Battle Stance"), half = true,
		tooltip = { "Automatic Arms stance", "Prefers Battle Stance for Rend, Overpower and Spearing Strike. May enter Berserker Stance for Execute or enabled Burst Recklessness at 25 Rage or below. With Leveling Rotation selected, Defensive Stance retains the earlier tank fallback." },
	})
	ui.SettingCheck(arms, "armsHamstringFiller", {
		label = "Arms: Hamstring damage filler", icon = SpellIcon("Hamstring"), half = false,
		tooltip = { "Hamstring damage filler", "Optional repeated damage filler when Mortal Strike and Slam are unavailable for more than one second. Separate from Maintain Hamstring: the existing macro still controls only target-slow upkeep." },
	})
	ui.SettingCheck(arms, "armsInterrupt", {
		label = "Arms interrupts", icon = SpellIcon("Pummel"), half = true,
		tooltip = { "Arms interrupts", "Pummel in Berserker Stance, or Shield Bash in Battle Stance with a shield. Requires a casting target, learned spell, range and Rage. Does not automatically swap weapons." },
	})
	ui.Slider(arms, {
		label = "Arms filler minimum Rage", min = 15, max = 100, step = 5, suffix = " rage", half = true,
		get = function() return tonumber(ui.Profile().armsFillerReserveRage) or 20 end,
		set = function(value) ui.Profile().armsFillerReserveRage=value end,
		tooltip = { "Arms filler minimum Rage", "Minimum Rage for Spearing Strike and optional damage-filler Hamstring between primary attacks. Default: 20. Actual costs are also checked." },
	})
	ui.Help(arms, "Rend supports Bloodthrill's Overpower opportunities. Improved Slam and Mortal Strike are the normal attacks; Spearing Strike fills verified gaps on any creature type. Shared DPS sliders below save separate Arms choices for Sunder, Slam, Heroic Strike and Cleave.")
	ui.Help(arms, "Arms area attacks require AoE On and the selected number of confirmed engaged melee enemies. Hamstring damage filler defaults OFF; Maintain Hamstring and /alhamstring keep their existing target-slow behavior.")
	local armsBurst = ui.Card(stack, "ARMS BURST", "Requires Burst On at the spell icon", { id="armsBurst", build="arms", group="burst" })
	for _,entry in ipairs({{"armsRecklessness","Recklessness"},{"armsBloodFury","Blood Fury"},{"armsBerserking","Berserking"}}) do
		ui.SettingCheck(armsBurst,entry[1],{
			label="Use "..entry[2],icon=SpellIcon(entry[2]),half=true,
			tooltip={entry[2],"Arms Burst On only, when actually learned, permitted, ready and affordable. Recklessness requires Berserker Stance and also increases damage taken. The default Human build has no active damage racial."},
		})
	end
	ui.Slider(armsBurst, {
		label = "Arms Burst minimum target health", min = 0, max = 100, step = 5, suffix = " %", half = true,
		get = function() return rotation.ArmsBurstMinimum(ui.Profile()) end,
		set = function(value) ui.Profile().armsBurstMinTargetHP=value end,
		tooltip = { "Arms Burst minimum target health", "Minimum target health for enabled Arms Burst spells. Default: 35%. Zero removes this limit. Normal damage continues with Burst Off." },
	})
	local fury = ui.Card(stack, "FURY DAMAGE", "MythicSim default level-60 talents: 18/31/2", { id="fury", build="fury", group="damage" })
	ui.Check(fury, {
		profileKey="fury",label = "Use Fury", icon = SpellIcon("Bloodthirst"),
		get=function()return ui.Profile().fury==true end,
		set=function(value)rotation.SetDPSBuild("fury",value,ui.Profile())end,
		tooltip = { "Use Fury", "Selects learned Fury priorities and deselects Arms. Talents and equipment are not changed. Select Leveling Rotation to use the existing DPS priority." },
		onChange = ui.Repaint,
	})
	ui.SettingCheck(fury, "bloodthirst", {
		label = "Use Bloodthirst", icon = SpellIcon("Bloodthirst"), half = true,
		tooltip = { "Bloodthirst", "Main Fury strike when learned, in range, ready and affordable." },
	})
	ui.SettingCheck(fury, "furyAutoStance", {
		label = "Automatic Fury stance", icon = SpellIcon("Berserker Stance"), half = true,
		tooltip = { "Automatic Fury stance", "Uses Berserker Stance when Bloodthirst is learned, or for learned Whirlwind with AoE On. The selected Fury build takes priority over the current stance." },
	})
	ui.SettingCheck(fury, "furyOverpowerDance", {
		label = "Overpower stance switch", icon = SpellIcon("Overpower"), half = true,
		tooltip = { "Overpower stance switch", "Temporarily selects Battle Stance only for a readable Overpower proc at 50 Rage or below, then returns to Berserker Stance. Requires automatic stance and the Overpower checkbox. Unreadable procs do not trigger a switch." },
	})
	ui.SettingCheck(fury, "furyInterrupt", {
		label = "Use Pummel", icon = SpellIcon("Pummel"), half = true,
		tooltip = { "Pummel", "Interrupts a casting target in melee while in Berserker Stance, when learned and ready." },
	})
	ui.SettingCheck(fury, "furyBerserkerRage", {
		label = "Use Berserker Rage", icon = SpellIcon("Berserker Rage"), half = true,
		tooltip = { "Berserker Rage", "Normal combat utility for damage-taken Rage and fear immunity after damage priorities. Requires the learned spell and Berserker Stance." },
	})
	ui.SettingCheck(fury, "furyIntercept", {
		label = "Use Intercept", icon = SpellIcon("Intercept"), half = true,
		tooltip = { "Intercept", "Combat gap closer in Berserker Stance. Requires a learned spell, positively verified range, enough Rage and a ready cooldown." },
	})
	ui.Help(fury, "Area attacks require AoE On. Death Wish and Recklessness require Burst On and their individual checkboxes. Only learned and enabled spells are used.")

	local burst = ui.Card(stack, "FURY BURST", "Requires Burst On at the spell icon", { id="burst", build="fury", group="burst" })
	ui.SettingCheck(burst, "furyDeathWish", {
		label = "Use Death Wish", icon = SpellIcon("Death Wish"), half = true,
		tooltip = { "Death Wish", "Fury Burst On only: physical damage boost when learned, ready and affordable. Costs 10 Rage; three-minute cooldown. Also increases damage taken." },
	})
	ui.SettingCheck(burst, "furyRecklessness", {
		label = "Use Recklessness", icon = SpellIcon("Recklessness"), half = true,
		tooltip = { "Recklessness", "Fury Burst On only: critical-strike boost in Berserker Stance when learned and ready. Uses Automatic Fury stance when enabled. Thirty-minute cooldown; also increases damage taken." },
	})
	ui.Slider(burst, {
		label = "Burst minimum target health", half = true,
		min = 0, max = 100, step = 5, suffix = " %",
		get = function()
			return rotation and rotation.FuryBurstMinimum and rotation.FuryBurstMinimum(ui.Profile()) or 35
		end,
		set = function(value) ui.Profile().furyBurstMinTargetHP = value end,
		tooltip = { "Burst minimum target health", "Activates Death Wish, Recklessness and learned offensive racials only when target health is at or above this percentage. Default: 35%. Zero removes the health limit." },
	})

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
		profileKey = "slam",
		label = L("SLAM_LABEL"), icon = SpellIcon("Slam"), half = true,
		get = function()
			local p = ui.Profile()
			if p.arms==true then return p.armsSlam==true end
			if rotation and rotation.FuryUsesTalentSettings(p) then return p.furySlam == true end
			return p.slam == true
		end,
		set = function(value)
			local p = ui.Profile()
			if p.arms==true then p.armsSlam=value
			elseif rotation and rotation.FuryUsesTalentSettings(p) then p.furySlam = value else p.slam = value end
		end,
		onChange = ui.Repaint,
		tooltip = { "Slam", L("SLAM_HELP"), "After Bloodthirst is learned, Fury defaults Slam OFF for the 18/31/2 reference. This checkbox saves a separate Fury choice and preserves the earlier leveling DPS choice." },
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
		get = function() local p=ui.Profile();return p.arms==true and (tonumber(p.armsSunderMaxStacks) or 1) or (tonumber(p.sunderMaxStacks) or 2) end,
		set = function(v) local p=ui.Profile();if p.arms==true then p.armsSunderMaxStacks=v else p.sunderMaxStacks=v end end,
		tooltip = {
			L("SUNDER_LIMIT"), L("SUNDER_ZERO"), L("SUNDER_ONE_FIVE"),
		},
	})
	ui.Slider(core, {
        profileKey="slamReserveRage",
		label = L("SLAM_RESERVE"), half = true,
		min = 15, max = 100, step = 5, suffix = " rage",
		get = function()local p=ui.Profile();return p.arms==true and (tonumber(p.armsSlamReserveRage) or 15) or (tonumber(p.slamReserveRage) or 30) end,
		set = function(v)local p=ui.Profile();if p.arms==true then p.armsSlamReserveRage=v else p.slamReserveRage=v end end,
		tooltip = { L("SLAM_RESERVE"), L("SLAM_RESERVE_HELP"), thresholdHelp },
	})

	-- ------------------------------------------------------ procs & finishers
	local procs = ui.Card(stack, L("PROCS_FINISHERS"), nil, { id="procs", group="damage" })
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
	ui.Slider(rage, {
        profileKey="heroicDumpRage",
		label = L("HEROIC_THRESHOLD") .. " (DPS)",
		min = 15, max = 100, step = 5, suffix = " rage",
		get = function()
			if ui.Profile().arms==true then return tonumber(ui.Profile().armsHeroicDumpRage) or 80 end
			local configured = tonumber(ui.Profile().heroicDumpRage)
			if configured then return configured end
			local state = (rotation and rotation.GetUIState and ui.State()) or {}
			return state.heroicDumpAt or 75
		end,
		set = function(v)local p=ui.Profile();if p.arms==true then p.armsHeroicDumpRage=v else p.heroicDumpRage=v end end,
		tooltip = {
			L("HEROIC_THRESHOLD_TITLE"), L("HEROIC_THRESHOLD_HELP"),
			L("HEROIC_AUTO"), thresholdHelp,
		},
	})

	-- ------------------------------------------------------------ Tank profile
	local tank = ui.Card(stack, L("TANK_ROTATION"), L("TANK_PROFILE_HELP"), { id="tank", build={"leveling","protection"}, group="damage", levelingTank=true })
	ui.Help(tank, "Protection and the Defensive Stance leveling rotation use the Tank Heroic Strike and Protection Cleave Rage thresholds below. DPS reserves are separate.")
	ui.Help(tank,"Standard 0/20/31: Shield Slam and usable Revenge lead the damage rotation. Shield Block, emergency defenses and interrupts take priority. Rend, Heroic Strike and Sunder retain their existing checkboxes. Thunder Clap and Cleave require AoE On and the configured number of confirmed engaged melee enemies.")
	ui.SettingCheck(tank,"tankShieldSlam",{
		label="Use Shield Slam",icon=SpellIcon("Shield Slam"),half=true,
		tooltip={"Shield Slam","Primary Protection strike when the actual talent is learned, a shield is equipped, the target is in melee and its cost/cooldown permit it. Available from level 40."},
	})
	ui.SettingCheck(tank,"tankConcussionBlow",{
		label="Concussion Blow fallback",icon=SpellIcon("Concussion Blow"),half=true,
		tooltip={"Concussion Blow","Requires Tank interrupts. Uses the learned stun against a casting non-boss target when Shield Bash cannot be used. Some enemies are immune; the spell also remains available for manual queueing."},
	})
	ui.SettingCheck(tank,"tankLastStand",{
		label="Use Last Stand",icon=SpellIcon("Last Stand"),half=true,
		tooltip={"Last Stand","Emergency maximum-health increase at or below its health slider, independent of Burst. Avoids automatically stacking it during a confirmed Shield Wall."},
	})
	ui.Slider(tank,{
		label="Last Stand health",min=10,max=80,step=5,suffix=" % HP",half=true,
		get=function() return rotation.TankSetting(ui.Profile(),"tankLastStandHP") end,
		set=function(v) ui.Profile().tankLastStandHP=v end,
		tooltip={"Last Stand health","Cast at or below this percentage while in combat. Default: 25%. Also supports protected combat health."},
	})
	ui.SettingCheck(tank,"tankThunderClap",{
		label="Tank AoE: Thunder Clap",icon=SpellIcon("Thunder Clap"),half=true,
		tooltip={"Tank Thunder Clap","Requires AoE On and enough confirmed engaged melee enemies. Never leaves Defensive Stance to force a DPS area spell."},
	})
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
		label = "Protection Cleave Rage", half = true,
		min = 20, max = 100, step = 5, suffix = " rage",
		get = function() return rotation.TankSetting(ui.Profile(),"tankCleaveDumpRage") end,
		set = function(v) ui.Profile().tankCleaveDumpRage = v end,
		tooltip = { "Protection Cleave Rage", "Minimum Rage for Cleave with AoE On and the configured number of confirmed engaged melee enemies.",
			"Default: 20 Rage. The selected threshold also applies to protected combat Rage. The separate Cleave threshold below applies to DPS." },
	})
	ui.Slider(tank, {
		label = L("SHIELD_WALL_HP"),
		min = 10, max = 80, step = 5, suffix = " % HP",
		get = function() return rotation.TankSetting(ui.Profile(),"tankShieldWallHP") end,
		set = function(v) ui.Profile().tankShieldWallHP = v end,
		tooltip = { L("SHIELD_WALL_HP"), L("SHIELD_WALL_HP_HELP") },
	})
	local shieldInfo = ui.Info(tank, L("SHIELD_UNKNOWN"))
	local tankBurst=ui.Card(stack,"PROTECTION BURST","Requires Burst On at the spell icon", { id="tankBurst", build="protection", group="burst" })
	ui.SettingCheck(tankBurst,"tankBloodFury",{
		label="Use Blood Fury",icon=SpellIcon("Blood Fury"),half=true,
		tooltip={"Protection Blood Fury","Burst On only, if this racial is actually learned. Defaults OFF because it reduces healing received. Defensive cooldowns remain independent of Burst."},
	})
	ui.SettingCheck(tankBurst,"tankBerserking",{
		label="Use Berserking",icon=SpellIcon("Berserking"),half=true,
		tooltip={"Protection Berserking","Burst On only, when the racial is actually learned and ready. The reference Undead build has neither damage racial."},
	})
	ui.Slider(tankBurst,{
		label="Protection Burst minimum target health",min=0,max=100,step=5,suffix=" %",
		get=function() return rotation.TankSetting(ui.Profile(),"tankBurstMinTargetHP") end,
		set=function(v) ui.Profile().tankBurstMinTargetHP=v end,
		tooltip={"Protection Burst minimum target health","Minimum target health for enabled damage racials. Default: 35%. Zero removes this limit."},
	})
	ui.Help(tankBurst,"Protection stays in Defensive Stance. Recklessness and Retaliation remain available in the Spells list for manual use; this tank rotation does not automatically change stance to activate them.")

	-- ------------------------------------------------------------ multiple targets
	local aoe = ui.Card(stack, L("MULTI_TARGET"), nil, { id="aoe", group="aoe" })
	ui.Help(aoe,
		"Fury area attacks require AoE On and the enemy-count setting. "
		.. "Whirlwind requires Berserker Stance; Sweeping Strikes and Thunder Clap use Battle Stance. "
		.. "Cleave replaces Heroic Strike in the Fury AoE branch after primary strikes. "
		.. "If the enemy count cannot be read, AoE On remains the manual fallback. "
		.. "Protection uses its own Cleave Rage threshold in the Tank Rotation card.")
	ui.SettingCheck(aoe, "aoe", {
		label = L("ENABLE_AOE"),
		tooltip = { L("ENABLE_AOE"), L("AOE_HELP"), L("AOE_COMMAND") },
		onChange = ui.Repaint,
	})
	ui.Divider(aoe)
	ui.SettingCheck(aoe, "whirlwind", {
		label = "Use Whirlwind", icon = SpellIcon("Whirlwind"),
		tooltip = { "Whirlwind", "Fury AoE only: requires AoE On, learned Whirlwind, Berserker Stance, range, enough Rage and a ready cooldown." },
	})
	ui.Help(aoe, L("SWEEPING_INFO"),
		{ icon = SpellIcon("Sweeping Strikes") })
	ui.Help(aoe, "Sweeping Strikes requires Battle Stance and the learned talent.")
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
	ui.Slider(aoe, {
        profileKey="cleaveDumpRage",
		label = L("CLEAVE_THRESHOLD") .. " (DPS)", half = true,
		min = 20, max = 100, step = 5, suffix = " rage",
		get = function()
			local p = ui.Profile()
			if p.arms==true then return tonumber(p.armsCleaveDumpRage) or 80 end
			return p.fury == true and (tonumber(p.furyCleaveDumpRage) or 40) or (tonumber(p.cleaveDumpRage) or 60)
		end,
		set = function(v)
			local p = ui.Profile()
			if p.arms==true then p.armsCleaveDumpRage=v
			elseif p.fury == true then p.furyCleaveDumpRage = v else p.cleaveDumpRage = v end
		end,
		tooltip = { L("CLEAVE_THRESHOLD"), L("CLEAVE_THRESHOLD_HELP"), thresholdHelp },
	})
	ui.Slider(aoe, {
        profileKey="sweepingReserveRage",
		label = L("SWEEPING_RESERVE"),
		min = 30, max = 100, step = 5, suffix = " rage",
		get = function() return tonumber(ui.Profile().sweepingReserveRage) or 50 end,
		set = function(v) ui.Profile().sweepingReserveRage = v end,
		tooltip = { L("SWEEPING_RESERVE_TITLE"), L("SWEEPING_RESERVE_HELP"), thresholdHelp },
	})

	-- --------------------------------------------------- defense / utility
	local utility = ui.Card(stack, L("DEFENSIVE_UTILITY"), L("UTILITY_HELP"), { id="utility", group="survival" })
	ui.SettingCheck(utility, "demo", {
		label = "Demoralizing Shout", icon = SpellIcon("Demoralizing Shout"), half = true,
		tooltip = { "Demoralizing Shout", L("DEMO_HELP") },
	})
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
