local ADDON, AL = ...

-- ============================================================================
-- ActionLITE - Class_UI.lua - v0.9.2
-- ----------------------------------------------------------------------------
-- Shared builder for declarative class interfaces.
-- Each <Class>_UI.lua contains only its rotation's structure:
-- cards, options, spells and dropdowns. Controls write
-- directly to the selected profile, which the rotation then reads.
-- ============================================================================

local function Text(value)
	if type(value) ~= "table" then return tostring(value or "") end
	local language = AL.GetUILanguage and AL.GetUILanguage() or "en"
	return value[language] or value.en or value.fr or ""
end

local function SpellMap(rotation)
	local map = {}
	for _, entry in ipairs((rotation and rotation.spells) or {}) do
		map[entry[2]] = entry[1]
	end
	return map
end

local function KnownSpells(rotation)
	local known, total = 0, 0
	for _, entry in ipairs((rotation and rotation.spells) or {}) do
		total = total + 1
		if AL.known and AL.known[entry[2]] then known = known + 1 end
	end
	return known, total
end

-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
-- Shared mutually-exclusive role controls.  Dedicated and declarative class
-- pages both call this helper so the menu, HUD buttons and combat gates always
-- edit the same profile state.
function AL.BuildRotationRoleCard(stack, ui, token)
	if not stack or type(ui) ~= "table" or type(AL.GetRotationMode) ~= "function" then return end
	token = type(token) == "string" and token:upper() or AL.playerClass
	local supported = {}
	for _, mode in ipairs({ "DPS", "HEAL", "TANK" }) do
		if AL.RoleModeSupported(token, mode) then supported[#supported + 1] = mode end
	end
	if #supported == 0 then return end

	local card = ui.Card(stack, "ROTATION ROLE", "Select the behavior used by ActionLITE", {
		id = "rotation-role", group = "status",
	})
	local definitions = {
		DPS = { key = "roleDPS", label = "DPS", icon = "Interface\\Icons\\Ability_DualWield",
			help = "Uses the learned-spell Leveling damage rotation. This is the default selection." },
		HEAL = { key = "roleHeals", label = "Heals", icon = "Interface\\Icons\\Spell_Holy_Heal",
			help = "Enables Healing Rotation in open-world parties of 2-5 players. Dungeons also require WoW to assign you the Healer role. Use focus for healing macros, with mouseover as a manual override." },
		TANK = { key = "roleTank", label = "Tank", icon = "Interface\\Icons\\Ability_Defend",
			help = "Uses the learned Tank priority and permits threat-specific actions such as taunts. It can be selected manually and is selected automatically only from a readable party Tank role." },
	}
	for _, mode in ipairs(supported) do
		local roleMode = mode -- distinct closure value on Lua 5.1
		local def = definitions[roleMode]
		ui.Check(card, {
			profileKey = def.key,
			label = def.label,
			icon = def.icon,
			half = #supported > 1,
			get = function() return AL.GetRotationMode(ui.Profile(), token) == roleMode end,
			set = function(enabled)
				-- One role must remain selected.  Turning off Heal/Tank returns to
				-- DPS; clicking DPS again simply keeps the default selected.
				local selected = enabled and roleMode or "DPS"
				AL.SetRotationMode(selected, true, ui.Profile(), token)
			end,
			onChange = ui.Repaint,
			tooltip = { def.label .. " Rotation", def.help },
		})
	end
	ui.Help(card, "DPS is the default. Before any manual role choice, a readable non-raid party role may automatically select Heals or Tank; leaving that group returns an automatic selection to DPS. A manual choice is saved and remains authoritative.")
	return card
end

local function BuildControl(card, control, ui, spellIDs, rotation)
	if control.type == "slider" then
		return ui.Slider(card, {
			profileKey = control.key,
			label = Text(control.label),
			icon = control.icon,
			min = control.min,
			max = control.max,
			step = control.step or 1,
			suffix = Text(control.suffix),
			half = control.half,
			format = control.format,
			get = function()
				local raw = ui.Profile()[control.key]
                local value = not (issecretvalue and issecretvalue(raw)) and tonumber(raw) or nil
                if not value or value ~= value or value == math.huge or value == -math.huge then value = control.default or control.min end
                return math.max(control.min, math.min(control.max, math.floor(value + 0.5)))
			end,
			set = function(value) ui.Profile()[control.key] = value end,
			tooltip = control.tooltip and {
				Text(control.tooltip[1]), Text(control.tooltip[2]),
			} or nil,
		})
	end

	if control.type == "dropdown" then
		local options = {}
		for i, option in ipairs(control.options or {}) do
			options[i] = { label = Text(option.label), value = option.value }
		end
		return ui.StackDropdown(card, {
			profileKey = control.key,
			caption = Text(control.label),
			options = options,
			get = function()
				local value = ui.Profile()[control.key]
				if not (issecretvalue and issecretvalue(value)) then
                    for _, option in ipairs(control.options or {}) do if value == option.value then return value end end
                end
                return control.default
			end,
			set = function(value) ui.Profile()[control.key] = value end,
			onSelect = ui.Repaint,
			half = control.half,
		})
	end

	if control.type == "info" then
		return (ui.Help or ui.Info)(card, Text(control.text))
	end

	if control.type == "dynamic_info" then
		local row = ui.Info(card, "")
		local elapsed = 0

		local function Refresh()
			local value = ""
			if type(control.getText) == "function" then
				local ok, result = pcall(control.getText)
				if ok then
					value = tostring(result or "")
				else
					value = "unavailable"
				end
			else
				value = Text(control.text)
			end
			row:SetText(value)
		end

		row:SetScript("OnUpdate", function(_, delta)
			elapsed = elapsed + delta
			if elapsed < (control.interval or 0.20) then return end
			elapsed = 0
			Refresh()
		end)

		Refresh()
		return row
	end

	local originalChange = control.onChange
	local changed = originalChange
	for _, key in ipairs(rotation and rotation.buildKeys or {}) do
		if key == control.key then
			changed = function()
				local profile = ui.Profile()
				rotation.SetBuild(key, profile[key] == true, profile)
				if originalChange then originalChange() end
				if ui.Repaint then ui.Repaint() end
			end
			break
		end
	end
	local icon = control.icon
	if not icon and control.spell then
		icon = ui.SpellIcon(control.spell, spellIDs[control.spell])
	end
	return ui.SettingCheck(card, control.key, {
		label = Text(control.label or control.spell or control.key),
		icon = icon,
		half = control.half ~= false,
		onChange = changed,
		tooltip = control.tooltip and {
			Text(control.tooltip[1]), Text(control.tooltip[2]),
		} or nil,
	})
end

function AL.RegisterSimpleClassUI(token, config, version)
	if type(token) ~= "string" or type(config) ~= "table" then return end
	if type(AL.RegisterClassUI) ~= "function" then return end

	AL.RegisterClassUI(token, function(page, ui)
		local rotation = AL.rotations and AL.rotations[token]
		if rotation and rotation.NormalizeBuild then rotation.NormalizeBuild(ui.Profile()) end
		local spellIDs = SpellMap(rotation)
		local stack = ui.Body(page)
		local theme = ui.Theme
		local steel = { 0.72, 0.62, 0.50, 1 }

		local head = ui.Card(stack, Text(config.title), Text(config.subtitle), { id="status", group="status", status=true })
		local rowA = ui.BadgeRow(head, 3)
		local rowB = ui.BadgeRow(head, 2)
		local badges = {
			level = rowA.badges[1],
			spells = rowA.badges[2],
			state = rowA.badges[3],
			aoe = rowB.badges[1],
			burst = rowB.badges[2],
		}
		AL.BuildRotationRoleCard(stack, ui, token)
		for _, cardDef in ipairs(config.cards or {}) do
			-- Pre-launch Bluepost 03NOV2026 Hotfix v1.1.5
			-- A class can retain dormant implementation data while withdrawing a
			-- build from the current release. Only render build-scoped cards when
			-- that build is present in the rotation's public buildKeys list.
			local buildAvailable = cardDef.build == nil
			for _, key in ipairs(rotation and rotation.buildKeys or {}) do
				if key == cardDef.build then
					buildAvailable = true
					break
				elseif type(cardDef.build) == "table" then
					for _, candidate in ipairs(cardDef.build) do
						if key == candidate then buildAvailable = true; break end
					end
					if buildAvailable then break end
				end
			end
			if buildAvailable then
				local card = ui.Card(stack, Text(cardDef.title), Text(cardDef.subtitle), { id=cardDef.id, build=cardDef.build, group=cardDef.group, collapsed=cardDef.collapsed })
				for _, control in ipairs(cardDef.controls or {}) do
					BuildControl(card, control, ui, spellIDs, rotation)
				end
			end
		end


		local last = {}
		local function SetBadge(key, value, color)
			if last[key] == value then return end
			last[key] = value
			badges[key]:SetBadge(value, color)
		end

		local function Paint()
			local profile = ui.Profile()
			local known, total = KnownSpells(rotation)
			local level = UnitLevel and UnitLevel("player") or "?"
			SetBadge("level", AL.L("LEVEL") .. " " .. tostring(level), steel)
			SetBadge("spells", tostring(known) .. "/" .. tostring(total) .. " " .. AL.L("SPELLS"):upper(), steel)
			SetBadge("state", rotation and AL.L("ROTATION_LOADED") or AL.L("NO_ROTATION"),
				rotation and theme.ok or theme.danger)
			if config.aoeKey then
				SetBadge("aoe", profile[config.aoeKey] and AL.L("AOE_ON") or AL.L("AOE_OFF"),
					profile[config.aoeKey] and theme.ok or theme.textFaint)
			else
				SetBadge("aoe", Text({ en = "SINGLE TARGET", fr = "CIBLE UNIQUE", pt = "ALVO ÚNICO", es = "OBJETIVO ÚNICO", de = "EINZELZIEL", zh = "单体目标" }), theme.textFaint)
			end
			SetBadge("burst", AL.burst and AL.L("BURST_ON") or AL.L("BURST_OFF"),
				AL.burst and theme.gold or theme.textFaint)
			rowA:Layout()
			rowB:Layout()
		end

		ui.Paint(Paint)
		Paint()
		local elapsed = 0
		page:SetScript("OnUpdate", function(_, delta)
			elapsed = elapsed + delta
			if elapsed < 0.20 then return end
			elapsed = 0
			Paint()
		end)
	end, version)
end
